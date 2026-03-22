package com.example.receipt

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.widget.RemoteViews
import java.io.File
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.*

class SpendingWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            updateWidget(context, appWidgetManager, id)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == "com.example.receipt.UPDATE_WIDGET") {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, SpendingWidgetProvider::class.java))
            onUpdate(context, mgr, ids)
        }
    }

    private fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.spending_widget_layout)
        val summary = readTodaySummary(context)

        val fmt = NumberFormat.getInstance(Locale("en", "IN"))

        views.setTextViewText(R.id.widget_spent, "₹${fmt.format(summary.spent)}")
        views.setTextViewText(R.id.widget_received, "₹${fmt.format(summary.received)}")
        views.setTextViewText(R.id.widget_date, SimpleDateFormat("dd MMM yyyy", Locale.getDefault()).format(Date()))
        views.setTextViewText(R.id.widget_count, "${summary.count} txns today")

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (launchIntent != null) {
            val pending = PendingIntent.getActivity(context, 0, launchIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_root, pending)
        }

        manager.updateAppWidget(widgetId, views)
    }

    private fun readTodaySummary(context: Context): TodaySummary {
        val dbPath = findDatabase(context) ?: return TodaySummary()

        var db: SQLiteDatabase? = null
        try {
            db = SQLiteDatabase.openDatabase(dbPath, null, SQLiteDatabase.OPEN_READONLY)

            val todayStart = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date()) + "T00:00:00.000"

            val spentCursor = db.rawQuery(
                "SELECT COALESCE(SUM(amount), 0) FROM transactions WHERE transaction_type = 'debit' AND transaction_date >= ?",
                arrayOf(todayStart)
            )
            var spent = 0.0
            if (spentCursor.moveToFirst()) spent = spentCursor.getDouble(0)
            spentCursor.close()

            val recvCursor = db.rawQuery(
                "SELECT COALESCE(SUM(amount), 0) FROM transactions WHERE transaction_type = 'credit' AND transaction_date >= ?",
                arrayOf(todayStart)
            )
            var received = 0.0
            if (recvCursor.moveToFirst()) received = recvCursor.getDouble(0)
            recvCursor.close()

            val countCursor = db.rawQuery(
                "SELECT COUNT(*) FROM transactions WHERE transaction_date >= ?",
                arrayOf(todayStart)
            )
            var count = 0
            if (countCursor.moveToFirst()) count = countCursor.getInt(0)
            countCursor.close()

            return TodaySummary(spent, received, count)
        } catch (e: Exception) {
            return TodaySummary()
        } finally {
            db?.close()
        }
    }

    private fun findDatabase(context: Context): String? {
        // sqflite stores databases in the app's databases directory
        val dbDir = File(context.applicationInfo.dataDir, "databases")
        val dbFile = File(dbDir, "upi_tracker.db")
        return if (dbFile.exists()) dbFile.absolutePath else null
    }

    data class TodaySummary(val spent: Double = 0.0, val received: Double = 0.0, val count: Int = 0)
}
