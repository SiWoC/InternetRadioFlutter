import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:internetradio/controllers/radio_controller.dart';
import 'package:internetradio/models/app_settings.dart';

/// 60s inactivity timer and screensaver visibility for Player + keep-screen-on.
///
/// Resets on local touch ([onUserActivity]) and on mutating remote commands
/// ([onRemoteCommand]). Stays off while Settings or Yamaha overlay is visible,
/// or display may sleep.
class ScreensaverController extends ChangeNotifier {
  ScreensaverController({
    required RadioController radioController,
    this.idleTimeout = const Duration(seconds: 60),
  }) : _radioController = radioController {
    _radioController.addListener(_onRadioChanged);
    _syncEligibility();
  }

  final RadioController _radioController;

  /// Idle time before the overlay appears when [isEligible].
  final Duration idleTimeout;

  Timer? _timer;
  bool _visible = false;
  bool _disposed = false;

  /// True while the full-screen bouncing logo should be shown.
  bool get isVisible => _visible;

  /// Player mode, keep screen on, and Settings/Yamaha overlays closed.
  bool get isEligible =>
      _radioController.isPlayerMode &&
      _radioController.settings.displayPolicy == DisplayPolicy.keepScreenOn &&
      !_radioController.isSettingsOpen &&
      !_radioController.isYamahaOpen;

  /// Local touch: dismiss if showing, then restart the idle timer when eligible.
  void onUserActivity() {
    if (_disposed) {
      return;
    }
    _hideIfVisible();
    _restartTimerIfEligible();
  }

  /// Mutating remote TCP command on the Player: same as user activity.
  void onRemoteCommand() => onUserActivity();

  /// Hides the overlay without restarting the timer (e.g. becoming ineligible).
  void dismiss() {
    if (_disposed) {
      return;
    }
    _hideIfVisible();
  }

  void _onRadioChanged() {
    if (_disposed) {
      return;
    }
    _syncEligibility();
  }

  void _syncEligibility() {
    if (!isEligible) {
      _cancelTimer();
      _hideIfVisible();
      return;
    }
    if (!_visible && _timer == null) {
      _startTimer();
    }
  }

  void _restartTimerIfEligible() {
    _cancelTimer();
    if (isEligible && !_visible) {
      _startTimer();
    }
  }

  void _startTimer() {
    _cancelTimer();
    _timer = Timer(idleTimeout, _onIdleTimeout);
  }

  void _onIdleTimeout() {
    _timer = null;
    if (_disposed || !isEligible || _visible) {
      return;
    }
    _visible = true;
    notifyListeners();
  }

  void _hideIfVisible() {
    if (!_visible) {
      return;
    }
    _visible = false;
    notifyListeners();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _cancelTimer();
    _radioController.removeListener(_onRadioChanged);
    super.dispose();
  }
}
