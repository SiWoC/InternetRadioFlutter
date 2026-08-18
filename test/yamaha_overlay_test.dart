import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/models/yamaha_status.dart';
import 'package:internetradio/widgets/yamaha_overlay.dart';

void main() {
  const status = YamahaStatus(
    power: YamahaPower.on,
    inputSel: 'HDMI4',
    volumeTenthsDb: -570,
    mute: false,
  );
  const inputs = [
    YamahaInput(param: 'HDMI4', title: 'Mediaplay'),
    YamahaInput(param: 'HDMI2', title: 'HDMI2'),
  ];

  Future<void> pumpOverlay(
    WidgetTester tester, {
    YamahaStatus? snapshot = status,
    List<YamahaInput> itemList = inputs,
    bool busy = false,
    VoidCallback? onPower,
    ValueChanged<String>? onSelectInput,
    VoidCallback? onVolumeUp,
    VoidCallback? onVolumeDown,
    VoidCallback? onClose,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: YamahaOverlay(
            status: snapshot,
            inputs: itemList,
            busy: busy,
            onPower: onPower ?? () {},
            onSelectInput: onSelectInput ?? (_) {},
            onVolumeUp: onVolumeUp ?? () {},
            onVolumeDown: onVolumeDown ?? () {},
            onClose: onClose ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('shows power, input, volume, and Close', (tester) async {
    await pumpOverlay(tester);

    expect(find.text('Yamaha'), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('Input'), findsOneWidget);
    expect(find.text('Mediaplay'), findsOneWidget);
    expect(find.text('-57.0 dB'), findsOneWidget);
    expect(find.byTooltip('Standby'), findsOneWidget);
    expect(find.byTooltip('Volume up'), findsOneWidget);
    expect(find.byTooltip('Volume down'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('Close, power, and volume call through', (tester) async {
    var closed = false;
    var power = false;
    var up = false;
    var down = false;
    await pumpOverlay(
      tester,
      onClose: () => closed = true,
      onPower: () => power = true,
      onVolumeUp: () => up = true,
      onVolumeDown: () => down = true,
    );

    await tester.tap(find.text('Close'));
    await tester.tap(find.byTooltip('Standby'));
    await tester.tap(find.byTooltip('Volume up'));
    await tester.tap(find.byTooltip('Volume down'));
    await tester.pump();

    expect(closed, isTrue);
    expect(power, isTrue);
    expect(up, isTrue);
    expect(down, isTrue);
  });

  testWidgets('input dropdown forwards the selected param', (tester) async {
    String? selected;
    await pumpOverlay(tester, onSelectInput: (value) => selected = value);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HDMI2').last);
    await tester.pumpAndSettle();

    expect(selected, 'HDMI2');
  });

  testWidgets('busy with a status still allows power and volume', (
    tester,
  ) async {
    var power = false;
    var up = false;
    await pumpOverlay(
      tester,
      busy: true,
      onPower: () => power = true,
      onVolumeUp: () => up = true,
    );

    await tester.tap(find.byTooltip('Standby'));
    await tester.tap(find.byTooltip('Volume up'));
    await tester.pump();

    expect(power, isTrue);
    expect(up, isTrue);
  });

  testWidgets('null status shows Unreachable', (tester) async {
    await pumpOverlay(tester, snapshot: null);

    expect(find.text('Unreachable'), findsOneWidget);
    expect(find.text('Connecting...'), findsNothing);
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
