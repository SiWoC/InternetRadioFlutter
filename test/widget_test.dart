import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/controllers/radio_controller.dart';
import 'package:internetradio/main.dart';
import 'package:internetradio/models/radio_station.dart';
import 'package:internetradio/services/radio_player_service.dart';
import 'package:internetradio/services/settings_repository.dart';
import 'package:internetradio/services/station_repository.dart';
import 'package:internetradio/widgets/station_grid.dart';
import 'package:internetradio/widgets/station_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentPlayer implements RadioPlayer {
  @override
  RadioPlayerState get state => const RadioPlayerState();

  @override
  Stream<RadioPlayerState> get stateStream => const Stream.empty();

  @override
  Future<bool> play(String url, {bool applyAudioRouteFix = true}) async => true;

  @override
  Future<void> stop() async {}

  @override
  Future<void> setMuted(bool muted) async {}

  @override
  Future<void> toggleMute() async {}

  @override
  Future<void> refreshState() async {}

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<RadioController> buildController() async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsRepository.load();
    return RadioController(
      stations: StationRepository(const [
        RadioStation(
          name: 'All Time Top 40 hits',
          url: 'https://a.example',
          imageAssetPath: 'assets/images/alltimehits.png',
        ),
        RadioStation(
          name: 'ABC Triple J NSW',
          url: 'https://triplej.example',
          imageAssetPath: 'assets/images/triple-j.png',
        ),
        RadioStation(
          name: 'URL test',
          url: 'https://test.example',
        ),
      ]),
      settings: settings,
      player: _SilentPlayer(),
    );
  }

  testWidgets('MainScreen shows grid stations and chrome', (tester) async {
    final controller = await buildController();
    await tester.pumpWidget(InternetRadioApp(controller: controller));
    await tester.pump();

    expect(find.byType(StationGrid), findsOneWidget);
    expect(find.byType(StationTile), findsNWidgets(2));
    expect(find.byTooltip('Mute'), findsOneWidget);
    expect(find.byTooltip('Exit'), findsOneWidget);
    expect(find.byTooltip('Remote mode'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('StationGrid uses vertical scroll in portrait', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StationGrid(
            stations: [
              RadioStation(name: 'A', url: 'https://a.example'),
              RadioStation(name: 'B', url: 'https://b.example'),
              RadioStation(name: 'C', url: 'https://c.example'),
              RadioStation(name: 'D', url: 'https://d.example'),
            ],
            selectedIndex: 0,
            onStationSelected: _noopSelect,
          ),
        ),
      ),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.scrollDirection, Axis.vertical);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
  });

  testWidgets('StationGrid uses horizontal scroll in landscape', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StationGrid(
            stations: [
              RadioStation(name: 'A', url: 'https://a.example'),
              RadioStation(name: 'B', url: 'https://b.example'),
              RadioStation(name: 'C', url: 'https://c.example'),
              RadioStation(name: 'D', url: 'https://d.example'),
            ],
            selectedIndex: null,
            onStationSelected: _noopSelect,
          ),
        ),
      ),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.scrollDirection, Axis.horizontal);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
  });
}

void _noopSelect(int index) {}
