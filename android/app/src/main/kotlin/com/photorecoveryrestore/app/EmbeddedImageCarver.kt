package com.photorecoveryrestore.app

import android.content.Context
import java.io.File
import java.io.RandomAccessFile
import java.util.UUID

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
    )

    data class Page(val items: List<Carved>, val nextOffset: Long?)

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
        if (limit <= 0 || !container.isFile || !container.canRead() || container.length() <= 12) {
            return Page(emptyList(), null)
        }
        val offsets = mutableListOf<Pair<Long, String>>()
        val seenOffsets = mutableSetOf<Long>()
        var nextOffset: Long? = null
        RandomAccessFile(container, "r").use { input ->
            val buffer = ByteArray(CHUNK_BYTES + OVERLAP_BYTES)
            var base = startOffset.coerceIn(0, input.length())
            val pageEnd = (base + MAX_SCAN_BYTES_PER_PAGE).coerceAtMost(input.length())
            while (
                base < pageEnd &&
                offsets.size < limit &&
                !cancelled()
            ) {
                input.seek(base)
                val remainingInPage = pageEnd - base
                val requested = minOf(
                    buffer.size.toLong(),
                    remainingInPage + OVERLAP_BYTES,
                ).toInt()
                val read = input.read(buffer, 0, requested)
                if (read <= 0) break
                for (index in 0 until read - 11) {
                    val format = when {
                        u(buffer[index]) == 0xff && u(buffer[index + 1]) == 0xd8 &&
                            u(buffer[index + 2]) == 0xff -> "jpeg"
                        PNG.indices.all { buffer[index + it] == PNG[it] } -> "png"
                        ascii(buffer, index, 4) == "RIFF" &&
                            ascii(buffer, index + 8, 4) == "WEBP" -> "webp"
                        else -> null
                    }
                    if (format != null) {
                        val absolute = base + index
                        if (seenOffsets.add(absolute)) offsets += absolute to format
                        if (offsets.size >= limit) break
                    }
                }
                base += (read - OVERLAP_BYTES).coerceAtLeast(1)
            }
            if (base < input.length()) {
                nextOffset = if (offsets.size >= limit) {
                    offsets.last().first + 1
                } else {
                    base
                }
            }
        }
        val output = mutableListOf<Carved>()
        offsets.forEachIndexed { index, (offset, format) ->
            if (cancelled()) return Page(output, null)
            val length = payloadLength(container, offset, format) ?: return@forEachIndexed
            if (length <= 0 || length > MAX_PAYLOAD_BYTES) return@forEachIndexed
            val directory = outputDirectory()
            val extension = if (format == "jpeg") "jpg" else format
            val name = "${UUID.randomUUID()}_${index}.$extension"
            val partial = File(directory, "$name.part")
            val target = File(directory, name)
            try {
                RandomAccessFile(container, "r").use { input ->
                    partial.outputStream().buffered().use { sink ->
                        input.seek(offset)
                        var remaining = length
                        val bytes = ByteArray(CHUNK_BYTES)
                        while (remaining > 0 && !cancelled()) {
                            val count = input.read(bytes, 0, minOf(bytes.size.toLong(), remaining).toInt())
                            if (count <= 0) throw IllegalStateException("Truncated payload")
                            sink.write(bytes, 0, count)
                            remaining -= count
                        }
                        if (cancelled()) throw InterruptedException()
                    }
                }
                val inspected = inspector.inspect(partial)
                val width = inspected.width
                val height = inspected.height
                if (inspected.state != "valid" || width == null || height == null || !partial.renameTo(target)) {
                    partial.delete()
                    target.delete()
                } else {
                    output += Carved(
                        target,
                        container,
                        offset,
                        format,
                        inspected.mimeType ?: "image/$format",
                        width,
                        height,
                    )
                }
            } catch (_: Exception) {
                partial.delete()
                target.delete()
            }
        }
        return Page(output, nextOffset)
    }


    /** Removes only incomplete app-private extraction files, never valid results. */
    fun cleanupAbandonedParts(): Long {
        val cutoff = System.currentTimeMillis() - PART_FILE_MAX_AGE_MILLIS
        return outputDirectory().listFiles().orEmpty().sumOf { file ->
            if (file.isFile && file.name.endsWith(".part") && file.lastModified() < cutoff) {
                val bytes = file.length()
                if (file.delete()) bytes else 0L
            } else 0L
        }
    }

    private fun outputDirectory(): File =
        File(context.cacheDir, "deep_recovery_carved").apply { mkdirs() }
    private fun payloadLength(file: File, offset: Long, format: String): Long? =
        RandomAccessFile(file, "r").use { input ->
            when (format) {
                "webp" -> {
                    input.seek(offset + 4)
                    val size = readUInt32LE(input)
                    (size + 8).takeIf { it in 12..MAX_PAYLOAD_BYTES }
                }
                "png" -> pngLength(input, offset)
                else -> jpegLength(input, offset)
            }
        }

    private fun jpegLength(input: RandomAccessFile, offset: Long): Long? {
        input.seek(offset + 3)
        var previous = -1
        var consumed = 3L
        val buffer = ByteArray(CHUNK_BYTES)
        while (consumed < MAX_PAYLOAD_BYTES && input.filePointer < input.length()) {
            val permitted = minOf(buffer.size.toLong(), MAX_PAYLOAD_BYTES - consumed).toInt()
            val read = input.read(buffer, 0, permitted)
            if (read <= 0) break
            for (index in 0 until read) {
                val value = u(buffer[index])
                consumed++
                if (previous == 0xff && value == 0xd9) return consumed
                previous = value
            }
        }
        return null
    }

    private fun pngLength(input: RandomAccessFile, offset: Long): Long? {
        var position = offset + 8
        while (position + 12 <= input.length() && position - offset < MAX_PAYLOAD_BYTES) {
            input.seek(position)
            val size = input.readInt().toLong() and 0xffffffffL
            if (size > MAX_PAYLOAD_BYTES || position + 12 + size > input.length()) return null
            val type = ByteArray(4).also { input.readFully(it) }.toString(Charsets.US_ASCII)
            position += 12 + size
            if (type == "IEND" && size == 0L) return position - offset
        }
        return null
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
        private const val MAX_PAYLOAD_BYTES = 32L * 1024 * 1024
        private const val PART_FILE_MAX_AGE_MILLIS = 60L * 60L * 1000L
        private val PNG = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)
    }
}
