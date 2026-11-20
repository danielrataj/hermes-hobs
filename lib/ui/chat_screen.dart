import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../api/hermes_rpc.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../state/chat_controller.dart';
import 'bot_avatar.dart';
import 'cron_sheet.dart';
import 'format.dart';
import 'pull_up_reload.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.bot, this.embedded = false});

  final Bot bot;

  /// True when shown beside the bot list (no back button).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AppState>().chatFor(bot);
    return ChangeNotifierProvider.value(
      value: controller,
      child: ChatView(embedded: embedded),
    );
  }
}

class ChatView extends StatefulWidget {
  const ChatView({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _awayFromBottom = false;
  int _countWhenLeft = 0;
  bool _promptExpanded = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    // The list is reversed: offset 0 is the newest message.
    final away = _scroll.hasClients && _scroll.offset > 240;
    if (away != _awayFromBottom) {
      setState(() {
        _awayFromBottom = away;
        if (away) {
          _countWhenLeft = context.read<ChatController>().messages.length;
        }
      });
    }
  }

  void _jumpToBottom() {
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send(ChatController c) {
    final text = _input.text;
    if (text.trim().isEmpty || c.busy || !c.ready) return;
    _input.clear();
    c.send(text);
    _focus.requestFocus();
    if (_scroll.hasClients) _jumpToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ChatController>();
    final theme = Theme.of(context);
    final working = c.busy || c.bot.workingNow;
    final prompt = c.lastPrompt;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: widget.embedded ? 16 : 0,
        title: Row(
          children: [
            BotAvatar(bot: c.bot, size: 30, working: working),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.bot.displayName, overflow: TextOverflow.ellipsis),
                  Text(
                    _subtitle(c),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: c.busy
                          ? const Color(0xFF1D9E75)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Naplánované úlohy',
            onPressed: () => showCronSheet(context, c.bot),
            icon: const Icon(Icons.event_repeat_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (c.connection != ConnectionStatus.connected &&
              c.phase != ChatPhase.starting)
            MaterialBanner(
              content: const Text(
                'Spojení se serverem přerušeno, připojuji znovu…',
              ),
              leading: const Icon(Icons.wifi_off),
              actions: [
                TextButton(
                  onPressed: () => context.read<AppState>().onAppResumed(),
                  child: const Text('Teď'),
                ),
              ],
            ),
          if (prompt != null && c.messages.length > 2)
            _PinnedPrompt(
              text: prompt,
              expanded: _promptExpanded,
              onTap: () => setState(() => _promptExpanded = !_promptExpanded),
            ),
          Expanded(
            child: Stack(
              children: [
                PullUpReload(
                  onReload: c.reload,
                  child: _buildMessages(c, theme),
                ),
                if (_awayFromBottom)
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ActionChip(
                        avatar: const Icon(Icons.arrow_downward, size: 16),
                        label: Text(
                          c.messages.length > _countWhenLeft
                              ? '${c.messages.length - _countWhenLeft} nové'
                              : 'Na konec',
                        ),
                        onPressed: _jumpToBottom,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (c.error != null)
            Container(
              width: double.infinity,
              color: theme.colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  if (c.phase == ChatPhase.failed)
                    TextButton(onPressed: c.start, child: const Text('Znovu')),
                ],
              ),
            ),
          if (c.approval != null) _ApprovalCard(controller: c),
          if (c.clarify != null)
            _ClarifyCard(key: ObjectKey(c.clarify), controller: c),
          _Composer(
            controller: _input,
            focusNode: _focus,
            chat: c,
            onSend: () => _send(c),
          ),
        ],
      ),
    );
  }

  String _subtitle(ChatController c) {
    if (c.phase == ChatPhase.starting) return 'Otevírám Bot Chat…';
    if (c.busy) {
      return 'pracuje${c.statusText != null ? ' · ${c.statusText}' : '…'}';
    }
    if (c.bot.workingNow) return 'pracuje na pozadí';
    final last = c.bot.lastActive;
    return last != null ? 'aktivní ${relativeAge(last)}' : (c.bot.description);
  }

  Widget _buildMessages(ChatController c, ThemeData theme) {
    if (c.phase == ChatPhase.starting && c.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (c.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BotAvatar(bot: c.bot, size: 64),
              const SizedBox(height: 12),
              Text(
                'Napiš zprávu pro ${c.bot.displayName}',
                style: theme.textTheme.titleMedium,
              ),
              if (c.bot.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  c.bot.description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final items = c.messages.reversed.toList();
    final showTyping = c.busy && items.first.role == ChatRole.user;
    return SelectionArea(
      child: ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        itemCount: items.length + (showTyping ? 1 : 0),
        itemBuilder: (context, i) {
          if (showTyping) {
            if (i == 0) return _TypingRow(status: c.statusText);
            i -= 1;
          }
          final m = items[i];
          // Meta row (time, copy) under the last assistant row of a turn.
          final newer = i > 0 ? items[i - 1] : null;
          final endOfTurn =
              m.role == ChatRole.assistant &&
              !m.streaming &&
              (newer == null || newer.role == ChatRole.user);
          return _MessageRow(message: m, showMeta: endOfTurn, controller: c);
        },
      ),
    );
  }
}

class _PinnedPrompt extends StatelessWidget {
  const _PinnedPrompt({
    required this.text,
    required this.expanded,
    required this.onTap,
  });

  final String text;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.push_pin_outlined,
                  size: 15,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    maxLines: expanded ? 8 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: cs.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.showMeta,
    required this.controller,
  });

  final ChatMessage message;
  final bool showMeta;
  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    switch (message.role) {
      case ChatRole.user:
        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(message.text, style: theme.textTheme.bodyMedium),
          ),
        );
      case ChatRole.assistant:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MarkdownBody(
                data: message.text + (message.streaming ? ' ▍' : ''),
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  code: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (message.interrupted)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'přerušeno',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.outline,
                    ),
                  ),
                ),
              if (showMeta)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Text(
                        clockTime(message.time),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.outline,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Kopírovat',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        color: cs.outline,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: message.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Zkopírováno'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_outlined),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case ChatRole.activity:
        return _ActivityRow(
          message: message,
          onToggle: () => controller.toggleActivity(message),
        );
      case ChatRole.notice:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            message.text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        );
      case ChatRole.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: cs.onErrorContainer, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message.text,
                    style: TextStyle(color: cs.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}

/// One muted line summarizing consecutive tool calls; tap to expand.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.message, required this.onToggle});

