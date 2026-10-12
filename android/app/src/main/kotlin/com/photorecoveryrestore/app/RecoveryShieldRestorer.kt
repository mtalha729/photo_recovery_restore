package com.photorecoveryrestore.app

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.MediaStore
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.security.MessageDigest

class RecoveryShieldRestorer(private val context: Context) {
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

        val treeUriText = request["destinationTreeUri"] as? String
        return if (!treeUriText.isNullOrBlank()) {
            restoreToTree(protectionId, protectedCopy, expectedDigest, expectedSize, Uri.parse(treeUriText), request)
        } else {
            restoreToMediaStore(protectionId, protectedCopy, expectedDigest, expectedSize, request)
        }
    }

    private fun restoreToMediaStore(
        protectionId: String,
        protectedCopy: File,
        expectedDigest: String,
        expectedSize: Long,
        arguments: Map<*, *>,
    ): Map<String, Any?> {
        val resolver = context.contentResolver
        val usesPending = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, safeName(arguments["displayName"] as? String))
            put(MediaStore.Images.Media.MIME_TYPE, (arguments["mimeType"] as? String)?.takeIf { it.isNotBlank() } ?: "image/*")
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
            if (writtenDigest != expectedDigest || !destinationSizeMatches(created, expectedSize)) {
                resolver.delete(created, null, null)
                return result("verificationFailure", protectionId, "Restored media verification failed.")
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
                (arguments["mimeType"] as? String)?.takeIf { it.isNotBlank() } ?: "image/*",
                safeName(arguments["displayName"] as? String),
            ) ?: return result("writeFailure", protectionId, "Unable to create selected destination.")
            destination = created
            val writtenDigest = copyToUri(protectedCopy, created)
            if (writtenDigest != expectedDigest || !destinationSizeMatches(created, expectedSize)) {
                DocumentsContract.deleteDocument(resolver, created)
                return result("verificationFailure", protectionId, "Restored media verification failed.")
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

    private fun destinationSizeMatches(uri: Uri, expectedSize: Long): Boolean {
        val descriptorLength = context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length }
        if (descriptorLength != null && descriptorLength >= 0) return descriptorLength == expectedSize
        return context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.SIZE), null, null, null)?.use { cursor ->
            cursor.moveToFirst() && !cursor.isNull(0) && cursor.getLong(0) == expectedSize
        } ?: false
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

    private fun safeName(value: String?): String = value
        ?.trim()
        ?.takeIf { it.isNotEmpty() && !it.contains('/') && !it.contains('\\') }
        ?: "Recovered_${System.currentTimeMillis()}.jpg"

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
    }
}
