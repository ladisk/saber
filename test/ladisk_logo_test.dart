import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/ladisk_logo.dart';

void main() {
  Widget editor({Brightness brightness = Brightness.light}) => MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: const Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: Stack(
          children: [
            Positioned.fill(child: SizedBox()),
            LadiskLogo(),
          ],
        ),
      ),
    ),
  );

  testWidgets('LadiskLogo sits in the bottom left corner', (tester) async {
    await tester.pumpWidget(editor());

    final rect = tester.getRect(find.byType(SvgPicture));
    expect(rect.left, 12);
    expect(rect.bottom, 600 - 12);
    expect(rect.height, 64);
  });

  testWidgets('LadiskLogo lets touches through to the page', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => tapped = true,
                ),
              ),
              const LadiskLogo(),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(SvgPicture), warnIfMissed: false);
    expect(tapped, isTrue);
  });

  testWidgets('LadiskLogo gets a light background in dark mode', (
    tester,
  ) async {
    final backdrop = find.descendant(
      of: find.byType(LadiskLogo),
      matching: find.byType(DecoratedBox),
    );
    await tester.pumpWidget(editor());
    expect(backdrop, findsNothing);

    await tester.pumpWidget(editor(brightness: Brightness.dark));
    await tester.pumpAndSettle();
    expect(backdrop, findsOneWidget);
  });
}
