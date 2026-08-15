import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:internetradio/models/app_settings.dart';
import 'package:internetradio/models/radio_player_state.dart';
import 'package:internetradio/models/radio_station.dart';
import 'package:internetradio/models/remote_player_state.dart';
import 'package:internetradio/services/network_protocol.dart';
import 'package:internetradio/services/network_service.dart';
import 'package:internetradio/services/radio_player_service.dart';
import 'package:internetradio/services/settings_repository.dart';
import 'package:internetradio/services/station_repository.dart';
import 'package:internetradio/controllers/screensaver_controller.dart';
import 'package:internetradio/services/wakelock_service.dart';

/// Orchestrates playback, station selection, settings, and Player/Remote mode.
class RadioController extends ChangeNotifier {
  RadioController({
    required StationRepository stations,
    required SettingsRepository settings,
    RadioPlayer? player,
    NetworkService? network,
    ScreenWakelock? wakelock,
    Future<void> Function()? exitApp,
    Duration screensaverIdleTimeout = const Duration(seconds: 60),
  })  : _stations = stations,
        _settings = settings,
        _player = player ?? RadioPlayerService(),
        _network = network ?? NetworkService(),
        _wakelock = wakelock ?? WakelockService(),
        _exitApp = exitApp ?? _popApp
  {
    _playerSubscription = _player.stateStream.listen((state) {
      _playerState = state;
      notifyListeners();
    });
    _playerState = _player.state;
    screensaver = ScreensaverController(
      radioController: this,
      idleTimeout: screensaverIdleTimeout,
    );
  }

  final StationRepository _stations;
  final SettingsRepository _settings;
  final RadioPlayer _player;
  final NetworkService _network;
  final ScreenWakelock _wakelock;
  final Future<void> Function() _exitApp;

  /// Idle timer / visibility for the bouncing-logo overlay (Player + keep on).
  late final ScreensaverController screensaver;

  StreamSubscription<RadioPlayerState>? _playerSubscription;
  Timer? _pollTimer;
  RadioPlayerState _playerState = const RadioPlayerState();
  RemotePlayerState? _polledState;
  int? _selectedStationIndex;
  bool _settingsOpen = false;
  String? _settingsMessage;
  bool _disposed = false;
  bool _remoteCommandInFlight = false;
  bool _modeSwitchInFlight = false;
  bool _playerUnreachable = false;

  StationRepository get stations => _stations;

  AppSettings get settings => _settings.settings;

  bool get isPlayerMode => settings.mode == OperatingMode.player;

  bool get isRemoteMode => settings.mode == OperatingMode.remote;

  /// Failed tap-to-switch `PING`; stays set until Remote mode is entered.
  bool get playerUnreachable => _playerUnreachable;

  /// True while [SettingsOverlay] is visible (screensaver must stay off).
  bool get isSettingsOpen => _settingsOpen;

  /// Banner shown when Settings opens (e.g. invalid player IP).
  String? get settingsMessage => _settingsMessage;

  RadioPlayerState get playerState => _playerState;

  /// Index of the selected station (local Player choice or last Remote poll).
  int? get selectedStationIndex => _selectedStationIndex;

  RadioStation? get selectedStation {
    final index = _selectedStationIndex;
    if (index == null) {
      return null;
    }
    return _stations.byIndex(index);
  }

  /// Effective control snapshot: local while Player, last poll while Remote.
  RemotePlayerState get remotePlayerState {
    if (isRemoteMode) {
      return _polledState ??
          RemotePlayerState(stationIndex: _selectedStationIndex ?? 0);
    }
    return RemotePlayerState(
      stationIndex: _selectedStationIndex ?? 0,
      isMuted: _playerState.isMuted,
      isPlaying: _playerState.isPlaying,
    );
  }

  bool get isMuted => remotePlayerState.isMuted;

  bool get isPlaying => remotePlayerState.isPlaying;

  /// Applies persisted [OperatingMode]: Player listens + restores; Remote polls.
  Future<void> startForCurrentMode() async {
    _assertNotDisposed();
    switch (_settings.settings.mode) {
      case OperatingMode.player:
        await _activatePlayerMode();
      case OperatingMode.remote:
        await _activateRemoteMode();
    }
  }

  /// Starts the Player TCP listener on [NetworkProtocol.port].
  Future<void> startPlayerListener() async {
    _assertNotDisposed();
    try {
      await _network.startListener(onCommand: _onNetworkCommand);
    } on Object catch (error, stack) {
      debugPrint('Player listener failed to start: $error\n$stack');
    }
  }

  Future<void> stopPlayerListener() async {
    _assertNotDisposed();
    await _network.stopListener();
  }

  /// Toggles Player ↔ Remote. Empty player IP opens Settings with a message.
  Future<void> toggleOperatingMode() async {
    _assertNotDisposed();
    if (_modeSwitchInFlight) {
      return;
    }
    _modeSwitchInFlight = true;
    try {
      if (isRemoteMode) {
        await enterPlayerMode();
      } else {
        await requestRemoteMode();
      }
    } finally {
      _modeSwitchInFlight = false;
    }
  }

