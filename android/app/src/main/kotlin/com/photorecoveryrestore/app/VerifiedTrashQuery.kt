package com.photorecoveryrestore.app

import android.content.ContentResolver
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.storage.StorageManager
import android.provider.MediaStore

class VerifiedTrashQuery(private val context: Context) {
    private val contentResolver: ContentResolver
        get() = context.contentResolver
    private val signatureInspector = ImageSignatureInspector(contentResolver)

    fun query(
        pageSize: Int,
        continuationToken: String?,
        legacyAfterMediaStoreId: Long?,
    ): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return mapOf(
                "status" to "unsupported",
                "androidApiLevel" to Build.VERSION.SDK_INT,
            )
        }

        val volumes = MediaStoreVolumePaging.volumeNames(context)
        val removableVolumeNames = removableVolumeNames()
        var cursorState = MediaStoreVolumePaging.parse(
            continuationToken,
            legacyAfterMediaStoreId,
        ) ?: return failure("platformFailure", "Invalid trash continuation.")

        return try {
            var invalidFilesRejected = 0
            var inaccessibleFiles = 0
            var rawRowsExamined = 0
            while (cursorState.volumeIndex < volumes.size) {
                val volumeName = volumes[cursorState.volumeIndex]
                val page = queryVolume(
                    volumeName = volumeName,
                    pageSize = pageSize,
                    afterId = cursorState.afterId,
                    isRemovable = removableVolumeNames.contains(volumeName),
                )
                invalidFilesRejected += page.invalidFilesRejected
                inaccessibleFiles += page.inaccessibleFiles
                rawRowsExamined += page.rawRowsExamined
                if (page.items.isNotEmpty() || page.hasMore) {
                    val nextToken = if (page.hasMore) {
                        val lastExaminedId = page.lastExaminedId
                            ?: return failure("platformFailure", "Trash pagination made no progress.")
                        MediaStoreVolumePaging.token(
                            cursorState.volumeIndex,
                            lastExaminedId,
                        )
                    } else if (cursorState.volumeIndex + 1 < volumes.size) {
                        MediaStoreVolumePaging.token(cursorState.volumeIndex + 1, 0L)
                    } else {
                        null
                    }
                    return success(
                        page.items,
                        nextToken,
                        volumeName,
                        invalidFilesRejected,
                        inaccessibleFiles,
                        rawRowsExamined,
                    )
                }
                cursorState = MediaStorePageCursor(cursorState.volumeIndex + 1, 0L)
            }
            success(
                emptyList(),
                null,
                null,
                invalidFilesRejected,
                inaccessibleFiles,
                rawRowsExamined,
            )
        } catch (_: SecurityException) {
            failure("securityDenied", "Media trash access is unavailable.")
        } catch (_: Exception) {
            failure("platformFailure", "Unable to query verified media trash.")
        }
    }

    private fun queryVolume(
        volumeName: String,
        pageSize: Int,
        afterId: Long,
        isRemovable: Boolean,
    ): VolumePage {
        val collection = MediaStore.Images.Media.getContentUri(volumeName)
        val items = mutableListOf<Map<String, Any?>>()
        val queryArguments = Bundle().apply {
            putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_ONLY)
            putStringArray(
                ContentResolver.QUERY_ARG_SORT_COLUMNS,
                arrayOf(MediaStore.Images.Media._ID),
            )
            putInt(
                ContentResolver.QUERY_ARG_SORT_DIRECTION,
                ContentResolver.QUERY_SORT_DIRECTION_ASCENDING,
            )
            putInt(ContentResolver.QUERY_ARG_LIMIT, pageSize + 1)
            putString(
                ContentResolver.QUERY_ARG_SQL_SELECTION,
                "${MediaStore.Images.Media._ID} > ?",
            )
            putStringArray(
                ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS,
                arrayOf(afterId.toString()),
            )
        }
        var rawRowsExamined = 0
        var lastExaminedId: Long? = null
        var hasMore = false
        var invalidFilesRejected = 0
        var inaccessibleFiles = 0
        val cursor = contentResolver.query(collection, projection(), queryArguments, null)
            ?: throw IllegalStateException("MediaStore returned no trash cursor.")
        cursor.use { rows ->
            while (rows.moveToNext()) {
                if (rawRowsExamined >= pageSize) {
                    hasMore = true
                    break
                }
                rawRowsExamined++
                val id = rows.getLongOrNull(MediaStore.Images.Media._ID)
                    ?: throw IllegalStateException("MediaStore trash row has no ID.")
                lastExaminedId = id
                if (rows.getIntOrNull(MediaStore.MediaColumns.IS_TRASHED) != 1) continue
                val contentUri = collection.buildUpon()
                    .appendPath(id.toString())
                    .build()
                val declaredMime = rows.getStringOrNull(MediaStore.Images.Media.MIME_TYPE)
                val signature = signatureInspector.inspect(contentUri)
                if (signature.state == "unavailable") {
                    inaccessibleFiles++
                }
                val identifiedImage = (signature.state == "valid" ||
                    signature.state == "unsupported") &&
                    !signature.format.isNullOrBlank() &&
                    signature.mimeType?.startsWith("image/") == true
                // Images.Media plus IS_TRASHED is authoritative even when an
                // older row has no MIME value and its bytes cannot yet open.
                val unreadableImageRow = signature.state == "unavailable" &&
                    (declaredMime == null || declaredMime.startsWith("image/"))
                if (!identifiedImage && !unreadableImageRow) {
                    invalidFilesRejected++
                    continue
                }
                items += mapOf(
                    "mediaStoreId" to id,
                    "contentUri" to contentUri.toString(),
                    "displayName" to rows.getStringOrNull(MediaStore.Images.Media.DISPLAY_NAME),
                    "mimeType" to (signature.mimeType ?: declaredMime),
                    "initialBytesReadable" to identifiedImage,
                    "byteSize" to rows.getLongOrNull(MediaStore.Images.Media.SIZE),
                    "width" to (
                        signature.width
                            ?: rows.getIntOrNull(MediaStore.Images.Media.WIDTH)
                    ),
                    "height" to (
                        signature.height
                            ?: rows.getIntOrNull(MediaStore.Images.Media.HEIGHT)
                    ),
                    "dateTakenMillis" to rows.getLongOrNull(MediaStore.Images.Media.DATE_TAKEN),
                    "dateAddedSeconds" to rows.getLongOrNull(MediaStore.Images.Media.DATE_ADDED),
                    "dateModifiedSeconds" to rows.getLongOrNull(MediaStore.Images.Media.DATE_MODIFIED),
                    "relativePath" to rows.getStringOrNull(MediaStore.MediaColumns.RELATIVE_PATH),
                    "bucketName" to rows.getStringOrNull(MediaStore.Images.Media.BUCKET_DISPLAY_NAME),
                    "orientationDegrees" to rows.getIntOrNull(MediaStore.Images.Media.ORIENTATION),
                    "storageVolumeName" to volumeName,
                    "isRemovableStorage" to isRemovable,
                    "isTrashed" to true,
                )
            }
        }
        return VolumePage(
            items,
            hasMore,
            lastExaminedId,
            invalidFilesRejected,
            inaccessibleFiles,
            rawRowsExamined,
        )
    }

    private fun success(
        items: List<Map<String, Any?>>,
        nextContinuationToken: String?,
        scannedVolumeName: String?,
        invalidFilesRejected: Int,
        inaccessibleFiles: Int,
        rawRowsExamined: Int,
    ): Map<String, Any?> = mapOf(
        "status" to "success",
        "items" to items,
        "nextAfterMediaStoreId" to null,
        "nextContinuationToken" to nextContinuationToken,
        "scannedVolumeName" to scannedVolumeName,
        "invalidFilesRejected" to invalidFilesRejected,
        "inaccessibleFiles" to inaccessibleFiles,
        "rawRowsExamined" to rawRowsExamined,
    )

    private fun failure(code: String, message: String): Map<String, Any?> =
        mapOf("status" to "failure", "code" to code, "message" to message)

    private fun removableVolumeNames(): Set<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptySet()
        val storageManager = context.getSystemService(StorageManager::class.java)
        return storageManager.storageVolumes
            .asSequence()
            .filter { it.isRemovable }
            .mapNotNull { it.mediaStoreVolumeName }
            .toSet()
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

    private data class VolumePage(
        val items: MutableList<Map<String, Any?>>,
        val hasMore: Boolean,
        val lastExaminedId: Long?,
        val invalidFilesRejected: Int,
        val inaccessibleFiles: Int,
        val rawRowsExamined: Int,
    )

    companion object {
        // This projection is only reached after the API 30 guard in query().
        // Keep API 30-only column references out of static class initialization
        // so Android 8–10 can return the supported/unsupported result safely.
        private fun projection(): Array<String> = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.MIME_TYPE,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.DATE_MODIFIED,
            MediaStore.MediaColumns.RELATIVE_PATH,
            MediaStore.Images.Media.BUCKET_DISPLAY_NAME,
            MediaStore.Images.Media.ORIENTATION,
            MediaStore.MediaColumns.VOLUME_NAME,
            MediaStore.MediaColumns.IS_TRASHED,
        )
    }
}
