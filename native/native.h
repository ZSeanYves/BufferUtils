#ifndef BUFFERUTILS_NATIVE_V1_H_INCLUDED
#define BUFFERUTILS_NATIVE_V1_H_INCLUDED

#include "moonbit.h"

#ifdef __cplusplus
extern "C" {
#endif

#define BUFFERUTILS_V1_OK 0
#define BUFFERUTILS_V1_EOF 1
#define BUFFERUTILS_V1_OPEN_FAILED 2
#define BUFFERUTILS_V1_READ_FAILED 3
#define BUFFERUTILS_V1_WRITE_FAILED 4
#define BUFFERUTILS_V1_FLUSH_FAILED 5
#define BUFFERUTILS_V1_CLOSE_FAILED 6
#define BUFFERUTILS_V1_INVALID_ARGUMENT 7
#define BUFFERUTILS_V1_CLOSED 8
#define BUFFERUTILS_V1_SEEK_FAILED 9
#define BUFFERUTILS_V1_MMAP_FAILED 10
#define BUFFERUTILS_V1_UNSUPPORTED 11
#define BUFFERUTILS_V1_INTERRUPTED 12
#define BUFFERUTILS_V1_NOT_FOUND 13
#define BUFFERUTILS_V1_PERMISSION_DENIED 14
#define BUFFERUTILS_V1_WOULD_BLOCK 15
#define BUFFERUTILS_V1_TIMED_OUT 16
#define BUFFERUTILS_V1_CONNECTION_RESET 17
#define BUFFERUTILS_V1_BROKEN_PIPE 18
#define BUFFERUTILS_V1_CONNECTION_REFUSED 19
#define BUFFERUTILS_V1_NOT_CONNECTED 20
#define BUFFERUTILS_V1_ADDRESS_IN_USE 21
#define BUFFERUTILS_V1_ADDRESS_NOT_AVAILABLE 22
#define BUFFERUTILS_V1_STORAGE_FULL 23
#define BUFFERUTILS_V1_OUT_OF_MEMORY 24

MOONBIT_FFI_EXPORT void *bufferutils_file_open(
  const uint8_t *path,
  int32_t path_len,
  int32_t mode
);
MOONBIT_FFI_EXPORT int32_t bufferutils_file_read(
  void *file,
  uint8_t *dst,
  int32_t len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_file_write(
  void *file,
  const uint8_t *src,
  int32_t len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_file_flush(void *file);
MOONBIT_FFI_EXPORT int64_t bufferutils_file_seek(
  void *file,
  int64_t offset,
  int32_t whence
);
MOONBIT_FFI_EXPORT int32_t bufferutils_file_error(void *file);
MOONBIT_FFI_EXPORT int32_t bufferutils_file_os_error(void *file);
MOONBIT_FFI_EXPORT int32_t bufferutils_file_close(void *file);
MOONBIT_FFI_EXPORT int32_t bufferutils_file_is_closed(void *file);

MOONBIT_FFI_EXPORT void *bufferutils_mapped_open(
  const uint8_t *path,
  int32_t path_len
);
MOONBIT_FFI_EXPORT void *bufferutils_mapped_slice(
  void *view,
  int32_t start,
  int32_t len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_mapped_len(void *view);
MOONBIT_FFI_EXPORT int32_t bufferutils_mapped_error(void *view);
MOONBIT_FFI_EXPORT int32_t bufferutils_mapped_os_error(void *view);
MOONBIT_FFI_EXPORT int32_t bufferutils_mapped_read_byte(void *view, int32_t index);
MOONBIT_FFI_EXPORT moonbit_bytes_t bufferutils_mapped_copy(
  void *view,
  int32_t start,
  int32_t len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_mapped_find(void *view, int32_t value);
MOONBIT_FFI_EXPORT int32_t bufferutils_mapped_close(void *view);
MOONBIT_FFI_EXPORT int32_t bufferutils_mapped_is_closed(void *view);

MOONBIT_FFI_EXPORT void *bufferutils_tcp_connect(
  const uint8_t *host,
  int32_t host_len,
  int32_t port
);
MOONBIT_FFI_EXPORT void *bufferutils_tcp_listen(
  const uint8_t *host,
  int32_t host_len,
  int32_t port
);
MOONBIT_FFI_EXPORT void *bufferutils_tcp_accept(void *listener);
MOONBIT_FFI_EXPORT int32_t bufferutils_tcp_local_port(void *listener);
MOONBIT_FFI_EXPORT int32_t bufferutils_tcp_read(
  void *socket,
  uint8_t *dst,
  int32_t len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_tcp_write(
  void *socket,
  const uint8_t *src,
  int32_t len
);
MOONBIT_FFI_EXPORT int32_t bufferutils_tcp_close(void *socket);
MOONBIT_FFI_EXPORT int32_t bufferutils_tcp_is_closed(void *socket);
MOONBIT_FFI_EXPORT int32_t bufferutils_tcp_error(void *socket);
MOONBIT_FFI_EXPORT int32_t bufferutils_tcp_os_error(void *socket);

#ifdef __cplusplus
}
#endif

#endif
