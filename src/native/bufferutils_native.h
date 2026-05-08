#ifndef BUFFERUTILS_NATIVE_H_INCLUDED
#define BUFFERUTILS_NATIVE_H_INCLUDED

#include "moonbit.h"

#ifdef __cplusplus
extern "C" {
#endif

#define BUFFERUTILS_NATIVE_OK 0
#define BUFFERUTILS_NATIVE_EOF 1
#define BUFFERUTILS_NATIVE_OPEN_FAILED 2
#define BUFFERUTILS_NATIVE_READ_FAILED 3
#define BUFFERUTILS_NATIVE_WRITE_FAILED 4
#define BUFFERUTILS_NATIVE_FLUSH_FAILED 5
#define BUFFERUTILS_NATIVE_CLOSE_FAILED 6
#define BUFFERUTILS_NATIVE_INVALID_HANDLE 7
#define BUFFERUTILS_NATIVE_INVALID_ARGUMENT 8

MOONBIT_FFI_EXPORT int32_t bufferutils_native_version(void);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_last_status(void);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_open_source(const uint8_t *path, int32_t path_len);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_open_sink(const uint8_t *path, int32_t path_len, int32_t mode);
MOONBIT_FFI_EXPORT moonbit_bytes_t bufferutils_native_read_chunk(int32_t handle_id, int32_t size);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_write_chunk(int32_t handle_id, const uint8_t *data, int32_t data_len);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_flush(int32_t handle_id);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_close(int32_t handle_id);

#ifdef __cplusplus
}
#endif

#endif
