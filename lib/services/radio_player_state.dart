/// ExoPlayer playback phase reported by native code.
enum PlaybackState {
  Idle,
  Buffering,
  Ready,
  Ended,
  Unknown,
}

/// Playback state reported by the native Media3 player.
///
/// Channel map fields (MethodChannel `getState` / EventChannel updates):
/// - `url` — current stream URL, or null when stopped
/// - `playbackState` — [PlaybackState] name (`Idle` | `Buffering` | `Ready` | `Ended` | `Unknown`)
/// - `isPlaying` — ExoPlayer isPlaying
/// - `isMuted` — output muted (stream may still be connected)
/// - `error` — last player error message, or null
/// - `bufferedPositionMs` / `totalBufferedDurationMs` — buffer metrics
///
/// Call results such as `play()`'s started bool are **not** part of this map.
class RadioPlayerState {
  const RadioPlayerState({
    this.url,
    this.playbackState = PlaybackState.Idle,
    this.isPlaying = false,
    this.isMuted = false,
    this.error,
    this.bufferedPositionMs = 0,
    this.totalBufferedDurationMs = 0,
  });

  final String? url;
  final PlaybackState playbackState;
  final bool isPlaying;
  final bool isMuted;
  final String? error;
  final int bufferedPositionMs;
  final int totalBufferedDurationMs;

  factory RadioPlayerState.fromMap(Map<dynamic, dynamic> map) {
    return RadioPlayerState(
      url: map['url'] as String?,
      playbackState: _parsePlaybackState(map['playbackState'] as String?),
      isPlaying: map['isPlaying'] as bool? ?? false,
      isMuted: map['isMuted'] as bool? ?? false,
      error: map['error'] as String?,
      bufferedPositionMs: map['bufferedPositionMs'] as int? ?? 0,
      totalBufferedDurationMs: map['totalBufferedDurationMs'] as int? ?? 0,
    );
  }

  bool get hasActiveStream => url != null && playbackState != PlaybackState.Idle;

  String get statusLabel {
    if (error != null) {
      return 'Error: $error';
    }
    if (isPlaying) {
      return isMuted ? 'Playing (muted)' : 'Playing';
    }
    return playbackState.name;
  }

  RadioPlayerState copyWith({
    String? url,
    PlaybackState? playbackState,
    bool? isPlaying,
    bool? isMuted,
    String? error,
    int? bufferedPositionMs,
    int? totalBufferedDurationMs,
  }) {
    return RadioPlayerState(
      url: url ?? this.url,
      playbackState: playbackState ?? this.playbackState,
      isPlaying: isPlaying ?? this.isPlaying,
      isMuted: isMuted ?? this.isMuted,
      error: error ?? this.error,
      bufferedPositionMs: bufferedPositionMs ?? this.bufferedPositionMs,
      totalBufferedDurationMs:
          totalBufferedDurationMs ?? this.totalBufferedDurationMs,
    );
  }

  static PlaybackState _parsePlaybackState(String? raw) {
    if (raw == null || raw.isEmpty) {
      return PlaybackState.Idle;
    }
    return PlaybackState.values.asNameMap()[raw] ?? PlaybackState.Unknown;
  }
}
