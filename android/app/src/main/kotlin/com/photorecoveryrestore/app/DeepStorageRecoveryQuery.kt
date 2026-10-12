package com.photorecoveryrestore.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.os.SystemClock

import java.io.File
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** Bounded, metadata-first traversal of legitimately accessible shared storage. */
class DeepStorageRecoveryQuery(private val context: Context) {
    private val inspector = ImageSignatureInspector(context.contentResolver)
    private val embeddedImageCarver = EmbeddedImageCarver(context)
    private val metadataCache = DeepScanMetadataCache(context)
    // The carver remains available for a future explicit thorough pass. The
    // standard deep pass deliberately never traverses database/cache payloads.
    private val sessions = ConcurrentHashMap<String, Session>()

    fun capability(): Map<String, Any?> {
        val usesAllFilesAccess = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
        val available = if (usesAllFilesAccess) {
            Environment.isExternalStorageManager()
        } else {
            hasLegacySharedReadAccess()
        }
        val requestSupported = if (usesAllFilesAccess) {
            val requested = runCatching {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.GET_PERMISSIONS,
                ).requestedPermissions?.toSet().orEmpty()
            }.getOrDefault(emptySet())
            Manifest.permission.MANAGE_EXTERNAL_STORAGE in requested
        } else true
        val status = when {
            available -> "available"
            requestSupported -> "accessRequired"
            else -> "unavailable"
        }
        return mapOf(
            "status" to status,
            "available" to available,
            "requiresAllFilesAccess" to usesAllFilesAccess,
            "accessMode" to if (usesAllFilesAccess) "allFilesAccess" else "legacySharedRead",
            "apiLevel" to Build.VERSION.SDK_INT,
            "requestSupported" to requestSupported,
        )
    }

    fun query(
        pageSize: Int,
        token: String?,
        profile: String,
        currentMediaLocations: Set<String> = emptySet(),
    ): Map<String, Any?> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !Environment.isExternalStorageManager()) {
            return failure("accessRequired", "Deep storage access is not enabled.")
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R && !hasLegacySharedReadAccess()) {
            return failure("accessRequired", "Shared image access is not enabled.")
        }
        val sessionId = token?.substringBefore(':')
        val session = if (sessionId == null) createSession(profile, currentMediaLocations) else sessions[sessionId]
            ?: return failure("invalidContinuation", "The deep-scan continuation expired.")
        if (token != null && token != session.lastIssuedToken) {
            session.repeatedCursorDetections++
            session.pending.clear()
            sessions.remove(session.id)
            return terminalPage(session, "repeatedCursor")
        }
        val items = mutableListOf<Map<String, Any?>>()
        var examinedThisPage = 0
        var workConsumedThisPage = 0
        val directoriesAtPageStart = session.directoriesExamined
        val filesAtPageStart = session.filesExamined
        val candidatesAtPageStart = session.candidatesFound
        val invalidAtPageStart = session.invalidFiles
        val unavailableAtPageStart = session.unavailableFiles
        val unsupportedAtPageStart = session.unsupportedFiles
        val currentSkippedAtPageStart = session.currentFilesSkipped
        val cacheHitsAtPageStart = session.signatureCacheHits
        val cacheMissesAtPageStart = session.signatureCacheMisses
        val duplicateDirectoriesAtPageStart = session.duplicateDirectorySkips
        val repeatedCursorsAtPageStart = session.repeatedCursorDetections
        scanPage@ while (
            session.pending.isNotEmpty() &&
                items.size < pageSize &&
                examinedThisPage < MAX_FILES_PER_PAGE
        ) {
            if (session.cancelled) {
                sessions.remove(session.id)
                metadataCache.flush()
                return failure("cancelled", "Deep scan cancelled safely.")
            }
            val work = session.pending.removeFirst()
            workConsumedThisPage++
            // A directory work item is itself an examined entry. This keeps the
            // budget strict even for empty, inaccessible, or duplicate folders.
            examinedThisPage++
            session.entriesExamined++
            val canonical = work.directory
            session.currentArea = categoryFor(canonical)
            if (!isAllowed(canonical, work.root)) continue
            if (work.nextChildIndex == 0 && work.embeddedOffset == 0L) {
                if (!session.visited.add(canonical.path)) continue
                session.directoriesExamined++
            } else if (!session.visited.contains(canonical.path)) {
                continue
            }
            val children = work.children ?: runCatching { canonical.listFiles() }.getOrNull() ?: continue
            for (index in work.nextChildIndex until children.size) {
                if (session.cancelled || Thread.currentThread().isInterrupted) {
                    sessions.remove(session.id)
                    metadataCache.flush()
                    return failure("cancelled", "Deep scan cancelled safely.")
                }
                val child = children[index]
                // Every entry consumes the page budget, including directories,
                // current media and extension-filtered files.
                examinedThisPage++
                session.entriesExamined++
                if (child.isDirectory) {
                    if (!work.shallowRoot || shouldEnterFromRoot(child)) {
                        enqueueDirectory(session, child, work.root)
                    }
                } else {
                    session.filesExamined++
                    val root = work.root
                    val relative = root.file.toPath().relativize(child.toPath())
                        .toString().replace('\\', '/')
                    if (session.currentMediaLocations.contains(
                            currentMediaKey(root.name, relative, child.length()),
                        )) {
                        session.currentFilesSkipped++
                    } else if (session.thorough && child.extension.lowercase() in CONTAINER_EXTENSIONS &&
                        isCarvingLocation(relative)
                    ) {
                        val carved = embeddedImageCarver.carvePage(
                            child,
                            work.embeddedOffset,
                            minOf(MAX_CARVED_RESULTS_PER_WORK, pageSize - items.size),
                        ) { session.cancelled || Thread.currentThread().isInterrupted }
                        carved.items.forEach { payload ->
                            items += mapOf(
                                "filePath" to payload.file.absolutePath,
                                "canonicalPath" to null,
                                "containerPath" to child.absolutePath,
                                "embeddedOffset" to payload.offset,
                                "displayName" to "${child.name}_${payload.offset}.${payload.format}",
                                "mimeType" to payload.mimeType,
                                "detectedFormat" to payload.format,
                                "byteSize" to payload.file.length(),
                                "width" to payload.width,
                                "height" to payload.height,
                                "modifiedMillis" to child.lastModified().takeIf { it > 0 },
                                "relativePath" to relative.substringBeforeLast('/', ""),
                                "storageVolumeName" to root.name,
                                "isRemovableStorage" to root.removable,
                                "source" to if (root.removable) "sdCard" else sourceFor(relative),
                                "isTrashLike" to evidenceFor(relative).trash,
                                "isThumbnailLike" to false,
                                "isCacheLike" to true,
                                "isHidden" to child.name.startsWith('.'),
                                "isExtensionMismatch" to true,
                                "isEmbeddedPayload" to true,
                            )
                        }
                        session.embeddedPayloads += carved.items.size
                        session.carvedTemporaryBytes += carved.items.sumOf { it.file.length() }
                        if (carved.nextOffset != null) {
                            session.pending.addFirst(
                                DirectoryWork(canonical, root, children, index, carved.nextOffset),
                            )
                            break@scanPage
                        }
                    } else if (!shouldInspect(child, relative)) {
                        session.filesSkippedByExtension++
                        if (child.extension.lowercase() in CONTAINER_EXTENSIONS) {
                            session.containerFilesDeferred++
                        }
                    } else {
                        val byteSize = child.length()
                        val modifiedMillis = child.lastModified()
                        val relativeIdentity = relative
                        val signature = metadataCache.get(
                            volume = root.name,
                            relativePath = relativeIdentity,
                            size = byteSize,
                            modified = modifiedMillis,
                        )?.also { session.signatureCacheHits++ }
                            ?: inspector.inspect(child).also {
                                metadataCache.put(
                                    volume = root.name,
                                    relativePath = relativeIdentity,
                                    size = byteSize,
                                    modified = modifiedMillis,
                                    signature = it,
                                )
                                session.signatureCacheMisses++
                            }
                        session.standaloneFilesInspected++
                        if (signature.state == "unavailable") {
                            session.unavailableFiles++
                        } else if (signature.state == "unsupported") {
                            session.unsupportedFiles++
                        } else if (signature.state != "valid") {
                            session.invalidFiles++
                        } else {
                            val evidence = evidenceFor(relative)
                            items += mapOf(
                                "filePath" to child.absolutePath,
                                "canonicalPath" to null,
                                "displayName" to child.name,
                                "mimeType" to signature.mimeType,
                                "detectedFormat" to signature.format,
                                "byteSize" to byteSize,
                                "width" to signature.width,
                                "height" to signature.height,
                                "modifiedMillis" to modifiedMillis.takeIf { it > 0 },
                                "relativePath" to relative.substringBeforeLast('/', ""),
                                "storageVolumeName" to root.name,
                                "isRemovableStorage" to root.removable,
                                "source" to if (root.removable) "sdCard" else sourceFor(relative),
                                "isTrashLike" to evidence.trash,
                                "isThumbnailLike" to evidence.thumbnail,
                                "isCacheLike" to evidence.cache,
                                "isHidden" to child.name.startsWith('.'),
                                "isExtensionMismatch" to extensionMismatch(child, signature.format),
                            )
                            session.candidatesFound++
                        }
                    }
                }
                if (items.size >= pageSize || examinedThisPage >= MAX_FILES_PER_PAGE) {
                    if (index + 1 < children.size) {
                        session.pending.addFirst(DirectoryWork(canonical, work.root, children, index + 1))
                    }
                    break@scanPage
                }
            }
        }
        var complete = session.pending.isEmpty()
        var completionReason = if (complete) "exhausted" else "pageBoundary"
        var nextToken: String? = null
        if (!complete) {
            val stateId = traversalStateId(session)
            if (!session.issuedStateIds.add(stateId)) {
                session.repeatedCursorDetections++
                session.pending.clear()
                complete = true
                completionReason = "repeatedCursor"
            } else if (workConsumedThisPage == 0 && examinedThisPage == 0 && items.isEmpty()) {
                session.pending.clear()
                complete = true
                completionReason = "noProgress"
            } else {
                nextToken = "${session.id}:${++session.pageNumber}:$stateId"
                session.lastIssuedToken = nextToken
            }
        }
        if (complete) {
            sessions.remove(session.id)
            metadataCache.flush()
        }
        return mapOf(
            "status" to "success",
            "items" to items,
            "nextContinuationToken" to nextToken,
            "filesExamined" to (session.filesExamined - filesAtPageStart),
            "entriesExamined" to examinedThisPage,
            "directoriesExamined" to session.directoriesExamined - directoriesAtPageStart,
            "directoryWorkConsumed" to workConsumedThisPage,
            "candidatesFound" to session.candidatesFound - candidatesAtPageStart,
            "invalidFilesRejected" to session.invalidFiles - invalidAtPageStart,
            "unavailableFiles" to session.unavailableFiles - unavailableAtPageStart,
            "unsupportedFiles" to session.unsupportedFiles - unsupportedAtPageStart,
            "volumesScanned" to session.roots.map { it.name },
            "currentArea" to session.currentArea,
            "embeddedPayloads" to session.embeddedPayloads,
            "carvedTemporaryBytes" to session.carvedTemporaryBytes,
            "carvedTempBytesReclaimed" to session.reclaimedCarvedBytes,
            "remainingDirectoryQueue" to session.pending.size,
            "visitedDirectoryCount" to session.visited.size,
            "duplicateDirectorySkips" to
                session.duplicateDirectorySkips - duplicateDirectoriesAtPageStart,
            "repeatedCursorDetections" to
                session.repeatedCursorDetections - repeatedCursorsAtPageStart,
            "providerExhausted" to complete,
            "completionReason" to completionReason,
            "filesSkippedByExtension" to session.filesSkippedByExtension,
            "currentFilesSkipped" to session.currentFilesSkipped - currentSkippedAtPageStart,
            "standaloneFilesInspected" to session.standaloneFilesInspected,
            "containerFilesDeferred" to session.containerFilesDeferred,
            "signatureCacheHits" to session.signatureCacheHits - cacheHitsAtPageStart,
            "signatureCacheMisses" to session.signatureCacheMisses - cacheMissesAtPageStart,
            "nativeTraversalMs" to (SystemClock.elapsedRealtime() - session.startedAtMillis),
        )
    }

    fun cancel(token: String?) {
        val activeSessions = if (token == null) {
            sessions.values.toList()
        } else {
            listOfNotNull(sessions[token.substringBefore(':')])
        }
        activeSessions.forEach { session ->
            session.cancelled = true
            session.pending.clear()
            sessions.remove(session.id, session)
        }
        metadataCache.flush()
    }

    private fun createSession(
        profile: String,
        currentMediaLocations: Set<String>,
    ): Session {
        val roots = discoverRoots()
        val reclaimedCarvedBytes = embeddedImageCarver.cleanupAbandonedParts()
        val priorityNames = listOf(
            ".Trash", ".trash", ".recycle", "RecycleBin", "LOST.DIR",
            "DCIM/.thumbnails", "DCIM/.trash", "Pictures/.trash",
            "Pictures/Screenshots", "Download", "Android/media",
            "Android/media/com.whatsapp/WhatsApp/Media",
            "Android/media/org.telegram.messenger/Telegram", "DCIM", "Pictures",
        )
        val pending = ArrayDeque<DirectoryWork>()
        val scheduled = mutableSetOf<String>()
        fun schedule(root: VolumeRoot, directory: File, shallow: Boolean) {
            val canonical = runCatching { directory.canonicalFile }.getOrNull() ?: return
            if (!isAllowed(canonical, root)) return
            if (scheduled.add(canonical.path)) pending.addLast(DirectoryWork(canonical, root, shallowRoot = shallow))
        }
        // A root is read only one level deep. It discovers direct images and
        // approved media/recovery folders without turning fastDeep into a full
        // shared-storage crawl.
        roots.forEach { root ->
            schedule(root, root.file, shallow = true)
            priorityNames.forEach { name -> schedule(root, File(root.file, name), shallow = false) }
        }
        val session = Session(
            UUID.randomUUID().toString(), roots, pending,
            scheduledDirectories = scheduled,
            reclaimedCarvedBytes = reclaimedCarvedBytes,
            // Existing-media exclusion remains authoritative in Dart. Avoid a
            // second full MediaStore walk here.
            currentMediaLocations = currentMediaLocations,
            thorough = profile == "thorough",
        )
        sessions[session.id] = session
        return session
    }

    private fun enqueueDirectory(session: Session, directory: File, root: VolumeRoot) {
        val canonical = runCatching { directory.canonicalFile }.getOrNull() ?: return
        if (!isAllowed(canonical, root)) return
        if (!session.scheduledDirectories.add(canonical.path)) {
            session.duplicateDirectorySkips++
            return
        }
        session.pending.addLast(DirectoryWork(canonical, root))
    }

    private fun shouldEnterFromRoot(directory: File): Boolean {
        val name = directory.name.lowercase()
        return name in ROOT_MEDIA_DIRECTORIES || name.startsWith(".") ||
            name.contains("trash") || name.contains("recycl") || name.contains("cache") ||
            name.contains("preview") || name.contains("media") || name.contains("whatsapp") ||
            name.contains("telegram") || name.contains("messenger")
    }

    private fun shouldInspect(file: File, relative: String?): Boolean {
        val extension = file.extension.lowercase()
        if (extension in IMAGE_EXTENSIONS) return true
        if (extension in UNRELATED_EXTENSIONS) return false
        val evidence = evidenceFor(relative ?: file.name)
        val highValue = evidence.trash || evidence.thumbnail || evidence.cache ||
            (relative?.lowercase()?.let { it.startsWith("dcim/") || it.startsWith("pictures/") ||
                it.startsWith("download/") || it.startsWith("android/media/") } == true)
        return extension.isEmpty() || highValue
    }

    private fun isCarvingLocation(relative: String?): Boolean {
        val value = relative?.lowercase() ?: return false
        return value.contains("/cache/") || value.contains("/preview/") ||
            value.contains("/previews/") || value.startsWith("android/media/") ||
            value.contains("/.trash/") || value.contains("/.trashed-")
    }

    private fun currentMediaKey(
        volume: String,
        relativeFile: String?,
        size: Long,
    ): String? {
        val normalized = relativeFile?.replace('\\', '/')?.trim('/')?.lowercase()
            ?.takeIf { it.isNotBlank() }
            ?: return null
        val separator = normalized.lastIndexOf('/')
        if (separator <= 0 || separator == normalized.lastIndex) return null
        val relativePath = normalized.substring(0, separator)
        val displayName = normalized.substring(separator + 1)
        return "${volume.lowercase()}|$relativePath|$displayName|$size"
    }
    private fun traversalStateId(session: Session): String {
        val head = session.pending.peekFirst()
        val identity = if (head == null) {
            "empty"
        } else {
            val path = runCatching { head.directory.canonicalPath }.getOrDefault(head.directory.path)
            "$path:${head.nextChildIndex}:${head.embeddedOffset}:${session.pending.size}:${session.visited.size}"
        }
        return identity.hashCode().toUInt().toString(16)
    }

    private fun terminalPage(session: Session, reason: String): Map<String, Any?> = mapOf(
        "status" to "success",
        "items" to emptyList<Map<String, Any?>>(),
        "nextContinuationToken" to null,
        "filesExamined" to 0,
        "directoriesExamined" to 0,
        "directoryWorkConsumed" to 0,
        "candidatesFound" to 0,
        "invalidFilesRejected" to 0,
        "unavailableFiles" to 0,
        "volumesScanned" to session.roots.map { it.name },
        "currentArea" to session.currentArea,
        "embeddedPayloads" to session.embeddedPayloads,
        "remainingDirectoryQueue" to 0,
        "visitedDirectoryCount" to session.visited.size,
        "duplicateDirectorySkips" to 0,
        "repeatedCursorDetections" to if (reason == "repeatedCursor") 1 else 0,
        "providerExhausted" to true,
        "completionReason" to reason,
        "filesSkippedByExtension" to session.filesSkippedByExtension,
        "currentFilesSkipped" to session.currentFilesSkipped,
        "standaloneFilesInspected" to session.standaloneFilesInspected,
        "containerFilesDeferred" to session.containerFilesDeferred,
    )

    private fun discoverRoots(): List<VolumeRoot> {
        val values = mutableListOf<VolumeRoot>()
        fun add(file: File?, removable: Boolean) {
            val canonical = file?.let { runCatching { it.canonicalFile }.getOrNull() } ?: return
            if (!canonical.exists() || values.any { it.file.path == canonical.path }) return
            values += VolumeRoot(if (removable) canonical.name else "external_primary", canonical, removable)
        }
        add(Environment.getExternalStorageDirectory(), false)
        context.getExternalFilesDirs(null).filterNotNull().forEach { appDir ->
            var root: File? = appDir
            repeat(4) { root = root?.parentFile }
            add(root, Environment.isExternalStorageRemovable(appDir))
        }
        return values
    }

    private fun isAllowed(file: File, root: VolumeRoot) =
        !isRestricted(file) && isWithin(file, root.file)

    private fun isWithin(file: File, root: File): Boolean {
        val path = runCatching { file.canonicalPath }.getOrNull() ?: return false
        val rootPath = root.path.trimEnd(File.separatorChar)
        return path == rootPath || path.startsWith(rootPath + File.separator)
    }

    private fun isRestricted(file: File): Boolean {
        val normalized = file.path.replace('\\', '/').lowercase()
        return normalized.contains("/android/data/") || normalized.endsWith("/android/data") ||
            normalized.contains("/android/obb/") || normalized.endsWith("/android/obb")
    }

    private fun sourceFor(path: String?): String {
        val value = path?.lowercase() ?: return "unknown"
        return when {
            value.contains("whatsapp") || value.contains("telegram") || value.contains("messenger") || value.contains("signal") || value.contains("viber") -> "messagingSharedMedia"
            value.startsWith("pictures/screenshots") || value.contains("/screenshots/") -> "screenshots"
            value.startsWith("download/") -> "downloadsSavedMedia"
            value.startsWith("dcim/") || value.startsWith("pictures/") -> "cameraGallery"
            else -> "unknown"
        }
    }

    private fun evidenceFor(path: String): Evidence {
        val value = path.lowercase()
        return Evidence(
            trash = value.contains("/.trash/") || value.startsWith(".trash/") ||
                value.contains("/.trashed-") || value.startsWith(".trashed-") ||
                value.contains("/.recycle/") || value.contains("/recyclebin/"),
            thumbnail = value.contains("/.thumbnails/") || value.contains("/thumbnail") || value.contains("/thumb/"),
            cache = value.contains("/cache/") || value.contains("/preview/") || value.contains("/previews/"),
        )
    }

    private fun categoryFor(file: File): String {
        val value = file.path.replace('\\', '/').lowercase()
        return when {
            value.contains("/.trash") || value.contains("/.trashed-") -> "Trash locations"
            value.contains("thumbnail") || value.contains("/thumb/") -> "Thumbnail locations"
            value.contains("/download") -> "Downloads"
            value.contains("/android/media") -> "Shared app media"
            value.contains("/dcim") -> "Camera media"
            value.contains("/pictures") -> "Pictures"
            else -> "Shared storage"
        }
    }

    private fun extensionMismatch(file: File, format: String?): Boolean {
        val extension = file.extension.lowercase()
        if (extension.isEmpty()) return true
        val expected = when (format) {
            "jpeg" -> setOf("jpg", "jpeg")
            "tiff" -> setOf("tif", "tiff")
            "heif" -> setOf("heif", "heic")
            else -> setOfNotNull(format)
        }
        return extension !in expected
    }

    private fun failure(code: String, message: String) =
        mapOf("status" to "failure", "code" to code, "message" to message)

    private fun hasLegacySharedReadAccess(): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED

    private data class VolumeRoot(val name: String, val file: File, val removable: Boolean)
    private data class DirectoryWork(
        val directory: File,
        val root: VolumeRoot,
        val children: Array<File>? = null,
        val nextChildIndex: Int = 0,
        val embeddedOffset: Long = 0,
        val shallowRoot: Boolean = false,
    )
    private data class Evidence(val trash: Boolean, val thumbnail: Boolean, val cache: Boolean)
    private data class Session(
        val id: String,
        val roots: List<VolumeRoot>,
        val pending: ArrayDeque<DirectoryWork>,
        val startedAtMillis: Long = SystemClock.elapsedRealtime(),
        val visited: MutableSet<String> = mutableSetOf(),
        val scheduledDirectories: MutableSet<String> = mutableSetOf(),
        val reclaimedCarvedBytes: Long = 0,
        val currentMediaLocations: Set<String> = emptySet(),
        val thorough: Boolean = false,
        val issuedStateIds: MutableSet<String> = mutableSetOf(),
        @Volatile var cancelled: Boolean = false,
        var filesExamined: Int = 0,
        var entriesExamined: Int = 0,
        var directoriesExamined: Int = 0,
        var candidatesFound: Int = 0,
        var invalidFiles: Int = 0,
        var unavailableFiles: Int = 0,
        var unsupportedFiles: Int = 0,
        var currentArea: String = "Shared storage",
        var embeddedPayloads: Int = 0,
        var carvedTemporaryBytes: Long = 0,
        var pageNumber: Int = 0,
        var lastIssuedToken: String? = null,
        var duplicateDirectorySkips: Int = 0,
        var repeatedCursorDetections: Int = 0,
        var filesSkippedByExtension: Int = 0,
        var currentFilesSkipped: Int = 0,
        var standaloneFilesInspected: Int = 0,
        var containerFilesDeferred: Int = 0,
        var signatureCacheHits: Int = 0,
        var signatureCacheMisses: Int = 0,
    )

    companion object {
        private const val MAX_FILES_PER_PAGE = 2000
        private const val MAX_CARVED_RESULTS_PER_WORK = 4
        private val IMAGE_EXTENSIONS = setOf("jpg", "jpeg", "png", "webp", "gif", "bmp", "tif", "tiff", "heic", "heif", "avif")
        private val UNRELATED_EXTENSIONS = setOf("mp4", "mkv", "avi", "mov", "mp3", "wav", "aac", "apk", "pdf", "zip", "rar", "7z", "doc", "docx", "xls", "xlsx")
        private val CONTAINER_EXTENSIONS = setOf("db", "sqlite", "cache", "bin", "dat", "tmp")
        private val ROOT_MEDIA_DIRECTORIES = setOf("dcim", "pictures", "download", "downloads", "android", "movies")
    }
}
