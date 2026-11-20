import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/strings.dart';
import 'state/app_state.dart';
import 'ui/bots_screen.dart';
import 'ui/login_screen.dart';
import 'ui/splash_screen.dart';
import 'ui/theme.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  Strings.current = Strings.forLocale(
    Strings.resolve(binding.platformDispatcher.locales),
  );
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: const HobsApp(),
    ),
  );
}

class HobsApp extends StatefulWidget {
  const HobsApp({super.key});

  @override
  State<HobsApp> createState() => _HobsAppState();
}

class _HobsAppState extends State<HobsApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppState>().onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = context.select<AppState, AuthPhase>((s) => s.phase);
    final language = context.select<AppState, String?>((s) => s.languageCode);
    return MaterialApp(
      title: 'Hermes Hobs',
      debugShowCheckedModeBanner: false,
      // No explicit locale: follow the device's preferred languages.
      locale: language == null ? null : Locale(language),
      supportedLocales: Strings.supportedLocales,
      localizationsDelegates: const [
        Strings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      localeListResolutionCallback: (locales, _) => Strings.resolve(locales),
      theme: HobsTheme.lightTheme(),
      darkTheme: HobsTheme.darkTheme(),
      home: switch (phase) {
        AuthPhase.loading => const SplashScreen(),
        AuthPhase.signedOut => const LoginScreen(),
        AuthPhase.signedIn => const BotsScreen(),
      },
    );
  }
}
