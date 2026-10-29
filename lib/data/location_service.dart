import 'package:geolocator/geolocator.dart';

import '../domain/models.dart';

/// How the app obtains a position. Reviewers can switch this from the
/// developer sheet in the app, or start with --dart-define=SIM_LOCATION=inside|outside.
enum LocationMode { gps, simulatedInside, simulatedOutside }

class LocationException implements Exception {
  LocationException(this.message, {this.openSettings = false});
  final String message;
  final bool openSettings; // permission permanently denied: only Settings can fix it
  @override
  String toString() => message;
}

class LocationService {
  LocationService()
      : mode = switch (const String.fromEnvironment('SIM_LOCATION')) {
          'inside' => LocationMode.simulatedInside,
          'outside' => LocationMode.simulatedOutside,
          _ => LocationMode.gps,
        };

  LocationMode mode;

  Future<({double lat, double lng})> current(Office office) async {
    switch (mode) {
      case LocationMode.simulatedInside:
        return (lat: office.latitude + 0.0005, lng: office.longitude); // ~55 m north
      case LocationMode.simulatedOutside:
        return (lat: office.latitude + 0.0045, lng: office.longitude); // ~500 m north
      case LocationMode.gps:
        break;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationException('Location services are turned off. Enable them and try again.', openSettings: true);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw LocationException('Location permission is required to record attendance.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationException('Location permission was permanently denied. Allow it in Settings to record attendance.',
          openSettings: true);
    }
    try {
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
      return (lat: p.latitude, lng: p.longitude);
    } catch (_) {
      throw LocationException('Your location is currently unavailable. Move to an open area and try again.');
    }
  }

  Future<void> openSettings() async {
    await (await Geolocator.isLocationServiceEnabled() ? Geolocator.openAppSettings() : Geolocator.openLocationSettings());
  }
}
