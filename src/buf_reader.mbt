///|
fn validate_stream_capacity(capacity : Int) -> Unit raise BufferError {
  if capacity <= 0 {
    raise BufferError::InvalidCapacity(
      "buffer capacity must be greater than zero",
    )
  }
}

///|
/// A buffered reader that refills from a source in batches.
pub struct BufReader {
  source : MemorySource
  buf : Array[Byte]
  mut pos : Int
  mut end : Int
  capacity : Int
  mut reached_eof : Bool
}

///|
/// Create a new buffered reader from a memory source.
pub fn new_buf_reader(
  source : MemorySource,
  capacity : Int,
) -> BufReader raise BufferError {
  validate_stream_capacity(capacity)
  let buf : Array[Byte] = Array::makei(capacity, fn(_i) { (0).to_byte() })
  let reader : BufReader = {
    source,
    buf,
    pos: 0,
    end: 0,
    capacity,
    reached_eof: false,
  }
  reader
}

///|
/// Create a buffered reader directly from a file snapshot.
pub fn new_file_buf_reader(
  path : String,
  capacity : Int,
) -> BufReader raise BufferError {
  let source = new_file_source(path)
  new_buf_reader(file_source_to_memory(source), capacity)
}

///|
fn validate_buffer_request(n : Int) -> Unit raise BufferError {
  if n < 0 {
    raise BufferError::InvalidInput("requested byte count must be non-negative")
  }
}

///|
fn append_view(dst : Array[Byte], src : ArrayView[Byte]) -> Unit {
  if src.length() == 0 {
    return
  }
  let start = dst.length()
  dst.resize(start + src.length(), (0).to_byte())
  src.blit_to(dst, dst_offset=start)
}

///|
/// Fill the internal buffer when it has been fully consumed.
pub fn BufReader::fill_buf(self : BufReader) -> Int {
  let buffered = self.buffered_len()
  if buffered > 0 {
    return buffered
  }
  if self.reached_eof {
    return 0
  }

  self.pos = 0
  self.end = 0
  let count = self.source.read(self.buf)
  self.end = count
  self.reached_eof = count == 0
  count
}

///|
/// Read a single byte from the buffered reader.
pub fn BufReader::read_byte(self : BufReader) -> Byte raise BufferError {
  if self.fill_buf() == 0 {
    raise BufferError::Underflow("not enough bytes remaining in buffer")
  }
  let byte = self.buf[self.pos]
  self.pos += 1
  byte
}

///|
/// Read exactly `n` bytes from the buffered reader.
pub fn BufReader::read_exact(
  self : BufReader,
  n : Int,
) -> Array[Byte] raise BufferError {
  validate_buffer_request(n)
  let result : Array[Byte] = Array::new(capacity=n)
  while result.length() < n {
    if self.buffered_len() == 0 && self.fill_buf() == 0 {
      raise BufferError::Underflow("not enough bytes remaining in buffer")
    }

    let needed = n - result.length()
    let available = self.buffered_len()
    let count = if available < needed { available } else { needed }
    append_view(result, self.buf[self.pos:self.pos + count])
    self.pos += count
  }
  result
}

///|
/// Read all remaining bytes until EOF.
pub fn BufReader::read_to_end(self : BufReader) -> Array[Byte] {
  let result : Array[Byte] = []
  result.reserve_capacity(self.buffered_len() + self.source.remaining())
  while true {
    if self.buffered_len() == 0 && self.fill_buf() == 0 {
      break
    }

    let available = self.buffered_len()
    append_view(result, self.buf[self.pos:self.pos + available])
    self.pos += available
  }
  result
}

///|
/// Consume `n` bytes that are already buffered.
pub fn BufReader::consume(self : BufReader, n : Int) -> Unit raise BufferError {
  validate_buffer_request(n)
  if n > self.buffered_len() {
    raise BufferError::Underflow("not enough bytes remaining in buffer")
  }
  self.pos += n
}

///|
/// Return the number of unread bytes currently buffered.
pub fn BufReader::buffered_len(self : BufReader) -> Int {
  let available = self.end - self.pos
  if available < 0 {
    0
  } else {
    available
  }
}

///|
/// Return the configured buffer capacity.
pub fn BufReader::capacity(self : BufReader) -> Int {
  self.capacity
}

///|
/// Return whether the reader has reached EOF and drained the internal buffer.
pub fn BufReader::is_eof(self : BufReader) -> Bool {
  self.buffered_len() == 0 && self.source.is_empty()
}
