package com.photorecoveryrestore.app

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException
import java.security.MessageDigest
import java.util.UUID

/** Copies readable recovery bytes without decoding or recompressing them. */
class DeepFileCopyRestorer(private val context: Context) {
    private val resolver = context.contentResolver
    private val inspector = ImageSignatureInspector(resolver)

    fun restore(arguments: Map<*, *>?): Map<String, Any?> {
        val sourceUri = parseContentUri(arguments?.get("sourceUri") as? String)
        val sourceFile = if (sourceUri == null) {
            val rawPath = (arguments?.get("filePath") as? String)
                ?.takeIf { it.isNotBlank() }
                ?: return result("sourceUnavailable")
            val file = runCatching { File(rawPath).canonicalFile }.getOrNull()
                ?: return result("sourceUnavailable")
            if (!isAllowed(file)) return result("sourceUnavailable")
            val readable = if (file.isFile && file.canRead()) file else
                reextractExpired(arguments, file)
            if (readable == null) {
                return result("sourceUnavailable")
            }
            readable
        } else {
            if (sourceUri.authority == MediaStore.AUTHORITY) {
                // MediaStore reads are covered by the granted image permission.
            } else if (!hasPersistedTreeReadGrant(sourceUri)) {
                val canRead = runCatching {
                    resolver.openInputStream(sourceUri)?.use { true } == true
                }.getOrDefault(false)
                if (!canRead) return result("accessRequired")
            }
            null
        }

        val signature = sourceFile?.let(inspector::inspect)
            ?: sourceUri?.let(inspector::inspect)
            ?: return result("sourceUnavailable")
        if (!isRecognizedImage(signature.state, signature.format, signature.mimeType)) {
            return result("invalidImage")
        }
        val mimeType = signature.mimeType ?: return result("invalidImage")

        val expected = (arguments?.get("expectedSize") as? Number)?.toLong()
            ?.takeIf { it >= 0L }
        val sourceLength = sourceFile?.length() ?: sourceUri?.let(::querySize) ?: expected
        if (expected != null && sourceLength != null && expected != sourceLength) {
            return result("verificationFailure")
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) return result("accessRequired")

        val pictures = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        val requiredSpace = expected ?: sourceLength ?: 0L
        val availableSpace = runCatching { StatFs(pictures.path).availableBytes }.getOrDefault(0L)
        if (requiredSpace > 0L && availableSpace < requiredSpace) {
            return result("insufficientStorage")
        }

        val displayName = safeName(arguments?.get("displayName") as? String, signature.format)
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Photo Recovery & Restore")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }
        val destination = try {
            resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
        } catch (_: SecurityException) {
            return result("accessRequired")
        } catch (_: Exception) {
            return result("writeFailure")
        } ?: return result("writeFailure")

        try {
            val sourceDigest = MessageDigest.getInstance("SHA-256")
            var copied = 0L
            openSource(sourceFile, sourceUri)?.buffered()?.use { input ->
                resolver.openOutputStream(destination, "w")?.buffered()?.use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        sourceDigest.update(buffer, 0, count)
                        copied += count
                    }
                    output.flush()
                } ?: throw IllegalStateException("Destination unavailable")
            } ?: throw FileNotFoundException("Source unavailable")

            if (copied <= 0L ||
                (sourceLength != null && copied != sourceLength) ||
                (expected != null && copied != expected)
            ) throw VerificationException()

            val destinationSignature = inspector.inspect(destination)
            if (!isRecognizedImage(
                    destinationSignature.state,
                    destinationSignature.format,
                    destinationSignature.mimeType,
                ) || destinationSignature.mimeType == null
            ) throw VerificationException()
            if (signature.width != null && destinationSignature.width != null &&
                signature.width != destinationSignature.width
            ) throw VerificationException()
            if (signature.height != null && destinationSignature.height != null &&
                signature.height != destinationSignature.height
            ) throw VerificationException()

