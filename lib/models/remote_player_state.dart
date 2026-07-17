/// Snapshot of the Player as reported to a Remote client (TCP `STATE|…`).
class RemotePlayerState {
  const RemotePlayerState({
    required this.stationIndex,
    this.isMuted = false,
    this.isPlaying = false,
  });

  final int stationIndex;
  final bool isMuted;
  final bool isPlaying;

  RemotePlayerState copyWith({
    int? stationIndex,
    bool? isMuted,
    bool? isPlaying,
  }) {
    return RemotePlayerState(
      stationIndex: stationIndex ?? this.stationIndex,
      isMuted: isMuted ?? this.isMuted,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RemotePlayerState &&
        other.stationIndex == stationIndex &&
        other.isMuted == isMuted &&
        other.isPlaying == isPlaying;
  }

  @override
  int get hashCode => Object.hash(stationIndex, isMuted, isPlaying);
}
