//! C FFI bindings for the audio processing library
//! 
//! These functions provide a C-compatible interface for use from Swift/Objective-C

use crate::{load_audio_from_bytes, encode_wav_to_bytes};
use libc::{c_char, c_uint, size_t};
use std::ptr;
use std::slice;

/// Convert audio file (MP3, WAV, etc.) to WAV format
/// 
/// # Safety
/// - `data` must be a valid pointer to `data_len` bytes of audio file data
/// - Caller must free returned data with `audio_free_bytes`
/// - Caller must free returned error (if non-null) with `audio_free_error`
#[repr(C)]
pub struct ConvertResultFFI {
    pub data: *mut u8,
    pub length: size_t,
    pub sample_rate: c_uint,
    pub error: *mut c_char,
}

#[no_mangle]
pub unsafe extern "C" fn audio_convert_to_wav(
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

/// Free a byte array
/// 
/// # Safety
/// - `ptr` must be from a previous FFI call or null
#[no_mangle]
pub unsafe extern "C" fn audio_free_bytes(ptr: *mut u8, len: size_t) {
    if !ptr.is_null() {
        let _ = Vec::from_raw_parts(ptr, len, len);
    }
}

/// Free an error string
/// 
/// # Safety
/// - `ptr` must be from a previous FFI call or null
#[no_mangle]
pub unsafe extern "C" fn audio_free_error(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = std::ffi::CString::from_raw(ptr);
    }
}

// Legacy aliases for backward compatibility
#[no_mangle]
pub unsafe extern "C" fn pca_convert_to_wav(
    data: *const u8,
    data_len: size_t,
) -> ConvertResultFFI {
    audio_convert_to_wav(data, data_len)
}

#[no_mangle]
pub unsafe extern "C" fn pca_free_bytes(ptr: *mut u8, len: size_t) {
    audio_free_bytes(ptr, len)
}

#[no_mangle]
pub unsafe extern "C" fn pca_free_error(ptr: *mut c_char) {
    audio_free_error(ptr)
}

// Helper to convert Rust string to C string
fn string_to_c(s: String) -> *mut c_char {
    match std::ffi::CString::new(s) {
        Ok(cs) => cs.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}
