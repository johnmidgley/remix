#!/usr/bin/env python3
"""
One-time script to convert Demucs PyTorch model to ONNX format.
Run this once to generate the ONNX model, then you won't need Python anymore.

Requirements:
    pip install demucs torch onnx

Usage:
    python convert_demucs.py
"""

import torch
import torch.onnx
from demucs.pretrained import get_model

def convert_to_onnx(model_name="htdemucs_6s", output_path="htdemucs_6s.onnx"):
    print(f"Loading model: {model_name}")
    model = get_model(model_name)
    model.eval()
    
    # Create dummy input: [batch, channels, samples]
    # Using 10 seconds of audio at 44.1kHz
    dummy_input = torch.randn(1, 2, 441000)
    
    print(f"Exporting to ONNX: {output_path}")
    torch.onnx.export(
        model,
        dummy_input,
        output_path,
        input_names=["audio"],
        output_names=["stems"],
        dynamic_axes={
            "audio": {2: "samples"},
            "stems": {3: "samples"}
        },
        opset_version=14,
        do_constant_folding=True,
    )
    
    print(f"Done! Model saved to: {output_path}")
    print("\nYou can now rebuild the Remix app:")
    print("  cd .. && ./build-macos-app.sh")

if __name__ == "__main__":
    convert_to_onnx()
