#include "bufferutils_native.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>

#if defined(__unix__) || defined(__APPLE__)
#define BUFFERUTILS_NATIVE_HAS_MMAP 1
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#else
#define BUFFERUTILS_NATIVE_HAS_MMAP 0
#endif

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

typedef struct bufferutils_native_external_owner_payload {
  uint8_t *data;
  int32_t len;
  int32_t live_views;
  int32_t closed;
  int32_t mapped;
} bufferutils_native_external_owner_payload;

typedef struct bufferutils_native_mmap_owner {
  int32_t id;
  uint8_t *data;
  int32_t len;
  int32_t ref_count;
  int closed;
  int mapped;
  struct bufferutils_native_mmap_owner *next;
} bufferutils_native_mmap_owner;

typedef struct bufferutils_native_mmap_view_entry {
  int32_t id;
  int32_t owner_id;
  int32_t offset;
  int32_t len;
  int closed;
  struct bufferutils_native_mmap_view_entry *next;
} bufferutils_native_mmap_view_entry;

static bufferutils_native_handle_entry *bufferutils_native_handles = NULL;
static bufferutils_native_mmap_owner *bufferutils_native_mmap_owners = NULL;
static bufferutils_native_mmap_view_entry *bufferutils_native_mmap_views = NULL;
static int32_t bufferutils_native_next_id = 1;
static int32_t bufferutils_native_next_mmap_owner_id = 1;
static int32_t bufferutils_native_next_mmap_view_id = 1;
static int32_t bufferutils_native_external_mmap_owner_count = 0;
static int32_t bufferutils_native_external_mmap_view_count = 0;
static int32_t bufferutils_native_last_status_code = BUFFERUTILS_NATIVE_OK;

static moonbit_bytes_t bufferutils_native_empty_bytes(void) {
  return moonbit_empty_int8_array;
}

static int32_t bufferutils_native_set_status(int32_t status) {
  bufferutils_native_last_status_code = status;
  return status;
}

static int32_t bufferutils_native_take_next_id(int32_t *counter) {
  if (counter == NULL || *counter <= 0 || *counter == INT32_MAX) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_ID_EXHAUSTED);
    return 0;
  }
  int32_t id = *counter;
  *counter = id + 1;
  return id;
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

static bufferutils_native_mmap_owner *bufferutils_native_find_mmap_owner(
  int32_t id
) {
  bufferutils_native_mmap_owner *entry = bufferutils_native_mmap_owners;
  while (entry != NULL) {
    if (entry->id == id) {
      return entry;
    }
    entry = entry->next;
  }
  return NULL;
}

static bufferutils_native_mmap_view_entry *bufferutils_native_find_mmap_view(
  int32_t id
) {
  bufferutils_native_mmap_view_entry *entry = bufferutils_native_mmap_views;
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
  entry->id = bufferutils_native_take_next_id(&bufferutils_native_next_id);
  if (entry->id == 0) {
    fclose(file);
    libc_free(entry);
    return 0;
  }
  entry->kind = kind;
  entry->file = file;
  entry->next = bufferutils_native_handles;
  bufferutils_native_handles = entry;
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return entry->id;
}

static bufferutils_native_mmap_owner *bufferutils_native_alloc_mmap_owner(
  uint8_t *data,
  int32_t len,
  int mapped
) {
  bufferutils_native_mmap_owner *owner =
    (bufferutils_native_mmap_owner *)libc_malloc(sizeof(bufferutils_native_mmap_owner));
  if (owner == NULL) {
#if BUFFERUTILS_NATIVE_HAS_MMAP
    if (mapped && data != NULL && len > 0) {
      munmap(data, (size_t)len);
    }
#endif
    return NULL;
  }
  owner->id =
    bufferutils_native_take_next_id(&bufferutils_native_next_mmap_owner_id);
  if (owner->id == 0) {
#if BUFFERUTILS_NATIVE_HAS_MMAP
    if (mapped && data != NULL && len > 0) {
      munmap(data, (size_t)len);
    }
#endif
    libc_free(owner);
    return NULL;
  }
  owner->data = data;
  owner->len = len;
  owner->ref_count = 0;
  owner->closed = 0;
  owner->mapped = mapped;
  owner->next = NULL;
  return owner;
}

