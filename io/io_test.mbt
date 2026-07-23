///|
fn[T, E : Error] capture_io_result(f : () -> T raise E) -> Result[T, E] {
  try f() |> Ok catch {
    error => Err(error)
  }
}

///|
struct FailingWriter {
  data : Array[Byte]
  mut remaining_before_error : Int
}

///|
impl Write for FailingWriter with fn write(self, src, offset, length) {
  if self.remaining_before_error == 0 {
    raise io_error(
      Backend,
      "write",
      context="injected",
      message="injected failure",
    )
  }
  let count = Int::min(length, self.remaining_before_error)
  for i in 0..<count {
    self.data.push(src[offset + i])
  }
  self.remaining_before_error -= count
  count
}

///|
impl Write for FailingWriter with fn flush(_self) {
  ()
}

///|
struct ProgressErrorWriter {
  data : Array[Byte]
  mut failed : Bool
}

///|
struct InterruptOnceReader {
  data : Bytes
  mut position : Int
  mut interrupted : Bool
}

///|
impl Read for InterruptOnceReader with fn read(self, dst, offset, length) {
  if !self.interrupted {
    self.interrupted = true
    raise io_error(Interrupted, "read", message="injected interrupt")
  }
  let count = Int::min(length, self.data.length() - self.position)
  for i in 0..<count {
    dst[offset + i] = self.data[self.position + i]
  }
  self.position += count
  count
}

///|
struct InterruptOnceWriter {
  data : Array[Byte]
  mut interrupted : Bool
}

///|
impl Write for InterruptOnceWriter with fn write(self, src, offset, length) {
  if !self.interrupted {
    self.interrupted = true
    raise io_error(Interrupted, "write", message="injected interrupt")
  }
  for i in 0..<length {
    self.data.push(src[offset + i])
  }
  length
}

///|
impl Write for InterruptOnceWriter with fn flush(_self) {
  ()
}

///|
impl Write for ProgressErrorWriter with fn write(self, src, offset, length) {
  if !self.failed && length > 0 {
    self.data.push(src[offset])
    self.failed = true
    raise io_error(
      Backend,
      "write",
      context="injected-progress",
      progress=1,
      message="failed after one byte",
    )
  }
  for i in 0..<length {
    self.data.push(src[offset + i])
  }
  length
}

///|
impl Write for ProgressErrorWriter with fn flush(_self) {
  ()
}

///|
enum InvalidRead {
  InvalidRead
}

///|
impl Read for InvalidRead with fn read(_self, _dst, _offset, _length) {
  -1
}

///|
enum InvalidWrite {
  InvalidWrite
  ZeroWrite
}

///|
impl Write for InvalidWrite with fn write(self, _src, _offset, _length) {
  match self {
    InvalidWrite => -1
    ZeroWrite => 0
  }
}

///|
impl Write for InvalidWrite with fn flush(_self) {
  ()
}

///|
enum ErrorRead {
  ErrorRead
}

///|
impl Read for ErrorRead with fn read(_self, _dst, _offset, _length) {
  raise io_error(Backend, "read", message="injected read error")
}

///|
test "Read::read_exact handles ordinary short reads" {
  let reader = MemoryReader::new(b"abcdef", max_chunk=2)
  let dst = Array::make(6, (0).to_byte())
  Read::read_exact(reader, dst.mut_view())
  inspect(Bytes::from_array(dst[:]), content="b\"abcdef\"")
  assert_eq(reader.read_calls(), 3)
}

///|
test "Read::read_fixed default path preserves offsets and validates ranges" {
  let reader = MemoryReader::new(b"abc")
  let destination = FixedArray::make(5, b'-')
  assert_eq(Read::read_fixed(reader, destination, 1, 3), 3)
  assert_eq(destination.unsafe_reinterpret_as_bytes(), b"-abc-")
  let invalid = capture_io_result(() => {
    Read::read_fixed(reader, destination, -1, 1)
  })
  match invalid {
    Err(error) => assert_eq(error.kind(), InvalidInput)
    Ok(_) => fail("expected InvalidInput")
  }
}

