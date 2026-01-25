// music_tool.h
// C FFI header for the Rust PCA audio processing library

#ifndef MUSIC_TOOL_H
#define MUSIC_TOOL_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque session handle
typedef struct PcaSession PcaSession;

// Result from processing audio
typedef struct {
    PcaSession* session;
    uint32_t num_components;
    uint32_t sample_rate;
    char* error;
} PcaResultFFI;

// Audio buffer
typedef struct {
    double* data;
    size_t length;
    uint32_t sample_rate;
    char* error;
} AudioBufferFFI;

// Component info
typedef struct {
    double eigenvalue;
    double variance_ratio;
} ComponentInfoFFI;

// Result from audio conversion
typedef struct {
    uint8_t* data;
    size_t length;
    uint32_t sample_rate;
    char* error;
} ConvertResultFFI;

// Process audio data and create a PCA session
// Returns a result with session handle or error
// Caller must free session with pca_session_free
PcaResultFFI pca_process_audio(
    const uint8_t* data,
    size_t data_len,
    uint32_t num_components,
    uint32_t window_size,
    uint32_t hop_size
);

// Get component info (eigenvalue and variance ratio)
ComponentInfoFFI pca_get_component_info(
    const PcaSession* session,
    uint32_t component_index
);

// Get audio samples for a specific component
// Caller must free with pca_free_audio_buffer
AudioBufferFFI pca_get_component_audio(
    const PcaSession* session,
    uint32_t component_index
);

// Mix components with given volumes
// volumes array must have num_volumes elements
// Caller must free with pca_free_audio_buffer
AudioBufferFFI pca_mix_components(
    const PcaSession* session,
    const double* volumes,
    size_t num_volumes
);

// Encode audio samples as WAV data
// Returns pointer to WAV bytes, sets out_len to length
// Caller must free with pca_free_bytes
uint8_t* pca_encode_wav(
    const double* samples,
    size_t num_samples,
    uint32_t sample_rate,
    size_t* out_len
);

// Free a PCA session
void pca_session_free(PcaSession* session);

// Free an audio buffer
void pca_free_audio_buffer(AudioBufferFFI buffer);

// Free a byte array
void pca_free_bytes(uint8_t* ptr, size_t len);

// Free an error string
void pca_free_error(char* ptr);

// Free error in result
void pca_result_free_error(PcaResultFFI* result);

// Convert audio file (MP3, WAV, etc.) to WAV format
// Input can be any supported audio format
// Caller must free data with pca_free_bytes and error with pca_free_error
ConvertResultFFI pca_convert_to_wav(
    const uint8_t* data,
    size_t data_len
);

#ifdef __cplusplus
}
#endif

#endif // MUSIC_TOOL_H
