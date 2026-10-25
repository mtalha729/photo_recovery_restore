package com.photorecoveryrestore.app

import android.content.ContentResolver
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.BufferedInputStream

/** Reads only a bounded header. It never decodes a bitmap or loads a full file. */
class ImageSignatureInspector(private val resolver: ContentResolver) {
    fun inspect(uri: Uri): ImageSignatureResult {
        val signature = try {
            val header = ByteArray(MAX_HEADER_BYTES)
            val count = resolver.openInputStream(uri)?.use { stream ->
                var offset = 0
                while (offset < header.size) {
                    val read = stream.read(header, offset, header.size - offset)
                    if (read <= 0) break
                    offset += read
                }
                offset
            } ?: return ImageSignatureResult.unavailable()
            detect(header, count)
        } catch (_: SecurityException) {
            return ImageSignatureResult.unavailable()
        } catch (_: FileNotFoundException) {
            return ImageSignatureResult.unavailable()
        } catch (_: Exception) {
            return ImageSignatureResult.corrupted()
        }
        if (signature.state != "valid") return signature

        // Confirm decoder-readable bounds without allocating a bitmap. Some
        // recognized formats/codecs do not expose bounds on every API level;
        // those remain explicit unknown-dimension images rather than being
        // mislabeled as deleted or silently discarded.
        return try {
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            resolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, options)
            } ?: return ImageSignatureResult.unavailable()
            if (options.outWidth <= 0 || options.outHeight <= 0) {
                undecodable(signature)
            } else {
                signature.copy(width = options.outWidth, height = options.outHeight)
            }
        } catch (_: SecurityException) {
            ImageSignatureResult.unavailable()
        } catch (_: FileNotFoundException) {
            ImageSignatureResult.unavailable()
        } catch (_: Exception) {
            ImageSignatureResult.corrupted(signature.format, signature.mimeType)
        }
    }

    fun inspect(file: File): ImageSignatureResult {
        if (!file.isFile || file.length() <= 0L) return ImageSignatureResult.corrupted()
        return try {
            val header = ByteArray(MAX_HEADER_BYTES)
            BufferedInputStream(FileInputStream(file), MAX_HEADER_BYTES * 2).use { stream ->
                stream.mark(MAX_HEADER_BYTES)
                var offset = 0
                while (offset < header.size) {
                    val read = stream.read(header, offset, header.size - offset)
                    if (read <= 0) break
                    offset += read
                }
                val signature = detect(header, offset)
                if (signature.state != "valid") return signature
                if (signature.format == "webp" &&
                    readUInt32LE(header, 4) + 8 > file.length()
                ) return ImageSignatureResult.corrupted(signature.format, signature.mimeType)
                if (signature.format == "bmp" &&
                    readUInt32LE(header, 2) > file.length()
                ) return ImageSignatureResult.corrupted(signature.format, signature.mimeType)
                // Reset the same buffered file handle for bounds-only decoding.
                // BitmapFactory never creates a bitmap when inJustDecodeBounds is set.
                stream.reset()
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeStream(stream, null, options)
                if (options.outWidth <= 0 || options.outHeight <= 0) {
                    return undecodable(signature)
                }
                signature.copy(width = options.outWidth, height = options.outHeight)
            }
        } catch (_: SecurityException) {
            ImageSignatureResult.unavailable()
        } catch (_: FileNotFoundException) {
            ImageSignatureResult.unavailable()
        } catch (_: Exception) {
            ImageSignatureResult.corrupted()
        }
    }

    internal fun detect(bytes: ByteArray, count: Int = bytes.size): ImageSignatureResult {
        if (count >= 4 && u(bytes[0]) == 0xff && u(bytes[1]) == 0xd8 &&
            u(bytes[2]) == 0xff
        ) {
            var markerIndex = 3
            while (markerIndex < count && u(bytes[markerIndex]) == 0xff) markerIndex++
            if (markerIndex < count && u(bytes[markerIndex]) !in setOf(0x00, 0xd8, 0xd9)) {
                return ImageSignatureResult.valid("jpeg", "image/jpeg")
            }
        }
        if (count >= 33 && bytes.copyOfRange(0, 8).contentEquals(PNG) &&
            readUInt32BE(bytes, 8) == 13L && ascii(bytes, 12, 4) == "IHDR" &&
            readUInt32BE(bytes, 16) in 1L..MAX_IMAGE_DIMENSION &&
            readUInt32BE(bytes, 20) in 1L..MAX_IMAGE_DIMENSION &&
            validPngColorDepth(u(bytes[24]), u(bytes[25])) &&
            u(bytes[26]) == 0 && u(bytes[27]) == 0 && u(bytes[28]) <= 1
        ) {
            return ImageSignatureResult.valid("png", "image/png")
        }
        if (count >= 10) {
            val signature = bytes.copyOfRange(0, 6).toString(Charsets.US_ASCII)
            if ((signature == "GIF87a" || signature == "GIF89a") &&
                (u(bytes[6]) or (u(bytes[7]) shl 8)) > 0 &&
                (u(bytes[8]) or (u(bytes[9]) shl 8)) > 0
            ) {
                return ImageSignatureResult.valid("gif", "image/gif")
            }
        }
        if (count >= 26 && ascii(bytes, 0, 4) == "RIFF" &&
            ascii(bytes, 8, 4) == "WEBP" &&
            readUInt32LE(bytes, 4) >= 12L &&
            ascii(bytes, 12, 4) in WEBP_IMAGE_CHUNKS &&
            readUInt32LE(bytes, 16) > 0L &&
            when (ascii(bytes, 12, 4)) {
                "VP8X" -> count >= 30 && readUInt32LE(bytes, 16) == 10L
                "VP8L" -> readUInt32LE(bytes, 16) >= 5L && u(bytes[20]) == 0x2f
                else -> readUInt32LE(bytes, 16) >= 10L &&
                    u(bytes[23]) == 0x9d && u(bytes[24]) == 0x01 &&
                    u(bytes[25]) == 0x2a
            }
        ) {
            return ImageSignatureResult.valid("webp", "image/webp")
        }
        if (count >= 26 && ascii(bytes, 0, 2) == "BM" &&
            readUInt32LE(bytes, 2) >= 26L &&
            readUInt32LE(bytes, 14) >= 12L
        ) {
            return ImageSignatureResult.valid("bmp", "image/bmp")
        }
        if (count >= 4) {
            val littleEndian = u(bytes[0]) == 0x49 && u(bytes[1]) == 0x49 &&
                u(bytes[2]) == 0x2A && u(bytes[3]) == 0x00
            val bigEndian = u(bytes[0]) == 0x4D && u(bytes[1]) == 0x4D &&
                u(bytes[2]) == 0x00 && u(bytes[3]) == 0x2A
            if (littleEndian || bigEndian) {
                return ImageSignatureResult.valid("tiff", "image/tiff")
            }
        }
        if (count >= 12 && ascii(bytes, 4, 4) == "ftyp") {
            val brand = ascii(bytes, 8, 4).lowercase()
            if (brand in HEIF_BRANDS) {
                val mime = if (brand == "avif" || brand == "avis") "image/avif" else "image/heif"
                return ImageSignatureResult.valid(if (mime == "image/avif") "avif" else "heif", mime)
            }
        }
        return ImageSignatureResult.invalid()
    }

    private fun ascii(bytes: ByteArray, offset: Int, length: Int): String =
        bytes.copyOfRange(offset, offset + length).toString(Charsets.US_ASCII)

    private fun u(value: Byte): Int = value.toInt() and 0xFF

    private fun readUInt32BE(bytes: ByteArray, offset: Int): Long =
        ((u(bytes[offset]).toLong() shl 24) or
            (u(bytes[offset + 1]).toLong() shl 16) or
            (u(bytes[offset + 2]).toLong() shl 8) or
            u(bytes[offset + 3]).toLong())

    private fun readUInt32LE(bytes: ByteArray, offset: Int): Long =
        (u(bytes[offset]).toLong() or
            (u(bytes[offset + 1]).toLong() shl 8) or
            (u(bytes[offset + 2]).toLong() shl 16) or
            (u(bytes[offset + 3]).toLong() shl 24))

    private fun undecodable(signature: ImageSignatureResult): ImageSignatureResult =
        if (signature.format in setOf("jpeg", "png", "webp", "gif")) {
            ImageSignatureResult.corrupted(signature.format, signature.mimeType)
        } else {
            ImageSignatureResult.unsupported(signature.format, signature.mimeType)
        }

    private fun validPngColorDepth(depth: Int, color: Int): Boolean = when (color) {
        0 -> depth in setOf(1, 2, 4, 8, 16)
        2, 4, 6 -> depth == 8 || depth == 16
        3 -> depth in setOf(1, 2, 4, 8)
        else -> false
    }

    companion object {
        private const val MAX_HEADER_BYTES = 64
        private const val MAX_IMAGE_DIMENSION = 100000L
        private val WEBP_IMAGE_CHUNKS = setOf("VP8 ", "VP8L", "VP8X")
        private val PNG = byteArrayOf(
            0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        )
        private val HEIF_BRANDS = setOf(
            "heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1", "avif", "avis",
        )
    }
}

data class ImageSignatureResult(
    val state: String,
    val format: String? = null,
    val mimeType: String? = null,
    val width: Int? = null,
    val height: Int? = null,
) {
    companion object {
        fun valid(format: String, mimeType: String) = ImageSignatureResult("valid", format, mimeType)
        fun invalid() = ImageSignatureResult("invalid")
        fun corrupted(format: String? = null, mimeType: String? = null) =
            ImageSignatureResult("corrupted", format, mimeType)
        fun unsupported(format: String? = null, mimeType: String? = null) =
            ImageSignatureResult("unsupported", format, mimeType)
        fun unavailable() = ImageSignatureResult("unavailable")
    }
}
