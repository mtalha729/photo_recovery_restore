package com.photorecoveryrestore.app

import android.content.ContentResolver
import android.net.Uri
import android.os.Build
import android.provider.MediaStore

class CurrentMediaMetadataQuery(private val contentResolver: ContentResolver) {
    fun query(
        mediaStoreId: Long,
        storageVolumeName: String?,
        contentUriText: String?,
    ): Map<String, Any?> {
        val projection = buildProjection()
        val collection = if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            !storageVolumeName.isNullOrBlank()
        ) {
            MediaStore.Images.Media.getContentUri(storageVolumeName)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val itemUri = contentUriText
            ?.let { runCatching { Uri.parse(it) }.getOrNull() }
            ?.takeIf { it.scheme == ContentResolver.SCHEME_CONTENT }
            ?: collection.buildUpon().appendPath(mediaStoreId.toString()).build()
        return try {
            contentResolver.query(
                collection,
                projection.toTypedArray(),
                "${MediaStore.Images.Media._ID} = ?",
                arrayOf(mediaStoreId.toString()),
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return unavailable()

                success(
                    mapOf(
                        "mediaStoreId" to cursor.getLongOrNull(MediaStore.Images.Media._ID),
                        "contentUri" to itemUri.toString(),
                        "displayName" to cursor.getStringOrNull(MediaStore.Images.Media.DISPLAY_NAME),
                        "mimeType" to cursor.getStringOrNull(MediaStore.Images.Media.MIME_TYPE),
                        "byteSize" to cursor.getLongOrNull(MediaStore.Images.Media.SIZE),
                        "width" to cursor.getIntOrNull(MediaStore.Images.Media.WIDTH),
                        "height" to cursor.getIntOrNull(MediaStore.Images.Media.HEIGHT),
                        "dateTakenMillis" to cursor.getLongOrNull(MediaStore.Images.Media.DATE_TAKEN),
                        "dateAddedSeconds" to cursor.getLongOrNull(MediaStore.Images.Media.DATE_ADDED),
                        "dateModifiedSeconds" to cursor.getLongOrNull(MediaStore.Images.Media.DATE_MODIFIED),
                        "relativePath" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            cursor.getStringOrNull(MediaStore.MediaColumns.RELATIVE_PATH)
                        } else null,
                        "bucketName" to cursor.getStringOrNull(MediaStore.Images.Media.BUCKET_DISPLAY_NAME),
                        "orientationDegrees" to cursor.getIntOrNull(MediaStore.Images.Media.ORIENTATION),
                        "storageVolumeName" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            cursor.getStringOrNull(MediaStore.MediaColumns.VOLUME_NAME)
                        } else storageVolumeName,
                    ),
                )
            } ?: unavailable()
        } catch (_: SecurityException) {
            failure("securityDenied", "Media access is unavailable.")
        } catch (_: Exception) {
            failure("platformFailure", "Unable to read current media metadata.")
        }
    }

    private fun buildProjection(): MutableList<String> {
        val projection = mutableListOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.MIME_TYPE,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.DATE_MODIFIED,
            MediaStore.Images.Media.BUCKET_DISPLAY_NAME,
            MediaStore.Images.Media.ORIENTATION,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection += MediaStore.MediaColumns.RELATIVE_PATH
            projection += MediaStore.MediaColumns.VOLUME_NAME
        }
        return projection
    }

    private fun success(metadata: Map<String, Any?>): Map<String, Any?> {
        return mapOf("status" to "success", "metadata" to metadata)
    }

    private fun unavailable(): Map<String, Any?> {
        return failure("recordUnavailable", "Current media record is unavailable.")
    }

    private fun failure(code: String, message: String): Map<String, Any?> {
        return mapOf("status" to "failure", "code" to code, "message" to message)
    }

    private fun android.database.Cursor.getStringOrNull(column: String): String? {
        val index = getColumnIndex(column)
        return if (index < 0 || isNull(index)) null else getString(index)
    }

    private fun android.database.Cursor.getLongOrNull(column: String): Long? {
        val index = getColumnIndex(column)
        return if (index < 0 || isNull(index)) null else getLong(index)
    }

    private fun android.database.Cursor.getIntOrNull(column: String): Int? {
        val index = getColumnIndex(column)
        return if (index < 0 || isNull(index)) null else getInt(index)
    }
}
