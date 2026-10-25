package com.photorecoveryrestore.app

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.MediaStore
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.security.MessageDigest

class RecoveryShieldRestorer(private val context: Context) {
    private val signatureInspector = ImageSignatureInspector(context.contentResolver)

    fun restore(arguments: Map<*, *>?): Map<String, Any?> {
        val request = arguments
            ?: return result("notEligible", null, "Invalid protected-copy metadata.")
        val protectionId = request["protectionId"] as? String
        val copyPath = request["protectedCopyLocation"] as? String
        val expectedDigest = (request["sha256Digest"] as? String)?.lowercase()
        val expectedSize = (request["expectedByteSize"] as? Number)?.toLong()
        if (protectionId.isNullOrBlank() || copyPath.isNullOrBlank() || expectedDigest.isNullOrBlank() || expectedSize == null || expectedSize < 0) {
            return result("notEligible", protectionId, "Invalid protected-copy metadata.")
        }

        val shieldRoot = runCatching { File(context.noBackupFilesDir, SHIELD_DIRECTORY).canonicalFile }
            .getOrElse { return result("platformFailure", protectionId, "Shield storage is unavailable.") }
        val protectedCopy = runCatching { File(copyPath).canonicalFile }
            .getOrElse { return result("protectedCopyMissing", protectionId, "Protected copy is unavailable.") }
        if (!protectedCopy.path.startsWith(shieldRoot.path + File.separator) || !protectedCopy.isFile) {
            return result("protectedCopyMissing", protectionId, "Protected copy is unavailable.")
        }
        if (protectedCopy.length() != expectedSize || digest(protectedCopy) != expectedDigest) {
            return result("integrityFailure", protectionId, "Protected-copy integrity check failed.")
        }
        val signature = signatureInspector.inspect(protectedCopy)
        if ((signature.state != "valid" && signature.state != "unsupported") ||
            signature.format.isNullOrBlank() ||
            signature.mimeType?.startsWith("image/") != true
        ) {
            return result("integrityFailure", protectionId, "Protected bytes are not a validated image.")
        }
        val mimeType = signature.mimeType
            ?: return result("integrityFailure", protectionId, "Protected image format is unknown.")
        val originalUri = (request["originalContentUri"] as? String)
            ?.let { runCatching { Uri.parse(it) }.getOrNull() }
            ?.takeIf { it.scheme == "content" }
        if (originalUri != null && matchesBytes(originalUri, expectedSize, expectedDigest)) {
            return result(
                "alreadyPresent",
                protectionId,
                "A byte-identical original is already available. No new copy was saved.",
            )
        }

        val treeUriText = request["destinationTreeUri"] as? String
        if (!treeUriText.isNullOrBlank()) {
            val treeUri = runCatching { Uri.parse(treeUriText) }.getOrNull()
                ?.takeIf { it.scheme == "content" && !it.authority.isNullOrBlank() }
                ?: return result("notEligible", protectionId, "Invalid selected destination folder.")
            val hasPersistedWriteGrant = context.contentResolver.persistedUriPermissions.any {
                it.uri == treeUri && it.isReadPermission && it.isWritePermission
            }
            if (!hasPersistedWriteGrant) {
                return result("accessRequired", protectionId, "Selected destination access is unavailable.")
            }
            return restoreToTree(
                protectionId,
                protectedCopy,
                expectedDigest,
                expectedSize,
                mimeType,
                treeUri,
                request,
            )
        }
        return restoreToMediaStore(
            protectionId,
            protectedCopy,
            expectedDigest,
            expectedSize,
            mimeType,
            request,
        )
    }