///|
test "Read::read_exact reports partial progress at EOF" {
  let reader = MemoryReader::new(b"abc", max_chunk=2)
  let dst = Array::make(5, (0).to_byte())
  let result = capture_io_result(() => Read::read_exact(reader, dst.mut_view()))
  match result {
    Err(error) => {
      assert_eq(error.kind(), UnexpectedEof)
      assert_eq(error.progress(), 3)
    }
    Ok(_) => fail("expected UnexpectedEof")
  }
}

///|
test "Write::write_all handles ordinary short writes" {
  let writer = MemoryWriter::new(max_chunk=2)
  Write::write_all(writer, [b'a', b'b', b'c', b'd', b'e'][:])
  inspect(writer.to_bytes(), content="b\"abcde\"")
  assert_eq(writer.write_calls(), 3)
}

///|
test "exact read and write retry interrupted operations" {
  let reader : InterruptOnceReader = {
    data: b"retry",
    position: 0,
    interrupted: false,
  }
  let destination = Array::make(5, (0).to_byte())
  Read::read_exact(reader, destination.mut_view())
  inspect(Bytes::from_array(destination[:]), content="b\"retry\"")
  let writer : InterruptOnceWriter = { data: [], interrupted: false }
  Write::write_all(writer, destination[:])
  inspect(Bytes::from_array(writer.data[:]), content="b\"retry\"")
}

///|
test "vectored helpers preserve ordering across short backends" {
  let reader = MemoryReader::new(b"abcdef", max_chunk=2)
  let first = Array::make(2, (0).to_byte())
  let second = Array::make(4, (0).to_byte())
  let destinations = [first.mut_view(), second.mut_view()]
  read_exact_vectored(reader, destinations[:])
  assert_eq(first, [b'a', b'b'])
  assert_eq(second, [b'c', b'd', b'e', b'f'])

  let writer = MemoryWriter::new(max_chunk=1)
  let sources = [[b'a', b'b'][:], [b'c', b'd', b'e', b'f'][:]]
  write_all_vectored(writer, sources[:])
  inspect(writer.to_bytes(), content="b\"abcdef\"")
}

///|
test "BufReader fill_buf and consume support allocation-free parsing" {
  let source = MemoryReader::new(b"alpha,beta", max_chunk=3)
  let reader = BufReader::new(source, capacity=4)
  assert_eq(BufRead::fill_buf(reader).to_owned(), [b'a', b'l', b'p'])
  BufRead::consume(reader, 2)
  assert_eq(BufRead::fill_buf(reader).to_owned(), [b'p'])
  let output : Array[Byte] = []
  ignore(BufRead::read_until(reader, b',', output))
  inspect(Bytes::from_array(output[:]), content="b\"pha,\"")
}

///|
test "BufReader bypasses an empty internal buffer for large reads" {
  let source = MemoryReader::new(b"abcdefgh")
  let reader = BufReader::new(source, capacity=4)
  let dst = Array::make(8, (0).to_byte())
  assert_eq(Read::read_array(reader, dst.mut_view()), 8)
  assert_eq(reader.bypass_read_calls(), 1)
  assert_eq(reader.underlying_read_calls(), 1)
  inspect(Bytes::from_array(dst[:]), content="b\"abcdefgh\"")
}

///|
test "BufWriter coalesces small writes and bypasses large writes" {
  let sink = MemoryWriter::new()
  let writer = BufWriter::new(sink, capacity=4)
  assert_eq(Write::write_array(writer, [b'a', b'b'][:]), 2)
  assert_eq(writer.buffered_len(), 2)
  Write::flush(writer)
  assert_eq(sink.write_calls(), 1)
  assert_eq(Write::write_array(writer, [b'c', b'd', b'e', b'f'][:]), 4)
  assert_eq(writer.bypass_write_calls(), 1)
  inspect(sink.to_bytes(), content="b\"abcdef\"")
}

