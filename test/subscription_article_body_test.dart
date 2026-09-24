import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/subscriptions/subscription_article_body.dart';
import 'package:mithka/theme/app_theme.dart';

final _article =
    '''
<p><a href="#later">Jump later</a></p>
<p><a href="https://example.com/story#later">Jump same page</a></p>
<p><a href="https://example.com/elsewhere#section">Elsewhere</a></p>
<h2 id="later" style="margin-top:1200px">Target heading</h2>
${List.filled(40, '<p>Trailing paragraph so the heading can reach the top.</p>').join()}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('toc anchors scroll and other links still open', (tester) async {
    tester.view.physicalSize = const Size(400, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        home: Scaffold(
          body: ListView(
            children: [
              SubscriptionArticleBody(
                text: _article,
                html: true,
                pageUrl: 'https://example.com/story',
                onOpenLink: (url) async => opened.add(url),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.pixels, 0);
    expect(
      tester.getRect(find.text('Target heading', findRichText: true)).top,
      greaterThan(320),
    );

    await _tapLink(tester, 'Jump later');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(position.pixels, greaterThan(100));
    expect(
      tester.getRect(find.text('Target heading', findRichText: true)).top,
      lessThan(80),
    );
    expect(opened, isEmpty);

    position.jumpTo(0);
    await tester.pump();

    await _tapLink(tester, 'Jump same page');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(position.pixels, greaterThan(100));
    expect(
      tester.getRect(find.text('Target heading', findRichText: true)).top,
      lessThan(80),
    );
    expect(opened, isEmpty);

    position.jumpTo(0);
    await tester.pump();

    await _tapLink(tester, 'Elsewhere');
    await tester.pump();

    expect(opened, ['https://example.com/elsewhere#section']);
    expect(position.pixels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('telegram plain text does not become html', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        home: const Scaffold(
          body: SubscriptionArticleBody(
            text: 'Channel paragraph',
            html: false,
            onOpenLink: _noopOpen,
          ),
        ),
      ),
    );
    expect(find.text('Channel paragraph'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });
}

Future<void> _noopOpen(String url) async {}

Future<void> _tapLink(WidgetTester tester, String label) {
  final rect = tester.getRect(find.text(label, findRichText: true));
  return tester.tapAt(rect.topLeft + const Offset(8, 8));
}
