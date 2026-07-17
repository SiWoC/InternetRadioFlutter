import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/models/app_settings.dart';
import 'package:internetradio/services/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('load returns defaults when prefs are empty', () async {
    final repo = await SettingsRepository.load();

    expect(repo.settings, const AppSettings());
  });

  test('save then load restores all fields', () async {
    final repo = await SettingsRepository.load();
    const updated = AppSettings(
      mode: OperatingMode.remote,
      playerIp: '192.168.1.10',
      lastStationName: 'Q-Music',
      testUrl: 'https://example.com/stream',
      displayPolicy: DisplayPolicy.allowScreenOff,
    );

    await repo.save(updated);

    final reloaded = await SettingsRepository.load();
    expect(reloaded.settings, updated);
  });

  test('save clears optional fields when null', () async {
    SharedPreferences.setMockInitialValues({
      'settings.mode': 'player',
      'settings.playerIp': '',
      'settings.lastStationName': 'Kink',
      'settings.testUrl': 'https://old.example',
      'settings.displayPolicy': 'keepScreenOn',
    });

    final repo = await SettingsRepository.load();
    await repo.save(const AppSettings());

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('settings.lastStationName'), isFalse);
    expect(prefs.containsKey('settings.testUrl'), isFalse);
    expect(repo.settings.lastStationName, isNull);
    expect(repo.settings.testUrl, isNull);
  });
}
