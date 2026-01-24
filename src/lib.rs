//! Audio PCA decomposition library
//! 
//! Splits audio into principal component audio files by performing
//! PCA/SVD on the spectrogram.

pub mod ffi;

use anyhow::{Context, Result, anyhow};
use hound::{SampleFormat, WavReader, WavSpec};
use ndarray::{Array2, Axis};
use ndarray_linalg::SVD;
use num_complex::Complex;
use rustfft::{FftPlanner, num_complex::Complex as FftComplex};
use std::f64::consts::PI;
use std::io::{Cursor, Read, Seek};
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

/// Result of PCA decomposition
#[derive(Debug)]
pub struct PcaResult {
    /// Audio samples for each component
    pub components: Vec<Vec<f64>>,
    /// Eigenvalue for each component
    pub eigenvalues: Vec<f64>,
    /// Variance ratio (percentage) for each component
    pub variance_ratios: Vec<f64>,
    /// Sample rate of the audio
    pub sample_rate: u32,
}

/// Load audio samples from a WAV file reader
pub fn load_wav_from_reader<R: Read + Seek>(reader: R) -> Result<(Vec<f64>, WavSpec)> {
    let reader = WavReader::new(reader)
        .context("Failed to parse WAV data")?;
    
    let spec = reader.spec();
    
    let samples: Vec<f64> = match spec.sample_format {
        SampleFormat::Float => {
            reader.into_samples::<f32>()
                .map(|s| s.map(|v| v as f64))
                .collect::<Result<Vec<_>, _>>()?
        }
        SampleFormat::Int => {
            let bits = spec.bits_per_sample;
            let max_val = (1u32 << (bits - 1)) as f64;
            reader.into_samples::<i32>()
                .map(|s| s.map(|v| v as f64 / max_val))
                .collect::<Result<Vec<_>, _>>()?
        }
    };
    
    // Convert to mono if stereo
    let mono_samples = if spec.channels == 2 {
        samples.chunks(2)
            .map(|chunk| (chunk[0] + chunk.get(1).unwrap_or(&0.0)) / 2.0)
            .collect()
    } else {
        samples
    };
    
    Ok((mono_samples, spec))
}

/// Load audio samples from bytes (WAV format)
pub fn load_wav_from_bytes(data: &[u8]) -> Result<(Vec<f64>, WavSpec)> {
    load_wav_from_reader(Cursor::new(data))
}

/// Audio format detection
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum AudioFormat {
    Wav,
    Mp3,
    Unknown,
}

/// Detect audio format from file header bytes
pub fn detect_format(data: &[u8]) -> AudioFormat {
    if data.len() < 12 {
        return AudioFormat::Unknown;
    }
    
    // WAV: starts with "RIFF" and contains "WAVE"
    if &data[0..4] == b"RIFF" && &data[8..12] == b"WAVE" {
        return AudioFormat::Wav;
    }
    
    // MP3: starts with ID3 tag or frame sync
    if &data[0..3] == b"ID3" {
        return AudioFormat::Mp3;
    }
    
    // MP3 frame sync: 0xFF followed by 0xE* or 0xF*
    if data[0] == 0xFF && (data[1] & 0xE0) == 0xE0 {
        return AudioFormat::Mp3;
    }
    
    AudioFormat::Unknown
}

/// Decoded audio result
pub struct DecodedAudio {
    pub samples: Vec<f64>,
    pub sample_rate: u32,
    pub channels: u16,
}

/// Load audio using symphonia (supports MP3, WAV, and other formats)
pub fn load_audio_symphonia(data: &[u8]) -> Result<DecodedAudio> {
    let cursor = Cursor::new(data.to_vec());
    let mss = MediaSourceStream::new(Box::new(cursor), Default::default());
    
    let hint = Hint::new();
    let format_opts = FormatOptions::default();
    let metadata_opts = MetadataOptions::default();
    
    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &format_opts, &metadata_opts)
        .context("Failed to probe audio format")?;
    
    let mut format = probed.format;
    
    let track = format.tracks()
        .iter()
        .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
        .ok_or_else(|| anyhow!("No supported audio track found"))?;
    
    let sample_rate = track.codec_params.sample_rate
        .ok_or_else(|| anyhow!("Unknown sample rate"))?;
    let channels = track.codec_params.channels
        .map(|c| c.count() as u16)
        .unwrap_or(2);
    
    let decoder_opts = DecoderOptions::default();
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &decoder_opts)
        .context("Failed to create audio decoder")?;
    
    let track_id = track.id;
    let mut samples: Vec<f64> = Vec::new();
    
    loop {
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(symphonia::core::errors::Error::IoError(e)) 
                if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(e) => return Err(e.into()),
        };
        
        if packet.track_id() != track_id {
            continue;
        }
        
        let decoded = match decoder.decode(&packet) {
            Ok(d) => d,
            Err(symphonia::core::errors::Error::DecodeError(_)) => continue,
            Err(e) => return Err(e.into()),
        };
        
        let spec = *decoded.spec();
        let duration = decoded.capacity() as u64;
        
        let mut sample_buf = SampleBuffer::<f32>::new(duration, spec);
        sample_buf.copy_interleaved_ref(decoded);
        
        for &s in sample_buf.samples() {
            samples.push(s as f64);
        }
    }
    
    // Convert to mono if stereo
    let mono_samples = if channels == 2 {
        samples.chunks(2)
            .map(|chunk| (chunk[0] + chunk.get(1).unwrap_or(&0.0)) / 2.0)
            .collect()
    } else if channels > 2 {
        // Mix down all channels
        samples.chunks(channels as usize)
            .map(|chunk| chunk.iter().sum::<f64>() / channels as f64)
            .collect()
    } else {
        samples
    };
    
    Ok(DecodedAudio {
        samples: mono_samples,
        sample_rate,
        channels,
    })
}

