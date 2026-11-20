import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/bots_screen.dart';
import 'ui/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: const HermesBotsApp(),
    ),
  );
}

class HermesBotsApp extends StatefulWidget {
  const HermesBotsApp({super.key});

  @override
  State<HermesBotsApp> createState() => _HermesBotsAppState();
}

class _HermesBotsAppState extends State<HermesBotsApp> with WidgetsBindingObserver {
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

  static const _seed = Color(0xFFFFAC02); // Hermes amber

  @override
  Widget build(BuildContext context) {
    final phase = context.select<AppState, AuthPhase>((s) => s.phase);
    return MaterialApp(
      title: 'Hermes Bots',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark),
      home: switch (phase) {
        AuthPhase.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
        AuthPhase.signedOut => const LoginScreen(),
        AuthPhase.signedIn => const BotsScreen(),
      },
    );
  }
}
