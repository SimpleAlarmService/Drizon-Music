// Renders the app icon PNGs from AppIconArt. Skipped unless asked:
//   DRIZON_RENDER_ICON=1 flutter test test/render_app_icon_test.dart
//   dart run flutter_launcher_icons
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oye/ui/brand/app_icon_art.dart';

final _skip = Platform.environment['DRIZON_RENDER_ICON'] == '1' ? false : 'set DRIZON_RENDER_ICON=1';

Future<void> _render(WidgetTester tester, Widget art, String path) async {
  final key = GlobalKey();
  tester.view.physicalSize = const Size(1024, 1024);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Material(type: MaterialType.transparency, child: RepaintBoundary(key: key, child: art)),
  ));
  await tester.pump();
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('app icon', (tester) async {
    await _render(tester, const AppIconArt(), 'assets/icon/app_icon.png');
    await _render(tester, const AppIconArt(foregroundOnly: true), 'assets/icon/app_icon_foreground.png');
    addTearDown(tester.view.reset);
  }, skip: _skip != false);
}
