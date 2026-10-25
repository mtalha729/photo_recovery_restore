package com.photorecoveryrestore.app

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.util.Size
import android.util.LruCache
import android.provider.MediaStore
import java.io.ByteArrayOutputStream
import java.io.File

class BoundedThumbnailLoader(private val context: Context) {
    private val resolver: ContentResolver = context.contentResolver
    private val fileDecoder = BoundedFileThumbnailDecoder(context)
    private val uriDecoder = BoundedUriThumbnailDecoder(resolver)
    private val memoryCache = object : LruCache<String, ByteArray>(MAXIMUM_CACHE_BYTES) {
        override fun sizeOf(key: String, value: ByteArray): Int = value.size
    }

    fun load(arguments: Map<*, *>?): Map<String, Any?> {
        val uri = (arguments?.get("contentUri") as? String)?.let(Uri::parse)
        val file = (arguments?.get("filePath") as? String)?.let(::File)
        val width = ((arguments?.get("width") as? Number)?.toInt() ?: 1).coerceIn(1, 512)
        val height = ((arguments?.get("height") as? Number)?.toInt() ?: 1).coerceIn(1, 512)
        val cacheKey = cacheKey(uri, file, width, height)
        memoryCache.get(cacheKey)?.let { return success(it) }
        return try {
            val bitmap = if (file != null) {
                fileDecoder.decode(file, width, height) ?: return failure("missing")
            } else if (uri != null && Build.VERSION.SDK_INT >= 29) {
                resolver.loadThumbnail(uri, Size(width, height), null)
            } else if (uri != null) {
                val mediaId = if (uri.authority == MediaStore.AUTHORITY) {
                    runCatching { ContentUris.parseId(uri) }.getOrNull()
                } else null
                val legacy = mediaId?.let {
                    MediaStore.Images.Thumbnails.getThumbnail(
                        resolver, it, MediaStore.Images.Thumbnails.MINI_KIND, null,
                    )
                }
                legacy ?: uriDecoder.decode(uri, width, height) ?: return failure("missing")
            } else return failure("missing")
            val bounded = scaleDown(bitmap, width, height)
            val output = ByteArrayOutputStream()
            bounded.compress(Bitmap.CompressFormat.JPEG, 82, output)
            if (bounded !== bitmap) bounded.recycle()
            bitmap.recycle()
            output.toByteArray().also { bytes -> memoryCache.put(cacheKey, bytes) }.let(::success)
        } catch (_: SecurityException) {
            failure("accessDenied")
        } catch (_: Exception) {
            failure("missing")
        }
    }

    private fun cacheKey(uri: Uri?, file: File?, width: Int, height: Int): String {
        val location = when {
            file != null -> "file:${file.absolutePath}:${file.length()}:${file.lastModified()}"
            uri != null -> "uri:$uri"
            else -> "missing"
        }
        return "$location:$width:$height"
    }

    private fun scaleDown(bitmap: Bitmap, maxWidth: Int, maxHeight: Int): Bitmap {
        val scale = minOf(maxWidth.toFloat() / bitmap.width, maxHeight.toFloat() / bitmap.height, 1f)
        if (scale >= 1f) return bitmap
        return Bitmap.createScaledBitmap(
            bitmap,
            (bitmap.width * scale).toInt().coerceAtLeast(1),
            (bitmap.height * scale).toInt().coerceAtLeast(1),
            true,
        )
    }

    private fun failure(code: String) = mapOf<String, Any?>(
        "status" to "failure",
        "code" to code,
    )

    private fun success(bytes: ByteArray) = mapOf<String, Any?>(
        "status" to "success",
        "bytes" to bytes,
    )

    companion object {
        private const val MAXIMUM_CACHE_BYTES = 4 * 1024 * 1024
    }
}
