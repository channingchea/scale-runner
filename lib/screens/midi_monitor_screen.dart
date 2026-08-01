import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../midi/midi_service.dart';
import '../theory/music_theory.dart';
import 'latency_calibration_screen.dart';

// flutter_midi_command's MidiDevice, surfaced only here for the picker.
import 'package:flutter_midi_command/flutter_midi_command.dart' show MidiDevice;

/// MIDI device screen: lists devices, lets you connect (USB or Bluetooth),
/// and shows the last note played so you can confirm a keyboard works.
class MidiMonitorScreen extends StatefulWidget {
  const MidiMonitorScreen({super.key, required this.midi});

  final MidiService midi;

  @override
  State<MidiMonitorScreen> createState() => _MidiMonitorScreenState();
}

class _MidiMonitorScreenState extends State<MidiMonitorScreen> {
  List<MidiDevice> _devices = [];
  String? _lastNote;
  bool _loading = false;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    widget.midi.start();
    _subs.add(widget.midi.noteStream.listen((e) {
      if (e.isOn) _setLastNote(noteName(e.note));
    }));
    // Re-scan whenever the OS reports a MIDI setup change (a BLE device
    // finishing discovery fires this) so newly-found keyboards appear.
    _subs.add(widget.midi.onSetupChanged.listen((event) {
      _refresh();
    }));
    _refresh();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _setLastNote(String name) {
    if (!mounted) return;
    setState(() => _lastNote = name);
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final devices = await widget.midi.devices();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _loading = false;
    });
  }

  Future<void> _calibrate() async {
    final calibrated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LatencyCalibrationScreen(
          device: widget.midi.connectedDevice!,
          midi: widget.midi,
        ),
      ),
    );
    if (!mounted) return;
    if (calibrated == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Calibration complete! Timing offsets for your '
            'device will be applied to scoring automatically.',
          ),
        ),
      );
    }
  }

  Future<void> _connect(MidiDevice d) async {
    await widget.midi.connect(d);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Connected to ${d.name}')),
    );
  }

  Future<void> _pairBluetooth() async {
    try {
      await widget.midi.startBluetoothCentral();
      await _refresh();
      // BLE discovery is async; the immediate scan above is usually too early.
      // Rescan a few times over the next several seconds to catch the device.
      for (final secs in const [1, 3, 6, 10]) {
        Future.delayed(Duration(seconds: secs), () {
          if (mounted) _refresh();
        });
      }
    } catch (e, st) {
      debugPrint('Bluetooth pairing failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bluetooth error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MIDI Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth),
            tooltip: 'Pair Bluetooth MIDI',
            onPressed: _pairBluetooth,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan devices',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Devices', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_loading) const LinearProgressIndicator(),
            if (!_loading && _devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No MIDI devices found. Connect a USB keyboard or pair over '
                  'Bluetooth, then rescan.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ..._devices.map((d) {
              final connected = widget.midi.connectedDevice?.id == d.id;
              return Card(
                child: ListTile(
                  leading: Icon(
                    connected ? Icons.piano : Icons.piano_outlined,
                    color: connected ? AppColors.correct : AppColors.textSecondary,
                  ),
                  title: Text(d.name),
                  subtitle: Text(d.type),
                  trailing: connected
                      ? const Text('Connected',
                          style: TextStyle(color: AppColors.correct))
                      : const Icon(Icons.chevron_right),
                  onTap: connected ? null : () => _connect(d),
                ),
              );
            }),
            const SizedBox(height: 16),
            Text('Test your keyboard',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _buildNoteTester(),
            if (widget.midi.connectedDevice != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _calibrate,
                  icon: const Icon(Icons.timer),
                  label: const Text('Calibrate Timing'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Friendly connection check: shows the name of the last key played.
  Widget _buildNoteTester() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _lastNote != null ? AppColors.correct : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          Text(
            _lastNote ?? '—',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: _lastNote != null
                  ? AppColors.correct
                  : AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _lastNote != null
                ? 'Keyboard working!'
                : 'Play a key to test the connection',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
