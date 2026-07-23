///|
/// The origin used by asynchronous seek operations.
pub(all) enum AsyncSeekFrom {
  Start(Int64)
  Current(Int64)
  End(Int64)
} derive(Eq, @debug.Debug)

///|
/// A cancellation-aware asynchronous byte reader.
pub(open) trait AsyncRead {
  async fn read(Self, FixedArray[Byte], offset? : Int, max_len? : Int) -> Int
  async fn read_exact(Self, FixedArray[Byte], offset? : Int, len? : Int) -> Unit = _
  async fn read_to_end(Self) -> Bytes = _
}

///|
impl AsyncRead with fn read_exact(
  self,
  destination,
  offset? = 0,
  len? = destination.length() - offset,
) {
  if offset < 0 || len < 0 || offset > destination.length() - len {
    raise @syncio.io_error(@syncio.InvalidInput, "async read_exact")
  }
  for progress = 0; progress < len; {
    let count = self.read(
      destination,
      offset=offset + progress,
      max_len=len - progress,
    )
    if count == 0 {
      raise @syncio.io_error(
        @syncio.UnexpectedEof,
        "async read_exact",
        progress~,
      )
    }
    if count < 0 || count > len - progress {
      raise @syncio.io_error(
        @syncio.ContractViolation,
        "async read_exact",
        progress~,
      )
    }
    continue progress + count
  }
}

///|
impl AsyncRead with fn read_to_end(self) {
  let output : Array[Byte] = []
  let scratch = FixedArray::make(8192, (0).to_byte())
  while true {
    let count = self.read(scratch)
    if count == 0 {
      break
    }
    if count < 0 || count > scratch.length() {
      raise @syncio.io_error(@syncio.ContractViolation, "async read_to_end")
    }
    for i in 0..<count {
      output.push(scratch[i])
    }
  }
  Bytes::from_array(output)
}

///|
/// A cancellation-aware asynchronous byte writer.
pub(open) trait AsyncWrite {
  async fn write(Self, Bytes, offset~ : Int, len~ : Int) -> Int
  async fn flush(Self) -> Unit
  async fn shutdown(Self) -> Unit = _
  async fn write_all(Self, Bytes, offset? : Int, len? : Int) -> Unit = _
}

///|
impl AsyncWrite with fn shutdown(self) {
  AsyncWrite::flush(self)
}

///|
impl AsyncWrite with fn write_all(
  self,
  source,
  offset? = 0,
  len? = source.length() - offset,
) {
  if offset < 0 || len < 0 || offset > source.length() - len {
    raise @syncio.io_error(@syncio.InvalidInput, "async write_all")
  }
  for progress = 0; progress < len; {
    let count = self.write(source, offset=offset + progress, len=len - progress)
    if count == 0 {
      raise @syncio.io_error(@syncio.WriteZero, "async write_all", progress~)
    }
    if count < 0 || count > len - progress {
      raise @syncio.io_error(
        @syncio.ContractViolation,
        "async write_all",
        progress~,
      )
    }
    continue progress + count
  }
}

///|
pub(open) trait AsyncBufRead: AsyncRead {
  /// The returned view borrows the reader's internal fixed buffer and is
  /// invalidated by the next reader operation.
  async fn fill_buf(Self) -> ArrayView[Byte]
  fn consume(Self, Int) -> Unit raise @syncio.IoError
  async fn read_until(Self, Byte) -> Bytes = _
}

///|
impl AsyncBufRead with fn read_until(self, delimiter) {
  let output : Array[Byte] = []
  while true {
    let chunk = self.fill_buf()
    if chunk.is_empty() {
      break
    }
    let mut consumed = chunk.length()
    for i in 0..<chunk.length() {
      output.push(chunk[i])
      if chunk[i] == delimiter {
        consumed = i + 1
        self.consume(consumed)
        return Bytes::from_array(output)
      }
    }
    self.consume(consumed)
  }
  Bytes::from_array(output)
}

///|
pub(open) trait AsyncSeek {
  async fn seek(Self, AsyncSeekFrom) -> Int64
  async fn stream_position(Self) -> Int64 = _
  async fn rewind(Self) -> Unit = _
}

///|
impl AsyncSeek with fn stream_position(self) {
  self.seek(Current(0L))
}

///|
impl AsyncSeek with fn rewind(self) {
  ignore(self.seek(Start(0L)))
}

///|
pub(open) trait AsyncClose {
  async fn close(Self) -> Unit
  fn is_closed(Self) -> Bool
}

///|
pub async fn[R : AsyncRead] read_to_end(reader : R) -> Bytes {
  AsyncRead::read_to_end(reader)
}

///|
pub async fn[W : AsyncWrite] write_all(writer : W, bytes : Bytes) -> Unit {
  AsyncWrite::write_all(writer, bytes)
}
