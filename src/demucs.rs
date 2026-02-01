//! Demucs audio source separation using Python subprocess
//!
//! This module provides audio stem separation by calling the Python demucs package.
//! Requires: pip install demucs

use anyhow::{Context, Result, anyhow};
use std::path::Path;
use std::process::Command;
use std::fs;

/// Demucs model sample rate
pub const DEMUCS_SAMPLE_RATE: u32 = 44100;

/// Stem names in Demucs htdemucs_6s model output order
pub const STEM_NAMES: [&str; 6] = ["drums", "bass", "other", "vocals", "guitar", "piano"];

/// Display names for stems
pub const STEM_DISPLAY_NAMES: [&str; 6] = ["Drums", "Bass", "Other", "Vocals", "Guitar", "Keys"];

/// Separation result containing paths to output stem files
#[derive(Debug, Clone)]
pub struct SeparationResult {
    pub model: String,
    pub input_path: String,
    pub stems: Vec<(String, String)>, // (stem_name, stem_path)
}

/// Find Python executable (bundled or system)
fn find_python() -> Result<String> {
    // First, try to find bundled Python in app bundle
    if let Ok(exe_path) = std::env::current_exe() {
        // Get app bundle path (macOS: /path/to/Remix.app/Contents/MacOS/Remix)
        if let Some(macos_dir) = exe_path.parent() {
            if let Some(contents_dir) = macos_dir.parent() {
                let bundled_python = contents_dir
                    .join("Resources")
                    .join("python")
                    .join("bin")
                    .join("python-wrapper.sh");
                
                if bundled_python.exists() {
                    eprintln!("✓ Using bundled Python: {}", bundled_python.display());
                    return Ok(bundled_python.to_string_lossy().to_string());
                }
            }
        }
    }
    
    // Fall back to system Python
    eprintln!("Bundled Python not found, trying system Python...");
    let candidates = ["python3", "python", "/usr/bin/python3", "/usr/local/bin/python3"];
    
    for candidate in candidates {
        if let Ok(output) = Command::new(candidate)
            .arg("--version")
            .output()
        {
            if output.status.success() {
                eprintln!("✓ Using system Python: {}", candidate);
                return Ok(candidate.to_string());
            }
        }
    }
    
    Err(anyhow!(
        "Python not found.\n\n\
        The app should include a bundled Python distribution.\n\
        If you're running from source, please install Python 3:\n\
          brew install python3\n\
          pip3 install demucs"
    ))
}

/// Check if demucs is installed
fn check_demucs_installed(python: &str) -> Result<()> {
    let output = Command::new(python)
        .args(["-c", "import demucs; print(demucs.__version__)"])
        .output()
        .context("Failed to run Python")?;
    
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(anyhow!(
            "Demucs is not installed. Please run: pip install demucs\n\nError: {}",
            stderr
        ));
    }
    
    Ok(())
}

/// Demucs model wrapper - now just tracks if demucs is available
pub struct DemucsModel {
    python_path: String,
    model_name: String,
}

impl DemucsModel {
    /// Load/verify Demucs is available via bundled Python
    pub fn load(_model_path: &Path) -> Result<Self> {
        // Find Python
        let python = find_python()?;
        
        // Check demucs is installed
        check_demucs_installed(&python)?;
        
        Ok(Self {
            python_path: python,
            model_name: "htdemucs_6s".to_string(),
        })
    }
    
    /// Create a new DemucsModel with default settings
    pub fn new() -> Result<Self> {
        let python = find_python()?;
        check_demucs_installed(&python)?;
        
        Ok(Self {
            python_path: python,
            model_name: "htdemucs_6s".to_string(),
        })
    }
    
    /// Get the expected sample rate for input audio
    pub fn sample_rate(&self) -> u32 {
        DEMUCS_SAMPLE_RATE
    }
    
    /// Get the model name
    pub fn model_name(&self) -> &str {
        &self.model_name
    }
}

/// High-level function to separate an audio file into stems using Python demucs
pub fn separate_file(
    model: &mut DemucsModel,
    input_path: &Path,
    output_dir: &Path,
) -> Result<SeparationResult> {
    eprintln!("Running Demucs separation via Python...");
    eprintln!("  Python: {}", model.python_path);
    eprintln!("  Model: {}", model.model_name);
    eprintln!("  Input: {}", input_path.display());
    eprintln!("  Output: {}", output_dir.display());
    
    // Create output directory
    fs::create_dir_all(output_dir)?;
    
    // Run demucs via Python
    // Command: python -m demucs --two-stems=vocals -n htdemucs_6s -o output_dir input_file
    // For 6-stem: python -m demucs -n htdemucs_6s -o output_dir input_file
    let output = Command::new(&model.python_path)
        .args([
            "-m", "demucs",
            "-n", &model.model_name,
            "-o", output_dir.to_str().unwrap_or("."),
            input_path.to_str().unwrap_or(""),
        ])
        .output()
        .context("Failed to run demucs")?;
    
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        return Err(anyhow!(
            "Demucs separation failed:\n{}\n{}",
            stdout,
            stderr
        ));
    }
    
    // Demucs outputs to: output_dir/model_name/track_name/stem.wav
    let track_name = input_path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "track".to_string());
    
    let stems_dir = output_dir.join(&model.model_name).join(&track_name);
    
    eprintln!("Looking for stems in: {}", stems_dir.display());
    
    // Collect stem paths
    let mut stems = Vec::new();
    
    for stem_name in STEM_NAMES.iter() {
        let stem_path = stems_dir.join(format!("{}.wav", stem_name));
        
        if stem_path.exists() {
            eprintln!("  Found: {}", stem_name);
            stems.push((
                stem_name.to_string(),
                stem_path.to_string_lossy().to_string(),
            ));
        } else {
            eprintln!("  Missing: {} (expected at {})", stem_name, stem_path.display());
        }
    }
    
    if stems.is_empty() {
        // Try to list what's actually in the directory
        if let Ok(entries) = fs::read_dir(&stems_dir) {
            eprintln!("Files found in stems directory:");
            for entry in entries {
                if let Ok(entry) = entry {
                    eprintln!("  {}", entry.path().display());
                }
            }
        }
        return Err(anyhow!("No stem files were produced by Demucs"));
    }
    
    Ok(SeparationResult {
        model: model.model_name.clone(),
        input_path: input_path.to_string_lossy().to_string(),
        stems,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_find_python() {
        // This test will only pass if Python is installed
        let result = find_python();
        println!("Python found: {:?}", result);
    }
}
