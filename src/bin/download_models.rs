//! Download Demucs ONNX models for bundling with the app
//!
//! Downloads pre-converted ONNX models from a hosted location.
//! Replaces the Python download_models.py script.

use indicatif::{ProgressBar, ProgressStyle};
use sha2::{Sha256, Digest};
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::PathBuf;

/// Model information
struct ModelInfo {
    name: &'static str,
    url: &'static str,
    sha256: &'static str,
    size_mb: u64,
}

/// Available Demucs ONNX models
/// The htdemucs models need to be converted from PyTorch to ONNX format
const MODELS: &[ModelInfo] = &[
    ModelInfo {
        name: "htdemucs_6s",
        // UVR (Ultimate Vocal Remover) provides ONNX models for various separators
        // This is the 6-stem Demucs model converted to ONNX
        url: "https://github.com/facefusion/facefusion-assets/releases/download/models-3.0.0/demucs_htdemucs_6s.onnx",
        sha256: "", // Empty means skip verification (model may vary)
        size_mb: 85,
    },
];

fn download_with_progress(url: &str, dest: &PathBuf) -> Result<(), Box<dyn std::error::Error>> {
    println!("Downloading from: {}", url);
    
    let response = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(3600)) // 1 hour timeout for large files
        .build()?
        .get(url)
        .send()?;
    
    if !response.status().is_success() {
        return Err(format!("HTTP error: {}", response.status()).into());
    }
    
    let total_size = response.content_length().unwrap_or(0);
    
    let pb = ProgressBar::new(total_size);
    pb.set_style(ProgressStyle::default_bar()
        .template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {bytes}/{total_bytes} ({eta})")?
        .progress_chars("#>-"));
    
    let mut file = File::create(dest)?;
    let mut downloaded: u64 = 0;
    
    let mut reader = response;
    let mut buffer = [0u8; 8192];
    
    loop {
        let bytes_read = reader.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        file.write_all(&buffer[..bytes_read])?;
        downloaded += bytes_read as u64;
        pb.set_position(downloaded);
    }
    
    pb.finish_with_message("Download complete");
    Ok(())
}

fn verify_checksum(path: &PathBuf, expected: &str) -> Result<bool, Box<dyn std::error::Error>> {
    if expected.is_empty() {
        println!("  Skipping checksum verification (no hash provided)");
        return Ok(true);
    }
    
    println!("  Verifying checksum...");
    
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 65536];
    
    loop {
        let bytes_read = file.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }
    
    let result = hasher.finalize();
    let actual = format!("{:x}", result);
    
    if actual == expected {
        println!("  Checksum OK");
        Ok(true)
    } else {
        println!("  Checksum mismatch!");
        println!("    Expected: {}", expected);
        println!("    Actual:   {}", actual);
        Ok(false)
    }
}

fn download_model(model: &ModelInfo, output_dir: &PathBuf) -> Result<PathBuf, Box<dyn std::error::Error>> {
    let model_path = output_dir.join(format!("{}.onnx", model.name));
    
    // Check if already exists and valid
    if model_path.exists() {
        println!("Model {} already exists at {}", model.name, model_path.display());
        if verify_checksum(&model_path, model.sha256)? {
            return Ok(model_path);
        }
        println!("Checksum failed, re-downloading...");
        fs::remove_file(&model_path)?;
    }
    
    println!("\nDownloading model: {} (~{}MB)", model.name, model.size_mb);
    
    // Try to download from URL
    match download_with_progress(model.url, &model_path) {
        Ok(_) => {
            // Verify checksum
            if !verify_checksum(&model_path, model.sha256)? {
                fs::remove_file(&model_path)?;
                return Err("Checksum verification failed".into());
            }
            Ok(model_path)
        }
        Err(e) => {
            // Clean up partial download
            if model_path.exists() {
                fs::remove_file(&model_path).ok();
            }
            Err(e)
        }
    }
}

fn print_usage() {
    eprintln!("Usage: download_models [OPTIONS]");
    eprintln!();
    eprintln!("Options:");
    eprintln!("  -o, --output DIR    Output directory for models (default: ./models)");
    eprintln!("  -m, --model NAME    Model to download (default: htdemucs_6s)");
    eprintln!("  -h, --help          Show this help");
    eprintln!();
    eprintln!("Available models:");
    for model in MODELS {
        eprintln!("  {} (~{}MB)", model.name, model.size_mb);
    }
}

/// Create a conversion script for manual model conversion
fn create_conversion_script(output_dir: &PathBuf) -> std::io::Result<PathBuf> {
    let script_path = output_dir.join("convert_demucs.py");
    let script_content = r#"#!/usr/bin/env python3
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
    print("You can now delete this script and use the ONNX model with the Rust app.")

if __name__ == "__main__":
    convert_to_onnx()
"#;
    
    fs::write(&script_path, script_content)?;
    Ok(script_path)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    
    let mut output_dir = PathBuf::from("models");
    let mut model_name = "htdemucs_6s";
    
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-o" | "--output" => {
                i += 1;
                if i < args.len() {
                    output_dir = PathBuf::from(&args[i]);
                }
            }
            "-m" | "--model" => {
                i += 1;
                if i < args.len() {
                    model_name = &args[i];
                }
            }
            "-h" | "--help" => {
                print_usage();
                return;
            }
            _ => {
                eprintln!("Unknown argument: {}", args[i]);
                print_usage();
                std::process::exit(1);
            }
        }
        i += 1;
    }
    
    // Find the requested model
    let model = MODELS.iter().find(|m| m.name == model_name);
    let model = match model {
        Some(m) => m,
        None => {
            eprintln!("Unknown model: {}", model_name);
            eprintln!("Available models:");
            for m in MODELS {
                eprintln!("  {}", m.name);
            }
            std::process::exit(1);
        }
    };
    
    // Create output directory
    fs::create_dir_all(&output_dir).expect("Failed to create output directory");
    
    println!("===========================================");
    println!("Demucs ONNX Model Downloader");
    println!("===========================================");
    println!("Output directory: {}", output_dir.display());
    
    match download_model(model, &output_dir) {
        Ok(path) => {
            println!("\n===========================================");
            println!("Download complete!");
            println!("Model saved to: {}", path.display());
            
            // Print file size
            if let Ok(metadata) = fs::metadata(&path) {
                let size_mb = metadata.len() as f64 / 1024.0 / 1024.0;
                println!("Size: {:.1} MB", size_mb);
            }
            println!("===========================================");
        }
        Err(e) => {
            eprintln!("\nDownload failed: {}", e);
            eprintln!("\nThe pre-built ONNX model is not available from the configured URL.");
            eprintln!("You can convert the model yourself using Python (one-time only):\n");
            
            // Create conversion script
            match create_conversion_script(&output_dir) {
                Ok(script_path) => {
                    eprintln!("A conversion script has been created at:");
                    eprintln!("  {}", script_path.display());
                    eprintln!("\nTo convert the model:");
                    eprintln!("  1. pip install demucs torch onnx");
                    eprintln!("  2. cd {}", output_dir.display());
                    eprintln!("  3. python convert_demucs.py");
                    eprintln!("\nAfter conversion, the ONNX model will be ready to use.");
                }
                Err(script_err) => {
                    eprintln!("Could not create conversion script: {}", script_err);
                }
            }
            
            // Don't exit with error - the app can still be built, just without the model
            eprintln!("\nContinuing build without bundled model...");
        }
    }
}
