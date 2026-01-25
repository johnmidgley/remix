//! Demucs audio source separation using ONNX Runtime
//!
//! This module provides audio stem separation using the Demucs model
//! running on ONNX Runtime for cross-platform inference.

use anyhow::{Context, Result, anyhow};
use ndarray::{Array2, Array3, ArrayView2, s};
use ort::session::{Session, builder::GraphOptimizationLevel};
use ort::value::Value;
use rubato::{Resampler, SincFixedIn, SincInterpolationType, SincInterpolationParameters, WindowFunction};
use std::path::Path;
use hound::{WavSpec, WavWriter, SampleFormat};
use std::fs::File;
use std::io::BufWriter;

/// Demucs model sample rate
pub const DEMUCS_SAMPLE_RATE: u32 = 44100;

/// Stem names in Demucs htdemucs_6s model output order
pub const STEM_NAMES: [&str; 6] = ["drums", "bass", "vocals", "guitar", "piano", "other"];

/// Display names for stems
pub const STEM_DISPLAY_NAMES: [&str; 6] = ["Drums", "Bass", "Vocals", "Guitar", "Keys", "Other"];

/// Chunk size for processing (in samples) - about 10 seconds at 44.1kHz
const CHUNK_SIZE: usize = 441000;

/// Overlap between chunks (in samples) - about 1 second
const OVERLAP: usize = 44100;

/// Separation result containing paths to output stem files
#[derive(Debug, Clone)]
pub struct SeparationResult {
    pub model: String,
    pub input_path: String,
    pub stems: Vec<(String, String)>, // (stem_name, stem_path)
}

/// Demucs model wrapper
pub struct DemucsModel {
    session: Session,
    sample_rate: u32,
}

impl DemucsModel {
    /// Load a Demucs ONNX model from file
    pub fn load(model_path: &Path) -> Result<Self> {
        // Initialize ONNX Runtime
        let session = Session::builder()?
            .with_optimization_level(GraphOptimizationLevel::Level3)?
            .commit_from_file(model_path)
            .context("Failed to load ONNX model")?;
        
        Ok(Self {
            session,
            sample_rate: DEMUCS_SAMPLE_RATE,
        })
    }
    