static bufferutils_native_mmap_view_entry *bufferutils_native_alloc_mmap_view(
  int32_t owner_id,
  int32_t offset,
  int32_t len
) {
  bufferutils_native_mmap_view_entry *view =
    (bufferutils_native_mmap_view_entry *)libc_malloc(sizeof(bufferutils_native_mmap_view_entry));
  if (view == NULL) {
    return NULL;
  }
  view->id = bufferutils_native_take_next_id(&bufferutils_native_next_mmap_view_id);
  if (view->id == 0) {
    libc_free(view);
    return NULL;
  }
  view->owner_id = owner_id;
  view->offset = offset;
  view->len = len;
  view->closed = 0;
  view->next = NULL;
  return view;
}

static void bufferutils_native_insert_mmap_owner(
  bufferutils_native_mmap_owner *owner
) {
  owner->next = bufferutils_native_mmap_owners;
  bufferutils_native_mmap_owners = owner;
}

static void bufferutils_native_insert_mmap_view(
  bufferutils_native_mmap_view_entry *view
) {
  view->next = bufferutils_native_mmap_views;
  bufferutils_native_mmap_views = view;
}

static int32_t bufferutils_native_release_mmap_owner_by_id(int32_t owner_id) {
  bufferutils_native_mmap_owner **cursor = &bufferutils_native_mmap_owners;
  while (*cursor != NULL) {
    bufferutils_native_mmap_owner *owner = *cursor;
    if (owner->id == owner_id) {
      int32_t status = BUFFERUTILS_NATIVE_OK;
      owner->closed = 1;
      *cursor = owner->next;
#if BUFFERUTILS_NATIVE_HAS_MMAP
      if (owner->mapped && owner->data != NULL && owner->len > 0) {
        if (munmap(owner->data, (size_t)owner->len) != 0) {
          status = BUFFERUTILS_NATIVE_MUNMAP_FAILED;
        }
      }
#endif
      owner->data = NULL;
      owner->len = 0;
      owner->ref_count = 0;
      libc_free(owner);
      return status;
    }
    cursor = &owner->next;
  }
  return BUFFERUTILS_NATIVE_INVALID_HANDLE;
}

static int32_t bufferutils_native_register_mmap_root_view(
  uint8_t *data,
  int32_t len,
  int mapped
) {
  bufferutils_native_mmap_owner *owner =
    bufferutils_native_alloc_mmap_owner(data, len, mapped);
  if (owner == NULL) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_MMAP_FAILED);
    return 0;
  }
  bufferutils_native_mmap_view_entry *view =
    bufferutils_native_alloc_mmap_view(owner->id, 0, len);
  if (view == NULL) {
#if BUFFERUTILS_NATIVE_HAS_MMAP
    if (owner->mapped && owner->data != NULL && owner->len > 0) {
      munmap(owner->data, (size_t)owner->len);
    }
#endif
    libc_free(owner);
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_MMAP_FAILED);
    return 0;
  }
  owner->ref_count = 1;
  bufferutils_native_insert_mmap_owner(owner);
  bufferutils_native_insert_mmap_view(view);
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return view->id;
}

static int32_t bufferutils_native_resolve_mmap_view(
  int32_t handle_id,
  bufferutils_native_mmap_view_entry **out_view,
  bufferutils_native_mmap_owner **out_owner
) {
  if (handle_id <= 0) {
    return BUFFERUTILS_NATIVE_INVALID_HANDLE;
  }
  bufferutils_native_mmap_view_entry *view =
    bufferutils_native_find_mmap_view(handle_id);
  if (view == NULL || view->closed) {
    return BUFFERUTILS_NATIVE_INVALID_HANDLE;
  }
  bufferutils_native_mmap_owner *owner =
    bufferutils_native_find_mmap_owner(view->owner_id);
  if (owner == NULL || owner->closed) {
    return BUFFERUTILS_NATIVE_INVALID_HANDLE;
  }
  *out_view = view;
  *out_owner = owner;
  return BUFFERUTILS_NATIVE_OK;
}

static int32_t bufferutils_native_register_mmap_child_view(
  bufferutils_native_mmap_owner *owner,
  int32_t offset,
  int32_t len
) {
  bufferutils_native_mmap_view_entry *view =
    bufferutils_native_alloc_mmap_view(owner->id, offset, len);
  if (view == NULL) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_MMAP_FAILED);
  }
  owner->ref_count += 1;
  bufferutils_native_insert_mmap_view(view);
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return view->id;
}

