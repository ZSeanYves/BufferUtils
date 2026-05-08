///|
fn validate_native_path(path : String) -> Unit raise @bufferutils.BufferError {
  if path == "" {
    @bufferutils.raise_buffer_invalid_input("file path must not be empty")
  }
}

///|
fn validate_native_chunk_size(
  size : Int,
) -> Unit raise @bufferutils.BufferError {
  if size < 0 {
    @bufferutils.raise_buffer_invalid_input(
      "requested byte count must be non-negative",
    )
  }
}

///|
fn raise_native_open_error(
  kind : String,
  code : Int,
) -> Unit raise @bufferutils.BufferError {
  match decode_native_status(code) {
    NativeBackendErrorCode::InvalidInput =>
      @bufferutils.raise_buffer_invalid_input(
        "\{kind}: \{native_backend_status_message(code)}",
      )
    _ =>
      @bufferutils.raise_buffer_io(
        "\{kind}: \{native_backend_status_message(code)}",
      )
  }
}

///|
fn raise_native_read_error(code : Int) -> Unit raise @bufferutils.BufferError {
  match decode_native_status(code) {
    NativeBackendErrorCode::InvalidInput =>
      @bufferutils.raise_buffer_invalid_input(
        "native file source read failed: \{native_backend_status_message(code)}",
      )
    _ =>
      @bufferutils.raise_buffer_io(
        "native file source read failed: \{native_backend_status_message(code)}",
      )
  }
}

///|
fn raise_native_write_error(code : Int) -> Unit raise @bufferutils.BufferError {
  match decode_native_status(code) {
    NativeBackendErrorCode::InvalidInput =>
      @bufferutils.raise_buffer_invalid_input(
        "native file sink write failed: \{native_backend_status_message(code)}",
      )
    _ =>
      @bufferutils.raise_buffer_io(
        "native file sink write failed: \{native_backend_status_message(code)}",
      )
  }
}

///|
fn raise_native_flush_error(code : Int) -> Unit raise @bufferutils.BufferError {
  match decode_native_status(code) {
    NativeBackendErrorCode::InvalidInput =>
      @bufferutils.raise_buffer_invalid_input(
        "native file sink flush failed: \{native_backend_status_message(code)}",
      )
    _ =>
      @bufferutils.raise_buffer_io(
        "native file sink flush failed: \{native_backend_status_message(code)}",
      )
  }
}

///|
fn raise_native_close_error(
  kind : String,
  code : Int,
) -> Unit raise @bufferutils.BufferError {
  match decode_native_status(code) {
    NativeBackendErrorCode::InvalidInput =>
      @bufferutils.raise_buffer_invalid_input(
        "\{kind} close failed: \{native_backend_status_message(code)}",
      )
    _ =>
      @bufferutils.raise_buffer_io(
        "\{kind} close failed: \{native_backend_status_message(code)}",
      )
  }
}

///|
/// Experimental native sink open modes for the C `FILE*` backend.
pub(all) enum NativeFileMode {
  Overwrite
  Append
}

///|
fn native_file_mode_to_int(mode : NativeFileMode) -> Int {
  match mode {
    NativeFileMode::Overwrite => 0
    NativeFileMode::Append => 1
  }
}

///|
/// Experimental native file-handle source. Unlike `FileSource`, this does not
/// snapshot the whole file into memory.
pub struct NativeFileSource {
  path : String
  mut handle_id : Int
  mut closed : Bool
}

///|
/// Experimental native file-handle sink. Unlike `FileSink`, this writes
/// directly to an underlying `FILE*` handle.
pub struct NativeFileSink {
  path : String
  mode : NativeFileMode
  mut handle_id : Int
  mut closed : Bool
}

///|
/// Open a native file-handle source for chunked sequential reads.
pub fn new_native_file_source(
  path : String,
) -> NativeFileSource raise @bufferutils.BufferError {
  validate_native_path(path)
  let path_bytes = native_utf8_path_bytes(path)
  let handle_id = native_open_source_ffi(path_bytes, path_bytes.length())
  if handle_id <= 0 {
    raise_native_open_error(
      "native file source open failed",
      native_last_status_ffi(),
    )
  }
  { path, handle_id, closed: false }
}

