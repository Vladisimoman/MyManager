import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/app.dart';

/// Етап 21: на широкому екрані (браузер на комп'ютері) інтерфейс — колонка
/// по центру шириною [appMaxWidth]; на телефоні нічого не змінюється.
void main() {
  Future<({Size box, Size media})> measure(
    WidgetTester tester,
    Size screen,
  ) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Size media;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppWidthLimit(child: child!),
        home: Builder(
          builder: (context) {
            media = MediaQuery.sizeOf(context);
            return const Scaffold(body: SizedBox.expand(key: Key('page')));
          },
        ),
      ),
    );
    return (box: tester.getSize(find.byKey(const Key('page'))), media: media);
  }

  testWidgets('комп\'ютер: колонка 600 по центру, MediaQuery теж 600', (
    tester,
  ) async {
    final r = await measure(tester, const Size(1600, 900));
    expect(r.box.width, appMaxWidth);
    expect(r.media, const Size(appMaxWidth, 900));
    final left = tester.getTopLeft(find.byKey(const Key('page'))).dx;
    expect(left, (1600 - appMaxWidth) / 2);
  });

  testWidgets('телефон: на всю ширину', (tester) async {
    final r = await measure(tester, const Size(411, 914));
    expect(r.box.width, 411);
    expect(r.media, const Size(411, 914));
  });
}
