package com.photorecoveryrestore.app

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import java.io.File
import java.security.MessageDigest

/** Restores readable recovery bytes without decoding or recompressing them. */
class DeepFileCopyRestorer(private val context: Context) {
    private val resolver = context.contentResolver
    private val inspector = ImageSignatureInspector(resolver)

    fun restore(arguments: Map<*, *>?): Map<String, Any?> {
        val source = (arguments?.get("filePath") as? String)?.let(::File)
            ?: return result("sourceUnavailable")
        val canonical = runCatching { source.canonicalFile }.getOrNull()
            ?: return result("sourceUnavailable")
        if (!canonical.isFile || !canonical.canRead() || !isAllowed(canonical)) {
            return result("sourceUnavailable")
        }
        val signature = inspector.inspect(canonical)
        if (signature.state != "valid" || signature.mimeType == null) {
            return result("invalidImage")
        }
        val expected = (arguments?.get("expectedSize") as? Number)?.toLong()
        if (expected != null && expected >= 0 && expected != canonical.length()) {
            return result("verificationFailure")
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) return result("accessRequired")

        val pictures = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        if (runCatching { StatFs(pictures.path).availableBytes }.getOrDefault(0L) < canonical.length()) {
            return result("insufficientStorage")
        }
        val displayName = safeName(arguments?.get("displayName") as? String, signature.format)
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, signature.mimeType)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Photo Recovery & Restore")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val destination = try {
            resolver.insert(collection, values)
        } catch (_: SecurityException) {
            return result("accessRequired")
        } catch (_: Exception) {
            return result("writeFailure")
        } ?: return result("writeFailure")

        try {
            val sourceDigest = MessageDigest.getInstance("SHA-256")
            var copied = 0L
            canonical.inputStream().buffered().use { input ->
                resolver.openOutputStream(destination, "w")?.buffered()?.use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        sourceDigest.update(buffer, 0, count)
                        copied += count
                    }
                    output.flush()
                } ?: throw IllegalStateException("Destination unavailable")
            }
            if (copied != canonical.length()) throw VerificationException()
            val destinationDigest = MessageDigest.getInstance("SHA-256")
            var verified = 0L
            resolver.openInputStream(destination)?.buffered()?.use { input ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    destinationDigest.update(buffer, 0, count)
                    verified += count
                }
            } ?: throw VerificationException()
            if (verified != copied || !sourceDigest.digest().contentEquals(destinationDigest.digest())) {
                throw VerificationException()
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                resolver.update(destination, ContentValues().apply {
                    put(MediaStore.Images.Media.IS_PENDING, 0)
                }, null, null)
            }
            return mapOf(
                "status" to "restored",
                "destinationUri" to destination.toString(),
                "bytesCopied" to copied,
            )
        } catch (_: VerificationException) {
            runCatching { resolver.delete(destination, null, null) }
            return result("verificationFailure")
        } catch (_: SecurityException) {
            runCatching { resolver.delete(destination, null, null) }
            return result("accessRequired")
        } catch (_: Exception) {
            runCatching { resolver.delete(destination, null, null) }
            return result("writeFailure")
        }
    }

    private fun isAllowed(file: File): Boolean {
        val path = file.path.replace('\\', '/').lowercase()
        val cacheRoot = runCatching { context.cacheDir.canonicalFile }.getOrNull()
        if (cacheRoot != null && within(file, cacheRoot) &&
            file.path.contains("deep_recovery_carved")) return true
        if (path.contains("/android/obb/") || path.contains("/android/data/")) return false
        return sharedRoots().any { within(file, it) }
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
        val clean = value?.substringAfterLast('/')?.substringAfterLast('\\')
            ?.takeIf { it.isNotBlank() && it != "." && it != ".." }
        val extension = when (format) {
            "png" -> "png"
            "webp" -> "webp"
            "gif" -> "gif"
            "bmp" -> "bmp"
            "tiff" -> "tif"
            "heif", "heic" -> "heic"
            "avif" -> "avif"
            "jxl" -> "jxl"
            "jp2" -> "jp2"
            else -> "jpg"
        }
        if (clean != null && clean.contains('.')) return clean
        if (clean != null) return "$clean.$extension"
        return "recovered_${System.currentTimeMillis()}.$extension"
    }

    private fun result(status: String) = mapOf<String, Any?>("status" to status)
    private class VerificationException : Exception()
}
