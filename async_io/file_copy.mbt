///|
/// Observable progress from an asynchronous streaming copy.
pub(all) struct CopyProgress {
  bytes : Int
  read_calls : Int
  write_calls : Int
} derive(Eq, @debug.Debug)

///|
/// Copy a file through a reusable fixed-size buffer.
///
/// This adapter is intentionally separate from the synchronous core and uses
/// `moonbitlang/async`'s production Reader, Writer, cancellation, and file
/// implementations. The progress callback runs only after a chunk has been
/// fully accepted by the destination, so its value remains valid if the task
/// is cancelled later.
pub async fn copy_file(
  source_path : StringView,
  destination_path : StringView,
  buffer_size? : Int = 8192,
  on_progress? : (CopyProgress) -> Unit,
) -> CopyProgress {
  if buffer_size <= 0 {
    raise @syncio.io_error(
      @syncio.InvalidInput,
      "copy_file",
      message="buffer_size must be positive",
    )
  }
  let source = @fs.open(source_path, mode=@fs.ReadOnly)
  defer source.close()
  let destination = @fs.open(
    destination_path,
    mode=@fs.WriteOnly,
    create_mode=@fs.CreateOrTruncate,
  )
  defer destination.close()
  let buffer = FixedArray::make(buffer_size, (0).to_byte())
  let mut progress : CopyProgress = { bytes: 0, read_calls: 0, write_calls: 0 }
  while true {
    let count = @runtime_io.Reader::read(source, buffer) catch {
      err => raise map_async_error("copy_file read", err)
    }
    progress = { ..progress, read_calls: progress.read_calls + 1 }
    if count == 0 {
      break
    }
    let bytes = buffer.unsafe_reinterpret_as_bytes()
    @async.protect_from_cancel(() => {
      @runtime_io.Writer::write(destination, bytes[0:count]) catch {
        err => raise map_async_error("copy_file write", err)
      }
      progress = {
        bytes: progress.bytes + count,
        read_calls: progress.read_calls,
        write_calls: progress.write_calls + 1,
      }
    })
    match on_progress {
      Some(callback) => callback(progress)
      None => ()
    }
  }
  progress
}

///|
/// Read a complete file using the async runtime's buffered reader.
pub async fn read_file(path : StringView) -> Bytes {
  let source = @fs.open(path, mode=@fs.ReadOnly)
  defer source.close()
  @runtime_io.Reader::read_all(source).binary() catch {
    err => raise map_async_error("read_file", err)
  }
}

///|
/// Write a complete immutable byte view through the async runtime.
pub async fn write_file(path : StringView, data : BytesView) -> Unit {
  let destination = @fs.open(
    path,
    mode=@fs.WriteOnly,
    create_mode=@fs.CreateOrTruncate,
  )
  defer destination.close()
  @runtime_io.Writer::write(destination, data) catch {
    err => raise map_async_error("write_file", err)
  }
}
