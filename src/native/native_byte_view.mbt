///|
fn ensure_native_byte_view_open(
  view : NativeByteView,
) -> Unit raise @bufferutils.BufferError {
  if view.closed {
    @bufferutils.raise_buffer_io("native byte view is closed")
  }
}

///|
fn raise_native_mmap_open_error(
  code : Int,
) -> Unit raise @bufferutils.BufferError {
  match decode_native_status(code) {
    NativeBackendErrorCode::InvalidInput =>
      @bufferutils.raise_buffer_invalid_input(
        "native mmap view open failed: \{native_backend_status_message(code)}",
      )
    _ =>
      @bufferutils.raise_buffer_io(
        "native mmap view open failed: \{native_backend_status_message(code)}",
      )
  }
}

///|
fn raise_native_byte_view_error(
  action : String,
  code : Int,
) -> Unit raise @bufferutils.BufferError {
  match decode_native_status(code) {
    NativeBackendErrorCode::InvalidInput =>
      @bufferutils.raise_buffer_invalid_input(
        "\{action}: \{native_backend_status_message(code)}",
      )
    NativeBackendErrorCode::OutOfBounds =>
      @bufferutils.raise_buffer_underflow(
        "\{action}: \{native_backend_status_message(code)}",
      )
    _ =>
      @bufferutils.raise_buffer_io(
        "\{action}: \{native_backend_status_message(code)}",
      )
  }
}

///|
/// Experimental native-only borrowed byte handle over read-only mmap memory.
/// This is a research API: it provides explicit access operations without
/// claiming a stable MoonBit `BytesView` bridge.
pub struct NativeByteView {
  priv path : String
  priv mut handle_id : Int
  priv byte_len : Int
  priv mut closed : Bool
}

///|
pub fn new_mmap_file_view(
  path : String,
) -> NativeByteView raise @bufferutils.BufferError {
  validate_native_path(path)
  let path_bytes = native_utf8_path_bytes(path)
  let handle_id = native_open_mmap_view_ffi(path_bytes, path_bytes.length())
  if handle_id <= 0 {
    raise_native_mmap_open_error(native_last_status_ffi())
  }
  let byte_len = native_mmap_len_ffi(handle_id)
  let len_status = native_last_status_ffi()
  if len_status != 0 {
    ignore(native_mmap_close_ffi(handle_id))
    raise_native_byte_view_error(
      "native mmap view length query failed", len_status,
    )
  }
  { path, handle_id, byte_len, closed: false }
}

///|
pub fn NativeByteView::len(self : NativeByteView) -> Int {
  self.byte_len
}

///|
pub fn NativeByteView::is_closed(self : NativeByteView) -> Bool {
  self.closed
}

///|
pub fn NativeByteView::owner_ref_count(
  self : NativeByteView,
) -> Int raise @bufferutils.BufferError {
  ensure_native_byte_view_open(self)
  let count = native_mmap_owner_ref_count_ffi(self.handle_id)
  let status = native_last_status_ffi()
  if status != 0 {
    raise_native_byte_view_error(
      "native byte view owner ref-count query failed", status,
    )
  }
  count
}

///|
pub fn NativeByteView::slice_handle(
  self : NativeByteView,
  start : Int,
  len : Int,
) -> NativeByteView raise @bufferutils.BufferError {
  ensure_native_byte_view_open(self)
  if start < 0 {
    @bufferutils.raise_buffer_invalid_input(
      "slice handle start must be non-negative",
    )
  }
  if len < 0 {
    @bufferutils.raise_buffer_invalid_input(
      "slice handle length must be non-negative",
    )
  }
  let child_handle = native_mmap_slice_handle_ffi(self.handle_id, start, len)
  let status = native_last_status_ffi()
  if status != 0 || child_handle <= 0 {
    raise_native_byte_view_error(
      "native byte view slice creation failed", status,
    )
  }
  { path: self.path, handle_id: child_handle, byte_len: len, closed: false }
}

///|
pub fn NativeByteView::read_byte_at(
  self : NativeByteView,
  index : Int,
) -> Byte raise @bufferutils.BufferError {
  ensure_native_byte_view_open(self)
  if index < 0 {
    @bufferutils.raise_buffer_invalid_input("byte index must be non-negative")
  }
  let value = native_mmap_read_byte_at_ffi(self.handle_id, index)
  let status = native_last_status_ffi()
  if status != 0 {
    raise_native_byte_view_error("native byte view read failed", status)
  }
  value.to_byte()
}