    /// Get the expected sample rate for input audio
    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }
    
    /// Separate audio into stems
    /// 
    /// Input: stereo audio samples as [channels, samples] (2 x N)
    /// Output: separated stems as [stems, channels, samples] (6 x 2 x N)
    pub fn separate(&mut self, audio: ArrayView2<f32>) -> Result<Array3<f32>> {
        let (channels, total_samples) = (audio.shape()[0], audio.shape()[1]);
        
        if channels != 2 {
            return Err(anyhow!("Expected stereo audio (2 channels), got {}", channels));
        }
        
        if total_samples == 0 {
            return Err(anyhow!("Empty audio input"));
        }
        
        // For short audio, process in one go
        if total_samples <= CHUNK_SIZE {
            return self.process_chunk(audio);
        }
        
        // For longer audio, process in overlapping chunks
        let num_stems = STEM_NAMES.len();
        let mut output = Array3::<f32>::zeros((num_stems, channels, total_samples));
        let mut weights = Array2::<f32>::zeros((channels, total_samples));
        
        let step = CHUNK_SIZE - OVERLAP;
        let mut start = 0;
        
        while start < total_samples {
            let end = (start + CHUNK_SIZE).min(total_samples);
            let chunk = audio.slice(s![.., start..end]);
            
            // Pad if needed
            let chunk = if chunk.shape()[1] < CHUNK_SIZE {
                let mut padded = Array2::<f32>::zeros((2, CHUNK_SIZE));
                padded.slice_mut(s![.., ..chunk.shape()[1]]).assign(&chunk);
                padded
            } else {
                chunk.to_owned()
            };
            
            // Process chunk
            let chunk_output = self.process_chunk(chunk.view())?;
            
            // Calculate window weights for overlap-add
            let chunk_len = end - start;
            for i in 0..chunk_len {
                // Triangular window for smooth blending
                let weight = if i < OVERLAP && start > 0 {
                    i as f32 / OVERLAP as f32
                } else if i >= chunk_len - OVERLAP && end < total_samples {
                    (chunk_len - i) as f32 / OVERLAP as f32
                } else {
                    1.0
                };
                
                for stem_idx in 0..num_stems {
                    for ch in 0..channels {
                        output[[stem_idx, ch, start + i]] += chunk_output[[stem_idx, ch, i]] * weight;
                    }
                }
                
                for ch in 0..channels {
                    weights[[ch, start + i]] += weight;
                }
            }
            
            start += step;
        }
        
        // Normalize by weights
        for stem_idx in 0..num_stems {
            for ch in 0..channels {
                for i in 0..total_samples {
                    if weights[[ch, i]] > 0.0 {
                        output[[stem_idx, ch, i]] /= weights[[ch, i]];
                    }
                }
            }
        }
        
        Ok(output)
    }
    
    /// Process a single chunk through the model
    fn process_chunk(&mut self, audio: ArrayView2<f32>) -> Result<Array3<f32>> {
        let (channels, samples) = (audio.shape()[0], audio.shape()[1]);
        
        // Prepare input tensor: [batch, channels, samples] = [1, 2, N]
        let input_shape = [1usize, channels, samples];
        let input_data: Vec<f32> = audio.iter().cloned().collect();
        
        // Create tensor from shape and data
        let input_tensor = Value::from_array((input_shape, input_data))?;
        
        // Run inference - pass inputs as a slice
        let outputs = self.session.run(ort::inputs![input_tensor])?;
        
        // Get output tensor (first output) - outputs is an iterator of (name, value)
        let (_, output_value) = outputs.iter().next()
            .ok_or_else(|| anyhow!("No output tensor found"))?;
        
        let (output_shape, output_data) = output_value.try_extract_tensor::<f32>()?;
        
        // Expected shape: [batch, stems, channels, samples] = [1, 6, 2, N]
        let dims: Vec<usize> = output_shape.iter().map(|&d| d as usize).collect();
        if dims.len() != 4 {
            return Err(anyhow!("Unexpected output shape: {:?}", dims));
        }
        
        let num_stems = dims[1];
        let out_channels = dims[2];
        let out_samples = dims[3];
        
        let mut result = Array3::<f32>::zeros((num_stems, out_channels, out_samples));
        
        // Convert from flat array to 3D array
        // Input is [batch=1, stems, channels, samples] flattened
        for stem in 0..num_stems {
            for ch in 0..out_channels {
                for s in 0..out_samples {
                    let idx = stem * out_channels * out_samples + ch * out_samples + s;
                    result[[stem, ch, s]] = output_data[idx];
                }
            }
        }
        
        Ok(result)
    }
}

/// Resample audio to target sample rate
pub fn resample_audio(audio: ArrayView2<f32>, from_rate: u32, to_rate: u32) -> Result<Array2<f32>> {
    if from_rate == to_rate {
        return Ok(audio.to_owned());
    }
    
    let params = SincInterpolationParameters {
        sinc_len: 256,
        f_cutoff: 0.95,
        interpolation: SincInterpolationType::Linear,
        oversampling_factor: 256,
        window: WindowFunction::BlackmanHarris2,
    };
    
    let channels = audio.shape()[0];
    let input_samples = audio.shape()[1];
    
    let mut resampler = SincFixedIn::<f32>::new(
        to_rate as f64 / from_rate as f64,
        2.0,
        params,
        input_samples,
        channels,
    )?;
    
    // Convert to Vec<Vec<f32>> for rubato
    let input: Vec<Vec<f32>> = (0..channels)
        .map(|ch| audio.row(ch).to_vec())
        .collect();
    
    let output = resampler.process(&input, None)?;
    
    // Convert back to Array2
    let output_samples = output[0].len();
    let mut result = Array2::<f32>::zeros((channels, output_samples));
    
    for (ch, samples) in output.iter().enumerate() {
        for (i, &sample) in samples.iter().enumerate() {
            result[[ch, i]] = sample;
        }
    }
    
    Ok(result)
}

/// Convert mono to stereo by duplicating the channel
pub fn mono_to_stereo(audio: &[f32]) -> Array2<f32> {
    let samples = audio.len();
    let mut stereo = Array2::<f32>::zeros((2, samples));
    
    for (i, &sample) in audio.iter().enumerate() {
        stereo[[0, i]] = sample;
        stereo[[1, i]] = sample;
    }
    
    stereo
}

