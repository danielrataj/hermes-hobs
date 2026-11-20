import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/ui/bot_avatar.dart';
import 'package:hobs/ui/format.dart';
import 'package:hobs/ui/login_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('login screen renders with default server', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    expect(find.text('Hermes Hobs'), findsOneWidget);
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
      BotAvatar.colorFor(Bot(name: 'x', displayName: 'x', color: '#F0997B')),
      const Color(0xFFF0997B),
    );
  });

  test('faces follow the dashboard formulas', () {
    // "a" hashes to 97: shape 97 % 7, hue 97.
    final a = BotAvatar.resolve(name: 'a');
    expect(a.shape, 'drop');
    expect(a.color, const HSLColor.fromAHSL(1, 97, .68, .58).toColor());
    // The hash wraps at 32 bits, like the dashboard's `>>> 0`.
    expect(BotAvatar.autoShape('financni-poradce'), 'hexagon');

    // The default profile keeps its fixed face until the user picks one.
    final fixed = BotAvatar.resolve(name: 'Default', shape: 'drop');
    expect((fixed.shape, fixed.color), ('squircle', const Color(0xFF8B5CF6)));
    expect(
      BotAvatar.resolve(name: 'default', shape: 'drop', custom: true).shape,
      'drop',
    );

    expect(
      BotAvatar.parseColor('hsl(30 68% 58%)'),
      const HSLColor.fromAHSL(1, 30, .68, .58).toColor(),
    );
    expect(BotAvatar.palette.length, 12);
    expect(BotAvatar.resolve(name: 'a', color: '#101010').lightEyes, isTrue);
    expect(BotAvatar.resolve(name: 'a', shape: 'hex').shape, 'hexagon');
    expect(BotAvatar.resolve(name: 'a', shape: 'weird').shape, 'drop');

    final blob = BotAvatar.resolve(name: 'a', shape: 'blobatar:k3x:sun');
    expect((blob.blobSeed, blob.blobKind), ('k3x', 'sun'));
    expect(BotAvatar.resolve(name: 'a', shape: 'blobatar').blobSeed, 'a');
    expect(BotAvatar.blobShape('', null), 'blobatar');
    expect(BotAvatar.blobShape('k3x', null), 'blobatar:k3x');
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