/// Load audio from bytes, auto-detecting format
pub fn load_audio_from_bytes(data: &[u8]) -> Result<(Vec<f64>, u32)> {
    let format = detect_format(data);
    
    match format {
        AudioFormat::Wav => {
            // Try symphonia first for better compatibility, fall back to hound
            match load_audio_symphonia(data) {
                Ok(decoded) => Ok((decoded.samples, decoded.sample_rate)),
                Err(_) => {
                    let (samples, spec) = load_wav_from_bytes(data)?;
                    Ok((samples, spec.sample_rate))
                }
            }
        }
        AudioFormat::Mp3 => {
            let decoded = load_audio_symphonia(data)?;
            Ok((decoded.samples, decoded.sample_rate))
        }
        AudioFormat::Unknown => {
            // Try symphonia anyway, it might be able to detect the format
            match load_audio_symphonia(data) {
                Ok(decoded) => Ok((decoded.samples, decoded.sample_rate)),
                Err(_) => Err(anyhow!("Unknown or unsupported audio format"))
            }
        }
    }
}

/// Encode audio samples as WAV bytes
pub fn encode_wav_to_bytes(samples: &[f64], sample_rate: u32) -> Result<Vec<u8>> {
    let spec = WavSpec {
        channels: 1,
        sample_rate,
        bits_per_sample: 32,
        sample_format: SampleFormat::Float,
    };
    
    let mut buffer = Cursor::new(Vec::new());
    {
        let mut writer = hound::WavWriter::new(&mut buffer, spec)?;
        for &sample in samples {
            writer.write_sample(sample as f32)?;
        }
        writer.finalize()?;
    }
    
    Ok(buffer.into_inner())
}

/// Create a Hann window
fn hann_window(size: usize) -> Vec<f64> {
    (0..size)
        .map(|i| 0.5 * (1.0 - (2.0 * PI * i as f64 / size as f64).cos()))
        .collect()
}

/// Compute Short-Time Fourier Transform
pub fn stft(samples: &[f64], window_size: usize, hop_size: usize) -> Array2<Complex<f64>> {
    let window = hann_window(window_size);
    let num_frames = (samples.len().saturating_sub(window_size)) / hop_size + 1;
    let num_bins = window_size / 2 + 1;
    
    let mut planner = FftPlanner::new();
    let fft = planner.plan_fft_forward(window_size);
    
    let mut spectrogram = Array2::zeros((num_bins, num_frames));
    
    for (frame_idx, start) in (0..samples.len().saturating_sub(window_size - 1))
        .step_by(hop_size)
        .enumerate()
    {
        if frame_idx >= num_frames {
            break;
        }
        
        let mut buffer: Vec<FftComplex<f64>> = samples[start..start + window_size]
            .iter()
            .zip(window.iter())
            .map(|(&s, &w)| FftComplex::new(s * w, 0.0))
            .collect();
        
        fft.process(&mut buffer);
        
        for (bin_idx, &val) in buffer.iter().take(num_bins).enumerate() {
            spectrogram[[bin_idx, frame_idx]] = Complex::new(val.re, val.im);
        }
    }
    
    spectrogram
}