///|
test "BufWriter preserves unwritten tail after a later short-write error" {
  let sink : FailingWriter = { data: [], remaining_before_error: 1 }
  let writer = BufWriter::new(sink, capacity=4)
  ignore(Write::write_array(writer, [b'a', b'b', b'c'][:]))
  let result = capture_io_result(() => Write::flush(writer))
  match result {
    Err(error) => assert_eq(error.progress(), 1)
    Ok(_) => fail("expected injected write failure")
  }
  let (inner, pending) = writer.into_parts()
  inspect(Bytes::from_array(inner.data[:]), content="b\"a\"")
  inspect(pending.to_bytes(), content="b\"bc\"")
}

///|
test "BufWriter finish returns a recoverable structured failure" {
  let sink : FailingWriter = { data: [], remaining_before_error: 0 }
  let writer = BufWriter::new(sink, capacity=4)
  ignore(Write::write_array(writer, [b'x'][:]))
  let result = writer.finish()
  match result {
    Err(failure) => {
      assert_eq(failure.error().kind(), Backend)
      let recovered = failure.into_inner()
      assert_eq(recovered.buffered_len(), 1)
    }
    Ok(_) => fail("expected recoverable finish failure")
  }
}

///|
test "BufWriter rejects backend progress attached to an error" {
  let sink : ProgressErrorWriter = { data: [], failed: false }
  let writer = BufWriter::new(sink, capacity=4)
  ignore(Write::write_array(writer, [b'a', b'b', b'c'][:]))
  let result = capture_io_result(() => Write::flush(writer))
  match result {
    Err(error) => assert_eq(error.kind(), ContractViolation)
    Ok(_) => fail("expected injected progress failure")
  }
  let (inner, pending) = writer.into_parts()
  inspect(Bytes::from_array(inner.data[:]), content="b\"a\"")
  inspect(pending.to_bytes(), content="b\"abc\"")
}

///|
test "read_to_end appends to existing caller storage" {
  let reader = MemoryReader::new(b"payload", max_chunk=2)
  let output = [b'>']
  assert_eq(read_to_end(reader, output), 7)
  inspect(Bytes::from_array(output[:]), content="b\">payload\"")
}

///|
test "structured errors retain portable and platform context" {
  let error = io_error(
    PermissionDenied,
    "open",
    context="fixture",
    path="/denied",
    raw_code=13,
    message="permission denied",
  )
  assert_eq(error.kind(), PermissionDenied)
  assert_eq(error.operation(), "open")
  assert_eq(error.context(), "fixture")
  assert_eq(error.path(), "/denied")
  assert_eq(error.raw_code(), 13)
  assert_eq(error.message(), "permission denied")
}

///|
test "read_to_string and read_line validate UTF-8" {
  let reader = MemoryReader::new(b"MoonBit 月", max_chunk=2)
  inspect(read_to_string(reader), content="MoonBit 月")
  let buffered = BufReader::new(
    MemoryReader::new(b"alpha\nbeta", max_chunk=2),
    capacity=3,
  )
  let line = StringBuilder()
  assert_eq(BufRead::read_line(buffered, line), 6)
  inspect(line.to_string(), content="alpha\n")
  let invalid = MemoryReader::new(b"\xFF")
  let result = capture_io_result(() => read_to_string(invalid))
  match result {
    Err(error) => assert_eq(error.kind(), InvalidData)
    Ok(_) => fail("expected invalid UTF-8")
  }
}

///|
test "Cursor implements read write and seek" {
  let cursor = Cursor::new([b'a', b'b', b'c'][:])
  assert_eq(Seek::seek(cursor, Start(1L)), 1L)
  Write::write_all(cursor, [b'Z'][:])
  assert_eq(Seek::stream_position(cursor), 2L)
  Seek::rewind(cursor)
  let output = Array::make(3, (0).to_byte())
  Read::read_exact(cursor, output.mut_view())
  inspect(Bytes::from_array(output[:]), content="b\"aZc\"")
}

