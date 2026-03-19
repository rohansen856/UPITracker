import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationData {
  final double latitude;
  final double longitude;
  final String? name;

  LocationData({required this.latitude, required this.longitude, this.name});
}

class LocationService {
  Future<bool> isLocationEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  Future<bool> hasPermission() async {
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  Future<bool> requestPermission() async {
    final perm = await Geolocator.requestPermission();
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  Future<LocationData?> getCurrentLocation() async {
    try {
      if (!await isLocationEnabled()) return null;
      if (!await hasPermission()) {
        final granted = await requestPermission();
        if (!granted) return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      String? placeName;
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = [p.name, p.subLocality, p.locality, p.administrativeArea]
              .where((s) => s != null && s.isNotEmpty);
          placeName = parts.join(', ');
        }
      } catch (_) {}

      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        name: placeName,
      );
    } catch (_) {
      return null;
    }
  }
}
