import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/hermes_rpc.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import 'chat_screen.dart';

/// Bot (profile) list. On wide screens the chat opens beside the list.
class BotsScreen extends StatefulWidget {
  const BotsScreen({super.key});

  @override
  State<BotsScreen> createState() => _BotsScreenState();
}

class _BotsScreenState extends State<BotsScreen> {
  String? _selected;

  static const _splitBreakpoint = 840.0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= _splitBreakpoint;
      Bot? selected;
      for (final b in app.bots) {
        if (b.name == _selected) selected = b;
      }
      final list = _BotList(
        selected: wide ? _selected : null,
        onOpen: (bot) {
          if (wide) {
            setState(() => _selected = bot.name);
          } else {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChatScreen(bot: bot),
            ));
          }
        },
      );
      if (!wide) return list;
      return Row(
        children: [
          SizedBox(width: 340, child: list),
          const VerticalDivider(width: 1),
          Expanded(
            child: selected == null
                ? const _EmptyDetail()
                : ChatScreen(key: ValueKey(selected.name), bot: selected, embedded: true),
          ),
        ],
      );
    });
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.forum_outlined, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text('Vyber bota vlevo', style: theme.textTheme.titleMedium),
        ]),
      ),
    );
  }
}

class _BotList extends StatelessWidget {
  const _BotList({required this.onOpen, this.selected});

  final void Function(Bot bot) onOpen;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Boti'),
        actions: [
          _ConnectionDot(status: app.connection),
          IconButton(
            tooltip: 'Obnovit',
            onPressed: app.loadingBots ? null : app.refreshBots,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') app.logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text('${app.username} @ ${Uri.tryParse(app.serverUrl)?.host ?? app.serverUrl}'),
              ),
              const PopupMenuItem(value: 'logout', child: Text('Odhlásit')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: app.refreshBots,
        child: Builder(builder: (context) {
          if (app.loadingBots && app.bots.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (app.botsError != null && app.bots.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 120),
              Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Center(child: Text(app.botsError!, textAlign: TextAlign.center)),
              const SizedBox(height: 12),
              Center(
                child: OutlinedButton(onPressed: app.refreshBots, child: const Text('Zkusit znovu')),
              ),
            ]);
          }
          if (app.bots.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 120),
              Center(child: Text('Na serveru nejsou žádní boti.')),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: app.bots.length,
            separatorBuilder: (_, _) => const SizedBox(height: 2),
            itemBuilder: (context, i) {
              final bot = app.bots[i];
              final active = app.hasChat(bot);
              return ListTile(
                selected: bot.name == selected,
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Text(bot.initials),
                ),
                title: Row(children: [
                  Flexible(child: Text(bot.displayName, overflow: TextOverflow.ellipsis)),
                  if (bot.isDefault) ...[
                    const SizedBox(width: 6),
                    _Tag(label: 'default', color: theme.colorScheme.secondaryContainer),
                  ],
                ]),
                subtitle: Text(
                  [
                    if (bot.description.isNotEmpty) bot.description,
                    if (bot.model != null) bot.model!,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: active
                    ? Icon(Icons.chat_bubble, size: 18, color: theme.colorScheme.primary)
                    : const Icon(Icons.chevron_right),
                onTap: () => onOpen(bot),
              );
            },
          );
        }),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      ConnectionStatus.connected => (Colors.green, 'Připojeno'),
      ConnectionStatus.connecting => (Colors.orange, 'Připojuji…'),
      ConnectionStatus.disconnected => (Colors.red, 'Odpojeno'),
    };
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(Icons.circle, size: 10, color: color),
      ),
    );
  }
}
