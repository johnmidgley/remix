// remix.h
// C FFI header for the Rust audio processing library

#ifndef REMIX_H
#define REMIX_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Audio Conversion
// ============================================================================

// Result from audio conversion
typedef struct {
    uint8_t* data;
    size_t length;
    uint32_t sample_rate;
    char* error;
} ConvertResultFFI;

// Convert audio file (MP3, WAV, etc.) to WAV format
// Input can be any supported audio format
// Caller must free data with audio_free_bytes and error with audio_free_error
ConvertResultFFI audio_convert_to_wav(
    const uint8_t* data,
    size_t data_len
);

// Free a byte array
void audio_free_bytes(uint8_t* ptr, size_t len);

// Free an error string
void audio_free_error(char* ptr);

// Legacy aliases for backward compatibility
ConvertResultFFI pca_convert_to_wav(
    const uint8_t* data,
    size_t data_len
);

void pca_free_bytes(uint8_t* ptr, size_t len);

void pca_free_error(char* ptr);

// ============================================================================
// Demucs Stem Separation
// ============================================================================

// Opaque handle to a loaded Demucs model
typedef struct DemucsModelHandle DemucsModelHandle;

// Result from stem separation
typedef struct {
    uint32_t stem_count;      // Number of stems (usually 6)
    char** stem_names;        // Array of stem names
    char** stem_paths;        // Array of stem file paths
    char* error;              // Error message (null if success)
} SeparationResultFFI;

// Initialize Demucs (verifies Python and demucs package are available)
// model_path is ignored (kept for API compatibility)
// Returns null on failure if Python/demucs not available
DemucsModelHandle* demucs_load_model(const char* model_path);

// Free a Demucs model handle
void demucs_free_model(DemucsModelHandle* handle);

// Separate audio file into stems
// Caller must free result with demucs_free_result
SeparationResultFFI demucs_separate(
    DemucsModelHandle* handle,
    const char* input_path,
    const char* output_dir
);

// Free a separation result
void demucs_free_result(SeparationResultFFI result);

// Get the number of stems the model produces (6 for htdemucs_6s)
uint32_t demucs_stem_count(void);

// Get a stem name by index (returns static string, do not free)
const char* demucs_stem_name(uint32_t index);

#ifdef __cplusplus
}
#endif

#endif // REMIX_H
