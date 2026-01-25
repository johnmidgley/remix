// music_tool.h
// C FFI header for the Rust audio processing library

#ifndef MUSIC_TOOL_H
#define MUSIC_TOOL_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

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

#ifdef __cplusplus
}
#endif

#endif // MUSIC_TOOL_H
