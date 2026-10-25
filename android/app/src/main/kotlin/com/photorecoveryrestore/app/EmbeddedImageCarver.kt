package com.photorecoveryrestore.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.UUID
import java.util.zip.CRC32

/** Bounded file-level JPEG/PNG/WebP carving; never scans raw devices. */
class EmbeddedImageCarver(private val context: Context) {
    private val inspector = ImageSignatureInspector(context.contentResolver)
    data class Carved(
        val file: File,
        val container: File,
        val offset: Long,
        val format: String,
        val mimeType: String,
        val width: Int,
        val height: Int,
        val newlyExtracted: Boolean,
    )

    data class Page(
        val items: List<Carved>,
        val nextOffset: Long?,
        val storageLimitReached: Boolean = false,
        val storageExhausted: Boolean = false,
        val readFailure: Boolean = false,
    )

    private var retainedBytes: Long? = null

    /**
     * Streams one bounded page from an accessible container. The next offset
     * resumes at the same container on a later traversal page, so large cache
     * databases are never rejected or loaded as one buffer.
     */
    fun carvePage(
        container: File,
        startOffset: Long,
        limit: Int,
        cancelled: () -> Boolean,
    ): Page {
        if (limit <= 0) return Page(emptyList(), null)
        if (!container.isFile || !container.canRead()) {
            return Page(emptyList(), null, readFailure = true)
        }
        if (container.length() <= 12) {
            return Page(emptyList(), null)
        }
        val output = mutableListOf<Carved>()
        var storageLimitReached = false
        var storageExhausted = false
        var signaturesInspected = 0
        return try {
          RandomAccessFile(container, "r").use { input ->
            val buffer = ByteArray(CHUNK_BYTES + OVERLAP_BYTES)
            var cursor = startOffset.coerceIn(0, input.length())
            val pageEnd = (cursor + MAX_SCAN_BYTES_PER_PAGE).coerceAtMost(input.length())
            while (cursor < pageEnd && output.size < limit && !cancelled()) {
                input.seek(cursor)
                val read = input.read(buffer, 0, minOf(
                    buffer.size.toLong(), input.length() - cursor,
                ).toInt())
                if (read < MIN_SIGNATURE_BYTES) {
                    cursor = input.length()
                    break
                }
                val inspectCount = minOf(
                    CHUNK_BYTES.toLong(), pageEnd - cursor, (read - MIN_SIGNATURE_BYTES + 1).toLong(),
                ).toInt()
                var consumed = 0
                for (index in 0 until inspectCount) {
                    consumed = index + 1
                    if (cancelled()) break
                    val format = when {
                        u(buffer[index]) == 0xff && u(buffer[index + 1]) == 0xd8 &&
                            u(buffer[index + 2]) == 0xff -> "jpeg"
                        PNG.indices.all { buffer[index + it] == PNG[it] } -> "png"
                        ascii(buffer, index, 4) == "RIFF" &&
                            ascii(buffer, index + 8, 4) == "WEBP" -> "webp"
                        else -> null
                    } ?: continue
                    if (signaturesInspected >= MAX_SIGNATURES_PER_PAGE) {
                        consumed = index
                        break
                    }
                    signaturesInspected++
                    val offset = cursor + index
                    val length = runCatching {
                        payloadLength(container, offset, format)
                    }.getOrNull() ?: continue
                    if (length <= 0 || length > MAX_PAYLOAD_BYTES) continue
                    val remainingBudget = (MAX_RETAINED_BYTES - retainedPayloadBytes())
                        .coerceAtLeast(0L)
                    if (length > remainingBudget) {
                        storageLimitReached = true
                        if (remainingBudget < MIN_STANDALONE_PAYLOAD_BYTES) {
                            storageExhausted = true
                            break
                        }
                        continue
                    }
                    extract(container, offset, length, format, cancelled)?.let { output += it }
                    if (output.size >= limit || signaturesInspected >= MAX_SIGNATURES_PER_PAGE) break
                }
                cursor += consumed.coerceAtLeast(1)
                if (storageExhausted || cancelled() ||
                    signaturesInspected >= MAX_SIGNATURES_PER_PAGE) break
            }
            Page(
                output,
                cursor.takeIf { !storageExhausted && !cancelled() && it < input.length() },
                storageLimitReached,
                storageExhausted,
            )
          }
        } catch (_: Exception) {
            Page(output, null, storageLimitReached, storageExhausted, readFailure = true)
        }
    }

