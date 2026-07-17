/// Player device (plays audio + may accept TCP) or remote control client.
enum OperatingMode {
  player,
  remote,
}

/// Player-mode display behaviour while audio may continue in the background.
enum DisplayPolicy {
  /// Keep screen on; screensaver may run after idle.
  keepScreenOn,

  /// Allow the screen to sleep; audio continues via the playback service.
  allowScreenOff,
}

/// User preferences persisted across sessions.
class AppSettings {
  const AppSettings({
    this.mode = OperatingMode.player,
    this.playerIp = '',
    this.lastStationName,
    this.testUrl,
    this.displayPolicy = DisplayPolicy.keepScreenOn,
  });

  final OperatingMode mode;

  /// IP of the Player device when this device is in [OperatingMode.remote].
  final String playerIp;

  final String? lastStationName;
  final String? testUrl;
  final DisplayPolicy displayPolicy;

  AppSettings copyWith({
    OperatingMode? mode,
    String? playerIp,
    String? lastStationName,
    String? testUrl,
    DisplayPolicy? displayPolicy,
  }) {
    return AppSettings(
      mode: mode ?? this.mode,
      playerIp: playerIp ?? this.playerIp,
      lastStationName: lastStationName ?? this.lastStationName,
      testUrl: testUrl ?? this.testUrl,
      displayPolicy: displayPolicy ?? this.displayPolicy,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppSettings &&
        other.mode == mode &&
        other.playerIp == playerIp &&
        other.lastStationName == lastStationName &&
        other.testUrl == testUrl &&
        other.displayPolicy == displayPolicy;
  }

  @override
  int get hashCode => Object.hash(
        mode,
        playerIp,
        lastStationName,
        testUrl,
        displayPolicy,
      );
}
