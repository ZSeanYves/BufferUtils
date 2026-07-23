#include "native.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <io.h>
#else
#include <fcntl.h>
#include <pthread.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/socket.h>
#endif

typedef struct bufferutils_file_payload {
#if defined(_WIN32)
  HANDLE file;
#else
  int file;
#endif
  int32_t mode;
  int32_t closed;
  int32_t error;
  int32_t os_error;
#if defined(_WIN32)
  CRITICAL_SECTION lock;
#else
  pthread_mutex_t lock;
#endif
} bufferutils_file_payload;

typedef struct bufferutils_mapping_owner {
  uint8_t *data;
  int64_t len;
  int32_t refs;
  int32_t mapped;
  int32_t error;
  int32_t os_error;
#if defined(_WIN32)
  HANDLE file;
  HANDLE mapping;
  CRITICAL_SECTION lock;
#else
  pthread_mutex_t lock;
#endif
} bufferutils_mapping_owner;

typedef struct bufferutils_mapping_view {
  bufferutils_mapping_owner *owner;
  int64_t offset;
  int64_t len;
  int32_t closed;
} bufferutils_mapping_view;

typedef struct bufferutils_socket_payload {
#if defined(_WIN32)
  SOCKET socket;
#else
  int socket;
#endif
  int32_t listener;
  int32_t closed;
  int32_t error;
  int32_t os_error;
#if defined(_WIN32)
  int32_t winsock_started;
  CRITICAL_SECTION lock;
#else
  pthread_mutex_t lock;
#endif
} bufferutils_socket_payload;

static void v1_file_lock(bufferutils_file_payload *file) {
#if defined(_WIN32)
  EnterCriticalSection(&file->lock);
#else
  pthread_mutex_lock(&file->lock);
#endif
}

static void v1_file_unlock(bufferutils_file_payload *file) {
#if defined(_WIN32)
  LeaveCriticalSection(&file->lock);
#else
  pthread_mutex_unlock(&file->lock);
#endif
}

static void v1_mapping_lock(bufferutils_mapping_owner *owner) {
#if defined(_WIN32)
  EnterCriticalSection(&owner->lock);
#else
  pthread_mutex_lock(&owner->lock);
#endif
}

static void v1_mapping_unlock(bufferutils_mapping_owner *owner) {
#if defined(_WIN32)
  LeaveCriticalSection(&owner->lock);
#else
  pthread_mutex_unlock(&owner->lock);
#endif
}

static void v1_socket_lock(bufferutils_socket_payload *socket) {
#if defined(_WIN32)
  EnterCriticalSection(&socket->lock);
#else
  pthread_mutex_lock(&socket->lock);
#endif
}

static void v1_socket_unlock(bufferutils_socket_payload *socket) {
#if defined(_WIN32)
  LeaveCriticalSection(&socket->lock);
#else
  pthread_mutex_unlock(&socket->lock);
#endif
}

static void v1_file_finalize(void *payload) {
  bufferutils_file_payload *file = (bufferutils_file_payload *)payload;
  if (!file->closed) {
#if defined(_WIN32)
    if (file->file != INVALID_HANDLE_VALUE) CloseHandle(file->file);
#else
    if (file->file >= 0) close(file->file);
#endif
  }
#if defined(_WIN32)
  DeleteCriticalSection(&file->lock);
#else
  pthread_mutex_destroy(&file->lock);
#endif
}

static void v1_mapping_release(bufferutils_mapping_owner *owner) {
  int should_free = 0;
  v1_mapping_lock(owner);
  owner->refs -= 1;
  should_free = owner->refs == 0;
  v1_mapping_unlock(owner);
  if (should_free) {
    if (owner->data != NULL) {
#if defined(_WIN32)
      if (owner->mapped) UnmapViewOfFile(owner->data);
#else
      if (owner->mapped) munmap(owner->data, (size_t)owner->len);
#endif
      owner->data = NULL;
    }
#if defined(_WIN32)
    if (owner->mapping != NULL) CloseHandle(owner->mapping);
    if (owner->file != INVALID_HANDLE_VALUE) CloseHandle(owner->file);
    DeleteCriticalSection(&owner->lock);
#else
    pthread_mutex_destroy(&owner->lock);
#endif
    libc_free(owner);
  }
}

static void v1_mapping_finalize(void *payload) {
  bufferutils_mapping_view *view = (bufferutils_mapping_view *)payload;
  if (view->owner != NULL && !view->closed) {
    view->closed = 1;
    v1_mapping_release(view->owner);
  }
}

static void v1_socket_finalize(void *payload) {
  bufferutils_socket_payload *socket = (bufferutils_socket_payload *)payload;
  if (!socket->closed) {
#if defined(_WIN32)
    closesocket(socket->socket);
#else
    close(socket->socket);
#endif
    socket->closed = 1;
  }
#if defined(_WIN32)
  DeleteCriticalSection(&socket->lock);
  if (socket->winsock_started) WSACleanup();
#else
  pthread_mutex_destroy(&socket->lock);
#endif
}

