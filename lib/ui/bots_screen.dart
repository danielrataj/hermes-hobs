import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/hermes_rpc.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'bot_avatar.dart';
import 'chat_screen.dart';
import 'format.dart';
import 'settings_screen.dart';
import 'theme.dart';

/// Bot roster grouped into the user's folders. On wide screens the chat
/// opens beside the list (like the dashboard); on phones it is pushed.
class BotsScreen extends StatefulWidget {
  const BotsScreen({super.key});

  @override
  State<BotsScreen> createState() => _BotsScreenState();
}

class _BotsScreenState extends State<BotsScreen> {
  String? _selected;

  static const _splitBreakpoint = 840.0;

  Future<void> _open(Bot bot, bool wide) async {
    final app = context.read<AppState>();
    if (wide) {
      setState(() => _selected = bot.name);
      app.setOpenBot(bot.name);
      return;
    }
    app.setOpenBot(bot.name);
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ChatScreen(bot: bot)));
    if (!mounted) return;
    app.setOpenBot(null);
    app.refreshBots(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= _splitBreakpoint;
        Bot? selected;
        for (final b in app.bots) {
          if (b.name == _selected) selected = b;
        }
        final list = _BotList(
          selected: wide ? _selected : null,
          onOpen: (b) => _open(b, wide),
        );
        if (!wide) return list;
        return Row(
          children: [
            SizedBox(width: 340, child: list),
            const VerticalDivider(width: 1),
            Expanded(
              child: selected == null
                  ? const _EmptyDetail()
                  : ChatScreen(
                      key: ValueKey(selected.name),
                      bot: selected,
                      embedded: true,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              Strings.of(context).pickBot,
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _BotList extends StatefulWidget {
  const _BotList({required this.onOpen, this.selected});

  final void Function(Bot bot) onOpen;
  final String? selected;

  @override
  State<_BotList> createState() => _BotListState();
}

class _BotListState extends State<_BotList> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.text = context.read<AppState>().query;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static List<(BotFilter, String)> _filters(Strings s) => [
    (BotFilter.all, s.filterAll),
    (BotFilter.unread, s.filterUnread),
    (BotFilter.pinned, s.filterPinned),
    (BotFilter.active, s.filterActive),
    (BotFilter.recent, s.filterRecent),
    (BotFilter.older, s.filterOlder),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final s = Strings.of(context);
    final sections = app.sections;
    final unread = app.bots.where(app.isUnread).length;
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.botsTitle),
            _ConnectionLine(status: app.connection),
          ],
        ),
        actions: [
          _AccountButton(app: app),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: app.setQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: s.searchBots,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: app.query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _search.clear();
                          app.setQuery('');
                        },
                      ),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final (f, label) in _filters(s))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: f == BotFilter.unread && unread > 0
                          ? _CountLabel(label: label, count: unread)
                          : Text(label),
                      selected: app.filter == f,
                      onSelected: (_) => app.setFilter(f),
                      visualDensity: VisualDensity.compact,
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: app.refreshBots,
              child: _buildBody(app, theme, s, sections),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    AppState app,
    ThemeData theme,
    Strings s,
    List<BotSection> sections,
  ) {
    if (app.loadingBots && app.bots.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (app.botsError != null && app.bots.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Center(child: Text(app.botsError!, textAlign: TextAlign.center)),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton(
              onPressed: app.refreshBots,
              child: Text(s.retry),
            ),
          ),
        ],
      );
    }
    if (sections.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Center(child: Text(app.bots.isEmpty ? s.noBots : s.noMatches)),
        ],
      );
    }
    final showHeaders = app.hasFolders;
    final children = <Widget>[];
    for (final s in sections) {
      final isCollapsed =
          showHeaders && app.collapsed.contains(s.key) && app.query.isEmpty;
      if (showHeaders) {
        children.add(
          _SectionHeader(
            title: s.title,
            count: s.bots.length,
            collapsed: isCollapsed,
            unread: s.bots.where(app.isUnread).length,
            onTap: () => app.toggleSection(s.key),
          ),
        );
      }
      if (!isCollapsed) {
        for (final b in s.bots) {
          children.add(
            _BotRow(
              bot: b,
              selected: b.name == widget.selected,
              unread: app.isUnread(b),
              working: app.isWorking(b),
              onTap: () => widget.onOpen(b),
            ),
          );
        }
      }
    }
    children.add(const SizedBox(height: 24));
    return ListView(children: children);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.collapsed,
    required this.unread,
    required this.onTap,
  });

  final String title;
  final int count;
  final bool collapsed;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 0.8,
      fontWeight: FontWeight.w600,
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 6),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.folder_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: style,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (collapsed && unread > 0) ...[
              Icon(
                Icons.circle,
                size: 7,
                color: HobsColors.of(context).lantern,
              ),
              const SizedBox(width: 8),
            ],
            Text('$count', style: style),
          ],
        ),
      ),
    );
  }
}

