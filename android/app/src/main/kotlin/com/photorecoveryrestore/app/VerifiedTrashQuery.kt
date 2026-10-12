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
            while (cursorState.volumeIndex < volumes.size) {
                val volumeName = volumes[cursorState.volumeIndex]
                val page = queryVolume(
                    volumeName = volumeName,
                    pageSize = pageSize,
                    afterId = cursorState.afterId,
                    isRemovable = removableVolumeNames.contains(volumeName),
                )
                if (page.items.isNotEmpty()) {
                    val nextToken = if (page.hasMore) {
                        MediaStoreVolumePaging.token(
                            cursorState.volumeIndex,
                            page.items.last().getValue("mediaStoreId") as Long,
                        )
                    } else if (cursorState.volumeIndex + 1 < volumes.size) {
                        MediaStoreVolumePaging.token(cursorState.volumeIndex + 1, 0L)
                    } else {
                        null
                    }
                    return success(page.items, nextToken, volumeName)
                }
                cursorState = MediaStorePageCursor(cursorState.volumeIndex + 1, 0L)
            }
            success(emptyList(), null, null)
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
        contentResolver.query(collection, projection, queryArguments, null)?.use { cursor ->
            while (cursor.moveToNext() && items.size <= pageSize) {
                if (cursor.getIntOrNull(MediaStore.MediaColumns.IS_TRASHED) != 1) continue
                val id = cursor.getLongOrNull(MediaStore.Images.Media._ID) ?: continue
                items += mapOf(
                    "mediaStoreId" to id,
                    "contentUri" to collection.buildUpon()
                        .appendPath(id.toString())
                        .build()
                        .toString(),
                    "displayName" to cursor.getStringOrNull(MediaStore.Images.Media.DISPLAY_NAME),
                    "mimeType" to cursor.getStringOrNull(MediaStore.Images.Media.MIME_TYPE),
                    "byteSize" to cursor.getLongOrNull(MediaStore.Images.Media.SIZE),
                    "width" to cursor.getIntOrNull(MediaStore.Images.Media.WIDTH),
                    "height" to cursor.getIntOrNull(MediaStore.Images.Media.HEIGHT),
                    "dateTakenMillis" to cursor.getLongOrNull(MediaStore.Images.Media.DATE_TAKEN),
                    "dateAddedSeconds" to cursor.getLongOrNull(MediaStore.Images.Media.DATE_ADDED),
                    "dateModifiedSeconds" to cursor.getLongOrNull(MediaStore.Images.Media.DATE_MODIFIED),
                    "relativePath" to cursor.getStringOrNull(MediaStore.MediaColumns.RELATIVE_PATH),
                    "bucketName" to cursor.getStringOrNull(MediaStore.Images.Media.BUCKET_DISPLAY_NAME),
                    "orientationDegrees" to cursor.getIntOrNull(MediaStore.Images.Media.ORIENTATION),
                    "storageVolumeName" to volumeName,
                    "isRemovableStorage" to isRemovable,
                    "isTrashed" to true,
                )
            }
        }
        val hasMore = items.size > pageSize
        if (hasMore) items.removeAt(items.lastIndex)
        return VolumePage(items, hasMore)
    }

    private fun success(
        items: List<Map<String, Any?>>,
        nextContinuationToken: String?,
        scannedVolumeName: String?,
    ): Map<String, Any?> = mapOf(
        "status" to "success",
        "items" to items,
        "nextAfterMediaStoreId" to null,
        "nextContinuationToken" to nextContinuationToken,
        "scannedVolumeName" to scannedVolumeName,
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
    )

    companion object {
        private val projection = arrayOf(
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