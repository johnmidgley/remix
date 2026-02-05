<div align="center">
  <img src="scripts/Remix.png" alt="Remix Icon" width="128">
  <h1>Remix</h1>
</div>

Audio stem separation tool with a native macOS mixer interface. Uses AI-powered Demucs for professional-quality instrument separation.

<div align="center">
  <img src="Remix UI.png" alt="Remix UI" width="800">
</div>

## Quickstart

Get started with Remix in 3 steps:

### 1. Build the App
```bash
./build-macos-app.sh
```
The script will automatically check for Python dependencies and offer to install them if needed.

### 2. Run Remix
```bash
open Remix.app
```

### 3. Analyze Your First Track
1. **Drag & drop** an audio file (WAV, MP3, M4A, FLAC, AIFF, or OGG) onto the window
2. Click **"Analyze"** to separate the track into stems
   - First run downloads the AI model (~1GB) and may take a few minutes
   - Subsequent runs are much faster, and cached files load instantly
3. **Mix** using the faders - adjust volume, pan, solo/mute individual instruments
4. Press **Space** to play/pause, **Cmd+E** for EQ, **Cmd+B** to export

That's it! You're now remixing. 🎵

**Tip:** The app remembers all your settings (speed, pitch, EQ, etc.) for each song, so you can return anytime and pick up where you left off.

---

## Features

- **AI Instrument Separation**: Splits audio into 6 stems using Demucs:
  - Drums, Bass, Guitar, Keys (piano), Voice, Other
- **Multiple Formats**: Supports WAV, MP3, M4A, FLAC, AIFF, and OGG input files
- **Native macOS App**: Logic Pro-style interface with SwiftUI
- **Smart Progress Estimation**: Learns from each analysis to provide accurate time estimates
  - Starts with 1:1 ratio (1 minute processing per 1 minute audio)
  - Adapts based on your machine's performance
  - Shows progress bar with time remaining
- **Intelligent Caching**: Fast reload of previously analyzed files
- **Real-time Mixing**: Adjust volume levels for each stem with faders
- **8-Band Parametric EQ**: Professional-grade EQ with per-stem or global control
  - Separate, movable window for independent operation
  - Stereo EQ interface with vertical faders and real-time level meters
  - Visual feedback: meters show frequency content for each band
  - 10 bands from 32 Hz to 16 kHz
  - Adjustable gain (-12 to +12 dB) and Q (bandwidth) per band
  - Apply to individual stems or master output
- **Playback Controls**: Variable speed (0.5x-2x) and pitch shift (±2 semitones)
  - Settings remembered per song
- **Solo/Mute**: Isolate or mute individual stems
- **Pan Control**: Position each stem in the stereo field
- **Export**: Bounce your custom mix to a WAV file

## Native macOS App

### Build Requirements (Your Machine Only)

- **Rust** (for building the Rust library)
- **Xcode Command Line Tools** (for Swift compilation)
- **Python 3.8+** (for creating the bundled Python distribution)

**Note:** These are only needed to BUILD the app. The resulting app is fully standalone with no user dependencies.

The build script automatically:
1. Compiles the Rust and Swift code
2. Bundles Python + demucs into the app
3. Creates a fully standalone `Remix.app`

**Users need nothing** - they just download and run Remix.app!

### Building

```bash
./build-macos-app.sh
```

### Running

```bash
open "Remix.app"
```

### Using the App

1. **Drop/Open**: Drag audio file onto the window or use File > Open
2. **Preview**: Listen to the original audio before analyzing
3. **Analyze**: Click the Analyze button to separate stems
   - First run: Shows estimated time based on audio length (1:1 ratio)
   - Subsequent runs: Uses learned rate from your machine's performance
   - Progress bar shows time remaining during processing
   - Cached files load instantly without re-processing
4. **Mix**: Use faders to adjust each stem's volume and pan position
5. **Solo/Mute**: Click S to solo a stem, M to mute it
6. **EQ**: Click EQ button in toolbar (or press Cmd+E) to open parametric equalizer
   - Opens in separate, movable window that can be positioned anywhere
   - Select individual stems or Master from dropdown
   - Stereo EQ interface with 10 vertical faders (32 Hz - 16 kHz)
   - Real-time level meters beside each fader show frequency content
   - Adjust gain (-12 to +12 dB) and Q (bandwidth) per band
   - EQ settings saved per song and per stem
7. **Playback**: Use speed (0.5x-2x) and pitch (±2 semitones) controls
8. **Transport**: Space to play/pause, transport controls in toolbar
9. **Bounce**: Export your mix via File > Bounce or the toolbar button

### Keyboard Shortcuts

