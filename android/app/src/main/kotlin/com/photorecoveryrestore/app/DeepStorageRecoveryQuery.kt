package com.photorecoveryrestore.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Environment
import android.os.SystemClock
import android.os.storage.StorageManager

import java.io.File
import java.nio.file.DirectoryStream
import java.nio.file.Files
import java.nio.file.Path
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/** Bounded, metadata-first traversal of legitimately accessible shared storage. */
class DeepStorageRecoveryQuery(private val context: Context) {
    private val inspector = ImageSignatureInspector(context.contentResolver)
    private val embeddedImageCarver = EmbeddedImageCarver(context)
    // The cache performs one bounded on-disk prune on first use; lazy creation
    // keeps SharedPreferences I/O off MainActivity's UI thread.
    private val metadataCache by lazy { DeepScanMetadataCache(context) }
    // Container carving is confined to the thorough profile and to files
    // that the OS actually permits this app to read.
    private val sessions = ConcurrentHashMap<String, Session>()
    private val cancellationGeneration = AtomicLong(0L)

    fun capability(): Map<String, Any?> {
        val apiLevel = Build.VERSION.SDK_INT
        val supportsAllFilesAccess = apiLevel >= Build.VERSION_CODES.R
        val declaresAllFilesAccess = if (supportsAllFilesAccess) {
            runCatching {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.GET_PERMISSIONS,
                ).requestedPermissions?.contains(Manifest.permission.MANAGE_EXTERNAL_STORAGE) == true
            }.getOrDefault(false)
        } else false
        val allFilesGranted = supportsAllFilesAccess && Environment.isExternalStorageManager()
        val mediaReadGranted = hasSharedImageReadAccess()
        val legacyMode = apiLevel < Build.VERSION_CODES.Q ||
            (apiLevel == Build.VERSION_CODES.Q && Environment.isExternalStorageLegacy())
        val available = allFilesGranted || mediaReadGranted
        val status = if (available) "available" else "accessRequired"
        val reason = when {
            allFilesGranted -> "Broad shared-storage access is granted."
            mediaReadGranted && legacyMode -> "Legacy shared-image access is granted."
            mediaReadGranted -> "Shared image files are readable where scoped storage permits."
            else -> "Shared image access is required."
        }
        return mapOf(
            "status" to status,
            "available" to available,
            "requiresAllFilesAccess" to allFilesGranted,
            "accessMode" to when {
                allFilesGranted -> "allFilesAccess"
                legacyMode -> "legacySharedRead"
                else -> "scopedMediaRead"
            },
            "apiLevel" to apiLevel,
            // On API 30+, this is true only for variants that actually declare
            // the permission. The release manifest intentionally does not.
            "requestSupported" to (supportsAllFilesAccess && declaresAllFilesAccess && !allFilesGranted),
            "debugBuild" to
                ((context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0),
            "reason" to reason,
        )
    }

    fun currentCancellationGeneration(): Long = cancellationGeneration.get()

    /** Signals promptly from the UI thread without mutating a worker-owned queue. */
    fun requestCancellation(token: String?) {
        cancellationGeneration.incrementAndGet()
        val activeSessions = if (token == null) {
            sessions.values.toList()
        } else {
            listOfNotNull(sessions[token.substringBefore(':')])
        }
        activeSessions.forEach { it.cancelled = true }
    }

