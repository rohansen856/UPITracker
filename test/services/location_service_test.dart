import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/services/location_service.dart';

void main() {
  group('LocationData', () {
    test('holds coordinates and name', () {
      final loc = LocationData(latitude: 28.6139, longitude: 77.2090, name: 'New Delhi');
      expect(loc.latitude, 28.6139);
      expect(loc.longitude, 77.2090);
      expect(loc.name, 'New Delhi');
    });

    test('name can be null', () {
      final loc = LocationData(latitude: 0, longitude: 0);
      expect(loc.name, isNull);
    });
  });
}
