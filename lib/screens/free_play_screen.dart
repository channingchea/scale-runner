import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio/note_player.dart';
import '../midi/midi_service.dart';
import '../onboarding/mode_guides.dart';
import '../quiz/quiz_settings.dart';
import '../runner/free_play_controller.dart';
import '../runner/note_latch.dart';
import '../theme/app_theme.dart';
import '../theory/chord_namer.dart';
import '../theory/fretboard.dart';
import '../theory/voicings.dart' show kVoicingKeyboardLow, kVoicingKeyboardHigh;
import '../ui/responsive.dart';
import '../widgets/fret_box_stepper.dart';
import '../widgets/fretboard_view.dart' show FretboardLabels, TwinDotMode;
import '../widgets/instrument_surface.dart';
import '../widgets/mode_guide_sheet.dart';
import '../widgets/metronome_bar.dart';
import '../widgets/rotate_hint_banner.dart';

/// The instrument with no prompt, no score and no session. Whatever is
/// sounding is named live — a note, an interval, or a chord — on the piano
/// and on the neck alike, since the namer only ever sees MIDI numbers. The
/// metronome bar is a plain practice click here: nothing judges the timing.
class FreePlayScreen extends StatefulWidget {
  const FreePlayScreen({super.key, required this.midi});

  final MidiService midi;

  @override
  State<FreePlayScreen> createState() => _FreePlayScreenState();
}

class _FreePlayScreenState extends State<FreePlayScreen> {
  FreePlayController? _controller;
  QuizSettings? _settings;
  MetronomeController? _metronome;
  bool _noteSound = true;
  Instrument _instrument = Instrument.piano;
  bool _leftHanded = false;
  TwinDotMode _twinMode = TwinDotMode.primaryAndGhost;
  FretboardLabels _fretLabels = const FretboardLabels();

  /// The fretboard window, moved by the player like Voicing capture.
  FretBox _box = const FretBox(0);
  final NotePlayer _notes = NotePlayer();

  /// Arpeggiated Notes. On guitar the shape is kept as cells (one note per
  /// string) and handed to the controller as notes, so a tapped fret stays
  /// sounding where it was tapped.
  bool _arpeggiated = true;
  final GuitarLatch _guitarLatch = GuitarLatch();

  static const double _keyboardOctaves =
      (kVoicingKeyboardHigh - kVoicingKeyboardLow) / 12;

