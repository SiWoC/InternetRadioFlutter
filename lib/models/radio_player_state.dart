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
/// - `retryInSeconds` — countdown until next auto-retry, or null when not retrying
/// - `bufferedPositionMs` / `totalBufferedDurationMs` — buffer metrics
/// - `streamStationName` — ICY `icy-name` / MediaMetadata.station when the stream sends it
/// - `nowPlaying` — current track line (`Artist - Title` or ICY StreamTitle)
///
/// Call results such as `play()`'s started bool are **not** part of this map.
class RadioPlayerState {
  const RadioPlayerState({
    this.url,
    this.playbackState = PlaybackState.Idle,
    this.isPlaying = false,
    this.isMuted = false,
    this.error,
    this.retryInSeconds,
    this.bufferedPositionMs = 0,
    this.totalBufferedDurationMs = 0,
    this.streamStationName,
    this.nowPlaying,
  });

  final String? url;
  final PlaybackState playbackState;
  final bool isPlaying;
  final bool isMuted;
  final String? error;
  final int? retryInSeconds;
  final int bufferedPositionMs;
  final int totalBufferedDurationMs;

  /// Station name from the stream (ICY `icy-name`), when present.
  final String? streamStationName;

  /// Now-playing line from the stream (ICY StreamTitle or artist + title).
  final String? nowPlaying;

  factory RadioPlayerState.fromMap(Map<dynamic, dynamic> map) {
    return RadioPlayerState(
      url: map['url'] as String?,
      playbackState: _parsePlaybackState(map['playbackState'] as String?),
      isPlaying: map['isPlaying'] as bool? ?? false,
      isMuted: map['isMuted'] as bool? ?? false,
      error: map['error'] as String?,
      retryInSeconds: map['retryInSeconds'] as int?,
      bufferedPositionMs: map['bufferedPositionMs'] as int? ?? 0,
      totalBufferedDurationMs: map['totalBufferedDurationMs'] as int? ?? 0,
      streamStationName: map['streamStationName'] as String?,
      nowPlaying: map['nowPlaying'] as String?,
    );
  }

  bool get hasActiveStream => url != null && playbackState != PlaybackState.Idle;

  String get statusLabel {
    if (retryInSeconds != null) {
      return 'Retry in ${retryInSeconds}s';
    }
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
    int? retryInSeconds,
    int? bufferedPositionMs,
    int? totalBufferedDurationMs,
    String? streamStationName,
    String? nowPlaying,
  }) {
    return RadioPlayerState(
      url: url ?? this.url,
      playbackState: playbackState ?? this.playbackState,
      isPlaying: isPlaying ?? this.isPlaying,
      isMuted: isMuted ?? this.isMuted,
      error: error ?? this.error,
      retryInSeconds: retryInSeconds ?? this.retryInSeconds,
      bufferedPositionMs: bufferedPositionMs ?? this.bufferedPositionMs,
      totalBufferedDurationMs:
          totalBufferedDurationMs ?? this.totalBufferedDurationMs,
      streamStationName: streamStationName ?? this.streamStationName,
      nowPlaying: nowPlaying ?? this.nowPlaying,
    );
  }

  static PlaybackState _parsePlaybackState(String? raw) {
    if (raw == null || raw.isEmpty) {
      return PlaybackState.Idle;
    }
    return PlaybackState.values.asNameMap()[raw] ?? PlaybackState.Unknown;
  }
}
