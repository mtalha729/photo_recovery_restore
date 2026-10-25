package com.photorecoveryrestore.app

import android.provider.MediaStore
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.security.MessageDigest
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var systemTrashRestoreCoordinator: SystemTrashRestoreCoordinator? = null
    private var folderTreeSelectionCoordinator: FolderTreeSelectionCoordinator? = null
    private var authorizedFolderMediaQuery: AuthorizedFolderMediaQuery? = null
    private var deepStorageQuery: DeepStorageRecoveryQuery? = null
    private var mediaAccessCoordinator: MediaAccessCoordinator? = null
    private var recoveryShieldSelectionCoordinator: RecoveryShieldSelectionCoordinator? = null
    private var smartCleanupDeletionCoordinator: SmartCleanupDeletionCoordinator? = null
    private val deepStorageExecutor = Executors.newSingleThreadExecutor()
    private val mediaInventoryExecutor = Executors.newSingleThreadExecutor()
    private val thumbnailExecutor = Executors.newFixedThreadPool(2)
    private val cleanupExecutor = Executors.newSingleThreadExecutor()
    private val recoveryShieldExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        systemTrashRestoreCoordinator = SystemTrashRestoreCoordinator(this, contentResolver)
        folderTreeSelectionCoordinator = FolderTreeSelectionCoordinator(this)
        authorizedFolderMediaQuery = AuthorizedFolderMediaQuery(this)
        mediaAccessCoordinator = MediaAccessCoordinator(this)
        smartCleanupDeletionCoordinator = SmartCleanupDeletionCoordinator(this, contentResolver)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SMART_CLEANUP_DIGEST_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "sha256") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val rawUri = call.argument<String>("contentUri")
            val uri = rawUri?.let { runCatching { Uri.parse(it) }.getOrNull() }
                ?.takeIf { it.scheme == "content" }
            if (uri == null) {
                result.success(null)
                return@setMethodCallHandler
            }
            cleanupExecutor.execute {
                val digest = runCatching {
                    contentResolver.openInputStream(uri)?.buffered(64 * 1024)?.use { input ->
                        val hash = MessageDigest.getInstance("SHA-256")
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val read = input.read(buffer)
                            if (read <= 0) break
                            hash.update(buffer, 0, read)
                        }
                        hash.digest().joinToString("") { byte -> "%02x".format(byte) }
                    }
                }.getOrNull()
                runOnUiThread { result.success(digest) }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SMART_CLEANUP_DELETE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "deletePhotos") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val photos = call.argument<List<Map<*, *>>>("photos")
            smartCleanupDeletionCoordinator?.delete(photos, result)
                ?: result.success(mapOf("deletedIds" to emptyList<String>(), "unavailableIds" to emptyList<String>(), "cancelled" to false))
        }
        val deepStorageQuery = DeepStorageRecoveryQuery(this)
        this.deepStorageQuery = deepStorageQuery
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEEP_STORAGE_RECOVERY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCapability" -> result.success(deepStorageQuery.capability())
                "getDeepStoragePage" -> {
                    val pageSize = call.argument<Number>("pageSize")?.toInt()
                    if (pageSize == null || pageSize !in 1..MAXIMUM_PAGE_SIZE) {
                        result.success(failure("platformFailure", "Invalid page size."))
                    } else {
                        val continuationToken = call.argument<String>("continuationToken")
                        val requestGeneration = deepStorageQuery.currentCancellationGeneration()
                        deepStorageExecutor.execute {
                            val response = runCatching {
                                deepStorageQuery.query(
                                    pageSize,
                                    continuationToken,
                                    call.argument<String>("profile") ?: "fastDeep",
                                    requestGeneration,
                                    call.argument<List<String>>("existingStorageLocationKeys")
                                        ?.toSet()
                                        ?: emptySet(),
                                )
                            }.getOrElse { error ->
                                deepStorageQuery.requestCancellation(continuationToken)
                                runCatching {
                                    deepStorageExecutor.execute {
                                        deepStorageQuery.cancel(continuationToken)
                                    }
                                }
                                failure("platformFailure", "Photo recovery scan failed (${error.javaClass.simpleName}).")
                            }
                            runOnUiThread { result.success(response) }
                        }
                    }
                }
                "cancelDeepStorageScan" -> {
                    val token = call.argument<String>("continuationToken")
                    deepStorageQuery.requestCancellation(token)
                    runCatching { deepStorageExecutor.execute { deepStorageQuery.cancel(token) } }
                    result.success(null)
                }
                "openDeepStorageAccessSettings" -> {
                    val capability = deepStorageQuery.capability()
                    if (capability["requestSupported"] != true ||
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.R
                    ) {
                        result.error(
                            "accessNotDeclared",
                            "This app build does not request optional All files access.",
                            null,
                        )
                    } else {
                        val opened = runCatching {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                    Uri.parse("package:$packageName"),
                                ),
                            )
                        }.recoverCatching {
                            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                        }.isSuccess
                        if (opened) result.success(null)
                        else result.error("settingsUnavailable", "Photo Recovery Access settings are unavailable.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_ACCESS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getMediaAccessState" -> result.success(mediaAccessCoordinator?.state())
                "requestMediaAccess" -> mediaAccessCoordinator?.request(
                    call.argument<String>("intent"),
                    result,
                )
                    ?: result.success(mapOf("status" to "unknown", "apiLevel" to android.os.Build.VERSION.SDK_INT))
                "openAppSettings" -> {
                    mediaAccessCoordinator?.openSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        val thumbnailLoader = BoundedThumbnailLoader(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BOUNDED_THUMBNAIL_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "loadThumbnail") {
                // ContentResolver thumbnail reads and sampled file decoding are
                // bounded, but they are still file I/O and must not block the UI.
                thumbnailExecutor.execute {
                    val response = thumbnailLoader.load(call.arguments as? Map<*, *>)
                    runOnUiThread { result.success(response) }
                }
            } else result.notImplemented()
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_STORAGE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "getDeviceStorage") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val stats = android.os.StatFs(android.os.Environment.getDataDirectory().path)
                result.success(
                    mapOf(
                        "totalBytes" to stats.totalBytes,
                        "availableBytes" to stats.availableBytes,
                    ),
                )
            } catch (_: Exception) {
                result.success(null)
            }
        }

        val onboardingPreferences = getSharedPreferences("onboarding", MODE_PRIVATE)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ONBOARDING_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isOnboardingComplete" -> result.success(
                    onboardingPreferences.getBoolean("complete", false),
                )
                "markOnboardingComplete" -> {
                    onboardingPreferences.edit().putBoolean("complete", true).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CURRENT_MEDIA_INVENTORY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "getCurrentMediaPage") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val pageSize = call.argument<Number>("pageSize")?.toInt()
            val afterMediaStoreId = call.argument<Number>("afterMediaStoreId")?.toLong()
            val continuationToken = call.argument<String>("continuationToken")
            if (pageSize == null || pageSize !in 1..MAXIMUM_INVENTORY_PAGE_SIZE) {
                result.success(failure("platformFailure", "Invalid page size."))
                return@setMethodCallHandler
            }

            // MediaStore can contain tens of thousands of records. Keep the
            // bounded page query off Flutter's platform/UI thread.
            mediaInventoryExecutor.execute {
                val response = runCatching {
                    MultiVolumeCurrentMediaQuery(this).query(
                        pageSize,
                        continuationToken,
                        afterMediaStoreId,
                    )
                }.getOrElse {
                    failure("platformFailure", "Unable to query current media.")
                }
                runOnUiThread { result.success(response) }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CURRENT_MEDIA_METADATA_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "getCurrentMediaMetadata") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val mediaStoreId = call.argument<Number>("mediaStoreId")?.toLong()
            if (mediaStoreId == null || mediaStoreId < 0) {
                result.success(failure("platformFailure", "Invalid MediaStore ID."))
                return@setMethodCallHandler
            }
            val volumeName = call.argument<String>("storageVolumeName")
            val contentUri = call.argument<String>("contentUri")
            mediaInventoryExecutor.execute {
                val response = runCatching {
                    CurrentMediaMetadataQuery(contentResolver).query(
                        mediaStoreId,
                        volumeName,
                        contentUri,
                    )
                }.getOrElse {
                    failure("platformFailure", "Unable to query current-media metadata.")
                }
                runOnUiThread { result.success(response) }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FOLDER_SCOPE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "selectFolder" -> folderTreeSelectionCoordinator?.selectFolder(result)
                    ?: result.success(failure("platformFailure", "Folder selection is unavailable."))
                "selectDestinationFolder" ->
                    folderTreeSelectionCoordinator?.selectDestinationFolder(result)
                        ?: result.success(failure("platformFailure", "Folder selection is unavailable."))
                "checkFolderGrant" -> folderTreeSelectionCoordinator?.checkGrant(
                    call.argument<String>("treeUri"),
                    result,
                ) ?: result.success(failure("platformFailure", "Folder permission is unavailable."))
                "getAuthorizedFolderMediaPage" -> {
                    val pageSize = call.argument<Number>("pageSize")?.toInt()
                    if (pageSize == null || pageSize !in 1..MAXIMUM_PAGE_SIZE) {
                        result.success(failure("platformFailure", "Invalid folder page size."))
                    } else {
                        val query = authorizedFolderMediaQuery
                        val treeUri = call.argument<String>("treeUri")
                        val continuationToken = call.argument<String>("continuationToken")
                        val requestGeneration = query?.currentCancellationGeneration()
                        deepStorageExecutor.execute {
                            val response = query?.query(
                                treeUri,
                                pageSize,
                                continuationToken,
                                requestGeneration ?: 0L,
                            ) ?: failure("platformFailure", "Folder scanning is unavailable.")
                            runOnUiThread { result.success(response) }
                        }
                    }
                }
                "cancelAuthorizedFolderScan" -> {
                    val token = call.argument<String>("continuationToken")
                    val query = authorizedFolderMediaQuery
                    query?.requestCancellation(token)
                    if (query != null) {
                        runCatching { deepStorageExecutor.execute { query.cancel(token) } }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VERIFIED_TRASH_DISCOVERY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "getVerifiedTrashPage") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val pageSize = call.argument<Number>("pageSize")?.toInt()
            val afterMediaStoreId = call.argument<Number>("afterMediaStoreId")?.toLong()
            val continuationToken = call.argument<String>("continuationToken")
            if (pageSize == null || pageSize !in 1..MAXIMUM_PAGE_SIZE) {
                result.success(failure("platformFailure", "Invalid page size."))
                return@setMethodCallHandler
            }
            deepStorageExecutor.execute {
                val response = runCatching {
                    VerifiedTrashQuery(this).query(
                        pageSize,
                        continuationToken,
                        afterMediaStoreId,
                    )
                }.getOrElse {
                    failure("platformFailure", "Unable to query verified media trash.")
                }
                runOnUiThread { result.success(response) }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SYSTEM_TRASH_RESTORE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "restoreSystemTrashBatch") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            systemTrashRestoreCoordinator?.restore(
                call.argument<List<String>>("uris"),
                result,
            ) ?: result.success(failure("platformFailure", "Restore is unavailable."))
        }

        val fileCopyRestorer = DeepFileCopyRestorer(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FILE_COPY_RESTORE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "restoreFileCopy") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            deepStorageExecutor.execute {
                val response = fileCopyRestorer.restore(call.arguments as? Map<*, *>)
                runOnUiThread { result.success(response) }
            }
        }

        val recoveryShieldStorage = RecoveryShieldStorage(this)
        recoveryShieldSelectionCoordinator = RecoveryShieldSelectionCoordinator(
            this,
            recoveryShieldStorage,
            recoveryShieldExecutor,
        )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RECOVERY_SHIELD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "protectItem") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            recoveryShieldExecutor.execute {
                val response = runCatching {
                    recoveryShieldStorage.protect(call.arguments as? Map<*, *>)
                }.getOrElse {
                    mapOf(
                        "status" to "platformFailure",
                        "message" to "Unable to protect the selected copy.",
                    )
                }
                runOnUiThread { result.success(response) }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RECOVERY_SHIELD_MANAGEMENT_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getShieldItems" -> recoveryShieldExecutor.execute {
                    val items = try {
                        recoveryShieldStorage.items()
                    } catch (_: Exception) {
                        runOnUiThread {
                            result.error(
                                "shieldStorageFailure",
                                "Unable to load Recovery Shield records.",
                                null,
                            )
                        }
                        return@execute
                    }
                    runOnUiThread { result.success(items) }
                }
                "protectSelectedPhotos" -> recoveryShieldSelectionCoordinator?.select(result)
                    ?: result.success(0)
                "unprotectItems" -> {
                    val protectionIds = call.argument<List<String>>("protectionIds") ?: emptyList()
                    recoveryShieldExecutor.execute {
                        val removed = runCatching {
                            recoveryShieldStorage.unprotect(protectionIds)
                        }.getOrDefault(false)
                        runOnUiThread { result.success(removed) }
                    }
                }
                "clearShield" -> recoveryShieldExecutor.execute {
                    val cleared = runCatching { recoveryShieldStorage.clear() }.getOrDefault(false)
                    runOnUiThread { result.success(cleared) }
                }
                else -> result.notImplemented()
            }
        }

        val settingsPreferences = getSharedPreferences("app_settings", MODE_PRIVATE)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SETTINGS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> result.success(
                    mapOf(
                        "themeMode" to settingsPreferences.getString("themeMode", "system"),
                        "reduceMotion" to settingsPreferences.getBoolean("reduceMotion", false),
                    ),
                )
                "save" -> {
                    settingsPreferences.edit()
                        .putString("themeMode", call.argument<String>("themeMode") ?: "system")
                        .putBoolean("reduceMotion", call.argument<Boolean>("reduceMotion") ?: false)
                        .apply()
                    result.success(null)
                }
                "authorizedFolders" -> result.success(
                    contentResolver.persistedUriPermissions
                        .filter { it.isReadPermission }
                        .map { it.uri.toString() },
                )
                "appVersion" -> result.success(
                    packageManager.getPackageInfo(packageName, 0).versionName ?: "Unavailable",
                )
                else -> result.notImplemented()
            }
        }

        val recoveredPhotosPreferences = getSharedPreferences("recovered_photo_history", MODE_PRIVATE)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RECOVERED_PHOTOS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "loadHistory" -> result.success(loadRecoveredPhotoHistory(recoveredPhotosPreferences))
                "upsertHistory" -> {
                    val raw = call.arguments as? Map<*, *>
                    val contentUri = raw?.get("contentUri") as? String
                    val parsedUri = contentUri?.let { runCatching { Uri.parse(it) }.getOrNull() }
                    if (raw == null || parsedUri?.scheme != "content") {
                        result.error("invalidHistoryRecord", "A restored content URI is required.", null)
                    } else {
                        val records = loadRecoveredPhotoHistory(recoveredPhotosPreferences)
                            .associateBy { it["contentUri"] as String }
                            .toMutableMap()
                        records[contentUri] = mapOf(
                            "id" to (raw["id"] as? String ?: contentUri),
                            "contentUri" to contentUri,
                            "restoredAtMillis" to ((raw["restoredAtMillis"] as? Number)?.toLong() ?: System.currentTimeMillis()),
                            "displayName" to (raw["displayName"] as? String),
                            "mimeType" to (raw["mimeType"] as? String),
                            "source" to (raw["source"] as? String),
                        )
                        saveRecoveredPhotoHistory(recoveredPhotosPreferences, records.values.toList())
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        val recoveryShieldRestorer = RecoveryShieldRestorer(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RECOVERY_SHIELD_RESTORE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "restoreProtectedCopy") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            recoveryShieldExecutor.execute {
                val response = runCatching {
                    recoveryShieldRestorer.restore(call.arguments as? Map<*, *>)
                }.getOrElse {
                    mapOf(
                        "status" to "platformFailure",
                        "message" to "Unable to restore protected media.",
                    )
                }
                runOnUiThread { result.success(response) }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (recoveryShieldSelectionCoordinator?.handleActivityResult(requestCode, resultCode, data) == true) return
        if (folderTreeSelectionCoordinator?.handleActivityResult(requestCode, resultCode, data) == true) return
        if (smartCleanupDeletionCoordinator?.handleActivityResult(requestCode, resultCode) == true) return
        if (systemTrashRestoreCoordinator?.handleActivityResult(requestCode, resultCode) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (mediaAccessCoordinator?.handleRequestPermissionsResult(requestCode) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        systemTrashRestoreCoordinator?.dispose()
        systemTrashRestoreCoordinator = null
        folderTreeSelectionCoordinator?.dispose()
        folderTreeSelectionCoordinator = null
        val folderMediaQuery = authorizedFolderMediaQuery
        val storageQuery = deepStorageQuery
        folderMediaQuery?.requestCancellation(null)
        storageQuery?.requestCancellation(null)
        if (folderMediaQuery != null || storageQuery != null) {
            runCatching {
                deepStorageExecutor.execute {
                    folderMediaQuery?.cancel(null)
                    storageQuery?.cancel(null)
                }
            }
        }
        authorizedFolderMediaQuery = null
        deepStorageQuery = null
        mediaAccessCoordinator?.dispose()
        mediaAccessCoordinator = null
        recoveryShieldSelectionCoordinator?.dispose()
        recoveryShieldSelectionCoordinator = null
        // Allow the queued cursor cleanup to run after an active page observes
        // the cancellation request; the executor is still shut down promptly.
        deepStorageExecutor.shutdown()
        mediaInventoryExecutor.shutdownNow()
        thumbnailExecutor.shutdownNow()
        cleanupExecutor.shutdownNow()
        recoveryShieldExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun loadRecoveredPhotoHistory(
        preferences: android.content.SharedPreferences,
    ): List<Map<String, Any?>> = runCatching {
        val raw = preferences.getString("items", "[]") ?: "[]"
        val rows = JSONArray(raw)
        buildList {
            for (index in 0 until rows.length()) {
                val row = rows.optJSONObject(index) ?: continue
                val uri = row.optString("contentUri").takeIf { it.isNotBlank() } ?: continue
                val parsed = runCatching { Uri.parse(uri) }.getOrNull()
                if (parsed?.scheme != "content") continue
                add(
                    mapOf(
                        "id" to row.optString("id", uri),
                        "contentUri" to uri,
                        "restoredAtMillis" to row.optLong("restoredAtMillis", 0L),
                        "displayName" to row.optString("displayName").takeIf { it.isNotBlank() },
                        "mimeType" to row.optString("mimeType").takeIf { it.isNotBlank() },
                        "source" to row.optString("source").takeIf { it.isNotBlank() },
                    ),
                )
            }
        }.sortedByDescending { it["restoredAtMillis"] as Long }
    }.getOrDefault(emptyList())

    private fun saveRecoveredPhotoHistory(
        preferences: android.content.SharedPreferences,
        records: List<Map<String, Any?>>,
    ) {
        val serialized = JSONArray().apply {
            records.sortedByDescending { (it["restoredAtMillis"] as? Long) ?: 0L }
                .take(MAXIMUM_RECOVERED_PHOTO_HISTORY)
                .forEach { record ->
                    put(JSONObject().apply {
                        record.forEach { (key, value) -> if (value != null) put(key, value) }
                    })
                }
        }
        preferences.edit().putString("items", serialized.toString()).apply()
    }
    private fun queryCurrentImages(pageSize: Int, afterMediaStoreId: Long?): Map<String, Any?> {
        val items = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.MIME_TYPE,
        )
        val selection = afterMediaStoreId?.let { "${MediaStore.Images.Media._ID} > ?" }
        val selectionArgs = afterMediaStoreId?.let { arrayOf(it.toString()) }

        return try {
            val cursor = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val queryArguments = android.os.Bundle().apply {
                    putStringArray(
                        android.content.ContentResolver.QUERY_ARG_SORT_COLUMNS,
                        arrayOf(MediaStore.Images.Media._ID),
                    )
                    putInt(
                        android.content.ContentResolver.QUERY_ARG_SORT_DIRECTION,
                        android.content.ContentResolver.QUERY_SORT_DIRECTION_ASCENDING,
                    )
                    putInt(android.content.ContentResolver.QUERY_ARG_LIMIT, pageSize + 1)
                    if (selection != null) {
                        putString(android.content.ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                        putStringArray(
                            android.content.ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS,
                            selectionArgs,
                        )
                    }
                }
                contentResolver.query(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    projection,
                    queryArguments,
                    null,
                )
            } else {
                // API 24–25 has no query-argument limit. Stop reading after one page;
                // items are still returned to Dart in bounded pages.
                contentResolver.query(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
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
                        "contentUri" to MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                            .buildUpon()
                            .appendPath(id.toString())
                            .build()
                            .toString(),
                        "displayName" to it.getStringOrNull(1),
                        "mimeType" to it.getStringOrNull(2),
                    )
                }

                val hasMore = items.size > pageSize
                if (hasMore) items.removeAt(items.lastIndex)
                success(
                    items,
                    if (hasMore) items.lastOrNull()?.get("mediaStoreId") as? Long else null,
                )
            } ?: success(emptyList(), null)
        } catch (_: SecurityException) {
            failure("securityDenied", "Media access is unavailable.")
        } catch (exception: Exception) {
            failure(
                "platformFailure",
                "MediaStore image query failed (${exception.javaClass.simpleName}).",
            )
        }
    }

    private fun success(items: List<Map<String, Any?>>, nextAfterMediaStoreId: Long?): Map<String, Any?> {
        return mapOf(
            "status" to "success",
            "items" to items,
            "nextAfterMediaStoreId" to nextAfterMediaStoreId,
        )
    }

    private fun failure(code: String, message: String): Map<String, Any?> {
        return mapOf("status" to "failure", "code" to code, "message" to message)
    }

    private fun android.database.Cursor.getStringOrNull(index: Int): String? {
        return if (isNull(index)) null else getString(index)
    }

    companion object {
        private const val SMART_CLEANUP_DIGEST_CHANNEL =
            "com.photorecoveryrestore.app/smart_cleanup_digest"
        private const val SMART_CLEANUP_DELETE_CHANNEL =
            "com.photorecoveryrestore.app/smart_cleanup_delete"
        private const val CURRENT_MEDIA_INVENTORY_CHANNEL =
            "com.photorecoveryrestore.app/current_media_inventory"
        private const val CURRENT_MEDIA_METADATA_CHANNEL =
            "com.photorecoveryrestore.app/current_media_metadata"
        private const val VERIFIED_TRASH_DISCOVERY_CHANNEL =
            "com.photorecoveryrestore.app/verified_trash_discovery"
        private const val SYSTEM_TRASH_RESTORE_CHANNEL =
            "com.photorecoveryrestore.app/system_trash_restore"
        private const val RECOVERY_SHIELD_CHANNEL =
            "com.photorecoveryrestore.app/recovery_shield"
        private const val RECOVERY_SHIELD_RESTORE_CHANNEL =
            "com.photorecoveryrestore.app/recovery_shield_restore"
        private const val RECOVERED_PHOTOS_CHANNEL =
            "com.photorecoveryrestore.app/recovered_photos"
        private const val MAXIMUM_PAGE_SIZE = 200
        private const val FOLDER_SCOPE_CHANNEL = "com.photorecoveryrestore.app/folder_scope"
        private const val MAXIMUM_INVENTORY_PAGE_SIZE = 500
        private const val MAXIMUM_RECOVERED_PHOTO_HISTORY = 500
        private const val MEDIA_ACCESS_CHANNEL =
            "com.photorecoveryrestore.app/media_access"
        private const val BOUNDED_THUMBNAIL_CHANNEL =
            "com.photorecoveryrestore.app/bounded_thumbnail"
        private const val DEVICE_STORAGE_CHANNEL =
            "com.photorecoveryrestore.app/device_storage"
        private const val ONBOARDING_CHANNEL =
            "com.photorecoveryrestore.app/onboarding"
        private const val RECOVERY_SHIELD_MANAGEMENT_CHANNEL =
            "com.photorecoveryrestore.app/recovery_shield_management"
        private const val SETTINGS_CHANNEL =
            "com.photorecoveryrestore.app/settings"
        private const val FILE_COPY_RESTORE_CHANNEL =
            "com.photorecoveryrestore.app/file_copy_restore"
        private const val DEEP_STORAGE_RECOVERY_CHANNEL =
            "com.photorecoveryrestore.app/deep_storage_recovery"
    }
}