static void v1_socket_init(bufferutils_socket_payload *socket) {
#if defined(_WIN32)
  InitializeCriticalSection(&socket->lock);
#else
  pthread_mutex_init(&socket->lock, NULL);
#endif
}

static int v1_socket_from_addrinfo(
  struct addrinfo *list,
  int listener,
#if defined(_WIN32)
  SOCKET *out
#else
  int *out
#endif
  , int *raw_error
) {
  struct addrinfo *item = list;
  while (item != NULL) {
#if defined(_WIN32)
    SOCKET socket_handle = socket(item->ai_family, item->ai_socktype, item->ai_protocol);
    if (socket_handle == INVALID_SOCKET) {
      *raw_error = WSAGetLastError();
      item = item->ai_next;
      continue;
    }
#else
    int socket_handle = socket(item->ai_family, item->ai_socktype, item->ai_protocol);
    if (socket_handle < 0) {
      *raw_error = errno;
      item = item->ai_next;
      continue;
    }
#endif
    int result;
    if (listener) {
      int reuse = 1;
      setsockopt(socket_handle, SOL_SOCKET, SO_REUSEADDR, (const char *)&reuse, sizeof(reuse));
#if defined(_WIN32)
      result = bind(socket_handle, item->ai_addr, (int)item->ai_addrlen);
#else
      result = bind(socket_handle, item->ai_addr, (socklen_t)item->ai_addrlen);
#endif
      if (result == 0) result = listen(socket_handle, 128);
    } else {
#if defined(_WIN32)
      result = connect(socket_handle, item->ai_addr, (int)item->ai_addrlen);
#else
      result = connect(socket_handle, item->ai_addr, (socklen_t)item->ai_addrlen);
#endif
    }
    if (result == 0) { *out = socket_handle; *raw_error = 0; return 1; }
#if defined(_WIN32)
    *raw_error = WSAGetLastError();
    closesocket(socket_handle);
#else
    *raw_error = errno;
    close(socket_handle);
#endif
    item = item->ai_next;
  }
  return 0;
}

static bufferutils_socket_payload *v1_socket_object(int listener) {
  bufferutils_socket_payload *socket =
    (bufferutils_socket_payload *)moonbit_make_external_object(
      v1_socket_finalize, (uint32_t)sizeof(bufferutils_socket_payload));
  if (socket == NULL) return NULL;
#if defined(_WIN32)
  socket->socket = INVALID_SOCKET;
  socket->winsock_started = 0;
#else
  socket->socket = -1;
#endif
  socket->listener = listener;
  socket->closed = 1;
  socket->error = BUFFERUTILS_V1_OPEN_FAILED;
  socket->os_error = 0;
  v1_socket_init(socket);
#if defined(_WIN32)
  WSADATA data;
  int startup = WSAStartup(MAKEWORD(2, 2), &data);
  if (startup != 0) {
    socket->os_error = startup;
    return socket;
  }
  socket->winsock_started = 1;
#endif
  return socket;
}

static int v1_copy_host(const uint8_t *host, int32_t len, char **out) {
  if (len < 0 || (len > 0 && host == NULL) || (host != NULL && memchr(host, 0, (size_t)len) != NULL)) return 0;
  char *copy = (char *)libc_malloc((size_t)len + 1);
  if (copy == NULL) return 0;
  if (len > 0) memcpy(copy, host, (size_t)len);
  copy[len] = 0;
  *out = copy;
  return 1;
}

static int v1_copy_path(const uint8_t *path, int32_t len, char **out) {
  if (path == NULL || len <= 0 || memchr(path, 0, (size_t)len) != NULL) return 0;
  char *copy = (char *)libc_malloc((size_t)len + 1);
  if (copy == NULL) return 0;
  memcpy(copy, path, (size_t)len);
  copy[len] = 0;
  *out = copy;
  return 1;
}

#if defined(_WIN32)
static wchar_t *v1_wide_path(const uint8_t *path, int32_t len) {
  if (path == NULL || len <= 0 || memchr(path, 0, (size_t)len) != NULL) return NULL;
  int wide_len = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (LPCCH)path, len, NULL, 0);
  if (wide_len <= 0) return NULL;
  wchar_t *wide = (wchar_t *)libc_malloc((size_t)(wide_len + 1) * sizeof(wchar_t));
  if (wide == NULL) return NULL;
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (LPCCH)path, len, wide, wide_len) != wide_len) {
    libc_free(wide);
    return NULL;
  }
  wide[wide_len] = L'\0';
  return wide;
}
#endif

