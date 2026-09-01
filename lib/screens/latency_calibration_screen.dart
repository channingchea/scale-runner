import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart' show MidiDevice;
import '../midi/midi_service.dart';
import '../quiz/quiz_settings.dart';
import '../widgets/metronome_bar.dart';

class LatencyCalibrationScreen extends StatefulWidget {
  const LatencyCalibrationScreen({
    super.key,
    required this.device,
    required this.midi,
  });

  final MidiDevice device;
  final MidiService midi;

  @override
  State<LatencyCalibrationScreen> createState() =>
      _LatencyCalibrationScreenState();
}

class _LatencyCalibrationScreenState extends State<LatencyCalibrationScreen> {
  late final MetronomeController _metronome;
  StreamSubscription? _midiSub;
  final List<int> _offsets = [];
  int? _medianOffset;

  /// Tightest and widest tap of the run. A single median hides a wandering
  /// offset; showing the range lets the player see whether their keyboard's
  /// delay is actually stable enough for one constant to correct.
  int? _minOffset;
  int? _maxOffset;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _metronome = MetronomeController(
      bpm: 100, // A comfortable, steady BPM for calibration
      onBpmChanged: (bpm) {}, // Fixed BPM for calibration
    );
    _metronome.inputLatencyMs = 0; // We want raw offset
    _metronome.start();

    _midiSub = widget.midi.noteStream.listen((event) {
      if (!mounted) return;
      if (event.isOn && event.velocity > 0) {
        _handleTap();
      }
    });
  }

  @override
  void dispose() {
    _metronome.dispose();
    _midiSub?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (_medianOffset != null) return; // Already calibrated
    if (!_metronome.running) return;

    final period = _metronome.beatPeriodMs;
    final since = _metronome.msSinceLastTick;
    final offset = since <= period ~/ 2 ? since : since - period;

    setState(() {
      _offsets.add(offset);
      if (_offsets.length >= 8) {
        // Signed median = the full sound-to-event offset. Because the player
        // taps along to the *audible* click, this number also absorbs audio
        // output latency (the click leaves the speaker after we trigger it),
        // not just input/BLE delay. A negative median is kept, not clamped:
        // it means events land on/ahead of the click on a low-latency path,
        // and subtracting that negative in the judge is exactly what stops
        // on-beat presses from reading late.
        final sorted = List<int>.from(_offsets)..sort();
        _medianOffset = sorted[sorted.length ~/ 2];
        _minOffset = sorted.first;
        _maxOffset = sorted.last;
        _metronome.stop(); // Stop metronome when done
      }
    });
  }

  Future<void> _saveAndClose() async {
    if (_medianOffset == null) return;
    setState(() => _saving = true);
    final settings = await QuizSettings.load();
    await settings.setInputLatencyMs(widget.device.name, _medianOffset!);
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  void _reset() {
    setState(() {
      _offsets.clear();
      _medianOffset = null;
      _minOffset = null;
      _maxOffset = null;
    });
    _metronome.start();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calibrate Timing'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Calibrating: ${widget.device.name}',
                style: textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                'Play any key on your keyboard in time with the metronome.',
                style: textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              if (_medianOffset == null) ...[
                Text(
                  'Taps: ${_offsets.length} / 8',
                  style: textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _offsets.length / 8.0,
                ),
                const Spacer(),
                const Text(
                  'Keep tapping...',
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                Text(
                  'Timing Offset',
                  style: textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '${_medianOffset}ms',
                  style: textTheme.displayMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your 8 taps ranged $_minOffset\u2013${_maxOffset}ms.'
                  '${(_maxOffset! - _minOffset!) > 60 ? ' That spread is wide '
                      'enough that one fixed correction can only get you close '
                      '\u2014 retry somewhere quieter, or with wired audio.' : ''}',
                  style: textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _reset,
                        child: const Text('Retry'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _saveAndClose,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
