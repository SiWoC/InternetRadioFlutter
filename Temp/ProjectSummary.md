# Internet Radio Unity - Project Summary

## Project Overview
A Unity-based internet radio streaming application designed to run on Android phones, connecting through the headphone jack to audio receivers. Built with Unity 6.2 and FMOD audio engine.

## Core Features
- **Internet Radio Streaming** - Stream radio stations using FMOD audio engine
- **Remote Control** - Install app on two devices; one acts as Player, the other as Remote controller
- **Custom Station Library** - Configure multiple radio stations with logos via JSON configuration
- **Mute/Unmute Control** - Toggle audio playback (mutes stream to keep connection alive, avoiding commercials on resume)
- **Screensaver Mode** - Automatic screensaver with bouncing station artwork after 60 seconds of inactivity
- **Dual Operating Modes** - Player mode (plays audio) and Remote mode (controls Player device)

## Technologies
- **Unity 6.2** - Game engine and UI framework
- **FMOD** - Professional audio streaming engine
- **TextMeshPro** - UI text rendering
- **Unity Input System** - Touch and mouse input handling
- **TCP/IP Networking** - Custom protocol for remote control (port 6435)

## Project Structure

### Main Scripts
- **MainSceneController.cs** - Main UI controller and application logic
- **FMODRadioStreamer.cs** - Handles FMOD audio streaming
- **NetworkManager.cs** - TCP/IP networking for remote control
- **ScreensaverController.cs** - Screensaver with bouncing station image
- **Settings.cs** - Static class for PlayerPrefs persistence
- **RadioStation.cs** - Serializable data class for station info
- **Utils.cs** - Utility functions (IP address detection, etc.)
- **AudioRouteFixer.cs** - Android-specific audio routing fixes

