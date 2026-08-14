import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/models/app_settings.dart';
import 'package:internetradio/widgets/settings_overlay.dart';

void main() {
  Future<void> pumpOverlay(
    WidgetTester tester, {
    Future<void> Function(String url)? onPlayTestUrl,
    Future<void> Function(DisplayPolicy policy)? onDisplayPolicyChanged,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsOverlay(
            initialPlayerIp: '192.168.1.10',
            initialTestUrl: 'https://test.example/stream',
            displayPolicy: DisplayPolicy.keepScreenOn,
            onTestConnection: (_) async => true,
            onPersistIp: (_) async {},
            onPlayTestUrl: onPlayTestUrl ?? (_) async {},
            onDisplayPolicyChanged: onDisplayPolicyChanged ?? (_) async {},
            onSaveAndClose: (_, __) async {},
          ),
        ),
      ),
    );
  }

  testWidgets('shows URL field, Play, and keep-screen-on', (tester) async {
    await pumpOverlay(tester);

    expect(find.text('Test stream URL'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Keep screen on'), findsOneWidget);
  });

  testWidgets('Play forwards the URL field', (tester) async {
    String? played;
    await pumpOverlay(
      tester,
      onPlayTestUrl: (url) async => played = url,
    );

    await tester.tap(find.text('Play'));
    await tester.pump();

    expect(played, 'https://test.example/stream');
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
