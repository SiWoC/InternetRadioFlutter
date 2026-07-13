# Internet Radio Flutter

A Flutter/Dart/Kotlin-based internet radio streaming application designed to run on one of my old Android phones which I connect through the headphone jack to my receiver.

![Internet Radio Lego Frame](Internet%20Radio%20Lego%20frame.jpg)

## Features

- **Internet Radio** - Stream radio stations via Android Media3 (ExoPlayer)
- **Remote Control** - Install the app on two devices and control one with the other
- **Custom Station Library** - Configure multiple radio stations with logos through a "hardcoded json" before building.
- **Mute/Unmute Control** - Toggle audio playback (current build mutes the stream which means it keeps consuming data, but prevents having to listen to the start commercial on resume)
- **Screensaver Mode** - Automatic screensaver with station artwork

## Technologies

| Layer | Stack | Role |
|-------|--------|------|
| UI | **Flutter 3.44** / **Dart 3.12** | Screens, station grid, settings, remote UI |
| App logic | **Dart** | Stations, settings, TCP remote protocol, controllers |
| Audio | **Kotlin** + **AndroidX Media3 1.10** | Live stream playback, mute, audio routing |
| Bridge | **MethodChannel** / **EventChannel** | Dart ↔ native player |
| Persistence | **shared_preferences**  | Mode, player IP, last station |
| Networking | **dart:io** TCP | Remote control on port 6435 |

**Android:** minSdk 26 (Android 8), target Android 14. Built-in Kotlin (AGP).

## Requirements

- Flutter 3.44.2 (Dart 3.12.2)
- Android SDK / device or emulator (API 26+)
- JDK 17 (for Android Gradle builds)

## Project layout (app code)

```
lib/
  main.dart                 # App entry
  services/
    radio_player_service.dart   # PoC: media3_radio_player.dart (rename)
    radio_player_state.dart
android/app/src/main/kotlin/nl/siwoc/internetradio/
  RadioPlayerManager.kt     # Media3 / ExoPlayer
  RadioPlayerPlugin.kt      # Platform channel
  MainActivity.kt
assets/                     # Station config
  settings.json
  images/                   # Station logos (PNG)
```

## Configuration

### Station list — `assets/settings.json`

Place the station list at:

```
assets/settings.json
```

Register it in `pubspec.yaml` under `flutter: assets:`.

Format (same as the Unity app):

```json
{
  "station": [
    {
      "name": "Station Name",
      "url": "https://stream-url.com/stream",
      "image": "/images/station-logo.png"
    }
  ]
}
```

- **name** - Display name of the station
- **url** — Stream URL (MP3, Icecast, redirects, etc.; verify per station with Media3)
- **image** — Path under `assets/`, typically `/images/filename.png`

The last station in the list is reserved for URL testing in settings (Unity behaviour).

### Station logos — `assets/images/`

Place logo files at:

```
assets/images/
  station-logo.png
  ...
```

Use PNG (WEBP possible if the loader supports it). If a logo is missing, the UI falls back to the station name.

### Fallback stations

If `settings.json` fails to load, the app should use hardcoded fallbacks:

- ABC Triple J NSW
- Q-Music
- Radio 538

## Controls

- **Station buttons** — Switch station (Player) or send remote command (Remote)
- **Mute** — Toggle output (stream stays connected)
- **Player / Remote** — Operating mode
- **Settings** — Player IP, connection test, URL test
- **Touch** — Resets screensaver timer
- **Exit** — Close app (Android)

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).

## Notes

- Player mode keeps the device awake while playing
- Screensaver after ~60s inactivity
- Last station and mode persist between sessions
- Development checklist: [todo.md](todo.md)
- Class & folder overview: [docs/class-overview.md](docs/class-overview.md)
