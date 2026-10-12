package com.photorecoveryrestore.app

import android.content.ContentResolver
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore

internal data class MediaStorePageCursor(val volumeIndex: Int, val afterId: Long)

internal object MediaStoreVolumePaging {
    private const val TOKEN_PREFIX = "mv1"

    fun volumeNames(context: Context): List<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.getExternalVolumeNames(context).sorted()
        } else {
            listOf("external")
        }

    fun parse(token: String?, legacyAfterId: Long?): MediaStorePageCursor? {
        if (token.isNullOrBlank()) return MediaStorePageCursor(0, legacyAfterId ?: 0L)
        val parts = token.split(':')
        if (parts.size != 3 || parts[0] != TOKEN_PREFIX) return null
        val volumeIndex = parts[1].toIntOrNull() ?: return null
        val afterId = parts[2].toLongOrNull() ?: return null
        if (volumeIndex < 0 || afterId < 0) return null
        return MediaStorePageCursor(volumeIndex, afterId)
    }

    fun token(volumeIndex: Int, afterId: Long): String =
        "$TOKEN_PREFIX:$volumeIndex:$afterId"
}

class MultiVolumeCurrentMediaQuery(private val context: Context) {
    private val contentResolver: ContentResolver
        get() = context.contentResolver

    fun query(
        pageSize: Int,
        continuationToken: String?,
        legacyAfterMediaStoreId: Long?,
    ): Map<String, Any?> {
        val volumes = MediaStoreVolumePaging.volumeNames(context)
        var cursorState = MediaStoreVolumePaging.parse(
            continuationToken,
            legacyAfterMediaStoreId,
        ) ?: return failure("platformFailure", "Invalid inventory continuation.")

        return try {
            while (cursorState.volumeIndex < volumes.size) {
                val volumeName = volumes[cursorState.volumeIndex]
                val page = queryVolume(volumeName, pageSize, cursorState.afterId)
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
            failure("securityDenied", "Media access is unavailable.")
        } catch (exception: Exception) {
            failure(
                "platformFailure",
                "MediaStore image query failed (${exception.javaClass.simpleName}).",
            )
        }
    }

    private fun queryVolume(
        volumeName: String,
        pageSize: Int,
        afterId: Long,
    ): VolumePage {
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(volumeName)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val projection = arrayOf(
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
            // RELATIVE_PATH is available only from Android 10. It is kept out
            // of older projections so Android 7–9 cursor queries stay valid.
            *(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                arrayOf(MediaStore.Images.Media.RELATIVE_PATH)
            } else emptyArray()),
        )
        val selection = "${MediaStore.Images.Media._ID} > ?"
        val selectionArgs = arrayOf(afterId.toString())
        val items = mutableListOf<Map<String, Any?>>()
        val cursor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val queryArguments = Bundle().apply {
                putStringArray(
                    ContentResolver.QUERY_ARG_SORT_COLUMNS,
                    arrayOf(MediaStore.Images.Media._ID),
                )
                putInt(
                    ContentResolver.QUERY_ARG_SORT_DIRECTION,
                    ContentResolver.QUERY_SORT_DIRECTION_ASCENDING,
                )
                putInt(ContentResolver.QUERY_ARG_LIMIT, pageSize + 1)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_VISIBLE)
                }
                putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, selectionArgs)
            }
            contentResolver.query(collection, projection, queryArguments, null)
        } else {
            contentResolver.query(
                collection,
                projection,
                selection,
                selectionArgs,
                "${MediaStore.Images.Media._ID} ASC",
            )
        }
        cursor?.use {
            while (it.moveToNext() && items.size <= pageSize) {
                val id = it.getLong(0)
                items += mapOf(
                    "mediaStoreId" to id,
                    "contentUri" to collection.buildUpon()
                        .appendPath(id.toString())
                        .build()
                        .toString(),
                    "displayName" to it.getStringOrNull(MediaStore.Images.Media.DISPLAY_NAME),
                    "mimeType" to it.getStringOrNull(MediaStore.Images.Media.MIME_TYPE),
                    "storageVolumeName" to volumeName,
                    "byteSize" to it.getLongOrNull(MediaStore.Images.Media.SIZE),
                    "width" to it.getIntOrNull(MediaStore.Images.Media.WIDTH),
                    "height" to it.getIntOrNull(MediaStore.Images.Media.HEIGHT),
                    "dateTaken" to it.getLongOrNull(MediaStore.Images.Media.DATE_TAKEN),
                    // MediaStore stores these two legacy columns in seconds.
                    "dateAdded" to it.getSecondsAsMillisOrNull(MediaStore.Images.Media.DATE_ADDED),
                    "dateModified" to it.getSecondsAsMillisOrNull(MediaStore.Images.Media.DATE_MODIFIED),
                    "relativePath" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        it.getStringOrNull(MediaStore.Images.Media.RELATIVE_PATH)
                    } else null,
                    "bucketName" to it.getStringOrNull(MediaStore.Images.Media.BUCKET_DISPLAY_NAME),
                    "orientationDegrees" to it.getIntOrNull(MediaStore.Images.Media.ORIENTATION),
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

    private fun android.database.Cursor.getStringOrNull(column: String): String? =
        getColumnIndex(column).takeIf { it >= 0 }?.let { index ->
            if (isNull(index)) null else getString(index)?.trim()?.takeIf { it.isNotEmpty() }
        }

    private fun android.database.Cursor.getLongOrNull(column: String): Long? =
        getColumnIndex(column).takeIf { it >= 0 }?.let { index ->
            if (isNull(index)) null else getLong(index).takeIf { it >= 0L }
        }

    private fun android.database.Cursor.getIntOrNull(column: String): Int? =
        getColumnIndex(column).takeIf { it >= 0 }?.let { index ->
            if (isNull(index)) null else getInt(index).takeIf { it >= 0 }
        }

    private fun android.database.Cursor.getSecondsAsMillisOrNull(column: String): Long? =
        getLongOrNull(column)?.takeIf { it > 0L }?.times(1000L)

    private data class VolumePage(
        val items: MutableList<Map<String, Any?>>,
        val hasMore: Boolean,
    )
}