  final ChatMessage message;
  final VoidCallback onToggle;

  static String _label(String tool) => switch (tool) {
    'message_agent' || 'send_message' => 'zpráva agentovi',
    'skill_view' || 'skills_list' || 'skill_load' => 'skill',
    'terminal' || 'execute_code' => 'příkaz',
    'web_search' => 'hledání na webu',
    'web_extract' || 'browser_navigate' => 'web',
    'read_file' || 'search_files' => 'soubory',
    'write_file' || 'patch' => 'úprava souboru',
    'clarify' => 'dotaz',
    'cronjob' => 'naplánovaná úloha',
    'todo' => 'úkoly',
    'memory' => 'paměť',
    'delegate_task' => 'delegace',
    _ => tool.replaceAll('_', ' '),
  };

  String _summary() {
    final tools = message.tools;
    final running = tools.where((t) => t.state == ToolState.running).toList();
    if (running.isNotEmpty) {
      final t = running.last;
      final detail = t.progress ?? t.preview;
      return '${_label(t.name)}${detail != null && detail.isNotEmpty ? ' · $detail' : ''}';
    }
    final counts = <String, int>{};
    for (final t in tools) {
      final l = _label(t.name);
      counts[l] = (counts[l] ?? 0) + 1;
    }
    return counts.entries
        .map((e) => e.value > 1 ? '${e.key} ×${e.value}' : e.key)
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final running = message.toolsRunning;
    final failed = message.tools.any((t) => t.state == ToolState.failed);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  if (running)
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    )
                  else
                    Icon(
                      failed ? Icons.error_outline : Icons.build_outlined,
                      size: 14,
                      color: failed ? cs.error : cs.outline,
                    ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _summary(),
                      style: muted,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    message.expanded ? Icons.expand_less : Icons.chevron_right,
                    size: 16,
                    color: cs.outline,
                  ),
                ],
              ),
            ),
          ),
          if (message.expanded)
            Padding(
              padding: const EdgeInsets.only(left: 21, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final t in message.tools)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            switch (t.state) {
                              ToolState.running => Icons.more_horiz,
                              ToolState.done => Icons.check,
                              ToolState.failed => Icons.close,
                            },
                            size: 13,
                            color: t.state == ToolState.failed
                                ? cs.error
                                : cs.outline,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: t.name,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  if ((t.summary ?? t.preview) != null)
                                    TextSpan(
                                      text: '  ${t.summary ?? t.preview}',
                                    ),
                                  if (t.durationS != null)
                                    TextSpan(
                                      text:
                                          '  ${t.durationS!.toStringAsFixed(1)} s',
                                    ),
                                ],
                              ),
                              style: muted,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TypingRow extends StatelessWidget {
  const _TypingRow({this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              status ?? 'Přemýšlí…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.chat,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ChatController chat;
  final VoidCallback onSend;

  static const _effortLabels = {
    'minimal': 'Min',
    'low': 'Low',
    'medium': 'Med',
    'high': 'High',
    'xhigh': 'Max',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final canType = chat.ready || chat.busy;
    final chipStyle = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
              decoration: BoxDecoration(
                border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: CallbackShortcuts(
                      bindings: {
                        // Enter sends, Shift+Enter adds a newline (desktop keyboards).
                        const SingleActivator(LogicalKeyboardKey.enter): onSend,
                      },
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: canType,
                        minLines: 1,
                        maxLines: 6,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: chat.ready ? 'Napiš zprávu' : 'Připojuji…',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: chat.busy
                        ? IconButton.filledTonal(
                            tooltip: 'Zastavit',
                            onPressed: chat.interrupt,
                            icon: const Icon(Icons.stop, size: 20),
                          )
                        : IconButton.filled(
                            tooltip: 'Odeslat',
                            onPressed: chat.ready ? onSend : null,
                            icon: const Icon(Icons.arrow_upward, size: 20),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (chat.model != null)
                  Flexible(
                    child: Tooltip(
                      message: 'Model bota (mění se v profilu)',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          chat.model!,
                          style: chipStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  enabled: chat.ready,
                  tooltip: 'Úroveň uvažování',
                  initialValue: chat.reasoningEffort,
                  onSelected: chat.setReasoningEffort,
                  itemBuilder: (_) => [
                    for (final l in ChatController.effortLevels)
                      PopupMenuItem(
                        value: l,
                        child: Text('${_effortLabels[l]} · $l'),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _effortLabels[chat.reasoningEffort] ??
                              (chat.reasoningEffort ?? 'Uvažování'),
                          style: chipStyle,
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.controller});

  final ChatController controller;

  static const _labels = {
    'once': 'Povolit jednou',
    'session': 'Povolit v konverzaci',
    'always': 'Povolit vždy',
    'deny': 'Zamítnout',
  };

  @override
  Widget build(BuildContext context) {
    final a = controller.approval!;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bot žádá o schválení${a.toolName != null ? ' (${a.toolName})' : ''}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (a.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(a.description),
            ],
            if (a.command.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  a.command,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final choice in a.choices)
                  choice == 'deny'
                      ? OutlinedButton(
                          onPressed: () => controller.answerApproval(choice),
                          child: Text(_labels[choice] ?? choice),
                        )
                      : FilledButton.tonal(
                          onPressed: () => controller.answerApproval(choice),
                          child: Text(_labels[choice] ?? choice),
                        ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ClarifyCard extends StatefulWidget {
  const _ClarifyCard({super.key, required this.controller});

  final ChatController controller;

  @override
  State<_ClarifyCard> createState() => _ClarifyCardState();
}

class _ClarifyCardState extends State<_ClarifyCard> {
  final Map<String, String?> _answers = {};
  final Map<String, TextEditingController> _text = {};

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final qs = widget.controller.clarify!;
    final out = <String, String?>{};
    for (final q in qs) {
      final typed = _text[q.qid]?.text.trim();
      out[q.qid] = (typed != null && typed.isNotEmpty)
          ? typed
          : _answers[q.qid];
    }
    widget.controller.answerClarify(out);
  }

  @override
  Widget build(BuildContext context) {
    final qs = widget.controller.clarify!;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: theme.colorScheme.secondaryContainer,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.45,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.help_outline, size: 18),
                  const SizedBox(width: 8),
                  Text('Bot se ptá', style: theme.textTheme.titleSmall),
                ],
              ),
              for (final q in qs) ...[
                const SizedBox(height: 10),
                Text(q.question),
                const SizedBox(height: 6),
                if (q.choices != null && q.choices!.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final ch in q.choices!)
                        ChoiceChip(
                          label: Text(ch),
                          selected: _answers[q.qid] == ch,
                          onSelected: (_) =>
                              setState(() => _answers[q.qid] = ch),
                        ),
                    ],
                  ),
                TextField(
                  controller: _text.putIfAbsent(
                    q.qid,
                    TextEditingController.new,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: (q.choices?.isNotEmpty ?? false)
                        ? 'nebo vlastní odpověď'
                        : 'Odpověď',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => widget.controller.answerClarify(null),
                    child: const Text('Přeskočit'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('Odpovědět'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