    /** Must run on the deep-storage executor after any active page has returned. */
    fun query(
        pageSize: Int,
        token: String?,
        profile: String,
        requestGeneration: Long = currentCancellationGeneration(),
        existingStorageLocationKeys: Set<String> = emptySet(),
    ): Map<String, Any?> {
        if (requestGeneration != cancellationGeneration.get()) {
            return failure("cancelled", "Deep scan cancelled safely.")
        }
        if (pageSize !in 1..MAXIMUM_PAGE_SIZE) {
            return failure("platformFailure", "Invalid deep-scan page size.")
        }
        if (!hasSharedImageReadAccess() &&
            !(Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager())
        ) {
            return failure("accessRequired", "Shared image access is not enabled.")
        }
        val sessionId = token?.substringBefore(':')
        val session = if (sessionId == null) {
            if (sessions.isNotEmpty()) {
                return failure("scanInProgress", "Another deep scan is still active.")
            }
            createSession(profile, existingStorageLocationKeys)
        } else sessions[sessionId]
            ?: return failure("invalidContinuation", "The deep-scan continuation expired.")
        if (requestGeneration != cancellationGeneration.get()) {
            session.cancelled = true
            session.closeOpenDirectories()
            session.pending.clear()
            session.deferredContainers.clear()
            sessions.remove(session.id)
            return failure("cancelled", "Deep scan cancelled safely.")
        }
        if (token != null && token != session.lastIssuedToken) {
            session.repeatedCursorDetections++
            session.closeOpenDirectories()
            session.pending.clear()
            session.deferredContainers.clear()
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
        val currentFilesSkippedAtPageStart = session.currentFilesSkipped
        val unavailableDirectoriesAtPageStart = session.unavailableDirectories
        val cacheHitsAtPageStart = session.signatureCacheHits
        val cacheMissesAtPageStart = session.signatureCacheMisses
        val duplicateDirectoriesAtPageStart = session.duplicateDirectorySkips
        val repeatedCursorsAtPageStart = session.repeatedCursorDetections

        scanPage@ while (
            (session.pending.isNotEmpty() || session.deferredContainers.isNotEmpty()) &&
                items.size < pageSize &&
                examinedThisPage < MAX_FILES_PER_PAGE
        ) {
            if (session.cancelled || Thread.currentThread().isInterrupted) {
                session.closeOpenDirectories()
                sessions.remove(session.id)
                metadataCache.flush()
                return failure("cancelled", "Deep scan cancelled safely.")
            }
            if (session.entriesExamined >= MAX_TOTAL_ENTRIES) {
                session.resourceLimitReached = true
                session.closeOpenDirectories()
                session.pending.clear()
                session.deferredContainers.clear()
                break
            }
            val work = if (session.pending.isNotEmpty()) session.pending.removeFirst()
                else session.deferredContainers.removeFirst()
            session.activeWork = work
            workConsumedThisPage++
            examinedThisPage++
            session.entriesExamined++
            val canonical = work.directory
            session.currentArea = if (work.carveOnly) "Embedded cache inspection"
                else categoryFor(canonical)
            if (!isAllowed(canonical, work.root)) {
                work.closeDirectory()
                session.activeWork = null
                continue
            }
            // A single live DirectoryStream per active work item avoids the
            // unbounded File.listFiles() arrays used by the earlier traversal.
            val iterator = if (work.carveOnly) null else work.iterator ?: try {
                val stream = Files.newDirectoryStream(canonical.toPath())
                work.directoryStream = stream
                stream.iterator().also { work.iterator = it }
            } catch (_: SecurityException) {
                session.unavailableDirectories++
                work.closeDirectory()
                session.activeWork = null
                continue
            } catch (_: Exception) {
                session.unavailableDirectories++
                work.closeDirectory()
                session.activeWork = null
                continue
            }
            if (!work.carveOnly && session.visited.add(canonical.path)) {
                session.directoriesExamined++
                session.openedVolumes.add(work.root.name)
                if (canonical.path == work.root.file.path) {
                    session.rootDirectoriesOpened++
                }
            }

            while (true) {
                if (session.cancelled || Thread.currentThread().isInterrupted) {
                    session.pending.addFirst(work)
                    session.closeOpenDirectories()
                    session.activeWork = null
                    sessions.remove(session.id)
                    metadataCache.flush()
                    return failure("cancelled", "Deep scan cancelled safely.")
                }
                if (session.entriesExamined >= MAX_TOTAL_ENTRIES) {
                    session.resourceLimitReached = true
                    session.pending.addFirst(work)
                    session.activeWork = null
                    break@scanPage
                }

                val pendingCarve = work.embeddedFile
                if (pendingCarve != null) {
                    val relative = work.embeddedRelative ?: pendingCarve.name
                    val carved = embeddedImageCarver.carvePage(
                        pendingCarve,
                        work.embeddedOffset,
                        minOf(MAX_CARVED_RESULTS_PER_WORK, pageSize - items.size),
                    ) { session.cancelled || Thread.currentThread().isInterrupted }
                    if (carved.storageLimitReached) {
                        session.carvedStorageLimitReached = true
                    }
                    if (carved.storageExhausted) {
                        session.carvedStorageExhausted = true
                        session.deferredContainers.clear()
                    }
                    if (carved.readFailure) session.unavailableFiles++
                    carved.items.forEach { payload ->
                        items += mapOf(
                            "filePath" to payload.file.absolutePath,
                            "canonicalPath" to null,
                            "containerPath" to pendingCarve.absolutePath,
                            "embeddedOffset" to payload.offset,
                            "displayName" to "${pendingCarve.name}_${payload.offset}.${payload.format}",
                            "mimeType" to payload.mimeType,
                            "detectedFormat" to payload.format,
                            "byteSize" to payload.file.length(),
                            "width" to payload.width,
                            "height" to payload.height,
                            "modifiedMillis" to pendingCarve.lastModified().takeIf { it > 0 },
                            "relativePath" to relative.substringBeforeLast('/', ""),
                            "storageVolumeName" to work.root.name,
                            "isRemovableStorage" to work.root.removable,
                            "source" to if (work.root.removable) "sdCard" else sourceFor(relative),
                            "isTrashLike" to evidenceFor(relative).trash,
                            "isThumbnailLike" to evidenceFor(relative).thumbnail,
                            "isCacheLike" to true,
                            "isRecoveryCopyLike" to evidenceFor(relative).recoveryCopy,
                            "isHidden" to isHiddenPath(relative),
                            "isExtensionMismatch" to true,
                            "isEmbeddedPayload" to true,
                        )
                    }
                    session.embeddedPayloads += carved.items.size
                    session.candidatesFound += carved.items.size
                    session.carvedTemporaryBytes += carved.items
                        .filter { it.newlyExtracted }.sumOf { it.file.length() }
                    if (carved.nextOffset != null) {
                        work.embeddedOffset = carved.nextOffset
                        session.pending.addFirst(work)
                        session.activeWork = null
                        break@scanPage
                    }
                    work.embeddedFile = null
                    work.embeddedRelative = null
                    work.embeddedOffset = 0L
                    if (work.carveOnly) {
                        work.closeDirectory()
                        session.activeWork = null
                        break
                    }
                    if (items.size >= pageSize || examinedThisPage >= MAX_FILES_PER_PAGE) {
                        session.pending.addFirst(work)
                        session.activeWork = null
                        break@scanPage
                    }
                    continue
                }

                val hasNext = try {
                    iterator?.hasNext() == true
                } catch (_: SecurityException) {
                    session.unavailableDirectories++
                    work.closeDirectory()
                    session.activeWork = null
                    false
                } catch (_: Exception) {
                    session.unavailableDirectories++
                    work.closeDirectory()
                    session.activeWork = null
                    false
                }
                if (!hasNext) {
                    work.closeDirectory()
                    session.activeWork = null
                    break
                }
                val child = try {
                    iterator!!.next().toFile()
                } catch (_: Exception) {
                    session.unavailableDirectories++
                    work.closeDirectory()
                    session.activeWork = null
                    break
                }
                work.entriesConsumed++
                examinedThisPage++
                session.entriesExamined++
                if (Files.isSymbolicLink(child.toPath())) continue
                if (child.isDirectory) {
                    if (!work.shallowRoot || session.scanAllSharedDirectories || shouldEnterFromRoot(child)) {
                        enqueueDirectory(session, child, work.root)
                    }
                } else {
                    session.filesExamined++
                    val relative = work.root.file.toPath().relativize(child.toPath())
                        .toString().replace('\\', '/')
                    val byteSize = child.length()
                    val modifiedMillis = child.lastModified()
                    val evidence = evidenceFor(relative)
                    val independentArtifact = evidence.trash || evidence.thumbnail ||
                        evidence.cache || evidence.recoveryCopy || isHiddenPath(relative) ||
                        (session.carveContainers && isImageContainer(child, relative))
                    if (!independentArtifact && currentStorageLocationKey(
                            work.root.name,
                            relative,
                            child.name,
                            byteSize,
                        ) in session.currentStorageLocationKeys
                    ) {
                        session.currentFilesSkipped++
                        if (examinedThisPage >= MAX_FILES_PER_PAGE) {
                            session.pending.addFirst(work)
                            session.activeWork = null
                            break@scanPage
                        }
                        continue
                    }
                    if (session.carveContainers && !session.carvedStorageExhausted &&
                        isImageContainer(child, relative)
                    ) {
                        // A renamed standalone image can itself end in .bin or .dat.
                        // Check its signature before treating it as a container.
                        val standalone = inspector.inspect(child)
                        session.standaloneFilesInspected++
                        session.signatureCacheMisses++
                        if (standalone.state == "valid" ||
                            (standalone.state == "unsupported" && standalone.format != null &&
                                standalone.mimeType?.startsWith("image/") == true)
                        ) {
                            items += fileCandidate(
                                child, byteSize, modifiedMillis, relative,
                                work.root, standalone,
                            )
                            session.candidatesFound++
                        } else if (standalone.state == "unavailable") {
                            session.unavailableFiles++
                        } else {
                            if (session.deferredContainers.size < MAX_PENDING_DIRECTORIES) {
                                session.deferredContainers.addLast(
                                    DirectoryWork(canonical, work.root, carveOnly = true).apply {
                                        embeddedFile = child
                                        embeddedRelative = relative
                                    },
                                )
                                session.containerFilesDeferred++
                            } else session.deferredContainerLimitReached = true
                        }
                    } else if (!shouldInspect(child)) {
                        session.filesSkippedByExtension++
                        if (child.extension.lowercase() in CONTAINER_EXTENSIONS) {
                            session.containerFilesDeferred++
                        }
                    } else {
                        // Broad legacy or user-granted access checks signatures
                        // even when an accessible file has an unfamiliar suffix.
                        val signature = metadataCache.get(
                            volume = work.root.name,
                            relativePath = relative,
                            size = byteSize,
                            modified = modifiedMillis,
                        )?.also { session.signatureCacheHits++ }
                            ?: inspector.inspect(child).also {
                                metadataCache.put(
                                    volume = work.root.name,
                                    relativePath = relative,
                                    size = byteSize,
                                    modified = modifiedMillis,
                                    signature = it,
                                )
                                session.signatureCacheMisses++
                            }
                        session.standaloneFilesInspected++
                        when {
                            signature.state == "unavailable" -> session.unavailableFiles++
                            signature.state == "unsupported" -> {
                                session.unsupportedFiles++
                                // A recognized signature whose platform decoder
                                // cannot expose bounds is unknown quality, not
                                // proof of corruption. Keep bytes as a possible
                                // copy; restore rechecks signature and digest.
                                if (signature.format != null &&
                                    signature.mimeType?.startsWith("image/") == true
                                ) {
                                    items += fileCandidate(
                                        child,
                                        byteSize,
                                        modifiedMillis,
                                        relative,
                                        work.root,
                                        signature,
                                    )
                                    session.candidatesFound++
                                }
                            }
                            signature.state != "valid" -> session.invalidFiles++
                            else -> {
                                items += fileCandidate(
                                    child,
                                    byteSize,
                                    modifiedMillis,
                                    relative,
                                    work.root,
                                    signature,
                                )
                                session.candidatesFound++
                            }
                        }
                    }
                }
                if (items.size >= pageSize || examinedThisPage >= MAX_FILES_PER_PAGE) {
                    session.pending.addFirst(work)
                    session.activeWork = null
                    break@scanPage
                }
            }
        }
        if (session.entriesExamined >= MAX_TOTAL_ENTRIES && !session.cancelled) {
            session.resourceLimitReached = true
            session.closeOpenDirectories()
            session.pending.clear()
            session.deferredContainers.clear()
        }
        var complete = session.pending.isEmpty() && session.deferredContainers.isEmpty()
        var completionReason = if (!complete) {
            "pageBoundary"
        } else when {
            session.resourceLimitReached || session.deferredContainerLimitReached ->
                "exhaustedWithResourceLimit"
            session.carvedStorageLimitReached -> "exhaustedWithCarvedStorageLimit"
            session.unavailableDirectories > 0 || session.unavailableFiles > 0 ->
                "exhaustedWithUnreadableEntries"
            else -> "exhausted"
        }
        var nextToken: String? = null
        if (!complete) {
            val stateId = traversalStateId(session)
            if (!session.issuedStateIds.add(stateId)) {
                session.repeatedCursorDetections++
                session.closeOpenDirectories()
                session.pending.clear()
                session.deferredContainers.clear()
                complete = true
                completionReason = "repeatedCursor"
            } else if (workConsumedThisPage == 0 && examinedThisPage == 0 && items.isEmpty()) {
                session.closeOpenDirectories()
                session.pending.clear()
                session.deferredContainers.clear()
                complete = true
                completionReason = "noProgress"
            } else {
                nextToken = "${session.id}:${++session.pageNumber}:$stateId"
                session.lastIssuedToken = nextToken
            }
        }
        if (complete) {
            session.closeOpenDirectories()
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
            "unavailableDirectories" to session.unavailableDirectories - unavailableDirectoriesAtPageStart,
            "unsupportedFiles" to session.unsupportedFiles - unsupportedAtPageStart,
            "volumesScanned" to session.openedVolumes.toList(),
            "rootDirectoriesOpened" to session.rootDirectoriesOpened,
            "currentArea" to session.currentArea,
            "embeddedPayloads" to session.embeddedPayloads,
            "carvedTemporaryBytes" to session.carvedTemporaryBytes,
            "carvedTempBytesReclaimed" to session.reclaimedCarvedBytes,
            "remainingDirectoryQueue" to session.pending.size + session.deferredContainers.size,
            "visitedDirectoryCount" to session.visited.size,
            "duplicateDirectorySkips" to
                session.duplicateDirectorySkips - duplicateDirectoriesAtPageStart,
            "repeatedCursorDetections" to
                session.repeatedCursorDetections - repeatedCursorsAtPageStart,
            "providerExhausted" to complete,
            "completionReason" to completionReason,
            "filesSkippedByExtension" to session.filesSkippedByExtension,
            "currentFilesSkipped" to
                (session.currentFilesSkipped - currentFilesSkippedAtPageStart),
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
            session.closeOpenDirectories()
            session.pending.clear()
            session.deferredContainers.clear()
            sessions.remove(session.id, session)
        }
        metadataCache.flush()
    }

    private fun createSession(
        profile: String,
        currentStorageLocationKeys: Set<String>,
    ): Session {
        val roots = discoverRoots()
        val reclaimedCarvedBytes = embeddedImageCarver.cleanupAbandonedParts()
        val priorityNames = listOf(
            ".Trash", ".trash", ".recycle", "RecycleBin", "LOST.DIR",
            ".thumbnails", "Thumbnails", ".cache", "Cache",
            "DCIM/.thumbnails", "DCIM/.cache", "DCIM/.trash",
            "Pictures/.thumbnails", "Pictures/.cache", "Pictures/.trash",
            "Pictures/Thumbnails", "Pictures/Previews",
            "Pictures/Recovered", "Pictures/Backups", "DCIM/Recovered",
            "Download/.thumbnails", "Download/.cache", "Download/Previews",
            "Pictures/Screenshots", "Download", "Android/media",
            "Android/media/com.whatsapp/WhatsApp/Media",
            "Android/media/org.telegram.messenger/Telegram", "DCIM", "Pictures",
        )
        val pending = ArrayDeque<DirectoryWork>()
        val scheduled = mutableSetOf<String>()
        fun schedule(root: VolumeRoot, directory: File, shallow: Boolean) {
            val canonical = runCatching { directory.canonicalFile }.getOrNull() ?: return
            if (!isAllowed(canonical, root) || !canonical.isDirectory) return
            if (scheduled.add(canonical.path)) pending.addLast(DirectoryWork(canonical, root, shallowRoot = shallow))
        }
        // Visit likely recovery locations first, then discover every other
        // accessible top-level directory in the thorough profile.
        roots.forEach { root ->
            priorityNames.forEach { name -> schedule(root, File(root.file, name), shallow = false) }
            schedule(root, root.file, shallow = true)
        }
        val session = Session(
            UUID.randomUUID().toString(), roots, pending,
            scheduledDirectories = scheduled,
            reclaimedCarvedBytes = reclaimedCarvedBytes,
            scanAllSharedDirectories = profile == "thorough",
            carveContainers = profile == "thorough",
            currentStorageLocationKeys = currentStorageLocationKeys,
        )
        sessions[session.id] = session
        return session
    }

    private fun enqueueDirectory(session: Session, directory: File, root: VolumeRoot) {
        if (session.resourceLimitReached) return
        val canonical = runCatching { directory.canonicalFile }.getOrNull() ?: return
        if (!isAllowed(canonical, root)) return
        if (canonical.path in session.scheduledDirectories) {
            session.duplicateDirectorySkips++
            return
        }
        if (session.pending.size >= MAX_PENDING_DIRECTORIES ||
            session.scheduledDirectories.size >= MAX_TRACKED_DIRECTORIES
        ) {
            session.resourceLimitReached = true
            return
        }
        session.scheduledDirectories.add(canonical.path)
        session.pending.addLast(DirectoryWork(canonical, root))
    }

    private fun shouldEnterFromRoot(directory: File): Boolean {
        val name = directory.name.lowercase()
        return name in ROOT_MEDIA_DIRECTORIES || name.startsWith(".") ||
            name.contains("trash") || name.contains("recycl") || name.contains("cache") ||
            name.contains("preview") || name.contains("media") || name.contains("whatsapp") ||
            name.contains("telegram") || name.contains("messenger")
    }

    private fun shouldInspect(file: File): Boolean {
        val extension = file.extension.lowercase()
        if (extension in IMAGE_EXTENSIONS) return true
        val size = file.length()
        // A small header probe can identify an image even when its filename
        // claims to be a video, database, or other unrelated format.
        return size in MIN_STANDALONE_IMAGE_BYTES..MAX_STANDALONE_IMAGE_BYTES
    }

    /** Matches only the exact identity already indexed as current media. */
    private fun currentStorageLocationKey(
        volume: String,
        relative: String,
        displayName: String,
        byteSize: Long,
    ): String? {
        if (byteSize < 0) return null
        val directory = relative.substringBeforeLast('/', "")
            .replace('\\', '/')
            .trim('/')
            .replace(Regex("/+"), "/")
        val normalizedVolume = volume.trim().lowercase()
        val normalizedName = displayName.trim().lowercase()
        if (normalizedVolume.isEmpty() || directory.isEmpty() || normalizedName.isEmpty()) {
            return null
        }
        return "$normalizedVolume|$directory|$normalizedName|$byteSize"
    }

    private fun isCarvingLocation(relative: String?): Boolean {
        // `relative` is already root-relative, so high-value folders can be the
        // first path segment (for example `.trash/photo.db` or `cache/photo.db`).
        val value = relative?.replace('\\', '/')?.trim('/')?.lowercase() ?: return false
        val segments = value.split('/').filter { it.isNotEmpty() }
        return segments.any { segment ->
            segment == "cache" || segment == ".cache" ||
                segment == "thumbnail" || segment == "thumbnails" ||
                segment == ".thumbnails" || segment == "thumbcache" ||
                segment == "preview" || segment == ".preview" ||
                segment == "previews" || segment == ".previews" ||
                segment == "temp" || segment == ".temp" ||
                segment == "tmp" || segment == ".tmp" ||
                segment == "recovered" || segment == "recovery" ||
                segment == "backup" || segment == "backups" ||
                segment == ".trash" || segment.startsWith(".trashed-")
        } || value.startsWith("android/media/") || value.startsWith("lost.dir/")
    }

    private fun isImageContainer(file: File, relative: String): Boolean {
        if (!isCarvingLocation(relative) || !file.canRead()) return false
        val name = file.name.lowercase()
        val extension = file.extension.lowercase()
        if (extension in IMAGE_EXTENSIONS || extension in UNRELATED_EXTENSIONS ||
            file.length() < MIN_STANDALONE_IMAGE_BYTES
        ) return false
        return extension in CONTAINER_EXTENSIONS || name.startsWith("thumbcache") ||
            name.endsWith(".db-wal") ||
            (file.length() <= MAX_UNKNOWN_CONTAINER_BYTES &&
                (extension.isEmpty() || evidenceFor(relative).cache ||
                    evidenceFor(relative).thumbnail || evidenceFor(relative).trash ||
                    evidenceFor(relative).recoveryCopy))
    }

    private fun fileCandidate(
        file: File,
        byteSize: Long,
        modifiedMillis: Long,
        relative: String,
        root: VolumeRoot,
        signature: ImageSignatureResult,
    ): Map<String, Any?> {
        val evidence = evidenceFor(relative)
        return mapOf(
            "filePath" to file.absolutePath,
            "canonicalPath" to null,
            "displayName" to file.name,
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
            "isRecoveryCopyLike" to evidence.recoveryCopy,
            "isHidden" to isHiddenPath(relative),
            "isExtensionMismatch" to extensionMismatch(file, signature.format),
        )
    }

    private fun traversalStateId(session: Session): String {
        val head = session.pending.peekFirst() ?: session.deferredContainers.peekFirst()
        val identity = if (head == null) {
            "empty"
        } else {
            val path = runCatching { head.directory.canonicalPath }.getOrDefault(head.directory.path)
            "$path:${head.entriesConsumed}:${head.embeddedOffset}:${head.iterator != null}:${session.pending.size}:${session.deferredContainers.size}:${session.visited.size}"
        }
        return UUID.nameUUIDFromBytes(identity.toByteArray(Charsets.UTF_8)).toString()
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
        "unavailableDirectories" to 0,
        "volumesScanned" to session.openedVolumes.toList(),
        "rootDirectoriesOpened" to session.rootDirectoriesOpened,
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
            val volumeName = when {
                removable -> canonical.name
                Build.VERSION.SDK_INT < Build.VERSION_CODES.Q -> "external"
                else -> "external_primary"
            }
            values += VolumeRoot(volumeName, canonical, removable)
        }
        add(Environment.getExternalStorageDirectory(), false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            context.getSystemService(StorageManager::class.java)
                ?.storageVolumes
                ?.forEach { volume -> add(volume.directory, volume.isRemovable) }
        }
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
        val segments = value.replace('\\', '/').split('/').filter { it.isNotEmpty() }
        return Evidence(
            trash = value.contains("/.trash/") || value.startsWith(".trash/") ||
                value.contains("/.trashed-") || value.startsWith(".trashed-") ||
                value.contains("/.recycle/") || value.contains("/recyclebin/"),
            thumbnail = segments.any {
                it == "thumbnail" || it == "thumbnails" ||
                    it == ".thumbnail" || it == ".thumbnails" ||
                    it == "thumb" || it == "thumbcache"
            } || value.contains("/thumb/"),
            cache = segments.any { it == "cache" || it == ".cache" ||
                it == "preview" || it == ".preview" ||
                it == "previews" || it == ".previews" ||
                it == "temp" || it == ".temp" || it == "tmp" || it == ".tmp" },
            recoveryCopy = segments.any {
                it == "recovered" || it == "recovery" ||
                    it == "backup" || it == "backups" || it == "restored"
            },
        )
    }

