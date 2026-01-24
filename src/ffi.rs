//! C FFI bindings for the audio PCA library
//! 
//! These functions provide a C-compatible interface for use from Swift/Objective-C

use crate::{load_audio_from_bytes, encode_wav_to_bytes, mix_components, stft, istft, pca_decompose};
use libc::{c_char, c_double, c_uint, size_t};
use std::ptr;
use std::slice;

/// Opaque handle to a processing session
pub struct PcaSession {
    pub components: Vec<Vec<f64>>,
    pub eigenvalues: Vec<f64>,
    pub variance_ratios: Vec<f64>,
    pub sample_rate: u32,
}

/// Result structure returned to Swift
#[repr(C)]
pub struct PcaResultFFI {
    pub session: *mut PcaSession,
    pub num_components: c_uint,
    pub sample_rate: c_uint,
    pub error: *mut c_char,
}

/// Audio buffer structure for passing audio data
#[repr(C)]
pub struct AudioBufferFFI {
    pub data: *mut c_double,
    pub length: size_t,
    pub sample_rate: c_uint,
    pub error: *mut c_char,
}

/// Component info structure
#[repr(C)]
pub struct ComponentInfoFFI {
    pub eigenvalue: c_double,
    pub variance_ratio: c_double,
}

/// Process audio data and return a session handle
/// 
/// # Safety
/// - `data` must be a valid pointer to `data_len` bytes
/// - Caller must free the returned session with `pca_session_free`
#[no_mangle]
pub unsafe extern "C" fn pca_process_audio(
    data: *const u8,
    data_len: size_t,
    num_components: c_uint,
    window_size: c_uint,
    hop_size: c_uint,
) -> PcaResultFFI {
    if data.is_null() {
        return PcaResultFFI {
            session: ptr::null_mut(),
            num_components: 0,
            sample_rate: 0,
            error: string_to_c("Input data is null".to_string()),
        };
    }

    let audio_data = slice::from_raw_parts(data, data_len);
    
    // Load and decode audio
    let (samples, sample_rate) = match load_audio_from_bytes(audio_data) {
        Ok(result) => result,
        Err(e) => {
            return PcaResultFFI {
                session: ptr::null_mut(),
                num_components: 0,
                sample_rate: 0,
                error: string_to_c(format!("Failed to load audio: {}", e)),
            };
        }
    };

    // Compute STFT
    let spectrogram = stft(&samples, window_size as usize, hop_size as usize);
    
    // Apply PCA
    let (component_specs, eigenvalues, variance_ratios) = match pca_decompose(&spectrogram, num_components as usize) {
        Ok(result) => result,
        Err(e) => {
            return PcaResultFFI {
                session: ptr::null_mut(),
                num_components: 0,
                sample_rate: 0,
                error: string_to_c(format!("PCA failed: {}", e)),
            };
        }
    };

    // Reconstruct audio for each component
    let components: Vec<Vec<f64>> = component_specs
        .iter()
        .map(|spec| istft(spec, window_size as usize, hop_size as usize, samples.len()))
        .collect();

    let actual_components = components.len() as c_uint;

    let session = Box::new(PcaSession {
        components,
        eigenvalues,
        variance_ratios,
        sample_rate,
    });

    PcaResultFFI {
        session: Box::into_raw(session),
        num_components: actual_components,
        sample_rate,
        error: ptr::null_mut(),
    }
}

/// Get component info (eigenvalue and variance ratio)
/// 
/// # Safety
/// - `session` must be a valid session pointer from `pca_process_audio`
#[no_mangle]
pub unsafe extern "C" fn pca_get_component_info(
    session: *const PcaSession,
    component_index: c_uint,
) -> ComponentInfoFFI {
    if session.is_null() {
        return ComponentInfoFFI {
            eigenvalue: 0.0,
            variance_ratio: 0.0,
        };
    }

    let session = &*session;
    let idx = component_index as usize;

    if idx >= session.eigenvalues.len() {
        return ComponentInfoFFI {
            eigenvalue: 0.0,
            variance_ratio: 0.0,
        };
    }

    ComponentInfoFFI {
        eigenvalue: session.eigenvalues[idx],
        variance_ratio: session.variance_ratios[idx],
    }
}

/// Get audio samples for a specific component
/// 
/// # Safety
/// - `session` must be a valid session pointer
/// - Caller must free returned buffer with `pca_free_audio_buffer`
#[no_mangle]
pub unsafe extern "C" fn pca_get_component_audio(
    session: *const PcaSession,
    component_index: c_uint,
) -> AudioBufferFFI {
    if session.is_null() {
        return AudioBufferFFI {
            data: ptr::null_mut(),
            length: 0,
            sample_rate: 0,
            error: string_to_c("Session is null".to_string()),
        };
    }

    let session = &*session;
    let idx = component_index as usize;

    if idx >= session.components.len() {
        return AudioBufferFFI {
            data: ptr::null_mut(),
            length: 0,
            sample_rate: 0,
            error: string_to_c("Component index out of range".to_string()),
        };
    }

    let component = &session.components[idx];
    let mut buffer = component.clone().into_boxed_slice();
    let data = buffer.as_mut_ptr();
    let length = buffer.len();
    std::mem::forget(buffer);

    AudioBufferFFI {
        data,
        length,
        sample_rate: session.sample_rate,
        error: ptr::null_mut(),
    }
}

