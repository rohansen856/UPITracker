package com.upitracker.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

class SmsReceiver : BroadcastReceiver() {
    companion object {
        const val TAG = "SmsReceiver"
        const val ACTION_SMS = "com.upitracker.app.SMS_RECEIVED"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        context ?: return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        for (msg in messages) {
            val sender = msg.displayOriginatingAddress ?: ""
            val body = msg.displayMessageBody ?: ""
            val timestamp = msg.timestampMillis

            // Never log message contents: logcat is readable via adb and by
            // privileged apps, and these are bank SMS.
            Log.d(TAG, "SMS received (${body.length} chars)")

            // Package-scoped: an implicit broadcast would hand every SMS body
            // to any app that registers a receiver for this action.
            val broadcastIntent = Intent(ACTION_SMS).apply {
                setPackage(context.packageName)
                putExtra("sender", sender)
                putExtra("body", body)
                putExtra("timestamp", timestamp)
            }
            context.sendBroadcast(broadcastIntent)
        }
    }
}
