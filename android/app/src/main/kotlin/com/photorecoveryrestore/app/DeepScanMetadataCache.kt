package com.photorecoveryrestore.app

import android.content.Context
import org.json.JSONObject
import java.util.LinkedHashMap

/** App-private, metadata-only cache for unchanged shared-storage inspections. */
class DeepScanMetadataCache(context: Context) {
    private val preferences = context.getSharedPreferences("deep_scan_metadata", Context.MODE_PRIVATE)
    private val memory = object : LinkedHashMap<String, CacheEntry>(MAX_MEMORY_ENTRIES, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, CacheEntry>?): Boolean =
            size > MAX_MEMORY_ENTRIES
    }
    private val pending = LinkedHashMap<String, String>()

    init {
        prunePersistedEntries()
    }

    @Synchronized
    fun get(volume: String, relativePath: String, size: Long, modified: Long): ImageSignatureResult? {
        val key = key(volume, relativePath)
        memory[key]?.let { entry ->
            if (isExpired(entry) || !isStable(entry.signature)) {
                removeExpired(key)
                return null
            }
            return entry.signature.takeIf { entry.size == size && entry.modified == modified }
        }
        val raw = preferences.getString(key, null) ?: return null
        val entry = decode(raw) ?: return null
        if (isExpired(entry) || !isStable(entry.signature)) {
            removeExpired(key)
            return null
        }
        memory[key] = entry
        return entry.signature.takeIf { entry.size == size && entry.modified == modified }
    }

    @Synchronized
    fun put(
        volume: String,
        relativePath: String,
        size: Long,
        modified: Long,
        signature: ImageSignatureResult,
    ) {
        if (!isStable(signature)) return
        val key = key(volume, relativePath)
        val entry = CacheEntry(size, modified, System.currentTimeMillis(), signature)
        memory[key] = entry
        pending[key] = encode(entry)
        if (pending.size >= PERSIST_BATCH_SIZE) flushLocked()
    }

    @Synchronized
    fun flush() = flushLocked()

    private fun removeExpired(key: String) {
        memory.remove(key)
        pending.remove(key)
        preferences.edit().remove(key).apply()
    }

    private fun flushLocked() {
        if (pending.isEmpty()) return
        val editor = preferences.edit()
        pending.forEach { (key, value) -> editor.putString(key, value) }
        editor.apply()
        pending.clear()
    }

    private fun isExpired(entry: CacheEntry): Boolean =
        entry.savedAtMillis <= 0L || System.currentTimeMillis() - entry.savedAtMillis > MAX_AGE_MILLIS

    private fun isStable(signature: ImageSignatureResult): Boolean =
        signature.state != "unavailable" && signature.state != "corrupted"

    /** Bounds persistent metadata-only cache growth after interrupted/old scans. */
    private fun prunePersistedEntries() {
        val persisted = preferences.all.entries.mapNotNull { (key, raw) ->
            if (!key.startsWith("v:")) return@mapNotNull null
            val entry = (raw as? String)?.let(::decode)
            if (entry == null || isExpired(entry) || !isStable(entry.signature)) key to null
            else key to entry.savedAtMillis
        }
        val valid = persisted.filter { it.second != null }
            .sortedByDescending { it.second }
            .take(MAX_PERSISTED_ENTRIES)
            .mapTo(mutableSetOf()) { it.first }
        val remove = persisted.asSequence()
            .map { it.first }
            .filterNot(valid::contains)
            .toList()
        if (remove.isEmpty()) return
        val editor = preferences.edit()
        remove.forEach(editor::remove)
        editor.apply()
    }

    private fun decode(raw: String): CacheEntry? = runCatching {
        val row = JSONObject(raw)
        CacheEntry(
            size = row.optLong("size", -1L),
            modified = row.optLong("modified", -1L),
            savedAtMillis = row.optLong("savedAtMillis", 0L),
            signature = ImageSignatureResult(
                state = row.getString("state"),
                format = row.optString("format").takeIf { it.isNotBlank() },
                mimeType = row.optString("mime").takeIf { it.isNotBlank() },
                width = row.optInt("width", 0).takeIf { it > 0 },
                height = row.optInt("height", 0).takeIf { it > 0 },
            ),
        )
    }.getOrNull()

    private fun encode(entry: CacheEntry): String = JSONObject().apply {
        put("size", entry.size)
        put("modified", entry.modified)
        put("savedAtMillis", entry.savedAtMillis)
        put("state", entry.signature.state)
        put("format", entry.signature.format)
        put("mime", entry.signature.mimeType)
        put("width", entry.signature.width ?: 0)
        put("height", entry.signature.height ?: 0)
    }.toString()

    private fun key(volume: String, relativePath: String) =
        "v:" + volume.lowercase() + ":" + relativePath.lowercase().replace('\\', '/')

    private data class CacheEntry(
        val size: Long,
        val modified: Long,
        val savedAtMillis: Long,
        val signature: ImageSignatureResult,
    )

    companion object {
        private const val MAX_MEMORY_ENTRIES = 512
        private const val MAX_PERSISTED_ENTRIES = 10000
        private const val PERSIST_BATCH_SIZE = 64
        private const val MAX_AGE_MILLIS = 14L * 24L * 60L * 60L * 1000L
    }
}
