import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_bots/api/models.dart';
import 'package:hermes_bots/state/app_state.dart';
import 'package:hermes_bots/ui/login_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('login screen renders with default server', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const MaterialApp(home: LoginScreen()),
    ));
    expect(find.text('Hermes Bots'), findsOneWidget);
    expect(find.text('https://hermes.devrel.cz'), findsOneWidget);
    await tester.tap(find.text('Přihlásit'));
    await tester.pump();
    expect(find.text('Povinné'), findsNWidgets(2));
  });

  test('bot parsing edge cases used by the list UI', () {
    final b = Bot.fromJson({'name': 'research_bot', 'display_name': '', 'model': ''});
    expect(b.displayName, 'research_bot');
    expect(b.model, isNull);
    expect(b.initials, 'RB');
  });
}
