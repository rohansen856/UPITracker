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

            Log.d(TAG, "SMS from $sender: $body")

            val broadcastIntent = Intent(ACTION_SMS).apply {
                putExtra("sender", sender)
                putExtra("body", body)
                putExtra("timestamp", timestamp)
            }
            context.sendBroadcast(broadcastIntent)
        }
    }
}
