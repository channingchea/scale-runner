import 'midi_service.dart';
import '../quiz/quiz_settings.dart';

/// Default input-latency correction (ms) for a BLE MIDI keyboard: the typical
/// delay from key-strike to event arrival (radio batching + native→Dart hop).
/// A starting estimate, exposed so screens can dial it in per transport —
/// USB is near-zero, BLE is the dominant case.
const int defaultBleLatencyMs = 30;

/// Resolves the input-latency correction (ms) to apply for the currently
/// connected MIDI device.
///
/// A saved per-device calibration always wins, even if the transport later
/// re-enumerates under a different `type` label — iOS can report an
/// already-paired BLE keyboard as "native" instead of "BLE" once CoreMIDI
/// (rather than the plugin's own Bluetooth scan) is what surfaces it, which
/// would otherwise silently disable correction for a real BLE keyboard. Only
/// when no calibration is stored do we fall back to [defaultBleLatencyMs],
/// and only if the device currently reports as BLE.
Future<int> resolveInputLatencyMs(MidiService midi, QuizSettings settings) async {
  final deviceName = midi.connectedDevice?.name;
  if (deviceName != null) {
    final stored = await settings.inputLatencyMs(deviceName);
    if (stored != null) return stored;
  }
  return midi.isBleConnected ? defaultBleLatencyMs : 0;
}
