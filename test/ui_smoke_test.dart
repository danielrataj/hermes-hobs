import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_bots/api/models.dart';
import 'package:hermes_bots/state/app_state.dart';
import 'package:hermes_bots/ui/bot_avatar.dart';
import 'package:hermes_bots/ui/format.dart';
import 'package:hermes_bots/ui/login_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('login screen renders with default server', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    expect(find.text('Hermes Bots'), findsOneWidget);
    expect(find.text('https://hermes.devrel.cz'), findsOneWidget);
    await tester.tap(find.text('Přihlásit'));
    await tester.pump();
    expect(find.text('Povinné'), findsNWidgets(2));
  });

  testWidgets('avatars render for every shape', (tester) async {
    const shapes = [
      'circle',
      'squircle',
      'pill',
      'triangle',
      'hexagon',
      'cloud',
      'drop',
      'blobatar:7:a',
      'weird',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Wrap(
          children: [
            for (final s in shapes)
              BotAvatar(
                bot: Bot(name: 'b$s', displayName: s, shape: s),
                working: s == 'pill',
              ),
          ],
        ),
      ),
    );
    expect(find.byType(BotAvatar), findsNWidgets(shapes.length));
    expect(
      BotAvatar.shapeFor(
        Bot(name: 'x', displayName: 'x', shape: 'blobatar:7:a'),
      ),
      'blob',
    );
    expect(
      BotAvatar.colorFor(Bot(name: 'x', displayName: 'x', color: '#F0997B')),
      const Color(0xFFF0997B),
    );
  });

  test('bot parsing edge cases used by the list UI', () {
    final b = Bot.fromJson({
      'name': 'research_bot',
      'display_name': '',
      'model': '',
    });
    expect(b.displayName, 'research_bot');
    expect(b.model, isNull);
    expect(b.initials, 'RB');
  });

  test('relative age and previews', () {
    final now = DateTime(2026, 11, 20, 16);
    expect(
      relativeAge(now.subtract(const Duration(seconds: 20)), now: now),
      'teď',
    );
    expect(
      relativeAge(now.subtract(const Duration(minutes: 56)), now: now),
      '56m',
    );
    expect(relativeAge(now.subtract(const Duration(hours: 2)), now: now), '2h');
    expect(relativeAge(now.subtract(const Duration(days: 3)), now: now), '3d');
    expect(dayTime(DateTime(2026, 11, 21, 9), now: now), 'zítra 09:00');
    expect(
      plainPreview('**Analytik** ověřil\n\n`zdroje`'),
      'Analytik ověřil zdroje',
    );
  });
}
