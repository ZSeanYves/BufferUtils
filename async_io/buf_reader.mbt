///|
pub struct AsyncBufReader[R] {
  inner : R
  buffer : FixedArray[Byte]
  mut start : Int
  mut end : Int
}

///|
pub fn[R] AsyncBufReader::new(
  inner : R,
  capacity? : Int = 8192,
) -> AsyncBufReader[R] raise @syncio.IoError {
  if capacity <= 0 {
    raise @syncio.io_error(@syncio.InvalidInput, "AsyncBufReader::new")
  }
  { inner, buffer: FixedArray::make(capacity, (0).to_byte()), start: 0, end: 0 }
}

///|
pub fn[R] AsyncBufReader::buffered_len(self : AsyncBufReader[R]) -> Int {
  self.end - self.start
}

///|
pub fn[R] AsyncBufReader::get_ref(self : AsyncBufReader[R]) -> R {
  self.inner
}

///|
pub fn[R] AsyncBufReader::get_mut(self : AsyncBufReader[R]) -> R {
  self.inner
}

///|
pub fn[R] AsyncBufReader::into_parts(self : AsyncBufReader[R]) -> (R, Bytes) {
  (
    self.inner,
    Bytes::makei(self.buffered_len(), i => self.buffer[self.start + i]),
  )
}

///|
async fn[R : AsyncRead] AsyncBufReader::refill(self : AsyncBufReader[R]) -> Int {
  self.start = 0
  self.end = AsyncRead::read(self.inner, self.buffer)
  self.end
}

///|
pub impl[R : AsyncRead] AsyncRead for AsyncBufReader[R] with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  if offset < 0 || max_len < 0 || offset > destination.length() - max_len {
    raise @syncio.io_error(@syncio.InvalidInput, "async buffered read")
  }
  if self.buffered_len() == 0 && max_len >= self.buffer.length() {
    return AsyncRead::read(self.inner, destination, offset~, max_len~)
  }
  if self.buffered_len() == 0 && self.refill() == 0 {
    return 0
  }
  let count = Int::min(max_len, self.buffered_len())
  for i in 0..<count {
    destination[offset + i] = self.buffer[self.start + i]
  }
  self.start += count
  count
}

///|
pub impl[R : AsyncRead] AsyncBufRead for AsyncBufReader[R] with fn fill_buf(
  self,
) {
  if self.buffered_len() == 0 {
    ignore(self.refill())
  }
  Bytes::makei(self.buffered_len(), i => self.buffer[self.start + i])
}

///|
pub impl[R : AsyncRead] AsyncBufRead for AsyncBufReader[R] with fn consume(
  self,
  amount,
) {
  if amount < 0 || amount > self.buffered_len() {
    raise @syncio.io_error(
      @syncio.InvalidInput,
      "async buffered consume",
      message="amount exceeds the filled buffer",
    )
  }
  self.start += amount
}

///|
pub impl[R : AsyncSeek] AsyncSeek for AsyncBufReader[R] with fn seek(self, from) {
  let adjusted = match from {
    Current(offset) => Current(offset - self.buffered_len().to_int64())
    other => other
  }
  let position = AsyncSeek::seek(self.inner, adjusted)
  self.start = 0
  self.end = 0
  position
}

///|
pub impl[R : AsyncSeek] AsyncSeek for AsyncBufReader[R] with fn stream_position(
  self,
) {
  AsyncSeek::stream_position(self.inner) - self.buffered_len().to_int64()
}

///|
pub fn[R] AsyncBufReader::into_inner(self : AsyncBufReader[R]) -> R {
  self.inner
}
