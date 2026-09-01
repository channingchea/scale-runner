import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single Note On / Note Off event, decoded from the raw MIDI byte stream.
class MidiNoteEvent {
  final int note; // MIDI note number 0-127
  final int velocity; // 0-127
  final bool isOn; // true = Note On (key pressed)

  const MidiNoteEvent(this.note, this.velocity, this.isOn);

  @override
  bool operator ==(Object other) =>
      other is MidiNoteEvent &&
      other.note == note &&
      other.velocity == velocity &&
      other.isOn == isOn;

  @override
  int get hashCode => Object.hash(note, velocity, isOn);

  @override
  String toString() => '${isOn ? "ON " : "OFF"} note=$note vel=$velocity';
}

/// Number of data bytes that follow [status], or null if the message type
/// isn't one we know how to skip safely (e.g. Sysex, which needs an 0xF7
/// terminator scan rather than a fixed length).
int? _dataByteCountFor(int status) {
  switch (status) {
    case 0xF1:
    case 0xF3:
      return 1;
    case 0xF2:
      return 2;
    case 0xF6:
    case 0xF7:
      return 0;
  }
  switch (status & 0xF0) {
    case 0xC0: // Program Change
    case 0xD0: // Channel Pressure
      return 1;
    case 0x80: // Note Off
    case 0x90: // Note On
    case 0xA0: // Poly Key Pressure
    case 0xB0: // Control Change
    case 0xE0: // Pitch Bend
      return 2;
    default:
      return null; // 0xF0 (Sysex start) or anything unrecognized
  }
}

