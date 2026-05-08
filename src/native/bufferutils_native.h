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
#define BUFFERUTILS_NATIVE_MMAP_FAILED 9
#define BUFFERUTILS_NATIVE_MUNMAP_FAILED 10
#define BUFFERUTILS_NATIVE_OUT_OF_BOUNDS 11
#define BUFFERUTILS_NATIVE_CLOSED 12
#define BUFFERUTILS_NATIVE_UNSUPPORTED 13
#define BUFFERUTILS_NATIVE_ID_EXHAUSTED 14

MOONBIT_FFI_EXPORT int32_t bufferutils_native_version(void);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_last_status(void);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_open_source(const uint8_t *path, int32_t path_len);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_open_sink(const uint8_t *path, int32_t path_len, int32_t mode);
MOONBIT_FFI_EXPORT moonbit_bytes_t bufferutils_native_read_chunk(int32_t handle_id, int32_t size);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_write_chunk(int32_t handle_id, const uint8_t *data, int32_t data_len);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_flush(int32_t handle_id);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_close(int32_t handle_id);

MOONBIT_FFI_EXPORT int32_t bufferutils_native_open_mmap_view(
  const uint8_t *path,
  int32_t path_len
);
MOONBIT_FFI_EXPORT void *bufferutils_native_open_mmap_owner(
  const uint8_t *path,
  int32_t path_len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_len(int32_t handle_id);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_len(void *owner);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_ref_count(
  int32_t handle_id
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_ref_count_obj(
  void *owner
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_slice_handle(
  int32_t handle_id,
  int32_t start,
  int32_t len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_acquire_view(
  void *owner
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_release_view(
  void *owner
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_read_byte_at(
  int32_t handle_id,
  int32_t index
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_read_byte_at(
  void *owner,
  int32_t offset,
  int32_t len,
  int32_t index
);
MOONBIT_FFI_EXPORT moonbit_bytes_t bufferutils_native_mmap_copy_range(
  int32_t handle_id,
  int32_t start,
  int32_t len
);
MOONBIT_FFI_EXPORT moonbit_bytes_t bufferutils_native_mmap_owner_copy_range(
  void *owner,
  int32_t offset,
  int32_t len,
  int32_t start,
  int32_t copy_len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_find_byte(
  int32_t handle_id,
  int32_t byte_value
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_find_byte(
  void *owner,
  int32_t offset,
  int32_t len,
  int32_t byte_value
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_count_byte(
  int32_t handle_id,
  int32_t byte_value
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_count_byte(
  void *owner,
  int32_t offset,
  int32_t len,
  int32_t byte_value
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_index_of(
  int32_t handle_id,
  const uint8_t *data,
  int32_t data_len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_index_of(
  void *owner,
  int32_t offset,
  int32_t len,
  const uint8_t *data,
  int32_t data_len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_equals(
  int32_t handle_id,
  const uint8_t *data,
  int32_t data_len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_equals(
  void *owner,
  int32_t offset,
  int32_t len,
  const uint8_t *data,
  int32_t data_len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_crc32(int32_t handle_id);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_crc32(
  void *owner,
  int32_t offset,
  int32_t len
);
MOONBIT_FFI_EXPORT uint64_t bufferutils_native_mmap_checksum(
  int32_t handle_id
);
MOONBIT_FFI_EXPORT uint64_t bufferutils_native_mmap_owner_checksum(
  void *owner,
  int32_t offset,
  int32_t len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_starts_with(
  int32_t handle_id,
  const uint8_t *data,
  int32_t data_len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_starts_with(
  void *owner,
  int32_t offset,
  int32_t len,
  const uint8_t *data,
  int32_t data_len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_copy_to_file(
  int32_t handle_id,
  const uint8_t *path,
  int32_t path_len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_copy_to_file(
  void *owner,
  int32_t offset,
  int32_t len,
  const uint8_t *path,
  int32_t path_len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_close(int32_t handle_id);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_live_owner_count(void);
MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_live_view_count(void);

#ifdef __cplusplus
}
#endif

#endif
