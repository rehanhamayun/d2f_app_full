package com.example.d2f_application

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.*
import android.content.pm.PackageManager
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import com.brother.sdk.lmprinter.*
import com.brother.sdk.lmprinter.setting.QLPrintSettings
import com.brother.sdk.lmprinter.setting.PrintImageSettings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Direct official Brother SDK integration. All SDK calls use one serial worker. */
class BrotherPrinterBridge(private val activity: Activity) {
    private val prefs = activity.getSharedPreferences("d2f_brother_print_v1", Context.MODE_PRIVATE)
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val busy = AtomicBoolean(false)
    private val adapter get() = (activity.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
    private var permissionResult: MethodChannel.Result? = null
    private var permissionKind = ""
    private var discoveryTimeout: Runnable? = null
    private var discoveryResult: MethodChannel.Result? = null
    private var discoveryReceiver: BroadcastReceiver? = null
    private val found = linkedMapOf<String, Map<String, Any?>>()
    private val permissionRequest = 4218
    private val root = File(activity.filesDir, "d2f_print").apply { mkdirs() }
    private fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun safeId(id: String): String { require(id.matches(Regex("[A-Za-z0-9._:-]{1,160}"))) { "Invalid record identifier." }; return hash(id.toByteArray()) }
    private fun scope(call: MethodCall) = safeId(call.argument<String>("ownerId") ?: error("Sign in to a staff or driver account first."))
    private fun reply(result: MethodChannel.Result, value: Any?) = activity.runOnUiThread { result.success(value) }
    private fun error(result: MethodChannel.Result, code: String, message: String) = activity.runOnUiThread { result.error(code, message, null) }
    private fun deviceMap(d: BluetoothDevice): Map<String, Any?> = mapOf("address" to d.address, "name" to (d.name ?: "Bluetooth printer"), "paired" to (d.bondState == BluetoothDevice.BOND_BONDED))
    private fun requireBluetooth(scan: Boolean = false) {
        val required = if (Build.VERSION.SDK_INT >= 31) listOf(Manifest.permission.BLUETOOTH_CONNECT) + if(scan) listOf(Manifest.permission.BLUETOOTH_SCAN) else emptyList()
            else if(scan) listOf(Manifest.permission.ACCESS_FINE_LOCATION) else emptyList()
        if(required.any { activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }) throw SecurityException("Allow Nearby devices permission to use the printer. Older Android phones also require location permission for discovery only.")
        require(adapter != null) { "This phone does not support Bluetooth." }
        require(adapter!!.isEnabled) { "Turn on Bluetooth, then try again." }
    }
    fun requestPermissions(kind: String, result: MethodChannel.Result) {
        if(permissionResult != null) { result.error("BUSY", "A permission request is already open.", null); return }
        val permissions = if(kind == "camera") arrayOf(Manifest.permission.CAMERA) else if(Build.VERSION.SDK_INT >= 31)
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT,Manifest.permission.BLUETOOTH_SCAN) else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        val missing = permissions.filter { activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if(missing.isEmpty()) { result.success(true); return }
        permissionResult=result;permissionKind=kind;activity.requestPermissions(missing.toTypedArray(),permissionRequest)
    }
    fun onPermissions(requestCode: Int, grants: IntArray): Boolean {
        if(requestCode != permissionRequest)return false
        val result=permissionResult;permissionResult=null
        if(grants.isNotEmpty() && grants.all { it == PackageManager.PERMISSION_GRANTED }) result?.success(true)
        else result?.error("PERMISSION_DENIED",if(permissionKind=="camera") "Camera access was denied. Enable Camera in Android app permissions." else "Nearby devices access was denied. Enable it in Android app permissions.",null)
        return true
    }
    @Synchronized private fun jobs(owner: String): JSONArray = JSONArray(prefs.getString("jobs_$owner","[]"))
    @Synchronized private fun saveJob(owner: String, row: JSONObject) {
        val rows=jobs(owner);val next=JSONArray();var replaced=false
        for(i in 0 until rows.length()){val old=rows.getJSONObject(i);if(old.optString("clientJobId")==row.getString("clientJobId")){next.put(row);replaced=true}else next.put(old)}
        if(!replaced)next.put(row)
        // Never silently discard an unsynced audit entry.
        check(prefs.edit().putString("jobs_$owner",next.toString()).commit()) { "Could not save print history. Printing was not started." }
    }
    private fun asMap(o: JSONObject): Map<String,Any?> = o.keys().asSequence().associateWith { key -> when(val v=o.get(key)){JSONObject.NULL->null;is JSONObject->asMap(v);else->v} }
    private fun findJob(owner:String,id:String): JSONObject? {val rows=jobs(owner);return (0 until rows.length()).map{rows.getJSONObject(it)}.firstOrNull{it.optString("clientJobId")==id}}
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when(call.method){
                "permissions" -> requestPermissions("bluetooth",result)
                "enableBluetooth" -> {activity.startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE));result.success(true)}
                "settings" -> result.success(mapOf("defaultPrinter" to prefs.getString("printer",null)?.let{asMap(JSONObject(it))},"sdkVersion" to "4.13.2","supportedModel" to "Brother QL-1110NWB / QL-1110NWBc"))
                "paired" -> {requireBluetooth();result.success(adapter!!.bondedDevices.map{deviceMap(it)})}
                "discover" -> discover(result)
                "pair" -> {requireBluetooth(true);val address=call.argument<String>("address")?:error("Select a printer.");require(BluetoothAdapter.checkBluetoothAddress(address));val d=adapter!!.getRemoteDevice(address);result.success(if(d.bondState==BluetoothDevice.BOND_BONDED)true else d.createBond())}
                "saveDefault" -> {
                    requireBluetooth();val address=call.argument<String>("address")?:error("Select a printer.");require(BluetoothAdapter.checkBluetoothAddress(address));require(adapter!!.getRemoteDevice(address).bondState==BluetoothDevice.BOND_BONDED){"Complete Android Bluetooth pairing, then refresh paired printers."}
                    val media=call.argument<String>("media")?:"DieCutW102H152";require(media in listOf("DieCutW102H152","RollW102","DieCutW103H164")){"Select a supported Brother DK shipping roll."}
                    val row=JSONObject().put("address",address).put("name",call.argument<String>("name")?:"Brother QL-1110NWB").put("media",media)
                    check(prefs.edit().putString("printer",row.toString()).commit());result.success(asMap(row))
                }
                "cacheLabel" -> cacheLabel(call,result)
                "cachedLabels" -> {val dir=File(root,scope(call));result.success(dir.listFiles()?.filter{it.extension=="json"}?.mapNotNull{runCatching{asMap(JSONObject(it.readText()))}.getOrNull()}?:emptyList<Map<String,Any?>>())}
                "cachedPdf" -> {val f=File(File(root,scope(call)),safeId(call.argument<String>("parcelId")?:error("Missing parcel."))+".pdf");result.success(if(f.exists())f.readBytes() else null)}
                "history" -> {val rows=jobs(scope(call));result.success((rows.length()-1 downTo 0).map{val row=rows.getJSONObject(it);if(row.optString("status")=="PRINTING"&&!busy.get())row.put("status","UNKNOWN").put("message","App closed during printing. Check the physical label before explicitly reprinting.");asMap(row)})}
                "markSynced" -> {val owner=scope(call);val row=findJob(owner,call.argument<String>("clientJobId")?:"")?:error("Print job not found.");row.put("synced",true);saveJob(owner,row);result.success(true)}
                "purgeLabels" -> {File(root,scope(call)).deleteRecursively();result.success(true)}
                "status" -> status(result)
                "print" -> print(call,result)
                else -> result.notImplemented()
            }
        }catch(e:SecurityException){error(result,"PERMISSION_DENIED",e.message?:"Bluetooth permission is required.")}
        catch(e:Exception){error(result,"PRINTER_ERROR",e.message?:"Could not complete the printer action.")}
    }
    private fun cacheLabel(call:MethodCall,result:MethodChannel.Result){
        val owner=scope(call);val id=call.argument<String>("parcelId")?:error("Missing parcel.");val bytes=call.argument<ByteArray>("bytes")?:error("Missing label PDF.")
        require(bytes.size in 5..12_000_000 && String(bytes.take(5).toByteArray())=="%PDF-"){"Invalid shipping label PDF."}
        val dir=File(root,owner).apply{mkdirs()};val key=safeId(id);val file=File(dir,"$key.pdf");val temporary=File(dir,"$key.tmp");temporary.writeBytes(bytes);check(temporary.renameTo(file)){"Could not save this label for offline use."}
        val row=JSONObject().put("parcelId",id).put("trackingId",call.argument<String>("trackingId")?:"").put("cachedAt",System.currentTimeMillis()).put("labelHash",hash(bytes))
        File(dir,"$key.json").writeText(row.toString());result.success(asMap(row))
    }
    private fun discover(result:MethodChannel.Result){
        requireBluetooth(true);if(discoveryResult!=null){result.error("BUSY","Printer discovery is already running.",null);return}
        if(adapter!!.isDiscovering){adapter!!.cancelDiscovery();result.error("BUSY","Previous Bluetooth discovery is stopping. Tap Find nearby printers again.",null);return}
        discoveryResult=result;found.clear();adapter!!.bondedDevices.forEach{found[it.address]=deviceMap(it)}
        val receiver=object:BroadcastReceiver(){override fun onReceive(context:Context,intent:Intent){when(intent.action){BluetoothDevice.ACTION_FOUND->{val d=if(Build.VERSION.SDK_INT>=33)intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE,BluetoothDevice::class.java) else @Suppress("DEPRECATION") intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);if(d!=null)found[d.address]=deviceMap(d)};BluetoothAdapter.ACTION_DISCOVERY_FINISHED->finishDiscovery()}}}
        discoveryReceiver=receiver;val filter=IntentFilter().apply{addAction(BluetoothDevice.ACTION_FOUND);addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)}
        if(Build.VERSION.SDK_INT>=33)activity.registerReceiver(receiver,filter,Context.RECEIVER_EXPORTED)else @Suppress("DEPRECATION") activity.registerReceiver(receiver,filter)
        if(!adapter!!.startDiscovery()){finishDiscovery();return};discoveryTimeout=Runnable{finishDiscovery()};handler.postDelayed(discoveryTimeout!!,15000)
    }
    private fun finishDiscovery(){
        val result=discoveryResult?:return;discoveryResult=null
        discoveryTimeout?.let{handler.removeCallbacks(it)};discoveryTimeout=null
        runCatching{discoveryReceiver?.let{activity.unregisterReceiver(it)}};discoveryReceiver=null
        runCatching{if(adapter?.isDiscovering==true)adapter?.cancelDiscovery()};result.success(found.values.toList())
    }
    private fun openDriver():PrinterDriver{
        requireBluetooth();val p=JSONObject(prefs.getString("printer",null)?:error("Choose and save a default Brother printer first."))
        if(adapter!!.isDiscovering)adapter!!.cancelDiscovery()
        val opened=PrinterDriverGenerator.openChannel(Channel.newBluetoothChannel(p.getString("address"),adapter))
        if(opened.error.code!=OpenChannelError.ErrorCode.NoError)error("Connection failed (${opened.error.code}). Check printer power, Bluetooth pairing and distance.")
        return opened.driver?:error("Printer connection could not be opened.")
    }
    private fun status(result:MethodChannel.Result){
        if(!busy.compareAndSet(false,true)){result.error("BUSY","A print or connection check is already running.",null);return}
        worker.execute{var driver:PrinterDriver?=null;try{driver=openDriver();val status=driver.printerStatus;reply(result,mapOf("connected" to true,"status" to status.error.code.toString(),"printerStatus" to status.printerStatus?.errorCode?.toString()))}catch(e:Exception){error(result,"CONNECTION_FAILED",e.message?:"Could not connect.")}finally{runCatching{driver?.closeChannel()};busy.set(false)}}
    }
    private fun print(call:MethodCall,result:MethodChannel.Result){
        requireBluetooth();val owner=scope(call);val jobId=call.argument<String>("clientJobId")?:error("Missing print job ID.");safeId(jobId)
        findJob(owner,jobId)?.let{result.success(asMap(it));return}
        if(!busy.compareAndSet(false,true)){result.error("BUSY","A print job is already running. Wait before trying again.",null);return}
        try{
            val parcelId=call.argument<String>("parcelId")?:error("Select a saved parcel label.");val file=File(File(root,owner),safeId(parcelId)+".pdf");require(file.exists()){ "This parcel has no saved label. Open it online once before printing offline." }
            val printer=JSONObject(prefs.getString("printer",null)?:error("Save a default Brother printer first."));val labelBytes=file.readBytes();val fingerprint=hash(labelBytes);val force=call.argument<Boolean>("reprint")==true;val reason=call.argument<String>("reason")?:""
            if(force)require(reason.trim().isNotEmpty()){ "Record why this label needs reprinting." }
            val rows=jobs(owner);val recent=(0 until rows.length()).map{rows.getJSONObject(it)}.any{it.optString("labelHash")==fingerprint&&it.optString("printerAddress")==printer.getString("address")&&System.currentTimeMillis()-it.optLong("deviceTimeMs")<120000}
            require(!recent||force){"This label was recently sent. Check the physical label and use the explicit Reprint option if needed."}
            val snapshot=File(activity.cacheDir,"d2f-print-${safeId(jobId)}.pdf");snapshot.writeBytes(labelBytes)
            val pages=ParcelFileDescriptor.open(snapshot,ParcelFileDescriptor.MODE_READ_ONLY).use{fd->PdfRenderer(fd).use{it.pageCount}};require(pages in 1..21){"Shipping label must contain between 1 and 21 pages."}
            val row=JSONObject().put("clientJobId",jobId).put("parcelId",parcelId).put("trackingId",call.argument<String>("trackingId")?:"").put("printerName",printer.getString("name")).put("printerAddress",printer.getString("address")).put("labelHash",fingerprint).put("pages",pages).put("status","PRINTING").put("deviceTimeMs",System.currentTimeMillis()).put("source","ANDROID_BROTHER_SDK").put("reason",reason.trim()).put("synced",false)
            saveJob(owner,row)
            worker.execute{var driver:PrinterDriver?=null;var attempted=false
                try{
                    driver=openDriver();val settings=QLPrintSettings(PrinterModel.QL_1110NWB).apply{labelSize=QLPrintSettings.LabelSize.valueOf(printer.getString("media"));workPath=File(activity.cacheDir,"brother_work").apply{mkdirs()}.absolutePath;numCopies=1;isAutoCut=true;isCutAtEnd=true;autoCutForEachPageCount=1;scaleMode=PrintImageSettings.ScaleMode.FitPageAspect;printQuality=PrintImageSettings.PrintQuality.Best;resolution=PrintImageSettings.Resolution.Normal}
                    attempted=true;val outcome=driver.printPDF(snapshot.absolutePath,settings);val success=outcome.code==PrintError.ErrorCode.NoError
                    row.put("status",if(success)"COMPLETED"else"UNKNOWN").put("message",if(success)"Brother SDK completed the print job without reporting an error."else "Printer reported ${outcome.code}. Some labels may have printed. Check the physical output before reprinting.")
                }catch(e:Exception){row.put("status",if(attempted)"UNKNOWN"else"FAILED").put("message",e.message?:"Printer failed. Check the physical output before reprinting.")}
                finally{runCatching{driver?.closeChannel()};runCatching{snapshot.delete()};try{saveJob(owner,row);reply(result,asMap(row))}catch(e:Exception){error(result,"HISTORY_ERROR","Print outcome could not be saved. Check the physical label before reprinting.")};busy.set(false)}
            }
        }catch(e:Exception){busy.set(false);throw e}
    }
    fun dispose(){finishDiscovery();permissionResult?.error("CANCELLED","Permission request closed.",null);permissionResult=null;worker.shutdown()}
}
