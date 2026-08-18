import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/controllers/radio_controller.dart';
import 'package:internetradio/models/app_settings.dart';
import 'package:internetradio/models/radio_player_state.dart';
import 'package:internetradio/models/radio_station.dart';
import 'package:internetradio/models/remote_player_state.dart';
import 'package:internetradio/models/yamaha_status.dart';
import 'package:internetradio/services/network_protocol.dart';
import 'package:internetradio/services/network_service.dart';
import 'package:internetradio/services/radio_player_service.dart';
import 'package:internetradio/services/settings_repository.dart';
import 'package:internetradio/services/station_repository.dart';
import 'package:internetradio/services/wakelock_service.dart';
import 'package:internetradio/services/yamaha_service.dart';
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
  Future<bool> play(
    String url, {
    String? title,
    bool applyAudioRouteFix = true,
  }) async {
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

  void emit(RadioPlayerState state) {
    _state = state;
    _stateController.add(_state);
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
  String? findPlayerResult;
  final findPlayerCalls = <(String, String)>[];

  @override
  Future<bool> ping(
    String ipAddress, {
    Duration timeout = NetworkProtocol.connectionTimeout,
    int port = NetworkProtocol.port,
  }) async {
    pingCount++;
    return pingResult;
  }

  @override
  Future<String?> findPlayer({
    required String localIpv4,
    required String afterIp,
    Duration timeout = const Duration(milliseconds: 400),
    int concurrency = 32,
  }) async {
    findPlayerCalls.add((localIpv4, afterIp));
    return findPlayerResult;
  }
}

class _FakeWakelock implements ScreenWakelock {
  bool enabled = false;

  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
  }
}

class _FakeYamaha extends YamahaService {
  YamahaStatus? status = const YamahaStatus(
    power: YamahaPower.standby,
    inputSel: 'HDMI4',
    volumeTenthsDb: -570,
    mute: false,
  );
  List<YamahaInput>? inputs = const [
    YamahaInput(param: 'HDMI4', title: 'Mediaplay'),
    YamahaInput(param: 'HDMI2', title: 'HDMI2'),
  ];
  String? foundReceiverIp;
  var setPowerOk = true;
  var selectInputOk = true;
  var volumeOk = true;
  final setPowerCalls = <YamahaPower>[];
  final selectInputCalls = <String>[];
  final setVolumeCalls = <int>[];
  var getBasicStatusCount = 0;

  @override
  Future<YamahaStatus?> getBasicStatus(String ip) async {
    getBasicStatusCount++;
    return status;
  }

  @override
  Future<List<YamahaInput>?> getInputList(String ip) async => inputs;

  @override
  Future<String?> findReceiver({String afterIp = ''}) async => foundReceiverIp;

  @override
  Future<bool> setPower(String ip, YamahaPower power) async {
    setPowerCalls.add(power);
    if (!setPowerOk) {
      return false;
    }
    _patchStatus(power: power);
    return true;
  }

  @override
  Future<bool> selectInput(String ip, String inputSel) async {
    selectInputCalls.add(inputSel);
    if (!selectInputOk) {
      return false;
    }
    _patchStatus(inputSel: inputSel);
    return true;
  }

  @override
  Future<bool> setVolume(String ip, int tenthsDb) async {
    setVolumeCalls.add(tenthsDb);
    if (!volumeOk) {
      return false;
    }
    _patchStatus(volumeTenthsDb: tenthsDb);
    return true;
  }