    private fun isHiddenPath(relative: String): Boolean =
        relative.replace('\\', '/').split('/').any { it.startsWith('.') && it.length > 1 }

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

    private fun hasSharedImageReadAccess(): Boolean =
        context.checkSelfPermission(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                Manifest.permission.READ_MEDIA_IMAGES
            else Manifest.permission.READ_EXTERNAL_STORAGE
        ) ==
            PackageManager.PERMISSION_GRANTED

    private data class VolumeRoot(val name: String, val file: File, val removable: Boolean)
    private class DirectoryWork(
        val directory: File,
        val root: VolumeRoot,
        val shallowRoot: Boolean = false,
        val carveOnly: Boolean = false,
    ) {
        var directoryStream: DirectoryStream<Path>? = null
        var iterator: Iterator<Path>? = null
        var entriesConsumed: Int = 0
        var embeddedFile: File? = null
        var embeddedRelative: String? = null
        var embeddedOffset: Long = 0L

        fun closeDirectory() {
            runCatching { directoryStream?.close() }
            directoryStream = null
            iterator = null
        }
    }
    private data class Evidence(
        val trash: Boolean,
        val thumbnail: Boolean,
        val cache: Boolean,
        val recoveryCopy: Boolean,
    )
    private data class Session(
        val id: String,
        val roots: List<VolumeRoot>,
        val pending: ArrayDeque<DirectoryWork>,
        val deferredContainers: ArrayDeque<DirectoryWork> = ArrayDeque(),
        val startedAtMillis: Long = SystemClock.elapsedRealtime(),
        val visited: MutableSet<String> = mutableSetOf(),
        val scheduledDirectories: MutableSet<String> = mutableSetOf(),
        val reclaimedCarvedBytes: Long = 0,
        val scanAllSharedDirectories: Boolean = false,
        val carveContainers: Boolean = false,
        val currentStorageLocationKeys: Set<String> = emptySet(),
        val issuedStateIds: MutableSet<String> = mutableSetOf(),
        @Volatile var cancelled: Boolean = false,
        var filesExamined: Int = 0,
        var entriesExamined: Int = 0,
        var directoriesExamined: Int = 0,
        var rootDirectoriesOpened: Int = 0,
        val openedVolumes: MutableSet<String> = mutableSetOf(),
        var candidatesFound: Int = 0,
        var invalidFiles: Int = 0,
        var unavailableFiles: Int = 0,
        var unavailableDirectories: Int = 0,
        var unsupportedFiles: Int = 0,
        var currentArea: String = "Shared storage",
        var embeddedPayloads: Int = 0,
        var carvedTemporaryBytes: Long = 0,
        var activeWork: DirectoryWork? = null,
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
        var carvedStorageLimitReached: Boolean = false,
        var carvedStorageExhausted: Boolean = false,
        var deferredContainerLimitReached: Boolean = false,
        var resourceLimitReached: Boolean = false,
    ) {
        fun closeOpenDirectories() {
            activeWork?.closeDirectory()
            activeWork = null
            pending.forEach { it.closeDirectory() }
            deferredContainers.forEach { it.closeDirectory() }
        }
    }

