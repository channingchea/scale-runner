import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_midi_command/flutter_midi_command.dart';

/// A single Note On / Note Off event, decoded from the raw MIDI byte stream.
class MidiNoteEvent {
  final int note; // MIDI note number 0-127
  final int velocity; // 0-127
  final bool isOn; // true = Note On (key pressed)

  const MidiNoteEvent(this.note, this.velocity, this.isOn);

  @override
  String toString() => '${isOn ? "ON " : "OFF"} note=$note vel=$velocity';
}

/// Wraps `flutter_midi_command` so the rest of the app never imports the
/// package directly. Responsibilities:
///  - discover and connect/disconnect MIDI devices,
///  - decode the raw byte stream into clean [MidiNoteEvent]s,
///  - expose a debug log of raw packets for the MIDI monitor screen.
///
/// All MIDI parsing lives here; the quiz logic just listens to [noteStream].
class MidiService {
  final MidiCommand _midi = MidiCommand();

  /// Native bridge to Apple's CABTMIDICentralViewController (iOS only).
  static const _ble = MethodChannel('scale_runner/ble_midi');

  bool get _isIOS => !kIsWeb && Platform.isIOS;

  final _noteController = StreamController<MidiNoteEvent>.broadcast();
  final _rawController = StreamController<String>.broadcast();

  StreamSubscription<MidiPacket>? _rxSub;
  MidiDevice? _connected;

  /// Clean stream of decoded Note On/Off events for the quiz to consume.
  Stream<MidiNoteEvent> get noteStream => _noteController.stream;

  /// Human-readable raw packet strings for the debug monitor.
  Stream<String> get rawStream => _rawController.stream;

  MidiDevice? get connectedDevice => _connected;
  bool get isConnected => _connected != null;

  /// Begin listening to the global MIDI receive stream. Safe to call once at
  /// startup; individual devices are then connected via [connect].
  void start() {
    _rxSub ??= _midi.onMidiDataReceived?.listen(_handlePacket);
  }

  /// List currently visible MIDI devices (USB + already-paired BLE).
  Future<List<MidiDevice>> devices() async {
    final list = await _midi.devices;
    return list ?? <MidiDevice>[];
  }

  /// Open Apple's Bluetooth-MIDI central UI (iOS) to pair a BLE keyboard.
  ///
  /// On iOS we present Apple's own CABTMIDICentralViewController (the sheet
  /// GarageBand uses) via a native channel — flutter_midi_command's
  /// startBluetoothCentral() only scans headlessly and rarely surfaces the
  /// device. On other platforms we fall back to the plugin's central.
  /// May throw - caller should guard.
  Future<void> startBluetoothCentral() async {
    if (_isIOS) {
      await _midi.startBluetoothCentral(); // power on the central first
      await _ble.invokeMethod('showBluetoothPairing');
    } else {
      await _midi.startBluetoothCentral();
    }
  }

  /// Stream of device-change notifications (connect/disconnect/discovery).
  Stream<String>? get onSetupChanged => _midi.onMidiSetupChanged;

  Future<void> connect(MidiDevice device) async {
    if (_connected != null) {
      _midi.disconnectDevice(_connected!);
      _connected = null;
      // Let the native side finish tearing down the old connection before
      // opening a new one — avoids connecting to a device mid-teardown.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await _midi.connectToDevice(device);
    _connected = device;
  }

  void disconnect() {
    if (_connected != null) {
      _midi.disconnectDevice(_connected!);
      _connected = null;
    }
  }

  void _handlePacket(MidiPacket packet) {
    final data = packet.data;
    if (data.isEmpty) return;
    _rawController
        .add(data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '));

    // MIDI status byte: high nibble = message type, low nibble = channel.
    final status = data[0] & 0xF0;
    if (data.length < 3) return;
    final note = data[1];
    final velocity = data[2];

    // 0x90 = Note On, 0x80 = Note Off. A Note On with velocity 0 is, by
    // convention, a Note Off (running-status keyboards do this).
    if (status == 0x90 && velocity > 0) {
      _noteController.add(MidiNoteEvent(note, velocity, true));
    } else if (status == 0x80 || (status == 0x90 && velocity == 0)) {
      _noteController.add(MidiNoteEvent(note, 0, false));
    }
  }

  void dispose() {
    _rxSub?.cancel();
    disconnect();
    _noteController.close();
    _rawController.close();
  }
}
