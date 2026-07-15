# Android native layer

Kotlin sources live in
[android/app/src/main/kotlin/com/example/receipt/](../../android/app/src/main/kotlin/com/example/receipt/).
The app is Android-only in practice (notification listener + SMS are Android APIs).

## Manifest

[android/app/src/main/AndroidManifest.xml](../../android/app/src/main/AndroidManifest.xml)
— app label "UPI Tracker".

**Permissions:** `READ_SMS`, `RECEIVE_SMS`, `ACCESS_FINE_LOCATION`,
`ACCESS_COARSE_LOCATION`, `INTERNET`, `ACCESS_NETWORK_STATE`,
`RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE`. (Debug manifest adds only `INTERNET`.)

**Components:**

| Component | Type | Details |
|---|---|---|
| `.MainActivity` | activity | exported, `singleTop`, launcher |
| `.UpiNotificationListener` | service | guarded by `BIND_NOTIFICATION_LISTENER_SERVICE`, intent filter `NotificationListenerService` |
| `.SmsReceiver` | receiver | guarded by `BROADCAST_SMS`, intent filter `SMS_RECEIVED` priority 999 |
| `.SpendingWidgetProvider` | receiver | `APPWIDGET_UPDATE` + custom `com.example.receipt.UPDATE_WIDGET`; meta-data → `@xml/spending_widget_info` |

Plus a `<queries>` block for `PROCESS_TEXT` and `flutterEmbedding=2`.

## Kotlin classes

### `MainActivity : FlutterActivity`

Registers all three platform channels in `configureFlutterEngine` — full contract in
[platform-channels.md](platform-channels.md). Each `EventChannel.onListen` registers a
dynamic in-process `BroadcastReceiver` (`RECEIVER_NOT_EXPORTED` on API 33+) for the
internal actions below.

### `UpiNotificationListener : NotificationListenerService`

Filters `onNotificationPosted` by two package allowlists, then re-broadcasts internally
as `com.example.receipt.NOTIFICATION_RECEIVED` with extras
`{package, title, text, subText, timestamp = sbn.postTime}`. Extracts `EXTRA_TITLE`,
`EXTRA_TEXT`, `EXTRA_BIG_TEXT` (bigText preferred), `EXTRA_SUB_TEXT`.
`onNotificationRemoved` is a no-op.

**`UPI_PACKAGES` (10):** GPay `com.google.android.apps.nbu.paisa.user`, Paytm
`net.one97.paytm`, PhonePe `com.phonepe.app`, BHIM `in.org.npci.upiapp`, WhatsApp
`com.whatsapp`, Amazon `com.amazon.mShop.android.shopping`, MobiKwik
`com.mobikwik_new`, Freecharge `com.freecharge.android`, Airtel
`com.myairtel.myairtelapp`, Jio `com.jio.myjio`.

**`BANK_PACKAGES` (9):** SBI `com.sbi.SBIFreedomPlus`, ICICI
`com.csam.icici.bank.imobile`, Axis `com.axis.mobile`, HDFC `net.csam.hdfc`,
`com.msf.koenig.bma`, Union `com.unionbankofindia.unionbank`, Canara `com.canaaborb`,
BoI `org.boi.mobilebanking`, Indian Bank `com.infrasofttech.indianbank`.

### `SmsReceiver : BroadcastReceiver`

On the system `SMS_RECEIVED_ACTION`, extracts each message's
`displayOriginatingAddress`, `displayMessageBody` and `timestampMillis`, then
re-broadcasts internally as `com.example.receipt.SMS_RECEIVED` with extras
`{sender, body, timestamp}`. No persistence in native code.

### `SpendingWidgetProvider : AppWidgetProvider`

Home-screen widget rendered entirely from a SharedPreferences snapshot
(`receipt_widget`) pushed by Flutter — never opens SQLite from the receiver. Full
design in [../features/home-widget.md](../features/home-widget.md).

## Widget resources

- `res/xml/spending_widget_info.xml` — 4x2 cells (min 250x150dp), resizable,
  `updatePeriodMillis = 1800000` (30 min).
- `res/layout/spending_widget_layout.xml` — header (icon, "Last 24 hours", date), spent
  amount (26sp red) + trend chip, 44dp sparkline `ImageView`, footer (received green +
  count).
- Drawables: `widget_background.xml` (white→light-blue 135° gradient, 22dp corners),
  `widget_chip_up.xml` / `widget_chip_down.xml` / `widget_chip_neutral.xml`
  (translucent red/green/gray pills).

## Gradle

- [android/app/build.gradle.kts](../../android/app/build.gradle.kts):
  `applicationId = com.example.receipt`, `minSdk = 26`, target/compile SDK from the
  Flutter plugin, Java/Kotlin 17. **Release builds sign with the debug key** (no
  release keystore configured). No dependencies beyond the Flutter plugin — the Kotlin
  sources use only platform APIs.
- `android/settings.gradle.kts`: AGP 8.11.1, Kotlin 2.2.20.
- `android/gradle.properties`: `-Xmx8G`, AndroidX enabled.