            val expectedDigest = sourceDigest.digest()
            val destinationDigest = MessageDigest.getInstance("SHA-256")
            var verified = 0L
            resolver.openInputStream(destination)?.buffered()?.use { input ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    destinationDigest.update(buffer, 0, count)
                    verified += count
                }
            } ?: throw VerificationException()
            if (verified != copied ||
                !expectedDigest.contentEquals(destinationDigest.digest())
            ) throw VerificationException()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val published = resolver.update(destination, ContentValues().apply {
                    put(MediaStore.Images.Media.IS_PENDING, 0)
                }, null, null)
                if (published <= 0) throw VerificationException()
                val pending = resolver.query(
                    destination,
                    arrayOf(MediaStore.Images.Media.IS_PENDING),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getInt(0) else null
                }
                if (pending != 0) throw VerificationException()
            }
            val readable = resolver.openInputStream(destination)?.use { it.read() >= 0 } == true
            if (!readable) throw VerificationException()
            return mapOf(
                "status" to "restored",
                "destinationUri" to destination.toString(),
                "bytesCopied" to copied,
            )
        } catch (_: VerificationException) {
            runCatching { resolver.delete(destination, null, null) }
            return result("verificationFailure")
        } catch (_: FileNotFoundException) {
            runCatching { resolver.delete(destination, null, null) }
            return result("sourceUnavailable")
        } catch (_: SecurityException) {
            runCatching { resolver.delete(destination, null, null) }
            return result("accessRequired")
        } catch (_: Exception) {
            runCatching { resolver.delete(destination, null, null) }
            return result("writeFailure")
        }
    }

    private fun parseContentUri(value: String?): Uri? = value
        ?.takeIf { it.isNotBlank() }
        ?.let { runCatching { Uri.parse(it) }.getOrNull() }
        ?.takeIf { it.scheme == "content" }

    private fun isRecognizedImage(state: String, format: String?, mimeType: String?): Boolean =
        (state == "valid" || state == "unsupported") &&
            !format.isNullOrBlank() &&
            mimeType?.startsWith("image/") == true

    private fun openSource(file: File?, uri: Uri?) = when {
        file != null -> file.inputStream()
        uri != null -> resolver.openInputStream(uri)
        else -> null
    }

    private fun querySize(uri: Uri): Long? = runCatching {
        resolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst() || cursor.isNull(0)) null
            else cursor.getLong(0).takeIf { it >= 0L }
        }
    }.getOrNull()

    private fun hasPersistedTreeReadGrant(documentUri: Uri): Boolean {
        val authority = documentUri.authority ?: return false
        val treeDocumentId = runCatching {
            DocumentsContract.getTreeDocumentId(documentUri)
        }.getOrNull() ?: return false
        val treeUri = runCatching {
            DocumentsContract.buildTreeDocumentUri(authority, treeDocumentId)
        }.getOrNull() ?: return false
        return resolver.persistedUriPermissions.any {
            it.uri == treeUri && it.isReadPermission
        }
    }

    private fun isAllowed(file: File): Boolean {
        val path = file.path.replace('\\', '/').lowercase()
        val carvedRoot = runCatching {
            File(context.filesDir, "deep_recovery_carved").canonicalFile
        }.getOrNull()
        if (carvedRoot != null && within(file, carvedRoot)) return true
        val legacyCarvedRoot = runCatching {
            File(context.cacheDir, "deep_recovery_carved").canonicalFile
        }.getOrNull()
        if (legacyCarvedRoot != null && within(file, legacyCarvedRoot)) return true
        if (path.contains("/android/obb/") || path.contains("/android/data/")) return false
        return sharedRoots().any { within(file, it) }
    }

    private fun reextractExpired(arguments: Map<*, *>?, expired: File): File? {
        val metadata = arguments ?: return null
        val managedRoot = runCatching {
            File(context.filesDir, "deep_recovery_carved").canonicalFile
        }.getOrNull()
        val legacyRoot = runCatching {
            File(context.cacheDir, "deep_recovery_carved").canonicalFile
        }.getOrNull()
        if (listOfNotNull(managedRoot, legacyRoot).none { within(expired, it) }) return null
        val path = (metadata["containerPath"] as? String)?.takeIf { it.isNotBlank() }
            ?: return null
        val container = runCatching { File(path).canonicalFile }.getOrNull() ?: return null
        if (!container.isFile || !container.canRead() || !isAllowed(container)) return null
        val offset = (metadata["embeddedOffset"] as? Number)?.toLong()
            ?.takeIf { it >= 0L } ?: return null
        val format = metadata["detectedFormat"] as? String ?: return null
        val expectedSize = (metadata["expectedSize"] as? Number)?.toLong()
            ?.takeIf { it > 0L } ?: return null
        val carved = EmbeddedImageCarver(context).carvePage(container, offset, 1) { false }
            .items.firstOrNull { it.offset == offset && it.format == format &&
                it.file.length() == expectedSize }
        return carved?.file?.takeIf { it.isFile && it.canRead() && isAllowed(it) }
    }

    private fun sharedRoots(): List<File> {
        val roots = mutableListOf<File>()
        Environment.getExternalStorageDirectory()?.let { roots += it }
        context.getExternalFilesDirs(null).filterNotNull().forEach { directory ->
            var root: File? = directory
            repeat(4) { root = root?.parentFile }
            root?.let { roots += it }
        }
        return roots.mapNotNull { runCatching { it.canonicalFile }.getOrNull() }
            .distinctBy { it.path }
    }

    private fun within(file: File, root: File): Boolean {
        val child = file.path
        val parent = root.path.trimEnd(File.separatorChar)
        return child == parent || child.startsWith(parent + File.separator)
    }

    private fun safeName(value: String?, format: String?): String {
        val extension = when (format) {
            "jpeg" -> "jpg"
            "png" -> "png"
            "webp" -> "webp"
            "gif" -> "gif"
            "bmp" -> "bmp"
            "tiff" -> "tif"
            "heif" -> "heic"
            "avif" -> "avif"
            else -> "img"
        }
        val clean = value?.substringAfterLast('/')?.substringAfterLast('\\')
            ?.takeIf { it.isNotBlank() && it != "." && it != ".." }
            ?: return "recovered_${UUID.randomUUID()}.$extension"
        val base = clean.substringBeforeLast('.', clean).ifBlank { "recovered" }
        return "${base.take(80)}_${UUID.randomUUID()}.$extension"
    }

    private fun result(status: String) = mapOf<String, Any?>("status" to status)
    private class VerificationException : Exception()
}
