import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/ui/bots_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credentials_test.dart' show settle;
import 'fake_hermes_server.dart';

Bot _bot(String name, [String? section]) => Bot(
  name: name,
  displayName: name,
  sectionId: section,
  sectionName: section == null ? null : 'Folder $section',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('order', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a moved folder keeps its place, new folders go last', () async {
      final app = AppState()
        ..bots = [_bot('1', 'a'), _bot('2', 'b'), _bot('3', 'c'), _bot('4')];
      List<String> titles() => app.sections.map((s) => s.title).toList();
      expect(titles(), ['Folder a', 'Folder b', 'Folder c', 'Nezařazení']);

      app.moveSection('section:c', before: 'section:a');
      expect(titles(), ['Folder c', 'Folder a', 'Folder b', 'Nezařazení']);
      app.moveSection('section:c');
      expect(titles(), ['Folder a', 'Folder b', 'Folder c', 'Nezařazení']);

      // A search that hides a folder must not lose its place.
      app.moveSection('section:b', before: 'section:a');
      app.setQuery('3');
      app.moveSection('section:c');
      app.setQuery('');
      expect(titles(), ['Folder b', 'Folder a', 'Folder c', 'Nezařazení']);

      app.bots = [...app.bots, _bot('5', 'aa')];
      expect(titles().sublist(3), ['Folder aa', 'Nezařazení']);

      app.moveSection(BotSection.unassignedKey, before: 'section:a');
      expect(titles().last, 'Nezařazení');

      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getKeys().singleWhere(
        (k) => k.endsWith('sectionOrder'),
      );
      expect(prefs.getStringList(key), ['section:b', 'section:a', 'section:c']);
    });

    testWidgets('dragging a folder handle reorders, menu renames', (
      tester,
    ) async {
      final app = AppState()
        ..bots = [_bot('1', 'a'), _bot('2', 'b'), _bot('4')];
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: const MaterialApp(home: BotsScreen()),
        ),
      );
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
      expect(find.byIcon(Icons.more_horiz), findsNWidgets(2));

      final drag = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.drag_handle).first),
      );
      await tester.pump();
      await drag.moveBy(const Offset(0, 20));
      await tester.pump();
      await drag.moveBy(const Offset(0, 300));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(app.sections.map((s) => s.title), [
        'Folder b',
        'Folder a',
        'Nezařazení',
      ]);

      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Přejmenovat'));
      await tester.pumpAndSettle();
      expect(find.text('Přejmenovat složku'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Folder b'), findsOneWidget);
      await tester.tap(find.text('Zrušit'));
      await tester.pumpAndSettle();
      expect(find.text('Přejmenovat složku'), findsNothing);
    });
  });

  group('rename', () {
    late FakeHermesServer server;
    late AppState app;

    setUp(() async {
      HttpOverrides.global = null;
      server = FakeHermesServer();
      await server.start();
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      // The hidden bot sits in the same folder as the visible one.
      server.roster[2]['ui_meta'] = {
        'hermes-bots': {
          'hidden': true,
          'sectionId': 's1',
          'sectionName': 'Vibee.one',
        },
      };
      app = AppState();
      await app.login(
        serverUrl: server.baseUrl.toString(),
        username: 'u',
        password: 'p',
      );
      await settle(app);
    });

    tearDown(() async {
      app.dispose();
      await server.stop();
    });

    Map<String, dynamic> meta(int i) =>
        (server.roster[i]['ui_meta'] as Map)['hermes-bots']
            as Map<String, dynamic>;

    test('writes the name to every member and keeps the rest', () async {
      await app.renameSection('section:s1', '  Klienti ');

      expect(server.configures.map((c) => c['name']), ['cto', 'ghost']);
      expect(meta(0), {
        'title': 'CTO',
        'sectionId': 's1',
        'sectionName': 'Klienti',
        'pinned': true,
        'color': '#F0997B',
        'shape': 'circle',
      });
      expect(meta(2), {
        'hidden': true,
        'sectionId': 's1',
        'sectionName': 'Klienti',
      });
      expect(app.sections.first.title, 'Klienti');
      expect(app.bots.map((b) => b.name), ['cto', 'default']);
    });

    test('a stale revision is reread and retried', () async {
      await app.renameSection('section:s1', 'První');
      // Another client edits the bot: the app's copy is now one revision old.
      meta(0)['color'] = '#000000';
      (server.roster[0]['ui_meta_revisions'] as Map)['hermes-bots'] = 7;
      server.configures.clear();

      await app.renameSection('section:s1', 'Druhý');

      expect(server.configures.where((c) => c['name'] == 'cto').length, 2);
      expect(meta(0)['sectionName'], 'Druhý');
      expect(meta(0)['color'], '#000000');
      expect(app.sections.first.title, 'Druhý');
    });
  });
}
