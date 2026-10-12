package com.photorecoveryrestore.app

import android.content.Context
import android.net.Uri
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.security.MessageDigest
import java.util.UUID

class RecoveryShieldStorage(private val context: Context) {
    fun items(): List<Map<String, Any?>> {
        val root = root()
        return root.listFiles { file -> file.isFile && file.extension == "json" }
            ?.mapNotNull(::readManifest)
            ?.map { metadata ->
                val copy = File(metadata.optString("protectedCopyLocation"))
                val size = metadata.optLong("byteSize", -1L)
                val digest = metadata.optString("sha256Digest")
                mapOf(
                    "protectionId" to metadata.optString("protectionId"),
                    "displayName" to metadata.optString("displayName").takeIf { it.isNotBlank() },
                    "byteSize" to size.coerceAtLeast(0L),
                    "integrityVerified" to (
                        copy.isFile && copy.length() == size && digest.matches(Regex("[0-9a-fA-F]{64}"))
                    ),
                )
            }
            ?.filter { (it["protectionId"] as? String).isNullOrBlank().not() }
            ?.sortedBy { it["protectionId"] as String }
            ?: emptyList()
    }

    fun unprotect(protectionIds: List<String>): Boolean {
        val root = root()
        var success = true
        protectionIds.distinct().forEach { id ->
            val manifest = File(root, "${sha256(id.toByteArray())}.json")
            val metadata = readManifest(manifest)
            val copy = metadata?.optString("protectedCopyLocation")?.let(::File)
            if (copy != null && isInside(copy, root) && copy.exists() && !copy.delete()) success = false
            if (manifest.exists() && !manifest.delete()) success = false
        }
        return success
    }

    fun clear(): Boolean {
        val root = root()
        var success = true
        root.listFiles()?.forEach { file ->
            if (file.isFile && !file.delete()) success = false
        }
        return success
    }

    private fun root() = File(context.noBackupFilesDir, DIRECTORY_NAME)

    private fun isInside(file: File, root: File): Boolean = try {
        file.canonicalPath.startsWith(root.canonicalPath + File.separator)
    } catch (_: IOException) {
        false
    }

    fun protect(arguments: Map<*, *>?): Map<String, Any?> {
        val protectionId = arguments?.get("protectionId") as? String
        val sourceUriText = arguments?.get("sourceUri") as? String
        val stableIdentity = arguments?.get("stableSourceIdentity") as? String
        if (protectionId.isNullOrBlank() || sourceUriText.isNullOrBlank() || stableIdentity.isNullOrBlank()) {
            return result("platformFailure", protectionId, "Invalid protection request.")
        }

        val root = root()
        if (!root.exists() && !root.mkdirs()) {
            return result("platformFailure", protectionId, "Private Shield storage is unavailable.")
        }
        val key = sha256(protectionId.toByteArray())
        val manifest = File(root, "$key.json")
        val previous = readManifest(manifest)
        val previousCopy = previous?.optString("protectedCopyLocation")
            ?.takeIf { it.isNotBlank() }
            ?.let(::File)
        val expectedDigest = (arguments["expectedSha256"] as? String)?.lowercase()
        if (expectedDigest != null &&
            previous?.optString("stableSourceIdentity") == stableIdentity &&
            previous.optString("sha256Digest").lowercase() == expectedDigest &&
            previousCopy?.isFile == true &&
            previousCopy.length() == previous.optLong("byteSize", -1L)) {
            return success("alreadyProtected", protectionId, previous)
        }

        val expectedSize = (arguments["expectedByteSize"] as? Number)?.toLong()
        if (expectedSize != null && expectedSize >= 0 && root.usableSpace < expectedSize + STORAGE_MARGIN_BYTES) {
            return result("insufficientStorage", protectionId, "Not enough private app storage.")
        }

        val temporary = File(root, ".$key-${UUID.randomUUID()}.tmp")
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            var copied = 0L
            context.contentResolver.openInputStream(Uri.parse(sourceUriText))?.use { input ->
                temporary.outputStream().buffered().use { output ->
                    val buffer = ByteArray(COPY_BUFFER_SIZE)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue
                        output.write(buffer, 0, count)
                        digest.update(buffer, 0, count)
                        copied += count
                    }
                    output.flush()
                }
            } ?: return result("sourceUnavailable", protectionId, "The selected source is unavailable.")

            val actualDigest = digest.digest().joinToString("") { "%02x".format(it) }
            if (!temporary.isFile ||
                temporary.length() != copied ||
                (expectedSize != null && expectedSize >= 0 && copied != expectedSize) ||
                (expectedDigest != null && actualDigest != expectedDigest)) {
                temporary.delete()
                return result("integrityFailure", protectionId, "Protected-copy verification failed.")
            }

