import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/ui/bot_avatar.dart';
import 'package:hobs/ui/bot_detail_screen.dart';
import 'package:hobs/ui/bots_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credentials_test.dart' show settle;
import 'fake_hermes_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('screen', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<AppState> pumpList(WidgetTester tester) async {
      final app = AppState()
        ..bots = [
          Bot(
            name: 'dev-cto',
            displayName: 'CTO',
            description: 'Vede vývoj',
            shape: 'circle',
            color: '#F0997B',
            meta: const {'title': 'CTO', 'shape': 'circle'},
          ),
        ];
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: const MaterialApp(home: BotsScreen()),
        ),
      );
      return app;
    }

    testWidgets('the avatar in the list opens the profile', (tester) async {
      await pumpList(tester);
      await tester.tap(find.byTooltip('Upravit profil: CTO'));
      await tester.pumpAndSettle();

      expect(find.byType(BotDetailScreen), findsOneWidget);
      expect(find.text('Profil Hobíka'), findsOneWidget);
      expect(find.text('@dev-cto'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'CTO'), findsOneWidget);
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Vede vývoj'), findsOneWidget);
      // Offline: the model cannot be read, the rest stays editable.
      expect(find.textContaining('SOUL.md se nepodařilo'), findsOneWidget);
    });

    testWidgets('save wakes up on an edit, leaving asks first', (tester) async {
      await pumpList(tester);
      await tester.tap(find.byTooltip('Upravit profil: CTO'));
      await tester.pumpAndSettle();
      FilledButton save() =>
          tester.widget(find.widgetWithText(FilledButton, 'Uložit'));
      expect(save().onPressed, isNull);

      await tester.tap(find.byTooltip('hexagon'));
      await tester.pump();
      expect(save().onPressed, isNotNull);
      final preview = tester.widget<BotAvatar>(find.byType(BotAvatar).first);
      expect(preview.shape, 'hexagon');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Zahodit neuložené změny?'), findsOneWidget);
      await tester.tap(find.text('Zahodit'));
      await tester.pumpAndSettle();
      expect(find.byType(BotDetailScreen), findsNothing);
    });
  });

  group('saving', () {
    late FakeHermesServer server;
    late AppState app;

    setUp(() async {
      HttpOverrides.global = null;
      server = FakeHermesServer();
      await server.start();
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
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

    Map<String, dynamic> meta() =>
        (server.roster[0]['ui_meta'] as Map)['hermes-bots']
            as Map<String, dynamic>;

    test('appearance keeps the rest of the metadata', () async {
      await app.saveBotAppearance(
        app.botNamed('cto')!,
        title: ' Šéf ',
        shape: 'hexagon',
        color: null,
      );
      expect(meta(), {
        'title': 'Šéf',
        'sectionId': 's1',
        'sectionName': 'Vibee.one',
        'pinned': true,
        'shape': 'hexagon',
        'custom': true,
      });

      await app.refreshBots(silent: true);
      expect(app.botNamed('cto')!.displayName, 'Šéf');
    });

    test('a stale revision is reread and retried', () async {
      await app.renameSection('section:s1', 'Klienti');
      final stale = app.botNamed('cto')!;
      // Another client edits the bot: the app's copy is now one revision old.
      meta()['pinned'] = false;
      (server.roster[0]['ui_meta_revisions'] as Map)['hermes-bots'] = 7;
      server.configures.clear();

      await app.saveBotAppearance(
        stale,
        title: 'CTO',
        shape: stale.shape,
        color: '#000000',
      );
      expect(server.configures.length, 2);
      expect(meta()['pinned'], false);
      expect(meta()['color'], '#000000');
    });

    test('description goes through the profile command', () async {
      await app.saveBotDescription(app.botNamed('cto')!, ' Vede vývoj ');
      expect(server.cliCalls, [
        ['profile', 'describe', 'cto', '--text', 'Vede vývoj'],
      ]);
      await app.refreshBots(silent: true);
      expect(app.botNamed('cto')!.description, 'Vede vývoj');
    });

    test('model is read, switched, confirmed and unset', () async {
      final bot = app.botNamed('cto')!;
      final now = await app.botSetup(bot);
      expect((now.provider, now.model), ('nous', 'hermes-4'));
      final providers = await app.modelProviders();
      expect(providers.map((p) => p.label), [
        'Nous (nous)',
        'Codex (openai-codex)',
      ]);
      expect(providers.last.models, ['gpt-6.2-sol']);

      expect(
        await app.saveBotModel(
          bot,
          provider: 'openai-codex',
          model: 'gpt-6.2-sol',
        ),
        isNull,
      );
      expect(server.profileModel['default'], 'gpt-6.2-sol');

      // An expensive model is not switched until the user confirms.
      expect(
        await app.saveBotModel(bot, provider: 'nous', model: 'hermes-4-pro'),
        'Pricey.',
      );
      expect(server.profileModel['default'], 'gpt-6.2-sol');
      await app.saveBotModel(
        bot,
        provider: 'nous',
        model: 'hermes-4-pro',
        confirmed: true,
      );
      expect(server.profileModel['default'], 'hermes-4-pro');

      await app.saveBotModel(bot, provider: '', model: '');
      expect(server.cliCalls.last, [
        '--profile',
        'cto',
        'config',
        'unset',
        'model',
      ]);
    });

    test('SOUL.md is read and replaced', () async {
      final bot = app.botNamed('cto')!;
      expect((await app.botSetup(bot)).soul, '# CTO\n\nVede vývoj.\n');

      await app.saveBotSoul(bot, '# CTO\n\nVede vývoj a testy.\n');
      expect(server.configures.last, {
        'name': 'cto',
        'soul': '# CTO\n\nVede vývoj a testy.',
      });
      expect((await app.botSetup(bot)).soul, '# CTO\n\nVede vývoj a testy.');
    });
  });
}
