import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Desktop = a freely resizable window driven by a mouse. Used only where the
/// right behaviour genuinely differs from touch — not for styling.
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

/// Whether the device can actually buzz. `HapticFeedback` is a silent no-op on
/// desktop, so we hide the setting rather than offer a switch that does
/// nothing.
bool get hasHaptics => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

/// Widest a column of text and controls gets before it stops being readable.
/// Past this the content is centred and the extra width becomes margin.
const double kContentMaxWidth = 900.0;

/// Real piano white keys are roughly six times taller than they are wide.
/// Anything much squatter reads as a toy, which is what happens when a
/// 15-key octave range is stretched across a 1440px window.
const double kWhiteKeyAspect = 5.5;

/// Practice screens fall back to a tighter layout when there isn't room for
/// the full one. Deliberately a function of height alone: a short macOS window
/// needs this exactly as much as a landscape phone does, and the old
/// platform-gated version could never fire on desktop.
bool isCompactLayout(double height) => height < 500;

/// Widest the on-screen keyboard should be drawn for a given height and white
/// key count, so keys keep something like piano proportions. Returns
/// [available] when there is less room than that — narrow windows still fill.
double maxKeyboardWidth({
  required double available,
  required double height,
  required int whiteKeyCount,
}) {
  if (whiteKeyCount <= 0 || height <= 0) return available;
  final ideal = whiteKeyCount * (height / kWhiteKeyAspect);
  return ideal < available ? ideal : available;
}

/// Centres [child] and caps its width at [kContentMaxWidth]. A no-op on a
/// phone; on a Mac window or an iPad it stops rows stretching edge to edge
/// with a label at one end and a control at the other.
class ContentColumn extends StatelessWidget {
  const ContentColumn({
    super.key,
    required this.child,
    this.maxWidth = kContentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}
