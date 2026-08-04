///|
/// Lazy UTF-8 lines over an asynchronous buffered reader.
pub struct AsyncLines[R] {
  reader : AsyncBufReader[R]
}

///|
pub fn[R] AsyncBufReader::lines(self : AsyncBufReader[R]) -> AsyncLines[R] {
  { reader: self }
}

///|
pub fn[R] AsyncLines::into_inner(self : AsyncLines[R]) -> AsyncBufReader[R] {
  self.reader
}

///|
pub async fn[R : AsyncRead] AsyncLines::next(self : AsyncLines[R]) -> String? {
  let raw = AsyncBufRead::read_until(self.reader, b'\n')
  if raw.is_empty() {
    return None
  }
  let mut end = raw.length()
  if raw[end - 1] == b'\n' {
    end -= 1
    if end > 0 && raw[end - 1] == b'\r' {
      end -= 1
    }
  }
  Some(
    @utf8.decode(raw[0:end]) catch {
      _ => raise @syncio.io_error(@syncio.InvalidData, "AsyncLines::next")
    },
  )
}

///|
/// Lazy delimiter-separated bytes over an asynchronous buffered reader.
pub struct AsyncSplit[R] {
  reader : AsyncBufReader[R]
  delimiter : Byte
}

///|
pub fn[R] AsyncBufReader::split(
  self : AsyncBufReader[R],
  delimiter : Byte,
) -> AsyncSplit[R] {
  { reader: self, delimiter }
}

///|
pub fn[R] AsyncSplit::into_inner(self : AsyncSplit[R]) -> AsyncBufReader[R] {
  self.reader
}

///|
pub async fn[R : AsyncRead] AsyncSplit::next(self : AsyncSplit[R]) -> Bytes? {
  let raw = AsyncBufRead::read_until(self.reader, self.delimiter)
  if raw.is_empty() {
    return None
  }
  if raw[raw.length() - 1] == self.delimiter {
    Some(raw[0:raw.length() - 1].to_owned())
  } else {
    Some(raw)
  }
}

///|
/// Read one asynchronous source to EOF and then continue with another.
pub struct AsyncChain[A, B] {
  first : A
  second : B
  mut first_done : Bool
}

///|
pub fn[A, B] AsyncChain::new(first : A, second : B) -> AsyncChain[A, B] {
  { first, second, first_done: false }
}

///|
pub impl[A : AsyncRead, B : AsyncRead] AsyncRead for AsyncChain[A, B] with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  if !self.first_done {
    let count = AsyncRead::read(self.first, destination, offset~, max_len~)
    if count != 0 {
      return count
    }
    self.first_done = true
  }
  AsyncRead::read(self.second, destination, offset~, max_len~)
}

///|
/// Limit an asynchronous reader to a fixed byte count.
pub struct AsyncTake[R] {
  inner : R
  mut remaining : Int64
}

///|
pub fn[R] AsyncTake::new(
  inner : R,
  limit : Int64,
) -> AsyncTake[R] raise @syncio.IoError {
  if limit < 0L {
    raise @syncio.io_error(@syncio.InvalidInput, "AsyncTake::new")
  }
  { inner, remaining: limit }
}

///|
pub fn[R] AsyncTake::remaining(self : AsyncTake[R]) -> Int64 {
  self.remaining
}

///|
pub impl[R : AsyncRead] AsyncRead for AsyncTake[R] with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  if offset < 0 || max_len < 0 || offset > destination.length() - max_len {
    raise @syncio.io_error(@syncio.InvalidInput, "AsyncTake::read")
  }
  if self.remaining == 0L || max_len == 0 {
    return 0
  }
  let limited = if self.remaining < max_len.to_int64() {
    self.remaining.to_int()
  } else {
    max_len
  }
  let count = AsyncRead::read(self.inner, destination, offset~, max_len=limited)
  if count < 0 || count > limited {
    raise @syncio.io_error(@syncio.ContractViolation, "AsyncTake::read")
  }
  self.remaining -= count.to_int64()
  count
}

///|
/// A stream composed of independently buffered asynchronous read/write halves.
pub struct AsyncBufStream[R, W] {
  reader : AsyncBufReader[R]
  writer : AsyncBufWriter[W]
}

///|
pub fn[R, W] AsyncBufStream::new(
  reader : R,
  writer : W,
  capacity? : Int = 8192,
) -> AsyncBufStream[R, W] raise @syncio.IoError {
  {
    reader: AsyncBufReader::new(reader, capacity~),
    writer: AsyncBufWriter::new(writer, capacity~),
  }
}

///|
pub fn[R, W] AsyncBufStream::into_parts(
  self : AsyncBufStream[R, W],
) -> (AsyncBufReader[R], AsyncBufWriter[W]) {
  (self.reader, self.writer)
}

///|
pub impl[R : AsyncRead, W] AsyncRead for AsyncBufStream[R, W] with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  AsyncRead::read(self.reader, destination, offset~, max_len~)
}

///|
pub impl[R : AsyncRead, W] AsyncBufRead for AsyncBufStream[R, W] with fn fill_buf(
  self,
) {
  AsyncBufRead::fill_buf(self.reader)
}

///|
pub impl[R : AsyncRead, W] AsyncBufRead for AsyncBufStream[R, W] with fn consume(
  self,
  amount,
) {
  AsyncBufRead::consume(self.reader, amount)
}

///|
pub impl[R : AsyncRead, W] AsyncBufRead for AsyncBufStream[R, W] with fn read_until(
  self,
  delimiter,
) {
  AsyncBufRead::read_until(self.reader, delimiter)
}

///|
pub impl[R, W : AsyncWrite] AsyncWrite for AsyncBufStream[R, W] with fn write(
  self,
  source,
  offset~,
  len~,
) {
  AsyncWrite::write(self.writer, source, offset~, len~)
}

///|
pub impl[R, W : AsyncWrite] AsyncWrite for AsyncBufStream[R, W] with fn flush(
  self,
) {
  AsyncWrite::flush(self.writer)
}

///|
pub impl[R, W : AsyncWrite] AsyncWrite for AsyncBufStream[R, W] with fn shutdown(
  self,
) {
  AsyncWrite::shutdown(self.writer)
}
