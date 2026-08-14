import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/controllers/radio_controller.dart';
import 'package:internetradio/models/app_settings.dart';
import 'package:internetradio/models/radio_player_state.dart';
import 'package:internetradio/models/radio_station.dart';
import 'package:internetradio/models/remote_player_state.dart';
import 'package:internetradio/services/network_protocol.dart';
import 'package:internetradio/services/network_service.dart';
import 'package:internetradio/services/radio_player_service.dart';
import 'package:internetradio/services/settings_repository.dart';
import 'package:internetradio/services/station_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePlayer implements RadioPlayer {
  final playedUrls = <String>[];
  final _stateController = StreamController<RadioPlayerState>.broadcast();
  RadioPlayerState _state = const RadioPlayerState();
  bool muted = false;
  var stopCount = 0;

  @override
  RadioPlayerState get state => _state;

  @override
  Stream<RadioPlayerState> get stateStream => _stateController.stream;

  @override
  Future<bool> play(String url, {String? title, bool applyAudioRouteFix = true}) async {
    playedUrls.add(url);
    _state = RadioPlayerState(
      url: url,
      playbackState: PlaybackState.Ready,
      isPlaying: true,
      isMuted: muted,
    );
    _stateController.add(_state);
    return true;
  }

  @override
  Future<void> stop() async {
    stopCount++;
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

class _FakeNetwork extends NetworkService {
  final sent = <String>[];
  String? Function(String command)? onCommand;
  var listenerStarted = false;

  @override
  Future<void> startListener({
    required NetworkCommandHandler onCommand,
    int port = NetworkProtocol.port,
  }) async {
    listenerStarted = true;
  }

  @override
  Future<void> stopListener() async {
    listenerStarted = false;
  }

  @override
  Future<String?> sendCommand(
    String ipAddress,
    String command, {
    Duration timeout = NetworkProtocol.connectionTimeout,
    int port = NetworkProtocol.port,
  }) async {
    sent.add(command);
    return onCommand?.call(command);
  }

  @override
  Future<bool> ping(
    String ipAddress, {
    Duration timeout = NetworkProtocol.connectionTimeout,
    int port = NetworkProtocol.port,
  }) async {
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StationRepository stations;
  late SettingsRepository settings;
  late _FakePlayer player;
  late _FakeNetwork network;
  late RadioController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    stations = StationRepository(const [
      RadioStation(name: 'All Time Top 40 hits', url: 'https://a.example'),
      RadioStation(name: 'ABC Triple J NSW', url: 'https://triplej.example'),
    ]);
    settings = await SettingsRepository.load();
    player = _FakePlayer();
    network = _FakeNetwork();
    controller = RadioController(
      stations: stations,
      settings: settings,
      player: player,
      network: network,
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

  test('startForCurrentMode Player restores station', () async {
    await settings.save(
      const AppSettings(lastStationName: 'ABC Triple J NSW'),
    );

    await controller.startForCurrentMode();

    expect(controller.selectedStationIndex, 1);
    expect(player.playedUrls, ['https://triplej.example']);
    expect(network.listenerStarted, isTrue);
  });

  test('startForCurrentMode Remote does not restore station', () async {
    await settings.save(
      const AppSettings(
        mode: OperatingMode.remote,
        playerIp: '192.168.1.10',
        lastStationName: 'ABC Triple J NSW',
      ),
    );
    network.onCommand = (_) => 'STATE|1|0|1';

    await controller.startForCurrentMode();
    await Future<void>.delayed(Duration.zero);

    expect(player.playedUrls, isEmpty);
    expect(network.listenerStarted, isFalse);
    expect(network.sent, contains(NetworkProtocol.getState));
    expect(controller.selectedStationIndex, 1);
    expect(controller.isPlaying, isTrue);
  });

  test('requestRemoteMode with empty IP opens settings', () async {
    final switched = await controller.requestRemoteMode();

    expect(switched, isFalse);
    expect(controller.isSettingsOpen, isTrue);
    expect(controller.settingsMessage, 'Invalid Player IP-address');
    expect(controller.isPlayerMode, isTrue);
  });

  test('enterRemoteMode stops local audio and sends remote commands', () async {
    await controller.savePlayerIp('192.168.1.10');
    await controller.selectStation(0);
    network.listenerStarted = true;
    network.onCommand = (command) {
      if (command == NetworkProtocol.getState) {
        return 'STATE|0|0|1';
      }
      return NetworkProtocol.ok;
    };

    await controller.enterRemoteMode();

    expect(controller.isRemoteMode, isTrue);
    expect(settings.settings.mode, OperatingMode.remote);
    expect(player.stopCount, greaterThan(0));
    expect(network.listenerStarted, isFalse);

    await controller.selectStation(1);
    expect(network.sent, contains(NetworkProtocol.selectStation(1)));
    expect(player.playedUrls, ['https://a.example']);

    await controller.toggleMute();
    expect(network.sent, contains(NetworkProtocol.mute));
    expect(controller.isMuted, isTrue);
  });

  test('enterPlayerMode restores listener and last station', () async {
    await settings.save(
      const AppSettings(
        mode: OperatingMode.remote,
        playerIp: '10.0.0.2',
        lastStationName: 'ABC Triple J NSW',
      ),
    );
    network.onCommand = (_) => 'STATE|0|0|0';
    await controller.startForCurrentMode();

    await controller.enterPlayerMode();

    expect(controller.isPlayerMode, isTrue);
    expect(network.listenerStarted, isTrue);
    expect(controller.selectedStationIndex, 1);
    expect(player.playedUrls, ['https://triplej.example']);
  });

  test('savePlayerIp persists empty and non-empty values', () async {
    await controller.savePlayerIp('192.168.1.20');
    expect(controller.settings.playerIp, '192.168.1.20');

    await controller.savePlayerIp('');
    expect(controller.settings.playerIp, '');
  });

  test('openSettings / closeSettings toggles isSettingsOpen', () {
    expect(controller.isSettingsOpen, isFalse);
    controller.openSettings();
    expect(controller.isSettingsOpen, isTrue);
    controller.closeSettings();
    expect(controller.isSettingsOpen, isFalse);
  });

  test('remotePlayerState mirrors selection and player flags', () async {
    await controller.selectStation(1);
    await controller.setMuted(true);

    expect(
      controller.remotePlayerState,
      const RemotePlayerState(
        stationIndex: 1,
        isMuted: true,
        isPlaying: true,
      ),
    );
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
