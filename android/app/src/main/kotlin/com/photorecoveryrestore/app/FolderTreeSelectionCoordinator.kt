package com.photorecoveryrestore.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodChannel

class FolderTreeSelectionCoordinator(private val activity: Activity) {
    private var pendingResult: MethodChannel.Result? = null

    fun selectFolder(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.success(response("operationInProgress", "Folder selection is already active."))
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (_: Exception) {
            pendingResult = null
            result.success(response("platformFailure", "Folder selection is unavailable."))
        }
    }

    fun checkGrant(treeUriText: String?, result: MethodChannel.Result) {
        val treeUri = treeUriText?.let(Uri::parse)
        if (treeUri == null) {
            result.success(response("platformFailure", "Invalid folder tree URI."))
            return
        }
        val active = activity.contentResolver.persistedUriPermissions.any {
            it.uri == treeUri && it.isReadPermission
        }
        result.success(
            if (active) selectedResponse(treeUri)
            else response("permissionGrantLost", "The saved folder permission is no longer active."),
        )
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingResult ?: return true
        pendingResult = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(response("cancelled", null))
            return true
        }
        val treeUri = data?.data
        if (treeUri == null) {
            result.success(response("platformFailure", "No folder URI was returned."))
            return true
        }
        val documentId = runCatching { DocumentsContract.getTreeDocumentId(treeUri) }.getOrNull()
        if (documentId == null) {
            result.success(response("platformFailure", "The folder URI is malformed."))
            return true
        }
        if (isRestricted(documentId)) {
            result.success(response("restrictedLocation", "Android does not permit this folder scope."))
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            result.success(selectedResponse(treeUri))
        } catch (_: SecurityException) {
            result.success(response("accessUnavailable", "The folder grant could not be persisted."))
        } catch (_: Exception) {
            result.success(response("platformFailure", "Unable to save the folder grant."))
        }
        return true
    }

    fun dispose() {
        pendingResult?.success(response("platformFailure", "Folder selection was interrupted."))
        pendingResult = null
    }

    private fun selectedResponse(treeUri: Uri): Map<String, Any?> {
        val documentId = runCatching { DocumentsContract.getTreeDocumentId(treeUri) }.getOrNull()
            ?: return response("platformFailure", "The folder URI is malformed.")
        val separator = documentId.indexOf(':')
        val volumeId = if (separator >= 0) documentId.substring(0, separator) else documentId
        val relativePath = if (separator >= 0) documentId.substring(separator + 1).trim('/') else null
        val volume = resolveVolume(volumeId)
        return mapOf(
            "status" to "selected",
            "treeUri" to treeUri.toString(),
            "documentId" to documentId,
            "volumeName" to volume?.first,
            "isRemovable" to volume?.second,
            "relativePath" to relativePath?.takeIf { it.isNotEmpty() },
        )
    }

    private fun resolveVolume(volumeId: String): Pair<String, Boolean>? {
        if (volumeId.equals("primary", ignoreCase = true)) return "external_primary" to false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val manager = activity.getSystemService(StorageManager::class.java)
        return manager.storageVolumes.firstNotNullOfOrNull { volume ->
            val name = volume.mediaStoreVolumeName
            if (name != null && (name.equals(volumeId, true) || volume.uuid.equals(volumeId, true))) {
                name to volume.isRemovable
            } else null
        }
    }

    private fun isRestricted(documentId: String): Boolean {
        val separator = documentId.indexOf(':')
        val path = if (separator >= 0) documentId.substring(separator + 1).trim('/') else ""
        if (path.isEmpty()) return true
        val normalized = path.lowercase()
        return normalized == "download" ||
            normalized == "downloads" ||
            normalized == "android/data" ||
            normalized.startsWith("android/data/") ||
            normalized == "android/obb" ||
            normalized.startsWith("android/obb/")
    }

    private fun response(status: String, message: String?): Map<String, Any?> =
        mapOf("status" to status, "message" to message)

    companion object {
        private const val REQUEST_CODE = 48212
    }
}
