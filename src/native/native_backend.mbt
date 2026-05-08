///|
/// Native backend error codes returned by the experimental C file-handle layer.
priv enum NativeBackendErrorCode {
  Ok
  Eof
  OpenFailed
  ReadFailed
  WriteFailed
  FlushFailed
  CloseFailed
  InvalidHandle
  InvalidInput
  MmapFailed
  MunmapFailed
  OutOfBounds
  Closed
  Unsupported
  IdExhausted
}

///|
fn decode_native_status(code : Int) -> NativeBackendErrorCode {
  match code {
    0 => NativeBackendErrorCode::Ok
    1 => NativeBackendErrorCode::Eof
    2 => NativeBackendErrorCode::OpenFailed
    3 => NativeBackendErrorCode::ReadFailed
    4 => NativeBackendErrorCode::WriteFailed
    5 => NativeBackendErrorCode::FlushFailed
    6 => NativeBackendErrorCode::CloseFailed
    7 => NativeBackendErrorCode::InvalidHandle
    8 => NativeBackendErrorCode::InvalidInput
    9 => NativeBackendErrorCode::MmapFailed
    10 => NativeBackendErrorCode::MunmapFailed
    11 => NativeBackendErrorCode::OutOfBounds
    12 => NativeBackendErrorCode::Closed
    13 => NativeBackendErrorCode::Unsupported
    14 => NativeBackendErrorCode::IdExhausted
    _ => NativeBackendErrorCode::InvalidHandle
  }
}

///|
fn native_backend_status_message(code : Int) -> String {
  match decode_native_status(code) {
    NativeBackendErrorCode::Ok =>
      "native backend operation completed successfully"
    NativeBackendErrorCode::Eof => "native backend reached end of file"
    NativeBackendErrorCode::OpenFailed =>
      "native backend failed to open file handle"
    NativeBackendErrorCode::ReadFailed =>
      "native backend failed to read from file handle"
    NativeBackendErrorCode::WriteFailed =>
      "native backend failed to write to file handle"
    NativeBackendErrorCode::FlushFailed =>
      "native backend failed to flush file handle"
    NativeBackendErrorCode::CloseFailed =>
      "native backend failed to close file handle"
    NativeBackendErrorCode::InvalidHandle =>
      "native backend received an invalid file handle"
    NativeBackendErrorCode::InvalidInput =>
      "native backend received invalid input"
    NativeBackendErrorCode::MmapFailed =>
      "native backend failed to create or inspect mmap view"
    NativeBackendErrorCode::MunmapFailed =>
      "native backend failed to release mmap view"
    NativeBackendErrorCode::OutOfBounds =>
      "native backend mmap access was out of bounds"
    NativeBackendErrorCode::Closed =>
      "native backend resource is already closed"
    NativeBackendErrorCode::Unsupported =>
      "native backend feature is not supported on this platform"
    NativeBackendErrorCode::IdExhausted =>
      "native backend exhausted monotonic native resource identifiers"
  }
}

///|
fn native_utf8_path_bytes(path : String) -> Bytes {
  @utf8.encode(path)
}

///|
pub fn native_backend_version() -> Int {
  native_backend_version_ffi()
}

///|
extern "C" fn native_backend_version_ffi() -> Int = "bufferutils_native_version"

///|
extern "C" fn native_last_status_ffi() -> Int = "bufferutils_native_last_status"

///|
#borrow(path)
extern "C" fn native_open_source_ffi(path : Bytes, path_len : Int) -> Int = "bufferutils_native_open_source"

///|
#borrow(path)
extern "C" fn native_open_sink_ffi(
  path : Bytes,
  path_len : Int,
  mode : Int,
) -> Int = "bufferutils_native_open_sink"

///|
extern "C" fn native_read_chunk_ffi(handle_id : Int, size : Int) -> Bytes = "bufferutils_native_read_chunk"

///|
#borrow(data)
extern "C" fn native_write_chunk_ffi(
  handle_id : Int,
  data : Bytes,
  data_len : Int,
) -> Int = "bufferutils_native_write_chunk"

///|
extern "C" fn native_flush_ffi(handle_id : Int) -> Int = "bufferutils_native_flush"

///|
extern "C" fn native_close_ffi(handle_id : Int) -> Int = "bufferutils_native_close"

///|
#borrow(path)
extern "C" fn native_open_mmap_view_ffi(path : Bytes, path_len : Int) -> Int = "bufferutils_native_open_mmap_view"

///|
extern "C" fn native_mmap_len_ffi(handle_id : Int) -> Int = "bufferutils_native_mmap_len"

///|
extern "C" fn native_mmap_owner_ref_count_ffi(handle_id : Int) -> Int = "bufferutils_native_mmap_owner_ref_count"

///|
extern "C" fn native_mmap_slice_handle_ffi(
  handle_id : Int,
  start : Int,
  len : Int,
) -> Int = "bufferutils_native_mmap_slice_handle"

///|
extern "C" fn native_mmap_read_byte_at_ffi(handle_id : Int, index : Int) -> Int = "bufferutils_native_mmap_read_byte_at"

///|
extern "C" fn native_mmap_copy_range_ffi(
  handle_id : Int,
  start : Int,
  len : Int,
) -> Bytes = "bufferutils_native_mmap_copy_range"

///|
extern "C" fn native_mmap_find_byte_ffi(
  handle_id : Int,
  byte_value : Int,
) -> Int = "bufferutils_native_mmap_find_byte"

///|
extern "C" fn native_mmap_count_byte_ffi(
  handle_id : Int,
  byte_value : Int,
) -> Int = "bufferutils_native_mmap_count_byte"

///|
#borrow(data)
extern "C" fn native_mmap_index_of_ffi(
  handle_id : Int,
  data : Bytes,
  data_len : Int,
) -> Int = "bufferutils_native_mmap_index_of"

///|
#borrow(data)
extern "C" fn native_mmap_equals_ffi(
  handle_id : Int,
  data : Bytes,
  data_len : Int,
) -> Int = "bufferutils_native_mmap_equals"

///|
extern "C" fn native_mmap_crc32_ffi(handle_id : Int) -> Int = "bufferutils_native_mmap_crc32"

///|
extern "C" fn native_mmap_checksum_ffi(handle_id : Int) -> UInt64 = "bufferutils_native_mmap_checksum"

///|
#borrow(data)
extern "C" fn native_mmap_starts_with_ffi(
  handle_id : Int,
  data : Bytes,
  data_len : Int,
) -> Int = "bufferutils_native_mmap_starts_with"

///|
#borrow(path)
extern "C" fn native_mmap_copy_to_file_ffi(
  handle_id : Int,
  path : Bytes,
  path_len : Int,
) -> Int = "bufferutils_native_mmap_copy_to_file"

///|
extern "C" fn native_mmap_close_ffi(handle_id : Int) -> Int = "bufferutils_native_mmap_close"
