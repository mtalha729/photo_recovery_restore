package com.photorecoveryrestore.app

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class RecoveryShieldSelectionCoordinator(
    private val activity: Activity,
    private val storage: RecoveryShieldStorage,
) {
    private var pending: MethodChannel.Result? = null

    fun select(result: MethodChannel.Result) {
        if (pending != null) {
            result.success(0)
            return
        }
        pending = result
        activity.startActivityForResult(
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                type = "image/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                addCategory(Intent.CATEGORY_OPENABLE)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            },
            REQUEST_CODE,
        )
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending
        pending = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result?.success(0)
            return true
        }
        val uris = buildList {
            data.data?.let(::add)
            data.clipData?.let { clip ->
                for (index in 0 until clip.itemCount) add(clip.getItemAt(index).uri)
            }
        }.distinct()
        var protectedCount = 0
        uris.forEach { uri ->
            try {
                activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: Exception) {
                // The one-time activity grant is still sufficient for this copy operation.
            }
            var displayName: String? = null
            var byteSize: Long? = null
            try {
                activity.contentResolver.query(
                    uri,
                    arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        if (!cursor.isNull(0)) displayName = cursor.getString(0)
                        if (!cursor.isNull(1)) byteSize = cursor.getLong(1)
                    }
                }
            } catch (_: Exception) {
                // Optional picker metadata remains unknown.
            }
            val id = UUID.nameUUIDFromBytes(uri.toString().toByteArray()).toString()
            val response = storage.protect(
                mapOf(
                    "protectionId" to id,
                    "sourceUri" to uri.toString(),
                    "stableSourceIdentity" to "document:$uri",
                    "originalContentUri" to uri.toString(),
                    "source" to "unknown",
                    "displayName" to displayName,
                    "mimeType" to activity.contentResolver.getType(uri),
                    "expectedByteSize" to byteSize,
                ),
            )
            if (response["status"] in setOf("protected", "alreadyProtected", "updated")) protectedCount++
        }
        result?.success(protectedCount)
        return true
    }

    fun dispose() {
        pending?.success(0)
        pending = null
    }

    companion object { private const val REQUEST_CODE = 4813 }
}
