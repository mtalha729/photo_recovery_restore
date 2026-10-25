package com.photorecoveryrestore.app

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/** Bounded, read-only image discovery within one persisted SAF tree grant. */
class AuthorizedFolderMediaQuery(private val context: Context) {
    private val signatureInspector = ImageSignatureInspector(context.contentResolver)
    private val sessions = ConcurrentHashMap<String, Session>()
    private val cancellationGeneration = AtomicLong(0L)

    fun currentCancellationGeneration(): Long = cancellationGeneration.get()

    /** Signals from the UI thread without mutating a worker-owned cursor queue. */
    fun requestCancellation(continuationToken: String?) {
        cancellationGeneration.incrementAndGet()
        val activeSessions = if (continuationToken == null) {
            sessions.values.toList()
        } else {
            listOfNotNull(sessions[continuationToken.substringBefore(':')])
        }
        activeSessions.forEach { it.cancelled = true }
    }

    /** Run on the storage executor after any current page has returned. */
    fun cancel(continuationToken: String?) {
        val activeSessions = if (continuationToken == null) {
            sessions.values.toList()
        } else {
            listOfNotNull(sessions[continuationToken.substringBefore(':')])
        }
        activeSessions.forEach { session ->
            session.cancelled = true
            session.closeOpenCursors()
            session.pending.clear()
            sessions.remove(session.id, session)
        }
    }

    fun query(
        treeUriText: String?,
        pageSize: Int,
        continuationToken: String?,
        requestGeneration: Long = currentCancellationGeneration(),
    ): Map<String, Any?> {
        if (requestGeneration != cancellationGeneration.get()) {
            return failure("cancelled", "Selected-folder scan cancelled safely.")
        }
        if (pageSize !in 1..MAXIMUM_PAGE_SIZE) {
            return failure("platformFailure", "Invalid folder page size.")
        }
        val treeUri = treeUriText?.let { runCatching { Uri.parse(it) }.getOrNull() }
            ?.takeIf { it.scheme == "content" }
            ?: return failure("platformFailure", "Invalid folder tree URI.")
        if (!hasReadGrant(treeUri)) {
            return failure("permissionGrantLost", "The saved folder permission is no longer active.")
        }

        val sessionId = continuationToken?.substringBefore(':')
        val session = if (sessionId == null) {
            if (sessions.isNotEmpty()) {
                return failure("scanInProgress", "Another selected-folder scan is still active.")
            }
            createSession(treeUri) ?: return failure(
                "restrictedLocation",
                "This folder cannot be scanned through Android's document provider.",
            )
        } else {
            sessions[sessionId]
                ?: return failure("invalidContinuation", "The folder scan continuation expired.")
        }
        if (requestGeneration != cancellationGeneration.get() || session.cancelled) {
            session.cancelled = true
            session.closeOpenCursors()
            session.pending.clear()
            sessions.remove(session.id, session)
            return failure("cancelled", "Selected-folder scan cancelled safely.")
        }
        if (continuationToken != null && continuationToken != session.lastIssuedToken) {
            session.closeOpenCursors()
            session.pending.clear()
            sessions.remove(session.id, session)
            return failure("repeatedCursor", "The folder scan repeated a continuation state.")
        }
        if (session.treeUri != treeUri) {
            session.closeOpenCursors()
            session.pending.clear()
            sessions.remove(session.id, session)
            return failure("invalidContinuation", "The folder continuation belongs to another folder.")
        }
        if (!hasReadGrant(treeUri)) {
            session.closeOpenCursors()
            session.pending.clear()
            sessions.remove(session.id, session)
            return failure("permissionGrantLost", "The saved folder permission is no longer active.")
        }

        return try {
            val items = mutableListOf<Map<String, Any?>>()
            val stats = ScanStats()
            while (
                session.pending.isNotEmpty() &&
                    items.size < pageSize &&
                    stats.entriesExamined < MAX_ENTRIES_PER_PAGE &&
                    !session.resourceLimitReached
            ) {
                if (isCancelled(session, requestGeneration)) {
                    session.cancelled = true
                    break
                }
                val directory = session.pending.removeFirst()
                session.activeDirectory = directory
                stats.entriesExamined++
                if (stats.entriesExamined >= MAX_ENTRIES_PER_PAGE) {
                    session.pending.addFirst(directory)
                    session.activeDirectory = null
                    break
                }
                if (!directory.visited) {
                    if (!session.visitedDirectories.add(directory.documentId)) {
                        stats.duplicateDirectorySkips++
                        directory.closeCursor()
                        session.activeDirectory = null
                        continue
                    }
                    directory.visited = true
                }
                val continuation = scanDirectory(
                    session = session,
                    directory = directory,
                    pageSize = pageSize,
                    items = items,
                    stats = stats,
                    requestGeneration = requestGeneration,
                )
                session.activeDirectory = null
                if (continuation != null) session.pending.addFirst(continuation)
            }

            session.unavailableFiles += stats.unavailableFiles
            session.unavailableDirectories += stats.unavailableDirectories
            val cancelled = session.cancelled || isCancelled(session, requestGeneration)
            if (cancelled) session.cancelled = true
            val stopped = cancelled || session.permissionGrantLost || session.resourceLimitReached
            val complete = session.pending.isEmpty() || stopped
            val completionReason = when {
                cancelled -> "cancelled"
                session.permissionGrantLost -> "permissionGrantLost"
                session.resourceLimitReached -> "resourceLimit"
                complete && (session.unavailableFiles > 0 || session.unavailableDirectories > 0) ->
                    "exhaustedWithUnreadableEntries"
                complete -> "exhausted"
                else -> "pageBoundary"
            }
            val nextToken = if (complete) {
                session.closeOpenCursors()
                session.pending.clear()
                sessions.remove(session.id, session)
                null
            } else if (stats.entriesExamined == 0) {
                session.closeOpenCursors()
                session.pending.clear()
                sessions.remove(session.id, session)
                return failure("noProgress", "The authorized folder made no scan progress.")
            } else {
                "${session.id}:${++session.pageNumber}".also {
                    session.lastIssuedToken = it
                }
            }
            mapOf(
                "status" to "success",
                "items" to items,
                "nextContinuationToken" to nextToken,
                "filesExamined" to stats.filesExamined,
                "entriesExamined" to stats.entriesExamined,
                "skippedNonImages" to stats.skippedNonImages,
                "invalidFilesRejected" to stats.invalidFilesRejected,
                "unavailableFiles" to stats.unavailableFiles,
                "unavailableDirectories" to stats.unavailableDirectories,
                "unsupportedFiles" to stats.unsupportedFiles,
                "duplicateDirectorySkips" to stats.duplicateDirectorySkips,
                "providerExhausted" to complete,
                "completionReason" to completionReason,
            )
        } catch (_: SecurityException) {
            session.closeOpenCursors()
            session.pending.clear()
            sessions.remove(session.id, session)
            failure("permissionGrantLost", "The saved folder permission is no longer active.")
        } catch (_: Exception) {
            session.closeOpenCursors()
            session.pending.clear()
            sessions.remove(session.id, session)
            failure("platformFailure", "Unable to enumerate the authorized folder.")
        }
    }