class _BotRow extends StatelessWidget {
  const _BotRow({
    required this.bot,
    required this.selected,
    required this.unread,
    required this.working,
    required this.onTap,
  });

  final Bot bot;
  final bool selected;
  final bool unread;
  final bool working;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final preview = plainPreview(
      bot.preview.isNotEmpty ? bot.preview : bot.description,
    );
    return Material(
      color: selected
          ? cs.secondaryContainer.withValues(alpha: 0.6)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              BotAvatar(bot: bot, size: 38, working: working),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  bot.displayName,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: unread
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (bot.pinned) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.push_pin_outlined,
                                  size: 13,
                                  color: cs.outline,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          working ? s.working : relativeAge(bot.lastActive),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: working
                                ? HobsColors.of(context).working
                                : (unread ? cs.primary : cs.outline),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview.isEmpty ? s.noMessagesYet : preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: unread
                                  ? cs.onSurface
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: HobsColors.of(context).lantern,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The connection state in words under the screen title, so the colored
/// mark never has to be decoded on its own.
class _ConnectionLine extends StatelessWidget {
  const _ConnectionLine({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hobs = HobsColors.of(context);
    final s = Strings.of(context);
    final (color, label) = switch (status) {
      ConnectionStatus.connected => (hobs.working, s.connected),
      ConnectionStatus.connecting => (hobs.lantern, s.connecting),
      ConnectionStatus.disconnected => (
        theme.colorScheme.error,
        s.disconnected,
      ),
    };
    final connected = status == ConnectionStatus.connected;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: connected ? theme.colorScheme.onSurfaceVariant : color,
            fontWeight: connected ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Filter chip label with the number of waiting bots next to it.
class _CountLabel extends StatelessWidget {
  const _CountLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 6),
        Container(
          constraints: const BoxConstraints(minWidth: 20),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: cs.tertiaryContainer,
          ),
          child: Text(
            '$count',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onTertiaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// The signed-in user's initial. Opens the account menu, where every action
/// carries its own icon and label.
class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final name = app.username.trim();
    final host = Uri.tryParse(app.serverUrl)?.host ?? '';
    return PopupMenuButton<String>(
      tooltip: s.account,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (v) {
        if (v == 'logout') app.logout();
        if (v == 'settings') {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: cs.onSurface,
                ),
              ),
              Text(
                host.isEmpty ? app.serverUrl : host,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'settings',
          child: _MenuRow(icon: Icons.settings_outlined, label: s.settings),
        ),
        PopupMenuItem(
          value: 'logout',
          child: _MenuRow(icon: Icons.logout, label: s.signOut),
        ),
      ],
      icon: CircleAvatar(
        radius: 16,
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        child: name.isEmpty
            ? const Icon(Icons.person_outline, size: 18)
            : Text(
                name.characters.first.toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
    );
  }
}