  /// Enters Remote when the player IP is set and `PING` succeeds.
  ///
  /// Empty IP opens Settings. A failed ping stays in Player and sets
  /// [playerUnreachable] (red cross on the remote icon) until a later tap
  /// connects.
  Future<bool> requestRemoteMode() async {
    _assertNotDisposed();
    if (settings.playerIp.trim().isEmpty) {
      openSettings(message: 'Invalid Player IP-address');
      return false;
    }
    final reachable = await _network.ping(settings.playerIp);
    if (!reachable) {
      _playerUnreachable = true;
      notifyListeners();
      return false;
    }
    await enterRemoteMode();
    return true;
  }

  Future<void> enterRemoteMode() async {
    _assertNotDisposed();
    _playerUnreachable = false;
    await stopPlayerListener();
    await _player.stop();
    await _settings.save(
      _settings.settings.copyWith(mode: OperatingMode.remote),
    );
    await _activateRemoteMode();
    notifyListeners();
  }

  Future<void> enterPlayerMode() async {
    _assertNotDisposed();
    _stopRemotePoll();
    _polledState = null;
    await _settings.save(
      _settings.settings.copyWith(mode: OperatingMode.player),
    );
    await _activatePlayerMode();
    notifyListeners();
  }

  Future<void> _activatePlayerMode() async {
    await _applyDisplayPolicy();
    await startPlayerListener();
    await restoreLastStation();
  }

  Future<void> _activateRemoteMode() async {
    await _applyDisplayPolicy();
    _startRemotePoll();
  }

  /// Player + [DisplayPolicy.keepScreenOn] holds the screen; otherwise it may sleep.
  Future<void> _applyDisplayPolicy() async {
    final keepOn = isPlayerMode &&
        settings.displayPolicy == DisplayPolicy.keepScreenOn;
    await _wakelock.setEnabled(keepOn);
  }

  /// Resolves the stream URL, then applies it for the current mode.
  ///
  /// URL-test slot uses [AppSettings.testUrl] when set, otherwise the JSON URL.
  /// Player: plays locally. Remote: `TESTURL` for that slot (store+play on the
  /// Player), `SELECT_STATION|index` otherwise.
  Future<void> selectStation(int index) async {
    _assertNotDisposed();
    final station = _stations.byIndex(index);
    if (station == null) {
      return;
    }

    final isUrlTest = _stations.isUrlTestIndex(index);
    final url = _streamUrlFor(station, isUrlTest: isUrlTest);

    _selectedStationIndex = index;
    if (isRemoteMode && _polledState != null) {
      _polledState = _polledState!.copyWith(stationIndex: index);
    }
    notifyListeners();

    if (isRemoteMode) {
      final command = isUrlTest
          ? NetworkProtocol.testUrl(url)
          : NetworkProtocol.selectStation(index);
      await _sendToPlayer(command);
      return;
    }

    await _settings.save(
      _settings.settings.copyWith(lastStationName: station.name),
    );
    await _player.play(url, title: station.name);
  }

  Future<void> stop() async {
    _assertNotDisposed();
    if (isRemoteMode) {
      return;
    }
    await _player.stop();
  }

  /// Remote: sends `EXIT` so the Player stops audio and closes. No-op in Player mode.
  Future<void> exitRemotePlayer() async {
    _assertNotDisposed();
    if (!isRemoteMode) {
      return;
    }
    await _sendToPlayer(NetworkProtocol.exit);
  }

  Future<void> toggleMute() async {
    _assertNotDisposed();
    await setMuted(!isMuted);
  }

  /// Player: local mute. Remote: sends `MUTE` / `UNMUTE`.
  Future<void> setMuted(bool muted) async {
    _assertNotDisposed();
    if (isRemoteMode) {
      final command = muted ? NetworkProtocol.mute : NetworkProtocol.unmute;
      _polledState = remotePlayerState.copyWith(isMuted: muted);
      notifyListeners();
      await _sendToPlayer(command);
      return;
    }
    await _player.setMuted(muted);
  }

