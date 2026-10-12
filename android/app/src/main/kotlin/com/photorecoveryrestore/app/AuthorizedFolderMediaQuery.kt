package com.photorecoveryrestore.app

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject

class AuthorizedFolderMediaQuery(private val context: Context) {
    private val signatureInspector = ImageSignatureInspector(context.contentResolver)

    fun query(treeUriText: String?, pageSize: Int, continuationToken: String?): Map<String, Any?> {
        val treeUri = treeUriText?.let { runCatching { Uri.parse(it) }.getOrNull() }
            ?: return failure("platformFailure", "Invalid folder tree URI.")
        val hasGrant = context.contentResolver.persistedUriPermissions.any {
            it.uri == treeUri && it.isReadPermission
        }
        if (!hasGrant) return failure("permissionGrantLost", "The saved folder permission is no longer active.")
        val state = decodeState(continuationToken) ?: initialState(treeUri)
            ?: return failure("platformFailure", "The folder tree URI is malformed.")
        return try {
            val items = mutableListOf<Map<String, Any?>>()
            val stats = ScanStats()
            while (
                state.pending.isNotEmpty() &&
                    items.size < pageSize &&
                    stats.entriesExamined < MAX_ENTRIES_PER_PAGE
            ) {
                val directory = state.pending.removeAt(0)
                // Directory work itself is bounded too. Empty directory trees
                // must not evade the same page budget as file entries.
                stats.entriesExamined++
                if (stats.entriesExamined >= MAX_ENTRIES_PER_PAGE) {
                    state.pending.add(0, directory)
                    break
                }
                scanDirectory(treeUri, directory, pageSize, items, state.pending, stats)
            }
            mapOf(
                "status" to "success",
                "items" to items,
                "nextContinuationToken" to if (state.pending.isEmpty()) null else encodeState(state),
                "filesExamined" to stats.filesExamined,
                "entriesExamined" to stats.entriesExamined,
                "skippedNonImages" to stats.skippedNonImages,
                "invalidFilesRejected" to stats.invalidFilesRejected,
                "unavailableFiles" to stats.unavailableFiles,
                "unsupportedFiles" to stats.unsupportedFiles,
            )
        } catch (_: SecurityException) {
            failure("permissionGrantLost", "The saved folder permission is no longer active.")
        } catch (_: Exception) {
            failure("platformFailure", "Unable to enumerate the authorized folder.")
        }
    }

    private fun scanDirectory(
        treeUri: Uri,
        directory: DirectoryCursor,
        pageSize: Int,
        items: MutableList<Map<String, Any?>>,
        pending: MutableList<DirectoryCursor>,
        stats: ScanStats,
    ) {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, directory.documentId)
        context.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            var position = 0
            while (cursor.moveToNext()) {
                if (position++ < directory.offset) continue
                // Every visible child consumes bounded work, including malformed
                // rows, directories, and obvious non-image documents.
                stats.entriesExamined++
                val documentId = cursor.getStringOrNull(0)
                if (documentId != null) {
                    val displayName = cursor.getStringOrNull(1)
                    val declaredMimeType = cursor.getStringOrNull(2)
                    if (declaredMimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                        // Depth-first pending order prevents a wide directory from
                        // retaining every sibling in the continuation token.
                        if (!isRestrictedDocument(documentId)) {
                            pending.add(0, DirectoryCursor(documentId, 0))
                        }
                    } else if (isClearlyNonImage(declaredMimeType, displayName)) {
                        stats.skippedNonImages++
                    } else {
                        stats.filesExamined++
                        val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
                        val signature = signatureInspector.inspect(documentUri)
                        if (signature.state != "valid") {
                            if (signature.state == "unavailable") stats.unavailableFiles++
                            else if (signature.state == "unsupported") stats.unsupportedFiles++
                            else stats.invalidFilesRejected++
                        } else {
                            items += mapOf(
                                "documentUri" to documentUri.toString(),
                                "displayName" to displayName,
                                "mimeType" to signature.mimeType,
                                "declaredMimeType" to declaredMimeType,
                                "detectedFormat" to signature.format,
                                "signatureState" to signature.state,
                                "byteSize" to cursor.getLongOrNull(3),
                                "modifiedMillis" to cursor.getLongOrNull(4),
                            )
                        }
                    }
                }
                if (items.size >= pageSize || stats.entriesExamined >= MAX_ENTRIES_PER_PAGE) {
                    pending.add(0, DirectoryCursor(directory.documentId, position))
                    break
                }
            }
        }
    }
    private fun isClearlyNonImage(declaredMimeType: String?, displayName: String?): Boolean {
        if (declaredMimeType.isNullOrBlank() || declaredMimeType.startsWith("image/")) return false
        val extension = displayName?.substringAfterLast('.', "")?.lowercase().orEmpty()
        return extension in UNRELATED_EXTENSIONS
    }
    private fun initialState(treeUri: Uri): QueryState? {
        val rootId = runCatching { DocumentsContract.getTreeDocumentId(treeUri) }.getOrNull() ?: return null
        if (isRestrictedDocument(rootId)) return null
        return QueryState(mutableListOf(DirectoryCursor(rootId, 0)))
    }

    private fun encodeState(state: QueryState): String {
        val pending = JSONArray()
        state.pending.forEach { value ->
            pending.put(JSONObject().put("documentId", value.documentId).put("offset", value.offset))
        }
        val bytes = JSONObject().put("pending", pending).toString().toByteArray(Charsets.UTF_8)
        return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP)
    }

    private fun decodeState(token: String?): QueryState? {
        if (token.isNullOrBlank()) return null
        return runCatching {
            val raw = String(Base64.decode(token, Base64.URL_SAFE or Base64.NO_WRAP), Charsets.UTF_8)
            val values = JSONObject(raw).getJSONArray("pending")
            val pending = mutableListOf<DirectoryCursor>()
            for (index in 0 until values.length()) {
                val value = values.getJSONObject(index)
                val documentId = value.getString("documentId")
                val offset = value.getInt("offset")
                if (offset < 0 || isRestrictedDocument(documentId)) return null
                pending += DirectoryCursor(documentId, offset)
            }
            QueryState(pending)
        }.getOrNull()
    }

    private fun isRestrictedDocument(documentId: String): Boolean {
        val path = documentId.substringAfter(':', "").trim('/').lowercase()
        return path == "android/data" || path.startsWith("android/data/") ||
            path == "android/obb" || path.startsWith("android/obb/")
    }

    private fun failure(code: String, message: String): Map<String, Any?> =
        mapOf("status" to "failure", "code" to code, "message" to message)

    private fun android.database.Cursor.getStringOrNull(index: Int): String? =
        if (isNull(index)) null else getString(index)

    private fun android.database.Cursor.getLongOrNull(index: Int): Long? =
        if (isNull(index)) null else getLong(index)

    private data class DirectoryCursor(val documentId: String, val offset: Int)
    private data class QueryState(val pending: MutableList<DirectoryCursor>)
    private data class ScanStats(
        var filesExamined: Int = 0,
        var entriesExamined: Int = 0,
        var skippedNonImages: Int = 0,
        var invalidFilesRejected: Int = 0,
        var unavailableFiles: Int = 0,
        var unsupportedFiles: Int = 0,
    )

    companion object {
        private const val MAX_ENTRIES_PER_PAGE = 200
        private val UNRELATED_EXTENSIONS = setOf(
            "mp4", "mkv", "avi", "mov", "mp3", "wav", "aac", "apk", "pdf",
            "zip", "rar", "7z", "doc", "docx", "xls", "xlsx",
        )
        private val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
    }
}