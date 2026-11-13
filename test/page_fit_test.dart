import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/components/canvas/page_fit.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';

void main() {
  FlavorConfig.setup();
  const page = Size(1000, 1414);

  tearDown(() => stows.fitPageWidth.value = false);

  group('fittedPageWidth', () {
    test('off: pages only scale down', () {
      stows.fitPageWidth.value = false;
      expect(fittedPageWidth(page, 1366), 1000);
      expect(fittedPageWidth(page, 800), 800);
    });

    test('on: pages fill the container width', () {
      stows.fitPageWidth.value = true;
      expect(fittedPageWidth(page, 1366), 1366);
      expect(fittedPageWidth(page, 800), 800);
    });

    test('on: unbounded container keeps the page width', () {
      stows.fitPageWidth.value = true;
      expect(fittedPageWidth(page, double.infinity), 1000);
    });
  });

  group('page positions with fit on', () {
    final pages = [
      EditorPage(size: const Size(100, 100)),
      EditorPage(size: const Size(100, 200)),
      EditorPage(size: const Size(100, 300)),
    ];

    setUp(() => stows.fitPageWidth.value = true);

    test('getTopOfPage scales pages up to the screen width', () {
      // each page is drawn 2x: heights 200, 400, plus 16 gap each
      expect(
        CanvasGestureDetector.getTopOfPage(
          pageIndex: 2,
          pages: pages,
          screenWidth: 200,
        ),
        16 + 200 + 16 + 400,
      );
    });

    test('getPageIndex uses the same scaled heights', () {
      int index(double y) => CanvasGestureDetector.getPageIndex(
        scrollY: y,
        pages: pages,
        screenWidth: 200,
      );
      expect(index(200), 0);
      expect(index(300), 1); // would be page 2 with fit off
      expect(index(700), 2);
    });

    test('getPageIndexFromScrollPosition agrees', () {
      expect(
        EditorState.getPageIndexFromScrollPosition(
          scrollY: 300,
          screenWidth: 200,
          pages: pages,
        ),
        1,
      );
    });
  });

  testWidgets('fitPageToWidth scales the page widget up', (tester) async {
    stows.fitPageWidth.value = true;
    await tester.pumpWidget(
      Center(
        child: fitPageToWidth(
          pageSize: const Size(100, 200),
          width: 300,
          page: const Center(
            child: FittedBox(
              child: SizedBox(key: Key('page'), width: 100, height: 200),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getRect(find.byKey(const Key('page'))).size,
      const Size(300, 600),
    );
  });
}
