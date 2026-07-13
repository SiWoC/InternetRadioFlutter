# Internet Radio — development todo

Bottom-up plan after the Media3 PoC. Build from native → Dart services → UI.

**Done (PoC):** Media3 streaming, platform channel, buffer tuning, stream switch teardown, `AudioRouteFixer`.

---

## Layer 0 — Native audio (Kotlin)

### 0.1 Foreground playback
- [ ] Add `MediaSessionService` (or `MediaSession` + foreground service)
- [ ] Media notification (station name, mute/stop)
- [ ] Wire `RadioPlayerManager` into the service (not only `MainActivity` lifecycle)
- [ ] Handle audio focus in service context

### 0.2 Lifecycle
- [ ] Playback survives app background / screen off
- [ ] Clean shutdown on app kill vs user stop
- [ ] Decide owner: Dart dispose vs service-owned player

### 0.3 Hardening
- [ ] Stream error → auto-retry with backoff (optional)
- [ ] Optional: resolve StreamTheWorld redirect URLs once and cache final URL

### 0.4 Device behaviour
- [ ] Keep `AudioRouteFixer` on stream start
- [ ] **Display policy** setting (Player mode): `keepScreenOn` vs `allowScreenOff` — drives wakelock; screensaver only when screen stays on
- [ ] Test on Android 8 and Android 14 hardware

---

## Layer 1 — Platform bridge

### 1.1 Channel API
- [ ] State map = state only (remove `started` from map; keep as `play()` return value)
- [ ] Document expected state fields

### 1.2 Dart wrapper
- [ ] Single app-wide `RadioPlayerService` instance (not per-screen)
- [ ] Pick state management: `ChangeNotifier` / Riverpod / manual controller

---

## Layer 2 — Domain models (Dart)

### 2.1 Core types
- [ ] `RadioStation` (name, url, imageAssetPath)
- [ ] `OperatingMode` (player | remote)
- [ ] `DisplayPolicy` (keepScreenOn | allowScreenOff) — Player mode only
- [ ] `AppSettings` (mode, playerIp, lastStationName, testUrl, displayPolicy)
- [ ] `RemotePlayerState` (stationIndex, muteState)

### 2.2 Station config
- [ ] Parse `assets/settings.json` → `List<RadioStation>`
- [ ] Fallback list if JSON missing (Triple J, Q-Music, 538)
- [ ] Copy assets from Unity: `assets/settings.json`, `assets/images/*`
- [ ] Last station in list = URL test slot (Unity behaviour)
- [ ] Register assets in `pubspec.yaml`

---

## Layer 3 — Dart services

### 3.1 `StationRepository`
- [ ] Load stations from assets at startup
- [ ] Resolve image path → asset key
- [ ] Expose station by index / name

### 3.2 `SettingsRepository`
- [ ] `shared_preferences`: mode, player IP, last station, test URL, display policy
- [ ] Load on startup, save on change

### 3.3 `RadioController`
- [ ] Owns `RadioPlayerService`
- [ ] `selectStation(index)` → play URL, persist name
- [ ] `toggleMute()` / `stop()`
- [ ] Restore last station on cold start (Player mode)
- [ ] Subscribe to native state stream
- [ ] **Incoming remote TCP command → dismiss screensaver** (reset idle timer)
- [ ] Apply **display policy**: wakelock on/off in Player mode

### 3.4 `NetworkService`
- [ ] TCP port 6435
- [ ] Player: server — `PING`, `SELECT_STATION|n`, `MUTE`, `UNMUTE`, `GET_STATE`, `TESTURL|url`
- [ ] Remote: client — send commands, parse `STATE|…`, `PONG`
- [ ] 2s connection timeout, 2.5s poll interval (Remote)
- [ ] Local IP helper (bottom-left display)

### 3.5 Mode orchestration
- [ ] Player mode: TCP listener, local audio, apply display policy (wakelock)
- [ ] Remote mode: poll player, wakelock off, allow screen sleep
- [ ] Mode switch: stop listener / poll, update UI rules

---

## Layer 4 — UI (4 extracted widgets + MainScreen chrome)

### 4.1 `StationGrid` + `StationTile`
- [ ] Scrollable grid (portrait/landscape column count)
- [ ] Station tile: logo or name fallback
- [ ] Selected state highlight

### 4.2 `MainScreen` (static chrome inline — no separate widget files)
- [ ] Mute button (playing / muted visuals)
- [ ] Current station title
- [ ] Local IP text
- [ ] Player ↔ Remote toggle
- [ ] Settings entry
- [ ] Exit (Android)

### 4.3 `SettingsOverlay`
- [ ] Player IP field + connection test (`PING` → OK / Error / Testing…)
- [ ] URL test field (`TESTURL`, last station slot)
- [ ] **Display policy** toggle (Player mode): keep screen on / allow screen off
- [ ] Save to `SettingsRepository`

### 4.4 `ScreensaverOverlay`
- [ ] 60s inactivity timer (reset on local touch) — logic in `ScreensaverController`
- [ ] Full-screen overlay, bouncing station logo (only when display policy = keep screen on)
- [ ] Disabled while settings open
- [ ] Tap to dismiss
- [ ] **Dismiss when Player receives remote command** (`RadioController` → `ScreensaverController`)

---

## Layer 5 — Screens & app shell

### 5.1 Replace PoC `main.dart`
- [ ] `MaterialApp` + theme
- [ ] Root provider / controller injection
- [ ] Main screen: inline chrome + composes Layer 4 widgets/overlays

### 5.2 Layout
- [ ] Responsive grid (landscape ~3 columns, portrait dynamic rows)

### 5.3 Remote mode UI
- [ ] Remote: station tap → `SELECT_STATION|index`
- [ ] Remote: mute → `MUTE` / `UNMUTE`
- [ ] Sync UI from polled state

---

## Layer 6 — Integration & polish

### 6.1 End-to-end Player
- [ ] Full station list from `settings.json`
- [ ] Mute, screensaver, persist station, background audio

### 6.2 End-to-end Remote + Player
- [ ] Two phones on same LAN
- [ ] Mode switch, IP setup, poll sync

### 6.3 README / build
- [ ] Release APK signing
- [ ] Isolate `Temp/` from release builds if desired

### 6.4 Tests (minimal)
- [ ] JSON parse + fallback stations
- [ ] TCP protocol encode/decode
- [ ] Widget smoke: main screen loads stations

---

## Milestones

| # | Scope | Delivers |
|---|--------|----------|
| **M1** | 0.x (partial) + 2.x + 3.1–3.3 + 4.1–4.2 + 5.1 | Real stations, main Player UI, mute, persist |
| **M2** | 0.1–0.2 + 4.4 + 6.1 | Background play, screensaver, daily-use Player |
| **M3** | 3.4–3.5 + 5.3 + 6.2 | Remote control parity with Unity |
| **M4** | 6.3–6.4 | Ship-ready |

---

## Optional (not in Unity)

- [ ] Lock-screen / notification controls (Layer 0.1)
- [ ] Connection status indicator in Remote mode
- [ ] Resolve redirect URLs before play (StreamTheWorld)

---

## Nice-to-have

- [ ] **Wake Player screen on remote command** — when display policy is `allowScreenOff` and the Player screen is asleep, a remote command (station change, mute, etc.) would turn the display on so the UI is visible without pressing the power button. Audio already responds to remote either way; this is display-only. Unnecessary when policy is `keepScreenOn` (default for receiver use).