    private fun restoreToMediaStore(
        protectionId: String,
        protectedCopy: File,
        expectedDigest: String,
        expectedSize: Long,
        mimeType: String,
        arguments: Map<*, *>,
    ): Map<String, Any?> {
        val resolver = context.contentResolver
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return result(
                "accessRequired",
                protectionId,
                "Shared-media write access is required to restore on this Android version.",
            )
        }
        val usesPending = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, safeName(arguments["displayName"] as? String, mimeType))
            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            (arguments["dateTakenMillis"] as? Number)?.toLong()?.let { put(MediaStore.Images.Media.DATE_TAKEN, it) }
            (arguments["dateModifiedMillis"] as? Number)?.toLong()?.let { put(MediaStore.Images.Media.DATE_MODIFIED, it / 1000L) }
            if (usesPending) {
                put(MediaStore.Images.Media.RELATIVE_PATH, arguments["relativeDestination"] as? String)
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }
        var destination: Uri? = null
        return try {
            val created = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: return result("writeFailure", protectionId, "Unable to create shared-media destination.")
            destination = created
            val writtenDigest = copyToUri(protectedCopy, created)
            if (writtenDigest != expectedDigest || !destinationBytesMatch(created, expectedSize, expectedDigest) ||
                !isRecognizedImage(signatureInspector.inspect(created))
            ) {
                val removed = runCatching { resolver.delete(created, null, null) > 0 }
                    .getOrDefault(false)
                return result(
                    "verificationFailure",
                    protectionId,
                    if (removed) {
                        "Restored media verification failed; the incomplete output was removed."
                    } else {
                        "Restored media verification failed; an incomplete output may remain in the destination."
                    },
                )
            }
            if (usesPending) {
                val publish = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
                if (resolver.update(created, publish, null, null) != 1) {
                    resolver.delete(created, null, null)
                    return result("writeFailure", protectionId, "Unable to publish restored media.")
                }
            }
            success(protectionId, created, usesPending)
        } catch (_: SecurityException) {
            destination?.let { runCatching { resolver.delete(it, null, null) } }
            result(
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) "accessRequired" else "writeFailure",
                protectionId,
                "Shared-media write access is unavailable.",
            )
        } catch (_: FileNotFoundException) {
            destination?.let { runCatching { resolver.delete(it, null, null) } }
            result("writeFailure", protectionId, "Shared-media destination is unavailable.")
        } catch (error: IOException) {
            destination?.let { runCatching { resolver.delete(it, null, null) } }
            result(if (isNoSpace(error)) "insufficientStorage" else "writeFailure", protectionId, "Unable to write restored media.")
        } catch (_: Exception) {
            destination?.let { runCatching { resolver.delete(it, null, null) } }
            result("platformFailure", protectionId, "Unable to restore protected media.")
        }
    }

    private fun restoreToTree(
        protectionId: String,
        protectedCopy: File,
        expectedDigest: String,
        expectedSize: Long,
        mimeType: String,
        treeUri: Uri,
        arguments: Map<*, *>,
    ): Map<String, Any?> {
        val resolver = context.contentResolver
        var destination: Uri? = null
        return try {
            val treeDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
            val parent = DocumentsContract.buildDocumentUriUsingTree(treeUri, treeDocumentId)
            val created = DocumentsContract.createDocument(
                resolver,
                parent,
                mimeType,
                safeName(arguments["displayName"] as? String, mimeType),
            ) ?: return result("writeFailure", protectionId, "Unable to create selected destination.")
            destination = created
            val writtenDigest = copyToUri(protectedCopy, created)
            if (writtenDigest != expectedDigest || !destinationBytesMatch(created, expectedSize, expectedDigest) ||
                !isRecognizedImage(signatureInspector.inspect(created))
            ) {
                val removed = runCatching {
                    DocumentsContract.deleteDocument(resolver, created)
                }.getOrDefault(false)
                return result(
                    "verificationFailure",
                    protectionId,
                    if (removed) {
                        "Restored media verification failed; the incomplete output was removed."
                    } else {
                        "Restored media verification failed; an incomplete output may remain in the selected folder."
                    },
                )
            }
            success(protectionId, created, false)
        } catch (_: SecurityException) {
            destination?.let { runCatching { DocumentsContract.deleteDocument(resolver, it) } }
            result("accessRequired", protectionId, "Selected destination access is unavailable.")
        } catch (error: IOException) {
            destination?.let { runCatching { DocumentsContract.deleteDocument(resolver, it) } }
            result(if (isNoSpace(error)) "insufficientStorage" else "writeFailure", protectionId, "Unable to write selected destination.")
        } catch (_: Exception) {
            destination?.let { runCatching { DocumentsContract.deleteDocument(resolver, it) } }
            result("platformFailure", protectionId, "Unable to restore to selected destination.")
        }
    }

    private fun copyToUri(source: File, destination: Uri): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val destinationStream = context.contentResolver.openOutputStream(destination, "w")
            ?: throw IOException("Destination stream is unavailable.")
        destinationStream.buffered().use { output ->
            source.inputStream().buffered().use { input ->
                val buffer = ByteArray(COPY_BUFFER_SIZE)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    output.write(buffer, 0, count)
                    digest.update(buffer, 0, count)
                }
                output.flush()
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun destinationBytesMatch(
        uri: Uri,
        expectedSize: Long,
        expectedDigest: String,
    ): Boolean {
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            var byteCount = 0L
            context.contentResolver.openInputStream(uri)?.use { input ->
                val buffer = ByteArray(COPY_BUFFER_SIZE)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    byteCount += count
                    if (byteCount > expectedSize) return false
                    digest.update(buffer, 0, count)
                }
            } ?: return false
            byteCount == expectedSize &&
                digest.digest().joinToString("") { "%02x".format(it) } == expectedDigest
        } catch (_: Exception) {
            false
        }
    }

    private fun isRecognizedImage(signature: ImageSignatureResult): Boolean =
        (signature.state == "valid" || signature.state == "unsupported") &&
            !signature.format.isNullOrBlank() &&
            signature.mimeType?.startsWith("image/") == true

    private fun matchesBytes(uri: Uri, expectedSize: Long, expectedDigest: String): Boolean {
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            var byteCount = 0L
            context.contentResolver.openInputStream(uri)?.use { input ->
                val buffer = ByteArray(COPY_BUFFER_SIZE)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    byteCount += count
                    if (byteCount > expectedSize) return false
                    digest.update(buffer, 0, count)
                }
            } ?: return false
            byteCount == expectedSize &&
                digest.digest().joinToString("") { "%02x".format(it) } == expectedDigest
        } catch (_: Exception) {
            // Revoked or stale source grants do not block restoring a validated
            // protected copy; the user explicitly chose to save another copy.
            false
        }
    }

    private fun digest(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(COPY_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count > 0) digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun safeName(value: String?, mimeType: String): String {
        val extension = when (mimeType.lowercase()) {
            "image/jpeg", "image/jpg" -> "jpg"
            "image/png" -> "png"
            "image/webp" -> "webp"
            "image/gif" -> "gif"
            "image/bmp" -> "bmp"
            "image/tiff" -> "tif"
            "image/heif", "image/heic" -> "heic"
            "image/avif" -> "avif"
            else -> "img"
        }
        val cleaned = value
            ?.trim()
            ?.let { raw ->
                val fileName = raw.substringAfterLast('/').substringAfterLast('\\')
                fileName.substringBeforeLast('.', fileName)
            }
            ?.take(MAX_FILE_NAME_LENGTH)
            ?.takeIf { it.isNotBlank() && it != "." && it != ".." }
            ?: "Recovered_${System.currentTimeMillis()}"
        return "$cleaned.$extension"
    }

    private fun isNoSpace(error: IOException): Boolean =
        error.message?.contains("ENOSPC", ignoreCase = true) == true

    private fun success(protectionId: String, uri: Uri, usedPending: Boolean): Map<String, Any?> =
        mapOf(
            "status" to "restored",
            "protectionId" to protectionId,
            "restoredContentUri" to uri.toString(),
            "usedPendingPublish" to usedPending,
        )

    private fun result(status: String, protectionId: String?, message: String): Map<String, Any?> =
        mapOf("status" to status, "protectionId" to protectionId, "message" to message)

    companion object {
        private const val SHIELD_DIRECTORY = "recovery_shield"
        private const val COPY_BUFFER_SIZE = 64 * 1024
        private const val MAX_FILE_NAME_LENGTH = 180
    }
}
