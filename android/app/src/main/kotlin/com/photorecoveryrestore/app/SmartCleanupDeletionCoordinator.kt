package com.photorecoveryrestore.app

import android.app.Activity
import android.content.ContentResolver
import android.content.IntentSender
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel

class SmartCleanupDeletionCoordinator(
    private val activity: Activity,
    private val contentResolver: ContentResolver,
) {
    private data class RequestedPhoto(val id: String, val uri: Uri)

    private var pendingResult: MethodChannel.Result? = null
    private var pendingPhotos: List<RequestedPhoto> = emptyList()

    fun delete(raw: List<Map<*, *>>?, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.success(status(unavailableIds = raw?.mapNotNull { it["id"] as? String } ?: emptyList()))
            return
        }
        val photos = raw.orEmpty().mapNotNull { row ->
            val id = row["id"] as? String ?: return@mapNotNull null
            val uri = (row["contentUri"] as? String)?.let { runCatching { Uri.parse(it) }.getOrNull() }
                ?.takeIf { it.scheme == ContentResolver.SCHEME_CONTENT } ?: return@mapNotNull null
            RequestedPhoto(id, uri)
        }
        if (photos.isEmpty() || photos.size > MAXIMUM_REQUEST_SIZE) {
            result.success(status(unavailableIds = raw?.mapNotNull { it["id"] as? String } ?: emptyList()))
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            requestConfirmedDelete(photos, result)
        } else {
            deleteLegacy(photos, result)
        }
    }

    private fun requestConfirmedDelete(photos: List<RequestedPhoto>, result: MethodChannel.Result) {
        try {
            val request = MediaStore.createDeleteRequest(contentResolver, photos.map { it.uri })
            pendingResult = result
            pendingPhotos = photos
            activity.startIntentSenderForResult(request.intentSender, REQUEST_CODE, null, 0, 0, 0)
        } catch (_: SecurityException) {
            result.success(status(unavailableIds = photos.map { it.id }))
        } catch (_: Exception) {
            result.success(status(unavailableIds = photos.map { it.id }))
        }
    }

    private fun deleteLegacy(photos: List<RequestedPhoto>, result: MethodChannel.Result) {
        val deleted = mutableListOf<String>()
        val unavailable = mutableListOf<String>()
        photos.forEach { photo ->
            try {
                if (contentResolver.delete(photo.uri, null, null) > 0) deleted += photo.id
                else unavailable += photo.id
            } catch (_: SecurityException) {
                unavailable += photo.id
            } catch (_: Exception) {
                unavailable += photo.id
            }
        }
        result.success(status(deleted, unavailable))
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE || pendingResult == null) return false
        val result = pendingResult!!
        val photos = pendingPhotos
        pendingResult = null
        pendingPhotos = emptyList()
        if (resultCode != Activity.RESULT_OK) {
            result.success(status(cancelled = true))
            return true
        }
        val deleted = mutableListOf<String>()
        val unavailable = mutableListOf<String>()
        photos.forEach { photo ->
            if (exists(photo.uri)) unavailable += photo.id else deleted += photo.id
        }
        result.success(status(deleted, unavailable))
        return true
    }

    fun dispose() {
        pendingResult?.success(status(unavailableIds = pendingPhotos.map { it.id }))
        pendingResult = null
        pendingPhotos = emptyList()
    }

    private fun exists(uri: Uri): Boolean = try {
        contentResolver.query(uri, arrayOf(MediaStore.MediaColumns._ID), null, null, null)
            ?.use { it.moveToFirst() } ?: false
    } catch (_: Exception) {
        true
    }

    private fun status(
        deletedIds: List<String> = emptyList(),
        unavailableIds: List<String> = emptyList(),
        cancelled: Boolean = false,
    ): Map<String, Any> = mapOf(
        "deletedIds" to deletedIds,
        "unavailableIds" to unavailableIds,
        "cancelled" to cancelled,
    )

    companion object {
        private const val REQUEST_CODE = 7843
        private const val MAXIMUM_REQUEST_SIZE = 2000
    }
}
