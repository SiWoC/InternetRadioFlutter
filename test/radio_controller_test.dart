import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/controllers/radio_controller.dart';
import 'package:internetradio/models/app_settings.dart';
import 'package:internetradio/models/radio_station.dart';
import 'package:internetradio/services/radio_player_service.dart';
import 'package:internetradio/services/settings_repository.dart';
import 'package:internetradio/services/station_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePlayer implements RadioPlayer {
  final playedUrls = <String>[];
  final _stateController = StreamController<RadioPlayerState>.broadcast();
  RadioPlayerState _state = const RadioPlayerState();
  bool muted = false;

  @override
  RadioPlayerState get state => _state;

  @override
  Stream<RadioPlayerState> get stateStream => _stateController.stream;

  @override
  Future<bool> play(String url, {bool applyAudioRouteFix = true}) async {
    playedUrls.add(url);
    _state = RadioPlayerState(
      url: url,
      playbackState: 'ready',
      isPlaying: true,
      isMuted: muted,
    );
    _stateController.add(_state);
    return true;
  }

  @override
  Future<void> stop() async {
    _state = RadioPlayerState(isMuted: muted);
    _stateController.add(_state);
  }

  @override
  Future<void> setMuted(bool value) async {
    muted = value;
    _state = _state.copyWith(isMuted: value);
    _stateController.add(_state);
  }

  @override
  Future<void> toggleMute() => setMuted(!muted);

  @override
  Future<void> refreshState() async {}

  @override
  void dispose() {
    _stateController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StationRepository stations;
  late SettingsRepository settings;
  late _FakePlayer player;
  late RadioController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    stations = StationRepository(const [
      RadioStation(name: 'All Time Top 40 hits', url: 'https://a.example'),
      RadioStation(name: 'ABC Triple J NSW', url: 'https://triplej.example'),
    ]);
    settings = await SettingsRepository.load();
    player = _FakePlayer();
    controller = RadioController(
      stations: stations,
      settings: settings,
      player: player,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  test('selectStation plays URL and persists name', () async {
    await controller.selectStation(1);

    expect(controller.selectedStationIndex, 1);
    expect(controller.selectedStation?.name, 'ABC Triple J NSW');
    expect(player.playedUrls, ['https://triplej.example']);
    expect(settings.settings.lastStationName, 'ABC Triple J NSW');
  });

  test('selectStation ignores out-of-range index', () async {
    await controller.selectStation(99);

    expect(controller.selectedStationIndex, isNull);
    expect(player.playedUrls, isEmpty);
    expect(settings.settings.lastStationName, isNull);
  });

  test('restoreLastStation replays saved Player-mode station', () async {
    await settings.save(
      const AppSettings(lastStationName: 'ABC Triple J NSW'),
    );

    await controller.restoreLastStation();

    expect(controller.selectedStationIndex, 1);
    expect(player.playedUrls, ['https://triplej.example']);
  });

  test('restoreLastStation skips Remote mode', () async {
    await settings.save(
      const AppSettings(
        mode: OperatingMode.remote,
        lastStationName: 'ABC Triple J NSW',
      ),
    );

    await controller.restoreLastStation();

    expect(controller.selectedStationIndex, isNull);
    expect(player.playedUrls, isEmpty);
  });

  test('toggleMute and stop forward to player', () async {
    await controller.selectStation(0);
    await controller.toggleMute();
    expect(player.muted, isTrue);
    expect(controller.playerState.isMuted, isTrue);

    await controller.stop();
    expect(controller.playerState.url, isNull);
    expect(controller.playerState.isPlaying, isFalse);
  });
}
