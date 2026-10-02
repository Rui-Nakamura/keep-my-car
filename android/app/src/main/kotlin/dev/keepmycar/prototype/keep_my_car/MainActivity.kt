package dev.keepmycar.prototype.keep_my_car

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var backupFileChannel: BackupFileChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        savedInstanceState?.let {
            BackupFileChannel.restoreWatermark(it.getInt("backupFileRequestWatermark", 0x6000))
        }
        super.onCreate(savedInstanceState)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putInt("backupFileRequestWatermark", BackupFileChannel.requestWatermark())
        super.onSaveInstanceState(outState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backupFileChannel = BackupFileChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        backupFileChannel?.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        backupFileChannel?.close()
        backupFileChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
