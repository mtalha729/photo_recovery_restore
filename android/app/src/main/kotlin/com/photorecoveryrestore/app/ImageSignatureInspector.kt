package com.photorecoveryrestore.app

import android.content.ContentResolver
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.File
import java.io.FileInputStream
import java.io.BufferedInputStream

/** Reads only a bounded header. It never decodes a bitmap or loads a full file. */
class ImageSignatureInspector(private val resolver: ContentResolver) {
    fun inspect(uri: Uri): ImageSignatureResult {
        return try {
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
            ImageSignatureResult.unavailable()
        } catch (_: Exception) {
            ImageSignatureResult.corrupted()
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
                // Reset the same buffered file handle for bounds-only decoding.
                // BitmapFactory never creates a bitmap when inJustDecodeBounds is set.
                stream.reset()
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                try {
                    BitmapFactory.decodeStream(stream, null, options)
                } catch (_: SecurityException) {
                    return ImageSignatureResult.unavailable()
                } catch (_: Exception) {
                    // Some platform decoders throw instead of returning unknown
                    // bounds for a format they do not support.
                    return signature
                }
                if (options.outWidth <= 0 || options.outHeight <= 0) {
                    // The byte signature is still useful when the platform lacks
                    // a bounds decoder (for example HEIF, AVIF, RAW, JXL, or
                    // JPEG 2000 on older API levels). Keep it as a possible-copy
                    // candidate rather than silently dropping the original file.
                    return signature
                }
                signature.copy(width = options.outWidth, height = options.outHeight)
            }
        } catch (_: SecurityException) {
            ImageSignatureResult.unavailable()
        } catch (_: Exception) {
            ImageSignatureResult.corrupted()
        }
    }

    internal fun detect(bytes: ByteArray, count: Int = bytes.size): ImageSignatureResult {
        if (count >= 3 && u(bytes[0]) == 0xFF && u(bytes[1]) == 0xD8 && u(bytes[2]) == 0xFF) {
            return ImageSignatureResult.valid("jpeg", "image/jpeg")
        }
        if (count >= 8 && bytes.copyOfRange(0, 8).contentEquals(PNG)) {
            return ImageSignatureResult.valid("png", "image/png")
        }
        if (count >= 6) {
            val signature = bytes.copyOfRange(0, 6).toString(Charsets.US_ASCII)
            if (signature == "GIF87a" || signature == "GIF89a") {
                return ImageSignatureResult.valid("gif", "image/gif")
            }
        }
        if (count >= 12 && ascii(bytes, 0, 4) == "RIFF" && ascii(bytes, 8, 4) == "WEBP") {
            return ImageSignatureResult.valid("webp", "image/webp")
        }
        if (count >= 2 && ascii(bytes, 0, 2) == "BM") {
            return ImageSignatureResult.valid("bmp", "image/bmp")
        }
        if (count >= 4) {
            val littleEndian = u(bytes[0]) == 0x49 && u(bytes[1]) == 0x49 &&
                u(bytes[2]) == 0x2A && u(bytes[3]) == 0x00
            val bigEndian = u(bytes[0]) == 0x4D && u(bytes[1]) == 0x4D &&
                u(bytes[2]) == 0x00 && u(bytes[3]) == 0x2A
            val littleBigTiff = u(bytes[0]) == 0x49 && u(bytes[1]) == 0x49 &&
                u(bytes[2]) == 0x2B && u(bytes[3]) == 0x00
            val bigBigTiff = u(bytes[0]) == 0x4D && u(bytes[1]) == 0x4D &&
                u(bytes[2]) == 0x00 && u(bytes[3]) == 0x2B
            if (littleEndian || bigEndian || littleBigTiff || bigBigTiff) {
                return ImageSignatureResult.valid("tiff", "image/tiff")
            }
        }
        // JPEG XL and JPEG 2000 may not have a BitmapFactory decoder on older
        // Android releases. Their container/codestream signatures are still
        // strong enough to offer the original file as a possible copy.
        if (count >= 12 && bytes.copyOfRange(0, 12).contentEquals(JXL_CONTAINER)) {
            return ImageSignatureResult.valid("jxl", "image/jxl")
        }
        if (count >= 2 && u(bytes[0]) == 0xff && u(bytes[1]) == 0x0a) {
            return ImageSignatureResult.valid("jxl", "image/jxl")
        }
        if (count >= 12 && bytes.copyOfRange(0, 12).contentEquals(JP2_CONTAINER)) {
            return ImageSignatureResult.valid("jp2", "image/jp2")
        }
        if (count >= 4 && u(bytes[0]) == 0xff && u(bytes[1]) == 0x4f &&
            u(bytes[2]) == 0xff && u(bytes[3]) == 0x51) {
            return ImageSignatureResult.valid("jp2", "image/jp2")
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

    companion object {
        private const val MAX_HEADER_BYTES = 64
        private val PNG = byteArrayOf(
            0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        )
        private val JXL_CONTAINER = byteArrayOf(
            0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A,
            0x87.toByte(), 0x0A,
        )
        private val JP2_CONTAINER = byteArrayOf(
            0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A,
            0x87.toByte(), 0x0A,
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
