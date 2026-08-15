import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/controllers/radio_controller.dart';
import 'package:internetradio/main.dart';
import 'package:internetradio/models/radio_player_state.dart';
import 'package:internetradio/models/radio_station.dart';
import 'package:internetradio/services/network_protocol.dart';
import 'package:internetradio/services/network_service.dart';
import 'package:internetradio/services/radio_player_service.dart';
import 'package:internetradio/services/settings_repository.dart';
import 'package:internetradio/services/station_repository.dart';
import 'package:internetradio/services/wakelock_service.dart';
import 'package:internetradio/widgets/station_grid.dart';
import 'package:internetradio/widgets/station_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentPlayer implements RadioPlayer {
  @override
  RadioPlayerState get state => const RadioPlayerState();

  @override
  Stream<RadioPlayerState> get stateStream => const Stream.empty();

  @override
  Future<bool> play(String url, {String? title, bool applyAudioRouteFix = true}) async => true;

  @override
  Future<void> stop() async {}

  @override
  Future<void> setMuted(bool muted) async {}

  @override
  Future<void> toggleMute() async {}

  @override
  Future<void> refreshState() async {}

  @override
  Future<void> wakeDisplay() async {}

  @override
  void dispose() {}
}

class _SilentWakelock implements ScreenWakelock {
  @override
  Future<void> setEnabled(bool enabled) async {}
}

class _FakePingNetwork extends NetworkService {
  var pingResult = true;
  final sent = <String>[];

  @override
  Future<void> startListener({
    required NetworkCommandHandler onCommand,
    int port = NetworkProtocol.port,
  }) async {}

  @override
  Future<void> stopListener() async {}

  @override
  Future<String?> sendCommand(
    String ipAddress,
    String command, {
    Duration timeout = NetworkProtocol.connectionTimeout,
    int port = NetworkProtocol.port,
  }) async {
    sent.add(command);
    return NetworkProtocol.ok;
  }

  @override
  Future<bool> ping(
    String ipAddress, {
    Duration timeout = NetworkProtocol.connectionTimeout,
    int port = NetworkProtocol.port,
  }) async {
    return pingResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<RadioController> buildController({NetworkService? network}) async {
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
      wakelock: _SilentWakelock(),
      network: network,
    );
  }

  testWidgets('MainScreen shows grid stations and chrome', (tester) async {
    final controller = await buildController();
    await tester.pumpWidget(InternetRadioApp(controller: controller));
    await tester.pump();

    expect(find.byType(StationGrid), findsOneWidget);
    expect(find.byType(StationTile), findsNWidgets(3));
    expect(find.byTooltip('Mute'), findsOneWidget);
    expect(find.byTooltip('Exit'), findsOneWidget);
    expect(find.byTooltip('Remote mode'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('failed remote ping shows close until a later tap connects',
      (tester) async {
    final network = _FakePingNetwork()..pingResult = false;
    final controller = await buildController(network: network);
    await controller.savePlayerIp('192.168.1.10');

    await tester.pumpWidget(InternetRadioApp(controller: controller));
    await tester.pump();

    expect(find.byIcon(Icons.close), findsNothing);

    await tester.tap(find.byTooltip('Remote mode'));
    await tester.pump();

    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.settings_remote), findsOneWidget);

    network.pingResult = true;
    await tester.tap(find.byTooltip('Remote mode'));
    await tester.pump();

    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.radio), findsOneWidget);
    expect(find.byTooltip('Player mode'), findsOneWidget);
  });

  testWidgets('Remote Exit Yes sends EXIT; No does not', (tester) async {
    final pops = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') {
          pops.add(call.method);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final network = _FakePingNetwork();
    final controller = await buildController(network: network);
    await controller.savePlayerIp('192.168.1.10');
    await controller.enterRemoteMode();

    await tester.pumpWidget(InternetRadioApp(controller: controller));
    await tester.pump();

    await tester.tap(find.byTooltip('Exit'));
    await tester.pumpAndSettle();
    expect(find.text('Exit the player too?'), findsOneWidget);

    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(network.sent, isNot(contains(NetworkProtocol.exit)));
    expect(pops, ['SystemNavigator.pop']);

    pops.clear();
    await tester.tap(find.byTooltip('Exit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(network.sent, contains(NetworkProtocol.exit));
    expect(pops, ['SystemNavigator.pop']);
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