    companion object {
        private const val MAXIMUM_PAGE_SIZE = 200
        private const val MAX_FILES_PER_PAGE = 2000
        private const val MAX_TOTAL_ENTRIES = 1000000
        private const val MAX_PENDING_DIRECTORIES = 5000
        private const val MAX_TRACKED_DIRECTORIES = 100000
        private const val MAX_CARVED_RESULTS_PER_WORK = 4
        private const val MIN_STANDALONE_IMAGE_BYTES = 32L
        private const val MAX_STANDALONE_IMAGE_BYTES = 128L * 1024 * 1024
        private const val MAX_UNKNOWN_CONTAINER_BYTES = 128L * 1024 * 1024
        private val IMAGE_EXTENSIONS = setOf("jpg", "jpeg", "png", "webp", "gif", "bmp", "tif", "tiff", "heic", "heif", "avif")
        private val UNRELATED_EXTENSIONS = setOf("mp4", "mkv", "avi", "mov", "mp3", "wav", "aac", "apk", "pdf", "zip", "rar", "7z", "doc", "docx", "xls", "xlsx")
        private val CONTAINER_EXTENSIONS = setOf(
            "db", "db3", "sqlite", "sqlite3", "cache", "bin", "dat", "tmp",
            "blob", "thumb", "thumbcache", "ldb", "sst", "pack", "idx", "journal", "wal",
        )
        private val ROOT_MEDIA_DIRECTORIES = setOf("dcim", "pictures", "download", "downloads", "android", "movies")
    }
}
