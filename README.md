# Remix

Audio stem separation tool with a native macOS mixer interface. Uses AI-powered Demucs for professional-quality instrument separation.

## Features

- **AI Instrument Separation**: Splits audio into 6 stems using Demucs:
  - Drums, Bass, Vocals, Guitar, Keys (piano), Other
- **Multiple Formats**: Supports WAV and MP3 input files
- **Native macOS App**: Logic Pro-style interface with SwiftUI
- **Real-time Mixing**: Adjust volume levels for each stem with faders
- **Solo/Mute**: Isolate or mute individual stems
- **Playback**: Listen to your mix in real-time
- **Export**: Bounce your custom mix to a WAV file

## Native macOS App

### Building

```bash
# Standard build (includes bundled Demucs models)
./build-macos-app.sh

# Build without models (smaller app, downloads on first use)
./build-macos-app.sh --no-models
```

By default, the build script pre-downloads the Demucs AI model (~80MB) and bundles it with the app. This eliminates the model download for end users. Use `--no-models` for a smaller app that downloads models on first use.

### Running

```bash
open "Remix.app"
```

### Requirements

- **Python 3** (installed at `/usr/bin/python3`, `/usr/local/bin/python3`, or `/opt/homebrew/bin/python3`)
- **Demucs** will be auto-installed on first use (~4GB download for Python packages)
- If built with `--with-models`, the AI model is pre-bundled (~80MB saved)
- First separation takes several minutes; subsequent runs are faster

### Using the App

1. **Drop/Open**: Drag audio file onto the window or use File > Open
2. **Wait**: Demucs takes 2-5 minutes depending on file length
3. **Mix**: Use faders to adjust each stem's volume
4. **Solo/Mute**: Click S to solo a stem, M to mute it
5. **Transport**: Space to play/pause, transport controls in toolbar
6. **Bounce**: Export your mix via File > Bounce or the toolbar button

### Keyboard Shortcuts

- `Cmd+O` - Open file
- `Cmd+B` - Bounce mix
- `Cmd+R` - Reset all faders
- `Space` - Play/Pause
- `Return` - Stop
- `Cmd+L` - Toggle loop

## Stem Separation

Uses Meta's Demucs v4 (htdemucs_6s) deep learning model:

| Stem | Description |
|------|-------------|
| **Drums** | Kick, snare, hi-hats, cymbals, percussion |
| **Bass** | Bass guitar, synth bass |
| **Vocals** | Lead and backing vocals |
| **Guitar** | Electric and acoustic guitars |
| **Keys** | Piano, keyboards, synths |
| **Other** | Everything else (strings, horns, etc.) |

Quality: ~9 dB SDR (state-of-the-art)

## How Demucs Works

Demucs v4 uses a hybrid transformer architecture:
1. Dual U-Net processes audio in both time and frequency domains
2. Cross-domain transformer enables attention across domains
3. Trained on MUSDB18-HQ + 800 additional songs
4. Achieves 9.0+ dB SDR (Signal-to-Distortion Ratio)

## Building from Source

```bash
./build-macos-app.sh
```

## Notes

- Demucs requires ~4GB disk space for models (downloaded on first run)
- Processing time: ~2-5 minutes for a typical 3-4 minute song
- GPU acceleration available if CUDA is configured
- Supports WAV and MP3 input; output is always WAV