    private fun scanDirectory(
        session: Session,
        directory: DirectoryCursor,
        pageSize: Int,
        items: MutableList<Map<String, Any?>>,
        stats: ScanStats,
        requestGeneration: Long,
    ): DirectoryCursor? {
        val cursor = directory.cursor ?: try {
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                session.treeUri,
                directory.documentId,
            )
            context.contentResolver.query(childrenUri, PROJECTION, null, null, null)
        } catch (_: SecurityException) {
            session.permissionGrantLost = true
            directory.closeCursor()
            return null
        } catch (_: Exception) {
            stats.unavailableDirectories++
            directory.closeCursor()
            return null
        }
        if (cursor == null) {
            stats.unavailableDirectories++
            directory.closeCursor()
            return null
        }
        directory.cursor = cursor
        try {
            while (cursor.moveToNext()) {
                if (isCancelled(session, requestGeneration)) {
                    session.cancelled = true
                    directory.closeCursor()
                    return null
                }
                if (session.totalEntriesExamined >= MAX_TOTAL_ENTRIES) {
                    session.resourceLimitReached = true
                    return directory
                }
                session.totalEntriesExamined++
                stats.entriesExamined++
                val documentId = cursor.getStringOrNull(0)
                if (documentId != null) {
                    val displayName = cursor.getStringOrNull(1)
                    val declaredMimeType = cursor.getStringOrNull(2)
                    if (declaredMimeType == Document.MIME_TYPE_DIR) {
                        if (!isRestrictedDocument(documentId)) {
                            if (documentId in session.scheduledDirectories ||
                                documentId in session.visitedDirectories
                            ) {
                                stats.duplicateDirectorySkips++
                            } else if (
                                session.pending.size >= MAX_PENDING_DIRECTORIES ||
                                session.scheduledDirectories.size >= MAX_TRACKED_DIRECTORIES
                            ) {
                                session.resourceLimitReached = true
                            } else {
                                session.scheduledDirectories.add(documentId)
                                // Breadth-first scheduling keeps at most one live
                                // provider cursor across page boundaries.
                                session.pending.addLast(DirectoryCursor(documentId))
                            }
                        }
                    } else if (isClearlyNonImage(declaredMimeType, displayName)) {
                        stats.skippedNonImages++
                    } else {
                        stats.filesExamined++
                        val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                            session.treeUri,
                            documentId,
                        )
                        val signature = signatureInspector.inspect(documentUri)
                        when {
                            signature.state == "unavailable" -> stats.unavailableFiles++
                            signature.state == "unsupported" -> {
                                stats.unsupportedFiles++
                                if (signature.format != null &&
                                    signature.mimeType?.startsWith("image/") == true
                                ) {
                                    items += imageCandidate(
                                        session.treeUri,
                                        documentId,
                                        displayName,
                                        declaredMimeType,
                                        cursor.getLongOrNull(3),
                                        cursor.getLongOrNull(4),
                                        signature,
                                    )
                                }
                            }
                            signature.state == "valid" -> items += imageCandidate(
                                session.treeUri,
                                documentId,
                                displayName,
                                declaredMimeType,
                                cursor.getLongOrNull(3),
                                cursor.getLongOrNull(4),
                                signature,
                            )
                            else -> stats.invalidFilesRejected++
                        }
                    }
                }
                if (items.size >= pageSize || stats.entriesExamined >= MAX_ENTRIES_PER_PAGE) {
                    return directory
                }
                if (session.resourceLimitReached) return directory
            }
        } catch (_: SecurityException) {
            session.permissionGrantLost = true
            directory.closeCursor()
            return null
        } catch (_: Exception) {
            stats.unavailableDirectories++
            directory.closeCursor()
            return null
        }
        directory.closeCursor()
        return null
    }

    private fun imageCandidate(
        treeUri: Uri,
        documentId: String,
        displayName: String?,
        declaredMimeType: String?,
        byteSize: Long?,
        modifiedMillis: Long?,
        signature: ImageSignatureResult,
    ): Map<String, Any?> {
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
        return mapOf(
            "documentUri" to documentUri.toString(),
            "displayName" to displayName,
            "mimeType" to signature.mimeType,
            "declaredMimeType" to declaredMimeType,
            "detectedFormat" to signature.format,
            "relativeLocation" to relativeLocation(documentId),
            "byteSize" to byteSize,
            "modifiedMillis" to modifiedMillis,
        )
    }

    private fun createSession(treeUri: Uri): Session? {
        val rootId = runCatching { DocumentsContract.getTreeDocumentId(treeUri) }.getOrNull()
            ?: return null
        if (isRestrictedDocument(rootId)) return null
        val id = UUID.randomUUID().toString()
        val session = Session(id, treeUri)
        session.pending.addLast(DirectoryCursor(rootId))
        session.scheduledDirectories.add(rootId)
        sessions[id] = session
        return session
    }

    private fun hasReadGrant(treeUri: Uri): Boolean = runCatching {
        context.contentResolver.persistedUriPermissions.any {
            it.uri == treeUri && it.isReadPermission
        }
    }.getOrDefault(false)

    private fun isCancelled(session: Session, requestGeneration: Long): Boolean =
        session.cancelled ||
            Thread.currentThread().isInterrupted ||
            requestGeneration != cancellationGeneration.get()

    private fun relativeLocation(documentId: String): String? {
        val separator = documentId.indexOf(':')
        if (separator < 0) return null
        val path = documentId.substring(separator + 1).trim('/')
        val location = path.substringBeforeLast('/', "").trim('/')
        return location.takeIf { it.isNotEmpty() }
    }

    private fun isClearlyNonImage(declaredMimeType: String?, displayName: String?): Boolean {
        if (declaredMimeType.isNullOrBlank() || declaredMimeType.startsWith("image/")) return false
        val extension = displayName?.substringAfterLast('.', "")?.lowercase().orEmpty()
        return extension in UNRELATED_EXTENSIONS
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

    private data class DirectoryCursor(val documentId: String) {
        var cursor: Cursor? = null
        var visited: Boolean = false

        fun closeCursor() {
            runCatching { cursor?.close() }
            cursor = null
        }
    }

    private class Session(val id: String, val treeUri: Uri) {
        val pending = ArrayDeque<DirectoryCursor>()
        val scheduledDirectories = HashSet<String>()
        val visitedDirectories = HashSet<String>()
        val startedAtMillis = System.currentTimeMillis()
        var activeDirectory: DirectoryCursor? = null
        @Volatile var cancelled = false
        var permissionGrantLost = false
        var resourceLimitReached = false
        var totalEntriesExamined = 0
        var unavailableFiles = 0
        var unavailableDirectories = 0
        var pageNumber = 0
        var lastIssuedToken: String? = null

        fun closeOpenCursors() {
            activeDirectory?.closeCursor()
            activeDirectory = null
            pending.forEach { it.closeCursor() }
        }
    }

    private data class ScanStats(
        var filesExamined: Int = 0,
        var entriesExamined: Int = 0,
        var skippedNonImages: Int = 0,
        var invalidFilesRejected: Int = 0,
        var unavailableFiles: Int = 0,
        var unavailableDirectories: Int = 0,
        var unsupportedFiles: Int = 0,
        var duplicateDirectorySkips: Int = 0,
    )

    companion object {
        private const val MAXIMUM_PAGE_SIZE = 200
        private const val MAX_ENTRIES_PER_PAGE = 200
        private const val MAX_PENDING_DIRECTORIES = 5000
        private const val MAX_TRACKED_DIRECTORIES = 100000
        private const val MAX_TOTAL_ENTRIES = 1_000_000
        private val UNRELATED_EXTENSIONS = setOf(
            "mp4", "mkv", "avi", "mov", "mp3", "wav", "aac", "apk", "pdf",
            "zip", "rar", "7z", "doc", "docx", "xls", "xlsx",
        )
        private val PROJECTION = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE,
            Document.COLUMN_LAST_MODIFIED,
        )
    }
}
