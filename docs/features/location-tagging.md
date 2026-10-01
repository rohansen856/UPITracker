# Location tagging

Optional, best-effort geotagging of live-captured transactions.
[lib/services/location_service.dart](../../lib/services/location_service.dart) wraps
`geolocator` + `geocoding`.

## Behavior

- `getCurrentLocation() → Future<LocationData?>` — returns `null` on **any** failure
  (service disabled, permission denied, timeout). Requests permission if missing.
  Uses `LocationAccuracy.medium` with a **10-second time limit**.
- Reverse-geocodes to a display name by joining the non-empty parts of
  `[name, subLocality, locality, administrativeArea]` with `", "`. A geocoding failure
  is tolerated — coordinates are still returned without a name.
- `LocationData { latitude, longitude, name? }` is stored on the record as
  `latitude` / `longitude` / `location_name`, at full precision, and is **included in
  cloud sync**.
- The lookup is awaited inline before the record is inserted, so a slow fix delays a
  live capture by up to 10 seconds.

## Where it applies

Only **live** captures (`_processTransaction` during notification/SMS ingestion). The
SMS history scan and manual entries skip the lookup — a historical location would be
wrong anyway.

## Permissions

`ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION` are declared but optional; the
Settings screen exposes a "Grant" button via `permission_handler`
(`Permission.location`). With permission denied the pipeline simply stores no
coordinates — ingestion is never blocked on location.
