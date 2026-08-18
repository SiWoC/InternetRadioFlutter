import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/models/app_settings.dart';
import 'package:internetradio/widgets/settings_overlay.dart';

void main() {
  Future<void> pumpOverlay(
    WidgetTester tester, {
    Future<void> Function(String url)? onPlayTestUrl,
    Future<void> Function(DisplayPolicy policy)? onDisplayPolicyChanged,
    Future<String?> Function(String ip)? onFindPlayer,
    Future<String?> Function(String ip)? onFindYamaha,
    Future<void> Function(String ip)? onPersistPlayerIp,
    Future<void> Function(String ip)? onPersistYamahaIp,
    Future<void> Function({
      required String playerIp,
      required String testUrl,
      required String yamahaIp,
    })?
    onSaveAndClose,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsOverlay(
            initialPlayerIp: '192.168.1.10',
            initialTestUrl: 'https://test.example/stream',
            initialYamahaIp: '192.168.2.2',
            displayPolicy: DisplayPolicy.keepScreenOn,
            onTestPlayerConnection: (_) async => true,
            onPersistPlayerIp: onPersistPlayerIp ?? (_) async {},
            onFindPlayer: onFindPlayer ?? (_) async => null,
            onTestYamahaConnection: (_) async => true,
            onPersistYamahaIp: onPersistYamahaIp ?? (_) async {},
            onFindYamaha: onFindYamaha ?? (_) async => null,
            onPlayTestUrl: onPlayTestUrl ?? (_) async {},
            onDisplayPolicyChanged: onDisplayPolicyChanged ?? (_) async {},
            onSaveAndClose:
                onSaveAndClose ??
                ({
                  required playerIp,
                  required testUrl,
                  required yamahaIp,
                }) async {},
          ),
        ),
      ),
    );
  }

  testWidgets('shows URL field, Play, Yamaha IP, and keep-screen-on', (
    tester,
  ) async {
    await pumpOverlay(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Test stream URL'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Yamaha Receiver IP address'), findsOneWidget);
    expect(find.text('Test'), findsNWidgets(2));
    expect(find.byIcon(Icons.wifi_find), findsNWidgets(2));
    expect(find.text('Keep screen on'), findsOneWidget);
  });

  testWidgets('Play forwards the URL field', (tester) async {
    String? played;
    await pumpOverlay(tester, onPlayTestUrl: (url) async => played = url);

    await tester.tap(find.text('Play'));
    await tester.pump();

    expect(played, 'https://test.example/stream');
  });

  testWidgets('Save and Exit forwards Yamaha IP', (tester) async {
    String? savedYamahaIp;
    await pumpOverlay(
      tester,
      onSaveAndClose:
          ({required playerIp, required testUrl, required yamahaIp}) async {
            savedYamahaIp = yamahaIp;
          },
    );

    await tester.tap(find.text('Save and Exit'));
    await tester.pump();

    expect(savedYamahaIp, '192.168.2.2');
  });

  testWidgets('Find player fills and persists the next IP', (tester) async {
    String? foundArg;
    String? persisted;
    await pumpOverlay(
      tester,
      onFindPlayer: (ip) async {
        foundArg = ip;
        return '192.168.1.20';
      },
      onPersistPlayerIp: (ip) async => persisted = ip,
    );

    await tester.tap(find.byTooltip('Find player'));
    await tester.pump();
    await tester.pump();

    expect(foundArg, '192.168.1.10');
    expect(persisted, '192.168.1.20');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      '192.168.1.20',
    );
    expect(find.text('OK'), findsOneWidget);
  });

  testWidgets('Find receiver fills the Yamaha IP', (tester) async {
    String? foundArg;
    await pumpOverlay(
      tester,
      onFindYamaha: (ip) async {
        foundArg = ip;
        return '192.168.2.8';
      },
    );

    await tester.tap(find.byTooltip('Find receiver'));
    await tester.pump();
    await tester.pump();

    expect(foundArg, '192.168.2.2');
    expect(find.text('OK'), findsOneWidget);
  });

  testWidgets('does not overflow in short landscape', (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpOverlay(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
