/// Compact relative age like the dashboard roster: "teď", "56m", "2h", "3d".
String relativeAge(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'teď';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays < 30) return '${d.inDays}d';
  return '${t.day}. ${t.month}.';
}

String clockTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "dnes 9:00", "zítra 9:00", or "23. 11. 9:00".
String dayTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = day.difference(today).inDays;
  final prefix = switch (diff) {
    0 => 'dnes',
    1 => 'zítra',
    -1 => 'včera',
    _ => '${t.day}. ${t.month}.',
  };
  return '$prefix ${clockTime(t)}';
}

/// One-line preview: drop markdown emphasis and collapse whitespace.
String plainPreview(String s) => s
    .replaceAll(RegExp(r'[*_`#>]+'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