static const uint8_t *bufferutils_native_mmap_view_data(
  bufferutils_native_mmap_owner *owner,
  bufferutils_native_mmap_view_entry *view
) {
  if (owner == NULL || owner->data == NULL) {
    return NULL;
  }
  return owner->data + view->offset;
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

static int32_t bufferutils_native_close_mmap_internal(int32_t handle_id) {
  if (handle_id <= 0) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_HANDLE);
  }
  bufferutils_native_mmap_view_entry **cursor = &bufferutils_native_mmap_views;
  while (*cursor != NULL) {
    bufferutils_native_mmap_view_entry *view = *cursor;
    if (view->id == handle_id) {
      int32_t status = BUFFERUTILS_NATIVE_OK;
      int32_t owner_id = view->owner_id;
      bufferutils_native_mmap_owner *owner =
        bufferutils_native_find_mmap_owner(owner_id);

      view->closed = 1;
      *cursor = view->next;

      if (owner != NULL && owner->ref_count > 0) {
        owner->ref_count -= 1;
        if (owner->ref_count == 0) {
          owner->closed = 1;
          status = bufferutils_native_release_mmap_owner_by_id(owner_id);
        }
      }

      libc_free(view);
      return bufferutils_native_set_status(status);
    }
    cursor = &view->next;
  }
  return bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_HANDLE);
}

static uint32_t bufferutils_native_crc32_update(
  uint32_t crc,
  const uint8_t *data,
  int32_t len
) {
  uint32_t result = crc;
  for (int32_t i = 0; i < len; i++) {
    result ^= (uint32_t)data[i];
    for (int bit = 0; bit < 8; bit++) {
      if ((result & 1U) != 0) {
        result = (result >> 1) ^ 0xEDB88320U;
      } else {
        result >>= 1;
      }
    }
  }
  return result;
}

static int32_t bufferutils_native_external_owner_cleanup(
  bufferutils_native_external_owner_payload *owner
) {
  if (owner == NULL) {
    return BUFFERUTILS_NATIVE_INVALID_HANDLE;
  }
  if (owner->closed) {
    return BUFFERUTILS_NATIVE_OK;
  }

  int32_t status = BUFFERUTILS_NATIVE_OK;
#if BUFFERUTILS_NATIVE_HAS_MMAP
  if (owner->mapped && owner->data != NULL && owner->len > 0) {
    if (munmap(owner->data, (size_t)owner->len) != 0) {
      status = BUFFERUTILS_NATIVE_MUNMAP_FAILED;
    }
  }
#endif
  owner->closed = 1;
  owner->data = NULL;
  owner->len = 0;
  owner->mapped = 0;
  owner->live_views = 0;
  return status;
}

static void bufferutils_native_external_owner_finalize(void *self) {
  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)self;
  if (owner == NULL) {
    return;
  }
  if (!owner->closed) {
    if (bufferutils_native_external_mmap_owner_count > 0) {
      bufferutils_native_external_mmap_owner_count -= 1;
    }
    if (owner->live_views > 0) {
      int32_t views = owner->live_views;
      if (views > bufferutils_native_external_mmap_view_count) {
        bufferutils_native_external_mmap_view_count = 0;
      } else {
        bufferutils_native_external_mmap_view_count -= views;
      }
    }
    (void)bufferutils_native_external_owner_cleanup(owner);
  }
}

static int32_t bufferutils_native_external_owner_validate(
  bufferutils_native_external_owner_payload *owner
) {
  if (owner == NULL) {
    return BUFFERUTILS_NATIVE_INVALID_HANDLE;
  }
  if (owner->closed) {
    return BUFFERUTILS_NATIVE_CLOSED;
  }
  return BUFFERUTILS_NATIVE_OK;
}

static int32_t bufferutils_native_external_owner_resolve_view(
  bufferutils_native_external_owner_payload *owner,
  int32_t offset,
  int32_t len,
  const uint8_t **out_base
) {
  int32_t owner_status = bufferutils_native_external_owner_validate(owner);
  if (owner_status != BUFFERUTILS_NATIVE_OK) {
    return owner_status;
  }
  if (offset < 0 || len < 0) {
    return BUFFERUTILS_NATIVE_INVALID_ARGUMENT;
  }
  if (offset > owner->len || len > owner->len - offset) {
    return BUFFERUTILS_NATIVE_OUT_OF_BOUNDS;
  }
  if (out_base != NULL) {
    if (owner->data == NULL) {
      *out_base = NULL;
    } else {
      *out_base = owner->data + offset;
    }
  }
  return BUFFERUTILS_NATIVE_OK;
}