    private fun extract(
        container: File,
        offset: Long,
        length: Long,
        format: String,
        cancelled: () -> Boolean,
    ): Carved? {
            val directory = outputDirectory()
            val extension = if (format == "jpeg") "jpg" else format
            val partial = File(directory, "${UUID.randomUUID()}.part")
            try {
                val digest = MessageDigest.getInstance("SHA-256")
                RandomAccessFile(container, "r").use { input ->
                    partial.outputStream().buffered().use { sink ->
                        input.seek(offset)
                        var remaining = length
                        val bytes = ByteArray(CHUNK_BYTES)
                        while (remaining > 0 && !cancelled()) {
                            val count = input.read(bytes, 0, minOf(bytes.size.toLong(), remaining).toInt())
                            if (count <= 0) throw IllegalStateException("Truncated payload")
                            sink.write(bytes, 0, count)
                            digest.update(bytes, 0, count)
                            remaining -= count
                        }
                        if (cancelled()) throw InterruptedException()
                    }
                }
                val inspected = inspector.inspect(partial)
                val width = inspected.width
                val height = inspected.height
                if (inspected.state != "valid" || inspected.format != format ||
                    width == null || height == null ||
                    !canDecodeSample(partial, width, height)
                ) {
                    return null
                } else {
                    val contentDigest = digest.digest().joinToString("") {
                        "%02x".format(it.toInt() and 0xff)
                    }
                    val identity = MessageDigest.getInstance("SHA-256").digest(
                        "${container.canonicalPath}|$offset|$contentDigest".toByteArray(Charsets.UTF_8),
                    ).joinToString("") { "%02x".format(it.toInt() and 0xff) }
                    val name = "$identity.$extension"
                    val existing = File(directory, name)
                    val reusable = existing.isFile && existing.length() == partial.length() &&
                        inspector.inspect(existing).state == "valid"
                    val target = if (existing.exists() && !reusable) {
                        File(directory, "${UUID.randomUUID()}_$name")
                    } else existing
                    if (reusable) {
                        partial.delete()
                    } else if (!partial.renameTo(target)) {
                        return null
                    } else {
                        retainedBytes = retainedPayloadBytes() + target.length()
                    }
                    return Carved(
                        target,
                        container,
                        offset,
                        format,
                        inspected.mimeType ?: "image/$format",
                        width,
                        height,
                        !reusable,
                    )
                }
            } catch (_: Exception) {
                return null
            } finally {
                if (partial.exists()) partial.delete()
            }
    }


    /**
     * Do not prune valid payloads: a result from a previous scan may still be
     * selected for restoration. New extraction respects the staging budget.
     */
    fun cleanupAbandonedParts(): Long {
        val now = System.currentTimeMillis()
        val entries = outputDirectory().listFiles().orEmpty().filter { it.isFile }
        var reclaimed = 0L
        entries.filter {
            it.name.endsWith(".part") &&
                now - it.lastModified() > PART_FILE_MAX_AGE_MILLIS
        }.forEach { file ->
            val bytes = file.length()
            if (file.delete()) reclaimed += bytes
        }

        retainedBytes = entries.filter { it.extension.lowercase() in CARVED_EXTENSIONS }
            .sumOf { it.length() }
        return reclaimed
    }

    private fun retainedPayloadBytes(): Long = retainedBytes ?: outputDirectory().listFiles()
        .orEmpty().filter { it.isFile && it.extension.lowercase() in CARVED_EXTENSIONS }
        .sumOf { it.length() }.also { retainedBytes = it }