- `Cmd+O` - Open file
- `Cmd+B` - Bounce mix
- `Cmd+E` - Open EQ window
- `Cmd+R` - Reset all faders
- `Space` - Play/Pause
- `Return` - Stop
- `Cmd+L` - Toggle loop

### Playback Controls

- **Speed**: Adjust playback speed from 0.5x to 2x (accessible in toolbar)
- **Pitch**: Shift pitch ±2 semitones without affecting tempo (accessible in toolbar)

## Stem Separation

Uses Meta's Demucs v4 (htdemucs_6s) deep learning model:

| Stem | Description |
|------|-------------|
| **Drums** | Kick, snare, hi-hats, cymbals, percussion |
| **Bass** | Bass guitar, synth bass |
| **Guitar** | Electric and acoustic guitars |
| **Keys** | Piano, keyboards, synths |
| **Voice** | Lead and backing vocals |
| **Other** | Everything else (strings, horns, etc.) |

Quality: ~9 dB SDR (state-of-the-art)

## Smart Progress Estimation

Remix learns from each analysis to provide accurate time estimates:

1. **Initial Estimate**: First run assumes 1:1 ratio (1 minute processing per 1 minute audio)
2. **Adaptive Learning**: After each analysis, adjusts estimate based on actual time taken
3. **Machine-Specific**: Learns your specific machine's performance characteristics
4. **Persistent Memory**: Remembers learned rate between app launches
5. **Cache Awareness**: Only updates estimates from actual processing, not cache loads

Example: If your machine processes a 3-minute song in 6 minutes, future estimates will be closer to 2:1 ratio.

## How Demucs Works

Demucs v4 uses a hybrid transformer architecture:
1. Dual U-Net processes audio in both time and frequency domains
2. Cross-domain transformer enables attention across domains
3. Trained on MUSDB18-HQ + 800 additional songs
4. Achieves 9.0+ dB SDR (Signal-to-Distortion Ratio)

## License

Remix application code is licensed under the **Apache License 2.0** (see [LICENSE](LICENSE)).

### Third-Party Software

This application includes the following open-source software:

- **Demucs** - MIT License (Meta Platforms, Inc.) - AI music separation
- **PyTorch** - BSD-3-Clause License (Meta Platforms, Inc.) - Deep learning framework
- **Python** - Python Software Foundation License - Bundled runtime
- **Rust libraries** (hound, symphonia, anyhow, etc.) - Various open-source licenses

See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for complete licensing information.

### Commercial Use

✅ **You may use Remix commercially** under the terms of the Apache 2.0 license.  
✅ **Demucs (MIT License) permits commercial use** with proper attribution.

All required license files are included in the app bundle.

## Architecture

The app is built with:
- **Rust**: Audio processing, FFI layer, and Python integration
- **Swift/SwiftUI**: Native macOS user interface
- **Bundled Python**: Complete Python runtime + demucs packaged in the app
- **Demucs v4**: Full-quality AI model for stem separation (6 stems)

## Standalone App - Zero User Dependencies!

Remix is **fully standalone** - users just download and run:

✅ **No Python installation required**  
✅ **No pip packages needed**  
✅ **All dependencies bundled in the app**  
✅ **Works on any macOS system out of the box**  
✅ **Professional-quality AI with full Demucs v4**

The app bundles everything it needs:
- Python runtime (~50MB)
- Demucs + dependencies (~200MB)
- PyTorch and torchaudio
- All audio processing libraries
- Native Swift UI

Simply copy `Remix.app` to any Mac and it works - no setup required!

**App size**: ~300-500MB (comparable to professional audio software)

## Technical Details

### Bundled Python Distribution
The app uses a minimal Python distribution bundled inside the app bundle:
- **Build time**: Script creates isolated Python environment with demucs
- **Runtime**: App automatically uses bundled Python (invisible to users)
- **Size optimization**: Unnecessary files pruned (~200-300MB final bundle)
- **Zero interference**: Doesn't affect system Python installation

See [BUNDLED_PYTHON.md](BUNDLED_PYTHON.md) and [BUILD_STANDALONE.md](BUILD_STANDALONE.md) for details.

### Performance Notes
- **Processing time**: Varies by machine (typically 1-5 minutes per minute of audio)
  - App learns your machine's speed and provides accurate estimates
  - First run downloads the AI model (~350MB) automatically
- **Smart caching**: Previously analyzed files load instantly from cache
- **Per-song settings**: Speed, pitch, loop, and EQ settings are saved individually for each song
  - Return to any song and your preferred playback and EQ settings are restored
  - Each stem can have unique EQ curves that are remembered
- **Supported formats**: WAV, MP3, M4A, FLAC, AIFF, and OGG input; output is always WAV
- **Progress tracking**: Real-time progress bar with time-remaining estimates
- **Model storage**: Demucs model cached in `~/.cache/torch/hub/checkpoints/`