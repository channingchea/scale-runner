import 'dart:convert';

/// The practice-configuration keys that follow the account across devices,
/// with the type each is stored as. Everything else in prefs (instrument,
/// sounds, hints, reminders, onboarding flags, UI state) stays on the device.
///
/// Values travel as text; [encodeSetting] / [decodeSetting] convert.
enum SettingType { boolean, integer, string, stringList }

const Map<String, SettingType> kSyncedSettings = {
  'enabled_scales': SettingType.stringList,
  'enabled_chords': SettingType.stringList,
  'enabled_keys_scales': SettingType.stringList,
  'enabled_keys_chords': SettingType.stringList,
  'timing_difficulty': SettingType.string,
  'arpeggiated_notes': SettingType.boolean,
  'run_chords': SettingType.boolean,
  'run_progression': SettingType.string,
  'run_increment': SettingType.string,
  'run_sevenths': SettingType.boolean,
  'run_start_key': SettingType.integer,
  'run_reps': SettingType.integer,
  'inv_chords': SettingType.stringList,
  'inv_tempo': SettingType.boolean,
  'jam_key': SettingType.integer,
  'jam_families': SettingType.stringList,
  'jam_session_bars': SettingType.integer,
  'jam_freestyle': SettingType.boolean,
  'jam_any_tones': SettingType.boolean,
  'voicing_start_key': SettingType.integer,
  'voicing_increment': SettingType.string,
};

String encodeSetting(Object value) =>
    value is List ? jsonEncode(value) : value.toString();

/// Null when [text] doesn't parse as [type]; the caller keeps its local value.
Object? decodeSetting(SettingType type, String text) {
  try {
    switch (type) {
      case SettingType.boolean:
        return text == 'true' ? true : (text == 'false' ? false : null);
      case SettingType.integer:
        return int.tryParse(text);
      case SettingType.string:
        return text;
      case SettingType.stringList:
        final v = jsonDecode(text);
        return v is List ? [for (final e in v) e as String] : null;
    }
  } catch (_) {
    return null;
  }
}
