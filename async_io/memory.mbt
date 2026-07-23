///|
/// An in-memory asynchronous reader with seek support.
pub struct AsyncMemoryReader {
  data : Bytes
  mut position : Int
  mut closed : Bool
}

///|
pub fn AsyncMemoryReader::new(data : BytesView) -> AsyncMemoryReader {
  { data: data.to_owned(), position: 0, closed: false }
}

///|
pub impl AsyncRead for AsyncMemoryReader with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  if self.closed {
    raise @syncio.io_error(@syncio.Closed, "async memory read")
  }
  if offset < 0 || max_len < 0 || offset > destination.length() - max_len {
    raise @syncio.io_error(@syncio.InvalidInput, "async memory read")
  }
  let count = Int::min(max_len, self.data.length() - self.position)
  for i in 0..<count {
    destination[offset + i] = self.data[self.position + i]
  }
  self.position += count
  count
}

///|
pub impl AsyncSeek for AsyncMemoryReader with fn seek(self, from) {
  let target = match from {
    Start(offset) => offset
    Current(offset) => self.position.to_int64() + offset
    End(offset) => self.data.length().to_int64() + offset
  }
  if target < 0L || target > self.data.length().to_int64() {
    raise @syncio.io_error(@syncio.InvalidInput, "async memory seek")
  }
  self.position = target.to_int()
  target
}

///|
pub impl AsyncClose for AsyncMemoryReader with fn close(self) {
  self.closed = true
}

///|
pub impl AsyncClose for AsyncMemoryReader with fn is_closed(self) {
  self.closed
}

///|
/// An in-memory asynchronous sink useful for tests and adapters.
pub struct AsyncMemoryWriter {
  data : Array[Byte]
  mut closed : Bool
}

///|
pub fn AsyncMemoryWriter::new() -> AsyncMemoryWriter {
  { data: [], closed: false }
}

///|
pub fn AsyncMemoryWriter::bytes(self : AsyncMemoryWriter) -> Bytes {
  Bytes::from_array(self.data)
}

///|
pub impl AsyncWrite for AsyncMemoryWriter with fn write(
  self,
  source,
  offset~,
  len~,
) {
  if self.closed {
    raise @syncio.io_error(@syncio.Closed, "async memory write")
  }
  if offset < 0 || len < 0 || offset > source.length() - len {
    raise @syncio.io_error(@syncio.InvalidInput, "async memory write")
  }
  for i in 0..<len {
    self.data.push(source[offset + i])
  }
  len
}

///|
pub impl AsyncWrite for AsyncMemoryWriter with fn flush(_self) {
  ()
}

///|
pub impl AsyncClose for AsyncMemoryWriter with fn close(self) {
  self.closed = true
}

///|
pub impl AsyncClose for AsyncMemoryWriter with fn is_closed(self) {
  self.closed
}
