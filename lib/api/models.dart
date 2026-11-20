/// A Hermes profile — each profile is an independent agent ("bot").
class Bot {
  Bot({
    required this.name,
    required this.displayName,
    required this.description,
    this.model,
    this.provider,
    this.isDefault = false,
    this.skillCount = 0,
    this.gatewayRunning = false,
  });

  final String name;
  final String displayName;
  final String description;
  final String? model;
  final String? provider;
  final bool isDefault;
  final int skillCount;
  final bool gatewayRunning;

  factory Bot.fromJson(Map<String, dynamic> j) {
    String str(String k) => (j[k] as String?)?.trim() ?? '';
    final name = str('name');
    final display = str('display_name').isNotEmpty
        ? str('display_name')
        : (str('bot_title').isNotEmpty ? str('bot_title') : name);
    return Bot(
      name: name,
      displayName: display,
      description: str('description'),
      model: (j['model'] as String?)?.trim().isEmpty ?? true ? null : j['model'] as String,
      provider: j['provider'] as String?,
      isDefault: j['is_default'] == true,
      skillCount: (j['skill_count'] as num?)?.toInt() ?? 0,
      gatewayRunning: j['gateway_running'] == true,
    );
  }

  String get initials {
    final parts = displayName.split(RegExp(r'[\s_\-]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

enum ChatRole { user, assistant, notice, error }

enum ToolState { running, done, failed }

class ToolActivity {
  ToolActivity({required this.id, required this.name, this.preview});

  final String id;
  final String name;
  String? preview;
  String? summary;
  String? progress;
  double? durationS;
  ToolState state = ToolState.running;
}

class ChatMessage {
  ChatMessage({required this.role, this.text = '', this.streaming = false});

  final ChatRole role;
  String text;
  bool streaming;

  /// Tool calls the agent made while producing this reply.
  final List<ToolActivity> tools = [];

  /// Set when the turn ended as `interrupted`.
  bool interrupted = false;
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
  ClarifyQuestion({required this.qid, required this.question, this.choices, this.multiSelect = false});

  final String qid;
  final String question;
  final List<String>? choices;
  final bool multiSelect;
}
