import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../api/hermes_rpc.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../state/chat_controller.dart';

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
      child: _ChatView(embedded: embedded),
    );
  }
}

class _ChatView extends StatefulWidget {
  const _ChatView({required this.embedded});

  final bool embedded;

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

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
  }

  Future<void> _confirmReset(ChatController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nová konverzace?'),
        content: Text('Aktuální konverzace s ${c.bot.displayName} se zavře.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Zrušit')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Nová')),
        ],
      ),
    );
    if (ok == true) c.reset();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ChatController>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: widget.embedded ? 16 : 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.bot.displayName),
            Text(
              _subtitle(c),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Nová konverzace',
            onPressed: c.phase == ChatPhase.starting ? null : () => _confirmReset(c),
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (c.connection != ConnectionStatus.connected && c.phase != ChatPhase.starting)
            MaterialBanner(
              content: const Text('Spojení se serverem přerušeno, připojuji znovu…'),
              leading: const Icon(Icons.wifi_off),
              actions: [
                TextButton(
                    onPressed: () => context.read<AppState>().onAppResumed(),
                    child: const Text('Teď')),
              ],
            ),
          Expanded(child: _buildMessages(c, theme)),
          if (c.error != null)
            Container(
              width: double.infinity,
              color: theme.colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Expanded(
                    child: Text(c.error!,
                        style: TextStyle(color: theme.colorScheme.onErrorContainer))),
                if (c.phase == ChatPhase.failed)
                  TextButton(onPressed: c.start, child: const Text('Znovu')),
              ]),
            ),
          if (c.approval != null) _ApprovalCard(controller: c),
          if (c.clarify != null) _ClarifyCard(key: ObjectKey(c.clarify), controller: c),
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
    if (c.phase == ChatPhase.starting) return 'Otevírám konverzaci…';
    if (c.busy) return c.statusText ?? 'Pracuje…';
    return [
      if (c.model != null) c.model!,
      if (c.bot.description.isNotEmpty) c.bot.description,
    ].join(' · ');
  }

  Widget _buildMessages(ChatController c, ThemeData theme) {
    if (c.phase == ChatPhase.starting && c.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (c.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(radius: 32, child: Text(c.bot.initials, style: theme.textTheme.titleLarge)),
            const SizedBox(height: 12),
            Text('Napiš zprávu pro ${c.bot.displayName}', style: theme.textTheme.titleMedium),
            if (c.bot.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(c.bot.description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ]),
        ),
      );
    }
    final items = c.messages.reversed.toList();
    final showTyping = c.busy && (items.isEmpty || items.first.role == ChatRole.user);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      itemCount: items.length + (showTyping ? 1 : 0),
      itemBuilder: (context, i) {
        if (showTyping) {
          if (i == 0) return _TypingBubble(status: c.statusText);
          i -= 1;
        }
        return _MessageBubble(message: items[i]);
      },
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canType = chat.ready || chat.busy;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  // Enter sends, Shift+Enter adds a newline (desktop).
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
                    hintText: chat.ready ? 'Zpráva…' : 'Čekám na spojení…',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (chat.busy)
              IconButton.filledTonal(
                tooltip: 'Zastavit',
                onPressed: chat.interrupt,
                icon: const Icon(Icons.stop),
              )
            else
              IconButton.filled(
                tooltip: 'Odeslat',
                onPressed: chat.ready ? onSend : null,
                icon: const Icon(Icons.send),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    switch (message.role) {
      case ChatRole.notice:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(
            child: Text(message.text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
        );
      case ChatRole.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: cs.errorContainer, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.error_outline, color: cs.onErrorContainer, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: SelectableText(message.text,
                      style: TextStyle(color: cs.onErrorContainer))),
            ]),
          ),
        );
      case ChatRole.user:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            margin: const EdgeInsets.only(top: 6, bottom: 6, left: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SelectableText(message.text,
                style: TextStyle(color: cs.onPrimaryContainer)),
          ),
        );
      case ChatRole.assistant:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 720),
            margin: const EdgeInsets.only(top: 6, bottom: 6, right: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final t in message.tools) _ToolChip(tool: t),
                if (message.text.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: MarkdownBody(
                      data: message.text + (message.streaming ? ' ▍' : ''),
                      selectable: !message.streaming,
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
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
                  ),
                if (message.interrupted)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text('přerušeno',
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.outline)),
                  ),
              ],
            ),
          ),
        );
    }
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.tool});

  final ToolActivity tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final icon = switch (tool.state) {
      ToolState.running => const SizedBox(
          width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
      ToolState.done => Icon(Icons.check, size: 14, color: cs.primary),
      ToolState.failed => Icon(Icons.close, size: 14, color: cs.error),
    };
    final detail = tool.progress ?? tool.summary ?? tool.preview;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          icon,
          const SizedBox(width: 8),
          Text(tool.name, style: theme.textTheme.labelMedium),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
          ],
          if (tool.durationS != null) ...[
            const SizedBox(width: 6),
            Text('${tool.durationS!.toStringAsFixed(1)} s',
                style: theme.textTheme.labelSmall?.copyWith(color: cs.outline)),
          ],
        ]),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(status ?? 'Přemýšlí…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ]),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.shield_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Bot žádá o schválení${a.toolName != null ? ' (${a.toolName})' : ''}',
                  style: theme.textTheme.titleSmall),
            ),
          ]),
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
              child: SelectableText(a.command,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final choice in a.choices)
              choice == 'deny'
                  ? OutlinedButton(
                      onPressed: () => controller.answerApproval(choice),
                      child: Text(_labels[choice] ?? choice))
                  : FilledButton.tonal(
                      onPressed: () => controller.answerApproval(choice),
                      child: Text(_labels[choice] ?? choice)),
          ]),
        ]),
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
      out[q.qid] = (typed != null && typed.isNotEmpty) ? typed : _answers[q.qid];
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
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.help_outline, size: 18),
              const SizedBox(width: 8),
              Text('Bot se ptá', style: theme.textTheme.titleSmall),
            ]),
            for (final q in qs) ...[
              const SizedBox(height: 10),
              Text(q.question),
              const SizedBox(height: 6),
              if (q.choices != null && q.choices!.isNotEmpty)
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final ch in q.choices!)
                    ChoiceChip(
                      label: Text(ch),
                      selected: _answers[q.qid] == ch,
                      onSelected: (_) => setState(() => _answers[q.qid] = ch),
                    ),
                ]),
              TextField(
                controller: _text.putIfAbsent(q.qid, TextEditingController.new),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: (q.choices?.isNotEmpty ?? false) ? 'nebo vlastní odpověď' : 'Odpověď',
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: () => widget.controller.answerClarify(null),
                  child: const Text('Přeskočit')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _submit, child: const Text('Odpovědět')),
            ]),
          ]),
        ),
      ),
    );
  }
}
