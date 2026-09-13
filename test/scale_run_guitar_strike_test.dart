import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/midi/midi_service.dart';
import 'package:scale_runner/quiz/quiz_settings.dart';
import 'package:scale_runner/screens/scale_run_screen.dart';
import 'package:scale_runner/theme/app_theme.dart';
import 'package:scale_runner/theory/fretboard.dart' show Instrument;
import 'package:scale_runner/widgets/fretboard_view.dart' show FretboardView;
import 'package:scale_runner/widgets/instrument_surface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'helpers/guides_seen.dart';

/// Scale Running on guitar strikes the chord instead of holding it: the neck
/// takes taps as cells (so a struck tone can stay lit where it was tapped and
/// no held shape blocks the run's strings) and the copy says so. The strike
/// judgment itself is covered in scale_run_controller_test.dart; driving the
/// drill here would need the metronome's audio players.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, Instrument instrument) async {
    SharedPreferencesAsyncPlatform.instance = prefsWithGuidesSeen();
    final settings = await QuizSettings.load();
    await settings.setInstrument(instrument);
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: ScaleRunScreen(midi: MidiService())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('guitar takes cell taps and asks for a strike', (tester) async {
    await pump(tester, Instrument.guitar);
    final surface =
        tester.widget<InstrumentSurface>(find.byType(InstrumentSurface));
    expect(surface.onCellDown, isNotNull);
    expect(surface.latched, isNotNull);
    expect(find.byType(FretboardView), findsOneWidget);
    expect(find.textContaining('Strike the chord'), findsWidgets);
    expect(find.textContaining('Hold the chord'), findsNothing);
  });

  testWidgets('piano keeps press-and-hold and asks for a hold', (tester) async {
    await pump(tester, Instrument.piano);
    final surface =
        tester.widget<InstrumentSurface>(find.byType(InstrumentSurface));
    expect(surface.onCellDown, isNull);
    expect(surface.latched, isNull);
    expect(find.textContaining('Hold the chord'), findsWidgets);
    expect(find.textContaining('Strike the chord'), findsNothing);
  });
}
