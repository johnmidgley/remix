#!/usr/bin/env python3
"""
Downloads Demucs models for bundling with the app.
Models are saved to a 'models' directory that can be included in the app bundle.
"""

import argparse
import os
import sys
from pathlib import Path


def download_demucs_models(output_dir: Path, model_name: str = "htdemucs_6s"):
    """Download Demucs model weights to the specified directory."""
    
    print(f"Installing/checking dependencies...")
    
    # Ensure demucs is installed
    try:
        import demucs
    except ImportError:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "demucs"])
        import demucs
    
    from demucs.pretrained import get_model
    import torch
    
    print(f"Downloading model: {model_name}")
    
    # This triggers the download if not cached
    model = get_model(model_name)
    
    # Find where the model was cached
    # Demucs models are stored in torch hub cache
    torch_hub_dir = Path(torch.hub.get_dir()) / "checkpoints"
    
    # Also check the demucs-specific cache location
    home = Path.home()
    demucs_cache_locations = [
        torch_hub_dir,
        home / ".cache" / "torch" / "hub" / "checkpoints",
        home / ".cache" / "demucs",
    ]
    
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # The model files we need - demucs stores model configs and weights
    # The actual model name pattern varies
    model_patterns = [
        f"{model_name}*.th",
        f"{model_name}*.yaml", 
        f"htdemucs*.th",
        f"htdemucs*.yaml",
    ]
    
    import shutil
    import glob
    
    copied_files = []
    
    for cache_dir in demucs_cache_locations:
        if not cache_dir.exists():
            continue
            
        for pattern in model_patterns:
            for file_path in cache_dir.glob(pattern):
                dest = output_dir / file_path.name
                if not dest.exists():
                    print(f"  Copying: {file_path.name}")
                    shutil.copy2(file_path, dest)
                    copied_files.append(dest)
    
    # Demucs also stores model state in a different format
    # Let's save the model directly using torch
    model_state_path = output_dir / f"{model_name}.th"
    if not model_state_path.exists():
        print(f"  Saving model state: {model_state_path.name}")
        # Save model state dict
        torch.save({
            'state_dict': model.state_dict(),
            'model_name': model_name,
        }, model_state_path)
        copied_files.append(model_state_path)
    
    # Save model config/metadata
    config_path = output_dir / f"{model_name}_config.yaml"
    if not config_path.exists():
        import yaml
        config = {
            'name': model_name,
            'sources': list(model.sources),
            'samplerate': model.samplerate,
            'channels': model.audio_channels if hasattr(model, 'audio_channels') else 2,
        }
        with open(config_path, 'w') as f:
            yaml.dump(config, f)
        print(f"  Saved config: {config_path.name}")
        copied_files.append(config_path)
    
    if copied_files:
        print(f"\nModels saved to: {output_dir}")
        total_size = sum(f.stat().st_size for f in copied_files if f.exists())
        print(f"Total size: {total_size / 1024 / 1024:.1f} MB")
    else:
        print("\nNo new files to copy (models may already be in place)")
    
    # List final contents
    print(f"\nModel directory contents:")
    for f in sorted(output_dir.iterdir()):
        size_mb = f.stat().st_size / 1024 / 1024
        print(f"  {f.name} ({size_mb:.1f} MB)")
    
    return output_dir


def main():
    parser = argparse.ArgumentParser(description="Download Demucs models for app bundling")
    parser.add_argument(
        "-o", "--output",
        default="models",
        help="Output directory for models (default: ./models)"
    )
    parser.add_argument(
        "-m", "--model",
        default="htdemucs_6s",
        choices=["htdemucs_6s", "htdemucs", "htdemucs_ft"],
        help="Model to download (default: htdemucs_6s)"
    )
    
    args = parser.parse_args()
    
    output_dir = Path(args.output).resolve()
    download_demucs_models(output_dir, args.model)
    
    print("\nDone! You can now include this models directory in your app bundle.")


if __name__ == "__main__":
    main()