  /// Whether the guitar is taking taps as cells rather than as presses. Only
  /// then does a tapped fret stay sounding after the finger lifts.
  bool get _guitarLatching =>
      _arpeggiated && _instrument == Instrument.guitar;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _bootstrap();
    // First entry on this device shows the mode guide; "?" replays it.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => maybeShowGuide(context, GuideMode.freePlay));
  }

  Future<void> _bootstrap() async {
    final settings = await QuizSettings.load();
    final noteSound = await settings.noteSoundEnabled();
    final instrument = await settings.instrument();
    final leftHanded = await settings.leftHanded();
    final twinMode = await settings.guitarTwinMode();
    final fretLabels = await settings.fretboardLabels();
    final arpeggiated = await settings.arpeggiatedNotes();
    final metronome = MetronomeController(
      bpm: await settings.metronomeBpm(),
      onBpmChanged: settings.setMetronomeBpm,
      meter: await settings.meter(),
      onMeterChanged: settings.setMeter,
    )..hapticEnabled = await settings.tickHapticEnabled();
    final controller = FreePlayController(latchTaps: arpeggiated)
      ..onAnyPress = (note) {
        if (_noteSound) _notes.play(note);
      }
      ..bindMidi(widget.midi);
    if (!mounted) {
      controller.dispose();
      metronome.dispose();
      return;
    }
    setState(() {
      _settings = settings;
      _noteSound = noteSound;
      _instrument = instrument;
      _leftHanded = leftHanded;
      _twinMode = twinMode;
      _fretLabels = fretLabels;
      _arpeggiated = arpeggiated;
      _metronome = metronome;
      _controller = controller;
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _controller?.dispose();
    _metronome?.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    // Same shell as the quiz: no AppBar (it would eat kToolbarHeight on short
    // landscape phones), a thin icon row floated over the body instead.
    return Scaffold(
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    final bodyHeight = MediaQuery.of(context).size.height;
                    final compact = isCompactLayout(bodyHeight);
                    final maxKeyHeight = isDesktopPlatform ? 320.0 : 240.0;
                    final keyboardHeight = _instrument == Instrument.guitar &&
                            !compact
                        ? (bodyHeight * 0.62).clamp(280.0, bodyHeight * 0.72)
                        : compact
                            ? (bodyHeight * 0.40).clamp(120.0, maxKeyHeight)
                            : (bodyHeight * 0.46).clamp(140.0, maxKeyHeight);
                    return SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          const SizedBox(height: _topBarHeight),
                          if (_settings != null)
                            RotateHintBanner(settings: _settings!),
                          Expanded(
                            child: _buildReadout(controller, compact),
                          ),
                          _buildKeyboard(controller, keyboardHeight, compact),
                        ],
                      ),
                    );
                  },
                ),
                _buildTopBar(context),
              ],
            ),
    );
  }

  static const double _topBarHeight = 44;

  Widget _buildTopBar(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: _topBarHeight,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              color: AppColors.textPrimary,
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            // Balances the "?" button on the right so the click stays centred.
            const SizedBox(width: 48),
            const Spacer(),
            if (_metronome != null) MetronomeBar(controller: _metronome!),
            const Spacer(),
            // Same width as the back button so the click stays centred.
            SizedBox(
              width: 48,
              child: Icon(
                widget.midi.isConnected ? Icons.piano : Icons.touch_app,
                color: widget.midi.isConnected
                    ? AppColors.correct
                    : AppColors.textSecondary,
                size: 20,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.help_outline),
              color: AppColors.textPrimary,
              tooltip: 'Free Play guide',
              onPressed: () => ModeGuideSheet.show(context, GuideMode.freePlay),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadout(FreePlayController c, bool compact) {
    final readout = c.readout;
    final titleSize = compact ? 28.0 : (isDesktopPlatform ? 40.0 : 36.0);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: 20,
          vertical: compact ? 4 : 8,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: readout == null
                ? [
                    Text(
                      'Play anything',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textMuted,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: compact ? 6 : 10),
                    Text(
                      'Notes, intervals and chords are named as you play',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: compact ? 13 : 14,
                      ),
                    ),
                  ]
                : [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ShaderMask(
                        shaderCallback: (bounds) =>
                            AppColors.accentGradient.createShader(bounds),
                        child: Text(
                          readout.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: readout.kind == ReadoutKind.unmatched
                                ? titleSize * 0.6
                                : titleSize,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                    if (readout.detail case final detail?) ...[
                      SizedBox(height: compact ? 6 : 10),
                      Text(
                        detail,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compact ? 15 : 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeyboard(FreePlayController c, double height, bool compact) {
    final onGuitar = _instrument == Instrument.guitar;
    // The stepper follows the board like Voicing capture: beside a landscape
    // neck, above a portrait box.
    final neck = onGuitar && (compact || isDesktopPlatform);
    final surface = RepaintBoundary(
      child: InstrumentSurface(
        instrument: _instrument,
        lowMidi: kVoicingKeyboardLow,
        octaves: _keyboardOctaves,
        anchor: const [],
        box: onGuitar ? _box : null,
        feedbackFor: c.feedbackFor,
        isTargetHint: c.isTargetHint,
        onKeyDown: c.pressKey,
        onKeyUp: c.releaseKey,
        latched: _guitarLatching ? _guitarLatch.cells : null,
        onCellDown: _guitarLatching
            ? (cell) => setState(() => _guitarLatch.tapInto(c, cell))
            : null,
        compact: compact,
        leftHanded: _leftHanded,
        twinMode: _twinMode,
        labels: _fretLabels,
      ),
    );
    Widget stepper({required bool vertical}) => FretBoxStepper(
          box: _box,
          onChanged: (b) => setState(() => _box = b),
          vertical: vertical,
        );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: neck
            ? SizedBox(
                height: height,
                child: Row(
                  children: [
                    stepper(vertical: true),
                    Expanded(child: surface),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onGuitar) stepper(vertical: false),
                  SizedBox(
                    height: onGuitar ? height - FretBoxStepper.rowHeight : height,
                    child: surface,
                  ),
                ],
              ),
      ),
    );
  }
}
