# Internet Radio — development todo

Bottom-up plan after the Media3 PoC. Build from native → Dart services → UI.

**Done (Layer 0):** Media3 streaming, platform channel, buffer tuning, stream switch teardown, `AudioRouteFixer`, foreground `RadioPlaybackService` + notification, lifecycle/ownership, PoC streams verified on Android 8 and Android 14.

**Deferred from Layer 0:** **Display policy** (wakelock / keepScreenOn vs allowScreenOff) — wait until settings UI + screensaver (Layers 2–4). Redirect URLs: Media3 handles them; verify fav stations later.

---

## Layer 0 — Native audio (Kotlin) ✅

### 0.1 Foreground playback
- [x] Add `MediaSessionService` (or `MediaSession` + foreground service)
- [x] Media notification (station name, mute/stop)
- [x] Wire `RadioPlayerManager` into the service (not only `MainActivity` lifecycle)
- [x] Handle audio focus in service context

### 0.2 Lifecycle
- [x] Playback survives app background / screen off
- [x] Clean shutdown on app kill vs user stop (notification swipe/app swipe stop playback)
- [x] Decide owner: Dart dispose vs service-owned player

### 0.3 Hardening
- [x] ~~Stream error → auto-retry~~ → moved to Nice-to-have
- [x] ~~StreamTheWorld redirect cache~~ → skip (Media3 redirects work; re-check with fav stations)

### 0.4 Device behaviour
- [x] Keep `AudioRouteFixer` on stream start
- [ ] **Display policy** — deferred to settings + screensaver (see Layers 2–4)
- [x] Test on Android 8 and Android 14 hardware

---

## Layer 1 — Platform bridge

### 1.1 Channel API
- [x] State map = state only (`play()` returns bool; failures via error / `state.error`)
- [x] Document expected state fields (`RadioPlayerState`)

### 1.2 Dart wrapper
- [x] `RadioPlayerService` (`play`, `stop`, `setMuted`, `stateStream`)
- [ ] Single app-wide instance (not per-screen) — via `AppScope` / `RadioController`
- [x] UI listens through `RadioController` (`ChangeNotifier` or streams)

---

## Layer 2 — Domain models (Dart)

### 2.1 Core types
- [x] `RadioStation` (name, url, imageAssetPath)
- [x] `OperatingMode` / `DisplayPolicy` / `AppSettings` (`lib/models/app_settings.dart`)
- [x] `RemotePlayerState` (stationIndex, isMuted, isPlaying)

### 2.2 Station config
- [x] Load `assets/settings.json` → `List<RadioStation>` (`StationRepository`)
- [x] Fallback list if JSON missing (Triple J, Q-Music, 538)
- [x] Add `assets/settings.json` + `assets/images/*`
- [x] Last station in list = URL test slot
- [x] Register assets in `pubspec.yaml`

---

## Layer 3 — Dart services

### 3.1 `StationRepository`
- [x] Load stations from assets at startup
- [x] Expose station by index / name (and grid vs URL-test slot)

### 3.2 `SettingsRepository`
- [x] `shared_preferences`: mode, player IP, last station, test URL, display policy
- [x] Load on startup, save on change

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
- [ ] Start internatiolisation en/nl

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
| **M1** | Layer 0 ✅ + 2.x + 3.1–3.3 + 4.1–4.2 + 5.1 | Real stations, main Player UI, mute, persist |
| **M2** | 4.4 + display policy + 6.1 | Screensaver, display policy, daily-use Player |
| **M3** | 3.4–3.5 + 5.3 + 6.2 | Remote control parity with Unity |
| **M4** | 6.3–6.4 | Ship-ready |

---

## Optional (not in Unity)

- [x] Lock-screen / notification controls (Layer 0.1)
- [ ] Connection status indicator in Remote mode
- [ ] Resolve redirect URLs before play (StreamTheWorld) — only if a fav station fails Media3 redirects

---

## Nice-to-have

- [ ] **Stream error → auto-retry with backoff** — native `RadioPlayerManager`: on `PlaybackException`, retry current URL with exponential backoff; reset on successful play / station change
- [ ] **Wake Player screen on remote command** — when display policy is `allowScreenOff` and the Player screen is asleep, a remote command (station change, mute, etc.) would turn the display on so the UI is visible without pressing the power button. Audio already responds to remote either way; this is display-only. Unnecessary when policy is `keepScreenOn` (default for receiver use).
