import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
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

  /// Rebroadcasts the plugin's single-subscription setup stream so multiple
  /// screens can listen. We subscribe to the plugin ONCE (in [start]) and fan
  /// out here; subscribing the plugin stream more than once throws.
  final _setupController = StreamController<String>.broadcast();

  StreamSubscription<MidiPacket>? _rxSub;
  StreamSubscription<String>? _setupSub;
  MidiDevice? _connected;

  /// Id + name of the last device the user connected to. Retained across
  /// unplugs so the same keyboard auto-reconnects when it reappears. USB MIDI
  /// devices often re-enumerate with a fresh id, so we match on either id or
  /// name. Cleared only by an explicit [disconnect].
  String? _lastDeviceId;
  String? _lastDeviceName;

  /// Clean stream of decoded Note On/Off events for the quiz to consume.
  Stream<MidiNoteEvent> get noteStream => _noteController.stream;

  /// Human-readable raw packet strings for the debug monitor.
  Stream<String> get rawStream => _rawController.stream;

  MidiDevice? get connectedDevice => _connected;
  bool get isConnected => _connected != null;

  /// Begin listening to the global MIDI receive + setup streams. Safe to call
  /// repeatedly; both subscriptions are created once. Subscribing the plugin's
  /// streams more than once throws, so all fan-out goes through our broadcast
  /// controllers ([noteStream], [rawStream], [onSetupChanged]).
  void start() {
    _rxSub ??= _midi.onMidiDataReceived?.listen(_handlePacket);
    _setupSub ??= _midi.onMidiSetupChanged?.listen(_handleSetupChanged);
  }

  /// Single internal handler for every OS MIDI setup change. Reconciles
  /// connection state, auto-reconnects a replugged device, then notifies UI.
  /// Runs regardless of whether any screen is currently listening.
  Future<void> _handleSetupChanged(String event) async {
    await refreshConnectionState();
    await _tryAutoReconnect();
    if (!_setupController.isClosed) _setupController.add(event);
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

  /// Broadcast stream of device-change notifications (connect/disconnect/
  /// discovery). Fans out the single internal subscription set up in [start],
  /// so any number of screens can listen. Connection-state reconciliation and
  /// auto-reconnect already ran in [_handleSetupChanged] before each event.
  Stream<String> get onSetupChanged => _setupController.stream;

  /// Clear [_connected] if the tracked device is no longer present (or now
  /// reports disconnected) in the live MIDI device list.
  Future<void> refreshConnectionState() async {
    if (_connected == null) return;
    final live = await devices();
    final stillThere = live.any(
      (d) => d.id == _connected!.id && d.connected,
    );
    if (!stillThere) _connected = null;
  }

  /// If nothing is connected but the last-used device has reappeared in the
  /// live list, silently reconnect to it. Lets a replugged keyboard come back
  /// without the user re-picking it.
  Future<void> _tryAutoReconnect() async {
    if (_connected != null || _lastDeviceId == null) return;
    final live = await devices();
    MidiDevice? match;
    for (final d in live) {
      // Prefer an id match; fall back to name for devices that re-enumerate
      // with a new id on replug.
      if (d.id == _lastDeviceId || d.name == _lastDeviceName) {
        match = d;
        break;
      }
    }
    if (match != null) await connect(match);
  }

  Future<void> connect(MidiDevice device) async {
    // On USB replug the device often comes back already connected at the
    // native layer (our Dart state was cleared on unplug, but the port was
    // never actually torn down). Re-connecting it throws "Device already
    // connected", so just adopt it.
    if (device.connected) {
      _connected = device;
      _lastDeviceId = device.id;
      _lastDeviceName = device.name;
      return;
    }
    if (_connected != null) {
      _midi.disconnectDevice(_connected!);
      _connected = null;
      // Let the native side finish tearing down the old connection before
      // opening a new one — avoids connecting to a device mid-teardown.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    try {
      await _midi.connectToDevice(device);
    } on PlatformException catch (e) {
      // Benign race: the native side already opened the port. Treat as success.
      if (e.code != 'MESSAGEERROR' ||
          !(e.message?.contains('already connected') ?? false)) {
        rethrow;
      }
    }
    _connected = device;
    _lastDeviceId = device.id; // remember for auto-reconnect on replug
    _lastDeviceName = device.name;
  }

  /// Explicit, user-initiated disconnect. Clears [_lastDeviceId] so the device
  /// will NOT auto-reconnect — only a fresh [connect] re-arms that.
  void disconnect() {
    if (_connected != null) {
      _midi.disconnectDevice(_connected!);
      _connected = null;
    }
    _lastDeviceId = null;
    _lastDeviceName = null;
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
    _setupSub?.cancel();
    disconnect();
    _noteController.close();
    _rawController.close();
    _setupController.close();
  }
}
