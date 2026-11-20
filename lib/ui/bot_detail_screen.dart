import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'bot_avatar.dart';

/// A bot's profile: its face, title, description, model and SOUL.md, editable like in
/// the dashboard's "Edit profile" dialog. Opened by tapping a bot's avatar.
class BotDetailScreen extends StatefulWidget {
  const BotDetailScreen({super.key, required this.bot});

  final Bot bot;

  static Future<void> open(BuildContext context, Bot bot) =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => BotDetailScreen(bot: bot)));

  @override
  State<BotDetailScreen> createState() => _BotDetailScreenState();
}

class _BotDetailScreenState extends State<BotDetailScreen> {
  /// The bot the form was filled from; edits are compared against it.
  late Bot _bot = widget.bot;

  late final _title = TextEditingController(text: _bot.customTitle);
  late final _description = TextEditingController(text: _bot.description);
  final _provider = TextEditingController();
  final _model = TextEditingController();
  final _soul = TextEditingController();

  /// Stored values; null draws the one derived from the bot's name.
  late String? _shape = _bot.shape;
  late String? _color = _bot.color;

  /// Null while loading. [_setupFailed] when the profile could not be read.
  BotSetup? _saved;
  bool _setupFailed = false;
  List<ModelProvider> _providers = const [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _description, _provider, _model, _soul]) {
      c.addListener(_changed);
    }
    _loadSetup();
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _provider, _model, _soul]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSetup() async {
    final app = context.read<AppState>();
    // The provider list is a convenience: without it the fields are free text.
    final providers = app.modelProviders().catchError(
      (_) => const <ModelProvider>[],
    );
    try {
      final setup = await app.botSetup(_bot);
      final list = await providers;
      if (!mounted) return;
      _provider.text = setup.provider;
      _model.text = setup.model;
      _soul.text = setup.soul;
      setState(() {
        _providers = list;
        _saved = setup;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _setupFailed = true);
    }
  }

  bool get _appearanceDirty =>
      _title.text.trim() != _bot.customTitle ||
      _shape != _bot.shape ||
      _color != _bot.color;

  bool get _descriptionDirty =>
      _description.text.trim() != _bot.description.trim();

  bool get _modelDirty {
    final saved = _saved;
    return saved != null &&
        (_provider.text.trim() != saved.provider ||
            _model.text.trim() != saved.model);
  }

  bool get _soulDirty {
    final saved = _saved;
    return saved != null && _soul.text.trim() != saved.soul.trim();
  }

  bool get _dirty =>
      _appearanceDirty || _descriptionDirty || _modelDirty || _soulDirty;

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    final app = context.read<AppState>();
    final s = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final provider = _provider.text.trim();
    final model = _model.text.trim();
    if (_modelDirty && provider.isEmpty != model.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(s.modelRequired)));
      return;
    }
    setState(() => _saving = true);
    var done = true;
    try {
      final bot = app.botNamed(_bot.name) ?? _bot;
      if (_appearanceDirty) {
        await app.saveBotAppearance(
          bot,
          title: _title.text,
          shape: _shape,
          color: _color,
        );
      }
      if (_descriptionDirty) {
        await app.saveBotDescription(bot, _description.text);
      }
      if (_modelDirty) {
        final question = await app.saveBotModel(
          bot,
          provider: provider,
          model: model,
        );
        if (question != null) {
          if (!mounted) return;
          if (await _confirmModel(question)) {
            await app.saveBotModel(
              bot,
              provider: provider,
              model: model,
              confirmed: true,
            );
          } else {
            done = false;
          }
        }
        if (done) {
          _saved = BotSetup(
            provider: provider,
            model: model,
            soul: _saved!.soul,
          );
        }
      }
      if (_soulDirty) {
        await app.saveBotSoul(bot, _soul.text);
        _saved = BotSetup(
          provider: _saved!.provider,
          model: _saved!.model,
          soul: _soul.text,
        );
      }
    } catch (e) {
      done = false;
      messenger.showSnackBar(
        SnackBar(content: Text(s.botSaveFailed(AppState.describeError(e)))),
      );
    }
    await app.refreshBots(silent: true);
    final fresh = app.botNamed(_bot.name) ?? _bot;
    if (done) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.botSaved(fresh.displayName))),
      );
      if (mounted) navigator.pop();
      return;
    }
    // Something stayed unsaved: keep the form, compared to what is stored now.
    if (mounted) {
      setState(() {
        _bot = fresh;
        _saving = false;
      });
    }
  }

  Future<bool> _confirmModel(String question) async {
    final s = Strings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.confirmModelTitle),
        content: Text(question.isEmpty ? s.confirmModelFallback : question),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.switchModel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _askDiscard() async {
    final s = Strings.of(context);
    final navigator = Navigator.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.discardChangesTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.discardChanges),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.keepEditing),
          ),
        ],
      ),
    );
    if (discard == true && mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = Strings.of(context);
    final faceColor = BotAvatar.parseColor(_color) ?? BotAvatar.autoColor(_bot);
    final faceShape =
        BotAvatar.normalizeShape(_shape) ?? BotAvatar.autoShape(_bot);
    final title = _title.text.trim();
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _askDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.botProfile),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _dirty && !_saving ? _save : null,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(s.save),
              ),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Center(
                  child: BotAvatar(
                    bot: _bot,
                    size: 88,
                    shape: faceShape,
                    color: faceColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title.isEmpty ? _bot.name : title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  '@${_bot.name}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                _SectionLabel(s.appearance),
                _FieldLabel(s.shapeLabel),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ShapeTile(
                      label: s.byName,
                      selected: BotAvatar.normalizeShape(_shape) == null,
                      onTap: () => setState(() => _shape = null),
                      child: Text(
                        s.autoLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final shape in BotAvatar.pickableShapes)
                      _ShapeTile(
                        label: shape,
                        selected: BotAvatar.normalizeShape(_shape) == shape,
                        // A blob the dashboard drew stays as it is stored.
                        onTap: () => setState(
                          () => _shape =
                              BotAvatar.normalizeShape(_bot.shape) == shape
                              ? _bot.shape
                              : shape,
                        ),
                        child: BotAvatar(
                          bot: _bot,
                          size: 30,
                          shape: shape,
                          color: faceColor,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _FieldLabel(s.colorLabel),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Swatch(
                      label: s.byName,
                      color: null,
                      selected: BotAvatar.parseColor(_color) == null,
                      onTap: () => setState(() => _color = null),
                    ),
                    for (final c in _swatches())
                      _Swatch(
                        label: BotAvatar.hex(c),
                        color: c,
                        selected: BotAvatar.parseColor(_color) == c,
                        onTap: () => setState(() => _color = BotAvatar.hex(c)),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: s.botTitleLabel,
                    hintText: _bot.name,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _description,
                  minLines: 3,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: s.botDescriptionLabel,
                    hintText: s.botDescriptionHint,
                    alignLabelWithHint: true,
                  ),
                ),
                if (_setupFailed) ...[
                  const SizedBox(height: 24),
                  Text(
                    s.setupLoadFailed,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else if (_saved == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  _SectionLabel(s.modelSection),
                  ..._modelFields(s),
                  _SectionLabel(s.soulSection),
                  TextField(
                    controller: _soul,
                    minLines: 6,
                    maxLines: 16,
                    autocorrect: false,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.45,
                    ),
                    decoration: InputDecoration(hintText: s.soulHint),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The palette, led by the bot's own color when it is not one of them.
  List<Color> _swatches() {
    final own = BotAvatar.parseColor(_bot.color);
    return [
      if (own != null && !BotAvatar.palette.contains(own)) own,
      ...BotAvatar.palette,
    ];
  }

  List<Widget> _modelFields(Strings s) {
    final provider = _provider.text.trim();
    final model = _model.text.trim();
    if (_providers.isEmpty) {
      return [
        TextField(
          controller: _provider,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: s.providerLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _model,
          autocorrect: false,
          decoration: InputDecoration(labelText: s.modelLabel),
        ),
      ];
    }
    final known = _providers.where((p) => p.slug == provider);
    final models = [
      ...?known.firstOrNull?.models,
      if (model.isNotEmpty &&
          !(known.firstOrNull?.models.contains(model) ?? false))
        model,
    ];
    DropdownMenuItem<String> item(String value, String label) =>
        DropdownMenuItem(
          value: value,
          child: Text(label, overflow: TextOverflow.ellipsis),
        );
    return [
      DropdownButtonFormField<String>(
        initialValue: provider,
        isExpanded: true,
        decoration: InputDecoration(labelText: s.providerLabel),
        items: [
          item('', s.inheritModel),
          for (final p in _providers) item(p.slug, p.label),
          if (provider.isNotEmpty && known.isEmpty) item(provider, provider),
        ],
        onChanged: (slug) {
          if (slug == null || slug == provider) return;
          final offered = _providers
              .where((p) => p.slug == slug)
              .expand((p) => p.models)
              .toList();
          _provider.text = slug;
          _model.text = slug.isEmpty
              ? ''
              : (offered.contains(model) ? model : offered.firstOrNull ?? '');
        },
      ),
      const SizedBox(height: 12),
      if (provider.isEmpty)
        const SizedBox.shrink()
      else if ((known.firstOrNull?.models ?? const []).isEmpty)
        TextField(
          controller: _model,
          autocorrect: false,
          decoration: InputDecoration(labelText: s.modelLabel),
        )
      else
        DropdownButtonFormField<String>(
          key: ValueKey('model:$provider'),
          initialValue: model.isEmpty ? null : model,
          isExpanded: true,
          decoration: InputDecoration(labelText: s.modelLabel),
          items: [for (final m in models) item(m, m)],
          onChanged: (m) => _model.text = m ?? '',
        ),
    ];
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ShapeTile extends StatelessWidget {
  const _ShapeTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = BorderRadius.circular(14);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: selected ? cs.secondaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: border,
            side: BorderSide(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: border,
            onTap: onTap,
            child: SizedBox.square(dimension: 52, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}

/// One color of the palette; a null [color] is "derived from the name".
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fill = color;
    final onFill = fill == null
        ? cs.onSurfaceVariant
        : (fill.computeLuminance() < 0.25
              ? Colors.white
              : const Color(0xFF2C2C2A));
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: 26,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              border: Border.all(
                color: selected ? cs.primary : cs.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? Icon(Icons.check, size: 18, color: onFill)
                : (fill == null
                      ? Icon(
                          Icons.auto_awesome_outlined,
                          size: 18,
                          color: onFill,
                        )
                      : null),
          ),
        ),
      ),
    );
  }
}