static int32_t bufferutils_native_external_owner_acquire_view(
  bufferutils_native_external_owner_payload *owner
) {
  int32_t status = bufferutils_native_external_owner_validate(owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    return bufferutils_native_set_status(status);
  }
  owner->live_views += 1;
  bufferutils_native_external_mmap_view_count += 1;
  return bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
}

static int32_t bufferutils_native_external_owner_release_view(
  bufferutils_native_external_owner_payload *owner
) {
  int32_t status = bufferutils_native_external_owner_validate(owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    return bufferutils_native_set_status(status);
  }
  if (owner->live_views <= 0) {
    owner->closed = 1;
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_CLOSED);
  }

  owner->live_views -= 1;
  if (bufferutils_native_external_mmap_view_count > 0) {
    bufferutils_native_external_mmap_view_count -= 1;
  }

  if (owner->live_views == 0) {
    if (bufferutils_native_external_mmap_owner_count > 0) {
      bufferutils_native_external_mmap_owner_count -= 1;
    }
    status = bufferutils_native_external_owner_cleanup(owner);
    return bufferutils_native_set_status(status);
  }

  return bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_version(void) {
  return 100;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_last_status(void) {
  return bufferutils_native_last_status_code;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_live_owner_count(void) {
  return bufferutils_native_external_mmap_owner_count;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_live_view_count(void) {
  return bufferutils_native_external_mmap_view_count;
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

MOONBIT_FFI_EXPORT int32_t bufferutils_native_open_mmap_view(
  const uint8_t *path,
  int32_t path_len
) {
  if (path == NULL || path_len <= 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
#if !BUFFERUTILS_NATIVE_HAS_MMAP
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_UNSUPPORTED);
  return 0;
#else
  char *copy = bufferutils_native_copy_path(path, path_len);
  if (copy == NULL) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OPEN_FAILED);
    return 0;
  }
  int fd = open(copy, O_RDONLY);
  libc_free(copy);
  if (fd < 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OPEN_FAILED);
    return 0;
  }

  struct stat st;
  if (fstat(fd, &st) != 0) {
    close(fd);
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_MMAP_FAILED);
    return 0;
  }

  if (st.st_size < 0 || st.st_size > INT32_MAX) {
    close(fd);
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_MMAP_FAILED);
    return 0;
  }

  if (st.st_size == 0) {
    close(fd);
    return bufferutils_native_register_mmap_root_view(NULL, 0, 0);
  }

  void *mapped = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
  close(fd);
  if (mapped == MAP_FAILED) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_MMAP_FAILED);
    return 0;
  }
  return bufferutils_native_register_mmap_root_view(
    (uint8_t *)mapped,
    (int32_t)st.st_size,
    1
  );
#endif
}

MOONBIT_FFI_EXPORT void *bufferutils_native_open_mmap_owner(
  const uint8_t *path,
  int32_t path_len
) {
  if (path == NULL || path_len <= 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return NULL;
  }
#if !BUFFERUTILS_NATIVE_HAS_MMAP
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_UNSUPPORTED);
  return NULL;
