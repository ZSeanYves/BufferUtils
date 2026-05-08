#include "bufferutils_native.h"

#include <stdio.h>
#include <string.h>

enum {
  BUFFERUTILS_NATIVE_KIND_SOURCE = 1,
  BUFFERUTILS_NATIVE_KIND_SINK = 2
};

typedef struct bufferutils_native_handle_entry {
  int32_t id;
  int kind;
  FILE *file;
  struct bufferutils_native_handle_entry *next;
} bufferutils_native_handle_entry;

static bufferutils_native_handle_entry *bufferutils_native_handles = NULL;
static int32_t bufferutils_native_next_id = 1;
static int32_t bufferutils_native_last_status_code = BUFFERUTILS_NATIVE_OK;

static moonbit_bytes_t bufferutils_native_empty_bytes(void) {
  return moonbit_empty_int8_array;
}

static int32_t bufferutils_native_set_status(int32_t status) {
  bufferutils_native_last_status_code = status;
  return status;
}

static char *bufferutils_native_copy_path(const uint8_t *path, int32_t path_len) {
  if (path == NULL || path_len < 0) {
    return NULL;
  }
  char *copy = (char *)libc_malloc((size_t)path_len + 1);
  if (copy == NULL) {
    return NULL;
  }
  if (path_len > 0) {
    memcpy(copy, path, (size_t)path_len);
  }
  copy[path_len] = '\0';
  return copy;
}

static bufferutils_native_handle_entry *bufferutils_native_find(int32_t id) {
  bufferutils_native_handle_entry *entry = bufferutils_native_handles;
  while (entry != NULL) {
    if (entry->id == id) {
      return entry;
    }
    entry = entry->next;
  }
  return NULL;
}

static int32_t bufferutils_native_register(FILE *file, int kind) {
  bufferutils_native_handle_entry *entry =
    (bufferutils_native_handle_entry *)libc_malloc(sizeof(bufferutils_native_handle_entry));
  if (entry == NULL) {
    fclose(file);
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OPEN_FAILED);
    return 0;
  }
  entry->id = bufferutils_native_next_id++;
  entry->kind = kind;
  entry->file = file;
  entry->next = bufferutils_native_handles;
  bufferutils_native_handles = entry;
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return entry->id;
}

static int32_t bufferutils_native_close_internal(int32_t handle_id) {
  if (handle_id <= 0) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_HANDLE);
  }
  bufferutils_native_handle_entry **cursor = &bufferutils_native_handles;
  while (*cursor != NULL) {
    bufferutils_native_handle_entry *entry = *cursor;
    if (entry->id == handle_id) {
      int close_status = 0;
      *cursor = entry->next;
      if (entry->file != NULL) {
        close_status = fclose(entry->file);
      }
      libc_free(entry);
      if (close_status != 0) {
        return bufferutils_native_set_status(BUFFERUTILS_NATIVE_CLOSE_FAILED);
      }
      return bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
    }
    cursor = &entry->next;
  }
  return bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_HANDLE);
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_version(void) {
  return 100;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_last_status(void) {
  return bufferutils_native_last_status_code;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_open_source(
  const uint8_t *path,
  int32_t path_len
) {
  if (path == NULL || path_len <= 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
  char *copy = bufferutils_native_copy_path(path, path_len);
  if (copy == NULL) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OPEN_FAILED);
    return 0;
  }
  FILE *file = fopen(copy, "rb");
  libc_free(copy);
  if (file == NULL) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OPEN_FAILED);
    return 0;
  }
  return bufferutils_native_register(file, BUFFERUTILS_NATIVE_KIND_SOURCE);
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_open_sink(
  const uint8_t *path,
  int32_t path_len,
  int32_t mode
) {
  if (path == NULL || path_len <= 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
  if (mode != 0 && mode != 1) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
  char *copy = bufferutils_native_copy_path(path, path_len);
  if (copy == NULL) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OPEN_FAILED);
    return 0;
  }
  const char *fopen_mode = mode == 1 ? "ab" : "wb";
  FILE *file = fopen(copy, fopen_mode);
  libc_free(copy);
  if (file == NULL) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OPEN_FAILED);
    return 0;
  }
  return bufferutils_native_register(file, BUFFERUTILS_NATIVE_KIND_SINK);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t bufferutils_native_read_chunk(
  int32_t handle_id,
  int32_t size
) {
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  if (size < 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return bufferutils_native_empty_bytes();
  }
  if (size == 0) {
    return bufferutils_native_empty_bytes();
  }

  bufferutils_native_handle_entry *entry = bufferutils_native_find(handle_id);
  if (entry == NULL || entry->kind != BUFFERUTILS_NATIVE_KIND_SOURCE || entry->file == NULL) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_HANDLE);
    return bufferutils_native_empty_bytes();
  }

  moonbit_bytes_t out = moonbit_make_bytes_raw(size);
  size_t read_count = fread(out, 1, (size_t)size, entry->file);
  if (ferror(entry->file)) {
    clearerr(entry->file);
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_READ_FAILED);
    return bufferutils_native_empty_bytes();
  }
  if (read_count == 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_EOF);
    return bufferutils_native_empty_bytes();
  }
  if (read_count < (size_t)size) {
    moonbit_bytes_t exact = moonbit_make_bytes_raw((int32_t)read_count);
    memcpy(exact, out, read_count);
    if (feof(entry->file)) {
      bufferutils_native_set_status(BUFFERUTILS_NATIVE_EOF);
    }
    return exact;
  }
  return out;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_write_chunk(
  int32_t handle_id,
  const uint8_t *data,
  int32_t data_len
) {
  if (data_len < 0) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
  }
  bufferutils_native_handle_entry *entry = bufferutils_native_find(handle_id);
  if (entry == NULL || entry->kind != BUFFERUTILS_NATIVE_KIND_SINK || entry->file == NULL) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_HANDLE);
  }
  if (data_len == 0) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  }
  if (data == NULL) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
  }
  size_t written = fwrite(data, 1, (size_t)data_len, entry->file);
  if (written != (size_t)data_len) {
    clearerr(entry->file);
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_WRITE_FAILED);
  }
  return bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_flush(int32_t handle_id) {
  bufferutils_native_handle_entry *entry = bufferutils_native_find(handle_id);
  if (entry == NULL || entry->kind != BUFFERUTILS_NATIVE_KIND_SINK || entry->file == NULL) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_HANDLE);
  }
  if (fflush(entry->file) != 0) {
    clearerr(entry->file);
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_FLUSH_FAILED);
  }
  return bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_close(int32_t handle_id) {
  return bufferutils_native_close_internal(handle_id);
}
