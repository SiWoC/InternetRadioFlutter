import 'package:internetradio/models/remote_player_state.dart';

/// TCP command / response string helpers for the radio LAN protocol.
abstract final class NetworkProtocol {
  static const int port = 6435;

  static const Duration connectionTimeout = Duration(seconds: 2);

  /// How often a Remote client polls `GET_STATE`.
  static const Duration pollInterval = Duration(milliseconds: 2500);

  static const String ping = 'PING';
  static const String pong = 'PONG';
  static const String mute = 'MUTE';
  static const String unmute = 'UNMUTE';
  static const String exit = 'EXIT';
  static const String getState = 'GET_STATE';
  static const String ok = 'OK';

  static const String _selectStationPrefix = 'SELECT_STATION|';
  static const String _testUrlPrefix = 'TESTURL|';
  static const String _statePrefix = 'STATE|';

  static String selectStation(int index) => '$_selectStationPrefix$index';

  static String testUrl(String url) => '$_testUrlPrefix$url';

  static String error(String message) => 'ERROR:$message';

  static bool isPong(String? response) => response?.trim() == pong;

  static bool isOk(String? response) => response?.trim() == ok;

  /// Wire format: `STATE|stationIndex|muted|playing|stationTitle|nowPlaying`
  /// with muted/playing as `0`/`1`. Titles are percent-encoded so `|` is safe.
  static String encodeState(RemotePlayerState state) {
    final muted = state.isMuted ? '1' : '0';
    final playing = state.isPlaying ? '1' : '0';
    final stationTitle = Uri.encodeComponent(state.stationTitle ?? '');
    final nowPlaying = Uri.encodeComponent(state.nowPlaying ?? '');
    return '$_statePrefix${state.stationIndex}|$muted|$playing|'
        '$stationTitle|$nowPlaying';
  }

  static RemotePlayerState? parseState(String? line) {
    if (line == null) {
      return null;
    }
    final parts = line.trim().split('|');
    if (parts.length != 6 || parts[0] != 'STATE') {
      return null;
    }
    final index = int.tryParse(parts[1]);
    final muted = _parseFlag(parts[2]);
    final playing = _parseFlag(parts[3]);
    if (index == null || muted == null || playing == null) {
      return null;
    }
    return RemotePlayerState(
      stationIndex: index,
      isMuted: muted,
      isPlaying: playing,
      stationTitle: _decodeStateField(parts[4]),
      nowPlaying: _decodeStateField(parts[5]),
    );
  }

  /// Parses one inbound request line from a Remote client.
  static NetworkCommand parseCommand(String line) {
    final command = line.trim();
    if (command.isEmpty) {
      return const InvalidCommand('Empty command');
    }
    if (command == ping) {
      return const PingCommand();
    }
    if (command == mute) {
      return const MuteCommand();
    }
    if (command == unmute) {
      return const UnmuteCommand();
    }
    if (command == exit) {
      return const ExitCommand();
    }
    if (command == getState) {
      return const GetStateCommand();
    }
    if (command.startsWith(_selectStationPrefix)) {
      final raw = command.substring(_selectStationPrefix.length);
      final index = int.tryParse(raw);
      if (index == null) {
        return const InvalidCommand('Invalid station index');
      }
      return SelectStationCommand(index);
    }
    if (command.startsWith(_testUrlPrefix)) {
      final url = command.substring(_testUrlPrefix.length);
      if (url.isEmpty) {
        return const InvalidCommand('Invalid test URL');
      }
      return TestUrlCommand(url);
    }
    return const InvalidCommand('Unknown command');
  }

  static bool? _parseFlag(String raw) {
    if (raw == '0') {
      return false;
    }
    if (raw == '1') {
      return true;
    }
    return null;
  }

  static String? _decodeStateField(String raw) {
    if (raw.isEmpty) {
      return null;
    }
    try {
      final decoded = Uri.decodeComponent(raw).trim();
      return decoded.isEmpty ? null : decoded;
    } on FormatException {
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
  }
}

/// One parsed inbound TCP command.
sealed class NetworkCommand {
  const NetworkCommand();
}

final class PingCommand extends NetworkCommand {
  const PingCommand();
}

final class SelectStationCommand extends NetworkCommand {
  const SelectStationCommand(this.index);
  final int index;
}

final class MuteCommand extends NetworkCommand {
  const MuteCommand();
}

final class UnmuteCommand extends NetworkCommand {
  const UnmuteCommand();
}

final class ExitCommand extends NetworkCommand {
  const ExitCommand();
}

final class GetStateCommand extends NetworkCommand {
  const GetStateCommand();
}

final class TestUrlCommand extends NetworkCommand {
  const TestUrlCommand(this.url);
  final String url;
}

final class InvalidCommand extends NetworkCommand {
  const InvalidCommand(this.message);
  final String message;
}