/// Convert interleaved stereo to Array2
pub fn interleaved_to_array(audio: &[f32], channels: usize) -> Array2<f32> {
    let samples = audio.len() / channels;
    let mut result = Array2::<f32>::zeros((channels, samples));
    
    for i in 0..samples {
        for ch in 0..channels {
            result[[ch, i]] = audio[i * channels + ch];
        }
    }
    
    result
}

/// Save audio array to WAV file
pub fn save_wav(path: &Path, audio: ArrayView2<f32>, sample_rate: u32) -> Result<()> {
    let channels = audio.shape()[0] as u16;
    let samples = audio.shape()[1];
    
    let spec = WavSpec {
        channels,
        sample_rate,
        bits_per_sample: 32,
        sample_format: SampleFormat::Float,
    };
    
    let file = File::create(path)?;
    let writer = BufWriter::new(file);
    let mut wav_writer = WavWriter::new(writer, spec)?;
    
    // Write interleaved samples
    for i in 0..samples {
        for ch in 0..channels as usize {
            wav_writer.write_sample(audio[[ch, i]])?;
        }
    }
    
    wav_writer.finalize()?;
    Ok(())
}

/// High-level function to separate an audio file into stems
pub fn separate_file(
    model: &mut DemucsModel,
    input_path: &Path,
    output_dir: &Path,
) -> Result<SeparationResult> {
    use crate::load_audio_from_bytes;
    
    // Read input file
    let input_data = std::fs::read(input_path)
        .context("Failed to read input file")?;
    
    // Decode audio
    let (samples, sample_rate) = load_audio_from_bytes(&input_data)
        .context("Failed to decode audio")?;
    
    // Convert to stereo if needed (our load function returns mono)
    // We need to reload as stereo for proper separation
    let audio = mono_to_stereo(&samples.iter().map(|&x| x as f32).collect::<Vec<_>>());
    
    // Resample if needed
    let audio = if sample_rate != DEMUCS_SAMPLE_RATE {
        eprintln!("Resampling from {} to {} Hz...", sample_rate, DEMUCS_SAMPLE_RATE);
        resample_audio(audio.view(), sample_rate, DEMUCS_SAMPLE_RATE)?
    } else {
        audio
    };
    
    // Run separation
    eprintln!("Running Demucs separation...");
    let stems = model.separate(audio.view())?;
    
    // Create output directory
    let stem_dir = output_dir.join("htdemucs_6s").join(
        input_path.file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "output".to_string())
    );
    std::fs::create_dir_all(&stem_dir)?;
    
    // Save stems
    let mut result_stems = Vec::new();
    
    for (i, stem_name) in STEM_NAMES.iter().enumerate() {
        let stem_audio = stems.slice(s![i, .., ..]);
        let stem_path = stem_dir.join(format!("{}.wav", stem_name));
        
        eprintln!("Saving {}...", stem_name);
        save_wav(&stem_path, stem_audio, DEMUCS_SAMPLE_RATE)?;
        
        result_stems.push((
            stem_name.to_string(),
            stem_path.to_string_lossy().to_string(),
        ));
    }
    
    Ok(SeparationResult {
        model: "htdemucs_6s".to_string(),
        input_path: input_path.to_string_lossy().to_string(),
        stems: result_stems,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_mono_to_stereo() {
        let mono = vec![1.0f32, 2.0, 3.0];
        let stereo = mono_to_stereo(&mono);
        
        assert_eq!(stereo.shape(), &[2, 3]);
        assert_eq!(stereo[[0, 0]], 1.0);
        assert_eq!(stereo[[1, 0]], 1.0);
        assert_eq!(stereo[[0, 2]], 3.0);
        assert_eq!(stereo[[1, 2]], 3.0);
    }
    
    #[test]
    fn test_interleaved_to_array() {
        let interleaved = vec![1.0f32, 2.0, 3.0, 4.0, 5.0, 6.0]; // L R L R L R
        let array = interleaved_to_array(&interleaved, 2);
        
        assert_eq!(array.shape(), &[2, 3]);
        assert_eq!(array[[0, 0]], 1.0); // L
        assert_eq!(array[[1, 0]], 2.0); // R
        assert_eq!(array[[0, 1]], 3.0); // L
        assert_eq!(array[[1, 1]], 4.0); // R
    }
}
