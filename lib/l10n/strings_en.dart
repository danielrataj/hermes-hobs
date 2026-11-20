import 'strings.dart';

/// English language pack. Same voice as the Czech one: short, plain, casual.
class StringsEn extends Strings {
  const StringsEn();

  @override
  String get code => 'en';

  // --- login ---------------------------------------------------------------
  @override
  String get loginSubtitle => 'Sign in to your Hermes Agent dashboard';
  @override
  String get serverLabel => 'Server';
  @override
  String get serverInvalid => 'Enter a URL, like https://hermes.devrel.cz';
  @override
  String get usernameLabel => 'Username';
  @override
  String get passwordLabel => 'Password';
  @override
  String get fieldRequired => 'Required';
  @override
  String get rememberPassword => 'Remember password';
  @override
  String get signIn => 'Sign in';
  @override
  String get savedPasswordExpired =>
      'Your saved password no longer works. Sign in again.';

  // --- errors --------------------------------------------------------------
  @override
  String get errorBadCredentials => 'Wrong username or password.';
  @override
  String get errorNoPasswordLogin =>
      'This server doesn\'t allow password sign-in (provider "basic").';
  @override
  String get errorTooManyAttempts => 'Too many attempts. Wait a moment.';
  @override
  String get errorServerDown => 'The server is unavailable (503).';
  @override
  String errorServer(String message) => 'Server error: $message';
  @override
  String errorUnreachable(String message) =>
      'Can\'t reach the server: $message';
  @override
  String errorTls(String message) => 'TLS error: $message';
  @override
  String get errorTimeout => 'The request timed out.';
  @override
  String get errorBadServerUrl => 'That server address isn\'t valid.';
  @override
  String get errorNoSessionCookie =>
      'The server didn\'t return a session cookie';

  // --- bot list ------------------------------------------------------------
  @override
  String get botsTitle => 'Bots';
  @override
  String get pickBot => 'Pick a bot on the left';
  @override
  String get filterAll => 'All';
  @override
  String get filterUnread => 'Unread';
  @override
  String get filterPinned => 'Pinned';
  @override
  String get filterActive => 'Active';
  @override
  String get filterRecent => 'Recent';
  @override
  String get filterOlder => 'Older';
  @override
  String unreadCount(int n) => 'Unread: $n';
  @override
  String get noUnread => 'Nothing unread';
  @override
  String get settings => 'Settings';
  @override
  String get signOut => 'Sign out';
  @override
  String get searchBots => 'Search bots';
  @override
  String get retry => 'Try again';
  @override
  String get noBots => 'This server has no bots yet.';
  @override
  String get noMatches => 'No bots match this filter.';
  @override
  String get working => 'working';
  @override
  String get noMessagesYet => 'No messages yet';
  @override
  String get connected => 'Connected';
  @override
  String get connecting => 'Connecting…';
  @override
  String get disconnected => 'Disconnected';
  @override
  String get folderFallback => 'Folder';
  @override
  String get unassigned => 'Unsorted';

  // --- chat ----------------------------------------------------------------
  @override
  String get scheduledJobs => 'Scheduled jobs';
  @override
  String get connectionLost =>
      'Lost the connection to the server. Reconnecting…';
  @override
  String get reconnectNow => 'Now';
  @override
  String newMessages(int n) => '$n new';
  @override
  String get jumpToEnd => 'Jump to latest';
  @override
  String get tryAgain => 'Retry';
  @override
  String get openingChat => 'Opening Bot Chat…';
  @override
  String workingOn(String? status) =>
      status != null ? 'working · $status' : 'working…';
  @override
  String get workingInBackground => 'working in the background';
  @override
  String activeAgo(String age) => 'active $age';
  @override
  String writeTo(String bot) => 'Send $bot a message';
  @override
  String get interruptedTag => 'stopped';
  @override
  String get copy => 'Copy';
  @override
  String get copied => 'Copied';
  @override
  String get thinking => 'Thinking…';
  @override
  String get messageHint => 'Write a message';
  @override
  String get stop => 'Stop';
  @override
  String get send => 'Send';
  @override
  String get modelTooltip => 'The bot\'s model (change it in the profile)';
  @override
  String get reasoningLevel => 'Reasoning level';
  @override
  String get reasoning => 'Reasoning';
  @override
  String approvalTitle(String? tool) =>
      'The bot needs your approval${tool != null ? ' ($tool)' : ''}';
  @override
  String get allowOnce => 'Allow once';
  @override
  String get allowSession => 'Allow in this chat';
  @override
  String get allowAlways => 'Always allow';
  @override
  String get deny => 'Deny';
  @override
  String get botAsks => 'The bot has a question';
  @override
  String get orOwnAnswer => 'or write your own answer';
  @override
  String get answerHint => 'Your answer';
  @override
  String get skip => 'Skip';
  @override
  String get answer => 'Answer';

  @override
  String? toolLabel(String tool) => switch (tool) {
    'message_agent' || 'send_message' => 'message to agent',
    'skill_view' || 'skills_list' || 'skill_load' => 'skill',
    'terminal' || 'execute_code' => 'command',
    'web_search' => 'web search',
    'web_extract' || 'browser_navigate' => 'web',
    'read_file' || 'search_files' => 'files',
    'write_file' || 'patch' => 'file edit',
    'clarify' => 'question',
    'cronjob' => 'scheduled job',
    'todo' => 'to-dos',
    'memory' => 'memory',
    'delegate_task' => 'delegation',
    _ => null,
  };

  // --- chat state ----------------------------------------------------------
  @override
  String openChatFailed(Object e) => 'Couldn\'t open the chat: $e';
  @override
  String recoverFailed(Object e) =>
      'Couldn\'t restore the chat after the connection dropped: $e';
  @override
  String get chatNotReady => 'The chat isn\'t ready yet.';
  @override
  String interruptFailed(Object e) => 'Couldn\'t stop the bot: $e';
  @override
  String reasoningChangeFailed(Object e) =>
      'Couldn\'t change the reasoning level: $e';
  @override
  String approvalAnswerFailed(Object e) => 'Couldn\'t send your approval: $e';
  @override
  String clarifyAnswerFailed(Object e) => 'Couldn\'t send your answer: $e';
  @override
  String preparingTool(String? tool) => 'Preparing ${tool ?? 'a tool'}…';
  @override
  String get unknownError => 'Unknown error';
  @override
  String get interruptedNotice => 'Stopped';
  @override
  String get replyFailed => 'The reply ended with an error';

  // --- scheduled jobs ------------------------------------------------------
  @override
  String get refresh => 'Refresh';
  @override
  String jobsLoadFailed(Object? e) => 'Couldn\'t load the jobs: $e';
  @override
  String get noJobs => 'This bot has no scheduled jobs.';
  @override
  String nextRun(String when) => 'Next run: $when';
  @override
  String get paused => 'Paused';
  @override
  String lastRun(String when) => 'Last run: $when';
  @override
  String get failedTag => 'failed';
  @override
  String get jobFallback => 'Job';

  // --- settings ------------------------------------------------------------
  @override
  String get language => 'Language';
  @override
  String get languageSystem => 'Same as device';
  @override
  String languageSystemNow(String name) => 'Now: $name';
  @override
  String get languageName => 'English';

  // --- dates ---------------------------------------------------------------
  @override
  String get now => 'now';
  @override
  String get today => 'today';
  @override
  String get tomorrow => 'tomorrow';
  @override
  String get yesterday => 'yesterday';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  String shortDate(DateTime t) => '${t.day} ${_months[t.month - 1]}';
}
