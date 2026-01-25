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
import torch.nn as nn
from demucs.pretrained import get_model
from demucs.apply import BagOfModels
import types

def convert_to_onnx(model_name="htdemucs_6s", output_path="htdemucs_6s.onnx"):
    print(f"Loading model: {model_name}")
    bag = get_model(model_name)
    
    print(f"Model type: {type(bag)}")
    print(f"Model sources: {bag.sources}")
    print(f"Model sample rate: {bag.samplerate}")
    
    # BagOfModels contains multiple models - get the first one
    if isinstance(bag, BagOfModels):
        print(f"BagOfModels contains {len(bag.models)} model(s)")
        model = bag.models[0]
        print(f"Using first model: {type(model)}")
    else:
        model = bag
    
    model.eval()
    model.cpu()
    
    print(f"Inner model sources: {model.sources}")
    print(f"Inner model type: {type(model).__name__}")
    
    # Get the original HTDemucs forward method
    from demucs.htdemucs import HTDemucs
    original_htdemucs_forward = HTDemucs.forward
    
    # Monkey-patch to enable forward
    def unblocked_forward(self, mix):
        return original_htdemucs_forward(self, mix)
    
    model.forward = types.MethodType(unblocked_forward, model)
    
    # Create dummy input
    sample_rate = model.samplerate
    duration_samples = sample_rate * 7  # 7 seconds
    dummy_input = torch.randn(1, 2, duration_samples)
    
    print(f"\nInput shape: {dummy_input.shape}")
    print(f"Duration: {duration_samples / sample_rate:.2f}s at {sample_rate}Hz")
    
    # Test forward pass
    print("Testing forward pass...")
    with torch.no_grad():
        test_output = model(dummy_input)
    print(f"Output shape: {test_output.shape}")
    print(f"Number of stems: {test_output.shape[1]}")
    
    # Try dynamo export (newer PyTorch API)
    print(f"\nExporting to ONNX using dynamo: {output_path}")
    print("This may take several minutes...")
    
    try:
        # Try the newer dynamo-based export
        export_output = torch.onnx.dynamo_export(model, dummy_input)
        export_output.save(output_path)
        print("Dynamo export successful!")
    except Exception as e:
        print(f"Dynamo export failed: {e}")
        print("\nTrying alternative: JIT script then export...")
        
        # Try scripting instead of tracing
        try:
            scripted = torch.jit.script(model)
            torch.onnx.export(
                scripted,
                dummy_input,
                output_path,
                input_names=["audio"],
                output_names=["stems"],
                opset_version=17,
            )
            print("JIT script export successful!")
        except Exception as e2:
            print(f"JIT script export also failed: {e2}")
            print("\nThe HTDemucs model uses STFT which doesn't export to ONNX.")
            print("Falling back to saving as TorchScript instead...")
            
            # Save as TorchScript (can be loaded by libtorch)
            ts_path = output_path.replace('.onnx', '.pt')
            traced = torch.jit.trace(model, dummy_input)
            traced.save(ts_path)
            print(f"Saved TorchScript model to: {ts_path}")
            print("\nNote: The app will need to use libtorch instead of ONNX Runtime.")
            return
    
    print(f"\nDone! Model saved to: {output_path}")
    
    # Verify file size
    import os
    if os.path.exists(output_path):
        size_mb = os.path.getsize(output_path) / (1024 * 1024)
        print(f"Model size: {size_mb:.1f} MB")
    
    print("\nYou can now rebuild the Remix app:")
    print("  cd .. && ./build-macos-app.sh")

if __name__ == "__main__":
    convert_to_onnx()
