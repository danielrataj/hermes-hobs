import 'strings.dart';

/// Czech language pack. Informal voice: the app is on first-name terms.
class StringsCs extends Strings {
  const StringsCs();

  @override
  String get code => 'cs';

  // --- login ---------------------------------------------------------------
  @override
  String get loginSubtitle => 'Přihlášení k Hermes Agent dashboardu';
  @override
  String get serverLabel => 'Server';
  @override
  String get serverInvalid => 'Zadej URL, např. https://hermes.devrel.cz';
  @override
  String get usernameLabel => 'Uživatel';
  @override
  String get passwordLabel => 'Heslo';
  @override
  String get fieldRequired => 'Povinné';
  @override
  String get rememberPassword => 'Zapamatovat heslo';
  @override
  String get signIn => 'Přihlásit';
  @override
  String get savedPasswordExpired =>
      'Uložené heslo už neplatí, přihlas se znovu.';

  // --- errors --------------------------------------------------------------
  @override
  String get errorBadCredentials => 'Neplatné jméno nebo heslo.';
  @override
  String get errorNoPasswordLogin =>
      'Server nepodporuje přihlášení heslem (provider "basic").';
  @override
  String get errorTooManyAttempts => 'Příliš mnoho pokusů, chvíli počkej.';
  @override
  String get errorServerDown => 'Server je nedostupný (503).';
  @override
  String errorServer(String message) => 'Chyba serveru: $message';
  @override
  String errorUnreachable(String message) => 'Server nedostupný: $message';
  @override
  String errorTls(String message) => 'TLS chyba: $message';
  @override
  String get errorTimeout => 'Vypršel časový limit.';
  @override
  String get errorBadServerUrl => 'Neplatná adresa serveru.';
  @override
  String get errorNoSessionCookie => 'Server nevrátil session cookie';

  // --- bot list ------------------------------------------------------------
  @override
  String get botsTitle => 'Boti';
  @override
  String get pickBot => 'Vyber bota vlevo';
  @override
  String get filterAll => 'Vše';
  @override
  String get filterUnread => 'Nepřečtené';
  @override
  String get filterPinned => 'Připnutí';
  @override
  String get filterActive => 'Aktivní';
  @override
  String get filterRecent => 'Nedávno';
  @override
  String get filterOlder => 'Starší';
  @override
  String get account => 'Účet';
  @override
  String get settings => 'Nastavení';
  @override
  String get signOut => 'Odhlásit';
  @override
  String get searchBots => 'Hledat boty';
  @override
  String get retry => 'Zkusit znovu';
  @override
  String get noBots => 'Na serveru nejsou žádní boti.';
  @override
  String get noMatches => 'Filtru nic neodpovídá.';
  @override
  String get working => 'pracuje';
  @override
  String get noMessagesYet => 'Zatím bez zpráv';
  @override
  String get connected => 'Připojeno';
  @override
  String get connecting => 'Připojuji…';
  @override
  String get disconnected => 'Odpojeno';
  @override
  String get folderFallback => 'Složka';
  @override
  String get unassigned => 'Nezařazení';
  @override
  String get renameFolder => 'Přejmenovat';
  @override
  String get renameFolderTitle => 'Přejmenovat složku';
  @override
  String get folderNameLabel => 'Název složky';
  @override
  String get save => 'Uložit';
  @override
  String get cancel => 'Zrušit';
  @override
  String get renameFolderFailed =>
      'Složku se nepodařilo přejmenovat. Zkuste to znovu.';
  @override
  String get folderOptions => 'Možnosti složky';
  @override
  String get moveFolder => 'Přesunout složku';

