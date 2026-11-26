package co.anonymoke.anonymoke

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent

class MainActivity : FlutterActivity() {
    private var saveReply: MethodChannel.Result? = null
    private var saveContents: ByteArray? = null

    override fun onDestroy() {
        saveContents = null
        saveReply?.success(false)
        saveReply = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "anonymoke/files").setMethodCallHandler { call, result ->
            if (call.method != "saveJson") { result.notImplemented(); return@setMethodCallHandler }
            if (saveReply != null) { result.error("save_busy", "A save is already open.", null); return@setMethodCallHandler }
            val contents = call.argument<String>("contents")
            if (contents == null) { result.error("save_invalid", "No export content.", null); return@setMethodCallHandler }
            saveReply = result
            saveContents = contents.toByteArray(Charsets.UTF_8)
            try {
                startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/json"
                    putExtra(Intent.EXTRA_TITLE, "anonymoke-data.json")
                }, 7302)
            } catch (_: Exception) {
                saveReply = null
                saveContents = null
                result.error("save_unavailable", "Could not open Save File.", null)
            }
        }
    }

    @Deprecated("Activity result API retained for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7302) return
        val reply = saveReply ?: return
        val contents = saveContents
        saveReply = null
        saveContents = null
        val destination = data?.data
        if (resultCode != Activity.RESULT_OK || destination == null || contents == null) {
            reply.success(false)
            return
        }
        Thread {
            try {
                val stream = contentResolver.openOutputStream(destination, "wt") ?: error("save_unavailable")
                stream.use { it.write(contents) }
                runOnUiThread { reply.success(true) }
            } catch (_: Exception) {
                runOnUiThread { reply.error("save_failed", "The file could not be saved.", null) }
            }
        }.start()
    }
}
