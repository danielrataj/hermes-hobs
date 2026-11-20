import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pull-to-refresh for a reversed list (a chat): dragging past the newest
/// message, at the bottom edge, runs [onReload].
///
/// [RefreshIndicator] arms only at the far end of a reversed list, which in a
/// chat is the oldest message, so it cannot be used here.
class PullUpReload extends StatefulWidget {
  const PullUpReload({super.key, required this.onReload, required this.child});

  final Future<void> Function() onReload;
  final Widget child;

  /// Overscroll past the bottom edge that arms the reload.
  static const threshold = 64.0;

  @override
  State<PullUpReload> createState() => _PullUpReloadState();
}

class _PullUpReloadState extends State<PullUpReload> {
  double _pull = 0;
  bool _loading = false;

  bool _onNotification(ScrollNotification n) {
    if (n.depth != 0 || _loading || n.metrics.axis != Axis.vertical) {
      return false;
    }
    final byFinger = switch (n) {
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      OverscrollNotification(:final dragDetails) => dragDetails != null,
      _ => false,
    };
    if (!byFinger) {
      // Finger lifted (bounce-back or scroll end): fire if armed.
      if (_pull > 0 &&
          (n is ScrollUpdateNotification || n is ScrollEndNotification)) {
        _release();
      }
      return false;
    }
    // In a reversed list the newest message sits at minScrollExtent.
    final past = n.metrics.minScrollExtent - n.metrics.pixels;
    if (n is OverscrollNotification) {
      // Clamping physics: the position stays put, the overscroll is reported.
      if (n.overscroll < 0) _setPull(_pull - n.overscroll);
    } else if (past > 0) {
      // Bouncing physics: the position itself runs past the edge.
      _setPull(past);
    } else if (past < 0) {
      _setPull(0);
    }
    return false;
  }

  void _setPull(double value) {
    if (value != _pull) setState(() => _pull = value);
  }

  Future<void> _release() async {
    if (_pull < PullUpReload.threshold) {
      _setPull(0);
      return;
    }
    setState(() {
      _pull = 0;
      _loading = true;
    });
    try {
      await widget.onReload();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = math.min(_pull / PullUpReload.threshold, 1.0);
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: Stack(
        children: [
          widget.child,
          if (_loading || _pull > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Center(
                child: Opacity(
                  opacity: _loading ? 1 : progress,
                  child: Material(
                    elevation: 2,
                    shape: const CircleBorder(),
                    color: cs.surfaceContainerHigh,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          value: _loading ? null : progress,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
