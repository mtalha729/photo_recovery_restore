package com.photorecoveryrestore.app

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

class MediaAccessCoordinator(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private val preferences = activity.getSharedPreferences("media_access", 0)

    fun state(): Map<String, Any> = mapOf(
        "status" to currentStatus(),
        "apiLevel" to Build.VERSION.SDK_INT,
    )

    fun request(intent: String?, result: MethodChannel.Result) {
        if (pending != null) {
            result.success(state())
            return
        }
        val permissions = permissionsFor(intent)
        if (permissions.isEmpty() || currentStatus() == "fullAccess") {
            result.success(state())
            return
        }
        pending = result
        preferences.edit().putBoolean("requested", true).apply()
        activity.requestPermissions(permissions, REQUEST_CODE)
    }

    private fun permissionsFor(intent: String?): Array<String> {
        if (Build.VERSION.SDK_INT < 34) return requiredPermissions()
        return when (intent) {
            "changeSelectedPhotos" -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            )
            // Request both in one system dialog so Android can report a
            // durable selected-photo grant separately from full-library access.
            // The user still chooses the scope; the app cannot force full access.
            else -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            )
        }
    }

    fun openSettings() {
        activity.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", activity.packageName, null)
            },
        )
    }

    fun handleRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pending?.success(state())
        pending = null
        return true
    }

    fun dispose() {
        pending?.success(state())
        pending = null
    }

    private fun currentStatus(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return "notRequired"
        if (Build.VERSION.SDK_INT >= 33 && granted(Manifest.permission.READ_MEDIA_IMAGES)) {
            return "fullAccess"
        }
        if (Build.VERSION.SDK_INT >= 34 &&
            granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
        ) return "limitedSelectedAccess"
        if (Build.VERSION.SDK_INT <= 32 && granted(Manifest.permission.READ_EXTERNAL_STORAGE)) {
            return "fullAccess"
        }
        val permission = requiredPermissions().firstOrNull() ?: return "notRequired"
        return if (preferences.getBoolean("requested", false) &&
            !activity.shouldShowRequestPermissionRationale(permission)
        ) "settingsRequired" else "denied"
    }

    private fun requiredPermissions(): Array<String> = when {
        Build.VERSION.SDK_INT >= 34 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
        Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
        // Android 8–9 needs the legacy write grant for verified restore. The
        // manifest already scopes it to API 28, so it is never requested later.
        Build.VERSION.SDK_INT <= Build.VERSION_CODES.P -> arrayOf(
            Manifest.permission.READ_EXTERNAL_STORAGE,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
        )
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        else -> emptyArray()
    }

    private fun granted(permission: String) =
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    companion object { private const val REQUEST_CODE = 4812 }
}