    private fun canDecodeSample(file: File, width: Int, height: Int): Boolean {
        var sampleSize = 1
        while (maxOf(width, height) / sampleSize > MAX_DECODE_DIMENSION) {
            sampleSize *= 2
        }
        return try {
            val options = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.RGB_565
            }
            val bitmap = BitmapFactory.decodeFile(file.absolutePath, options) ?: return false
            val readable = bitmap.width > 0 && bitmap.height > 0
            bitmap.recycle()
            readable
        } catch (_: OutOfMemoryError) {
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun outputDirectory(): File =
        File(context.filesDir, "deep_recovery_carved").apply { mkdirs() }
    private fun payloadLength(file: File, offset: Long, format: String): Long? =
        RandomAccessFile(file, "r").use { input ->
            when (format) {
                "webp" -> webpLength(input, offset)
                "png" -> pngLength(input, offset)
                else -> jpegLength(input, offset)
            }
        }

    private fun jpegLength(input: RandomAccessFile, offset: Long): Long? {
        val end = minOf(input.length(), offset + MAX_PAYLOAD_BYTES)
        input.seek(offset)
        if (input.filePointer + 2 > end || input.readUnsignedByte() != 0xff ||
            input.readUnsignedByte() != 0xd8
        ) return null
        var markerCount = 0
        var hasFrame = false
        var hasScan = false
        while (input.filePointer + 2 <= end) {
            if (++markerCount > MAX_JPEG_MARKERS) return null
            if (input.readUnsignedByte() != 0xff) return null
            var marker = input.readUnsignedByte()
            while (marker == 0xff && input.filePointer < end) {
                marker = input.readUnsignedByte()
            }
            if (marker == 0xd9) {
                return (input.filePointer - offset).takeIf { hasFrame && hasScan }
            }
            if (marker == 0x00 || marker == 0xd8) return null
            if (marker == 0x01 || marker in 0xd0..0xd7) continue
            if (input.filePointer + 2 > end) return null
            val segmentLength = input.readUnsignedShort()
            if (segmentLength < 2 || input.filePointer + segmentLength - 2 > end) return null
            if (marker in FRAME_MARKERS) {
                if (segmentLength < 8) return null
                val precision = input.readUnsignedByte()
                val height = input.readUnsignedShort()
                val width = input.readUnsignedShort()
                if (precision == 0 || height == 0 || width == 0) return null
                hasFrame = true
                input.seek(input.filePointer + segmentLength - 7)
            } else {
                input.seek(input.filePointer + segmentLength - 2)
            }
            if (marker != 0xda) continue
            if (!hasFrame) return null
            hasScan = true
            while (input.filePointer + 1 < end) {
                if (input.readUnsignedByte() != 0xff) continue
                val markerStart = input.filePointer - 1
                var next = input.readUnsignedByte()
                while (next == 0xff && input.filePointer < end) {
                    next = input.readUnsignedByte()
                }
                if (next == 0x00 || next in 0xd0..0xd7) continue
                input.seek(markerStart)
                break
            }
        }
        return null
    }

    private fun pngLength(input: RandomAccessFile, offset: Long): Long? {
        input.seek(offset)
        val signature = ByteArray(PNG.size)
        if (offset + PNG.size > input.length()) return null
        input.readFully(signature)
        if (!signature.contentEquals(PNG)) return null
        var position = offset + 8
        val end = minOf(input.length(), offset + MAX_PAYLOAD_BYTES)
        var hasHeader = false
        var hasImageData = false
        var imageDataEnded = false
        var chunkCount = 0
        val buffer = ByteArray(CHUNK_BYTES)
        while (position + 12 <= end) {
            if (++chunkCount > MAX_CONTAINER_CHUNKS) return null
            input.seek(position)
            val size = input.readInt().toLong() and 0xffffffffL
            if (size > end - position - 12) return null
            val typeBytes = ByteArray(4).also { input.readFully(it) }
            val type = typeBytes.toString(Charsets.US_ASCII)
            if (!hasHeader && (type != "IHDR" || size != 13L)) return null
            if (type == "IHDR") {
                if (hasHeader || size != 13L) return null
                hasHeader = true
            }
            if (type == "IDAT") {
                if (imageDataEnded) return null
                if (size > 0L) hasImageData = true
            } else if (hasImageData) imageDataEnded = true
            val crc = CRC32().apply { update(typeBytes) }
            var remaining = size
            if (type == "IHDR") {
                val header = ByteArray(13).also { input.readFully(it) }
                crc.update(header)
                if (uint32BE(header, 0) !in 1L..MAX_IMAGE_DIMENSION ||
                    uint32BE(header, 4) !in 1L..MAX_IMAGE_DIMENSION ||
                    !validPngColorDepth(u(header[8]), u(header[9])) ||
                    u(header[10]) != 0 || u(header[11]) != 0 || u(header[12]) > 1
                ) return null
                remaining = 0
            }
            while (remaining > 0) {
                val count = input.read(buffer, 0, minOf(remaining, buffer.size.toLong()).toInt())
                if (count <= 0) return null
                crc.update(buffer, 0, count)
                remaining -= count
            }
            val storedCrc = input.readInt().toLong() and 0xffffffffL
            if (storedCrc != crc.value) return null
            position += 12 + size
            if (type == "IEND") {
                return (position - offset).takeIf { size == 0L && hasImageData }
            }
        }
        return null
    }

    private fun webpLength(input: RandomAccessFile, offset: Long): Long? {
        if (offset + 20 > input.length()) return null
        input.seek(offset)
        val riff = ByteArray(4).also { input.readFully(it) }
        if (riff.toString(Charsets.US_ASCII) != "RIFF") return null
        val size = readUInt32LE(input)
        val end = offset + size + 8
        if (size < 12L || end > input.length() || end - offset > MAX_PAYLOAD_BYTES) return null
        val webp = ByteArray(4).also { input.readFully(it) }
        if (webp.toString(Charsets.US_ASCII) != "WEBP") return null
        var position = offset + 12
        var hasImageData = false
        var firstChunk: String? = null
        var hasAnimation = false
        var chunkCount = 0
        while (position + 8 <= end) {
            if (++chunkCount > MAX_CONTAINER_CHUNKS) return null
            input.seek(position)
            val type = ByteArray(4).also { input.readFully(it) }.toString(Charsets.US_ASCII)
            val chunkSize = readUInt32LE(input)
            val paddedSize = chunkSize + (chunkSize and 1L)
            if (paddedSize > end - position - 8) return null
            if (firstChunk == null) {
                if (type !in setOf("VP8 ", "VP8L", "VP8X")) return null
                firstChunk = type
                if ((type == "VP8X" && chunkSize != 10L) ||
                    (type == "VP8L" && chunkSize < 5L) ||
                    (type == "VP8 " && chunkSize < 10L)
                ) return null
            }
            if (type == "VP8X") {
                if (chunkSize != 10L || position != offset + 12) return null
                val extended = ByteArray(10).also { input.readFully(it) }
                val width = 1L + u(extended[4]) + (u(extended[5]) shl 8) +
                    (u(extended[6]) shl 16)
                val height = 1L + u(extended[7]) + (u(extended[8]) shl 8) +
                    (u(extended[9]) shl 16)
                if (width > MAX_IMAGE_DIMENSION || height > MAX_IMAGE_DIMENSION) return null
            }
            if (type == "VP8L") {
                if (chunkSize < 5L) return null
                if (input.readUnsignedByte() != 0x2f) return null
            }
            if (type == "VP8 ") {
                if (chunkSize < 10L) return null
                input.seek(position + 8 + 3)
                if (input.readUnsignedByte() != 0x9d || input.readUnsignedByte() != 0x01 ||
                    input.readUnsignedByte() != 0x2a
                ) return null
            }
            if (type == "ANMF" && (firstChunk != "VP8X" || !hasAnimation || chunkSize < 16L)) {
                return null
            }
            if (type == "ANIM") hasAnimation = true
            if (type == "VP8 " || type == "VP8L" || type == "ANMF") {
                if (chunkSize == 0L) return null
                hasImageData = true
            }
            position += 8 + paddedSize
        }
        return (end - offset).takeIf {
            position == end && hasImageData &&
                (firstChunk == "VP8X" || chunkCount == 1) &&
                (!hasAnimation || firstChunk == "VP8X")
        }
    }

    private fun uint32BE(bytes: ByteArray, offset: Int): Long =
        (u(bytes[offset]).toLong() shl 24) or
            (u(bytes[offset + 1]).toLong() shl 16) or
            (u(bytes[offset + 2]).toLong() shl 8) or
            u(bytes[offset + 3]).toLong()

    private fun validPngColorDepth(depth: Int, color: Int): Boolean = when (color) {
        0 -> depth in setOf(1, 2, 4, 8, 16)
        2, 4, 6 -> depth == 8 || depth == 16
        3 -> depth in setOf(1, 2, 4, 8)
        else -> false
    }

    private fun readUInt32LE(input: RandomAccessFile): Long {
        var value = 0L
        repeat(4) { shift -> value = value or ((input.read().toLong() and 0xff) shl (shift * 8)) }
        return value
    }

    private fun ascii(bytes: ByteArray, offset: Int, length: Int) =
        bytes.copyOfRange(offset, offset + length).toString(Charsets.US_ASCII)
    private fun u(value: Byte) = value.toInt() and 0xff

    companion object {
        private const val CHUNK_BYTES = 64 * 1024
        private const val OVERLAP_BYTES = 16
        private const val MAX_SCAN_BYTES_PER_PAGE = 8L * 1024 * 1024
        private const val MAX_PAYLOAD_BYTES = 64L * 1024 * 1024
        private const val MAX_JPEG_MARKERS = 100000
        private const val MAX_CONTAINER_CHUNKS = 10000
        private const val MAX_SIGNATURES_PER_PAGE = 256
        private const val MAX_IMAGE_DIMENSION = 100000L
        private const val MAX_DECODE_DIMENSION = 1024
        private const val PART_FILE_MAX_AGE_MILLIS = 60L * 60L * 1000L
        private const val MAX_RETAINED_BYTES = 256L * 1024L * 1024L
        private const val MIN_SIGNATURE_BYTES = 12
        private const val MIN_STANDALONE_PAYLOAD_BYTES = 32L
        private val CARVED_EXTENSIONS = setOf("jpg", "jpeg", "png", "webp")
        private val FRAME_MARKERS = setOf(
            0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7,
            0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf,
        )
        private val PNG = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)
    }
}
