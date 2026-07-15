# Platform channels

All channels are registered in
[MainActivity.kt](../../android/app/src/main/kotlin/com/example/receipt/MainActivity.kt).
Dart consumers:
[lib/services/notification_service.dart](../../lib/services/notification_service.dart),
[lib/services/sms_service.dart](../../lib/services/sms_service.dart), and
`TransactionProvider._refreshWidget()`.

| Channel | Type | Purpose |
|---|---|---|
| `com.example.receipt/methods` | `MethodChannel` | 4 methods (below) |
| `com.example.receipt/notifications` | `EventChannel` | streams captured UPI/bank notifications |
| `com.example.receipt/sms` | `EventChannel` | streams incoming SMS |

## MethodChannel: `com.example.receipt/methods`

### `isNotificationAccessGranted` → `bool`

Checks `Settings.Secure "enabled_notification_listeners"` for the
`UpiNotificationListener` component. Dart wrapper returns false on any platform
exception.

### `openNotificationAccessSettings` → `true`

Launches `Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS` (notification access cannot
be requested via a runtime dialog).

### `readSmsHistory({limit: int = 200, since: long = 0})` → `List<Map>`

Queries `Telephony.Sms.CONTENT_URI` (ADDRESS, BODY, DATE, TYPE; `DATE > since`,
`DATE DESC LIMIT n`). Returns maps `{sender, body, timestamp, type}`. Dart wrapper
returns an empty list on error; the provider's history scan calls it with
`limit: 500`.

### `updateWidget(payload)` → `true`

Persists the Flutter-built snapshot via `SpendingWidgetProvider.saveSnapshot()` into
SharedPreferences (`receipt_widget`), then fires the package-scoped broadcast
`com.example.receipt.UPDATE_WIDGET` to re-render the widget. Payload keys:
`spent24h`, `received24h`, `spentPrev24h`, `deltaPct`, `count24h`, `spark7d`,
`updatedAt`. See [../features/home-widget.md](../features/home-widget.md).

## EventChannel: `com.example.receipt/notifications`

`onListen` registers an in-process `BroadcastReceiver` (`RECEIVER_NOT_EXPORTED` on
API 33+) for the internal action `com.example.receipt.NOTIFICATION_RECEIVED` (fired by
`UpiNotificationListener`). Event maps:

```
{ package: String, title: String, text: String, subText: String, timestamp: long }
```

Dart side exposes this as `NotificationService.notificationStream` (lazily created
broadcast stream).

## EventChannel: `com.example.receipt/sms`

Same pattern for the internal action `com.example.receipt.SMS_RECEIVED` (fired by
`SmsReceiver`). Event maps:

```
{ sender: String, body: String, timestamp: long }
```

Exposed as `SmsService.incomingSmsStream`.

## Internal broadcast actions (native-only)

| Action | Fired by | Consumed by |
|---|---|---|
| `com.example.receipt.NOTIFICATION_RECEIVED` | `UpiNotificationListener` | MainActivity's notifications event-channel receiver |
| `com.example.receipt.SMS_RECEIVED` | `SmsReceiver` | MainActivity's SMS event-channel receiver |
| `com.example.receipt.UPDATE_WIDGET` | MainActivity (`updateWidget`) | `SpendingWidgetProvider.onReceive` |
