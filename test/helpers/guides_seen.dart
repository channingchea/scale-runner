// Test seed: every mode guide already seen, so screen tests that tap the
// instrument on first entry aren't covered by the first-run guide sheet.

import 'package:scale_runner/onboarding/mode_guides.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';

/// Prefs with every [GuideMode] marked seen and nothing else set.
InMemorySharedPreferencesAsync prefsWithGuidesSeen() =>
    InMemorySharedPreferencesAsync.withData({
      for (final m in GuideMode.values) m.prefsKey: true,
    });
