/// Snapshot of the Player as reported to a Remote client (TCP `STATE|…`).
class RemotePlayerState {
  const RemotePlayerState({
    required this.stationIndex,
    this.isMuted = false,
    this.isPlaying = false,
    this.stationTitle,
    this.nowPlaying,
  });

  final int stationIndex;
  final bool isMuted;
  final bool isPlaying;

  /// Chrome station line from the Player (`streamStationName` or config name).
  final String? stationTitle;

  /// Chrome now-playing line from the Player (`Artist - Title` or ICY StreamTitle).
  final String? nowPlaying;

  RemotePlayerState copyWith({
    int? stationIndex,
    bool? isMuted,
    bool? isPlaying,
    String? stationTitle,
    String? nowPlaying,
  }) {
    return RemotePlayerState(
      stationIndex: stationIndex ?? this.stationIndex,
      isMuted: isMuted ?? this.isMuted,
      isPlaying: isPlaying ?? this.isPlaying,
      stationTitle: stationTitle ?? this.stationTitle,
      nowPlaying: nowPlaying ?? this.nowPlaying,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RemotePlayerState &&
        other.stationIndex == stationIndex &&
        other.isMuted == isMuted &&
        other.isPlaying == isPlaying &&
        other.stationTitle == stationTitle &&
        other.nowPlaying == nowPlaying;
  }

  @override
  int get hashCode => Object.hash(
        stationIndex,
        isMuted,
        isPlaying,
        stationTitle,
        nowPlaying,
      );
}
