# Internet Radio Unity

A Unity-based internet radio streaming application designed to run on one of my old Android phones which I connect through the headphone jack to my receiver.

![Internet Radio Lego Frame](Internet%20Radio%20Lego%20frame.jpg)

## Features

- **Internet Radio** - Stream radio stations using FMOD audio engine
- **Remote Control** - Install the app on two devices and control one with the other
- **Custom Station Library** - Configure multiple radio stations with logos through a "hardcoded json" before building.
- **Mute/Unmute Control** - Toggle audio playback (current build mutes the stream which means it keeps consuming data, but prevents having to listen to the start commercial on resume)
- **Screensaver Mode** - Automatic screensaver with station artwork

## Technologies

- **Unity 6.2** - Game engine and UI framework
- **FMOD** - Professional audio streaming engine

## Requirements

- Unity 6.2 or later
- FMOD Unity Integration
- FMOD Studio with a minimal project (although I only use the streaming api atm, building the app requires the FMOD plugin to be initialized with an actual project)

## Configuration

### Adding Radio Stations

Radio stations are configured via JSON file located at `Assets/Resources/settings.json`:

```json
{
  "station": [
    {
      "name": "Station Name",
      "url": "https://stream-url.com/stream",
      "image": "station-logo"
    }
  ]
}
```

- **name** - Display name of the station
- **url** - Direct streaming URL (test which streams work, FMOD tries different formats like ogg and MIDI)
- **image** - Logo filename in `Assets/Resources/` (without .png extension)

Station logos should be placed in the `Assets/Resources/` folder as PNG or WEBP images (this can be in an images subfolder).

### Fallback Stations

If `settings.json` fails to load, the app includes hardcoded fallback stations:
- ABC Triple J NSW
- Q-Music
- Radio 538

## Controls

- **Station Buttons** - Tap to switch stations
- **Mute Button** - Toggle audio on/off
- **Exit Button** - Close application (Android only)
- **Touch/Mouse** - Resets screensaver timer

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Notes

- The application prevents device sleep while running
- Screensaver activates after period of inactivity
- Station state persists between app sessions