/// Compute Inverse Short-Time Fourier Transform
pub fn istft(spectrogram: &Array2<Complex<f64>>, window_size: usize, hop_size: usize, output_length: usize) -> Vec<f64> {
    let window = hann_window(window_size);
    let num_frames = spectrogram.ncols();
    
    let mut planner = FftPlanner::new();
    let ifft = planner.plan_fft_inverse(window_size);
    
    let mut output = vec![0.0; output_length];
    let mut window_sum = vec![0.0; output_length];
    
    for frame_idx in 0..num_frames {
        let start = frame_idx * hop_size;
        if start + window_size > output_length {
            break;
        }
        
        let mut buffer: Vec<FftComplex<f64>> = Vec::with_capacity(window_size);
        
        for bin_idx in 0..spectrogram.nrows() {
            let val = spectrogram[[bin_idx, frame_idx]];
            buffer.push(FftComplex::new(val.re, val.im));
        }
        
        for bin_idx in (1..window_size / 2).rev() {
            let val = spectrogram[[bin_idx, frame_idx]];
            buffer.push(FftComplex::new(val.re, -val.im));
        }
        
        ifft.process(&mut buffer);
        
        for (i, (&val, &w)) in buffer.iter().zip(window.iter()).enumerate() {
            if start + i < output_length {
                output[start + i] += val.re * w / window_size as f64;
                window_sum[start + i] += w * w;
            }
        }
    }
    
    for (sample, &ws) in output.iter_mut().zip(window_sum.iter()) {
        if ws > 1e-8 {
            *sample /= ws;
        }
    }
    
    output
}

/// Apply PCA to spectrogram and return component spectrograms with metadata
pub fn pca_decompose(
    spectrogram: &Array2<Complex<f64>>, 
    n_components: usize
) -> Result<(Vec<Array2<Complex<f64>>>, Vec<f64>, Vec<f64>)> {
    let (num_bins, num_frames) = spectrogram.dim();
    
    let magnitude: Array2<f64> = spectrogram.mapv(|c| c.norm());
    let phase: Array2<f64> = spectrogram.mapv(|c| c.arg());
    
    let mean = magnitude.mean_axis(Axis(1)).unwrap();
    let mut centered = magnitude.clone();
    for mut col in centered.columns_mut() {
        col -= &mean;
    }
    
    let (u, s, vt) = centered.svd(true, true)
        .context("SVD computation failed")?;
    
    let u = u.unwrap();
    let vt = vt.unwrap();
    
    let n_components = n_components.min(s.len());
    let total_variance: f64 = s.iter().map(|&x| x * x).sum();
    
    let mut components = Vec::with_capacity(n_components);
    let mut eigenvalues = Vec::with_capacity(n_components);
    let mut variance_ratios = Vec::with_capacity(n_components);
    
    for i in 0..n_components {
        let eigenvalue = s[i] * s[i];
        let variance_ratio = eigenvalue / total_variance * 100.0;
        
        eigenvalues.push(eigenvalue);
        variance_ratios.push(variance_ratio);
        
        let u_col = u.column(i);
        let v_row = vt.row(i);
        
        let mut component_magnitude = Array2::zeros((num_bins, num_frames));
        for (bin_idx, &u_val) in u_col.iter().enumerate() {
            for (frame_idx, &v_val) in v_row.iter().enumerate() {
                component_magnitude[[bin_idx, frame_idx]] = u_val * s[i] * v_val;
            }
        }
        
        let scale = eigenvalue / total_variance;
        for mut col in component_magnitude.columns_mut() {
            col += &(&mean * scale);
        }
        
        component_magnitude.mapv_inplace(|x| x.abs());
        
        let component_spectrogram: Array2<Complex<f64>> = Array2::from_shape_fn(
            (num_bins, num_frames),
            |(i, j)| {
                let mag = component_magnitude[[i, j]];
                let ph = phase[[i, j]];
                Complex::new(mag * ph.cos(), mag * ph.sin())
            }
        );
        
        components.push(component_spectrogram);
    }
    
    Ok((components, eigenvalues, variance_ratios))
}

/// Process audio and return PCA components
/// Supports WAV and MP3 formats (auto-detected)
pub fn process_audio(
    audio_data: &[u8],
    n_components: usize,
    window_size: usize,
    hop_size: usize,
) -> Result<PcaResult> {
    let (samples, sample_rate) = load_audio_from_bytes(audio_data)?;
    
    let spectrogram = stft(&samples, window_size, hop_size);
    let (component_specs, eigenvalues, variance_ratios) = pca_decompose(&spectrogram, n_components)?;
    
    let components: Vec<Vec<f64>> = component_specs
        .iter()
        .map(|spec| istft(spec, window_size, hop_size, samples.len()))
        .collect();
    
    Ok(PcaResult {
        components,
        eigenvalues,
        variance_ratios,
        sample_rate,
    })
}

/// Mix multiple audio components with given volume levels
pub fn mix_components(components: &[Vec<f64>], volumes: &[f64]) -> Vec<f64> {
    if components.is_empty() {
        return Vec::new();
    }
    
    let len = components[0].len();
    let mut mixed = vec![0.0; len];
    
    for (component, &volume) in components.iter().zip(volumes.iter()) {
        for (i, &sample) in component.iter().enumerate() {
            if i < len {
                mixed[i] += sample * volume;
            }
        }
    }
    
    // Normalize to prevent clipping
    let max_val = mixed.iter().map(|&x| x.abs()).fold(0.0f64, f64::max);
    if max_val > 1.0 {
        for sample in &mut mixed {
            *sample /= max_val;
        }
    }
    
    mixed
}