  void _patchStatus({
    YamahaPower? power,
    String? inputSel,
    int? volumeTenthsDb,
  }) {
    final current = status;
    if (current == null) {
      return;
    }
    status = YamahaStatus(
      power: power ?? current.power,
      inputSel: inputSel ?? current.inputSel,
      volumeTenthsDb: volumeTenthsDb ?? current.volumeTenthsDb,
      mute: current.mute,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StationRepository stations;
  late SettingsRepository settings;
  late _FakePlayer player;
  late _FakeNetwork network;
  late _FakeWakelock wakelock;
  late _FakeYamaha yamaha;
  late int exitAppCount;
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
    yamaha = _FakeYamaha();
    exitAppCount = 0;
    controller = RadioController(
      stations: stations,
      settings: settings,
      player: player,
      network: network,
      yamaha: yamaha,
      wakelock: wakelock,
      localIpv4: () async => '192.168.1.50',
      exitApp: () async {
        exitAppCount++;
      },
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
    await settings.save(const AppSettings(lastStationName: 'ABC Triple J NSW'));

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
    await settings.save(const AppSettings(lastStationName: 'ABC Triple J NSW'));

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
    network.onCommand = (_) => 'STATE|1|0|1||';

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

  test(
    'requestRemoteMode ping failure stays Player and marks unreachable',
    () async {
      await controller.savePlayerIp('192.168.1.10');
      network.pingResult = false;

      final switched = await controller.requestRemoteMode();

      expect(switched, isFalse);
      expect(controller.isPlayerMode, isTrue);
      expect(controller.playerUnreachable, isTrue);
      expect(network.pingCount, 1);
    },
  );

  test(
    'requestRemoteMode ping success enters Remote and clears unreachable',
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
    },
  );

  test('enterRemoteMode stops local audio and sends remote commands', () async {
    await controller.savePlayerIp('192.168.1.10');
    await controller.selectStation(0);
    network.listenerStarted = true;
    network.onCommand = (command) {
      if (command == NetworkProtocol.getState) {
        return 'STATE|0|0|1||';
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
    network.onCommand = (_) => 'STATE|0|0|0||';
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
        stationTitle: 'ABC Triple J NSW',
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

  test('ExitCommand stops playback and exits the Player app', () async {
    await controller.selectStation(0);
    await controller.startPlayerListener();

    await network.handler!(const ExitCommand());
    expect(player.stopCount, greaterThan(0));
    expect(controller.playerState.isPlaying, isFalse);
    expect(exitAppCount, 0);

    await Future<void>.delayed(Duration.zero);
    expect(exitAppCount, 1);
  });

  test('exitRemotePlayer sends EXIT only in Remote mode', () async {
    await controller.savePlayerIp('192.168.1.10');
    await controller.exitRemotePlayer();
    expect(network.sent, isEmpty);

    await controller.enterRemoteMode();
    network.sent.clear();
    network.onCommand = (_) => NetworkProtocol.ok;

    await controller.exitRemotePlayer();
    expect(network.sent, contains(NetworkProtocol.exit));
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
    expect(
      network.sent,
      contains(NetworkProtocol.testUrl('https://test.example/stream')),
    );
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

  test(
    'selectStation on URL-test slot replays URL after playTestUrl',
    () async {
      await controller.playTestUrl('https://test.example/stream');
      player.playedUrls.clear();

      await controller.selectStation(2);

      expect(player.playedUrls, ['https://test.example/stream']);
    },
  );

  test(
    'Remote selectStation on URL-test slot sends TESTURL with effective URL',
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
    },
  );

  test(
    'Player keepScreenOn enables wakelock; Remote and allowScreenOff disable',
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
    },
  );

  test(
    'allowScreenOff wakes display on mutating remote command only',
    () async {
      await controller.setDisplayPolicy(DisplayPolicy.allowScreenOff);
      await controller.startPlayerListener();

      await network.handler!(const MuteCommand());
      expect(player.wakeDisplayCount, 1);

      await network.handler!(const PingCommand());
      await network.handler!(const GetStateCommand());
      expect(player.wakeDisplayCount, 1);

      await network.handler!(const SelectStationCommand(0));
      expect(player.wakeDisplayCount, 2);

      await network.handler!(const ExitCommand());
      expect(player.wakeDisplayCount, 2);
    },
  );

  test('keepScreenOn does not wake display on remote command', () async {
    await controller.setDisplayPolicy(DisplayPolicy.keepScreenOn);
    await controller.startPlayerListener();

    await network.handler!(const MuteCommand());
    expect(player.wakeDisplayCount, 0);
  });

  test('saveSettings persists IP and can clear test URL', () async {
    await controller.playTestUrl('https://old.example/stream');
    await controller.saveSettings(playerIp: '10.0.0.8', testUrl: '');

    expect(controller.settings.playerIp, '10.0.0.8');
    expect(controller.settings.testUrl, isNull);
  });

  test('saveSettings persists Yamaha IP', () async {
    await controller.saveSettings(
      playerIp: '10.0.0.8',
      testUrl: '',
      yamahaIp: '192.168.2.2',
    );

    expect(controller.settings.yamahaIp, '192.168.2.2');
  });

  test('testYamahaConnection is true when Basic_Status parses', () async {
    expect(await controller.testYamahaConnection('192.168.2.2'), isTrue);
    yamaha.status = null;
    expect(await controller.testYamahaConnection('192.168.2.2'), isFalse);
  });

  test('findPlayerIp sweeps from local /24 after the current IP', () async {
    network.findPlayerResult = '192.168.1.20';

    expect(await controller.findPlayerIp('192.168.1.10'), '192.168.1.20');
    expect(network.findPlayerCalls, [('192.168.1.50', '192.168.1.10')]);
  });

  test('findPlayerIp is null when this device has no IPv4', () async {
    controller.dispose();
    controller = RadioController(
      stations: stations,
      settings: settings,
      player: player,
      network: network,
      yamaha: yamaha,
      wakelock: wakelock,
      localIpv4: () async => 'No IP',
      exitApp: () async {},
    );
    network.findPlayerResult = '192.168.1.20';

    expect(await controller.findPlayerIp('192.168.1.10'), isNull);
    expect(network.findPlayerCalls, isEmpty);
  });

  test('findYamahaIp forwards the current receiver IP', () async {
    yamaha.foundReceiverIp = '192.168.2.8';
    expect(await controller.findYamahaIp('192.168.2.2'), '192.168.2.8');
  });

  test('openYamaha with empty IP opens Settings', () {
    controller.openYamaha();

    expect(controller.isYamahaOpen, isFalse);
    expect(controller.isSettingsOpen, isTrue);
    expect(controller.settingsMessage, 'Invalid Yamaha IP-address');
  });

  test('openYamaha loads status and input list', () async {
    await controller.saveYamahaIp('192.168.2.2');

    controller.openYamaha();
    expect(controller.isYamahaOpen, isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(controller.yamahaStatus?.power, YamahaPower.standby);
    expect(controller.yamahaInputs, [
      const YamahaInput(param: 'HDMI4', title: 'Mediaplay'),
      const YamahaInput(param: 'HDMI2', title: 'HDMI2'),
    ]);
    expect(controller.isSettingsOpen, isFalse);
  });

  test('toggleYamahaPower turns Standby into On', () async {
    await controller.saveYamahaIp('192.168.2.2');

    await controller.toggleYamahaPower();

    expect(yamaha.setPowerCalls, [YamahaPower.on]);
    expect(controller.yamahaStatus?.power, YamahaPower.on);
  });

  test('toggleYamahaPower turns On into Standby', () async {
    await controller.saveYamahaIp('192.168.2.2');
    yamaha.status = const YamahaStatus(
      power: YamahaPower.on,
      inputSel: 'HDMI4',
      volumeTenthsDb: -570,
      mute: false,
    );

    await controller.toggleYamahaPower();

    expect(yamaha.setPowerCalls, [YamahaPower.standby]);
    expect(controller.yamahaStatus?.power, YamahaPower.standby);
  });

  test('selectYamahaInput wakes from Standby then sets input', () async {
    await controller.saveYamahaIp('192.168.2.2');

    await controller.selectYamahaInput('HDMI2');

    expect(yamaha.setPowerCalls, [YamahaPower.on]);
    expect(yamaha.selectInputCalls, ['HDMI2']);
    expect(controller.yamahaStatus?.power, YamahaPower.on);
    expect(controller.yamahaStatus?.inputSel, 'HDMI2');
  });

  test('selectYamahaInput skips wake when already On', () async {
    await controller.saveYamahaIp('192.168.2.2');
    yamaha.status = const YamahaStatus(
      power: YamahaPower.on,
      inputSel: 'HDMI4',
      volumeTenthsDb: -570,
      mute: false,
    );

    await controller.selectYamahaInput('HDMI2');

    expect(yamaha.setPowerCalls, isEmpty);
    expect(yamaha.selectInputCalls, ['HDMI2']);
    expect(controller.yamahaStatus?.inputSel, 'HDMI2');
  });

  test('selectYamahaInput GETs status when selectInput fails', () async {
    await controller.saveYamahaIp('192.168.2.2');
    yamaha.status = const YamahaStatus(
      power: YamahaPower.on,
      inputSel: 'HDMI4',
      volumeTenthsDb: -570,
      mute: false,
    );
    yamaha.selectInputOk = false;

    await controller.selectYamahaInput('HDMI2');

    expect(yamaha.selectInputCalls, ['HDMI2']);
    expect(controller.yamahaStatus?.power, YamahaPower.on);
    expect(controller.yamahaStatus?.inputSel, 'HDMI4');
  });

  test('selectYamahaInput GETs status when wake fails', () async {
    await controller.saveYamahaIp('192.168.2.2');
    yamaha.setPowerOk = false;

    await controller.selectYamahaInput('HDMI2');

    expect(yamaha.setPowerCalls, [YamahaPower.on]);
    expect(yamaha.selectInputCalls, isEmpty);
    expect(controller.yamahaStatus?.power, YamahaPower.standby);
    expect(controller.yamahaStatus?.inputSel, 'HDMI4');
  });

  test('yamahaVolumeUp wakes from Standby then steps volume', () async {
    await controller.saveYamahaIp('192.168.2.2');

    await controller.yamahaVolumeUp();

    expect(yamaha.setPowerCalls, [YamahaPower.on]);
    expect(yamaha.setVolumeCalls, [-565]);
    expect(controller.yamahaStatus?.power, YamahaPower.on);
    expect(controller.yamahaStatus?.volumeTenthsDb, -565);
  });

  test('yamahaVolumeDown wakes from Standby then steps volume', () async {
    await controller.saveYamahaIp('192.168.2.2');

    await controller.yamahaVolumeDown();

    expect(yamaha.setPowerCalls, [YamahaPower.on]);
    expect(yamaha.setVolumeCalls, [-575]);
    expect(controller.yamahaStatus?.volumeTenthsDb, -575);
  });

  test('yamahaVolumeUp after load does not GET again when On', () async {
    await controller.saveYamahaIp('192.168.2.2');
    yamaha.status = const YamahaStatus(
      power: YamahaPower.on,
      inputSel: 'HDMI4',
      volumeTenthsDb: -570,
      mute: false,
    );
    controller.openYamaha();
    await Future<void>.delayed(Duration.zero);
    yamaha.getBasicStatusCount = 0;

    await controller.yamahaVolumeUp();

    expect(yamaha.getBasicStatusCount, 0);
    expect(yamaha.setPowerCalls, isEmpty);
    expect(yamaha.setVolumeCalls, [-565]);
    expect(controller.yamahaStatus?.volumeTenthsDb, -565);
  });

  test(
    'chromeStationTitle uses config name then stream station name',
    () async {
      await controller.selectStation(0);
      expect(controller.chromeStationTitle, 'All Time Top 40 hits');
      expect(controller.chromeNowPlaying, isNull);

      player.emit(
        RadioPlayerState(
          url: 'https://a.example',
          playbackState: PlaybackState.Ready,
          isPlaying: true,
          streamStationName: 'Icecast One',
          nowPlaying: 'Queen - Bohemian Rhapsody',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.chromeStationTitle, 'Icecast One');
      expect(controller.chromeNowPlaying, 'Queen - Bohemian Rhapsody');
    },
  );

  test(
    'chromeNowPlaying is hidden when it matches the station title',
    () async {
      await controller.selectStation(0);
      player.emit(
        RadioPlayerState(
          url: 'https://a.example',
          playbackState: PlaybackState.Ready,
          isPlaying: true,
          nowPlaying: 'All Time Top 40 hits',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.chromeNowPlaying, isNull);
    },
  );

  test('Remote chrome uses config name and no now-playing', () async {
    await controller.savePlayerIp('192.168.1.10');
    await controller.enterRemoteMode();

    expect(controller.chromeStationTitle, 'Waiting for player');
    expect(controller.chromeNowPlaying, isNull);
  });

  test('GET_STATE includes chrome station title and now-playing', () async {
    await controller.selectStation(0);
    await controller.startPlayerListener();
    player.emit(
      RadioPlayerState(
        url: 'https://a.example',
        playbackState: PlaybackState.Ready,
        isPlaying: true,
        streamStationName: 'Icecast One',
        nowPlaying: 'Queen - Bohemian Rhapsody',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final reply = await network.handler!(const GetStateCommand());
    expect(
      reply,
      NetworkProtocol.encodeState(
        const RemotePlayerState(
          stationIndex: 0,
          isPlaying: true,
          stationTitle: 'Icecast One',
          nowPlaying: 'Queen - Bohemian Rhapsody',
        ),
      ),
    );
  });

  test('Remote chrome uses polled station title and now-playing', () async {
    await settings.save(
      const AppSettings(mode: OperatingMode.remote, playerIp: '192.168.1.10'),
    );
    network.onCommand = (_) => NetworkProtocol.encodeState(
      const RemotePlayerState(
        stationIndex: 1,
        isPlaying: true,
        stationTitle: 'Icecast One',
        nowPlaying: 'Queen - Bohemian Rhapsody',
      ),
    );

    await controller.startForCurrentMode();
    await Future<void>.delayed(Duration.zero);

    expect(controller.chromeStationTitle, 'Icecast One');
    expect(controller.chromeNowPlaying, 'Queen - Bohemian Rhapsody');
    expect(controller.selectedStationIndex, 1);
  });
}
