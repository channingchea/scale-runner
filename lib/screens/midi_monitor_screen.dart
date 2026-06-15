import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../midi/midi_service.dart';
import '../theory/music_theory.dart';

// flutter_midi_command's MidiDevice, surfaced only here for the picker.
import 'package:flutter_midi_command/flutter_midi_command.dart' show MidiDevice;

/// MIDI device screen: lists devices, lets you connect (USB or Bluetooth),
/// and shows the last note played so you can confirm a keyboard works.
/// In debug builds it also shows the raw incoming packet log.
class MidiMonitorScreen extends StatefulWidget {
  const MidiMonitorScreen({super.key, required this.midi});

  final MidiService midi;

  @override
  State<MidiMonitorScreen> createState() => _MidiMonitorScreenState();
}

class _MidiMonitorScreenState extends State<MidiMonitorScreen> {
  List<MidiDevice> _devices = [];
  String? _lastNote;
  final List<String> _log = []; // debug builds only
  bool _loading = false;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    widget.midi.start();
    _subs.add(widget.midi.noteStream.listen((e) {
      if (e.isOn) _setLastNote(noteName(e.note));
      if (kDebugMode) _append(e.toString());
    }));
    if (kDebugMode) {
      _subs.add(widget.midi.rawStream.listen((raw) => _append('raw: $raw')));
    }
    // Re-scan whenever the OS reports a MIDI setup change (a BLE device
    // finishing discovery fires this) so newly-found keyboards appear.
    _subs.add(widget.midi.onSetupChanged.listen((event) {
      if (kDebugMode) _append('setup changed: $event');
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

  void _append(String line) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, line);
      if (_log.length > 200) _log.removeLast();
    });
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
            if (kDebugMode) ...[
              const SizedBox(height: 16),
              Text('Raw log (debug)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Expanded(child: _buildDebugLog()),
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

  Widget _buildDebugLog() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E13), // console: darker slate, never pure black
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: _log.isEmpty
          ? const Center(
              child: Text(
                'Play a key to see messages…',
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
          : ListView.builder(
              itemCount: _log.length,
              itemBuilder: (_, i) => Text(
                _log[i],
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: _log[i].startsWith('ON')
                      ? AppColors.correct
                      : AppColors.textSecondary,
                ),
              ),
            ),
    );
  }
}