  // --- chat ----------------------------------------------------------------
  @override
  String get scheduledJobs => 'Naplánované úlohy';
  @override
  String get connectionLost =>
      'Spojení se serverem přerušeno, připojuji znovu…';
  @override
  String get reconnectNow => 'Teď';
  @override
  String newMessages(int n) => switch (n) {
    1 => '1 nová',
    2 || 3 || 4 => '$n nové',
    _ => '$n nových',
  };
  @override
  String get jumpToEnd => 'Na konec';
  @override
  String get tryAgain => 'Znovu';
  @override
  String get openingChat => 'Otevírám Bot Chat…';
  @override
  String workingOn(String? status) =>
      status != null ? 'pracuje · $status' : 'pracuje…';
  @override
  String get workingInBackground => 'pracuje na pozadí';
  @override
  String activeAgo(String age) => 'aktivní $age';
  @override
  String writeTo(String bot) => 'Napiš zprávu pro $bot';
  @override
  String get interruptedTag => 'přerušeno';
  @override
  String get copy => 'Kopírovat';
  @override
  String get copied => 'Zkopírováno';
  @override
  String get thinking => 'Přemýšlí…';
  @override
  String get messageHint => 'Napiš zprávu';
  @override
  String get stop => 'Zastavit';
  @override
  String get send => 'Odeslat';
  @override
  String get modelTooltip => 'Model bota (mění se v profilu)';
  @override
  String get reasoningLevel => 'Úroveň uvažování';
  @override
  String get reasoning => 'Uvažování';
  @override
  String get approvalModeTooltip =>
      'Schvalování nebezpečných příkazů (platí pro celého bota)';
  @override
  String approvalModeLabel(String mode) => switch (mode) {
    'manual' => 'Ručně',
    'smart' => 'Chytře',
    'off' => 'Bez ptaní',
    _ => 'Schvalování',
  };
  @override
  String approvalModeHint(String mode) => switch (mode) {
    'manual' => 'Na každý nebezpečný příkaz se zeptá',
    'smart' => 'Bezpečné schválí sám, ptá se jen u rizikových',
    'off' => 'Nic neschvaluje, spouští vše hned',
    _ => mode,
  };
  @override
  String approvalTitle(String? tool) =>
      'Bot žádá o schválení${tool != null ? ' ($tool)' : ''}';
  @override
  String get allowOnce => 'Povolit jednou';
  @override
  String get allowSession => 'Povolit v konverzaci';
  @override
  String get allowAlways => 'Povolit vždy';
  @override
  String get deny => 'Zamítnout';
  @override
  String get botAsks => 'Bot se ptá';
  @override
  String get orOwnAnswer => 'nebo vlastní odpověď';
  @override
  String get answerHint => 'Odpověď';
  @override
  String get skip => 'Přeskočit';
  @override
  String get answer => 'Odpovědět';

  @override
  String? toolLabel(String tool) => switch (tool) {
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
    _ => null,
  };

  // --- chat state ----------------------------------------------------------
  @override
  String openChatFailed(Object e) => 'Nepodařilo se otevřít konverzaci: $e';
  @override
  String recoverFailed(Object e) => 'Obnovení po výpadku spojení selhalo: $e';
  @override
  String get chatNotReady => 'Konverzace není připravená.';
  @override
  String interruptFailed(Object e) => 'Přerušení selhalo: $e';
  @override
  String reasoningChangeFailed(Object e) =>
      'Změna úrovně uvažování selhala: $e';
  @override
  String approvalModeChangeFailed(Object e) =>
      'Změna režimu schvalování selhala: $e';
  @override
  String approvalAnswerFailed(Object e) => 'Odpověď na schválení selhala: $e';
  @override
  String clarifyAnswerFailed(Object e) => 'Odpověď na dotaz selhala: $e';
  @override
  String preparingTool(String? tool) => 'Připravuje ${tool ?? 'nástroj'}…';
  @override
  String get unknownError => 'Neznámá chyba';
  @override
  String get interruptedNotice => 'Přerušeno';
  @override
  String get replyFailed => 'Odpověď skončila chybou';

  // --- scheduled jobs ------------------------------------------------------
  @override
  String get refresh => 'Obnovit';
  @override
  String jobsLoadFailed(Object? e) => 'Úlohy se nepodařilo načíst: $e';
  @override
  String get noJobs => 'Bot nemá žádné naplánované úlohy.';
  @override
  String nextRun(String when) => 'Další běh: $when';
  @override
  String get paused => 'Pozastaveno';
  @override
  String lastRun(String when) => 'Poslední běh: $when';
  @override
  String get failedTag => 'chyba';
  @override
  String get jobFallback => 'Úloha';

  // --- settings ------------------------------------------------------------
  @override
  String get language => 'Jazyk';
  @override
  String get languageSystem => 'Podle zařízení';
  @override
  String languageSystemNow(String name) => 'Teď: $name';
  @override
  String get languageName => 'Čeština';

  // --- dates ---------------------------------------------------------------
  @override
  String get now => 'teď';
  @override
  String get today => 'dnes';
  @override
  String get tomorrow => 'zítra';
  @override
  String get yesterday => 'včera';
  @override
  String shortDate(DateTime t) => '${t.day}. ${t.month}.';
}
