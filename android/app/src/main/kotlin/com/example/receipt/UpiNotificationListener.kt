package com.example.receipt

import android.app.Notification
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class UpiNotificationListener : NotificationListenerService() {

    companion object {
        const val TAG = "UpiNotificationListener"
        const val ACTION_NOTIFICATION = "com.example.receipt.NOTIFICATION_RECEIVED"

        val UPI_PACKAGES = setOf(
            "com.google.android.apps.nbu.paisa.user",  // GPay
            "net.one97.paytm",                          // Paytm
            "com.phonepe.app",                          // PhonePe
            "in.org.npci.upiapp",                       // BHIM
            "com.whatsapp",                             // WhatsApp Pay
            "com.amazon.mShop.android.shopping",        // Amazon Pay
            "com.mobikwik_new",                          // MobiKwik
            "com.freecharge.android",                    // Freecharge
            "com.myairtel.myairtelapp",                  // Airtel Payments
            "com.jio.myjio",                            // Jio Pay
        )

        val BANK_PACKAGES = setOf(
            "com.sbi.SBIFreedomPlus",
            "com.csam.icici.bank.imobile",
            "com.axis.mobile",
            "net.csam.hdfc",
            "com.msf.koenig.bma",
            "com.unionbankofindia.unionbank",
            "com.canaaborb",
            "org.boi.mobilebanking",
            "com.infrasofttech.indianbank",
        )
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        val pkg = sbn.packageName ?: return

        if (!UPI_PACKAGES.contains(pkg) && !BANK_PACKAGES.contains(pkg)) return

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""

        val content = bigText.ifEmpty { text }
        if (content.isEmpty()) return

        Log.d(TAG, "UPI notification from $pkg: $content")

        val intent = Intent(ACTION_NOTIFICATION).apply {
            putExtra("package", pkg)
            putExtra("title", title)
            putExtra("text", content)
            putExtra("subText", subText)
            putExtra("timestamp", sbn.postTime)
        }
        sendBroadcast(intent)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {}
}
