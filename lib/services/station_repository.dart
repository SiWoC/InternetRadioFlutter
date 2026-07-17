import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:internetradio/models/radio_station.dart';

/// Loads and exposes the station list from `assets/settings.json`.
class StationRepository {
  StationRepository(List<RadioStation> stations)
      : _stations = List.unmodifiable(stations);

  static const _settingsAsset = 'assets/settings.json';

  final List<RadioStation> _stations;

  /// All stations, including the trailing URL-test slot.
  List<RadioStation> get stations => _stations;

  /// Stations shown in the main grid (everything except the URL-test slot).
  List<RadioStation> get gridStations {
    if (_stations.length <= 1) {
      return _stations;
    }
    return _stations.sublist(0, _stations.length - 1);
  }

  /// Last entry in the list — reserved for Settings URL testing.
  RadioStation? get urlTestStation {
    if (_stations.isEmpty) {
      return null;
    }
    return _stations.last;
  }

  int get length => _stations.length;

  RadioStation? byIndex(int index) {
    if (index < 0 || index >= _stations.length) {
      return null;
    }
    return _stations[index];
  }

  RadioStation? byName(String name) {
    for (final station in _stations) {
      if (station.name == name) {
        return station;
      }
    }
    return null;
  }

  int? indexOfName(String name) {
    for (var i = 0; i < _stations.length; i++) {
      if (_stations[i].name == name) {
        return i;
      }
    }
    return null;
  }

  /// Loads `assets/settings.json`, or [fallbacks] if missing/invalid/empty.
  static Future<StationRepository> load() async {
    try {
      final raw = await rootBundle.loadString(_settingsAsset);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return StationRepository(fallbacks);
      }
      final stations = RadioStation.listFromSettingsJson(decoded);
      if (stations.isEmpty) {
        return StationRepository(fallbacks);
      }
      return StationRepository(stations);
    } on Object {
      return StationRepository(fallbacks);
    }
  }

  /// Hardcoded list when config cannot be loaded.
  static const List<RadioStation> fallbacks = [
    RadioStation(
      name: 'ABC Triple J NSW',
      url: 'https://live-radio01.mediahubaustralia.com/2TJW/mp3/',
      imageAssetPath: 'assets/images/triple-j.png',
    ),
    RadioStation(
      name: 'Q-Music',
      url: 'https://stream.qmusic.nl/qmusic/mp3',
      imageAssetPath: 'assets/images/qmusic.png',
    ),
    RadioStation(
      name: 'Radio 538',
      url: 'https://playerservices.streamtheworld.com/api/livestream-redirect/RADIO538.mp3',
      imageAssetPath: 'assets/images/radio-538.png',
    ),
  ];
}
