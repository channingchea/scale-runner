import 'package:flutter/material.dart';

/// Master switch for on-device beat-timing diagnostics. When true, the
/// beat-driven controllers record a short ring buffer of what happened at each
/// judged downbeat/press and the mode screens render it as a small overlay;
/// each line is also sent to the debug console. Flip to false (and rebuild) to
/// silence everything before shipping.
const bool kBeatDebug = false;

/// Emits [line] to the debug console, prefixed and gated by [kBeatDebug].
void beatDebug(String line) {
  if (kBeatDebug) debugPrint('[beat] $line');
}

/// Shared ring-buffer sink used by the controllers: keeps the most recent
/// [maxLines] entries (newest last) for the on-screen overlay and mirrors each
/// to the console. No-op when [kBeatDebug] is off, so callers can log freely.
class BeatDebugLog {
  static const int maxLines = 8;
  final List<String> lines = [];

  void add(String line) {
    if (!kBeatDebug) return;
    lines.add(line);
    if (lines.length > maxLines) lines.removeAt(0);
    beatDebug(line);
  }
}

/// A compact, non-interactive overlay that renders a [BeatDebugLog]'s recent
/// lines at the bottom of a mode screen. Meant to be dropped into a [Stack]
/// (it returns a [Positioned]); rebuilds whenever [listenable] notifies, so it
/// tracks the live controller. Only shown while [kBeatDebug] is true.
class BeatDebugOverlay extends StatelessWidget {
  const BeatDebugOverlay({
    super.key,
    required this.listenable,
    required this.log,
  });

  final Listenable listenable;
  final BeatDebugLog Function() log;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 4,
      right: 4,
      bottom: 4,
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: listenable,
          builder: (context, _) {
            final lines = log().lines;
            return Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                lines.isEmpty ? '[beat debug on: play to log]' : lines.join('\n'),
                style: const TextStyle(
                  color: Color(0xFF7CFC00),
                  fontSize: 9,
                  height: 1.25,
                  fontFamily: 'monospace',
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