///|
test "BufReader seeking accounts for unread prefetched bytes" {
  let cursor = Cursor::new([b'a', b'b', b'c', b'd', b'e'][:])
  let reader = BufReader::new(cursor, capacity=4)
  assert_eq(BufRead::fill_buf(reader), [b'a', b'b', b'c', b'd'])
  BufRead::consume(reader, 1)
  assert_eq(Seek::stream_position(reader), 1L)
  assert_eq(Seek::seek(reader, Current(1L)), 2L)
  let byte = Array::make(1, (0).to_byte())
  assert_eq(Read::read_array(reader, byte.mut_view()), 1)
  assert_eq(byte[0], b'c')
}

///|
test "BufWriter flushes before seek and finish" {
  let cursor = Cursor::new([][:])
  let writer = BufWriter::new(cursor, capacity=4)
  ignore(Write::write_array(writer, [b'a', b'b', b'c'][:]))
  assert_eq(Seek::seek(writer, Start(1L)), 1L)
  ignore(Write::write_array(writer, [b'Z'][:]))
  let inner = writer.finish().unwrap()
  inspect(inner.to_bytes(), content="b\"aZc\"")
}

///|
test "Take Chain Empty and Repeat compose through Read" {
  let chain = Chain::new(MemoryReader::new(b"ab"), MemoryReader::new(b"cd"))
  let limited = Take::new(chain, 3L)
  let output : Array[Byte] = []
  assert_eq(read_to_end(limited, output), 3)
  inspect(Bytes::from_array(output[:]), content="b\"abc\"")
  let empty = Empty::new()
  assert_eq(
    Read::read_array(empty, Array::make(1, (0).to_byte()).mut_view()),
    0,
  )
  let repeated = Repeat::new(b'x')
  let repeated_output = Array::make(4, (0).to_byte())
  assert_eq(Read::read_array(repeated, repeated_output.mut_view()), 4)
  inspect(Bytes::from_array(repeated_output[:]), content="b\"xxxx\"")
}

///|
test "LineWriter flushes complete lines and retains an incomplete tail" {
  let sink = MemoryWriter::new()
  let writer = LineWriter::new(sink)
  assert_eq(Write::write_array(writer, [b'a', b'\n', b'b'][:]), 3)
  inspect(sink.to_bytes(), content="b\"a\\x0a\"")
  let (inner, pending) = writer.into_parts()
  inspect(inner.to_bytes(), content="b\"a\\x0a\"")
  inspect(pending, content="b\"b\"")
}

