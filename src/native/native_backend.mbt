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
