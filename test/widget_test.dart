import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/main.dart';

void main() {
  testWidgets('PoC screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(const InternetRadioApp());

    expect(find.text('Media3 Stream PoC'), findsOneWidget);
    expect(find.text('Triple J NSW'), findsOneWidget);
    expect(find.text('All Time Hits'), findsOneWidget);
  });
}
