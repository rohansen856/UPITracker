package com.example.receipt

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.util.Log
import android.widget.RemoteViews
import org.json.JSONArray
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Home-screen widget that renders the last-24h spending snapshot pushed by
 * Flutter through the `updateWidget` method channel. Reading from
 * SharedPreferences (rather than re-opening SQLite in a BroadcastReceiver) is
 * what lets the widget actually load on the launcher.
 *
 * Every code path that touches external state (prefs, bitmap allocation,
 * resource lookup) is wrapped so that a malformed payload or an OOM during
 * bitmap creation can never leave the user with a "Can't load widget" banner.
 * The worst case is a plain "—" card; the widget still renders.
 */
class SpendingWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "SpendingWidget"
        private const val PREFS = "receipt_widget"
        private const val KEY_SPENT_24H = "spent24h"
        private const val KEY_RECEIVED_24H = "received24h"
        private const val KEY_SPENT_PREV_24H = "spentPrev24h"
        private const val KEY_DELTA_PCT = "deltaPct"
        private const val KEY_HAS_DELTA = "hasDelta"
        private const val KEY_COUNT = "count24h"
        private const val KEY_SPARK = "spark7d"
        private const val KEY_UPDATED_AT = "updatedAt"

        /**
         * Called from [MainActivity] whenever Flutter pushes a new snapshot.
         * Accepts a `Map<String, Any?>` matching the payload built in
         * `TransactionProvider._refreshWidget`.
         */
        fun saveSnapshot(context: Context, payload: Any?) {
            try {
                val map = payload as? Map<*, *> ?: return
                val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()

                prefs.putFloat(KEY_SPENT_24H, (map["spent24h"] as? Number)?.toFloat() ?: 0f)
                prefs.putFloat(KEY_RECEIVED_24H, (map["received24h"] as? Number)?.toFloat() ?: 0f)
                prefs.putFloat(KEY_SPENT_PREV_24H, (map["spentPrev24h"] as? Number)?.toFloat() ?: 0f)

                val delta = map["deltaPct"] as? Number
                prefs.putBoolean(KEY_HAS_DELTA, delta != null)
                prefs.putFloat(KEY_DELTA_PCT, delta?.toFloat() ?: 0f)

                prefs.putInt(KEY_COUNT, (map["count24h"] as? Number)?.toInt() ?: 0)

                val spark = (map["spark7d"] as? List<*>)
                    ?.mapNotNull { (it as? Number)?.toDouble() }
                    ?: emptyList()
                prefs.putString(KEY_SPARK, JSONArray(spark).toString())

                prefs.putLong(
                    KEY_UPDATED_AT,
                    (map["updatedAt"] as? Number)?.toLong() ?: System.currentTimeMillis()
                )
                prefs.apply()
            } catch (t: Throwable) {
                Log.w(TAG, "saveSnapshot failed", t)
            }
        }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        // Push a first render immediately so the launcher doesn't sit on a
        // stale placeholder while it waits for the next broadcast.
        val mgr = AppWidgetManager.getInstance(context)
        val ids = mgr.getAppWidgetIds(ComponentName(context, SpendingWidgetProvider::class.java))
        onUpdate(context, mgr, ids)
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            try {
                renderWidget(context, appWidgetManager, id)
            } catch (t: Throwable) {
                Log.w(TAG, "render failed, falling back to minimal view", t)
                try {
                    appWidgetManager.updateAppWidget(id, buildFallback(context))
                } catch (inner: Throwable) {
                    Log.e(TAG, "fallback render also failed", inner)
                }
            }
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

    private fun renderWidget(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val snapshot = readSnapshot(context)
        val views = RemoteViews(context.packageName, R.layout.spending_widget_layout)

        val inr = NumberFormat.getInstance(Locale("en", "IN")).apply {
            maximumFractionDigits = 0
        }

        views.setTextViewText(R.id.widget_spent, "₹${inr.format(snapshot.spent)}")
        views.setTextViewText(R.id.widget_received, "₹${inr.format(snapshot.received)} in")
        views.setTextViewText(R.id.widget_subtitle, "Last 24 hours")
        views.setTextViewText(R.id.widget_date, SimpleDateFormat("EEE, d MMM", Locale.getDefault()).format(Date()))
        views.setTextViewText(R.id.widget_count, "${snapshot.count} txn${if (snapshot.count == 1) "" else "s"}")

        // Trend badge: +/− % vs yesterday, or "tracking started" if we have no
        // prior data. We swap entire drawable resources (not just colors) so the
        // rounded pill shape is preserved.
        if (snapshot.hasDelta) {
            val pct = snapshot.deltaPct
            val isFlat = abs(pct) < 0.5
            val isUp = pct > 0
            val label = when {
                isFlat -> "flat vs yesterday"
                isUp -> "+${pct.roundToInt()}% vs yesterday"
                else -> "${pct.roundToInt()}% vs yesterday"
            }
            views.setTextViewText(R.id.widget_trend, label)
            val (fg, bgRes) = when {
                isFlat -> Color.parseColor("#546E7A") to R.drawable.widget_chip_neutral
                isUp -> Color.parseColor("#E53935") to R.drawable.widget_chip_up
                else -> Color.parseColor("#2E7D32") to R.drawable.widget_chip_down
            }
            views.setTextColor(R.id.widget_trend, fg)
            views.setInt(R.id.widget_trend, "setBackgroundResource", bgRes)
        } else {
            views.setTextViewText(R.id.widget_trend, "tracking")
            views.setTextColor(R.id.widget_trend, Color.parseColor("#546E7A"))
            views.setInt(R.id.widget_trend, "setBackgroundResource", R.drawable.widget_chip_neutral)
        }

        // Sparkline: build a bitmap because RemoteViews has no way to set
        // per-bar heights on API < 31 otherwise. If bitmap allocation fails we
        // silently leave the ImageView empty — the card is still usable.
        try {
            val bars = if (snapshot.spark.isEmpty()) List(7) { 0.0 } else snapshot.spark
            val sparkBmp = drawSparkline(context, bars)
            views.setImageViewBitmap(R.id.widget_spark, sparkBmp)
        } catch (t: Throwable) {
            Log.w(TAG, "sparkline draw failed", t)
        }

        views.setOnClickPendingIntent(R.id.widget_root, launchAppIntent(context))
        manager.updateAppWidget(widgetId, views)
    }

    /** Minimal, allocation-free RemoteViews shown only when the full renderer throws. */
    private fun buildFallback(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.spending_widget_layout)
        views.setTextViewText(R.id.widget_subtitle, "Last 24 hours")
        views.setTextViewText(R.id.widget_date, SimpleDateFormat("EEE, d MMM", Locale.getDefault()).format(Date()))
        views.setTextViewText(R.id.widget_spent, "—")
        views.setTextViewText(R.id.widget_received, "tap to open")
        views.setTextViewText(R.id.widget_count, "")
        views.setTextViewText(R.id.widget_trend, "")
        views.setOnClickPendingIntent(R.id.widget_root, launchAppIntent(context))
        return views
    }

    private fun launchAppIntent(context: Context): PendingIntent? {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return null
        return PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun readSnapshot(context: Context): Snapshot {
        return try {
            val prefs: SharedPreferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val sparkJson = prefs.getString(KEY_SPARK, "[]") ?: "[]"
            val spark = runCatching {
                val arr = JSONArray(sparkJson)
                List(arr.length()) { arr.optDouble(it, 0.0) }
            }.getOrDefault(emptyList())

            Snapshot(
                spent = prefs.getFloat(KEY_SPENT_24H, 0f).toDouble(),
                received = prefs.getFloat(KEY_RECEIVED_24H, 0f).toDouble(),
                spentPrev = prefs.getFloat(KEY_SPENT_PREV_24H, 0f).toDouble(),
                hasDelta = prefs.getBoolean(KEY_HAS_DELTA, false),
                deltaPct = prefs.getFloat(KEY_DELTA_PCT, 0f).toDouble(),
                count = prefs.getInt(KEY_COUNT, 0),
                spark = spark,
                updatedAt = prefs.getLong(KEY_UPDATED_AT, 0L),
            )
        } catch (t: Throwable) {
            Log.w(TAG, "readSnapshot failed", t)
            Snapshot()
        }
    }

    /**
     * Draws a 7-bar sparkline with a subtle gradient and highlights the tallest
     * bar. Returns a bitmap sized to comfortably fill the widget's spark slot.
     */
    private fun drawSparkline(context: Context, values: List<Double>): Bitmap {
        val density = context.resources.displayMetrics.density.coerceAtLeast(1f)
        // Cap size so we stay well under the IPC/bundle limit on older launchers.
        val w = (240 * density).roundToInt().coerceAtMost(720)
        val h = (48 * density).roundToInt().coerceAtMost(160)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)

        val maxVal = (values.maxOrNull() ?: 0.0).coerceAtLeast(0.0)
        val n = values.size.coerceAtLeast(1)
        val slot = w.toFloat() / n
        val barWidth = (slot * 0.52f).coerceAtLeast(4f * density)
        val radius = 4f * density

        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val baseline = h.toFloat() - 1f

        for (i in values.indices) {
            val v = values[i]
            val isMax = maxVal > 0.0 && v >= maxVal
            val factor = if (maxVal == 0.0) 0.0 else v / maxVal
            val barHeight = (factor * (h - 8f * density)).toFloat().coerceAtLeast(3f * density)
            val left = slot * i + (slot - barWidth) / 2f
            val top = baseline - barHeight
            val right = left + barWidth
            val bottom = baseline

            val topColor = if (isMax) Color.parseColor("#1E88E5") else Color.parseColor("#7FB3E5F5")
            val botColor = if (isMax) Color.parseColor("#64B5F6") else Color.parseColor("#33B3E5F5")
            paint.shader = LinearGradient(0f, top, 0f, bottom, topColor, botColor, Shader.TileMode.CLAMP)

            c.drawRoundRect(RectF(left, top, right, bottom), radius, radius, paint)
        }

        return bmp
    }

    private data class Snapshot(
        val spent: Double = 0.0,
        val received: Double = 0.0,
        val spentPrev: Double = 0.0,
        val hasDelta: Boolean = false,
        val deltaPct: Double = 0.0,
        val count: Int = 0,
        val spark: List<Double> = emptyList(),
        val updatedAt: Long = 0L,
    )
}
