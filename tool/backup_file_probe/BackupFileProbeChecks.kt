package dev.keepmycar.prototype.keep_my_car

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.atomic.AtomicBoolean

// Framework-free JVM checks against the SAME source used by Android.
private var checks = 0
private fun scenario(name: String, run: () -> Unit) {
    run()
    checks++
    println("PASS $name")
}
private fun expectError(outcome: FileOutcome, code: String = "ioFailure") {
    check(outcome.status == "error" && outcome.code == code && outcome.bytes == null)
}
private fun active() = AtomicBoolean(false)

// Models a provider honoring wt; w overwrites from offset zero without truncating.
// This fake cannot establish the behavior of any actual DocumentsProvider.
private class ExistingOutput(private var contents: ByteArray, private val rejectTruncation: Boolean = false) {
    var requestedMode: String? = null
        private set
    fun bytes(): ByteArray = contents.copyOf()
    fun open(mode: String): OutputStream {
        requestedMode = mode
        require(mode == "wt" || mode == "w")
        if (mode == "wt" && rejectTruncation) throw IllegalArgumentException("unsupported mode")
        if (mode == "wt") contents = byteArrayOf()
        return object : OutputStream() {
            private var position = 0
            override fun write(value: Int) {
                if (position == contents.size) contents = contents.copyOf(position + 1)
                contents[position++] = value.toByte()
            }
        }
    }
}

