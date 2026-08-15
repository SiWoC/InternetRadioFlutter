# Internet Radio — development todo

Bottom-up plan after the Media3 PoC. Build from native → Dart services → UI.

**Done (Layer 0):** Media3 streaming, platform channel, buffer tuning, stream switch teardown, `AudioRouteFixer`, foreground `RadioPlaybackService` + notification, lifecycle/ownership, PoC streams verified on Android 8 and Android 14.

**Deferred from Layer 0:** Redirect URLs: Media3 handles them; verify fav stations later. Screensaver still Layer 4.4.

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
- [x] **Display policy** — settings toggle + wakelock (screensaver is 4.4)
- [x] Test on Android 8 and Android 14 hardware

---

## Layer 1 — Platform bridge

### 1.1 Channel API
- [x] State map = state only (`play()` returns bool; failures via error / `state.error`)
- [x] Document expected state fields (`RadioPlayerState`)

### 1.2 Dart wrapper
- [x] `RadioPlayerService` (`play`, `stop`, `setMuted`, `stateStream`)
- [x] Single app-wide instance (not per-screen) — via `AppScope` / `RadioController`
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
- [x] Expose station by index / name (including URL-test slot)

### 3.2 `SettingsRepository`
- [x] `shared_preferences`: mode, player IP, last station, test URL, display policy
- [x] Load on startup, save on change

### 3.3 `RadioController`
- [x] Owns `RadioPlayerService`
- [x] `selectStation(index)` → play URL, persist name
- [x] `toggleMute()` / `stop()`
- [x] Restore last station on cold start (Player mode)
- [x] Subscribe to native state stream
- [x] **Incoming remote TCP command → dismiss screensaver** (reset idle timer)
- [x] Apply **display policy**: wakelock on/off in Player mode

### 3.4 `NetworkService`
- [x] TCP port 6435 (Player listener + client `sendCommand` / `PING`)
- [x] Player: server — `PING`, `SELECT_STATION|n`, `MUTE`, `UNMUTE`, `GET_STATE`, `TESTURL|url`
- [x] Remote: client — `PING` (settings Test Connection)
- [x] Remote: client — send commands, parse `STATE|…`, poll
- [x] 2s connection timeout, 2.5s poll interval (Remote)
- [x] Local IP helper (bottom-left display) — `LocalNetworkInfo`

### 3.5 Mode orchestration
- [x] Player mode: TCP listener + display-policy wakelock
- [x] Remote mode: poll player; wakelock off
- [x] Mode switch: stop listener / poll, update UI rules

---

## Layer 4 — UI (4 extracted widgets + MainScreen chrome)

### 4.1 `StationGrid` + `StationTile`
- [x] Scrollable grid (portrait 3 columns / landscape 3 rows)
- [x] Station tile: logo or name fallback
- [x] Selected state highlight
- [ ] Start internatiolisation en/nl

### 4.2 `MainScreen` (static chrome inline — no separate widget files)
- [x] Mute button (playing / muted visuals)
- [x] Current station title
- [x] Local IP text
- [x] Player ↔ Remote toggle
- [x] Settings entry
- [x] Exit (Android)

### 4.3 `SettingsOverlay`
- [x] Player IP field + connection test (`PING` → OK / Error / Testing…)
- [x] URL test field (`TESTURL`, last station slot)
- [x] **Display policy** toggle (Player mode): keep screen on / allow screen off
- [x] Save to `SettingsRepository`

### 4.4 `ScreensaverOverlay`
- [x] 60s inactivity timer (reset on local touch) — logic in `ScreensaverController`
- [x] Full-screen overlay, bouncing station logo (only when display policy = keep screen on)
- [x] Disabled while settings open
- [x] Tap to dismiss
- [x] **Dismiss when Player receives remote command** (`RadioController` → `ScreensaverController`)

---

## Layer 5 — Screens & app shell

### 5.1 Replace PoC `main.dart`
- [x] `MaterialApp` + theme
- [x] Root provider / controller injection
- [x] Main screen: inline chrome + composes Layer 4 widgets/overlays

### 5.2 Layout
- [x] Responsive grid (landscape 3 rows + horizontal scroll, portrait 3 columns + vertical scroll)

### 5.3 Remote mode UI
- [x] Remote: station tap → `SELECT_STATION|index`
- [x] Remote: mute → `MUTE` / `UNMUTE`
- [x] Sync UI from polled state

---

## Milestones

| # | Scope | Delivers |
|---|--------|----------|
| **M1** | Layer 0 ✅ + 2.x + 3.1–3.3 + 4.1–4.2 + 5.1 | Real stations, main Player UI, mute, persist |
| **M2** | 4.4 | Screensaver, daily-use Player |
| **M3** | 3.4–3.5 + 5.3 + 6.2 | Remote control parity with Unity |

---

## Nice-to-have

- [X] Connection status indicator when trying to switch to Remote mode
- [X] Resolve redirect URLs before play (StreamTheWorld) — only if a fav station fails Media3 redirects
- [x] **Stream error → auto-retry with backoff** — native `RadioPlayerManager`: on transient `PlaybackException`, retry current URL with exponential backoff (1s→32s cap); `retryInSeconds` in state / status; reset on successful play / station change / stop
- [x] **Wake Player screen on remote command** — when display policy is `allowScreenOff` and the Player screen is asleep, a remote command (station change, mute, etc.) would turn the display on so the UI is visible without pressing the power button. Audio already responds to remote either way; this is display-only. Unnecessary when policy is `keepScreenOn`.
- [ ] STOP from remote to player with confirmation question if player should be stopped too.
