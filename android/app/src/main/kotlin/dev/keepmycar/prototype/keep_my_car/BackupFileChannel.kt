package dev.keepmycar.prototype.keep_my_car

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

internal class BackupFileChannel(activity: Activity, messenger: BinaryMessenger) {
    private var activity: Activity? = activity
    private val resolver = activity.applicationContext.contentResolver
    companion object {
        private const val CHANNEL = "keep_my_car/backup_file"
        fun requestWatermark(): Int = BackupFileGate.watermark()
        fun restoreWatermark(value: Int) {
            BackupFileGate.restore(value)
        }
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "backup-file-io").apply { isDaemon = true }
    }
    private var pending: BackupFileOperation? = null
    private var requestCode: Int? = null
    private var saveBytes: ByteArray? = null
    private var timeoutTask: Runnable? = null
    private var closed = false

    init {
        channel.setMethodCallHandler(::handle)
    }

    @Suppress("DEPRECATION")
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "save" && call.method != "read") {
            result.notImplemented()
            return
        }
        if (closed) {
            result.success(fileError("interrupted").wire())
            return
        }
        if (BackupFileGate.busy) {
            result.success(fileError("busy").wire())
            return
        }
        val saving = call.method == "save"
        val args = call.arguments as? Map<*, *>
        val filename = args?.get("filename") as? String
        val mime = args?.get("mimeType") as? String
        val bytes = args?.get("bytes") as? ByteArray
        if (saving && (filename.isNullOrBlank() || filename.any { it == '/' || it == '\\' || it.isISOControl() } ||
                mime.isNullOrBlank() || !mime.matches(Regex("[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+")) || bytes == null)) {
            result.success(fileError("invalidArguments").wire())
            return
        }
        // Never recycle a request code in this process (or across saved Activity state).
        val operation = BackupFileOperation { result.success(it.wire()) }
        val allocatedRequest = BackupFileGate.acquire(operation)
        if (allocatedRequest == null) {
            result.success(fileError("platformFailure").wire())
            return
        }
        pending = operation
        requestCode = allocatedRequest
        saveBytes = if (saving) bytes else null
        try {
            val intent = Intent(if (saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = if (saving) mime else "*/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
                if (saving) putExtra(Intent.EXTRA_TITLE, filename)
            }
            val host = activity ?: throw IllegalStateException()
            host.startActivityForResult(intent, allocatedRequest)
        } catch (_: Exception) {
            operation.complete(fileError("platformFailure"))
            release(operation)
        }
    }

    fun onActivityResult(code: Int, resultCode: Int, data: Intent?) {
        if (closed || code != requestCode) return
        val operation = pending ?: return
        if (operation.transferring) return
        try {
            // Cancel/error do not require inspecting provider result extras.
            if (resultCode != Activity.RESULT_OK) {
                finishSelection(operation, selectionFailure(resultCode, false, false, false)!!)
                return
            }
            val uri = data?.data
            val conflictingClip = data?.clipData?.let {
                it.itemCount != 1 || it.getItemAt(0).uri != uri
            } ?: false
            val failure = selectionFailure(resultCode, uri != null, conflictingClip, uri?.scheme == "content")
            if (failure != null) finishSelection(operation, failure)
            else transfer(operation, uri!!)
        } catch (_: Exception) {
            finishSelection(operation, fileError("platformFailure"))
        }
    }

    private fun finishSelection(operation: BackupFileOperation, outcome: FileOutcome) {
        operation.complete(outcome)
        release(operation)
    }

    private fun transfer(operation: BackupFileOperation, uri: Uri) {
        if (!operation.beginIo(SystemClock.elapsedRealtime())) return
        val timeout = Runnable { operation.timeout() }
        timeoutTask = timeout
        main.postDelayed(timeout, BACKUP_IO_TIMEOUT_MS)
        val bytes = saveBytes
        saveBytes = null
        // Keep only the application resolver in the worker, never the Activity.
        try {
            worker.execute {
                val outcome = if (bytes != null) {
                    BackupStreamIo.save({ resolver.openOutputStream(uri, "wt") }, bytes, operation.abandoned)
                } else {
                    BackupStreamIo.read({ resolver.openInputStream(uri) }, operation.abandoned)
                }
                main.post {
                    // Also check elapsed time if main-thread delivery was delayed (e.g. background sleep).
                    main.removeCallbacks(timeout)
                    operation.finishIo(outcome, SystemClock.elapsedRealtime())
                    release(operation)
                }
            }
        } catch (_: Exception) {
            main.removeCallbacks(timeout)
            operation.complete(fileError("platformFailure"))
            release(operation)
        }
    }

    private fun release(operation: BackupFileOperation) {
        BackupFileGate.release(operation)
        if (pending === operation) {
            pending = null
            requestCode = null
            saveBytes = null
            timeoutTask = null
        }
    }

    fun close() {
        if (closed) return
        closed = true
        channel.setMethodCallHandler(null)
        activity = null
        timeoutTask?.let { main.removeCallbacks(it) }
        pending?.let {
            it.detach()
            if (!it.transferring) release(it)
        }
        // Does not interrupt or pretend to stop blocking provider calls.
        worker.shutdown()
    }
}