///|
pub fn NativeByteView::copy_range(
  self : NativeByteView,
  start : Int,
  len : Int,
) -> Array[Byte] raise @bufferutils.BufferError {
  ensure_native_byte_view_open(self)
  if start < 0 {
    @bufferutils.raise_buffer_invalid_input(
      "copy range start must be non-negative",
    )
  }
  if len < 0 {
    @bufferutils.raise_buffer_invalid_input(
      "copy range length must be non-negative",
    )
  }
  if len == 0 && start <= self.byte_len {
    return []
  }
  let bytes = native_mmap_copy_range_ffi(self.handle_id, start, len)
  let status = native_last_status_ffi()
  if status != 0 {
    raise_native_byte_view_error("native byte view copy failed", status)
  }
  bytes.to_array()
}

///|
pub fn NativeByteView::find_byte(
  self : NativeByteView,
  b : Byte,
) -> Int raise @bufferutils.BufferError {
  ensure_native_byte_view_open(self)
  let index = native_mmap_find_byte_ffi(self.handle_id, b.to_int())
  let status = native_last_status_ffi()
  if status != 0 {
    raise_native_byte_view_error("native byte view search failed", status)
  }
  index
}

///|
pub fn NativeByteView::count_byte(
  self : NativeByteView,
  b : Byte,
) -> Int raise @bufferutils.BufferError {
  ensure_native_byte_view_open(self)
  let count = native_mmap_count_byte_ffi(self.handle_id, b.to_int())
  let status = native_last_status_ffi()
  if status != 0 {
    raise_native_byte_view_error("native byte view count failed", status)
  }
  count
}

///|
pub fn NativeByteView::index_of(
  self : NativeByteView,
  data : Array[Byte],
) -> Int raise @bufferutils.BufferError {
  ensure_native_byte_view_open(self)
  let bytes = @bufferutils.array_to_bytes(data)
  let index = native_mmap_index_of_ffi(self.handle_id, bytes, bytes.length())
  let status = native_last_status_ffi()
  if status != 0 {
    raise_native_byte_view_error(
      "native byte view pattern search failed", status,
    )
  }
  index
}

///|
pub fn NativeByteView::equals(
  self : NativeByteView,
  data : Array[Byte],
) -> Bool raise @bufferutils.BufferError {
  ensure_native_byte_view_open(self)
  let bytes = @bufferutils.array_to_bytes(data)
  let matched = native_mmap_equals_ffi(self.handle_id, bytes, bytes.length())
  let status = native_last_status_ffi()
  if status != 0 {
    raise_native_byte_view_error(
      "native byte view equality check failed", status,
    )
  }
  matched != 0
}

///|
pub fn NativeByteView::crc32(
  self : NativeByteView,
) -> Int raise @bufferutils.BufferError {
  ensure_native_byte_view_open(self)
  let checksum = native_mmap_crc32_ffi(self.handle_id)
  let status = native_last_status_ffi()
  if status != 0 {
    raise_native_byte_view_error("native byte view crc32 failed", status)
  }
  checksum
}

///|
pub fn NativeByteView::checksum_u64(
  self : NativeByteView,
) -> UInt64 raise @bufferutils.BufferError {
  ensure_native_byte_view_open(self)
  let checksum = native_mmap_checksum_ffi(self.handle_id)
  let status = native_last_status_ffi()
  if status != 0 {
    raise_native_byte_view_error("native byte view checksum failed", status)
  }
  checksum
}

///|
pub fn NativeByteView::starts_with(
  self : NativeByteView,
  data : Array[Byte],
) -> Bool raise @bufferutils.BufferError {
  ensure_native_byte_view_open(self)
  let bytes = @bufferutils.array_to_bytes(data)
  let matched = native_mmap_starts_with_ffi(
    self.handle_id,
    bytes,
    bytes.length(),
  )
  let status = native_last_status_ffi()
  if status != 0 {
    raise_native_byte_view_error("native byte view prefix check failed", status)
  }
  matched != 0
}

///|
pub fn NativeByteView::copy_to_file(
  self : NativeByteView,
  path : String,
) -> Unit raise @bufferutils.BufferError {
  ensure_native_byte_view_open(self)
  validate_native_path(path)
  let path_bytes = native_utf8_path_bytes(path)
  let status = native_mmap_copy_to_file_ffi(
    self.handle_id,
    path_bytes,
    path_bytes.length(),
  )
  if status != 0 {
    raise_native_byte_view_error("native byte view copy-to-file failed", status)
  }
}

///|
pub fn NativeByteView::close(
  self : NativeByteView,
) -> Unit raise @bufferutils.BufferError {
  if self.closed {
    return
  }
  let status = native_mmap_close_ffi(self.handle_id)
  self.closed = true
  self.handle_id = 0
  if status != 0 {
    raise_native_byte_view_error("native byte view close failed", status)
  }
}
