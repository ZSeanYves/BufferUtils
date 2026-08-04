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
/// Return the bytes accepted by this writer as an owned value.
pub fn AsyncMemoryWriter::to_bytes(self : AsyncMemoryWriter) -> Bytes {
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

///|
/// One endpoint of a bounded in-memory full-duplex byte stream.
pub struct AsyncDuplexStream {
  incoming : @aqueue.Queue[Bytes]
  outgoing : @aqueue.Queue[Bytes]
  capacity : Int
  mut pending : Bytes
  mut pending_offset : Int
  mut read_closed : Bool
  mut write_closed : Bool
}

///|
/// Create connected in-memory duplex endpoints with bounded backpressure.
pub fn duplex(
  capacity? : Int = 8192,
) -> (AsyncDuplexStream, AsyncDuplexStream) raise @syncio.IoError {
  if capacity <= 0 {
    raise @syncio.io_error(@syncio.InvalidInput, "async duplex")
  }
  let left_to_right : @aqueue.Queue[Bytes] = @aqueue.Queue(
    kind=@aqueue.Blocking(1),
  )
  let right_to_left : @aqueue.Queue[Bytes] = @aqueue.Queue(
    kind=@aqueue.Blocking(1),
  )
  (
    {
      incoming: right_to_left,
      outgoing: left_to_right,
      capacity,
      pending: b"",
      pending_offset: 0,
      read_closed: false,
      write_closed: false,
    },
    {
      incoming: left_to_right,
      outgoing: right_to_left,
      capacity,
      pending: b"",
      pending_offset: 0,
      read_closed: false,
      write_closed: false,
    },
  )
}

///|
pub fn AsyncDuplexStream::capacity(self : AsyncDuplexStream) -> Int {
  self.capacity
}

///|
pub impl AsyncRead for AsyncDuplexStream with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  if offset < 0 || max_len < 0 || offset > destination.length() - max_len {
    raise @syncio.io_error(@syncio.InvalidInput, "async duplex read")
  }
  if max_len == 0 {
    return 0
  }
  while self.pending_offset == self.pending.length() {
    if self.read_closed {
      return 0
    }
    self.pending = self.incoming.get() catch {
      @aqueue.QueueAlreadyClosed => {
        self.read_closed = true
        return 0
      }
      error => raise error
    }
    self.pending_offset = 0
  }
  let count = Int::min(max_len, self.pending.length() - self.pending_offset)
  for i in 0..<count {
    destination[offset + i] = self.pending[self.pending_offset + i]
  }
  self.pending_offset += count
  count
}

///|
pub impl AsyncWrite for AsyncDuplexStream with fn write(
  self,
  source,
  offset~,
  len~,
) {
  if self.write_closed {
    raise @syncio.io_error(@syncio.Closed, "async duplex write")
  }
  if offset < 0 || len < 0 || offset > source.length() - len {
    raise @syncio.io_error(@syncio.InvalidInput, "async duplex write")
  }
  if len == 0 {
    return 0
  }
  let count = Int::min(len, self.capacity)
  self.outgoing.put(source[offset:offset + count].to_owned()) catch {
    @aqueue.QueueAlreadyClosed =>
      raise @syncio.io_error(@syncio.BrokenPipe, "async duplex write")
    error => raise error
  }
  count
}

///|
pub impl AsyncWrite for AsyncDuplexStream with fn flush(_self) {
  ()
}

///|
pub impl AsyncWrite for AsyncDuplexStream with fn shutdown(self) {
  if !self.write_closed {
    self.outgoing.close()
    self.write_closed = true
  }
}

///|
pub impl AsyncClose for AsyncDuplexStream with fn close(self) {
  if !self.write_closed {
    self.outgoing.close()
    self.write_closed = true
  }
  if !self.read_closed {
    self.incoming.close()
    self.read_closed = true
  }
}

///|
pub impl AsyncClose for AsyncDuplexStream with fn is_closed(self) {
  self.read_closed && self.write_closed
}
