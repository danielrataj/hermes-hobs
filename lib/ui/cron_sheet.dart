import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'format.dart';

/// The bot's scheduled jobs (dashboard's "Scheduled jobs" rail), read-only.
Future<void> showCronSheet(BuildContext context, Bot bot) {
  final app = context.read<AppState>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (context, scroll) =>
          _CronList(app: app, bot: bot, scroll: scroll),
    ),
  );
}

class _CronList extends StatefulWidget {
  const _CronList({required this.app, required this.bot, required this.scroll});

  final AppState app;
  final Bot bot;
  final ScrollController scroll;

  @override
  State<_CronList> createState() => _CronListState();
}

class _CronListState extends State<_CronList> {
  late Future<List<CronJob>> _jobs = widget.app.cronJobs(widget.bot);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    return FutureBuilder<List<CronJob>>(
      future: _jobs,
      builder: (context, snap) {
        final header = Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${s.scheduledJobs} · ${widget.bot.displayName}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: s.refresh,
                onPressed: () =>
                    setState(() => _jobs = widget.app.cronJobs(widget.bot)),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        );
        Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (snap.hasError) {
          body = Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              s.jobsLoadFailed(snap.error),
              style: TextStyle(color: cs.error),
            ),
          );
        } else if (snap.data!.isEmpty) {
          body = Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              s.noJobs,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          );
        } else {
          body = Column(
            children: [for (final j in snap.data!) _JobTile(job: j)],
          );
        }
        return ListView(controller: widget.scroll, children: [header, body]);
      },
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job});

  final CronJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final paused = !job.enabled || job.state == 'paused';
    final failed =
        job.lastStatus == 'error' ||
        job.lastStatus == 'failed' ||
        job.lastError != null;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return ListTile(
      leading: Icon(
        paused ? Icons.pause_circle_outline : Icons.schedule,
        color: paused ? cs.outline : cs.primary,
      ),
      title: Text(job.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(job.schedule, style: muted),
          if (!paused && job.nextRun != null)
            Text(s.nextRun(dayTime(job.nextRun!)), style: muted),
          if (paused) Text(s.paused, style: muted),
          if (job.lastRun != null)
            Text(
              '${s.lastRun(dayTime(job.lastRun!))}${failed ? ' · ${s.failedTag}' : ''}',
              style: muted?.copyWith(color: failed ? cs.error : null),
            ),
        ],
      ),
      isThreeLine: true,
    );
  }
}
