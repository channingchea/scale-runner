import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'midi/midi_service.dart';
import 'purchases/purchase_service.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PurchaseService.instance.configure();
  runApp(const ScaleRunnerApp());
}

class ScaleRunnerApp extends StatefulWidget {
  const ScaleRunnerApp({super.key});

  @override
  State<ScaleRunnerApp> createState() => _ScaleRunnerAppState();
}

class _ScaleRunnerAppState extends State<ScaleRunnerApp> {
  final MidiService _midi = MidiService();

  @override
  void initState() {
    super.initState();
    _midi.start();
  }

  @override
  void dispose() {
    _midi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scale Runner',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: SplashScreen(child: HomeScreen(midi: _midi)),
    );
  }
}
