import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oye/ui/widgets/cover_flow.dart';

Widget _tile(int i) {
  final colors = [
    Colors.red, Colors.orange, Colors.green, Colors.blue, Colors.purple,
  ];
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
          colors: [colors[i % 5], colors[i % 5].shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Center(
        child: Text('$i',
            style: const TextStyle(fontSize: 64, color: Colors.white))),
  );
}

/// Set DRIZON_SHOT_DIR to also write PNGs of the rendered Cover Flow.
final String? _shotDir = Platform.environment['DRIZON_SHOT_DIR'];

void main() {
  final key = GlobalKey<CoverFlowState>();
  final repaint = GlobalKey();
  final changes = <int>[];
  final taps = <int>[];

  Future<void> pumpFlow(WidgetTester tester, {int count = 5, int initial = 0}) {
    changes.clear();
    taps.clear();
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: RepaintBoundary(
          key: repaint,
          child: Center(
            child: CoverFlow(
              key: key,
              size: 200,
              itemCount: count,
              initialIndex: initial,
              itemBuilder: (_, i) => _tile(i),
              onIndexChanged: changes.add,
              onTapCenter: taps.add,
            ),
          ),
        ),
      ),
    ));
  }

  Future<void> snapshot(WidgetTester tester, String name) async {
    if (_shotDir == null) return;
    await tester.runAsync(() async {
      final boundary =
          repaint.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${_shotDir!}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('renders and reports taps on the centre cover', (tester) async {
    await pumpFlow(tester, initial: 2);
    await snapshot(tester, 'coverflow_center2');
    await tester.tapAt(tester.getCenter(find.byType(CoverFlow)) - const Offset(0, 60));
    await tester.pump();
    expect(taps, [2]);
  });

  testWidgets('dragging left advances the centred item', (tester) async {
    await pumpFlow(tester);
    await tester.drag(find.byType(CoverFlow), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(changes, isNotEmpty);
    expect(changes.last, greaterThanOrEqualTo(1));
    await snapshot(tester, 'coverflow_after_drag');
  });

  testWidgets('animateTo jumps with a spring and settles exactly', (tester) async {
    await pumpFlow(tester);
    key.currentState!.animateTo(4);
    await tester.pumpAndSettle();
    expect(changes.last, 4);
  });

  testWidgets('cannot be dragged far past either end', (tester) async {
    await pumpFlow(tester, count: 3);
    await tester.fling(find.byType(CoverFlow), const Offset(800, 0), 4000);
    await tester.pumpAndSettle();
    expect(changes.every((i) => i >= 0 && i <= 2), isTrue);
  });

  testWidgets('shrinking itemCount does not throw', (tester) async {
    await pumpFlow(tester, count: 5, initial: 4);
    await pumpFlow(tester, count: 2, initial: 1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