            val protectedCopy = File(root, "$key-$actualDigest.bin")
            if (!protectedCopy.exists() && !temporary.renameTo(protectedCopy)) {
                temporary.delete()
                return result("platformFailure", protectionId, "Unable to publish protected copy.")
            }
            temporary.delete()

            val protectedAt = System.currentTimeMillis()
            val metadata = JSONObject().apply {
                put("protectionId", protectionId)
                put("stableSourceIdentity", stableIdentity)
                putNullable("originalContentUri", arguments["originalContentUri"])
                putNullable("originalSource", arguments["source"])
                putNullable("displayName", arguments["displayName"])
                putNullable("mimeType", arguments["mimeType"])
                putNullable("originalLocation", arguments["originalLocation"])
                put("byteSize", copied)
                putNullable("width", arguments["width"])
                putNullable("height", arguments["height"])
                putNullable("createdAtMillis", arguments["createdAtMillis"])
                putNullable("modifiedAtMillis", arguments["modifiedAtMillis"])
                putNullable("takenAtMillis", arguments["takenAtMillis"])
                put("protectedCopyLocation", protectedCopy.absolutePath)
                put("sha256Digest", actualDigest)
                put("protectedAtMillis", protectedAt)
            }
            if (!publishManifest(root, key, manifest, metadata)) {
                if (previousCopy?.absolutePath != protectedCopy.absolutePath) protectedCopy.delete()
                return result("platformFailure", protectionId, "Unable to publish protection metadata.")
            }
            if (previousCopy != null && previousCopy.absolutePath != protectedCopy.absolutePath) {
                previousCopy.delete()
            }
            success(if (previous == null) "protected" else "updated", protectionId, metadata)
        } catch (_: FileNotFoundException) {
            temporary.delete()
            result("sourceUnavailable", protectionId, "The selected source is unavailable.")
        } catch (_: SecurityException) {
            temporary.delete()
            result("accessFailure", protectionId, "Access to the selected source was denied.")
        } catch (error: IOException) {
            temporary.delete()
            val noSpace = error.message?.contains("ENOSPC", ignoreCase = true) == true || root.usableSpace <= STORAGE_MARGIN_BYTES
            result(
                if (noSpace) "insufficientStorage" else "platformFailure",
                protectionId,
                if (noSpace) "Not enough private app storage." else "Unable to copy the selected source.",
            )
        } catch (_: Exception) {
            temporary.delete()
            result("platformFailure", protectionId, "Unable to protect the selected source.")
        }
    }

    private fun publishManifest(
        root: File,
        key: String,
        manifest: File,
        metadata: JSONObject,
    ): Boolean {
        val temporaryManifest = File(root, ".$key-${UUID.randomUUID()}.json.tmp")
        val backupManifest = File(root, ".$key-${UUID.randomUUID()}.json.bak")
        return try {
            temporaryManifest.writeText(metadata.toString())
            if (manifest.exists() && !manifest.renameTo(backupManifest)) return false
            if (!temporaryManifest.renameTo(manifest)) {
                backupManifest.renameTo(manifest)
                false
            } else {
                backupManifest.delete()
                true
            }
        } finally {
            temporaryManifest.delete()
        }
    }

    private fun readManifest(file: File): JSONObject? = try {
        if (file.isFile) JSONObject(file.readText()) else null
    } catch (_: Exception) {
        null
    }

    private fun success(status: String, protectionId: String, metadata: JSONObject): Map<String, Any?> =
        mapOf(
            "status" to status,
            "protectionId" to protectionId,
            "protectedCopyLocation" to metadata.optString("protectedCopyLocation"),
            "sha256Digest" to metadata.optString("sha256Digest"),
            "byteSize" to metadata.optLong("byteSize"),
            "protectedAtMillis" to metadata.optLong("protectedAtMillis"),
        )

    private fun result(status: String, protectionId: String?, message: String): Map<String, Any?> =
        mapOf("status" to status, "protectionId" to protectionId, "message" to message)

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { "%02x".format(it) }

    private fun JSONObject.putNullable(name: String, value: Any?) {
        if (value != null) put(name, value)
    }

    companion object {
        private const val DIRECTORY_NAME = "recovery_shield"
        private const val COPY_BUFFER_SIZE = 64 * 1024
        private const val STORAGE_MARGIN_BYTES = 1024 * 1024L
    }
}
