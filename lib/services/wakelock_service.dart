import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on or lets it sleep.
abstract interface class ScreenWakelock {
  Future<void> setEnabled(bool enabled);
}

/// [ScreenWakelock] backed by `wakelock_plus`.
class WakelockService implements ScreenWakelock {
  @override
  Future<void> setEnabled(bool enabled) {
    return WakelockPlus.toggle(enable: enabled);
  }
}
