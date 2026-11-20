import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';

/// App settings. For now just the language: follow the device, or pin one of
/// the language packs.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final s = Strings.of(context);
    final device = Strings.forLocale(
      Strings.resolve(View.of(context).platformDispatcher.locales),
    );
    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              s.language.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _LanguageTile(
            title: s.languageSystem,
            subtitle: s.languageSystemNow(device.languageName),
            selected: app.languageCode == null,
            onTap: () => app.setLanguage(null),
          ),
          for (final locale in Strings.supportedLocales)
            _LanguageTile(
              // Each language is listed under its own name, so it can be
              // found by someone who cannot read the current one.
              title: Strings.forLocale(locale).languageName,
              selected: app.languageCode == locale.languageCode,
              onTap: () => app.setLanguage(locale.languageCode),
            ),
        ],
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      selected: selected,
      trailing: selected ? Icon(Icons.check, color: cs.primary) : null,
      onTap: onTap,
    );
  }
}
