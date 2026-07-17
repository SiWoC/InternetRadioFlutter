import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:internetradio/models/app_settings.dart';
import 'package:internetradio/models/radio_station.dart';
import 'package:internetradio/services/radio_player_service.dart';
import 'package:internetradio/services/settings_repository.dart';
import 'package:internetradio/services/station_repository.dart';

/// Orchestrates playback, station selection, and settings persistence.
class RadioController extends ChangeNotifier {
  RadioController({
    required StationRepository stations,
    required SettingsRepository settings,
    RadioPlayer? player,
  })  : _stations = stations,
        _settings = settings,
        _player = player ?? RadioPlayerService()
  {
    _playerSubscription = _player.stateStream.listen((state) {
      _playerState = state;
      notifyListeners();
    });
    _playerState = _player.state;
  }

  final StationRepository _stations;
  final SettingsRepository _settings;
  final RadioPlayer _player;

  StreamSubscription<RadioPlayerState>? _playerSubscription;
  RadioPlayerState _playerState = const RadioPlayerState();
  int? _selectedStationIndex;
  bool _disposed = false;

  StationRepository get stations => _stations;

  AppSettings get settings => _settings.settings;

  RadioPlayerState get playerState => _playerState;

  /// Index of the last selected station, or null if none yet.
  int? get selectedStationIndex => _selectedStationIndex;

  RadioStation? get selectedStation {
    final index = _selectedStationIndex;
    if (index == null) {
      return null;
    }
    return _stations.byIndex(index);
  }

  /// Plays [index], persists its name, and notifies listeners.
  ///
  /// No-op when [index] is out of range.
  Future<void> selectStation(int index) async {
    _assertNotDisposed();
    final station = _stations.byIndex(index);
    if (station == null) {
      return;
    }

    _selectedStationIndex = index;
    notifyListeners();

    await _settings.save(
      _settings.settings.copyWith(lastStationName: station.name),
    );
    await _player.play(station.url);
  }

  Future<void> stop() async {
    _assertNotDisposed();
    await _player.stop();
  }

  Future<void> toggleMute() async {
    _assertNotDisposed();
    await _player.toggleMute();
  }

  /// Restores the last station when in Player mode and a name is stored.
  Future<void> restoreLastStation() async {
    _assertNotDisposed();
    final current = _settings.settings;
    if (current.mode != OperatingMode.player) {
      return;
    }
    final name = current.lastStationName;
    if (name == null) {
      return;
    }
    final index = _stations.indexOfName(name);
    if (index == null) {
      return;
    }
    await selectStation(index);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _playerSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('RadioController has been disposed');
    }
  }
}
