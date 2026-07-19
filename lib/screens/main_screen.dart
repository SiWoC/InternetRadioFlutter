import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:internetradio/app/app_scope.dart';
import 'package:internetradio/controllers/radio_controller.dart';
import 'package:internetradio/services/local_network_info.dart';
import 'package:internetradio/widgets/station_grid.dart';

/// Main radio UI — chrome + station grid.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _background = Color(0xFF0A3D4F);

  String _localIp = '…';

  @override
  void initState() {
    super.initState();
    _loadLocalIp();
  }

  Future<void> _loadLocalIp() async {
    final ip = await LocalNetworkInfo.localIpv4();
    if (!mounted) {
      return;
    }
    setState(() => _localIp = ip);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selected = controller.selectedStation;
        final playerState = controller.playerState;
        final muted = playerState.isMuted;
        final hasStream = playerState.url != null;
        final title = playerState.isPlaying
            ? (selected?.name ?? '')
            : playerState.playbackState.name;

        return Scaffold(
          backgroundColor: _background,
          body: Column(
            children: [
              _TopChrome(
                stationTitle: title,
                muted: muted,
                muteEnabled: hasStream,
                onMute: controller.toggleMute,
                onExit: () => _exitApp(controller),
              ),
              Expanded(
                child: StationGrid(
                  stations: controller.stations.gridStations,
                  selectedIndex: controller.selectedStationIndex,
                  onStationSelected: (index) =>
                      _selectStation(context, controller, index),
                ),
              ),
              _BottomChrome(
                localIp: _localIp,
                onRemoteStub: () {},
                onSettingsStub: () {},
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exitApp(RadioController controller) async {
    await controller.stop();
    SystemNavigator.pop();
  }

  Future<void> _selectStation(
    BuildContext context,
    RadioController controller,
    int index,
  ) async {
    try {
      await controller.selectStation(index);
    } on PlatformException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Play failed: ${error.message}')),
      );
    }
  }
}

class _TopChrome extends StatelessWidget {
  const _TopChrome({
    required this.stationTitle,
    required this.muted,
    required this.muteEnabled,
    required this.onMute,
    required this.onExit,
  });

  final String stationTitle;
  final bool muted;
  final bool muteEnabled;
  final VoidCallback onMute;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, isLandscape ? 4 : 8, 12, 0),
      child: SizedBox(
        height: isLandscape ? 56 : 72,
        child: Row(
          children: [
            _ChromeIconButton(
              assetPath: muted
                  ? 'assets/images/mute-muted.png'
                  : 'assets/images/mute-playing.png',
              onPressed: muteEnabled ? onMute : null,
              semanticLabel: muted ? 'Unmute' : 'Mute',
            ),
            Expanded(
              child: Text(
                stationTitle,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isLandscape ? 24 : 28,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ),
            _ChromeIconButton(
              assetPath: 'assets/images/exit.png',
              onPressed: onExit,
              semanticLabel: 'Exit',
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomChrome extends StatelessWidget {
  const _BottomChrome({
    required this.localIp,
    required this.onRemoteStub,
    required this.onSettingsStub,
  });

  final String localIp;
  final VoidCallback onRemoteStub;
  final VoidCallback onSettingsStub;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    // Taller strip in landscape so icons sit above the screen edge;
    // content is top-aligned inside that strip.
    return SizedBox(
      height: isLandscape ? 80 : 56,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, isLandscape ? 4 : 4, 12, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  localIp,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
              ),
              _ChromeIconButton(
                assetPath: 'assets/images/remote-control.png',
                onPressed: onRemoteStub,
                semanticLabel: 'Remote mode',
                size: 48,
              ),
              const SizedBox(width: 8),
              _ChromeIconButton(
                assetPath: 'assets/images/settings.png',
                onPressed: onSettingsStub,
                semanticLabel: 'Settings',
                size: 48,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.assetPath,
    required this.onPressed,
    required this.semanticLabel,
    this.size = 56,
  });

  final String assetPath;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: semanticLabel,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      icon: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Icon(
          Icons.broken_image,
          size: size * 0.6,
          color: Colors.white70,
        ),
      ),
    );
  }
}
