import 'dart:async';

import 'package:flutter/services.dart';
import 'package:internetradio/services/radio_player_state.dart';

export 'radio_player_state.dart';

/// Playback API used by [RadioController] (native or test double).
abstract interface class RadioPlayer {
  RadioPlayerState get state;
  Stream<RadioPlayerState> get stateStream;
  Future<bool> play(String url, {bool applyAudioRouteFix = true});
  Future<void> stop();
  Future<void> setMuted(bool muted);
  Future<void> toggleMute();
  Future<void> refreshState();
  void dispose();
}

/// Dart facade for the native Media3 radio player (Android).
class RadioPlayerService implements RadioPlayer {
  RadioPlayerService() {
    _eventSubscription = _events.receiveBroadcastStream().listen(
      (event) {
        if (_disposed) {
          return;
        }
        if (event is Map) {
          _updateState(RadioPlayerState.fromMap(event));
        }
      },
      onError: (Object error) {
        if (_disposed) {
          return;
        }
        _updateState(
          _lastState.copyWith(
            error: error.toString(),
            isPlaying: false,
          ),
        );
      },
    );
  }

  static const _methods = MethodChannel('nl.siwoc.internetradio/radio_player');
  static const _events = EventChannel('nl.siwoc.internetradio/radio_player_events');

  final _stateController = StreamController<RadioPlayerState>.broadcast();
  StreamSubscription<dynamic>? _eventSubscription;
  RadioPlayerState _lastState = const RadioPlayerState();
  bool _disposed = false;

  /// Latest state from native events or method calls.
  RadioPlayerState get state => _lastState;

  Stream<RadioPlayerState> get stateStream => _stateController.stream;

  /// Starts [url].
  ///
  /// Returns `true` when a stream was (re)started, `false` when [url] was
  /// already active (noop). Failures throw or appear on [RadioPlayerState.error].
  Future<bool> play(
    String url, {
    bool applyAudioRouteFix = true,
  }) async {
    _assertNotDisposed();
    final started = await _methods.invokeMethod<bool>('play', {
      'url': url,
      'applyAudioRouteFix': applyAudioRouteFix,
    }) ?? true;
    await refreshState();
    return started;
  }

  Future<void> stop() async {
    _assertNotDisposed();
    final result = await _methods.invokeMethod<Map<dynamic, dynamic>>('stop');
    _updateState(RadioPlayerState.fromMap(result ?? {}));
  }

  Future<void> setMuted(bool muted) async {
    _assertNotDisposed();
    final result = await _methods.invokeMethod<Map<dynamic, dynamic>>('setMuted', {
      'muted': muted,
    });
    _updateState(RadioPlayerState.fromMap(result ?? {}));
  }

  Future<void> toggleMute() {
    return setMuted(!_lastState.isMuted);
  }

  Future<void> refreshState() async {
    _assertNotDisposed();
    final result = await _methods.invokeMethod<Map<dynamic, dynamic>>('getState');
    _updateState(RadioPlayerState.fromMap(result ?? {}));
  }

  Future<void> retriggerAudioRouting() {
    _assertNotDisposed();
    return _methods.invokeMethod<void>('retriggerAudioRouting');
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _eventSubscription?.cancel();
    _stateController.close();
  }

  void _updateState(RadioPlayerState state) {
    _lastState = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('RadioPlayerService has been disposed');
    }
  }
}
