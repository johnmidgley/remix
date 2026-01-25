#!/usr/bin/env python3
"""
Demucs audio separation wrapper script.
Separates audio into 6 stems: drums, bass, vocals, guitar, piano, other

Uses soundfile as the audio backend to avoid FFmpeg dependency.
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def check_and_install_deps():
    """Check and install required dependencies."""
    required = ['demucs', 'soundfile']
    missing = []
    
    for pkg in required:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    
    if missing:
        print(f"Installing missing packages: {missing}", file=sys.stderr)
        try:
            subprocess.check_call([
                sys.executable, "-m", "pip", "install", "--user"
            ] + missing, stderr=subprocess.STDOUT)
            print("Packages installed successfully", file=sys.stderr)
        except subprocess.CalledProcessError as e:
            print(f"Failed to install packages: {e}", file=sys.stderr)
            return False
    
    return True


def find_bundled_model_dir():
    """Find bundled models directory (in app bundle Resources or development location)."""
    script_path = Path(__file__).resolve()
    
    # Check if running from app bundle: .app/Contents/Resources/demucs_separate.py
    # Models would be at: .app/Contents/Resources/models/
    resources_models = script_path.parent / "models"
    if resources_models.exists():
        return resources_models
    
    # Development location: scripts/demucs_separate.py -> models/
    dev_models = script_path.parent.parent / "models"
    if dev_models.exists():
        return dev_models
    
    return None


def separate_audio(input_path: str, output_dir: str, model: str = "htdemucs_6s"):
    """
    Separate audio using Demucs with soundfile backend.
    Uses bundled models if available, otherwise downloads from internet.
    """
    import torch
    import torchaudio
    import soundfile as sf
    import numpy as np
    
    input_path = Path(input_path)
    output_dir = Path(output_dir)
    
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"Loading audio from {input_path}...", file=sys.stderr)
    
    # Load audio using soundfile directly
    audio_data, sample_rate = sf.read(str(input_path), dtype='float32')
    
    # Convert to tensor in expected format (channels, samples)
    if audio_data.ndim == 1:
        # Mono - duplicate to stereo
        audio_tensor = torch.from_numpy(audio_data).unsqueeze(0).repeat(2, 1)
    else:
        # Stereo or multi-channel - transpose to (channels, samples)
        audio_tensor = torch.from_numpy(audio_data.T)
        if audio_tensor.shape[0] > 2:
            audio_tensor = audio_tensor[:2]  # Take first 2 channels
        elif audio_tensor.shape[0] == 1:
            audio_tensor = audio_tensor.repeat(2, 1)
    
    # Ensure float32
    audio_tensor = audio_tensor.float()
    
    print(f"Audio shape: {audio_tensor.shape}, sample rate: {sample_rate}", file=sys.stderr)
    
    # Load demucs model - check for bundled models first
    from demucs.pretrained import get_model
    from demucs.apply import apply_model
    
    bundled_dir = find_bundled_model_dir()
    
    print(f"Loading model {model}...", file=sys.stderr)
    
    if bundled_dir:
        # Check if bundled model exists
        model_file = bundled_dir / f"{model}.th"
        if model_file.exists():
            print(f"Using bundled model from {bundled_dir}", file=sys.stderr)
            # Set torch hub dir to use bundled models
            os.environ['TORCH_HOME'] = str(bundled_dir.parent)
    
    demucs_model = get_model(model)
    demucs_model.eval()
    
    # Use CPU for compatibility (MPS has limitations with large convolutions)
    # CUDA would work but most Mac users don't have it
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    print(f"Using device: {device}", file=sys.stderr)
    demucs_model.to(device)
    
    # Add batch dimension
    audio_batch = audio_tensor.unsqueeze(0).to(device)
    
    # Resample if needed (demucs expects 44100 Hz)
    if sample_rate != demucs_model.samplerate:
        print(f"Resampling from {sample_rate} to {demucs_model.samplerate}...", file=sys.stderr)
        resampler = torchaudio.transforms.Resample(sample_rate, demucs_model.samplerate).to(device)
        audio_batch = resampler(audio_batch)
        sample_rate = demucs_model.samplerate
    
    print("Separating (this may take a few minutes)...", file=sys.stderr)
    
    # Apply model
    with torch.no_grad():
        sources = apply_model(demucs_model, audio_batch, device=device, progress=True)
    
    # sources shape: (batch, num_sources, channels, samples)
    sources = sources[0]  # Remove batch dim
    
    # Get stem names from model
    stem_names = demucs_model.sources
    print(f"Stems: {stem_names}", file=sys.stderr)
    
    # Save stems
    stems_dir = output_dir / model / input_path.stem
    stems_dir.mkdir(parents=True, exist_ok=True)
    
    result = {
        "model": model,
        "input": str(input_path),
        "stems": {}
    }
    
    for i, stem_name in enumerate(stem_names):
        stem_audio = sources[i].cpu().numpy().T  # (samples, channels)
        stem_path = stems_dir / f"{stem_name}.wav"
        
        sf.write(str(stem_path), stem_audio, sample_rate)
        result["stems"][stem_name] = str(stem_path)
        print(f"Saved {stem_name} to {stem_path}", file=sys.stderr)
    
    return result


def main():
    parser = argparse.ArgumentParser(description="Separate audio using Demucs")
    parser.add_argument("input", help="Input audio file")
    parser.add_argument("-o", "--output", required=True, help="Output directory")
    parser.add_argument("-m", "--model", default="htdemucs_6s", 
                        choices=["htdemucs_6s", "htdemucs", "htdemucs_ft"],
                        help="Demucs model (default: htdemucs_6s for 6 stems)")
    parser.add_argument("--install", action="store_true", 
                        help="Install dependencies if not found")
    parser.add_argument("--json", action="store_true",
                        help="Output result as JSON")
    
    args = parser.parse_args()
    
    # Check/install dependencies
    if args.install:
        if not check_and_install_deps():
            sys.exit(1)
    else:
        try:
            import demucs
            import soundfile
        except ImportError as e:
            print(f"Missing dependency: {e}", file=sys.stderr)
            print("Run with --install to auto-install dependencies", file=sys.stderr)
            sys.exit(1)
    
    try:
        result = separate_audio(args.input, args.output, args.model)
        
        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print(f"Separation complete!")
            print(f"Model: {result['model']}")
            print(f"Stems:")
            for stem, path in result['stems'].items():
                print(f"  {stem}: {path}")
        
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
