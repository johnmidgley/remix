//! C FFI bindings for the audio processing library
//! 
//! These functions provide a C-compatible interface for use from Swift/Objective-C

use crate::{load_audio_from_bytes, encode_wav_to_bytes};
use crate::demucs::{DemucsModel, separate_file, STEM_NAMES};
use libc::{c_char, c_uint, size_t};
use std::ffi::CStr;
use std::path::Path;
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

// ============================================================================
// Demucs FFI
// ============================================================================

/// Opaque handle to a loaded Demucs model
pub struct DemucsModelHandle {
    model: DemucsModel,
}

/// Result of stem separation
#[repr(C)]
pub struct SeparationResultFFI {
    /// Number of stems (usually 6)
    pub stem_count: c_uint,
    /// Array of stem names (null-terminated C strings)
    pub stem_names: *mut *mut c_char,
    /// Array of stem file paths (null-terminated C strings)
    pub stem_paths: *mut *mut c_char,
    /// Error message if failed (null if success)
    pub error: *mut c_char,
}

/// Load a Demucs ONNX model from file
/// 
/// # Safety
/// - `model_path` must be a valid null-terminated C string
/// - Returns null on failure, check with demucs_get_last_error()
#[no_mangle]
pub unsafe extern "C" fn demucs_load_model(model_path: *const c_char) -> *mut DemucsModelHandle {
    if model_path.is_null() {
        return ptr::null_mut();
    }
    
    let path_str = match CStr::from_ptr(model_path).to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    
    let path = Path::new(path_str);
    
    match DemucsModel::load(path) {
        Ok(model) => {
            let handle = Box::new(DemucsModelHandle { model });
            Box::into_raw(handle)
        }
        Err(e) => {
            eprintln!("Failed to load Demucs model: {}", e);
            ptr::null_mut()
        }
    }
}

/// Free a Demucs model handle
/// 
/// # Safety
/// - `handle` must be from a previous demucs_load_model() call or null
#[no_mangle]
pub unsafe extern "C" fn demucs_free_model(handle: *mut DemucsModelHandle) {
    if !handle.is_null() {
        let _ = Box::from_raw(handle);
    }
}

/// Separate audio file into stems
/// 
/// # Safety
/// - `handle` must be a valid DemucsModelHandle from demucs_load_model()
/// - `input_path` must be a valid null-terminated C string path to an audio file
/// - `output_dir` must be a valid null-terminated C string path to output directory
/// - Caller must free result with demucs_free_result()
#[no_mangle]
pub unsafe extern "C" fn demucs_separate(
    handle: *mut DemucsModelHandle,
    input_path: *const c_char,
    output_dir: *const c_char,
) -> SeparationResultFFI {
    // Validate handle
    if handle.is_null() {
        return SeparationResultFFI {
            stem_count: 0,
            stem_names: ptr::null_mut(),
            stem_paths: ptr::null_mut(),
            error: string_to_c("Invalid model handle".to_string()),
        };
    }
    
    // Parse input path
    let input_str = match CStr::from_ptr(input_path).to_str() {
        Ok(s) => s,
        Err(_) => {
            return SeparationResultFFI {
                stem_count: 0,
                stem_names: ptr::null_mut(),
                stem_paths: ptr::null_mut(),
                error: string_to_c("Invalid input path".to_string()),
            };
        }
    };
    
    // Parse output dir
    let output_str = match CStr::from_ptr(output_dir).to_str() {
        Ok(s) => s,
        Err(_) => {
            return SeparationResultFFI {
                stem_count: 0,
                stem_names: ptr::null_mut(),
                stem_paths: ptr::null_mut(),
                error: string_to_c("Invalid output directory".to_string()),
            };
        }
    };
    
    let model_handle = &mut *handle;
    let input_path = Path::new(input_str);
    let output_dir = Path::new(output_str);
    
    // Run separation
    match separate_file(&mut model_handle.model, input_path, output_dir) {
        Ok(result) => {
            let stem_count = result.stems.len();
            
            // Allocate arrays for names and paths
            let names_ptr = libc::malloc(stem_count * std::mem::size_of::<*mut c_char>()) as *mut *mut c_char;
            let paths_ptr = libc::malloc(stem_count * std::mem::size_of::<*mut c_char>()) as *mut *mut c_char;
            
            if names_ptr.is_null() || paths_ptr.is_null() {
                if !names_ptr.is_null() { libc::free(names_ptr as *mut _); }
                if !paths_ptr.is_null() { libc::free(paths_ptr as *mut _); }
                return SeparationResultFFI {
                    stem_count: 0,
                    stem_names: ptr::null_mut(),
                    stem_paths: ptr::null_mut(),
                    error: string_to_c("Memory allocation failed".to_string()),
                };
            }
            
            // Fill arrays
            for (i, (name, path)) in result.stems.iter().enumerate() {
                *names_ptr.add(i) = string_to_c(name.clone());
                *paths_ptr.add(i) = string_to_c(path.clone());
            }
            
            SeparationResultFFI {
                stem_count: stem_count as c_uint,
                stem_names: names_ptr,
                stem_paths: paths_ptr,
                error: ptr::null_mut(),
            }
        }
        Err(e) => {
            SeparationResultFFI {
                stem_count: 0,
                stem_names: ptr::null_mut(),
                stem_paths: ptr::null_mut(),
                error: string_to_c(format!("Separation failed: {}", e)),
            }
        }
    }
}

/// Free a separation result
/// 
/// # Safety
/// - Only call with a result from demucs_separate()
#[no_mangle]
pub unsafe extern "C" fn demucs_free_result(result: SeparationResultFFI) {
    // Free stem names
    if !result.stem_names.is_null() {
        for i in 0..result.stem_count as usize {
            let name = *result.stem_names.add(i);
            if !name.is_null() {
                let _ = std::ffi::CString::from_raw(name);
            }
        }
        libc::free(result.stem_names as *mut _);
    }
    
    // Free stem paths
    if !result.stem_paths.is_null() {
        for i in 0..result.stem_count as usize {
            let path = *result.stem_paths.add(i);
            if !path.is_null() {
                let _ = std::ffi::CString::from_raw(path);
            }
        }
        libc::free(result.stem_paths as *mut _);
    }
    
    // Free error
    if !result.error.is_null() {
        let _ = std::ffi::CString::from_raw(result.error);
    }
}

/// Get the number of stems the model produces
#[no_mangle]
pub extern "C" fn demucs_stem_count() -> c_uint {
    STEM_NAMES.len() as c_uint
}

/// Get a stem name by index
/// 
/// # Safety
/// - Returns a static string, do not free
#[no_mangle]
pub extern "C" fn demucs_stem_name(index: c_uint) -> *const c_char {
    static STEM_NAMES_C: [&[u8]; 6] = [
        b"drums\0",
        b"bass\0",
        b"vocals\0",
        b"guitar\0",
        b"piano\0",
        b"other\0",
    ];
    
    if (index as usize) < STEM_NAMES_C.len() {
        STEM_NAMES_C[index as usize].as_ptr() as *const c_char
    } else {
        ptr::null()
    }
}
