package com.example.receipt

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "com.example.receipt/methods"
        private const val NOTIFICATION_EVENT_CHANNEL = "com.example.receipt/notifications"
        private const val SMS_EVENT_CHANNEL = "com.example.receipt/sms"
    }

    private var notificationReceiver: BroadcastReceiver? = null
    private var smsReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationAccessGranted" -> {
                    result.success(isNotificationListenerEnabled())
                }
                "openNotificationAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                }
                "readSmsHistory" -> {
                    val limit = (call.argument<Number>("limit"))?.toInt() ?: 200
                    val since = (call.argument<Number>("since"))?.toLong() ?: 0L
                    result.success(readSmsHistory(limit, since))
                }
                "updateWidget" -> {
                    // Persist the snapshot from Flutter so the widget provider never
                    // has to re-read sqflite's DB from a BroadcastReceiver (that path
                    // was the source of "Can't load widget" on the launcher).
                    SpendingWidgetProvider.saveSnapshot(applicationContext, call.arguments)
                    val intent = Intent("com.example.receipt.UPDATE_WIDGET")
                    intent.setPackage(packageName)
                    sendBroadcast(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    notificationReceiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            intent ?: return
                            val data = mapOf(
                                "package" to (intent.getStringExtra("package") ?: ""),
                                "title" to (intent.getStringExtra("title") ?: ""),
                                "text" to (intent.getStringExtra("text") ?: ""),
                                "subText" to (intent.getStringExtra("subText") ?: ""),
                                "timestamp" to intent.getLongExtra("timestamp", System.currentTimeMillis())
                            )
                            events?.success(data)
                        }
                    }
                    val filter = IntentFilter(UpiNotificationListener.ACTION_NOTIFICATION)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(notificationReceiver, filter, RECEIVER_NOT_EXPORTED)
                    } else {
                        registerReceiver(notificationReceiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    notificationReceiver?.let { unregisterReceiver(it) }
                    notificationReceiver = null
                }
            }
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    smsReceiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            intent ?: return
                            val data = mapOf(
                                "sender" to (intent.getStringExtra("sender") ?: ""),
                                "body" to (intent.getStringExtra("body") ?: ""),
                                "timestamp" to intent.getLongExtra("timestamp", System.currentTimeMillis())
                            )
                            events?.success(data)
                        }
                    }
                    val filter = IntentFilter(SmsReceiver.ACTION_SMS)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(smsReceiver, filter, RECEIVER_NOT_EXPORTED)
                    } else {
                        registerReceiver(smsReceiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    smsReceiver?.let { unregisterReceiver(it) }
                    smsReceiver = null
                }
            }
        )
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val cn = ComponentName(this, UpiNotificationListener::class.java)
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat != null && flat.contains(cn.flattenToString())
    }

    private fun readSmsHistory(limit: Int, sinceTimestamp: Long): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()
        val uri: Uri = Telephony.Sms.CONTENT_URI
        val projection = arrayOf(
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
            Telephony.Sms.TYPE,
        )
        val selection = if (sinceTimestamp > 0) "${Telephony.Sms.DATE} > ?" else null
        val selectionArgs = if (sinceTimestamp > 0) arrayOf(sinceTimestamp.toString()) else null

        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(
                uri, projection, selection, selectionArgs,
                "${Telephony.Sms.DATE} DESC LIMIT $limit"
            )
            cursor?.let {
                while (it.moveToNext()) {
                    val address = it.getString(0) ?: ""
                    val body = it.getString(1) ?: ""
                    val date = it.getLong(2)
                    val type = it.getInt(3)
                    results.add(mapOf(
                        "sender" to address,
                        "body" to body,
                        "timestamp" to date,
                        "type" to type
                    ))
                }
            }
        } finally {
            cursor?.close()
        }
        return results
    }
}
