package dev.keepmycar.prototype.keep_my_car

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.atomic.AtomicBoolean

// Probe limits, not permanent product limits.
internal const val PROBE_MAX_READ_BYTES = 5 * 1024 * 1024
internal const val PROBE_IO_TIMEOUT_MS = 60_000L

internal data class FileOutcome(val status: String, val code: String? = null, val bytes: ByteArray? = null) {
    fun wire(): Map<String, Any> = buildMap {
        put("status", status)
        code?.let { put("code", it) }
        bytes?.let { put("bytes", it) }
    }
}

internal fun fileError(code: String) = FileOutcome("error", code)

// Android RESULT_OK = -1, RESULT_CANCELED = 0. Null means a valid selection, not success.
internal fun selectionFailure(resultCode: Int, hasUri: Boolean, multiple: Boolean, contentUri: Boolean): FileOutcome? = when {
    resultCode == 0 -> FileOutcome("cancelled")
    resultCode != -1 -> fileError("platformFailure")
    !hasUri -> fileError("missingUri")
    multiple || !contentUri -> fileError("invalidResponse")
    else -> null
}

internal class FileIoFailure(val code: String) : RuntimeException()

internal object BackupStreamIo {
    fun save(open: () -> OutputStream?, bytes: ByteArray, abandoned: AtomicBoolean): FileOutcome = attempt {
        checkActive(abandoned)
        val stream = open() ?: throw FileIoFailure("streamUnavailable")
        stream.use {
            checkActive(abandoned)
            it.write(bytes)
            checkActive(abandoned)
            it.flush()
        }
        checkActive(abandoned)
        FileOutcome("success")
    }

    fun read(open: () -> InputStream?, abandoned: AtomicBoolean): FileOutcome = attempt {
        checkActive(abandoned)
        val stream = open() ?: throw FileIoFailure("streamUnavailable")
        val output = ByteArrayOutputStream()
        stream.use {
            val buffer = ByteArray(8192)
            while (true) {
                checkActive(abandoned)
                val count = it.read(buffer)
                if (count < 0) break
                if (count == 0) continue
                if (count > PROBE_MAX_READ_BYTES - output.size()) throw FileIoFailure("tooLarge")
                output.write(buffer, 0, count)
            }
        }
        checkActive(abandoned)
        FileOutcome("success", bytes = output.toByteArray())
    }

    private fun checkActive(abandoned: AtomicBoolean) {
        if (abandoned.get()) throw FileIoFailure("interrupted")
    }

    private fun attempt(work: () -> FileOutcome): FileOutcome = try {
        work()
    } catch (failure: FileIoFailure) {
        fileError(failure.code)
    } catch (_: Exception) {
        // Includes IOException, SecurityException and RuntimeException. Never expose provider text.
        fileError("ioFailure")
    }
}

// All methods are called on the Android main thread. Workers only touch abandoned.
internal class BackupFileOperation(reply: (FileOutcome) -> Unit) {
    private var reply: ((FileOutcome) -> Unit)? = reply
    val abandoned = AtomicBoolean(false)
    var transferring = false
        private set
    private var replied = false
    private var detached = false
    private var deadlineMs = Long.MAX_VALUE

    fun beginIo(nowMs: Long = 0): Boolean {
        if (transferring || replied || detached) return false
        transferring = true
        deadlineMs = nowMs + PROBE_IO_TIMEOUT_MS
        return true
    }

    fun finishIo(outcome: FileOutcome, nowMs: Long) {
        if (nowMs >= deadlineMs) timeout()
        complete(outcome)
    }

    fun complete(outcome: FileOutcome) {
        if (!replied && !detached) {
            replied = true
            val callback = reply
            reply = null
            try {
                callback?.invoke(outcome)
            } catch (_: RuntimeException) {
                // The messenger may already be detached. Never retry or reuse this result.
            }
        }
    }

    fun timeout() {
        if (!transferring) return
        abandoned.set(true)
        complete(fileError("timeout"))
        // The owner MUST retain busy until the worker has actually exited.
    }

    fun detach() {
        abandoned.set(true)
        complete(fileError("interrupted"))
        detached = true
    }
}

// Main-thread-only, shared by old/new Activity instances. No Activity or messenger references.
internal object BackupProbeGate {
    private const val FIRST_REQUEST = 0x6000
    private const val LAST_REQUEST = 0x7fff
    private var nextRequest = FIRST_REQUEST
    private var owner: BackupFileOperation? = null
    val busy: Boolean get() = owner != null
    fun watermark(): Int = nextRequest
    fun restore(value: Int) {
        nextRequest = maxOf(nextRequest, value.coerceIn(FIRST_REQUEST, LAST_REQUEST + 1))
    }
    fun acquire(operation: BackupFileOperation): Int? {
        if (busy || nextRequest > LAST_REQUEST) return null
        owner = operation
        return nextRequest++
    }
    fun release(operation: BackupFileOperation) {
        if (owner === operation) owner = null
    }
}
