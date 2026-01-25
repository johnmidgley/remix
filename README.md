# Remix

Audio stem separation tool with a native macOS mixer interface. Uses AI-powered Demucs for professional-quality instrument separation.

**Pure Rust implementation** - no Python dependencies required at runtime.

## Features

- **AI Instrument Separation**: Splits audio into 6 stems using Demucs:
  - Drums, Bass, Vocals, Guitar, Keys (piano), Other
- **Multiple Formats**: Supports WAV and MP3 input files
- **Native macOS App**: Logic Pro-style interface with SwiftUI
- **Real-time Mixing**: Adjust volume levels for each stem with faders
- **Solo/Mute**: Isolate or mute individual stems
- **Playback**: Listen to your mix in real-time
- **Export**: Bounce your custom mix to a WAV file
- **No Python Required**: Uses ONNX Runtime for native inference

## Native macOS App

### Building

```bash
# Standard build (includes bundled Demucs ONNX model)
./build-macos-app.sh

# Build without models (smaller app, requires manual model download)
./build-macos-app.sh --no-models
```

By default, the build script downloads the Demucs ONNX model (~85MB) and bundles it with the app. Use `--no-models` for a smaller app (you'll need to provide the model separately).

### Running

```bash
open "Remix.app"
```

### Requirements

- **Rust** (for building)
- **Xcode Command Line Tools** (for Swift compilation)
- **ONNX Runtime** - Install via Homebrew:
  ```bash
  brew install onnxruntime
  ```

### ONNX Model Setup

The app requires a Demucs ONNX model for stem separation. You have two options:

**Option 1: Automatic download** (if a pre-built model is available)
```bash
./build-macos-app.sh  # Will attempt to download the model
```

**Option 2: Convert from PyTorch** (one-time Python step)
```bash
# Create and enter models directory
mkdir -p models && cd models

# Install Python dependencies (one-time)
pip install demucs torch onnx

# Run the conversion script (created by build if download fails)
python convert_demucs.py

# Return to project root and rebuild
cd .. && ./build-macos-app.sh
```

After conversion, you won't need Python anymore - the app runs entirely on Rust/ONNX Runtime.

- First separation takes 2-5 minutes depending on audio length

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

The model runs via ONNX Runtime for efficient cross-platform inference.

## Building from Source

```bash
# Install dependencies
brew install onnxruntime

# Build the app
./build-macos-app.sh
```

## Architecture

The app is built with:
- **Rust**: Audio processing, ONNX inference, and FFI layer
- **Swift/SwiftUI**: Native macOS user interface
- **ONNX Runtime**: Neural network inference

## Notes

- ONNX model size: ~85MB (bundled with app by default)
- Processing time: ~2-5 minutes for a typical 3-4 minute song
- Supports WAV and MP3 input; output is always WAV
- Caches analysis results for faster subsequent loads
