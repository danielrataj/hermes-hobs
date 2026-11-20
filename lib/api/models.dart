/// Summary of a session row as `profiles.list {include_sessions: true}` reports it.
class SessionSummary {
  SessionSummary({
    required this.id,
    this.resolvedId,
    this.preview = '',
    this.lastActive,
    this.messageCount = 0,
  });

  final String id;

  /// Live tip after context compression; resume this one.
  final String? resolvedId;
  final String preview;
  final DateTime? lastActive;
  final int messageCount;

  String get resumeId =>
      (resolvedId != null && resolvedId!.isNotEmpty) ? resolvedId! : id;

  static SessionSummary? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return SessionSummary(
      id: id,
      resolvedId: j['resolved_id']?.toString(),
      preview: (j['preview']?.toString() ?? '').trim(),
      lastActive: epochToDate(j['last_active']),
      messageCount: (j['message_count'] as num?)?.toInt() ?? 0,
    );
  }
}

DateTime? epochToDate(Object? v) {
  if (v is! num || v <= 0) return null;
  // Hermes stores Unix seconds (float); tolerate milliseconds too.
  final ms = v > 1e12 ? v.toInt() : (v * 1000).toInt();
  return DateTime.fromMillisecondsSinceEpoch(ms);
}

/// A Hermes profile — each profile is an independent agent ("bot").
///
/// Bot Mode appearance lives in `profile.yaml` under `ui_meta['hermes-bots']`
/// (`title`, `sectionId`/`sectionName`, `color`, `shape`, `pinned`, `hidden`).
class Bot {
  Bot({
    required this.name,
    required this.displayName,
    this.description = '',
    this.model,
    this.provider,
    this.isDefault = false,
    this.sectionId,
    this.sectionName,
    this.color,
    this.shape,
    this.pinned = false,
    this.hidden = false,
    this.canonical,
    this.lastSession,
    this.workerActiveAt,
  });

  final String name;
  final String displayName;
  final String description;
  final String? model;
  final String? provider;
  final bool isDefault;
  final String? sectionId;
  final String? sectionName;
  final String? color;
  final String? shape;
  final bool pinned;
  final bool hidden;

  /// The bot's forever-chat: the session titled "Bot Chat" on its profile.
  final SessionSummary? canonical;
  final SessionSummary? lastSession;

  /// Heartbeat of the newest background worker (cron/kanban) session.
  final DateTime? workerActiveAt;

  static const canonicalTitle = 'Bot Chat';

  factory Bot.fromJson(Map<String, dynamic> j) {
    String str(Object? v) => (v is String) ? v.trim() : '';
    final uiMeta = j['ui_meta'];
    final meta = (uiMeta is Map && uiMeta['hermes-bots'] is Map)
        ? Map<String, dynamic>.from(uiMeta['hermes-bots'] as Map)
        : const <String, dynamic>{};
    final name = str(j['name']);
    final display = [
      str(meta['title']),
      str(j['display_name']),
      str(j['bot_title']),
      name,
    ].firstWhere((s) => s.isNotEmpty, orElse: () => name);
    final worker = j['worker_session'];
    final model = str(j['model']);
    return Bot(
      name: name,
      displayName: display,
      description: str(j['description']).isNotEmpty
          ? str(j['description'])
          : str(meta['description']),
      model: model.isEmpty ? null : model,
      provider: str(j['provider']).isEmpty ? null : str(j['provider']),
      isDefault: j['is_default'] == true,
      sectionId: str(meta['sectionId']).isEmpty ? null : str(meta['sectionId']),
      sectionName: str(meta['sectionName']).isEmpty
          ? null
          : str(meta['sectionName']),
      color: str(meta['color']).isEmpty ? null : str(meta['color']),
      shape: str(meta['shape']).isEmpty ? null : str(meta['shape']),
      pinned: meta['pinned'] == true,
      hidden: meta['hidden'] == true,
      canonical: SessionSummary.fromJson(j['canonical_session']),
      lastSession: SessionSummary.fromJson(j['last_session']),
      workerActiveAt: worker is Map ? epochToDate(worker['last_active']) : null,
    );
  }

  /// What the roster row shows: the Bot Chat's latest message.
  String get preview => canonical?.preview ?? '';

  DateTime? get lastActive {
    final a = canonical?.lastActive;
    final w = workerActiveAt;
    if (a == null) return w;
    if (w == null) return a;
    return a.isAfter(w) ? a : w;
  }

  /// A worker heartbeat within two minutes means the bot is busy right now.
  bool get workingNow {
    final w = workerActiveAt;
    return w != null &&
        DateTime.now().difference(w) < const Duration(minutes: 2);
  }

  String get initials {
    final parts = displayName
        .split(RegExp(r'[\s_\-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

enum ChatRole { user, assistant, activity, notice, error }

enum ToolState { running, done, failed }

class ToolActivity {
  ToolActivity({
    required this.id,
    required this.name,
    this.preview,
    this.state = ToolState.running,
  });

  final String id;
  final String name;
  String? preview;
  String? summary;
  String? progress;
  double? durationS;
  ToolState state;
}

/// One row of the transcript. `activity` rows group consecutive tool calls
/// into the single collapsible line the dashboard shows between replies.
class ChatMessage {
  ChatMessage({
    required this.role,
    this.text = '',
    this.streaming = false,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  final ChatRole role;
  String text;
  bool streaming;
  DateTime time;
  final List<ToolActivity> tools = [];
  bool interrupted = false;
  bool expanded = false;

  bool get toolsRunning => tools.any((t) => t.state == ToolState.running);
}

/// An approval request for a dangerous command (`approval` server request).
class PendingApproval {
  PendingApproval({
    required this.command,
    required this.description,
    required this.choices,
    this.toolName,
  });

  final String command;
  final String description;
  final List<String> choices;
  final String? toolName;
}

class ClarifyQuestion {
  ClarifyQuestion({
    required this.qid,
    required this.question,
    this.choices,
    this.multiSelect = false,
  });

  final String qid;
  final String question;
  final List<String>? choices;
  final bool multiSelect;
}

/// A scheduled (cron) job as `cron.manage {action: "list"}` reports it.
class CronJob {
  CronJob({
    required this.id,
    required this.name,
    required this.schedule,
    this.prompt = '',
    this.enabled = true,
    this.state,
    this.nextRun,
    this.lastRun,
    this.lastStatus,
    this.lastError,
  });

  final String id;
  final String name;
  final String schedule;
  final String prompt;
  final bool enabled;
  final String? state;
  final DateTime? nextRun;
  final DateTime? lastRun;
  final String? lastStatus;
  final String? lastError;

  static DateTime? _date(Object? v) {
    if (v is num) return epochToDate(v);
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
    return null;
  }

  factory CronJob.fromJson(Map<String, dynamic> j) => CronJob(
    id: j['job_id']?.toString() ?? j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? 'Úloha',
    schedule: j['schedule']?.toString() ?? '?',
    prompt: j['prompt_preview']?.toString() ?? '',
    enabled: j['enabled'] != false,
    state: j['state']?.toString(),
    nextRun: _date(j['next_run_at']),
    lastRun: _date(j['last_run_at']),
    lastStatus: j['last_status']?.toString(),
    lastError: j['last_error']?.toString(),
  );
}
