import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:internetradio/models/app_settings.dart';
import 'package:internetradio/models/radio_player_state.dart';
import 'package:internetradio/models/radio_station.dart';
import 'package:internetradio/models/remote_player_state.dart';
import 'package:internetradio/services/network_protocol.dart';
import 'package:internetradio/services/network_service.dart';
import 'package:internetradio/services/radio_player_service.dart';
import 'package:internetradio/services/settings_repository.dart';
import 'package:internetradio/services/station_repository.dart';

/// Orchestrates playback, station selection, settings, and Player/Remote mode.
class RadioController extends ChangeNotifier {
  RadioController({
    required StationRepository stations,
    required SettingsRepository settings,
    RadioPlayer? player,
    NetworkService? network,
  })  : _stations = stations,
        _settings = settings,
        _player = player ?? RadioPlayerService(),
        _network = network ?? NetworkService()
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
  final NetworkService _network;

  StreamSubscription<RadioPlayerState>? _playerSubscription;
  Timer? _pollTimer;
  RadioPlayerState _playerState = const RadioPlayerState();
  RemotePlayerState? _polledState;
  int? _selectedStationIndex;
  bool _settingsOpen = false;
  String? _settingsMessage;
  bool _disposed = false;
  bool _remoteCommandInFlight = false;

  StationRepository get stations => _stations;

  AppSettings get settings => _settings.settings;

  bool get isPlayerMode => settings.mode == OperatingMode.player;

  bool get isRemoteMode => settings.mode == OperatingMode.remote;

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
        _activateRemoteMode();
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
    if (isRemoteMode) {
      await enterPlayerMode();
    } else {
      await requestRemoteMode();
    }
  }

  /// Enters Remote when [AppSettings.playerIp] is set; otherwise opens Settings.
  Future<bool> requestRemoteMode() async {
    _assertNotDisposed();
    if (settings.playerIp.trim().isEmpty) {
      openSettings(message: 'Invalid Player IP-address');
      return false;
    }
    await enterRemoteMode();
    return true;
  }

  Future<void> enterRemoteMode() async {
    _assertNotDisposed();
    await stopPlayerListener();
    await _player.stop();
    await _settings.save(
      _settings.settings.copyWith(mode: OperatingMode.remote),
    );
    _activateRemoteMode();
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
    await startPlayerListener();
    await restoreLastStation();
  }

  void _activateRemoteMode() {
    _startRemotePoll();
  }

  /// Player: plays locally. Remote: sends `SELECT_STATION|index`.
  Future<void> selectStation(int index) async {
    _assertNotDisposed();
    final station = _stations.byIndex(index);
    if (station == null) {
      return;
    }

    if (isRemoteMode) {
      await _remoteSelectStation(index);
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
    if (isRemoteMode) {
      return;
    }
    await _player.stop();
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

  /// Plays [url] on the URL-test slot and persists it as [AppSettings.testUrl].
  Future<void> playTestUrl(String url) async {
    _assertNotDisposed();
    if (_stations.length == 0) {
      return;
    }
    final index = _stations.length - 1;
    _selectedStationIndex = index;
    notifyListeners();

    await _settings.save(
      _settings.settings.copyWith(testUrl: url),
    );
    await _player.play(url);
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

  /// TCP `PING`/`PONG` probe used by Settings → Test Connection.
  Future<bool> testPlayerConnection(String ipAddress) async {
    _assertNotDisposed();
    return _network.ping(ipAddress);
  }

  Future<void> _remoteSelectStation(int index) async {
    _selectedStationIndex = index;
    if (_polledState != null) {
      _polledState = _polledState!.copyWith(stationIndex: index);
    }
    notifyListeners();
    await _sendToPlayer(NetworkProtocol.selectStation(index));
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
        await selectStation(index);
        return NetworkProtocol.ok;
      case MuteCommand():
        await setMuted(true);
        return NetworkProtocol.ok;
      case UnmuteCommand():
        await setMuted(false);
        return NetworkProtocol.ok;
      case TestUrlCommand(:final url):
        await playTestUrl(url);
        return NetworkProtocol.ok;
      case GetStateCommand():
        return NetworkProtocol.encodeState(remotePlayerState);
      case InvalidCommand(:final message):
        return NetworkProtocol.error(message);
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _stopRemotePoll();
    _playerSubscription?.cancel();
    unawaited(_network.stopListener());
    _player.dispose();
    super.dispose();
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('RadioController has been disposed');
    }
  }
}
