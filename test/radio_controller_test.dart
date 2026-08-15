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
import 'package:internetradio/services/wakelock_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePlayer implements RadioPlayer {
  final playedUrls = <String>[];
  final _stateController = StreamController<RadioPlayerState>.broadcast();
  RadioPlayerState _state = const RadioPlayerState();
  bool muted = false;
  var stopCount = 0;
  var wakeDisplayCount = 0;

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
  Future<void> wakeDisplay() async {
    wakeDisplayCount++;
  }

  @override
  void dispose() {
    _stateController.close();
  }
}

class _FakeNetwork extends NetworkService {
  final sent = <String>[];
  String? Function(String command)? onCommand;
  NetworkCommandHandler? handler;
  var listenerStarted = false;

  @override
  Future<void> startListener({
    required NetworkCommandHandler onCommand,
    int port = NetworkProtocol.port,
  }) async {
    listenerStarted = true;
    handler = onCommand;
  }

  @override
  Future<void> stopListener() async {
    listenerStarted = false;
    handler = null;
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

  var pingResult = true;
  var pingCount = 0;

  @override
  Future<bool> ping(
    String ipAddress, {
    Duration timeout = NetworkProtocol.connectionTimeout,
    int port = NetworkProtocol.port,
  }) async {
    pingCount++;
    return pingResult;
  }
}

class _FakeWakelock implements ScreenWakelock {
  bool enabled = false;

  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StationRepository stations;
  late SettingsRepository settings;
  late _FakePlayer player;
  late _FakeNetwork network;
  late _FakeWakelock wakelock;
  late RadioController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    stations = StationRepository(const [
      RadioStation(name: 'All Time Top 40 hits', url: 'https://a.example'),
      RadioStation(name: 'ABC Triple J NSW', url: 'https://triplej.example'),
      RadioStation(name: 'URL test', url: 'https://json-test.example'),
    ]);
    settings = await SettingsRepository.load();
    player = _FakePlayer();
    network = _FakeNetwork();
    wakelock = _FakeWakelock();
    controller = RadioController(
      stations: stations,
      settings: settings,
      player: player,
      network: network,
      wakelock: wakelock,
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
    expect(network.pingCount, 0);
    expect(controller.playerUnreachable, isFalse);
  });

  test('requestRemoteMode ping failure stays Player and marks unreachable',
      () async {
    await controller.savePlayerIp('192.168.1.10');
    network.pingResult = false;

    final switched = await controller.requestRemoteMode();

    expect(switched, isFalse);
    expect(controller.isPlayerMode, isTrue);
    expect(controller.playerUnreachable, isTrue);
    expect(network.pingCount, 1);
  });

  test('requestRemoteMode ping success enters Remote and clears unreachable',
      () async {
    await controller.savePlayerIp('192.168.1.10');
    network.pingResult = false;
    await controller.requestRemoteMode();
    expect(controller.playerUnreachable, isTrue);

    network.pingResult = true;
    final switched = await controller.requestRemoteMode();

    expect(switched, isTrue);
    expect(controller.isRemoteMode, isTrue);
    expect(controller.playerUnreachable, isFalse);
    expect(network.pingCount, 2);
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

  test('playTestUrl plays locally in Player mode and persists', () async {
    await controller.playTestUrl(' https://test.example/stream ');

    expect(controller.selectedStationIndex, 2);
    expect(player.playedUrls, ['https://test.example/stream']);
    expect(settings.settings.testUrl, 'https://test.example/stream');
    expect(settings.settings.lastStationName, 'URL test');
    expect(network.sent, isEmpty);
  });

  test('playTestUrl sends TESTURL in Remote mode', () async {
    await controller.savePlayerIp('192.168.1.10');
    await controller.enterRemoteMode();
    network.sent.clear();
    network.onCommand = (_) => NetworkProtocol.ok;

    await controller.playTestUrl('https://test.example/stream');

    expect(player.playedUrls, isEmpty);
    expect(network.sent, contains(NetworkProtocol.testUrl('https://test.example/stream')));
    expect(settings.settings.testUrl, 'https://test.example/stream');
  });

  test('selectStation on URL-test slot uses persisted testUrl', () async {
    await settings.save(
      const AppSettings(testUrl: 'https://override.example/stream'),
    );

    await controller.selectStation(2);

    expect(player.playedUrls, ['https://override.example/stream']);
    expect(settings.settings.lastStationName, 'URL test');
  });

  test('selectStation on URL-test slot replays URL after playTestUrl', () async {
    await controller.playTestUrl('https://test.example/stream');
    player.playedUrls.clear();

    await controller.selectStation(2);

    expect(player.playedUrls, ['https://test.example/stream']);
  });

  test('Remote selectStation on URL-test slot sends TESTURL with effective URL',
      () async {
    await controller.savePlayerIp('192.168.1.10');
    await settings.save(
      settings.settings.copyWith(testUrl: 'https://override.example/stream'),
    );
    await controller.enterRemoteMode();
    network.sent.clear();
    network.onCommand = (_) => NetworkProtocol.ok;

    await controller.selectStation(2);

    expect(player.playedUrls, isEmpty);
    expect(
      network.sent,
      contains(NetworkProtocol.testUrl('https://override.example/stream')),
    );
  });

  test('Player keepScreenOn enables wakelock; Remote and allowScreenOff disable',
      () async {
    await controller.startForCurrentMode();
    expect(wakelock.enabled, isTrue);

    await controller.setDisplayPolicy(DisplayPolicy.allowScreenOff);
    expect(wakelock.enabled, isFalse);

    await controller.setDisplayPolicy(DisplayPolicy.keepScreenOn);
    expect(wakelock.enabled, isTrue);

    await controller.savePlayerIp('192.168.1.10');
    await controller.enterRemoteMode();
    expect(wakelock.enabled, isFalse);

    await controller.enterPlayerMode();
    expect(wakelock.enabled, isTrue);
  });

  test('allowScreenOff wakes display on mutating remote command only', () async {
    await controller.setDisplayPolicy(DisplayPolicy.allowScreenOff);
    await controller.startPlayerListener();

    await network.handler!(const MuteCommand());
    expect(player.wakeDisplayCount, 1);

    await network.handler!(const PingCommand());
    await network.handler!(const GetStateCommand());
    expect(player.wakeDisplayCount, 1);

    await network.handler!(const SelectStationCommand(0));
    expect(player.wakeDisplayCount, 2);
  });

  test('keepScreenOn does not wake display on remote command', () async {
    await controller.setDisplayPolicy(DisplayPolicy.keepScreenOn);
    await controller.startPlayerListener();

    await network.handler!(const MuteCommand());
    expect(player.wakeDisplayCount, 0);
  });

  test('saveSettings persists IP and can clear test URL', () async {
    await controller.playTestUrl('https://old.example/stream');
    await controller.saveSettings(
      playerIp: '10.0.0.8',
      testUrl: '',
    );

    expect(controller.settings.playerIp, '10.0.0.8');
    expect(controller.settings.testUrl, isNull);
  });
}