static int v1_status_from_os_error(int raw, int fallback) {
#if defined(_WIN32)
  switch (raw) {
    case ERROR_FILE_NOT_FOUND:
    case ERROR_PATH_NOT_FOUND: return BUFFERUTILS_V1_NOT_FOUND;
    case ERROR_ACCESS_DENIED: return BUFFERUTILS_V1_PERMISSION_DENIED;
    case ERROR_INVALID_PARAMETER: return BUFFERUTILS_V1_INVALID_ARGUMENT;
    case ERROR_NOT_ENOUGH_MEMORY:
    case ERROR_OUTOFMEMORY: return BUFFERUTILS_V1_OUT_OF_MEMORY;
    case ERROR_DISK_FULL: return BUFFERUTILS_V1_STORAGE_FULL;
    case WSAEWOULDBLOCK: return BUFFERUTILS_V1_WOULD_BLOCK;
    case WSAETIMEDOUT: return BUFFERUTILS_V1_TIMED_OUT;
    case WSAECONNRESET: return BUFFERUTILS_V1_CONNECTION_RESET;
    case ERROR_BROKEN_PIPE: return BUFFERUTILS_V1_BROKEN_PIPE;
    case WSAECONNREFUSED: return BUFFERUTILS_V1_CONNECTION_REFUSED;
    case WSAENOTCONN: return BUFFERUTILS_V1_NOT_CONNECTED;
    case WSAEADDRINUSE: return BUFFERUTILS_V1_ADDRESS_IN_USE;
    case WSAEADDRNOTAVAIL: return BUFFERUTILS_V1_ADDRESS_NOT_AVAILABLE;
    case WSAEINTR: return BUFFERUTILS_V1_INTERRUPTED;
    default: return fallback;
  }
#else
  switch (raw) {
    case ENOENT: return BUFFERUTILS_V1_NOT_FOUND;
    case EACCES:
    case EPERM: return BUFFERUTILS_V1_PERMISSION_DENIED;
    case EAGAIN:
#if EWOULDBLOCK != EAGAIN
    case EWOULDBLOCK:
#endif
      return BUFFERUTILS_V1_WOULD_BLOCK;
    case ETIMEDOUT: return BUFFERUTILS_V1_TIMED_OUT;
    case ECONNRESET: return BUFFERUTILS_V1_CONNECTION_RESET;
    case EPIPE: return BUFFERUTILS_V1_BROKEN_PIPE;
    case ECONNREFUSED: return BUFFERUTILS_V1_CONNECTION_REFUSED;
    case ENOTCONN: return BUFFERUTILS_V1_NOT_CONNECTED;
    case EADDRINUSE: return BUFFERUTILS_V1_ADDRESS_IN_USE;
    case EADDRNOTAVAIL: return BUFFERUTILS_V1_ADDRESS_NOT_AVAILABLE;
    case EINTR: return BUFFERUTILS_V1_INTERRUPTED;
    case ENOSPC: return BUFFERUTILS_V1_STORAGE_FULL;
    case ENOMEM: return BUFFERUTILS_V1_OUT_OF_MEMORY;
    case EINVAL: return BUFFERUTILS_V1_INVALID_ARGUMENT;
    default: return fallback;
  }
#endif
}