///|
test "sync boundary branches cover buffered reads, EOF, and invalid contracts" {
  let reader = BufReader::new(MemoryReader::new(b"abcd"), capacity=4)
  assert_eq(BufRead::fill_buf(reader).to_owned(), [b'a', b'b', b'c', b'd'])
  let one = Array::make(1, (0).to_byte())
  assert_eq(Read::read_array(reader, one.mut_view()), 1)
  assert_eq(one[0], b'a')
  BufRead::consume(reader, 3)
  assert_eq(BufRead::fill_buf(reader), [])
  assert_eq(BufRead::fill_buf(reader), [])
  assert_eq(
    capture_io_result(() => BufRead::consume(reader, -1)) is Err(_),
    true,
  )
  assert_eq(
    capture_io_result(() => BufRead::consume(reader, 1)) is Err(_),
    true,
  )

  let seek_reader = BufReader::new(
    Cursor::new([b'a', b'b', b'c'][:]),
    capacity=2,
  )
  assert_eq(Seek::seek(seek_reader, Start(1L)), 1L)
  let (_, unread) = seek_reader.into_parts()
  assert_eq(unread, [])

  assert_eq(
    capture_io_result(() => MemoryReader::new(b"x", max_chunk=0)) is Err(_),
    true,
  )
  let writer = MemoryWriter::new()
  assert_eq(
    capture_io_result(() => MemoryWriter::new(max_chunk=0)) is Err(_),
    true,
  )
  assert_eq(writer.flush_calls(), 0)
  Write::flush(writer)
  assert_eq(writer.flush_calls(), 1)

  assert_eq(
    capture_io_result(() => {
      Read::read_exact(
        InvalidRead::InvalidRead,
        Array::make(1, (0).to_byte()).mut_view(),
      )
    })
    is Err(_),
    true,
  )
  assert_eq(
    capture_io_result(() => read_to_end(InvalidRead::InvalidRead, [])) is Err(_),
    true,
  )
  assert_eq(
    capture_io_result(() => {
      Write::write_all(InvalidWrite::InvalidWrite, [b'x'][:])
    })
    is Err(_),
    true,
  )
  assert_eq(
    capture_io_result(() => Write::write_all(InvalidWrite::ZeroWrite, [b'x'][:]))
    is Err(_),
    true,
  )
  assert_eq(
    capture_io_result(() => read_to_end(ErrorRead::ErrorRead, [])) is Err(_),
    true,
  )
}

///|
test "LineWriter propagates and retains pending errors" {
  let failing : FailingWriter = { data: [], remaining_before_error: 0 }
  let writer = LineWriter::new(failing)
  ignore(Write::write_array(writer, [b'a', b'\n'][:]))
  assert_eq(
    capture_io_result(() => Write::write_array(writer, [b'b'][:])) is Err(_),
    true,
  )
  assert_eq(capture_io_result(() => Write::flush(writer)) is Err(_), true)

  let sink = MemoryWriter::new()
  let writer = LineWriter::new(sink)
  ignore(Write::write_array(writer, [b'x', b'\n'][:]))
  Write::flush(writer)
  assert_eq(sink.to_bytes(), b"x\n")
  ignore(Write::write_array(writer, [][:]))
}

///|
test "BufWriter handles zero writes and flushes before refilling" {
  let zero = BufWriter::new(InvalidWrite::ZeroWrite, capacity=2)
  ignore(Write::write_array(zero, [b'x'][:]))
  assert_eq(capture_io_result(() => Write::flush(zero)) is Err(_), true)

  let sink = MemoryWriter::new(max_chunk=1)
  let writer = BufWriter::new(sink, capacity=3)
  ignore(Write::write_array(writer, [b'a', b'b'][:]))
  Write::write_all(writer, [b'c', b'd', b'e', b'f'][:])
  Write::flush(writer)
  assert_eq(writer.get_ref().to_bytes(), b"abcdef")
}

///|
test "read_line reports invalid UTF-8 and vectored errors keep progress" {
  let buffered = BufReader::new(
    MemoryReader::new(Bytes::from_array([0xFF, b'\n'])),
    capacity=2,
  )
  let line = StringBuilder()
  assert_eq(
    capture_io_result(() => BufRead::read_line(buffered, line)) is Err(_),
    true,
  )
  let reader = ErrorRead::ErrorRead
  let first = Array::make(1, (0).to_byte())
  assert_eq(
    capture_io_result(() => read_exact_vectored(reader, [first.mut_view()][:]))
    is Err(_),
    true,
  )
  let writer = FailingWriter::{ data: [], remaining_before_error: 0 }
  let source : Array[ArrayView[Byte]] = [[b'x'][:]]
  assert_eq(
    capture_io_result(() => write_all_vectored(writer, source[:])) is Err(_),
    true,
  )
}

