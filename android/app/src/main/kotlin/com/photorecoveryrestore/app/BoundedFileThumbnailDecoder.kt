package com.photorecoveryrestore.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Environment
import java.io.File

/** Samples file-path previews to a bounded size before allocating pixels. */
class BoundedFileThumbnailDecoder(private val context: Context) {
    fun decode(file: File, width: Int, height: Int): Bitmap? {
        val canonical = runCatching { file.canonicalFile }.getOrNull() ?: return null
        if (!canonical.isFile || !canonical.canRead() || !isAllowed(canonical)) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(canonical.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outWidth / sample > width * 2 ||
            bounds.outHeight / sample > height * 2
        ) sample *= 2
        return BitmapFactory.decodeFile(
            canonical.path,
            BitmapFactory.Options().apply { inSampleSize = sample },
        )
    }

    private fun isAllowed(file: File): Boolean {
        val normalized = file.path.replace('\\', '/').lowercase()
        val cache = runCatching { context.cacheDir.canonicalFile }.getOrNull()
        if (cache != null && within(file, cache) &&
            file.path.contains("deep_recovery_carved")) return true
        if (normalized.contains("/android/data/") || normalized.contains("/android/obb/")) return false
        val roots = mutableListOf<File>()
        roots += Environment.getExternalStorageDirectory()
        context.getExternalFilesDirs(null).filterNotNull().forEach { directory ->
            var root: File? = directory
            repeat(4) { root = root?.parentFile }
            root?.let { roots += it }
        }
        return roots.mapNotNull { runCatching { it.canonicalFile }.getOrNull() }
            .any { within(file, it) }
    }

    private fun within(file: File, root: File): Boolean {
        val parent = root.path.trimEnd(File.separatorChar)
        return file.path == parent || file.path.startsWith(parent + File.separator)
    }
}