/// Mix components with given volumes and return audio buffer
/// 
/// # Safety
/// - `session` must be a valid session pointer
/// - `volumes` must be a valid pointer to `num_volumes` doubles
/// - Caller must free returned buffer with `pca_free_audio_buffer`
#[no_mangle]
pub unsafe extern "C" fn pca_mix_components(
    session: *const PcaSession,
    volumes: *const c_double,
    num_volumes: size_t,
) -> AudioBufferFFI {
    if session.is_null() || volumes.is_null() {
        return AudioBufferFFI {
            data: ptr::null_mut(),
            length: 0,
            sample_rate: 0,
            error: string_to_c("Invalid parameters".to_string()),
        };
    }

    let session = &*session;
    let volumes_slice = slice::from_raw_parts(volumes, num_volumes);

    let mixed = mix_components(&session.components, volumes_slice);
    
    let mut buffer = mixed.into_boxed_slice();
    let data = buffer.as_mut_ptr();
    let length = buffer.len();
    std::mem::forget(buffer);

    AudioBufferFFI {
        data,
        length,
        sample_rate: session.sample_rate,
        error: ptr::null_mut(),
    }
}

/// Encode audio samples as WAV data
/// 
/// # Safety
/// - `samples` must be a valid pointer to `num_samples` doubles
/// - Caller must free returned data with `pca_free_bytes`
#[no_mangle]
pub unsafe extern "C" fn pca_encode_wav(
    samples: *const c_double,
    num_samples: size_t,
    sample_rate: c_uint,
    out_len: *mut size_t,
) -> *mut u8 {
    if samples.is_null() || out_len.is_null() {
        return ptr::null_mut();
    }

    let samples_slice = slice::from_raw_parts(samples, num_samples);
    
    match encode_wav_to_bytes(samples_slice, sample_rate) {
        Ok(wav_data) => {
            *out_len = wav_data.len();
            let mut boxed = wav_data.into_boxed_slice();
            let ptr = boxed.as_mut_ptr();
            std::mem::forget(boxed);
            ptr
        }
        Err(_) => {
            *out_len = 0;
            ptr::null_mut()
        }
    }
}

/// Free a PCA session
/// 
/// # Safety
/// - `session` must be a valid session pointer or null
#[no_mangle]
pub unsafe extern "C" fn pca_session_free(session: *mut PcaSession) {
    if !session.is_null() {
        drop(Box::from_raw(session));
    }
}

/// Free an audio buffer
/// 
/// # Safety
/// - `buffer` data pointer must be from a previous FFI call or null
#[no_mangle]
pub unsafe extern "C" fn pca_free_audio_buffer(buffer: AudioBufferFFI) {
    if !buffer.data.is_null() {
        let _ = Vec::from_raw_parts(buffer.data, buffer.length, buffer.length);
    }
    if !buffer.error.is_null() {
        let _ = std::ffi::CString::from_raw(buffer.error);
    }
}

/// Free a byte array
/// 
/// # Safety
/// - `ptr` must be from a previous FFI call or null
#[no_mangle]
pub unsafe extern "C" fn pca_free_bytes(ptr: *mut u8, len: size_t) {
    if !ptr.is_null() {
        let _ = Vec::from_raw_parts(ptr, len, len);
    }
}

/// Free an error string
/// 
/// # Safety
/// - `ptr` must be from a previous FFI call or null
#[no_mangle]
pub unsafe extern "C" fn pca_free_error(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = std::ffi::CString::from_raw(ptr);
    }
}

/// Free a PcaResultFFI error string if present
/// 
/// # Safety
/// - Must only be called once per result
#[no_mangle]
pub unsafe extern "C" fn pca_result_free_error(result: *mut PcaResultFFI) {
    if !result.is_null() && !(*result).error.is_null() {
        let _ = std::ffi::CString::from_raw((*result).error);
        (*result).error = ptr::null_mut();
    }
}

/// Convert audio file (MP3, WAV, etc.) to WAV format
/// 
/// # Safety
/// - `data` must be a valid pointer to `data_len` bytes of audio file data
/// - Caller must free returned data with `pca_free_bytes`
/// - Caller must free returned error (if non-null) with `pca_free_error`
#[repr(C)]
pub struct ConvertResultFFI {
    pub data: *mut u8,
    pub length: size_t,
    pub sample_rate: c_uint,
    pub error: *mut c_char,
}

#[no_mangle]
pub unsafe extern "C" fn pca_convert_to_wav(
    data: *const u8,
    data_len: size_t,
) -> ConvertResultFFI {
    if data.is_null() || data_len == 0 {
        return ConvertResultFFI {
            data: ptr::null_mut(),
            length: 0,
            sample_rate: 0,
            error: string_to_c("Input data is null or empty".to_string()),
        };
    }

    let audio_data = slice::from_raw_parts(data, data_len);
    
    // Load and decode audio (handles MP3, WAV, etc.)
    let (samples, sample_rate) = match load_audio_from_bytes(audio_data) {
        Ok(result) => result,
        Err(e) => {
            return ConvertResultFFI {
                data: ptr::null_mut(),
                length: 0,
                sample_rate: 0,
                error: string_to_c(format!("Failed to load audio: {}", e)),
            };
        }
    };

    // Encode as WAV
    match encode_wav_to_bytes(&samples, sample_rate) {
        Ok(wav_data) => {
            let length = wav_data.len();
            let mut boxed = wav_data.into_boxed_slice();
            let ptr = boxed.as_mut_ptr();
            std::mem::forget(boxed);
            
            ConvertResultFFI {
                data: ptr,
                length,
                sample_rate,
                error: ptr::null_mut(),
            }
        }
        Err(e) => {
            ConvertResultFFI {
                data: ptr::null_mut(),
                length: 0,
                sample_rate: 0,
                error: string_to_c(format!("Failed to encode WAV: {}", e)),
            }
        }
    }
}

// Helper to convert Rust string to C string
fn string_to_c(s: String) -> *mut c_char {
    match std::ffi::CString::new(s) {
        Ok(cs) => cs.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}