  /// Plays [testUrl] on the URL-test slot and persists it as [AppSettings.testUrl].
  ///
  /// Player: local play. Remote: sends `TESTURL|url`.
  Future<void> playTestUrl(String testUrl) async {
    _assertNotDisposed();
    testUrl = testUrl.trim();
    if (testUrl.isEmpty || _stations.length == 0) {
      return;
    }
    final index = _stations.length - 1;
    final station = _stations.byIndex(index);
    _selectedStationIndex = index;
    notifyListeners();

    await _settings.save(
      _settings.settings.copyWith(
        testUrl: testUrl,
        lastStationName: station?.name,
      ),
    );

    if (isRemoteMode) {
      if (_polledState != null) {
        _polledState = _polledState!.copyWith(stationIndex: index);
      }
      await _sendToPlayer(NetworkProtocol.testUrl(testUrl));
      return;
    }

    await _player.play(testUrl, title: station?.name);
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

  void openSettings({String? message}) {
    _assertNotDisposed();
    _settingsMessage = message;
    _settingsOpen = true;
    notifyListeners();
  }

  void closeSettings() {
    _assertNotDisposed();
    if (!_settingsOpen && _settingsMessage == null) {
      return;
    }
    _settingsOpen = false;
    _settingsMessage = null;
    notifyListeners();
  }

  /// Persists [playerIp] (empty allowed). Does not close settings.
  Future<void> savePlayerIp(String playerIp) async {
    _assertNotDisposed();
    await _settings.save(
      _settings.settings.copyWith(playerIp: playerIp),
    );
    notifyListeners();
  }

  /// Persists player IP and test URL (empty URL clears the stored value).
  Future<void> saveSettings({
    required String playerIp,
    required String testUrl,
  }) async {
    _assertNotDisposed();
    testUrl = testUrl.trim();
    final current = _settings.settings;
    await _settings.save(
      AppSettings(
        mode: current.mode,
        playerIp: playerIp,
        lastStationName: current.lastStationName,
        testUrl: testUrl.isEmpty ? null : testUrl,
        displayPolicy: current.displayPolicy,
      ),
    );
    notifyListeners();
  }

  /// Persists [policy] and applies wakelock for the current mode.
  Future<void> setDisplayPolicy(DisplayPolicy policy) async {
    _assertNotDisposed();
    await _settings.save(
      _settings.settings.copyWith(displayPolicy: policy),
    );
    await _applyDisplayPolicy();
    notifyListeners();
  }

  /// TCP `PING`/`PONG` probe used by Settings → Test Connection.
  Future<bool> testPlayerConnection(String ipAddress) async {
    _assertNotDisposed();
    return _network.ping(ipAddress);
  }

  /// JSON stream URL, or [AppSettings.testUrl] when the URL-test slot has one stored.
  String _streamUrlFor(RadioStation station, {required bool isUrlTest}) {
    if (isUrlTest) {
      final override = _settings.settings.testUrl?.trim();
      if (override != null && override.isNotEmpty) {
        return override;
      }
    }
    return station.url;
  }

  Future<String?> _sendToPlayer(String command) async {
    final ip = settings.playerIp.trim();
    if (ip.isEmpty) {
      return null;
    }
    _remoteCommandInFlight = true;
    try {
      return await _network.sendCommand(ip, command);
    } finally {
      _remoteCommandInFlight = false;
    }
  }

  void _startRemotePoll() {
    _stopRemotePoll();
    unawaited(_pollPlayerState());
    _pollTimer = Timer.periodic(NetworkProtocol.pollInterval, (_) {
      unawaited(_pollPlayerState());
    });
  }

  void _stopRemotePoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollPlayerState() async {
    if (_disposed || !isRemoteMode || _remoteCommandInFlight) {
      return;
    }
    final ip = settings.playerIp.trim();
    if (ip.isEmpty) {
      return;
    }

    final reply = await _network.sendCommand(ip, NetworkProtocol.getState);
    final state = NetworkProtocol.parseState(reply);
    if (state == null || _disposed || !isRemoteMode) {
      return;
    }

    _polledState = state;
    _selectedStationIndex = state.stationIndex;
    notifyListeners();
  }

  FutureOr<String> _onNetworkCommand(NetworkCommand command) async {
    switch (command) {
      case PingCommand():
        return NetworkProtocol.pong;
      case SelectStationCommand(:final index):
        _onMutatingRemoteCommand();
        await selectStation(index);
        return NetworkProtocol.ok;
      case MuteCommand():
        _onMutatingRemoteCommand();
        await setMuted(true);
        return NetworkProtocol.ok;
      case UnmuteCommand():
        _onMutatingRemoteCommand();
        await setMuted(false);
        return NetworkProtocol.ok;
      case ExitCommand():
        await stop(); // stop the player over method channel on the Kotlin side
        unawaited(Future<void>.delayed(Duration.zero, _exitApp)); // exit the app, which will exit on all layers
        return NetworkProtocol.ok;
      case TestUrlCommand(:final url):
        _onMutatingRemoteCommand();
        await playTestUrl(url);
        return NetworkProtocol.ok;
      case GetStateCommand():
        return NetworkProtocol.encodeState(remotePlayerState);
      case InvalidCommand(:final message):
        return NetworkProtocol.error(message);
    }
  }

  /// Screensaver dismiss + optional display wake when the screen may be off.
  void _onMutatingRemoteCommand() {
    screensaver.onRemoteCommand();
    if (settings.displayPolicy == DisplayPolicy.allowScreenOff) {
      unawaited(_player.wakeDisplay());
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    screensaver.dispose();
    _stopRemotePoll();
    _playerSubscription?.cancel();
    unawaited(_network.stopListener());
    unawaited(_wakelock.setEnabled(false));
    _player.dispose();
    super.dispose();
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('RadioController has been disposed');
    }
  }

  static Future<void> _popApp() async {
    await SystemNavigator.pop();
  }
}
