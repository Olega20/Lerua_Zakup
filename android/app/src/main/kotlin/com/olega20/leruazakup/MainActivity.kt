package com.olega20.leruazakup

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.StatFs
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val channelName = "lerua_zakup/notifications"
    private val platformChannelName = "lerua_zakup/platform"
    private val connectivityChannelName = "lerua_zakup/connectivity"
    private val permissionRequestCode = 4107
    private val backupFolderRequestCode = 6101
    private val backupFileRequestCode = 6102
    private var permissionResult: MethodChannel.Result? = null
    private var backupFolderResult: MethodChannel.Result? = null
    private var backupFileResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, platformChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAvailableStorageBytes" -> {
                        try {
                            result.success(StatFs(filesDir.absolutePath).availableBytes)
                        } catch (error: Exception) {
                            result.error("storage_unavailable", error.message, null)
                        }
                    }
                    "chooseBackupFolder" -> {
                        backupFolderResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        startActivityForResult(intent, backupFolderRequestCode)
                    }
                    "chooseBackupFile" -> {
                        backupFileResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }
                        startActivityForResult(intent, backupFileRequestCode)
                    }
                    "writeBackupFile" -> {
                        try {
                            val tree = Uri.parse(call.argument<String>("folderUri")!!)
                            val name = call.argument<String>("fileName")!!
                            val bytes = call.argument<ByteArray>("bytes")!!
                            val treeId = DocumentsContract.getTreeDocumentId(tree)
                            val parent = DocumentsContract.buildDocumentUriUsingTree(tree, treeId)
                            val file = DocumentsContract.createDocument(contentResolver, parent,
                                "application/octet-stream", name)
                                ?: throw IllegalStateException("Не удалось создать файл резервной копии")
                            contentResolver.openOutputStream(file, "wt")!!.use { it.write(bytes) }
                            result.success(file.toString())
                        } catch (error: Exception) {
                            result.error("backup_write_failed", error.javaClass.simpleName, null)
                        }
                    }
                    "listBackupFiles" -> {
                        try {
                            val tree = Uri.parse(call.argument<String>("folderUri")!!)
                            val treeId = DocumentsContract.getTreeDocumentId(tree)
                            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, treeId)
                            val files = mutableListOf<Map<String, Any?>>()
                            contentResolver.query(children,
                                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                                    DocumentsContract.Document.COLUMN_LAST_MODIFIED),
                                null, null, null)?.use { cursor ->
                                while (cursor.moveToNext()) {
                                    val id = cursor.getString(0)
                                    files.add(mapOf(
                                        "name" to cursor.getString(1),
                                        "modified" to cursor.getLong(2),
                                        "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString()
                                    ))
                                }
                            }
                            result.success(files)
                        } catch (error: Exception) {
                            result.error("backup_list_failed", error.javaClass.simpleName, null)
                        }
                    }
                    "deleteBackupFile" -> {
                        try {
                            result.success(DocumentsContract.deleteDocument(
                                contentResolver, Uri.parse(call.argument<String>("uri")!!)))
                        } catch (error: Exception) {
                            result.error("backup_delete_failed", error.javaClass.simpleName, null)
                        }
                    }
                    "readBackupFile" -> {
                        try {
                            val uri = Uri.parse(call.argument<String>("uri")!!)
                            val bytes = contentResolver.openInputStream(uri)!!.use { it.readBytes() }
                            result.success(bytes)
                        } catch (error: Exception) {
                            result.error("backup_read_failed", error.javaClass.simpleName, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, connectivityChannelName)
            .setStreamHandler(ConnectivityStreamHandler())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "createChannels" -> {
                        createNotificationChannels()
                        result.success(null)
                    }
                    "requestPermission" -> requestNotificationPermission(result)
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == backupFolderRequestCode) {
            val callback = backupFolderResult
            backupFolderResult = null
            val uri = if (resultCode == RESULT_OK) data?.data else null
            if (uri != null) {
                try {
                    val flags = (data?.flags ?: 0) and
                        (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    contentResolver.takePersistableUriPermission(uri, flags)
                    callback?.success(uri.toString())
                } catch (error: Exception) {
                    callback?.error("backup_permission_failed", error.javaClass.simpleName, null)
                }
            } else {
                callback?.success(null)
            }
        } else if (requestCode == backupFileRequestCode) {
            val callback = backupFileResult
            backupFileResult = null
            val uri = if (resultCode == RESULT_OK) data?.data else null
            if (uri != null) {
                try {
                    val flags = (data?.flags ?: 0) and Intent.FLAG_GRANT_READ_URI_PERMISSION
                    contentResolver.takePersistableUriPermission(uri, flags)
                } catch (_: Exception) { }
                callback?.success(uri.toString())
            } else {
                callback?.success(null)
            }
        }
    }

    private inner class ConnectivityStreamHandler : EventChannel.StreamHandler {
        private var callback: ConnectivityManager.NetworkCallback? = null
        private var sink: EventChannel.EventSink? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            onCancel(null)
            sink = events
            val manager = getSystemService(ConnectivityManager::class.java)
            val networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = emitCurrentStatus(manager)
                override fun onLost(network: Network) = emitCurrentStatus(manager)
                override fun onCapabilitiesChanged(
                    network: Network,
                    capabilities: NetworkCapabilities
                ) = emitCurrentStatus(manager)
            }
            callback = networkCallback
            try {
                manager.registerDefaultNetworkCallback(networkCallback)
                emitCurrentStatus(manager)
            } catch (error: Exception) {
                events.error("connectivity_unavailable", error.message, null)
            }
        }

        private fun emitCurrentStatus(manager: ConnectivityManager) {
            val network = manager.activeNetwork
            val capabilities = network?.let { manager.getNetworkCapabilities(it) }
            val hasValidatedInternet = capabilities != null &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
            runOnUiThread { sink?.success(hasValidatedInternet) }
        }

        override fun onCancel(arguments: Any?) {
            val current = callback
            if (current != null) {
                val manager = getSystemService(ConnectivityManager::class.java)
                try {
                    manager.unregisterNetworkCallback(current)
                } catch (_: Exception) {
                    // The callback may already have been unregistered by Android.
                }
            }
            callback = null
            sink = null
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannelGroup(
            NotificationChannelGroup("lerua_updates", "Lerua Zakup")
        )
        val channel = NotificationChannel(
            "lerua_general",
            "Уведомления приложения",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Уведомления Lerua Zakup"
            group = "lerua_updates"
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
        }
        manager.createNotificationChannel(channel)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (permissionResult != null) {
            result.error("permission_in_progress", "Notification permission request is already active", null)
            return
        }
        permissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            permissionRequestCode
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            permissionResult?.success(
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            )
            permissionResult = null
        }
    }
}
