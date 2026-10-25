package com.photorecoveryrestore.app

import android.app.Activity
import android.content.ContentResolver
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel

class SystemTrashRestoreCoordinator(
    private val activity: Activity,
    private val contentResolver: ContentResolver,
) {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingUris: List<Uri> = emptyList()

    fun restore(rawUris: List<String>?, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.success(status("unsupportedPlatform"))
            return
        }
        if (pendingResult != null) {
            result.success(status("operationInProgress"))
            return
        }
        if (rawUris.isNullOrEmpty() || rawUris.size > MAXIMUM_REQUEST_SIZE) {
            result.success(status("platformFailure", "Invalid restore batch size."))
            return
        }

        val uris = rawUris.mapNotNull { value ->
            runCatching { Uri.parse(value) }
                .getOrNull()
                ?.takeIf { it.scheme == ContentResolver.SCHEME_CONTENT }
        }
        if (uris.size != rawUris.size) {
            result.success(status("staleOrMissingMediaItem", "Invalid media URI."))
            return
        }

        try {
            val staleUris = uris.filter { trashState(it) != true }
            if (staleUris.isNotEmpty()) {
                result.success(
                    status(
                        "staleOrMissingMediaItem",
                        "One or more media items are no longer in system trash.",
                        unverifiedUris = staleUris,
                    ),
                )
                return
            }

            val pendingIntent = MediaStore.createTrashRequest(
                contentResolver,
                uris,
                false,
            )
            pendingResult = result
            pendingUris = uris
            activity.startIntentSenderForResult(
                pendingIntent.intentSender,
                REQUEST_CODE,
                null,
                0,
                0,
                0,
            )
        } catch (_: SecurityException) {
            clearPending()
            result.success(status("accessFailure", "Media trash access is unavailable."))
        } catch (_: Exception) {
            clearPending()
            result.success(status("platformFailure", "Unable to prepare restore request."))
        }
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE || pendingResult == null) return false

        val result = pendingResult!!
        val uris = pendingUris
        clearPending()

        if (resultCode != Activity.RESULT_OK) {
            result.success(status("userDeniedOrCancelled"))
            return true
        }

        try {
            val unverifiedUris = uris.filter {
                trashState(it) != false || !isReadable(it)
            }
            if (unverifiedUris.isNotEmpty()) {
                result.success(
                    status(
                        "verificationFailed",
                        "System approval did not produce a verified restored state.",
                        unverifiedUris = unverifiedUris,
                    ),
                )
            } else {
                result.success(status("restored", affectedUris = uris))
            }
        } catch (_: SecurityException) {
            result.success(status("accessFailure", "Unable to verify restored media."))
        } catch (_: Exception) {
            result.success(status("verificationFailed", "Unable to verify restored media."))
        }
        return true
    }

    fun dispose() {
        pendingResult?.success(
            status("platformFailure", "Restore operation ended with the activity lifecycle."),
        )
        clearPending()
    }

    private fun trashState(uri: Uri): Boolean? {
        val queryArguments = Bundle().apply {
            putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_INCLUDE)
        }
        return contentResolver.query(
            uri,
            arrayOf(MediaStore.MediaColumns.IS_TRASHED),
            queryArguments,
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst() || cursor.isNull(0)) {
                null
            } else {
                cursor.getInt(0) == 1
            }
        }
    }

    private fun isReadable(uri: Uri): Boolean = runCatching {
        contentResolver.openInputStream(uri)?.use { it.read() >= 0 } == true
    }.getOrDefault(false)

    private fun status(
        value: String,
        message: String? = null,
        affectedUris: List<Uri> = emptyList(),
        unverifiedUris: List<Uri> = emptyList(),
    ): Map<String, Any?> {
        return mapOf(
            "status" to value,
            "message" to message,
            "affectedUris" to affectedUris.map(Uri::toString),
            "unverifiedUris" to unverifiedUris.map(Uri::toString),
        )
    }

    private fun clearPending() {
        pendingResult = null
        pendingUris = emptyList()
    }

    companion object {
        private const val REQUEST_CODE = 7842
        private const val MAXIMUM_REQUEST_SIZE = 2000
    }
}
