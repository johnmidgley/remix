//! Audio processing library
//! 
//! Provides audio loading and encoding utilities for the Remix app.

pub mod ffi;

use anyhow::{Context, Result, anyhow};
use hound::{SampleFormat, WavReader, WavSpec};
use std::io::{Cursor, Read, Seek};
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

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