///|
test "Cursor, Empty, and Take expose bounds and ownership helpers" {
  let cursor = Cursor::new([b'a', b'b'][:])
  assert_eq(cursor.len(), 2)
  assert_eq(cursor.position(), 0L)
  assert_eq(BufRead::fill_buf(cursor), [b'a', b'b'])
  BufRead::consume(cursor, 1)
  assert_eq(cursor.position(), 1L)
  assert_eq(
    capture_io_result(() => BufRead::consume(cursor, 2)) is Err(_),
    true,
  )
  assert_eq(
    capture_io_result(() => Seek::seek(cursor, End(-3L))) is Err(_),
    true,
  )
  Write::write_all(cursor, [b'X', b'Y'][:])
  assert_eq(cursor.to_bytes(), b"aXY")
  assert_eq(
    capture_io_result(() => Seek::seek(cursor, Start(-1L))) is Err(_),
    true,
  )

  let empty = Empty::new()
  assert_eq(BufRead::fill_buf(empty), [])
  assert_eq(capture_io_result(() => BufRead::consume(empty, 1)) is Err(_), true)

  let limited = Take::new(MemoryReader::new(b"abcd"), 2L)
  assert_eq(limited.remaining(), 2L)
  let dst = Array::make(1, (0).to_byte())
  assert_eq(Read::read_array(limited, dst.mut_view()), 1)
  let inner = limited.into_inner()
  ignore(inner)
  assert_eq(
    capture_io_result(() => Take::new(MemoryReader::new(b"x"), -1L)) is Err(_),
    true,
  )
}

///|
test "BufReader and BufWriter validate construction and expose parts" {
  let source = MemoryReader::new(b"x")
  assert_eq(
    capture_io_result(() => BufReader::new(source, capacity=0)) is Err(_),
    true,
  )
  let reader = BufReader::new(MemoryReader::new(b"x"), capacity=2)
  let empty_dst = Array::make(0, (0).to_byte())
  assert_eq(Read::read_array(reader, empty_dst.mut_view()), 0)
  assert_eq(BufReader::get_ref(reader).remaining(), 1)
  assert_eq(BufReader::get_mut(reader).remaining(), 1)
  let one = Array::make(1, (0).to_byte())
  Read::read_exact(reader, one.mut_view())
  assert_eq(BufRead::fill_buf(reader), [])
  assert_eq(BufReader::into_inner(reader).remaining(), 0)

  let sink = MemoryWriter::new()
  assert_eq(
    capture_io_result(() => BufWriter::new(sink, capacity=0)) is Err(_),
    true,
  )
  let writer = BufWriter::new(MemoryWriter::new(), capacity=2)
  assert_eq(writer.capacity(), 2)
  assert_eq(writer.underlying_write_calls(), 0)
  assert_eq(writer.get_ref().write_calls(), 0)
  assert_eq(writer.get_mut().write_calls(), 0)
  assert_eq(Write::write_array(writer, [][:]), 0)
  let seek_writer = BufWriter::new(Cursor::new([][:]), capacity=2)
  ignore(Write::write_array(seek_writer, [b'a', b'b'][:]))
  assert_eq(Seek::stream_position(seek_writer), 2L)
}

///|
test "default vectored and error helpers preserve contracts" {
  let reader = MemoryReader::new(b"abc")
  let first = FixedArray::make(0, (0).to_byte())
  let second = FixedArray::make(2, (0).to_byte())
  assert_eq(
    Read::read_vectored(
      reader,
      [IoSliceMut::new(first, 0, 0), IoSliceMut::new(second, 0, 2)][:],
    ),
    2,
  )
  assert_eq(Read::is_read_vectored(reader), false)
  let writer = MemoryWriter::new()
  let sources = [IoSlice::new(b"", 0, 0), IoSlice::new(b"a", 0, 1)]
  assert_eq(Write::write_vectored(writer, sources[:]), 1)
  assert_eq(Write::is_write_vectored(writer), false)
  assert_eq(error_is_interrupted(), true)
  let overflow = io_error(Backend, "test", progress=2147483647).add_progress(10)
  assert_eq(overflow.progress(), 2147483647)
}

