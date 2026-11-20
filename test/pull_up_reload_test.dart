import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/ui/pull_up_reload.dart';

void main() {
  for (final (name, physics) in <(String, ScrollPhysics)>[
    ('bouncing', const BouncingScrollPhysics()),
    ('clamping', const ClampingScrollPhysics()),
  ]) {
    group('$name physics', () {
      late int reloads;
      late Completer<void> done;

      Future<void> pump(WidgetTester tester) {
        reloads = 0;
        done = Completer<void>();
        return tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PullUpReload(
                onReload: () {
                  reloads++;
                  return done.future;
                },
                child: ListView.builder(
                  reverse: true,
                  physics: AlwaysScrollableScrollPhysics(parent: physics),
                  itemCount: 40,
                  itemBuilder: (_, i) =>
                      SizedBox(height: 60, child: Text('row $i')),
                ),
              ),
            ),
          ),
        );
      }

      testWidgets('pulling up past the newest row reloads once', (
        tester,
      ) async {
        await pump(tester);
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        // The bounce-back after lifting the finger needs a ticked frame.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(reloads, 1);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // A second pull while loading is ignored.
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pump();
        expect(reloads, 1);

        done.complete();
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
      });

      testWidgets('a short pull does not reload', (tester) async {
        await pump(tester);
        await tester.drag(find.byType(ListView), const Offset(0, -40));
        await tester.pumpAndSettle();
        expect(reloads, 0);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      });

      testWidgets('scrolling into history does not reload', (tester) async {
        await pump(tester);
        await tester.drag(find.byType(ListView), const Offset(0, 400));
        await tester.pumpAndSettle();
        expect(reloads, 0);
      });
    });
  }
}