///|
/// Open a native file-handle sink for direct file writes.
pub fn new_native_file_sink(
  path : String,
  mode : NativeFileMode,
) -> NativeFileSink raise @bufferutils.BufferError {
  validate_native_path(path)
  let path_bytes = native_utf8_path_bytes(path)
  let handle_id = native_open_sink_ffi(
    path_bytes,
    path_bytes.length(),
    native_file_mode_to_int(mode),
  )
  if handle_id <= 0 {
    raise_native_open_error(
      "native file sink open failed",
      native_last_status_ffi(),
    )
  }
  { path, mode, handle_id, closed: false }
}

///|
fn ensure_native_source_open(
  source : NativeFileSource,
) -> Unit raise @bufferutils.BufferError {
  if source.closed {
    @bufferutils.raise_buffer_io("native file source is closed")
  }
}

///|
fn ensure_native_sink_open(
  sink : NativeFileSink,
) -> Unit raise @bufferutils.BufferError {
  if sink.closed {
    @bufferutils.raise_buffer_io("native file sink is closed")
  }
}

///|
/// Read up to `size` bytes from the native file handle.
pub fn NativeFileSource::read_chunk(
  self : NativeFileSource,
  size : Int,
) -> Array[Byte] raise @bufferutils.BufferError {
  validate_native_chunk_size(size)
  ensure_native_source_open(self)
  if size == 0 {
    return []
  }
  let bytes = native_read_chunk_ffi(self.handle_id, size)
  let status = native_last_status_ffi()
  match decode_native_status(status) {
    NativeBackendErrorCode::Ok => bytes.to_array()
    NativeBackendErrorCode::Eof => bytes.to_array()
    _ => {
      raise_native_read_error(status)
      []
    }
  }
}

///|
/// Close the native file source. Repeated close calls are safe.
pub fn NativeFileSource::close(
  self : NativeFileSource,
) -> Unit raise @bufferutils.BufferError {
  if self.closed {
    return
  }
  let status = native_close_ffi(self.handle_id)
  self.closed = true
  self.handle_id = 0
  if status != 0 {
    raise_native_close_error("native file source", status)
  }
}

///|
pub fn NativeFileSource::is_closed(self : NativeFileSource) -> Bool {
  self.closed
}

///|
/// Write all bytes directly to the native file handle.
pub fn NativeFileSink::write_all(
  self : NativeFileSink,
  data : Array[Byte],
) -> Unit raise @bufferutils.BufferError {
  ensure_native_sink_open(self)
  if data.length() == 0 {
    return
  }
  let bytes = @bufferutils.array_to_bytes(data)
  let status = native_write_chunk_ffi(self.handle_id, bytes, bytes.length())
  if status != 0 {
    raise_native_write_error(status)
  }
}

///|
/// Flush buffered stdio state into the target file.
pub fn NativeFileSink::flush(
  self : NativeFileSink,
) -> Unit raise @bufferutils.BufferError {
  ensure_native_sink_open(self)
  let status = native_flush_ffi(self.handle_id)
  if status != 0 {
    raise_native_flush_error(status)
  }
}

///|
/// Close the native file sink. Repeated close calls are safe.
pub fn NativeFileSink::close(
  self : NativeFileSink,
) -> Unit raise @bufferutils.BufferError {
  if self.closed {
    return
  }
  let flush_status = native_flush_ffi(self.handle_id)
  let close_status = native_close_ffi(self.handle_id)
  self.closed = true
  self.handle_id = 0
  if flush_status != 0 {
    raise_native_flush_error(flush_status)
  }
  if close_status != 0 {
    raise_native_close_error("native file sink", close_status)
  }
}

///|
pub fn NativeFileSink::is_closed(self : NativeFileSink) -> Bool {
  self.closed
}