### Configuration Files
- **Assets/Resources/settings.json** - Radio station configuration (name, URL, image path)
- **Assets/Resources/images/** - Station logo images (PNG/WEBP)

### UI Prefabs
- **Assets/Prefabs/StationButton.prefab** - Prefab for dynamically created station buttons

## UI Elements

### Main Panel (MainSceneController.cs)
1. **Canvas** (`uiCanvas`) - Main UI canvas
2. **Mute Button** (`muteButton`) - Button with two state GameObjects:
   - `muteButtonPlaying` - Visual for playing state
   - `muteButtonMuted` - Visual for muted state
3. **Mode Toggle Buttons**:
   - `remoteButton` - Button to switch to Remote mode (shown in Player mode)
   - `playerButton` - Button to switch to Player mode (shown in Remote mode)
4. **Station Name Text** (`stationNameText`) - TextMeshProUGUI displaying current station name (e.g., "All Time Top 40 hits")
5. **Station Grid**:
   - `stationScrollView` - RectTransform for scrollable container
   - `stationListParent` - Transform parent for dynamically created station buttons
   - `stationButtonPrefab` - Prefab used to instantiate station buttons
6. **IP Address Text** (`ipAddressText`) - TextMeshProUGUI showing local IP address (bottom-left)
7. **Exit Button** - Red circular button (top-right) that calls `OnExit()` method

### Settings Panel (Overlay)
8. **Settings Panel** (`settingsPanel`) - GameObject overlay panel
9. **Player IP Input Field** (`playerIPAddressInputField`) - TMP_InputField for entering Player device IP address
10. **Connection Test Result Text** (`settingsPlayerConnectionTestResultText`) - TextMeshProUGUI showing connection test status ("OK", "Error", "Testing...")
11. **URL Test Input Field** (`settingsURLToTestInputField`) - TMP_InputField for testing stream URLs

### Screensaver (ScreensaverController.cs)
- **Screensaver Button** (`screensaverButton`) - Full-screen button for touch detection
- **Station Image** (`stationImage`) - Bouncing station logo image (child of screensaver button)
- **Unknown Sprite** (`unknown`) - Fallback sprite when station image not available

## Station Configuration

### JSON Format (Assets/Resources/settings.json)
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

### Station Data Structure
- **name** - Display name shown in UI
- **url** - Direct streaming URL (FMOD supports various formats: MP3, OGG, etc.)
- **image** - Logo path relative to Resources folder (without .png extension)

### Image Loading
- Images loaded from `Assets/Resources/images/` folder
- Supports PNG and WEBP formats
- If image not found, station name is displayed as text fallback
- Last station in list is used as "Testing" station for URL testing

### Fallback Stations
If `settings.json` fails to load, hardcoded fallback stations are used:
- ABC Triple J NSW
- Q-Music
- Radio 538

## Operating Modes

### Player Mode
- Plays audio streams locally
- Listens for TCP commands on port 6435
- Prevents device sleep (`SleepTimeout.NeverSleep`)
- Shows `remoteButton` (to switch to Remote mode)
- Responds to commands: SELECT_STATION, MUTE, UNMUTE, GET_STATE, TESTURL

### Remote Mode
- Controls Player device over network
- Polls Player state every 2.5 seconds (`STATE_POLL_INTERVAL`)
- Shows `playerButton` (to switch to Player mode)
- Sends commands to Player device
- Allows device sleep (`SleepTimeout.SystemSetting`)

## Network Protocol

### Port
- **6435** - TCP port for remote control communication

### Commands (Remote → Player)
- `PING` - Connection test (responds with `PONG`)
- `SELECT_STATION|<index>` - Switch to station by index
- `TESTURL|<url>` - Test a stream URL (uses last station slot)
- `MUTE` - Mute audio
- `UNMUTE` - Unmute audio
- `GET_STATE` - Request current state

### State Response Format
- `STATE|<stationIndex>|<muteState>` where muteState is "MUTED" or "PLAYING"

### Connection Timeout
- 2 seconds (`CONNECTION_TIMEOUT`)

## Persistence (Settings.cs)
Uses Unity PlayerPrefs to store:
- `CurrentStation` - Last selected station name
- `OperatingMode` - Player (0) or Remote (1)
- `PlayerIPAddress` - IP address of Player device
- `TestURL` - URL for testing streams

## Layout & Responsive Design

### Orientation Handling
- **Landscape**: 3-column grid, adjusted canvas scaler (matchWidthOrHeight = 0.6)
- **Portrait**: Dynamic grid rows based on screen height, proportional distribution of space between station name and scroll view

### Station Grid
- Uses `GridLayoutGroup` component
- Horizontal scrolling enabled
- Content width calculated dynamically based on number of stations and rows
- Station buttons display logos when available, otherwise show station name text

## Screensaver Behavior
- Activates after 60 seconds (`inactivityTimeout`) of no input
- Shows bouncing station logo animation
- Bounces off screen edges with random angle changes
- Touch anywhere on screensaver exits
- Does not activate when settings panel is open
- Station image updates when station changes

## Audio Features

### FMOD Integration
- Uses FMOD RuntimeManager for system initialization
- Streams audio directly from URLs
- Handles pause/resume (stops stream on pause to save bandwidth)
- Mute functionality (keeps stream alive, just mutes output)

### Android-Specific
- Audio route fix for devices that default to speaker after reboot
- Configurable delay for audio route fix application
- Headphone jack output preferred

## Key Methods & Functionality

### MainSceneController
- `SetupStations()` - Loads stations from JSON or fallback
- `CreateStationButtons()` - Dynamically creates station button grid
- `SelectStation(int index)` - Switches station (handles both modes)
- `ToggleMute()` - Mutes/unmutes audio
- `OnRemote()` / `OnPlayer()` - Mode switching
- `OnSettings()` - Opens settings panel
- `PollPlayerState()` - Remote mode state synchronization
- `UpdateLayoutForOrientation()` - Responsive layout updates

### FMODRadioStreamer
- `PlayStream(string url)` - Starts streaming from URL
- `StopStream()` - Stops current stream
- `ToggleMuteStream()` - Mutes/unmutes audio
- `IsMuted()` - Returns mute state
- Event: `OnMuteStateChanged` - Fired when mute state changes

### NetworkManager
- `StartListener()` - Starts TCP listener (Player mode)
- `StopListener()` - Stops TCP listener
- `TestConnection(string ip)` - Tests connection to Player
- `SendCommand(string ip, string command)` - Sends command to Player
- Events: `OnStationSelected`, `OnTestURL`, `OnMuteRequested`, `OnUnmuteRequested`, `OnStateRequested`

## Development Notes
- Unity version: 6.2
- Prefer Inspector-based configuration where possible
- Commented code blocks are kept as backup (do not remove)
- When refactoring, ask before touching additional code
- Avoid creating complete markdown recap files unless requested

## Build Configuration
- Target platform: Android
- Uses FMOD Unity Integration plugin
- Requires FMOD Studio project (minimal) for build initialization
- Builds stored in `AndroidBuilds/` folder

