import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:internetradio/app/app_scope.dart';
import 'package:internetradio/controllers/radio_controller.dart';
import 'package:internetradio/screens/main_screen.dart';
import 'package:internetradio/services/settings_repository.dart';
import 'package:internetradio/services/station_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.bottom],
  );

  final stations = await StationRepository.load();
  final settings = await SettingsRepository.load();
  final controller = RadioController(
    stations: stations,
    settings: settings,
  );
  await controller.restoreLastStation();

  runApp(InternetRadioApp(controller: controller));
}

class InternetRadioApp extends StatefulWidget {
  const InternetRadioApp({super.key, required this.controller});

  final RadioController controller;

  @override
  State<InternetRadioApp> createState() => _InternetRadioAppState();
}

class _InternetRadioAppState extends State<InternetRadioApp> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: widget.controller,
      child: MaterialApp(
        title: 'Internet Radio',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0A3D4F),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const MainScreen(),
      ),
    );
  }
}
