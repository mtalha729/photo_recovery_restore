package com.photorecoveryrestore.app

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri

/** Bounds-first decoding for authorized document URIs on API 26–28. */
class BoundedUriThumbnailDecoder(private val resolver: ContentResolver) {
    fun decode(uri: Uri, width: Int, height: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { input ->
            BitmapFactory.decodeStream(input, null, bounds)
        } ?: return null
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outWidth / sample > width * 2 ||
            bounds.outHeight / sample > height * 2
        ) sample *= 2
        return resolver.openInputStream(uri)?.use { input ->
            BitmapFactory.decodeStream(
                input,
                null,
                BitmapFactory.Options().apply { inSampleSize = sample },
            )
        }
    }
}