fun main() {
    val bytes = byteArrayOf(0, 1, 127, -1)
    scenario("wt replaces larger existing contents with only new shorter bytes") {
        val target = ExistingOutput(ByteArray(8192) { 42 })
        val outcome = BackupStreamIo.save({ target.open("wt") }, bytes, active())
        check(target.requestedMode == "wt" && outcome.status == "success")
        check(target.bytes().size == bytes.size && target.bytes().contentEquals(bytes))
    }
    scenario("fake non-truncating w retains old tail (negative control)") {
        val old = ByteArray(8192) { 42 }
        val target = ExistingOutput(old)
        check(BackupStreamIo.save({ target.open("w") }, bytes, active()).status == "success")
        check(target.bytes().contentEquals(bytes + old.copyOfRange(bytes.size, old.size)))
        check(!target.bytes().contentEquals(bytes))
    }
    scenario("provider rejecting wt returns error without fallback") {
        val modes = mutableListOf<String>()
        val target = ExistingOutput(ByteArray(8192) { 42 }, rejectTruncation = true)
        expectError(BackupStreamIo.save({
            modes += "wt"
            target.open("wt")
        }, bytes, active()))
        check(modes == listOf("wt"))
        check(target.bytes().contentEquals(ByteArray(8192) { 42 }))
    }
    scenario("RESULT_OK without URI is error, not Cancel") {
        expectError(selectionFailure(-1, false, false, false)!!, "missingUri")
    }
    scenario("normal Cancel") { check(selectionFailure(0, false, false, false)!!.status == "cancelled") }
    scenario("unexpected result") { expectError(selectionFailure(7, true, false, true)!!, "platformFailure") }
    scenario("multiple selection rejected") { expectError(selectionFailure(-1, true, true, true)!!, "invalidResponse") }
    scenario("non-content URI rejected") { expectError(selectionFailure(-1, true, false, false)!!, "invalidResponse") }
    scenario("valid selection is not I/O success yet") { check(selectionFailure(-1, true, false, true) == null) }
    for (elapsed in listOf(PROBE_IO_TIMEOUT_MS - 1, PROBE_IO_TIMEOUT_MS, PROBE_IO_TIMEOUT_MS + 1)) {
        scenario("I/O deadline boundary $elapsed") {
            val results = mutableListOf<FileOutcome>()
            val operation = BackupFileOperation { results += it }
            operation.beginIo(100)
            operation.finishIo(FileOutcome("success"), 100 + elapsed)
            check(results.size == 1)
            if (elapsed < PROBE_IO_TIMEOUT_MS) check(results.single().status == "success")
            else expectError(results.single(), "timeout")
        }
    }
    scenario("save order and bytes") {
        val order = mutableListOf<String>()
        val target = object : ByteArrayOutputStream() {
            override fun write(b: ByteArray, off: Int, len: Int) { order += "write"; super.write(b, off, len) }
            override fun flush() { order += "flush" }
            override fun close() { order += "close" }
        }
        val outcome = BackupStreamIo.save({ order += "open"; target }, bytes, active())
        check(outcome.status == "success")
        check(order == listOf("open", "write", "flush", "close"))
        check(target.toByteArray().contentEquals(bytes))
    }
    scenario("read closes before success") {
        var closed = false
        val source = object : ByteArrayInputStream(bytes) {
            override fun close() { closed = true }
        }
        val outcome = BackupStreamIo.read({ source }, active())
        check(closed && outcome.status == "success" && outcome.bytes!!.contentEquals(bytes))
    }
    scenario("empty read succeeds") {
        check(BackupStreamIo.read({ ByteArrayInputStream(byteArrayOf()) }, active()).bytes!!.isEmpty())
    }
    scenario("null output") { expectError(BackupStreamIo.save({ null }, bytes, active()), "streamUnavailable") }
    scenario("null input") { expectError(BackupStreamIo.read({ null }, active()), "streamUnavailable") }
    for (stage in listOf("write", "flush", "close")) {
        scenario("$stage failure") {
            var closed = false
            val stream = object : OutputStream() {
                override fun write(b: Int) { if (stage == "write") throw IOException() }
                override fun flush() { if (stage == "flush") throw IOException() }
                override fun close() { closed = true; if (stage == "close") throw IOException() }
            }
            expectError(BackupStreamIo.save({ stream }, bytes, active()))
            check(closed)
        }
    }
    for (closeFails in listOf(false, true)) {
        scenario("read failure closes (closeFails=$closeFails)") {
            var closed = false
            val stream = object : InputStream() {
                override fun read(): Int = throw IOException()
                override fun close() { closed = true; if (closeFails) throw IOException() }
            }
            expectError(BackupStreamIo.read({ stream }, active()))
            check(closed)
        }
    }
    scenario("read close failure discards bytes") {
        val stream = object : ByteArrayInputStream(bytes) { override fun close() { throw IOException() } }
        expectError(BackupStreamIo.read({ stream }, active()))
    }
    scenario("partial read failure discards already read bytes") {
        var closed = false
        val stream = object : InputStream() {
            var first = true
            override fun read(): Int = throw IOException()
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (!first) throw IOException()
                first = false
                b[off] = 42
                return 1
            }
            override fun close() { closed = true }
        }
        expectError(BackupStreamIo.read({ stream }, active()))
        check(closed)
    }
    scenario("abandonment during close cannot become success") {
        val abandoned = active()
        val stream = object : ByteArrayInputStream(bytes) {
            override fun close() { abandoned.set(true) }
        }
        expectError(BackupStreamIo.read({ stream }, abandoned), "interrupted")
    }
    scenario("write and close both fail") {
        val stream = object : OutputStream() {
            override fun write(b: Int) { throw IOException() }
            override fun close() { throw RuntimeException() }
        }
        expectError(BackupStreamIo.save({ stream }, bytes, active()))
    }
    for (exception in listOf(SecurityException(), FileNotFoundException(), IOException(), IllegalArgumentException(), RuntimeException())) {
        scenario("open save ${exception.javaClass.simpleName}") {
            expectError(BackupStreamIo.save({ throw exception }, bytes, active()))
        }
        scenario("open read ${exception.javaClass.simpleName}") {
            expectError(BackupStreamIo.read({ throw exception }, active()))
        }
    }
    for (size in listOf(PROBE_MAX_READ_BYTES - 1, PROBE_MAX_READ_BYTES, PROBE_MAX_READ_BYTES + 1)) {
        scenario("actual read size $size") {
            var closed = false
            val stream = object : ByteArrayInputStream(ByteArray(size)) {
                override fun close() { closed = true }
            }
            val outcome = BackupStreamIo.read({ stream }, active())
            check(closed)
            if (size > PROBE_MAX_READ_BYTES) expectError(outcome, "tooLarge")
            else check(outcome.status == "success" && outcome.bytes!!.size == size)
        }
    }
    scenario("timeout keeps gate busy until actual worker exit") {
        val results = mutableListOf<FileOutcome>()
        val operation = BackupFileOperation { results += it }
        check(BackupProbeGate.acquire(operation) != null)
        check(operation.beginIo())
        operation.timeout()
        check(BackupProbeGate.busy)
        check(BackupProbeGate.acquire(BackupFileOperation {}) == null)
        operation.complete(FileOutcome("success"))
        check(results.size == 1 && results.single().code == "timeout")
        BackupProbeGate.release(operation)
        check(!BackupProbeGate.busy)
    }
    scenario("selection busy rejects both further save/read operations") {
        val selecting = BackupFileOperation {}
        check(BackupProbeGate.acquire(selecting) != null)
        repeat(2) { check(BackupProbeGate.acquire(BackupFileOperation {}) == null) }
        selecting.detach()
        BackupProbeGate.release(selecting)
        check(!BackupProbeGate.busy)
    }
    scenario("detached I/O keeps new Activity busy until worker exits") {
        val old = BackupFileOperation {}
        check(BackupProbeGate.acquire(old) != null)
        old.beginIo()
        old.detach()
        check(BackupProbeGate.acquire(BackupFileOperation {}) == null)
        old.finishIo(FileOutcome("success"), 100)
        BackupProbeGate.release(old)
        check(!BackupProbeGate.busy)
    }
    scenario("duplicate OS result cannot start second I/O") {
        val operation = BackupFileOperation {}
        check(operation.beginIo())
        check(!operation.beginIo())
    }
    scenario("normal completion beats later timeout exactly once") {
        val results = mutableListOf<FileOutcome>()
        val operation = BackupFileOperation { results += it }
        operation.beginIo()
        operation.complete(FileOutcome("success"))
        operation.timeout()
        check(results.size == 1 && results.single().status == "success")
    }
    scenario("cleanup beats late success and timeout") {
        val results = mutableListOf<FileOutcome>()
        val operation = BackupFileOperation { results += it }
        operation.beginIo()
        operation.detach()
        operation.timeout()
        operation.complete(FileOutcome("success"))
        check(results.size == 1 && results.single().code == "interrupted")
    }
    scenario("error and close error produce only one result") {
        val results = mutableListOf<FileOutcome>()
        val operation = BackupFileOperation { results += it }
        operation.complete(fileError("ioFailure"))
        operation.complete(fileError("ioFailure"))
        check(results.size == 1)
    }
    scenario("selector has no I/O timeout") {
        val results = mutableListOf<FileOutcome>()
        val operation = BackupFileOperation { results += it }
        operation.timeout()
        check(results.isEmpty())
        operation.complete(FileOutcome("cancelled"))
        check(results.single().status == "cancelled")
        check(!operation.beginIo())
    }
    scenario("old cleanup cannot unlock a new owner") {
        val old = BackupFileOperation {}
        val oldCode = BackupProbeGate.acquire(old)!!
        BackupProbeGate.release(old)
        val newer = BackupFileOperation {}
        val newCode = BackupProbeGate.acquire(newer)!!
        check(oldCode != newCode)
        BackupProbeGate.release(old)
        check(BackupProbeGate.busy)
        BackupProbeGate.release(newer)
    }
    scenario("restored request watermark never moves backward") {
        val saved = BackupProbeGate.watermark()
        BackupProbeGate.restore(saved - 1)
        check(BackupProbeGate.watermark() == saved)
        BackupProbeGate.restore(saved + 3)
        check(BackupProbeGate.watermark() == saved + 3)
    }
    scenario("abandoned I/O never opens provider") {
        val abandoned = AtomicBoolean(true)
        expectError(BackupStreamIo.save({ error("must not open") }, bytes, abandoned), "interrupted")
        expectError(BackupStreamIo.read({ error("must not open") }, abandoned), "interrupted")
    }
    scenario("detached messenger failure does not enable duplicate reply") {
        var count = 0
        val operation = BackupFileOperation { count++; throw IllegalStateException() }
        operation.detach()
        operation.complete(FileOutcome("success"))
        check(count == 1)
    }
    println("$checks Kotlin probe checks passed")
}