///|
test "IoSlice validation and BufReader convenience APIs" {
  let reader = BufReader::new(MemoryReader::new(b"a\nb\n"), capacity=2)
  assert_eq(BufReader::peek(reader, 1).to_owned(), [b'a'])
  assert_eq(BufReader::skip_until(reader, b'\n'), 2)
  let lines = reader.lines()
  assert_eq(lines, ["b\n"])
  let invalid = capture_io_result(() => IoSlice::new(b"x", 2, 0))
  assert_eq(invalid is Err(_), true)
  let destination = FixedArray::make(1, (0).to_byte())
  let invalid_mut = capture_io_result(() => IoSliceMut::new(destination, 0, 2))
  assert_eq(invalid_mut is Err(_), true)
}

///|
test "memory pipe connects reader and writer endpoints" {
  let (reader, writer) = MemoryPipe::new()
  ignore(Write::write_array(writer, [b'p', b'i', b'n', b'g'][:]))
  let output = Array::make(4, (0).to_byte())
  Read::read_exact(reader, output.mut_view())
  assert_eq(output, [b'p', b'i', b'n', b'g'])
  Close::close(writer)
  assert_true(Close::is_closed(writer))
}

///|
test "BufStream and Sink compose independent buffered halves" {
  let stream = BufStream::new(
    MemoryReader::new(b"in"),
    MemoryWriter::new(),
    capacity=2,
  )
  let input = Array::make(2, (0).to_byte())
  Read::read_exact(stream, input.mut_view())
  assert_eq(input, [b'i', b'n'])
  ignore(Write::write_array(stream, [b'o', b'k'][:]))
  Write::flush(stream)

  let sink = BufWriter::new(MemoryWriter::new(), capacity=2)
  Sink::send(sink, b"sink", 0, 4)
  Sink::close(sink)
  assert_eq(sink.buffered_len(), 0)
}

///|
test "adapter primary ranges reject invalid input" {
  let cursor = Cursor::new([b'x'][:])
  let destination = FixedArray::make(1, (0).to_byte())
  assert_eq(
    capture_io_result(() => Read::read(cursor, destination, 2, 1)) is Err(_),
    true,
  )
  assert_eq(
    capture_io_result(() => Write::write(cursor, b"x", 2, 1)) is Err(_),
    true,
  )
  let repeated = Repeat::new(b'r')
  assert_eq(
    capture_io_result(() => Read::read(repeated, destination, -1, 1)) is Err(_),
    true,
  )
  let limited = Take::new(MemoryReader::new(b"x"), 1L)
  assert_eq(
    capture_io_result(() => Read::read(limited, destination, 2, 1)) is Err(_),
    true,
  )
  let line_writer = LineWriter::new(MemoryWriter::new())
  assert_eq(
    capture_io_result(() => Write::write(line_writer, b"x", 2, 1)) is Err(_),
    true,
  )
}

///|
test "BufReader buffer split and relative seek helpers" {
  let reader = BufReader::new(MemoryReader::new(b"a,b"), capacity=2)
  assert_eq(reader.peek(1).to_owned(), [b'a'])
  assert_eq(reader.buffer().to_owned(), [b'a', b','])
  assert_eq(reader.split(b','), [[b'a'], [b'b']])
  assert_true(
    try {
      ignore(reader.peek(-1))
      false
    } catch {
      _ => true
    },
  )

  let seekable = BufReader::new(Cursor::new([b'a', b'b', b'c'][:]), capacity=2)
  ignore(BufRead::fill_buf(seekable))
  seekable.seek_relative(1L)
  assert_eq(Seek::stream_position(seekable), 1L)
  let destination = FixedArray::make(1, (0).to_byte())
  assert_true(
    try {
      ignore(Read::read(seekable, destination, 2, 1))
      false
    } catch {
      _ => true
    },
  )
}

///|
fn error_is_interrupted() -> Bool {
  io_error(Interrupted, "test").is_interrupted()
}
