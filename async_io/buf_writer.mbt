///|
pub struct AsyncBufWriter[W] {
  inner : W
  buffer : FixedArray[Byte]
  mut start : Int
  mut end : Int
  capacity : Int
}

///|
pub fn[W] AsyncBufWriter::new(
  inner : W,
  capacity? : Int = 8192,
) -> AsyncBufWriter[W] raise @syncio.IoError {
  if capacity <= 0 {
    raise @syncio.io_error(@syncio.InvalidInput, "AsyncBufWriter::new")
  }
  {
    inner,
    buffer: FixedArray::make(capacity, (0).to_byte()),
    start: 0,
    end: 0,
    capacity,
  }
}

///|
pub fn[W] AsyncBufWriter::pending_len(self : AsyncBufWriter[W]) -> Int {
  self.end - self.start
}

///|
pub fn[W] AsyncBufWriter::get_ref(self : AsyncBufWriter[W]) -> W {
  self.inner
}

///|
pub fn[W] AsyncBufWriter::get_mut(self : AsyncBufWriter[W]) -> W {
  self.inner
}

///|
pub fn[W] AsyncBufWriter::into_parts(
  self : AsyncBufWriter[W],
) -> (W, @buffer.SharedBytes) {
  (
    self.inner,
    @buffer.SharedBytes::from_fixed_array(self.buffer, self.start, self.end),
  )
}

///|
async fn[W : AsyncWrite] AsyncBufWriter::flush_buffer(
  self : AsyncBufWriter[W],
) -> Unit {
  while self.pending_len() > 0 {
    @async.protect_from_cancel(() => {
      let pending = self.buffer.unsafe_reinterpret_as_bytes()
      let count = AsyncWrite::write(
        self.inner,
        pending,
        offset=self.start,
        len=self.pending_len(),
      )
      if count == 0 {
        raise @syncio.io_error(@syncio.WriteZero, "async buffered flush")
      }
      if count < 0 || count > self.pending_len() {
        raise @syncio.io_error(
          @syncio.ContractViolation,
          "async buffered flush",
        )
      }
      self.start += count
    })
  }
  self.start = 0
  self.end = 0
}

///|
pub impl[W : AsyncWrite] AsyncWrite for AsyncBufWriter[W] with fn write(
  self,
  source,
  offset~,
  len~,
) {
  if offset < 0 || len < 0 || offset > source.length() - len {
    raise @syncio.io_error(@syncio.InvalidInput, "async buffered write")
  }
  if self.pending_len() == 0 && len >= self.capacity {
    return AsyncWrite::write(self.inner, source, offset~, len~)
  }
  if self.end == self.capacity {
    self.flush_buffer()
  }
  let count = Int::min(len, self.capacity - self.end)
  for i in 0..<count {
    self.buffer[self.end + i] = source[offset + i]
  }
  self.end += count
  count
}

///|
pub impl[W : AsyncWrite] AsyncWrite for AsyncBufWriter[W] with fn flush(self) {
  self.flush_buffer()
  AsyncWrite::flush(self.inner)
}

///|
pub impl[W : AsyncWrite + AsyncSeek] AsyncSeek for AsyncBufWriter[W] with fn seek(
  self,
  from,
) {
  AsyncWrite::flush(self)
  AsyncSeek::seek(self.inner, from)
}

///|
pub impl[W : AsyncWrite + AsyncSeek] AsyncSeek for AsyncBufWriter[W] with fn stream_position(
  self,
) {
  AsyncWrite::flush(self)
  AsyncSeek::stream_position(self.inner)
}

///|
pub async fn[W : AsyncWrite] AsyncBufWriter::finish(
  self : AsyncBufWriter[W],
) -> W {
  AsyncWrite::flush(self)
  self.inner
}
