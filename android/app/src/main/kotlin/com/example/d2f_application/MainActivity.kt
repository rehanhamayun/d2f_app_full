package com.example.d2f_application

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null
    private val saveRequest = 4206
    private lateinit var printerBridge: BrotherPrinterBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        printerBridge = BrotherPrinterBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "d2f/printer").setMethodCallHandler { call,result -> printerBridge.handle(call,result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "d2f/permissions").setMethodCallHandler { call,result -> if(call.method=="camera")printerBridge.requestPermissions("camera",result)else result.notImplemented() }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "d2f/labels").setMethodCallHandler { call, result ->
            if (call.method != "savePdf") { result.notImplemented(); return@setMethodCallHandler }
            if (pendingResult != null) { result.error("BUSY", "A label save is already open.", null); return@setMethodCallHandler }
            val bytes = call.argument<ByteArray>("bytes")
            val name = call.argument<String>("name") ?: "D2F-shipping-label.pdf"
            if (bytes == null) { result.error("INVALID", "Label data is missing.", null); return@setMethodCallHandler }
            pendingResult = result
            pendingBytes = bytes
            try {
                startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/pdf"
                    putExtra(Intent.EXTRA_TITLE, name)
                }, saveRequest)
            } catch (error: Exception) {
                pendingResult = null; pendingBytes = null
                result.error("SAVE_FAILED", "Could not open the file picker.", null)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode,permissions,grantResults)
        if(::printerBridge.isInitialized)printerBridge.onPermissions(requestCode,grantResults)
    }
    override fun onDestroy(){if(::printerBridge.isInitialized)printerBridge.dispose();super.onDestroy()}

    @Deprecated("Deprecated in Android; required for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != saveRequest) return
        val result = pendingResult ?: return
        val bytes = pendingBytes
        pendingResult = null; pendingBytes = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || bytes == null) { result.success(false); return }
        try {
            val stream = contentResolver.openOutputStream(uri) ?: throw IllegalStateException("No output stream")
            stream.use { it.write(bytes) }
            result.success(true)
        } catch (error: Exception) { result.error("SAVE_FAILED", "Could not save the PDF.", null) }
    }
}
