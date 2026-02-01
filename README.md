<div align="center">
  <img src="scripts/Remix.png" alt="Remix Icon" width="128">
  <h1>Remix</h1>
</div>

Audio stem separation tool with a native macOS mixer interface. Uses AI-powered Demucs for professional-quality instrument separation.

<div align="center">
  <img src="Remix UI.png" alt="Remix UI" width="800">
</div>

## Features

- **AI Instrument Separation**: Splits audio into 6 stems using Demucs:
  - Drums, Bass, Guitar, Keys (piano), Voice, Other
- **Multiple Formats**: Supports WAV and MP3 input files
- **Native macOS App**: Logic Pro-style interface with SwiftUI
- **Smart Progress Estimation**: Learns from each analysis to provide accurate time estimates
  - Starts with 1:1 ratio (1 minute processing per 1 minute audio)
  - Adapts based on your machine's performance
  - Shows progress bar with time remaining
- **Intelligent Caching**: Fast reload of previously analyzed files
- **Real-time Mixing**: Adjust volume levels for each stem with faders
- **Playback Controls**: Variable speed (0.5x-2x) and pitch shift (±2 semitones)
  - Settings remembered per song
- **Solo/Mute**: Isolate or mute individual stems
- **Pan Control**: Position each stem in the stereo field
- **Export**: Bounce your custom mix to a WAV file

## Native macOS App

### Requirements

- **Rust** (for building)
- **Xcode Command Line Tools** (for Swift compilation)
- **Python 3** with demucs package:
  ```bash
  pip install demucs
  ```

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
6. **Playback**: Use speed (0.5x-2x) and pitch (±2 semitones) controls
7. **Transport**: Space to play/pause, transport controls in toolbar
8. **Bounce**: Export your mix via File > Bounce or the toolbar button

### Keyboard Shortcuts

- `Cmd+O` - Open file
- `Cmd+B` - Bounce mix
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

## Architecture

The app is built with:
- **Rust**: Audio processing and FFI layer
- **Swift/SwiftUI**: Native macOS user interface
- **Python/Demucs**: AI-powered stem separation (called as subprocess)

## Troubleshooting

### PyTorch 2.8.0 Compatibility Issue

If you see an error like:
```
RuntimeError: unsupported operation: more than one element of the written-to tensor 
refers to a single memory location. Please clone() the tensor before performing the operation.
```

This is due to stricter memory overlap checks in PyTorch 2.8.0. To fix:

**Automatic Fix (Recommended):**
```bash
python3 -c "import os; path = os.path.expanduser('~/Library/Python/3.9/lib/python/site-packages/demucs/separate.py'); content = open(path).read(); content = content.replace('wav -= ref.mean()', 'wav = wav - ref.mean()').replace('wav /= ref.std()', 'wav = wav / ref.std()'); open(path, 'w').write(content)"
```

**Manual Fix:**
Edit your demucs installation file (typically `~/Library/Python/3.9/lib/python/site-packages/demucs/separate.py`):

Line 171: Change `wav -= ref.mean()` to `wav = wav - ref.mean()`  
Line 172: Change `wav /= ref.std()` to `wav = wav / ref.std()`

**Alternative:** Downgrade PyTorch (not recommended):
```bash
pip install torch==2.5.0
```

**Note:** This patch needs to be reapplied if you upgrade/reinstall demucs. The demucs maintainers will likely fix this in a future release.

## Notes

- **Processing time**: Varies by machine (typically 1-5 minutes per minute of audio)
  - App learns your machine's speed and provides accurate estimates
  - First analysis may be slower while downloading the model
- **Smart caching**: Previously analyzed files load instantly from cache
- **Per-song settings**: Speed, pitch, and loop settings are saved individually for each song
  - Return to any song and your preferred playback settings are restored
- **Supported formats**: WAV and MP3 input; output is always WAV
- **First run**: Downloads Demucs model (~1GB)
- **Progress tracking**: Real-time progress bar with time-remaining estimates