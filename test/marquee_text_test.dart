import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/widgets/marquee_text.dart';

void main() {
  testWidgets('short text stays a single static label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: MarqueeText(
                text: 'Short',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Short'), findsOneWidget);
  });

  testWidgets('long text uses two looping copies', (tester) async {
    const text = 'A very long now-playing line that will not fit';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 80,
              child: MarqueeText(
                text: text,
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(text), findsNWidgets(2));
  });

  testWidgets('looping copies keep a gap between title end and next start',
      (tester) async {
    const text = 'A very long now-playing line that will not fit';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 80,
              child: MarqueeText(
                text: text,
                style: TextStyle(fontSize: 16),
                gap: 48,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final texts = find.text(text);
    expect(texts, findsNWidgets(2));
    final first = tester.getRect(texts.at(0));
    final second = tester.getRect(texts.at(1));
    expect(second.left, closeTo(first.right + 48, 1));
  });

  testWidgets('text slightly wider than the box still scrolls', (tester) async {
    const text = 'Captain Sensible - Happy Talk';
    const style = TextStyle(fontSize: 16);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              child: MarqueeText(text: text, style: style),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final box = tester.renderObject<RenderBox>(find.text(text));
    final intrinsic = box.getMaxIntrinsicWidth(box.size.height);
    expect(intrinsic, greaterThan(80));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: intrinsic - 4,
              child: const MarqueeText(text: text, style: style),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(text), findsNWidgets(2));
  });

  testWidgets('line box is taller than fontSize so descenders fit',
      (tester) async {
    const fontSize = 16.0;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: MarqueeText(
                text: 'yg()',
                style: TextStyle(fontSize: fontSize),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final size = tester.getSize(find.byType(MarqueeText));
    expect(size.height, greaterThan(fontSize));
  });
}
