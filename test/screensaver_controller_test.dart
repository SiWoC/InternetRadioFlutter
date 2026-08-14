import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/controllers/radio_controller.dart';
import 'package:internetradio/models/app_settings.dart';
import 'package:internetradio/models/radio_player_state.dart';
import 'package:internetradio/models/radio_station.dart';
import 'package:internetradio/services/network_protocol.dart';
import 'package:internetradio/services/network_service.dart';
import 'package:internetradio/services/radio_player_service.dart';
import 'package:internetradio/services/settings_repository.dart';
import 'package:internetradio/services/station_repository.dart';
import 'package:internetradio/services/wakelock_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePlayer implements RadioPlayer {
  final _stateController = StreamController<RadioPlayerState>.broadcast();
  RadioPlayerState _state = const RadioPlayerState();

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
    _state = RadioPlayerState(
      url: url,
      playbackState: PlaybackState.Ready,
      isPlaying: true,
    );
    _stateController.add(_state);
    return true;
  }

  @override
  Future<void> stop() async {
    _state = const RadioPlayerState();
    _stateController.add(_state);
  }

  @override
  Future<void> setMuted(bool value) async {
    _state = _state.copyWith(isMuted: value);
    _stateController.add(_state);
  }

  @override
  Future<void> toggleMute() => setMuted(!_state.isMuted);

  @override
  Future<void> refreshState() async {}

  @override
  void dispose() {
    _stateController.close();
  }
}

class _FakeNetwork extends NetworkService {
  NetworkCommandHandler? handler;

  @override
  Future<void> startListener({
    required NetworkCommandHandler onCommand,
    int port = NetworkProtocol.port,
  }) async {
    handler = onCommand;
  }

  @override
  Future<void> stopListener() async {
    handler = null;
  }

  @override
  Future<String?> sendCommand(
    String ipAddress,
    String command, {
    Duration timeout = NetworkProtocol.connectionTimeout,
    int port = NetworkProtocol.port,
  }) async {
    return null;
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

class _FakeWakelock implements ScreenWakelock {
  @override
  Future<void> setEnabled(bool value) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const idle = Duration(seconds: 60);

  late _FakeNetwork network;

  Future<RadioController> buildController({
    AppSettings? initial,
    Duration idleTimeout = idle,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final stations = StationRepository(const [
      RadioStation(name: 'A', url: 'https://a.example'),
      RadioStation(name: 'B', url: 'https://b.example'),
    ]);
    final settings = await SettingsRepository.load();
    if (initial != null) {
      await settings.save(initial);
    }
    network = _FakeNetwork();
    return RadioController(
      stations: stations,
      settings: settings,
      player: _FakePlayer(),
      network: network,
      wakelock: _FakeWakelock(),
      screensaverIdleTimeout: idleTimeout,
    );
  }

  RadioController pumpController(
    FakeAsync async, {
    AppSettings? initial,
  }) {
    RadioController? controller;
    buildController(initial: initial).then((c) => controller = c);
    async.flushMicrotasks();
    return controller!;
  }

  test('shows after idle timeout when Player + keepScreenOn', () {
    fakeAsync((async) {
      final controller = pumpController(async);
      addTearDown(controller.dispose);

      expect(controller.screensaver.isEligible, isTrue);
      expect(controller.screensaver.isVisible, isFalse);

      async.elapse(idle);
      expect(controller.screensaver.isVisible, isTrue);
    });
  });

  test('onUserActivity dismisses and restarts timer', () {
    fakeAsync((async) {
      final controller = pumpController(async);
      addTearDown(controller.dispose);

      async.elapse(idle);
      expect(controller.screensaver.isVisible, isTrue);

      controller.screensaver.onUserActivity();
      expect(controller.screensaver.isVisible, isFalse);

      async.elapse(const Duration(seconds: 59));
      expect(controller.screensaver.isVisible, isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(controller.screensaver.isVisible, isTrue);
    });
  });

  test('settings open suppresses screensaver', () {
    fakeAsync((async) {
      final controller = pumpController(async);
      addTearDown(controller.dispose);

      async.elapse(idle);
      expect(controller.screensaver.isVisible, isTrue);

      controller.openSettings();
      expect(controller.screensaver.isVisible, isFalse);

      async.elapse(idle);
      expect(controller.screensaver.isVisible, isFalse);

      controller.closeSettings();
      async.elapse(idle);
      expect(controller.screensaver.isVisible, isTrue);
    });
  });

  test('allowScreenOff never shows screensaver', () {
    fakeAsync((async) {
      final controller = pumpController(
        async,
        initial: const AppSettings(
          displayPolicy: DisplayPolicy.allowScreenOff,
        ),
      );
      addTearDown(controller.dispose);

      expect(controller.screensaver.isEligible, isFalse);
      async.elapse(idle);
      expect(controller.screensaver.isVisible, isFalse);
    });
  });

  test('Remote mode never shows screensaver', () {
    fakeAsync((async) {
      final controller = pumpController(
        async,
        initial: const AppSettings(
          mode: OperatingMode.remote,
          playerIp: '192.168.1.10',
        ),
      );
      addTearDown(controller.dispose);

      expect(controller.screensaver.isEligible, isFalse);
      async.elapse(idle);
      expect(controller.screensaver.isVisible, isFalse);
    });
  });

  test('mutating remote command dismisses screensaver', () {
    fakeAsync((async) {
      final controller = pumpController(async);
      addTearDown(controller.dispose);

      unawaited(controller.startPlayerListener());
      async.flushMicrotasks();

      async.elapse(idle);
      expect(controller.screensaver.isVisible, isTrue);

      network.handler!(const SelectStationCommand(0));
      async.flushMicrotasks();
      expect(controller.screensaver.isVisible, isFalse);
    });
  });

  test('PING and GET_STATE do not dismiss screensaver', () {
    fakeAsync((async) {
      final controller = pumpController(async);
      addTearDown(controller.dispose);

      unawaited(controller.startPlayerListener());
      async.flushMicrotasks();

      async.elapse(idle);
      expect(controller.screensaver.isVisible, isTrue);

      network.handler!(const PingCommand());
      async.flushMicrotasks();
      expect(controller.screensaver.isVisible, isTrue);

      network.handler!(const GetStateCommand());
      async.flushMicrotasks();
      expect(controller.screensaver.isVisible, isTrue);
    });
  });
}