MOONBIT_FFI_EXPORT void *bufferutils_file_open(
  const uint8_t *path, int32_t path_len, int32_t mode
) {
  bufferutils_file_payload *file =
    (bufferutils_file_payload *)moonbit_make_external_object(
      v1_file_finalize, (uint32_t)sizeof(bufferutils_file_payload));
  if (file == NULL) return NULL;
#if defined(_WIN32)
  file->file = INVALID_HANDLE_VALUE;
#else
  file->file = -1;
#endif
  file->mode = mode;
  file->closed = 1;
  file->error = BUFFERUTILS_V1_OPEN_FAILED;
  file->os_error = 0;
#if defined(_WIN32)
  InitializeCriticalSection(&file->lock);
#else
  pthread_mutex_init(&file->lock, NULL);
#endif
#if defined(_WIN32)
  wchar_t *wide = v1_wide_path(path, path_len);
  if (wide == NULL) { file->os_error = ERROR_INVALID_PARAMETER; return file; }
  DWORD access = mode == 0 ? GENERIC_READ : GENERIC_WRITE;
  DWORD creation = mode == 0 ? OPEN_EXISTING : (mode == 1 ? CREATE_ALWAYS : OPEN_ALWAYS);
  HANDLE opened = CreateFileW(
    wide, access, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    NULL, creation, FILE_ATTRIBUTE_NORMAL, NULL
  );
  libc_free(wide);
  if (opened == INVALID_HANDLE_VALUE) {
    file->os_error = (int32_t)GetLastError();
    file->error = v1_status_from_os_error(file->os_error, BUFFERUTILS_V1_OPEN_FAILED);
    return file;
  }
  file->file = opened;
  if (mode == 2) {
    LARGE_INTEGER zero;
    zero.QuadPart = 0;
    if (!SetFilePointerEx(opened, zero, NULL, FILE_END)) {
      file->os_error = (int32_t)GetLastError();
      CloseHandle(opened);
      file->file = INVALID_HANDLE_VALUE;
      file->error = v1_status_from_os_error(file->os_error, BUFFERUTILS_V1_SEEK_FAILED);
      return file;
    }
  }
#else
  char *copy = NULL;
  if (!v1_copy_path(path, path_len, &copy)) {
    file->os_error = EINVAL;
    file->error = BUFFERUTILS_V1_INVALID_ARGUMENT;
    return file;
  }
  int flags = mode == 0 ? O_RDONLY : (O_WRONLY | O_CREAT | (mode == 1 ? O_TRUNC : O_APPEND));
  int opened = open(copy, flags, 0666);
  libc_free(copy);
  if (opened < 0) {
    file->os_error = errno;
    file->error = v1_status_from_os_error(file->os_error, BUFFERUTILS_V1_OPEN_FAILED);
    return file;
  }
  file->file = opened;
#endif
  file->closed = 0;
  file->error = BUFFERUTILS_V1_OK;
  file->os_error = 0;
  return file;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_file_read(
  void *payload, uint8_t *dst, int32_t len
) {
  bufferutils_file_payload *file = (bufferutils_file_payload *)payload;
  if (file == NULL || file->closed) return -BUFFERUTILS_V1_CLOSED;
  if (len < 0 || (len > 0 && dst == NULL)) return -BUFFERUTILS_V1_INVALID_ARGUMENT;
  if (len == 0) return 0;
  v1_file_lock(file);
#if defined(_WIN32)
  DWORD count = 0;
  BOOL ok = ReadFile(file->file, dst, (DWORD)len, &count, NULL);
  if (!ok) {
    file->os_error = (int32_t)GetLastError();
    file->error = v1_status_from_os_error(file->os_error, BUFFERUTILS_V1_READ_FAILED);
    v1_file_unlock(file);
    return -file->error;
  }
#else
  ssize_t count = read(file->file, dst, (size_t)len);
  if (count < 0) {
    file->os_error = errno;
    file->error = v1_status_from_os_error(file->os_error, BUFFERUTILS_V1_READ_FAILED);
    v1_file_unlock(file);
    return -file->error;
  }
#endif
  v1_file_unlock(file);
  return (int32_t)count;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_file_write(
  void *payload, const uint8_t *src, int32_t len
) {
  bufferutils_file_payload *file = (bufferutils_file_payload *)payload;
  if (file == NULL || file->closed) return -BUFFERUTILS_V1_CLOSED;
  if (len < 0 || (len > 0 && src == NULL)) return -BUFFERUTILS_V1_INVALID_ARGUMENT;
  if (len == 0) return 0;
  v1_file_lock(file);
#if defined(_WIN32)
  DWORD count = 0;
  BOOL ok = WriteFile(file->file, src, (DWORD)len, &count, NULL);
  if (!ok) {
    file->os_error = (int32_t)GetLastError();
    file->error = v1_status_from_os_error(file->os_error, BUFFERUTILS_V1_WRITE_FAILED);
    v1_file_unlock(file);
    return -file->error;
  }
#else
  ssize_t count = write(file->file, src, (size_t)len);
  if (count < 0) {
    file->os_error = errno;
    file->error = v1_status_from_os_error(file->os_error, BUFFERUTILS_V1_WRITE_FAILED);
    v1_file_unlock(file);
    return -file->error;
  }
#endif
  v1_file_unlock(file);
  return (int32_t)count;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_file_flush(void *payload) {
  bufferutils_file_payload *file = (bufferutils_file_payload *)payload;
  if (file == NULL || file->closed) return BUFFERUTILS_V1_CLOSED;
  v1_file_lock(file);
#if defined(_WIN32)
  BOOL ok = FlushFileBuffers(file->file);
  int result = ok ? 0 : -1;
  if (!ok) { file->os_error = (int32_t)GetLastError(); file->error = v1_status_from_os_error(file->os_error, BUFFERUTILS_V1_FLUSH_FAILED); }
#else
  int result = fsync(file->file);
  if (result != 0) { file->os_error = errno; file->error = v1_status_from_os_error(file->os_error, BUFFERUTILS_V1_FLUSH_FAILED); }
#endif
  v1_file_unlock(file);
  return result == 0 ? BUFFERUTILS_V1_OK : file->error;
}

MOONBIT_FFI_EXPORT int64_t bufferutils_file_seek(
  void *payload, int64_t offset, int32_t whence
) {
  bufferutils_file_payload *file = (bufferutils_file_payload *)payload;
  if (file == NULL || file->closed) return -(int64_t)BUFFERUTILS_V1_CLOSED;
  v1_file_lock(file);
#if defined(_WIN32)
  LARGE_INTEGER distance;
  LARGE_INTEGER position_value;
  distance.QuadPart = offset;
  DWORD method = whence == SEEK_SET ? FILE_BEGIN : (whence == SEEK_CUR ? FILE_CURRENT : FILE_END);
  BOOL ok = SetFilePointerEx(file->file, distance, &position_value, method);
  int result = ok ? 0 : -1;
  int64_t position = ok ? position_value.QuadPart : -1;
#else
  off_t position_value = lseek(file->file, (off_t)offset, whence);
  int result = position_value < 0 ? -1 : 0;
  int64_t position = (int64_t)position_value;
#endif
  if (result != 0 || position < 0) {
#if defined(_WIN32)
    file->os_error = (int32_t)GetLastError();
#else
    file->os_error = errno;
#endif
    file->error = v1_status_from_os_error(file->os_error, BUFFERUTILS_V1_SEEK_FAILED);
  }
  v1_file_unlock(file);
  return result == 0 && position >= 0 ? position : -(int64_t)BUFFERUTILS_V1_SEEK_FAILED;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_file_error(void *payload) {
  bufferutils_file_payload *file = (bufferutils_file_payload *)payload;
  return file == NULL ? BUFFERUTILS_V1_INVALID_ARGUMENT : file->error;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_file_os_error(void *payload) {
  bufferutils_file_payload *file = (bufferutils_file_payload *)payload;
  return file == NULL ? 0 : file->os_error;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_file_close(void *payload) {
  bufferutils_file_payload *file = (bufferutils_file_payload *)payload;
  if (file == NULL) return BUFFERUTILS_V1_INVALID_ARGUMENT;
  v1_file_lock(file);
  if (file->closed) { v1_file_unlock(file); return BUFFERUTILS_V1_OK; }
#if defined(_WIN32)
  int result = CloseHandle(file->file) ? 0 : -1;
  if (result != 0) file->os_error = (int32_t)GetLastError();
  file->file = INVALID_HANDLE_VALUE;
#else
  int result = close(file->file);
  if (result != 0) file->os_error = errno;
  file->file = -1;
#endif
  file->closed = 1;
  if (result != 0) file->error = v1_status_from_os_error(file->os_error, BUFFERUTILS_V1_CLOSE_FAILED);
  v1_file_unlock(file);
  return result == 0 ? BUFFERUTILS_V1_OK : file->error;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_file_is_closed(void *payload) {
  bufferutils_file_payload *file = (bufferutils_file_payload *)payload;
  return file == NULL || file->closed;
}

static bufferutils_mapping_owner *v1_mapping_owner_new(void) {
  bufferutils_mapping_owner *owner =
    (bufferutils_mapping_owner *)libc_malloc(sizeof(bufferutils_mapping_owner));
  if (owner == NULL) return NULL;
  owner->data = NULL;
  owner->len = 0;
  owner->refs = 1;
  owner->mapped = 0;
  owner->error = BUFFERUTILS_V1_MMAP_FAILED;
  owner->os_error = 0;
#if defined(_WIN32)
  owner->file = INVALID_HANDLE_VALUE;
  owner->mapping = NULL;
  InitializeCriticalSection(&owner->lock);
#else
  pthread_mutex_init(&owner->lock, NULL);
#endif
  return owner;
}

static bufferutils_mapping_view *v1_mapping_view_new(
  bufferutils_mapping_owner *owner, int64_t offset, int64_t len
) {
  bufferutils_mapping_view *view =
    (bufferutils_mapping_view *)moonbit_make_external_object(
      v1_mapping_finalize, (uint32_t)sizeof(bufferutils_mapping_view));
  if (view == NULL) return NULL;
  view->owner = owner;
  view->offset = offset;
  view->len = len;
  view->closed = 0;
  return view;
}

MOONBIT_FFI_EXPORT void *bufferutils_mapped_open(
  const uint8_t *path, int32_t path_len
) {
  bufferutils_mapping_owner *owner = v1_mapping_owner_new();
  if (owner == NULL) return NULL;
  bufferutils_mapping_view *view = v1_mapping_view_new(owner, 0, 0);
  if (view == NULL) { v1_mapping_release(owner); return NULL; }
#if defined(_WIN32)
  wchar_t *wide = v1_wide_path(path, path_len);
  if (wide == NULL) {
    owner->os_error = ERROR_INVALID_PARAMETER;
    owner->error = BUFFERUTILS_V1_INVALID_ARGUMENT;
    return view;
  }
  HANDLE file = CreateFileW(
    wide,
    GENERIC_READ,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    NULL,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL,
    NULL
  );
  libc_free(wide);
  if (file == INVALID_HANDLE_VALUE) {
    owner->os_error = (int32_t)GetLastError();
    owner->error = v1_status_from_os_error(owner->os_error, BUFFERUTILS_V1_MMAP_FAILED);
    return view;
  }
  LARGE_INTEGER size;
  if (!GetFileSizeEx(file, &size)) {
    owner->os_error = (int32_t)GetLastError();
    owner->error = v1_status_from_os_error(owner->os_error, BUFFERUTILS_V1_MMAP_FAILED);
    CloseHandle(file);
    return view;
  }
  if (size.QuadPart < 0 || size.QuadPart > INT32_MAX) {
    owner->error = BUFFERUTILS_V1_UNSUPPORTED;
    CloseHandle(file);
    return view;
  }
  owner->len = (int64_t)size.QuadPart;
  if (owner->len > 0) {
    owner->mapping = CreateFileMappingW(file, NULL, PAGE_READONLY, 0, 0, NULL);
    if (owner->mapping == NULL) {
      owner->os_error = (int32_t)GetLastError();
      owner->error = v1_status_from_os_error(owner->os_error, BUFFERUTILS_V1_MMAP_FAILED);
      CloseHandle(file);
      return view;
    }
    owner->data = (uint8_t *)MapViewOfFile(owner->mapping, FILE_MAP_READ, 0, 0, 0);
    if (owner->data == NULL) {
      owner->os_error = (int32_t)GetLastError();
      owner->error = v1_status_from_os_error(owner->os_error, BUFFERUTILS_V1_MMAP_FAILED);
      CloseHandle(file);
      return view;
    }
    owner->mapped = 1;
  }
  CloseHandle(file);
#else
  char *copy = NULL;
  if (!v1_copy_path(path, path_len, &copy)) {
    owner->os_error = EINVAL;
    owner->error = BUFFERUTILS_V1_INVALID_ARGUMENT;
    return view;
  }
  int fd = open(copy, O_RDONLY);
  libc_free(copy);
  if (fd < 0) {
    owner->os_error = errno;
    owner->error = v1_status_from_os_error(owner->os_error, BUFFERUTILS_V1_MMAP_FAILED);
    return view;
  }
  struct stat st;
  if (fstat(fd, &st) != 0) {
    owner->os_error = errno;
    owner->error = v1_status_from_os_error(owner->os_error, BUFFERUTILS_V1_MMAP_FAILED);
    close(fd);
    return view;
  }
  if (st.st_size < 0 || st.st_size > INT32_MAX) {
    owner->error = BUFFERUTILS_V1_UNSUPPORTED;
    close(fd);
    return view;
  }
  owner->len = (int64_t)st.st_size;
  if (owner->len > 0) {
    owner->data = (uint8_t *)mmap(NULL, (size_t)owner->len, PROT_READ, MAP_PRIVATE, fd, 0);
    if (owner->data == MAP_FAILED) {
      owner->data = NULL;
      owner->os_error = errno;
      owner->error = v1_status_from_os_error(owner->os_error, BUFFERUTILS_V1_MMAP_FAILED);
      close(fd);
      return view;
    }
    owner->mapped = 1;
  }
  close(fd);
#endif
  owner->error = BUFFERUTILS_V1_OK;
  owner->os_error = 0;
  view->len = owner->len;
  return view;
}

MOONBIT_FFI_EXPORT void *bufferutils_mapped_slice(
  void *payload, int32_t start, int32_t len
) {
  bufferutils_mapping_view *parent = (bufferutils_mapping_view *)payload;
  if (parent == NULL || parent->closed || start < 0 || len < 0 || (int64_t)start + len > parent->len) return NULL;
  bufferutils_mapping_owner *owner = parent->owner;
  v1_mapping_lock(owner);
  owner->refs += 1;
  v1_mapping_unlock(owner);
  bufferutils_mapping_view *view = v1_mapping_view_new(owner, parent->offset + start, len);
  if (view == NULL) v1_mapping_release(owner);
  return view;
}

static int v1_view_ok(bufferutils_mapping_view *view) {
  return view != NULL && !view->closed && view->owner != NULL &&
    view->owner->error == BUFFERUTILS_V1_OK;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_mapped_len(void *payload) {
  bufferutils_mapping_view *view = (bufferutils_mapping_view *)payload;
  if (view == NULL || view->closed || view->owner == NULL) return -BUFFERUTILS_V1_CLOSED;
  if (view->owner->error != BUFFERUTILS_V1_OK) return -view->owner->error;
  return (int32_t)view->len;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_mapped_error(void *payload) {
  bufferutils_mapping_view *view = (bufferutils_mapping_view *)payload;
  return view == NULL || view->owner == NULL ? BUFFERUTILS_V1_OUT_OF_MEMORY : view->owner->error;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_mapped_os_error(void *payload) {
  bufferutils_mapping_view *view = (bufferutils_mapping_view *)payload;
  return view == NULL || view->owner == NULL ? 0 : view->owner->os_error;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_mapped_read_byte(void *payload, int32_t index) {
  bufferutils_mapping_view *view = (bufferutils_mapping_view *)payload;
  if (!v1_view_ok(view)) return -BUFFERUTILS_V1_CLOSED;
  if (index < 0 || (int64_t)index >= view->len) return -BUFFERUTILS_V1_INVALID_ARGUMENT;
  return (int32_t)view->owner->data[view->offset + index];
}

MOONBIT_FFI_EXPORT moonbit_bytes_t bufferutils_mapped_copy(
  void *payload, int32_t start, int32_t len
) {
  bufferutils_mapping_view *view = (bufferutils_mapping_view *)payload;
  if (!v1_view_ok(view) || start < 0 || len < 0 || (int64_t)start + len > view->len) return moonbit_empty_int8_array;
  moonbit_bytes_t result = moonbit_make_bytes_raw(len);
  if (len > 0) memcpy(result, view->owner->data + view->offset + start, (size_t)len);
  return result;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_mapped_find(void *payload, int32_t value) {
  bufferutils_mapping_view *view = (bufferutils_mapping_view *)payload;
  if (!v1_view_ok(view) || value < 0 || value > 255) return -BUFFERUTILS_V1_INVALID_ARGUMENT;
  for (int64_t i = 0; i < view->len; i++) if (view->owner->data[view->offset + i] == (uint8_t)value) return (int32_t)i;
  return -1;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_mapped_close(void *payload) {
  bufferutils_mapping_view *view = (bufferutils_mapping_view *)payload;
  if (view == NULL || view->closed) return BUFFERUTILS_V1_OK;
  view->closed = 1;
  v1_mapping_release(view->owner);
  return BUFFERUTILS_V1_OK;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_mapped_is_closed(void *payload) {
  bufferutils_mapping_view *view = (bufferutils_mapping_view *)payload;
  return !v1_view_ok(view);
}

static void *v1_tcp_open_common(
  const uint8_t *host,
  int32_t host_len,
  int32_t port,
  int listener
) {
  bufferutils_socket_payload *result = v1_socket_object(listener);
  if (result == NULL) return NULL;
  if (port < 0 || port > 65535) {
    result->error = BUFFERUTILS_V1_INVALID_ARGUMENT;
    return result;
  }
#if defined(_WIN32)
  if (!result->winsock_started) return result;
#endif
  char *host_copy = NULL;
  if (!v1_copy_host(host, host_len, &host_copy)) {
    result->error = BUFFERUTILS_V1_INVALID_ARGUMENT;
    return result;
  }
  char port_buffer[16];
  snprintf(port_buffer, sizeof(port_buffer), "%d", port);
  struct addrinfo hints;
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;
  if (listener) hints.ai_flags = AI_PASSIVE;
  struct addrinfo *addresses = NULL;
  const char *node = host_len == 0 ? NULL : host_copy;
  int status = getaddrinfo(node, port_buffer, &hints, &addresses);
  libc_free(host_copy);
  if (status != 0 || addresses == NULL) {
    result->os_error = status;
    result->error = BUFFERUTILS_V1_OPEN_FAILED;
    return result;
  }
  int opened = v1_socket_from_addrinfo(
    addresses,
    listener,
    &result->socket,
    &result->os_error
  );
  freeaddrinfo(addresses);
  if (!opened) {
    result->error = v1_status_from_os_error(
      result->os_error,
      BUFFERUTILS_V1_OPEN_FAILED
    );
    return result;
  }
  result->closed = 0;
  result->error = BUFFERUTILS_V1_OK;
  return result;
}

MOONBIT_FFI_EXPORT void *bufferutils_tcp_connect(
  const uint8_t *host, int32_t host_len, int32_t port
) {
  return v1_tcp_open_common(host, host_len, port, 0);
}

MOONBIT_FFI_EXPORT void *bufferutils_tcp_listen(
  const uint8_t *host, int32_t host_len, int32_t port
) {
  return v1_tcp_open_common(host, host_len, port, 1);
}

MOONBIT_FFI_EXPORT void *bufferutils_tcp_accept(void *payload) {
  bufferutils_socket_payload *listener = (bufferutils_socket_payload *)payload;
  bufferutils_socket_payload *result = v1_socket_object(0);
  if (result == NULL) return NULL;
  if (listener == NULL || listener->closed || !listener->listener) {
    result->error = BUFFERUTILS_V1_CLOSED;
    return result;
  }
#if defined(_WIN32)
  SOCKET accepted = accept(listener->socket, NULL, NULL);
  if (accepted == INVALID_SOCKET) {
    result->os_error = WSAGetLastError();
    result->error = v1_status_from_os_error(result->os_error, BUFFERUTILS_V1_OPEN_FAILED);
    return result;
  }
#else
  int accepted = accept(listener->socket, NULL, NULL);
  if (accepted < 0) {
    result->os_error = errno;
    result->error = v1_status_from_os_error(result->os_error, BUFFERUTILS_V1_OPEN_FAILED);
    return result;
  }
#endif
  result->socket = accepted;
  result->closed = 0;
  result->error = BUFFERUTILS_V1_OK;
  return result;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_tcp_local_port(void *payload) {
  bufferutils_socket_payload *socket = (bufferutils_socket_payload *)payload;
  if (socket == NULL || socket->closed) return -BUFFERUTILS_V1_CLOSED;
  struct sockaddr_storage address;
#if defined(_WIN32)
  int len = (int)sizeof(address);
#else
  socklen_t len = (socklen_t)sizeof(address);
#endif
  if (getsockname(socket->socket, (struct sockaddr *)&address, &len) != 0) {
#if defined(_WIN32)
    socket->os_error = WSAGetLastError();
#else
    socket->os_error = errno;
#endif
    socket->error = v1_status_from_os_error(socket->os_error, BUFFERUTILS_V1_OPEN_FAILED);
    return -socket->error;
  }
  if (address.ss_family == AF_INET) {
    return ntohs(((struct sockaddr_in *)&address)->sin_port);
  }
  if (address.ss_family == AF_INET6) {
    return ntohs(((struct sockaddr_in6 *)&address)->sin6_port);
  }
  return -BUFFERUTILS_V1_OPEN_FAILED;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_tcp_read(
  void *payload, uint8_t *dst, int32_t len
) {
  bufferutils_socket_payload *socket = (bufferutils_socket_payload *)payload;
  if (socket == NULL || socket->closed || socket->listener) return -BUFFERUTILS_V1_CLOSED;
  if (len < 0 || (len > 0 && dst == NULL)) return -BUFFERUTILS_V1_INVALID_ARGUMENT;
  if (len == 0) return 0;
  v1_socket_lock(socket);
#if defined(_WIN32)
  int count = recv(socket->socket, (char *)dst, len, 0);
#else
  int count = (int)recv(socket->socket, dst, (size_t)len, 0);
#endif
  if (count < 0) {
#if defined(_WIN32)
    socket->os_error = WSAGetLastError();
#else
    socket->os_error = errno;
#endif
    socket->error = v1_status_from_os_error(socket->os_error, BUFFERUTILS_V1_READ_FAILED);
  }
  v1_socket_unlock(socket);
  return count < 0 ? -socket->error : count;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_tcp_write(
  void *payload, const uint8_t *src, int32_t len
) {
  bufferutils_socket_payload *socket = (bufferutils_socket_payload *)payload;
  if (socket == NULL || socket->closed || socket->listener) return -BUFFERUTILS_V1_CLOSED;
  if (len < 0 || (len > 0 && src == NULL)) return -BUFFERUTILS_V1_INVALID_ARGUMENT;
  if (len == 0) return 0;
  v1_socket_lock(socket);
#if defined(_WIN32)
  int count = send(socket->socket, (const char *)src, len, 0);
#else
  int count = (int)send(socket->socket, src, (size_t)len, 0);
#endif
  if (count < 0) {
#if defined(_WIN32)
    socket->os_error = WSAGetLastError();
#else
    socket->os_error = errno;
#endif
    socket->error = v1_status_from_os_error(socket->os_error, BUFFERUTILS_V1_WRITE_FAILED);
  }
  v1_socket_unlock(socket);
  return count < 0 ? -socket->error : count;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_tcp_close(void *payload) {
  bufferutils_socket_payload *socket = (bufferutils_socket_payload *)payload;
  if (socket == NULL) return BUFFERUTILS_V1_INVALID_ARGUMENT;
  v1_socket_lock(socket);
  if (socket->closed) { v1_socket_unlock(socket); return BUFFERUTILS_V1_OK; }
#if defined(_WIN32)
  int status = closesocket(socket->socket);
  if (status != 0) socket->os_error = WSAGetLastError();
  socket->socket = INVALID_SOCKET;
#else
  int status = close(socket->socket);
  if (status != 0) socket->os_error = errno;
  socket->socket = -1;
#endif
  socket->closed = 1;
  v1_socket_unlock(socket);
  return status == 0 ? BUFFERUTILS_V1_OK : BUFFERUTILS_V1_CLOSE_FAILED;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_tcp_is_closed(void *payload) {
  bufferutils_socket_payload *socket = (bufferutils_socket_payload *)payload;
  return socket == NULL || socket->closed;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_tcp_error(void *payload) {
  bufferutils_socket_payload *socket = (bufferutils_socket_payload *)payload;
  return socket == NULL ? BUFFERUTILS_V1_INVALID_ARGUMENT : socket->error;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_tcp_os_error(void *payload) {
  bufferutils_socket_payload *socket = (bufferutils_socket_payload *)payload;
  return socket == NULL ? 0 : socket->os_error;
}
