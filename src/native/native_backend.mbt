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
type NativeByteOwner

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
/// Experimental native external-object owner constructor for mmap-backed views.
#borrow(path)
extern "C" fn native_open_mmap_owner_ffi(
  path : Bytes,
  path_len : Int,
) -> NativeByteOwner = "bufferutils_native_open_mmap_owner"

///|
#borrow(owner)
extern "C" fn native_mmap_owner_len_ffi(owner : NativeByteOwner) -> Int = "bufferutils_native_mmap_owner_len"

///|
#borrow(owner)
extern "C" fn native_mmap_owner_ref_count_obj_ffi(
  owner : NativeByteOwner,
) -> Int = "bufferutils_native_mmap_owner_ref_count_obj"

///|
#borrow(owner)
extern "C" fn native_mmap_owner_acquire_view_ffi(
  owner : NativeByteOwner,
) -> Int = "bufferutils_native_mmap_owner_acquire_view"

///|
#borrow(owner)
extern "C" fn native_mmap_owner_release_view_ffi(
  owner : NativeByteOwner,
) -> Int = "bufferutils_native_mmap_owner_release_view"

///|
#borrow(owner)
extern "C" fn native_mmap_owner_read_byte_at_ffi(
  owner : NativeByteOwner,
  offset : Int,
  byte_len : Int,
  index : Int,
) -> Int = "bufferutils_native_mmap_owner_read_byte_at"

///|
#borrow(owner)
extern "C" fn native_mmap_owner_copy_range_ffi(
  owner : NativeByteOwner,
  offset : Int,
  byte_len : Int,
  start : Int,
  len : Int,
) -> Bytes = "bufferutils_native_mmap_owner_copy_range"

///|
#borrow(owner)
extern "C" fn native_mmap_owner_find_byte_ffi(
  owner : NativeByteOwner,
  offset : Int,
  byte_len : Int,
  byte_value : Int,
) -> Int = "bufferutils_native_mmap_owner_find_byte"

///|
#borrow(owner)
extern "C" fn native_mmap_owner_count_byte_ffi(
  owner : NativeByteOwner,
  offset : Int,
  byte_len : Int,
  byte_value : Int,
) -> Int = "bufferutils_native_mmap_owner_count_byte"

///|
#borrow(owner, data)
extern "C" fn native_mmap_owner_index_of_ffi(
  owner : NativeByteOwner,
  offset : Int,
  byte_len : Int,
  data : Bytes,
  data_len : Int,
) -> Int = "bufferutils_native_mmap_owner_index_of"

///|
/// Experimental external-object owner equality check for NativeByteView.
#borrow(owner, data)
extern "C" fn native_mmap_owner_equals_ffi(
  owner : NativeByteOwner,
  offset : Int,
  byte_len : Int,
  data : Bytes,
  data_len : Int,
) -> Int = "bufferutils_native_mmap_owner_equals"

///|
#borrow(owner)
extern "C" fn native_mmap_owner_crc32_ffi(
  owner : NativeByteOwner,
  offset : Int,
  byte_len : Int,
) -> Int = "bufferutils_native_mmap_owner_crc32"

///|
#borrow(owner)
extern "C" fn native_mmap_owner_checksum_ffi(
  owner : NativeByteOwner,
  offset : Int,
  byte_len : Int,
) -> UInt64 = "bufferutils_native_mmap_owner_checksum"

///|
#borrow(owner, data)
extern "C" fn native_mmap_owner_starts_with_ffi(
  owner : NativeByteOwner,
  offset : Int,
  byte_len : Int,
  data : Bytes,
  data_len : Int,
) -> Int = "bufferutils_native_mmap_owner_starts_with"

///|
/// Experimental external-object owner transfer path for NativeByteView.
#borrow(owner, path)
extern "C" fn native_mmap_owner_copy_to_file_ffi(
  owner : NativeByteOwner,
  offset : Int,
  byte_len : Int,
  path : Bytes,
  path_len : Int,
) -> Int = "bufferutils_native_mmap_owner_copy_to_file"
