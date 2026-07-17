import 'package:internetradio/models/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists [AppSettings] via `shared_preferences`.
class SettingsRepository {
  SettingsRepository(this._prefs, AppSettings settings) : _settings = settings;

  static const _keyMode = 'settings.mode';
  static const _keyPlayerIp = 'settings.playerIp';
  static const _keyLastStationName = 'settings.lastStationName';
  static const _keyTestUrl = 'settings.testUrl';
  static const _keyDisplayPolicy = 'settings.displayPolicy';

  final SharedPreferences _prefs;
  AppSettings _settings;

  AppSettings get settings => _settings;

  /// Loads prefs and returns a repository with the restored [AppSettings].
  static Future<SettingsRepository> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsRepository(prefs, readFrom(prefs));
  }

  /// Writes [settings] and updates the in-memory snapshot.
  Future<void> save(AppSettings settings) async {
    _settings = settings;
    await _prefs.setString(_keyMode, settings.mode.name);
    await _prefs.setString(_keyPlayerIp, settings.playerIp);
    await _prefs.setString(_keyDisplayPolicy, settings.displayPolicy.name);

    if (settings.lastStationName == null) {
      await _prefs.remove(_keyLastStationName);
    } else {
      await _prefs.setString(_keyLastStationName, settings.lastStationName!);
    }

    if (settings.testUrl == null) {
      await _prefs.remove(_keyTestUrl);
    } else {
      await _prefs.setString(_keyTestUrl, settings.testUrl!);
    }
  }

  /// Reads [AppSettings] from an existing prefs instance (also used in tests).
  static AppSettings readFrom(SharedPreferences prefs) {
    return AppSettings(
      mode: _parseMode(prefs.getString(_keyMode)),
      playerIp: prefs.getString(_keyPlayerIp) ?? '',
      lastStationName: _emptyToNull(prefs.getString(_keyLastStationName)),
      testUrl: _emptyToNull(prefs.getString(_keyTestUrl)),
      displayPolicy: _parseDisplayPolicy(prefs.getString(_keyDisplayPolicy)),
    );
  }

  static OperatingMode _parseMode(String? raw) {
    return OperatingMode.values.asNameMap()[raw] ?? OperatingMode.player;
  }

  static DisplayPolicy _parseDisplayPolicy(String? raw) {
    return DisplayPolicy.values.asNameMap()[raw] ?? DisplayPolicy.keepScreenOn;
  }

  static String? _emptyToNull(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }
}
