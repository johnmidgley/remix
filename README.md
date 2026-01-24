# Remix

Audio stem separation tool with a native macOS mixer interface. Supports AI-powered instrument separation via Demucs, or spectral decomposition via PCA.

## Features

- **Demucs Instrument Separation**: Splits audio into 6 stems using AI:
  - Drums, Bass, Vocals, Guitar, Keys (piano), Other
- **PCA Mode**: Experimental spectral decomposition into principal components
- **Multiple Formats**: Supports WAV and MP3 input files
- **Native macOS App**: Logic Pro-style interface with SwiftUI
- **Real-time Mixing**: Adjust volume levels for each stem with faders
- **Solo/Mute**: Isolate or mute individual stems
- **Playback**: Listen to your mix in real-time
- **Export**: Bounce your custom mix to a WAV file

## Native macOS App

### Building

```bash
./build-macos-app.sh
```

### Running

```bash
open "Remix.app"
```

### Requirements for Demucs Mode

- **Python 3** (installed at `/usr/bin/python3`, `/usr/local/bin/python3`, or `/opt/homebrew/bin/python3`)
- **Demucs** will be auto-installed on first use (~4GB download)
- First separation takes several minutes; subsequent runs are faster

### Using the App

1. **Select Mode**: Choose "Demucs (Instruments)" or "PCA (Spectral)"
2. **Drop/Open**: Drag audio file onto the window or use File > Open
3. **Wait**: Demucs takes 2-5 minutes depending on file length
4. **Mix**: Use faders to adjust each stem's volume
5. **Solo/Mute**: Click S to solo a stem, M to mute it
6. **Transport**: Space to play/pause, transport controls in toolbar
7. **Bounce**: Export your mix via File > Bounce or the toolbar button

### Keyboard Shortcuts

- `Cmd+O` - Open file
- `Cmd+B` - Bounce mix
- `Cmd+R` - Reset all faders
- `Space` - Play/Pause
- `Return` - Stop
- `Cmd+L` - Toggle loop

## Separation Modes

### Demucs (Recommended)

Uses Meta's Demucs v4 (htdemucs_6s) deep learning model to separate:

| Stem | Description |
|------|-------------|
| **Drums** | Kick, snare, hi-hats, cymbals, percussion |
| **Bass** | Bass guitar, synth bass |
| **Vocals** | Lead and backing vocals |
| **Guitar** | Electric and acoustic guitars |
| **Keys** | Piano, keyboards, synths |
| **Other** | Everything else (strings, horns, etc.) |

Quality: ~9 dB SDR (state-of-the-art)

### PCA (Experimental)

Decomposes audio by spectral patterns using Principal Component Analysis. Does NOT separate instruments - separates by frequency content patterns. Useful for experimental audio manipulation.

## CLI / Web Version

The original CLI and web interface are still available:

```bash
cargo build --release
./target/release/music-tool           # Web server on localhost:3000
./target/release/music-tool --cli -i audio.wav -n 4 -o ./output  # CLI mode
```

## How Demucs Works

Demucs v4 uses a hybrid transformer architecture:
1. Dual U-Net processes audio in both time and frequency domains
2. Cross-domain transformer enables attention across domains
3. Trained on MUSDB18-HQ + 800 additional songs
4. Achieves 9.0+ dB SDR (Signal-to-Distortion Ratio)

## Building from Source

### macOS App
```bash
./build-macos-app.sh
```

### Rust Library + CLI
```bash
cargo build --release
```

## Notes

- Demucs requires ~4GB disk space for models (downloaded on first run)
- Processing time: ~2-5 minutes for a typical 3-4 minute song
- GPU acceleration available if CUDA is configured
- Supports WAV and MP3 input; output is always WAV
