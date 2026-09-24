import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/transcript_entry_boundary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a transcript row is tracked only after it has a size', (
    tester,
  ) async {
    final entries = <int, RenderBox>{};
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: TranscriptEntryBoundary(
            messageId: 7,
            mountedEntries: entries,
            child: const SizedBox(width: 20, height: 30),
          ),
        ),
      ),
    );

    final box = entries[7];
    expect(box, isNotNull);
    expect(box!.hasSize, isTrue);
    expect(box.size, const Size(20, 30));
  });

  testWidgets('a removed element is not asked for its render object', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Center(child: SizedBox(key: key, width: 12, height: 8)),
    );
    final context = key.currentContext;
    expect(laidOutBoxOf(context)?.size, const Size(12, 8));

    await tester.pumpWidget(const SizedBox.shrink());
    expect(laidOutBoxOf(context), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two paragraphs under a selection area can lay out', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: SelectionArea(
            child: Column(
              children: [Text('First paragraph'), Text('Second paragraph')],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('First paragraph'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
