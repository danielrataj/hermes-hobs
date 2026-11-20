import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/bots_screen.dart';
import 'ui/login_screen.dart';
import 'ui/splash_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    return MaterialApp(
      title: 'Hobs',
      debugShowCheckedModeBanner: false,
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
