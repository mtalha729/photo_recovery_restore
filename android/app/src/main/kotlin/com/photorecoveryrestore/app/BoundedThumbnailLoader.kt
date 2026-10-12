package com.photorecoveryrestore.app

import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import java.io.ByteArrayOutputStream
import java.io.File

class BoundedThumbnailLoader(private val context: Context) {
    private val resolver: ContentResolver = context.contentResolver
    private val fileDecoder = BoundedFileThumbnailDecoder(context)
    fun load(arguments: Map<*, *>?): Map<String, Any?> {
        val uri = (arguments?.get("contentUri") as? String)?.let(Uri::parse)
        val file = (arguments?.get("filePath") as? String)?.let(::File)
        val width = ((arguments?.get("width") as? Number)?.toInt() ?: 1).coerceIn(1, 512)
        val height = ((arguments?.get("height") as? Number)?.toInt() ?: 1).coerceIn(1, 512)
        return try {
            val bitmap = if (file != null) {
                fileDecoder.decode(file, width, height) ?: return failure("missing")
            } else if (uri != null && Build.VERSION.SDK_INT >= 29) {
                resolver.loadThumbnail(uri, Size(width, height), null)
            } else if (uri != null) {
                val id = uri.lastPathSegment?.toLongOrNull() ?: return failure("missing")
                @Suppress("DEPRECATION")
                MediaStore.Images.Thumbnails.getThumbnail(
                    resolver,
                    id,
                    MediaStore.Images.Thumbnails.MINI_KIND,
                    null,
                ) ?: return failure("missing")
            } else return failure("missing")
            val bounded = scaleDown(bitmap, width, height)
            val output = ByteArrayOutputStream()
            bounded.compress(Bitmap.CompressFormat.JPEG, 82, output)
            if (bounded !== bitmap) bounded.recycle()
            bitmap.recycle()
            mapOf("status" to "success", "bytes" to output.toByteArray())
        } catch (_: SecurityException) {
            failure("accessDenied")
        } catch (_: Exception) {
            failure("missing")
        }
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
}