/// Decodes a raw MIDI byte stream into Note On/Off events.
///
/// A single packet can contain several coalesced messages — BLE MIDI in
/// particular batches simultaneous note-ons (chords) into one packet — so
/// this walks the whole buffer rather than reading only the first message.
/// It also supports MIDI running status, where a message omits its own
/// status byte and reuses the previous one (common on BLE keyboards sending
/// chords). Non-note channel messages are skipped by their known length;
/// System Real-Time bytes (0xF8-0xFF) are skipped without disturbing running
/// status. An unrecognized/Sysex status stops parsing the rest of the packet
/// rather than misreading subsequent bytes as notes.
///
/// [lastStatus] seeds running status for a buffer that starts mid-message
/// (unused across real packets today, but keeps this testable standalone).
List<MidiNoteEvent> parseMidiBytes(Uint8List bytes, {int? lastStatus}) {
  final events = <MidiNoteEvent>[];
  int? status = lastStatus;
  int i = 0;
  while (i < bytes.length) {
    final byte = bytes[i];
    if (byte >= 0xF8) {
      // System Real-Time: single byte, doesn't touch running status.
      i++;
      continue;
    }
    if (byte & 0x80 != 0) {
      status = byte;
      i++;
    }
    if (status == null) break; // data byte with no status yet - malformed
    final needed = _dataByteCountFor(status);
    if (needed == null) break; // unknown/Sysex - bail out safely
    if (i + needed > bytes.length) break; // incomplete message at packet tail

    if (needed == 2 && (status & 0xF0 == 0x80 || status & 0xF0 == 0x90)) {
      final note = bytes[i];
      final velocity = bytes[i + 1];
      // 0x90 Note On with velocity 0 is, by convention, a Note Off (some
      // keyboards use this instead of a real 0x80 message).
      if (status & 0xF0 == 0x90 && velocity > 0) {
        events.add(MidiNoteEvent(note, velocity, true));
      } else {
        events.add(MidiNoteEvent(note, 0, false));
      }
    }
    i += needed;
  }
  return events;
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

  /// Native bridge to Apple's Bluetooth-MIDI pairing UI. One channel name for
  /// both Apple platforms; the native side picks the right class
  /// (CABTMIDICentralViewController on iOS, CABTLEMIDIWindowController on
  /// macOS — see ios/Runner/SceneDelegate.swift and
  /// macos/Runner/MainFlutterWindow.swift).
  static const _ble = MethodChannel('scale_runner/ble_midi');

  /// True where a native pairing UI is wired up. Everywhere else we fall back
  /// to the plugin's headless central.
  bool get _hasNativeBlePairing =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  final _noteController = StreamController<MidiNoteEvent>.broadcast();
  final _rawController = StreamController<String>.broadcast();

  /// Rebroadcasts the plugin's single-subscription setup stream so multiple
  /// screens can listen. We subscribe to the plugin ONCE (in [start]) and fan
  /// out here; subscribing the plugin stream more than once throws.
  final _setupController = StreamController<String>.broadcast();

  StreamSubscription<MidiPacket>? _rxSub;
  StreamSubscription<String>? _setupSub;
  MidiDevice? _connected;

  /// Id + name + type of the last device the user connected to. Retained
  /// across unplugs so the same keyboard auto-reconnects when it reappears,
  /// and persisted to disk so it survives app restarts. USB MIDI devices
  /// often re-enumerate with a fresh id, so we match on either id or name.
  /// Cleared only by an explicit [disconnect].
  String? _lastDeviceId;
  String? _lastDeviceName;
  String? _lastDeviceType;

  static const _prefsId = 'midi_last_device_id';
  static const _prefsName = 'midi_last_device_name';
  static const _prefsType = 'midi_last_device_type';

  AppLifecycleListener? _lifecycle;
  bool _restoreStarted = false;
  Timer? _scanStopTimer;

  /// Clean stream of decoded Note On/Off events for the quiz to consume.
  Stream<MidiNoteEvent> get noteStream => _noteController.stream;

  /// Human-readable raw packet strings for the debug monitor.
  Stream<String> get rawStream => _rawController.stream;

  MidiDevice? get connectedDevice => _connected;
  bool get isConnected => _connected != null;

  /// Whether the connected device is Bluetooth LE. BLE is the only transport
  /// with meaningful input latency (radio batching); USB/network/virtual are
  /// near-zero, so latency correction should apply only when this is true.
  bool get isBleConnected => _connected?.type == 'BLE';

  /// Begin listening to the global MIDI receive + setup streams. Safe to call
  /// repeatedly; both subscriptions are created once. Subscribing the plugin's
  /// streams more than once throws, so all fan-out goes through our broadcast
  /// controllers ([noteStream], [rawStream], [onSetupChanged]).
  void start() {
    _rxSub ??= _midi.onMidiDataReceived?.listen(_handlePacket);
    _setupSub ??= _midi.onMidiSetupChanged?.listen(_handleSetupChanged);
    // Returning to the foreground doesn't always fire a MIDI setup change,
    // so retry the remembered device explicitly on every app resume.
    _lifecycle ??= AppLifecycleListener(onResume: attemptReconnect);
    _restoreLastDevice();
  }

  /// Load the remembered device from disk (once per launch) and try to
  /// reconnect, so the user's keyboard survives an app restart without a
  /// trip back to the MIDI Devices screen. Guarded: plugins are absent in
  /// widget tests and restore must never take the app down.
  Future<void> _restoreLastDevice() async {
    if (_restoreStarted) return;
    _restoreStarted = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastDeviceId ??= prefs.getString(_prefsId);
      _lastDeviceName ??= prefs.getString(_prefsName);
      _lastDeviceType ??= prefs.getString(_prefsType);
      await attemptReconnect();
    } catch (e) {
      debugPrint('MIDI restore unavailable: $e');
    }
  }

  /// Try to reconnect to the remembered device right now. If it was a BLE
  /// keyboard that isn't visible yet, scan briefly — once it surfaces, the
  /// setup-change handler completes the reconnect. No-op when already
  /// connected or nothing is remembered.
  Future<void> attemptReconnect() async {
    if (_connected != null || _lastDeviceId == null) return;
    try {
      await _tryAutoReconnect();
      if (_connected != null || _lastDeviceType != 'BLE') return;
      await _midi.startBluetoothCentral();
      await _midi
          .waitUntilBluetoothIsInitialized()
          .timeout(const Duration(seconds: 5));
      await _midi.startScanningForBluetoothDevices();
      // Don't scan forever - it costs battery. 15s covers a keyboard that's
      // already advertising; anything later still connects via the screen.
      _scanStopTimer?.cancel();
      _scanStopTimer = Timer(const Duration(seconds: 15),
          _midi.stopScanningForBluetoothDevices);
    } catch (e) {
      debugPrint('MIDI reconnect attempt failed: $e'); // e.g. Bluetooth off
    }
  }

  /// Remember [d] in memory and on disk for auto-reconnect (replug, resume,
  /// and future launches). Prefs write is fire-and-forget.
  void _rememberDevice(MidiDevice d) {
    _lastDeviceId = d.id;
    _lastDeviceName = d.name;
    _lastDeviceType = d.type;
    SharedPreferences.getInstance().then((p) {
      p.setString(_prefsId, d.id);
      p.setString(_prefsName, d.name);
      p.setString(_prefsType, d.type);
    }).catchError((Object e) {
      debugPrint('MIDI prefs write failed: $e');
    });
  }

  /// Single internal handler for every OS MIDI setup change. Reconciles
  /// connection state, auto-reconnects a replugged device, then notifies UI.
  /// Runs regardless of whether any screen is currently listening. Fetches
  /// the live device list once and shares it with both steps below instead
  /// of each querying the plugin separately.
  Future<void> _handleSetupChanged(String event) async {
    final live = await devices();
    await refreshConnectionState(liveDevices: live);
    await _tryAutoReconnect(liveDevices: live);
    if (!_setupController.isClosed) _setupController.add(event);
  }

  /// List currently visible MIDI devices (USB + already-paired BLE).
  Future<List<MidiDevice>> devices() async {
    final list = await _midi.devices;
    return list ?? <MidiDevice>[];
  }

  /// Open Apple's Bluetooth-MIDI pairing UI to pair a BLE keyboard.
  ///
  /// On iOS and macOS we present Apple's own pairing UI (the one GarageBand
  /// uses) via a native channel — flutter_midi_command's
  /// startBluetoothCentral() only scans headlessly and rarely surfaces the
  /// device. On other platforms we fall back to the plugin's central.
  /// May throw - caller should guard.
  Future<void> startBluetoothCentral() async {
    if (_hasNativeBlePairing) {
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
  /// reports disconnected) in the live MIDI device list. Pass [liveDevices]
  /// to reuse an already-fetched list instead of querying the plugin again.
  Future<void> refreshConnectionState({List<MidiDevice>? liveDevices}) async {
    if (_connected == null) return;
    final live = liveDevices ?? await devices();
    final stillThere = live.any((d) => d.id == _connected!.id && d.connected);
    if (!stillThere) _connected = null;
  }

  /// If nothing is connected but the last-used device has reappeared in the
  /// live list, silently reconnect to it. Lets a replugged keyboard come back
  /// without the user re-picking it. Pass [liveDevices] to reuse an
  /// already-fetched list instead of querying the plugin again.
  Future<void> _tryAutoReconnect({List<MidiDevice>? liveDevices}) async {
    if (_connected != null || _lastDeviceId == null) return;
    final live = liveDevices ?? await devices();
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
      _rememberDevice(device);
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
    _rememberDevice(device);
    // A reconnect scan may still be running - it's done its job now.
    _scanStopTimer?.cancel();
    _midi.stopScanningForBluetoothDevices();
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
    _lastDeviceType = null;
    SharedPreferences.getInstance().then((p) {
      p.remove(_prefsId);
      p.remove(_prefsName);
      p.remove(_prefsType);
    }).catchError((Object e) {
      debugPrint('MIDI prefs clear failed: $e');
    });
  }

  void _handlePacket(MidiPacket packet) {
    final data = packet.data;
    if (data.isEmpty) return;
    _rawController.add(
      data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '),
    );

    for (final event in parseMidiBytes(data)) {
      _noteController.add(event);
    }
  }

  void dispose() {
    _rxSub?.cancel();
    _setupSub?.cancel();
    _lifecycle?.dispose();
    _scanStopTimer?.cancel();
    // Tear down the connection but do NOT forget the remembered device -
    // only a user-initiated [disconnect] should erase it.
    if (_connected != null) {
      _midi.disconnectDevice(_connected!);
      _connected = null;
    }
    _noteController.close();
    _rawController.close();
    _setupController.close();
  }
}