#else
  char *copy = bufferutils_native_copy_path(path, path_len);
  if (copy == NULL) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OPEN_FAILED);
    return NULL;
  }
  int fd = open(copy, O_RDONLY);
  libc_free(copy);
  if (fd < 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OPEN_FAILED);
    return NULL;
  }

  struct stat st;
  if (fstat(fd, &st) != 0) {
    close(fd);
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_MMAP_FAILED);
    return NULL;
  }

  if (st.st_size < 0 || st.st_size > INT32_MAX) {
    close(fd);
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_MMAP_FAILED);
    return NULL;
  }

  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)moonbit_make_external_object(
      bufferutils_native_external_owner_finalize,
      (uint32_t)sizeof(bufferutils_native_external_owner_payload)
    );
  if (owner == NULL) {
    close(fd);
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_MMAP_FAILED);
    return NULL;
  }

  owner->data = NULL;
  owner->len = 0;
  owner->live_views = 1;
  owner->closed = 0;
  owner->mapped = 0;

  if (st.st_size > 0) {
    void *mapped = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (mapped == MAP_FAILED) {
      owner->live_views = 0;
      owner->closed = 1;
      bufferutils_native_set_status(BUFFERUTILS_NATIVE_MMAP_FAILED);
      return NULL;
    }
    owner->data = (uint8_t *)mapped;
    owner->len = (int32_t)st.st_size;
    owner->mapped = 1;
  } else {
    close(fd);
  }

  bufferutils_native_external_mmap_owner_count += 1;
  bufferutils_native_external_mmap_view_count += 1;
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return owner;
#endif
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_len(int32_t handle_id) {
  bufferutils_native_mmap_view_entry *view = NULL;
  bufferutils_native_mmap_owner *owner = NULL;
  int32_t status =
    bufferutils_native_resolve_mmap_view(handle_id, &view, &owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  (void)owner;
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return view->len;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_len(void *owner_obj) {
  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)owner_obj;
  int32_t status = bufferutils_native_external_owner_validate(owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return owner->len;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_ref_count(
  int32_t handle_id
) {
  bufferutils_native_mmap_view_entry *view = NULL;
  bufferutils_native_mmap_owner *owner = NULL;
  int32_t status =
    bufferutils_native_resolve_mmap_view(handle_id, &view, &owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  (void)view;
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return owner->ref_count;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_ref_count_obj(
  void *owner_obj
) {
  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)owner_obj;
  int32_t status = bufferutils_native_external_owner_validate(owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return owner->live_views;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_slice_handle(
  int32_t handle_id,
  int32_t start,
  int32_t len
) {
  if (start < 0 || len < 0) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
  }
  bufferutils_native_mmap_view_entry *view = NULL;
  bufferutils_native_mmap_owner *owner = NULL;
  int32_t status =
    bufferutils_native_resolve_mmap_view(handle_id, &view, &owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    return bufferutils_native_set_status(status);
  }
  if (start > view->len || len > view->len - start) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_OUT_OF_BOUNDS);
  }
  return bufferutils_native_register_mmap_child_view(
    owner,
    view->offset + start,
    len
  );
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_acquire_view(
  void *owner_obj
) {
  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)owner_obj;
  return bufferutils_native_external_owner_acquire_view(owner);
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_release_view(
  void *owner_obj
) {
  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)owner_obj;
  return bufferutils_native_external_owner_release_view(owner);
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_read_byte_at(
  int32_t handle_id,
  int32_t index
) {
  if (index < 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
  bufferutils_native_mmap_view_entry *view = NULL;
  bufferutils_native_mmap_owner *owner = NULL;
  int32_t status =
    bufferutils_native_resolve_mmap_view(handle_id, &view, &owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  if (index >= view->len) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OUT_OF_BOUNDS);
    return 0;
  }
  const uint8_t *base = bufferutils_native_mmap_view_data(owner, view);
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return base[index];
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_read_byte_at(
  void *owner_obj,
  int32_t offset,
  int32_t len,
  int32_t index
) {
  if (index < 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)owner_obj;
  const uint8_t *base = NULL;
  int32_t status =
    bufferutils_native_external_owner_resolve_view(owner, offset, len, &base);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  if (index >= len) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OUT_OF_BOUNDS);
    return 0;
  }
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return base[index];
}

MOONBIT_FFI_EXPORT moonbit_bytes_t bufferutils_native_mmap_copy_range(
  int32_t handle_id,
  int32_t start,
  int32_t len
) {
  if (start < 0 || len < 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return bufferutils_native_empty_bytes();
  }
  bufferutils_native_mmap_view_entry *view = NULL;
  bufferutils_native_mmap_owner *owner = NULL;
  int32_t status =
    bufferutils_native_resolve_mmap_view(handle_id, &view, &owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return bufferutils_native_empty_bytes();
  }
  if (len == 0) {
    if (start <= view->len) {
      bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
      return bufferutils_native_empty_bytes();
    }
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OUT_OF_BOUNDS);
    return bufferutils_native_empty_bytes();
  }
  if (start > view->len || len > view->len - start) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OUT_OF_BOUNDS);
    return bufferutils_native_empty_bytes();
  }
  const uint8_t *base = bufferutils_native_mmap_view_data(owner, view);
  moonbit_bytes_t out = moonbit_make_bytes_raw(len);
  memcpy(out, base + start, (size_t)len);
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return out;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t bufferutils_native_mmap_owner_copy_range(
  void *owner_obj,
  int32_t offset,
  int32_t len,
  int32_t start,
  int32_t copy_len
) {
  if (start < 0 || copy_len < 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return bufferutils_native_empty_bytes();
  }
  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)owner_obj;
  const uint8_t *base = NULL;
  int32_t status =
    bufferutils_native_external_owner_resolve_view(owner, offset, len, &base);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return bufferutils_native_empty_bytes();
  }
  if (copy_len == 0) {
    if (start <= len) {
      bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
      return bufferutils_native_empty_bytes();
    }
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OUT_OF_BOUNDS);
    return bufferutils_native_empty_bytes();
  }
  if (start > len || copy_len > len - start) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OUT_OF_BOUNDS);
    return bufferutils_native_empty_bytes();
  }
  moonbit_bytes_t out = moonbit_make_bytes_raw(copy_len);
  memcpy(out, base + start, (size_t)copy_len);
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return out;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_find_byte(
  int32_t handle_id,
  int32_t byte_value
) {
  if (byte_value < 0 || byte_value > 255) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return -1;
  }
  bufferutils_native_mmap_view_entry *view = NULL;
  bufferutils_native_mmap_owner *owner = NULL;
  int32_t status =
    bufferutils_native_resolve_mmap_view(handle_id, &view, &owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return -1;
  }
  const uint8_t *base = bufferutils_native_mmap_view_data(owner, view);
  for (int32_t i = 0; i < view->len; i++) {
    if (base[i] == (uint8_t)byte_value) {
      bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
      return i;
    }
  }
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return -1;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_find_byte(
  void *owner_obj,
  int32_t offset,
  int32_t len,
  int32_t byte_value
) {
  if (byte_value < 0 || byte_value > 255) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return -1;
  }
  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)owner_obj;
  const uint8_t *base = NULL;
  int32_t status =
    bufferutils_native_external_owner_resolve_view(owner, offset, len, &base);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return -1;
  }
  for (int32_t i = 0; i < len; i++) {
    if (base[i] == (uint8_t)byte_value) {
      bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
      return i;
    }
  }
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return -1;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_count_byte(
  int32_t handle_id,
  int32_t byte_value
) {
  if (byte_value < 0 || byte_value > 255) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
  bufferutils_native_mmap_view_entry *view = NULL;
  bufferutils_native_mmap_owner *owner = NULL;
  int32_t status =
    bufferutils_native_resolve_mmap_view(handle_id, &view, &owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  const uint8_t *base = bufferutils_native_mmap_view_data(owner, view);
  int32_t count = 0;
  for (int32_t i = 0; i < view->len; i++) {
    if (base[i] == (uint8_t)byte_value) {
      count++;
    }
  }
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return count;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_count_byte(
  void *owner_obj,
  int32_t offset,
  int32_t len,
  int32_t byte_value
) {
  if (byte_value < 0 || byte_value > 255) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)owner_obj;
  const uint8_t *base = NULL;
  int32_t status =
    bufferutils_native_external_owner_resolve_view(owner, offset, len, &base);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  int32_t count = 0;
  for (int32_t i = 0; i < len; i++) {
    if (base[i] == (uint8_t)byte_value) {
      count++;
    }
  }
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return count;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_index_of(
  int32_t handle_id,
  const uint8_t *data,
  int32_t data_len
) {
  if (data_len < 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return -1;
  }
  if (data_len > 0 && data == NULL) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return -1;
  }
  bufferutils_native_mmap_view_entry *view = NULL;
  bufferutils_native_mmap_owner *owner = NULL;
  int32_t status =
    bufferutils_native_resolve_mmap_view(handle_id, &view, &owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return -1;
  }
  if (data_len == 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
    return 0;
  }
  if (data_len > view->len) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
    return -1;
  }
  const uint8_t *base = bufferutils_native_mmap_view_data(owner, view);
  int32_t limit = view->len - data_len;
  for (int32_t i = 0; i <= limit; i++) {
    if (memcmp(base + i, data, (size_t)data_len) == 0) {
      bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
      return i;
    }
  }
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return -1;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_index_of(
  void *owner_obj,
  int32_t offset,
  int32_t len,
  const uint8_t *data,
  int32_t data_len
) {
  if (data_len < 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return -1;
  }
  if (data_len > 0 && data == NULL) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return -1;
  }
  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)owner_obj;
  const uint8_t *base = NULL;
  int32_t status =
    bufferutils_native_external_owner_resolve_view(owner, offset, len, &base);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return -1;
  }
  if (data_len == 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
    return 0;
  }
  if (data_len > len) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
    return -1;
  }
  int32_t limit = len - data_len;
  for (int32_t i = 0; i <= limit; i++) {
    if (memcmp(base + i, data, (size_t)data_len) == 0) {
      bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
      return i;
    }
  }
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return -1;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_equals(
  int32_t handle_id,
  const uint8_t *data,
  int32_t data_len
) {
  if (data_len < 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
  if (data_len > 0 && data == NULL) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
  bufferutils_native_mmap_view_entry *view = NULL;
  bufferutils_native_mmap_owner *owner = NULL;
  int32_t status =
    bufferutils_native_resolve_mmap_view(handle_id, &view, &owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  if (view->len != data_len) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
    return 0;
  }
  if (data_len == 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
    return 1;
  }
  const uint8_t *base = bufferutils_native_mmap_view_data(owner, view);
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return memcmp(base, data, (size_t)data_len) == 0 ? 1 : 0;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_equals(
  void *owner_obj,
  int32_t offset,
  int32_t len,
  const uint8_t *data,
  int32_t data_len
) {
  if (data_len < 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
  if (data_len > 0 && data == NULL) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)owner_obj;
  const uint8_t *base = NULL;
  int32_t status =
    bufferutils_native_external_owner_resolve_view(owner, offset, len, &base);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  if (len != data_len) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
    return 0;
  }
  if (data_len == 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
    return 1;
  }
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return memcmp(base, data, (size_t)data_len) == 0 ? 1 : 0;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_crc32(int32_t handle_id) {
  bufferutils_native_mmap_view_entry *view = NULL;
  bufferutils_native_mmap_owner *owner = NULL;
  int32_t status =
    bufferutils_native_resolve_mmap_view(handle_id, &view, &owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  const uint8_t *base = bufferutils_native_mmap_view_data(owner, view);
  uint32_t crc = 0xFFFFFFFFU;
  crc = bufferutils_native_crc32_update(crc, base, view->len);
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return (int32_t)(crc ^ 0xFFFFFFFFU);
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_crc32(
  void *owner_obj,
  int32_t offset,
  int32_t len
) {
  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)owner_obj;
  const uint8_t *base = NULL;
  int32_t status =
    bufferutils_native_external_owner_resolve_view(owner, offset, len, &base);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  uint32_t crc = 0xFFFFFFFFU;
  crc = bufferutils_native_crc32_update(crc, base, len);
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return (int32_t)(crc ^ 0xFFFFFFFFU);
}

MOONBIT_FFI_EXPORT uint64_t bufferutils_native_mmap_checksum(int32_t handle_id) {
  bufferutils_native_mmap_view_entry *view = NULL;
  bufferutils_native_mmap_owner *owner = NULL;
  int32_t status =
    bufferutils_native_resolve_mmap_view(handle_id, &view, &owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  const uint8_t *base = bufferutils_native_mmap_view_data(owner, view);
  uint64_t hash = 14695981039346656037ULL;
  for (int32_t i = 0; i < view->len; i++) {
    hash ^= (uint64_t)base[i];
    hash *= 1099511628211ULL;
  }
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return hash;
}

MOONBIT_FFI_EXPORT uint64_t bufferutils_native_mmap_owner_checksum(
  void *owner_obj,
  int32_t offset,
  int32_t len
) {
  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)owner_obj;
  const uint8_t *base = NULL;
  int32_t status =
    bufferutils_native_external_owner_resolve_view(owner, offset, len, &base);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  uint64_t hash = 14695981039346656037ULL;
  for (int32_t i = 0; i < len; i++) {
    hash ^= (uint64_t)base[i];
    hash *= 1099511628211ULL;
  }
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return hash;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_starts_with(
  int32_t handle_id,
  const uint8_t *data,
  int32_t data_len
) {
  if (data_len < 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
  if (data_len > 0 && data == NULL) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
  bufferutils_native_mmap_view_entry *view = NULL;
  bufferutils_native_mmap_owner *owner = NULL;
  int32_t status =
    bufferutils_native_resolve_mmap_view(handle_id, &view, &owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  if (data_len == 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
    return 1;
  }
  if (data_len > view->len) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
    return 0;
  }
  const uint8_t *base = bufferutils_native_mmap_view_data(owner, view);
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return memcmp(base, data, (size_t)data_len) == 0 ? 1 : 0;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_starts_with(
  void *owner_obj,
  int32_t offset,
  int32_t len,
  const uint8_t *data,
  int32_t data_len
) {
  if (data_len < 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
  if (data_len > 0 && data == NULL) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
    return 0;
  }
  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)owner_obj;
  const uint8_t *base = NULL;
  int32_t status =
    bufferutils_native_external_owner_resolve_view(owner, offset, len, &base);
  if (status != BUFFERUTILS_NATIVE_OK) {
    bufferutils_native_set_status(status);
    return 0;
  }
  if (data_len == 0) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
    return 1;
  }
  if (data_len > len) {
    bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
    return 0;
  }
  bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
  return memcmp(base, data, (size_t)data_len) == 0 ? 1 : 0;
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_copy_to_file(
  int32_t handle_id,
  const uint8_t *path,
  int32_t path_len
) {
  if (path == NULL || path_len <= 0) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
  }
  bufferutils_native_mmap_view_entry *view = NULL;
  bufferutils_native_mmap_owner *owner = NULL;
  int32_t status =
    bufferutils_native_resolve_mmap_view(handle_id, &view, &owner);
  if (status != BUFFERUTILS_NATIVE_OK) {
    return bufferutils_native_set_status(status);
  }

  char *copy = bufferutils_native_copy_path(path, path_len);
  if (copy == NULL) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_WRITE_FAILED);
  }

  FILE *file = fopen(copy, "wb");
  libc_free(copy);
  if (file == NULL) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_WRITE_FAILED);
  }

  if (view->len > 0) {
    const uint8_t *base = bufferutils_native_mmap_view_data(owner, view);
    size_t written = fwrite(
      base,
      1,
      (size_t)view->len,
      file
    );
    if (written != (size_t)view->len) {
      clearerr(file);
      fclose(file);
      return bufferutils_native_set_status(BUFFERUTILS_NATIVE_WRITE_FAILED);
    }
  }

  if (fflush(file) != 0) {
    clearerr(file);
    fclose(file);
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_FLUSH_FAILED);
  }
  if (fclose(file) != 0) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_CLOSE_FAILED);
  }
  return bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_owner_copy_to_file(
  void *owner_obj,
  int32_t offset,
  int32_t len,
  const uint8_t *path,
  int32_t path_len
) {
  if (path == NULL || path_len <= 0) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_INVALID_ARGUMENT);
  }
  bufferutils_native_external_owner_payload *owner =
    (bufferutils_native_external_owner_payload *)owner_obj;
  const uint8_t *base = NULL;
  int32_t status =
    bufferutils_native_external_owner_resolve_view(owner, offset, len, &base);
  if (status != BUFFERUTILS_NATIVE_OK) {
    return bufferutils_native_set_status(status);
  }

  char *copy = bufferutils_native_copy_path(path, path_len);
  if (copy == NULL) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_WRITE_FAILED);
  }

  FILE *file = fopen(copy, "wb");
  libc_free(copy);
  if (file == NULL) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_WRITE_FAILED);
  }

  if (len > 0) {
    size_t written = fwrite(base, 1, (size_t)len, file);
    if (written != (size_t)len) {
      clearerr(file);
      fclose(file);
      return bufferutils_native_set_status(BUFFERUTILS_NATIVE_WRITE_FAILED);
    }
  }

  if (fflush(file) != 0) {
    clearerr(file);
    fclose(file);
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_FLUSH_FAILED);
  }
  if (fclose(file) != 0) {
    return bufferutils_native_set_status(BUFFERUTILS_NATIVE_CLOSE_FAILED);
  }
  return bufferutils_native_set_status(BUFFERUTILS_NATIVE_OK);
}

MOONBIT_FFI_EXPORT int32_t bufferutils_native_mmap_close(int32_t handle_id) {
  return bufferutils_native_close_mmap_internal(handle_id);
}
