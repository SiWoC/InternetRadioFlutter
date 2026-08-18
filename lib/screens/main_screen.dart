import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:internetradio/app/app_scope.dart';
import 'package:internetradio/controllers/radio_controller.dart';
import 'package:internetradio/models/app_settings.dart';
import 'package:internetradio/services/local_network_info.dart';
import 'package:internetradio/widgets/marquee_text.dart';
import 'package:internetradio/widgets/screensaver_overlay.dart';
import 'package:internetradio/widgets/settings_overlay.dart';
import 'package:internetradio/widgets/station_grid.dart';
import 'package:internetradio/widgets/yamaha_overlay.dart';

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
    final screensaver = controller.screensaver;

    return ListenableBuilder(
      listenable: Listenable.merge([controller, screensaver]),
      builder: (context, _) {
        final selected = controller.selectedStation;
        final muted = controller.isMuted;
        final stationTitle = controller.chromeStationTitle;
        final nowPlaying = controller.chromeNowPlaying;
        final muteEnabled =
            controller.isRemoteMode || controller.playerState.url != null;

        return Scaffold(
          backgroundColor: _background,
          body: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => screensaver.onUserActivity(),
            child: Stack(
              children: [
                Column(
                  children: [
                    _TopChrome(
                      stationTitle: stationTitle,
                      nowPlaying: nowPlaying,
                      muted: muted,
                      muteEnabled: muteEnabled,
                      onMute: () => unawaited(controller.toggleMute()),
                      onExit: () => _exitApp(controller),
                    ),
                    Expanded(
                      child: StationGrid(
                        stations: controller.stations.stations,
                        selectedIndex: controller.selectedStationIndex,
                        onStationSelected: (index) =>
                            _selectStation(context, controller, index),
                      ),
                    ),
                    _BottomChrome(
                      localIp: _localIp,
                      mode: controller.settings.mode,
                      playerUnreachable: controller.playerUnreachable,
                      onToggleMode: () =>
                          unawaited(controller.toggleOperatingMode()),
                      onYamaha: controller.openYamaha,
                      onSettings: controller.openSettings,
                    ),
                  ],
                ),
                if (controller.isSettingsOpen)
                  Positioned.fill(
                    child: SettingsOverlay(
                      initialPlayerIp: controller.settings.playerIp,
                      initialTestUrl: controller.settings.testUrl ?? '',
                      initialYamahaIp: controller.settings.yamahaIp,
                      displayPolicy: controller.settings.displayPolicy,
                      bannerMessage: controller.settingsMessage,
                      onTestPlayerConnection: controller.testPlayerConnection,
                      onPersistPlayerIp: controller.savePlayerIp,
                      onFindPlayer: controller.findPlayerIp,
                      onTestYamahaConnection: controller.testYamahaConnection,
                      onPersistYamahaIp: controller.saveYamahaIp,
                      onFindYamaha: controller.findYamahaIp,
                      onPlayTestUrl: controller.playTestUrl,
                      onDisplayPolicyChanged: controller.setDisplayPolicy,
                      onSaveAndClose:
                          ({
                            required playerIp,
                            required testUrl,
                            required yamahaIp,
                          }) async {
                            await controller.saveSettings(
                              playerIp: playerIp,
                              testUrl: testUrl,
                              yamahaIp: yamahaIp,
                            );
                            controller.closeSettings();
                          },
                    ),
                  ),
                if (controller.isYamahaOpen)
                  Positioned.fill(
                    child: YamahaOverlay(
                      status: controller.yamahaStatus,
                      inputs: controller.yamahaInputs,
                      busy: controller.yamahaBusy,
                      onPower: () => unawaited(controller.toggleYamahaPower()),
                      onSelectInput: (inputSel) =>
                          unawaited(controller.selectYamahaInput(inputSel)),
                      onVolumeUp: () => unawaited(controller.yamahaVolumeUp()),
                      onVolumeDown: () =>
                          unawaited(controller.yamahaVolumeDown()),
                      onClose: controller.closeYamaha,
                    ),
                  ),
                if (screensaver.isVisible)
                  Positioned.fill(
                    child: ScreensaverOverlay(
                      station: selected,
                      onDismiss: screensaver.onUserActivity,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exitApp(RadioController controller) async {
    if (controller.isRemoteMode) {
      final reachable = await controller.testPlayerConnection(
        controller.settings.playerIp,
      );
      if (!mounted) {
        return;
      }
      if (reachable) {
        final exitPlayer = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exit the player too?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes'),
              ),
            ],
          ),
        );
        if (!mounted || exitPlayer == null) {
          return;
        }
        if (exitPlayer) {
          await controller.exitRemotePlayer();
        }
      }
    } else {
      await controller.stop();
    }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Play failed: ${error.message}')));
    }
  }
}

class _TopChrome extends StatelessWidget {
  const _TopChrome({
    required this.stationTitle,
    required this.nowPlaying,
    required this.muted,
    required this.muteEnabled,
    required this.onMute,
    required this.onExit,
  });

  final String stationTitle;
  final String? nowPlaying;
  final bool muted;
  final bool muteEnabled;
  final VoidCallback onMute;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final nowPlayingLine = nowPlaying;
    final hasNowPlaying = nowPlayingLine != null && nowPlayingLine.isNotEmpty;
    final stationStyle = TextStyle(
      color: Colors.white,
      fontSize: isLandscape
          ? (hasNowPlaying ? 20 : 24)
          : (hasNowPlaying ? 22 : 28),
      fontWeight: FontWeight.w600,
    );
    final nowPlayingStyle = TextStyle(
      color: Colors.white,
      fontSize: isLandscape ? 14 : 16,
      fontWeight: FontWeight.w400,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(12, isLandscape ? 4 : 8, 12, 0),
      child: SizedBox(
        height: isLandscape ? 72 : 84,
        child: Row(
          children: [
            _ChromeIconButton(
              icon: muted ? Icons.volume_off : Icons.volume_up,
              onPressed: muteEnabled ? onMute : null,
              semanticLabel: muted ? 'Unmute' : 'Mute',
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: MarqueeText(
                      text: stationTitle,
                      style: stationStyle,
                      velocity: 30,
                    ),
                  ),
                  if (hasNowPlaying) ...[
                    const SizedBox(height: 2),
                    SizedBox(
                      width: double.infinity,
                      child: MarqueeText(
                        text: nowPlayingLine,
                        style: nowPlayingStyle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _ChromeIconButton(
              icon: Icons.exit_to_app,
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
    required this.mode,
    required this.playerUnreachable,
    required this.onToggleMode,
    required this.onYamaha,
    required this.onSettings,
  });

  final String localIp;
  final OperatingMode mode;
  final bool playerUnreachable;
  final VoidCallback onToggleMode;
  final VoidCallback onYamaha;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final isRemote = mode == OperatingMode.remote;

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
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
              _YamahaChromeButton(onPressed: onYamaha),
              const SizedBox(width: 8),
              _ModeToggleButton(
                isRemote: isRemote,
                showUnreachableOverlay: !isRemote && playerUnreachable,
                onPressed: onToggleMode,
              ),
              const SizedBox(width: 8),
              _ChromeIconButton(
                icon: Icons.settings,
                onPressed: onSettings,
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

class _ModeToggleButton extends StatelessWidget {
  const _ModeToggleButton({
    required this.isRemote,
    required this.showUnreachableOverlay,
    required this.onPressed,
  });

  final bool isRemote;
  final bool showUnreachableOverlay;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const size = 48.0;
    final iconSize = size * 0.7;
    return IconButton(
      onPressed: onPressed,
      tooltip: isRemote ? 'Player mode' : 'Remote mode',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: size, height: size),
      icon: SizedBox(
        width: iconSize,
        height: iconSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              isRemote ? Icons.radio : Icons.settings_remote,
              size: iconSize,
              color: Colors.white,
            ),
            if (showUnreachableOverlay)
              Align(
                alignment: const Alignment(0, -0.85),
                child: Icon(
                  Icons.close,
                  size: iconSize * 0.55,
                  color: Colors.red,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _YamahaChromeButton extends StatelessWidget {
  const _YamahaChromeButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const size = 48.0;
    final iconSize = size * 0.7;
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Yamaha',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: size, height: size),
      icon: Image.asset(
        'assets/images/yamaha-white-370x370.png',
        width: iconSize,
        height: iconSize,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.size = 56,
  });

  final IconData icon;
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
      icon: Icon(icon, size: size * 0.7, color: Colors.white),
    );
  }
}
