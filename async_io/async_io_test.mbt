///|
async test "async traits preserve exact memory and seek semantics" {
  let reader = AsyncMemoryReader::new(b"abcdef"[:])
  let prefix = FixedArray::make(3, (0).to_byte())
  AsyncRead::read_exact(reader, prefix)
  assert_eq(prefix.unsafe_reinterpret_as_bytes(), b"abc")
  assert_eq(AsyncSeek::seek(reader, Current(-1L)), 2L)
  assert_eq(read_to_end(reader), b"cdef")
  AsyncClose::close(reader)
  assert_eq(AsyncClose::is_closed(reader), true)

  let writer = AsyncMemoryWriter::new()
  write_all(writer, b"hello")
  assert_eq(writer.to_bytes(), b"hello")
}

///|
async test "typed async helpers cover signed unsigned and floating endianness" {
  let writer = AsyncMemoryWriter::new()
  AsyncWrite::write_u8(writer, b'\xFE')
  AsyncWrite::write_i8(writer, -1)
  AsyncWrite::write_u16_be(writer, 0x1234U.to_uint16())
  AsyncWrite::write_u16_le(writer, 0x5678U.to_uint16())
  AsyncWrite::write_i16_be(writer, Int16::from_int(-1234))
  AsyncWrite::write_i16_le(writer, Int16::from_int(-2345))
  AsyncWrite::write_u32_be(writer, 0x89ABCDEFU)
  AsyncWrite::write_u32_le(writer, 0x76543210U)
  AsyncWrite::write_i32_be(writer, -234567)
  AsyncWrite::write_i32_le(writer, -123456)
  AsyncWrite::write_f32_be(writer, 1.5)
  AsyncWrite::write_f32_le(writer, -1.25)
  AsyncWrite::write_u64_be(writer, 0x0123456789ABCDEFUL)
  AsyncWrite::write_u64_le(writer, 0xFEDCBA9876543210UL)
  AsyncWrite::write_i64_be(writer, -123456789L)
  AsyncWrite::write_i64_le(writer, -987654321L)
  AsyncWrite::write_f64_be(writer, -2.25)
  AsyncWrite::write_f64_le(writer, 3.5)
  let reader = AsyncMemoryReader::new(writer.to_bytes()[:])
  assert_eq(AsyncRead::read_u8(reader), b'\xFE')
  assert_eq(AsyncRead::read_i8(reader), -1)
  assert_eq(AsyncRead::read_u16_be(reader), 0x1234U.to_uint16())
  assert_eq(AsyncRead::read_u16_le(reader), 0x5678U.to_uint16())
  assert_eq(AsyncRead::read_i16_be(reader), Int16::from_int(-1234))
  assert_eq(AsyncRead::read_i16_le(reader), Int16::from_int(-2345))
  assert_eq(AsyncRead::read_u32_be(reader), 0x89ABCDEFU)
  assert_eq(AsyncRead::read_u32_le(reader), 0x76543210U)
  assert_eq(AsyncRead::read_i32_be(reader), -234567)
  assert_eq(AsyncRead::read_i32_le(reader), -123456)
  assert_eq(AsyncRead::read_f32_be(reader), 1.5)
  assert_eq(AsyncRead::read_f32_le(reader), -1.25)
  assert_eq(AsyncRead::read_u64_be(reader), 0x0123456789ABCDEFUL)
  assert_eq(AsyncRead::read_u64_le(reader), 0xFEDCBA9876543210UL)
  assert_eq(AsyncRead::read_i64_be(reader), -123456789L)
  assert_eq(AsyncRead::read_i64_le(reader), -987654321L)
  assert_eq(AsyncRead::read_f64_be(reader), -2.25)
  assert_eq(AsyncRead::read_f64_le(reader), 3.5)
}

///|
async test "async cursors chain take and buffered stream remain lazy" {
  try {
    let lines = AsyncBufReader::new(
      AsyncMemoryReader::new(b"one\r\ntwo\n"[:]),
      capacity=3,
    ).lines()
    assert_eq(lines.next(), Some("one"))
    assert_eq(lines.next(), Some("two"))
    assert_eq(lines.next(), None)

    let split = AsyncBufReader::new(
      AsyncMemoryReader::new(b"a,b"[:]),
      capacity=2,
    ).split(b',')
    assert_eq(split.next(), Some(b"a"))
    assert_eq(split.next(), Some(b"b"))
    assert_eq(split.next(), None)

    let chain = AsyncChain::new(
      AsyncMemoryReader::new(b"ab"[:]),
      AsyncMemoryReader::new(b"cd"[:]),
    )
    let take = AsyncTake::new(chain, 3L)
    assert_eq(AsyncRead::read_to_end(take), b"abc")
    assert_eq(take.remaining(), 0L)

    let direct = AsyncBufReader::new(
      AsyncMemoryReader::new(b"in"[:]),
      capacity=2,
    )
    assert_eq(AsyncBufRead::fill_buf(direct).to_owned(), [b'i', b'n'])
    assert_eq(direct.buffered_len(), 2)
    let direct_input = FixedArray::make(2, (0).to_byte())
    assert_eq(AsyncRead::read(direct, direct_input, offset=0, max_len=2), 2)
    assert_eq(
      AsyncRead::read(direct, FixedArray::make(0, b'-'), offset=0, max_len=0),
      0,
    )

    let stream = AsyncBufStream::new(
      AsyncMemoryReader::new(b"in"[:]),
      AsyncMemoryWriter::new(),
      capacity=2,
    )
    assert_true(AsyncBufRead::has_data_left(stream))
    assert_eq(AsyncBufRead::fill_buf(stream).to_owned(), [b'i', b'n'])
    let (observed_reader, _) = stream.into_parts()
    assert_eq(observed_reader.buffered_len(), 2)
    AsyncBufRead::consume(stream, 0)
    let (after_consume, _) = stream.into_parts()
    assert_eq(after_consume.buffered_len(), 2)
    let input = FixedArray::make(2, (0).to_byte())
    assert_eq(AsyncRead::read(stream, input), 2)
    assert_eq(input.unsafe_reinterpret_as_bytes(), b"in")
    AsyncWrite::write_all(stream, b"out")
    AsyncWrite::flush(stream)
    AsyncWrite::shutdown(stream)
    let (_, writer) = stream.into_parts()
    assert_eq(writer.get_ref().to_bytes(), b"out")
  } catch {
    @syncio.IoError::Io(failure) =>
      fail("\{failure.operation}: \{failure.message}")
    error => raise error
  }
}

///|
struct OverReportingAsyncReader {}

///|
impl AsyncRead for OverReportingAsyncReader with fn read(
  _self,
  _destination,
  offset? = 0,
  max_len? = 0,
) {
  ignore(offset)
  max_len + 1
}

///|
async test "async cursor invalid and contract branches do not hide errors" {
  assert_eq(
    try {
      ignore(AsyncTake::new(AsyncMemoryReader::new(b""[:]), -1L))
      false
    } catch {
      _ => true
    },
    true,
  )
  let invalid_take = AsyncTake::new(AsyncMemoryReader::new(b"x"[:]), 1L)
  let destination = FixedArray::make(1, (0).to_byte())
  assert_eq(
    try {
      ignore(AsyncRead::read(invalid_take, destination, offset=2, max_len=1))
      false
    } catch {
      _ => true
    },
    true,
  )
  let over = AsyncTake::new(OverReportingAsyncReader::{  }, 1L)
  assert_eq(
    try {
      ignore(AsyncRead::read(over, destination))
      false
    } catch {
      error => async_error_has_kind(error, @syncio.ContractViolation)
    },
    true,
  )
  let invalid_line = AsyncBufReader::new(
    AsyncMemoryReader::new(b"\xFF\n"[:]),
    capacity=2,
  ).lines()
  assert_eq(
    try {
      ignore(invalid_line.next())
      false
    } catch {
      error => async_error_has_kind(error, @syncio.InvalidData)
    },
    true,
  )
  ignore(invalid_line.into_inner())
  let split = AsyncBufReader::new(AsyncMemoryReader::new(b"x"[:]), capacity=1).split(
    b',',
  )
  ignore(split.into_inner())
  assert_eq(
    try {
      ignore(
        copy_bidirectional_with_sizes(
          TestDuplex::{ incoming: b"", position: 0, outgoing: [] },
          TestDuplex::{ incoming: b"", position: 0, outgoing: [] },
          0,
          1,
        ),
      )
      false
    } catch {
      _ => true
    },
    true,
  )
}

///|
async test "bounded memory duplex waits transfers and drains before EOF" {
  let (left, right) = duplex(capacity=2)
  assert_eq(left.capacity(), 2)
  let zero = FixedArray::make(0, (0).to_byte())
  assert_eq(AsyncRead::read(right, zero), 0)
  assert_eq(AsyncWrite::write(left, b"", offset=0, len=0), 0)
  AsyncWrite::flush(left)
  @async.with_task_group(group => {
    let sender = group.spawn(() => {
      AsyncWrite::write_all(left, b"ping")
      AsyncWrite::shutdown(left)
    })
    assert_eq(AsyncRead::read_to_end(right), b"ping")
    sender.wait()
  })
  AsyncClose::close(left)
  AsyncClose::close(right)
  assert_true(AsyncClose::is_closed(left))
  assert_true(AsyncClose::is_closed(right))
}

///|
async test "duplex cancellation preserves pending-data and progress contracts" {
  assert_eq(
    try {
      ignore(duplex(capacity=0))
      false
    } catch {
      _ => true
    },
    true,
  )
  let (left, right) = duplex(capacity=1)
  assert_eq(
    try {
      ignore(AsyncWrite::write(left, b"x", offset=2, len=1))
      false
    } catch {
      error => async_error_has_kind(error, @syncio.InvalidInput)
    },
    true,
  )
  @async.with_task_group(group => {
    let waiting_read = group.spawn(() => {
      let byte = FixedArray::make(1, (0).to_byte())
      ignore(AsyncRead::read(right, byte))
    })
    @async.pause()
    waiting_read.cancel()
    assert_eq(
      try {
        waiting_read.wait()
        false
      } catch {
        error => @async.is_cancellation_error(error)
      },
      true,
    )
    assert_eq(AsyncWrite::write(left, b"a", offset=0, len=1), 1)
    let blocked_write = group.spawn(() => {
      ignore(AsyncWrite::write(left, b"b", offset=0, len=1))
    })
    @async.pause()
    blocked_write.cancel()
    assert_eq(
      try {
        blocked_write.wait()
        false
      } catch {
        error => @async.is_cancellation_error(error)
      },
      true,
    )
    let received = FixedArray::make(1, (0).to_byte())
    AsyncRead::read_exact(right, received)
    assert_eq(received.unsafe_reinterpret_as_bytes(), b"a")
  })
  AsyncClose::close(right)
  assert_eq(
    try {
      ignore(AsyncWrite::write(left, b"x", offset=0, len=1))
      false
    } catch {
      error => async_error_has_kind(error, @syncio.BrokenPipe)
    },
    true,
  )
  AsyncWrite::shutdown(left)
  assert_eq(
    try {
      ignore(AsyncWrite::write(left, b"x", offset=0, len=1))
      false
    } catch {
      error => async_error_has_kind(error, @syncio.Closed)
    },
    true,
  )
  let invalid = FixedArray::make(1, (0).to_byte())
  assert_eq(
    try {
      ignore(AsyncRead::read(left, invalid, offset=2, max_len=1))
      false
    } catch {
      error => async_error_has_kind(error, @syncio.InvalidInput)
    },
    true,
  )
  AsyncClose::close(left)
  assert_eq(AsyncRead::read(left, invalid), 0)
}

///|
fn async_error_has_kind(error : Error, expected : @syncio.IoErrorKind) -> Bool {
  match error {
    @syncio.IoError::Io(failure) => failure.kind == expected
    _ => false
  }
}

///|
async test "AsyncBufReader merges small reads and recovers unread bytes" {
  let inner = AsyncMemoryReader::new(b"one\ntwo"[:])
  let reader = AsyncBufReader::new(inner, capacity=4)
  assert_eq(AsyncBufRead::read_until(reader, b'\n'), b"one\n")
  let output = FixedArray::make(2, (0).to_byte())
  AsyncRead::read_exact(reader, output)
  assert_eq(output.unsafe_reinterpret_as_bytes(), b"tw")
  let (_, unread) = reader.into_parts()
  assert_eq(unread, b"o")
}

///|
async test "async buffered seek accounts for unread and pending bytes" {
  let reader = AsyncBufReader::new(
    AsyncMemoryReader::new(b"abcdef"[:]),
    capacity=4,
  )
  assert_eq(AsyncBufRead::fill_buf(reader).to_owned(), [b'a', b'b', b'c', b'd'])
  AsyncBufRead::consume(reader, 1)
  assert_eq(AsyncSeek::stream_position(reader), 1L)
  assert_eq(AsyncSeek::seek(reader, Current(1L)), 2L)
  assert_eq(AsyncSeek::seek(reader, Start(2L)), 2L)
  let byte = FixedArray::make(1, (0).to_byte())
  AsyncRead::read_exact(reader, byte)
  assert_eq(byte.unsafe_reinterpret_as_bytes(), b"c")
  ignore(AsyncBufReader::get_mut(reader))
  ignore(AsyncBufReader::into_inner(reader))

  ensure_async_test_dir()
  let path = async_test_dir + "/buffered-seek.bin"
  let writer = AsyncBufWriter::new(AsyncFile::create(path), capacity=2)
  ignore(AsyncWrite::write(writer, b"a", offset=0, len=1))
  ignore(AsyncWrite::write(writer, b"b", offset=0, len=1))
  ignore(AsyncBufWriter::get_mut(writer))
  assert_eq(AsyncSeek::seek(writer, Start(1L)), 1L)
  AsyncWrite::write_all(writer, b"Z")
  assert_eq(AsyncSeek::stream_position(writer), 2L)
  AsyncClose::close(AsyncBufWriter::get_ref(writer))
}

///|
struct PartialThenFailWriter {
  output : Array[Byte]
  mut calls : Int
}

///|
impl AsyncWrite for PartialThenFailWriter with fn write(
  self,
  source,
  offset~,
  len~,
) {
  self.calls += 1
  if self.calls > 1 {
    raise @syncio.io_error(@syncio.BrokenPipe, "partial async writer")
  }
  let count = Int::min(2, len)
  for i in 0..<count {
    self.output.push(source[offset + i])
  }
  count
}

///|
impl AsyncWrite for PartialThenFailWriter with fn flush(_self) {
  ()
}

///|
async test "AsyncBufWriter retains the uncommitted tail after flush failure" {
  let inner : PartialThenFailWriter = { output: [], calls: 0 }
  let writer = AsyncBufWriter::new(inner, capacity=8)
  AsyncWrite::write_all(writer, b"abcdef")
  let failed = try {
    AsyncWrite::flush(writer)
    false
  } catch {
    _ => true
  }
  assert_eq(failed, true)
  let (recovered, pending) = writer.into_parts()
  assert_eq(Bytes::from_array(recovered.output), b"ab")
  assert_eq(pending.to_bytes(), b"cdef")
}

///|
async test "AsyncFile uses an explicit seekable offset" {
  ensure_async_test_dir()
  let path = async_test_dir + "/seekable.bin"
  let file = AsyncFile::create(path)
  AsyncWrite::write_all(file, b"abcdef")
  assert_eq(AsyncSeek::seek(file, Start(2L)), 2L)
  assert_eq(AsyncSeek::seek(file, Current(1L)), 3L)
  assert_eq(AsyncSeek::seek(file, End(-1L)), 5L)
  assert_eq(
    try {
      ignore(AsyncSeek::seek(file, Start(-1L)))
      false
    } catch {
      _ => true
    },
    true,
  )
  assert_eq(AsyncSeek::seek(file, Start(2L)), 2L)
  AsyncWrite::write_all(file, b"ZZ")
  assert_eq(AsyncSeek::seek(file, Start(0L)), 0L)
  let output = FixedArray::make(6, (0).to_byte())
  AsyncRead::read_exact(file, output)
  assert_eq(output.unsafe_reinterpret_as_bytes(), b"abZZef")
  AsyncClose::close(file)
  assert_eq(AsyncClose::is_closed(file), true)
}

///|
async test "socket.Tcp adapter performs an async loopback roundtrip" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_task_group(group => {
    let server_task = group.spawn(() => {
      let (peer, _) = server.accept()
      defer peer.close()
      let request = FixedArray::make(4, (0).to_byte())
      AsyncRead::read_exact(peer, request)
      assert_eq(request.unsafe_reinterpret_as_bytes(), b"ping")
      AsyncWrite::write_all(peer, b"pong")
    })
    let client = @socket.Tcp::connect(server.addr)
    defer client.close()
    AsyncWrite::write_all(client, b"ping")
    AsyncWrite::flush(client)
    let response = FixedArray::make(4, (0).to_byte())
    AsyncRead::read_exact(client, response)
    assert_eq(response.unsafe_reinterpret_as_bytes(), b"pong")
    server_task.wait()
  })
}

///|
struct TestDuplex {
  incoming : Bytes
  mut position : Int
  outgoing : Array[Byte]
}

///|
impl AsyncRead for TestDuplex with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  let count = Int::min(max_len, self.incoming.length() - self.position)
  for i in 0..<count {
    destination[offset + i] = self.incoming[self.position + i]
  }
  self.position += count
  count
}

///|
impl AsyncWrite for TestDuplex with fn write(self, source, offset~, len~) {
  for i in 0..<len {
    self.outgoing.push(source[offset + i])
  }
  len
}

///|
impl AsyncWrite for TestDuplex with fn flush(_self) {
  ()
}

///|
struct ShutdownProbe {
  events : Array[String]
}

///|
impl AsyncWrite for ShutdownProbe with fn write(self, _source, offset~, len~) {
  ignore(offset)
  self.events.push("write")
  len
}

///|
impl AsyncWrite for ShutdownProbe with fn flush(self) {
  self.events.push("flush")
}

///|
impl AsyncWrite for ShutdownProbe with fn shutdown(self) {
  self.events.push("shutdown")
}

///|
struct ShutdownFailWriter {
  output : Array[Byte]
}

///|
impl AsyncWrite for ShutdownFailWriter with fn write(
  self,
  source,
  offset~,
  len~,
) {
  for i in 0..<len {
    self.output.push(source[offset + i])
  }
  len
}

///|
impl AsyncWrite for ShutdownFailWriter with fn flush(_self) {
  ()
}

///|
impl AsyncWrite for ShutdownFailWriter with fn shutdown(_self) {
  raise @syncio.io_error(@syncio.Backend, "injected async shutdown")
}

///|
async test "buffered shutdown flushes pending bytes before the inner shutdown" {
  let probe : ShutdownProbe = { events: [] }
  let writer = AsyncBufWriter::new(probe, capacity=8)
  ignore(AsyncWrite::write(writer, b"ok", offset=0, len=2))
  AsyncWrite::shutdown(writer)
  assert_eq(writer.get_ref().events, ["write", "shutdown"])
}

///|
async test "buffered shutdown preserves committed bytes and propagates failure" {
  let inner : ShutdownFailWriter = { output: [] }
  let writer = AsyncBufWriter::new(inner, capacity=8)
  ignore(AsyncWrite::write(writer, b"ok", offset=0, len=2))
  assert_eq(
    try {
      AsyncWrite::shutdown(writer)
      false
    } catch {
      error => async_error_has_kind(error, @syncio.Backend)
    },
    true,
  )
  assert_eq(Bytes::from_array(inner.output), b"ok")
}

///|
async test "copy and copy_bidirectional report committed bytes" {
  let source = AsyncMemoryReader::new(b"copy"[:])
  let destination = AsyncMemoryWriter::new()
  assert_eq(copy(source, destination, buffer_size=2), 4)
  assert_eq(destination.to_bytes(), b"copy")

  let left : TestDuplex = { incoming: b"left", position: 0, outgoing: [] }
  let right : TestDuplex = { incoming: b"right", position: 0, outgoing: [] }
  assert_eq(copy_bidirectional_with_sizes(left, right, 2, 3), (4, 5))
  assert_eq(Bytes::from_array(left.outgoing), b"right")
  assert_eq(Bytes::from_array(right.outgoing), b"left")

  let empty_left : TestDuplex = { incoming: b"", position: 0, outgoing: [] }
  let empty_right : TestDuplex = { incoming: b"", position: 0, outgoing: [] }
  assert_eq(copy_bidirectional(empty_left, empty_right), (0, 0))
}

///|
async test "AsyncTcp wrappers track close state" {
  let listener = AsyncTcpListener::bind("127.0.0.1:0")
  @async.with_task_group(group => {
    let server_task = group.spawn(() => {
      let peer = listener.accept()
      let byte = FixedArray::make(1, (0).to_byte())
      AsyncRead::read_exact(peer, byte)
      AsyncClose::close(peer)
      assert_eq(AsyncClose::is_closed(peer), true)
    })
    let client = AsyncTcpStream::connect("127.0.0.1", listener.local_port())
    AsyncWrite::write_all(client, b"x")
    AsyncClose::close(client)
    AsyncClose::close(client)
    assert_eq(AsyncClose::is_closed(client), true)
    let closed_dst = FixedArray::make(1, (0).to_byte())
    assert_eq(
      try {
        ignore(AsyncRead::read(client, closed_dst))
        false
      } catch {
        _ => true
      },
      true,
    )
    assert_eq(
      try {
        ignore(AsyncWrite::write(client, b"x", offset=0, len=1))
        false
      } catch {
        _ => true
      },
      true,
    )
    AsyncWrite::flush(client)
    server_task.wait()
  })
  AsyncClose::close(listener)
  assert_eq(AsyncClose::is_closed(listener), true)
}

///|
enum AlwaysZeroAsyncWriter {
  Zero
}

///|
impl AsyncWrite for AlwaysZeroAsyncWriter with fn write(
  _self,
  _source,
  offset~,
  len~,
) {
  ignore(offset)
  ignore(len)
  0
}

///|
impl AsyncWrite for AlwaysZeroAsyncWriter with fn flush(_self) {
  ()
}

///|
async test "async defaults reject invalid ranges and zero progress" {
  let reader = AsyncMemoryReader::new(b"x"[:])
  let dst = FixedArray::make(1, (0).to_byte())
  let invalid_read = try {
    AsyncRead::read_exact(reader, dst, offset=2, len=1)
    false
  } catch {
    _ => true
  }
  assert_eq(invalid_read, true)
  let eof = AsyncMemoryReader::new(b""[:])
  let eof_result = try {
    AsyncRead::read_exact(eof, dst)
    false
  } catch {
    _ => true
  }
  assert_eq(eof_result, true)
  let writer = AlwaysZeroAsyncWriter::Zero
  let zero_result = try {
    AsyncWrite::write_all(writer, b"x")
    false
  } catch {
    _ => true
  }
  assert_eq(zero_result, true)
  let invalid_write = try {
    AsyncWrite::write_all(AsyncMemoryWriter::new(), b"x", offset=2, len=1)
    false
  } catch {
    _ => true
  }
  assert_eq(invalid_write, true)
}

///|
async test "async memory and buffering error branches are exercised" {
  let memory = AsyncMemoryReader::new(b"abc"[:])
  let dst = FixedArray::make(3, (0).to_byte())
  assert_eq(AsyncSeek::seek(memory, Start(1L)), 1L)
  assert_eq(AsyncSeek::seek(memory, End(-1L)), 2L)
  assert_eq(AsyncSeek::stream_position(memory), 2L)
  AsyncSeek::rewind(memory)
  let bad_seek = try {
    ignore(AsyncSeek::seek(memory, Current(-1L)))
    false
  } catch {
    _ => true
  }
  assert_eq(bad_seek, true)
  AsyncClose::close(memory)
  assert_eq(AsyncClose::is_closed(memory), true)
  let closed_read = try {
    ignore(AsyncRead::read(memory, dst))
    false
  } catch {
    _ => true
  }
  assert_eq(closed_read, true)

  assert_eq(
    try {
      ignore(AsyncBufReader::new(AsyncMemoryReader::new(b"x"[:]), capacity=0))
      false
    } catch {
      _ => true
    },
    true,
  )
  let empty_reader = AsyncBufReader::new(
    AsyncMemoryReader::new(b""[:]),
    capacity=2,
  )
  assert_eq(AsyncRead::read(empty_reader, dst), 0)
  assert_eq(AsyncBufReader::get_ref(empty_reader).position, 0)
  let buffered = AsyncBufReader::new(
    AsyncMemoryReader::new(b"1234"[:]),
    capacity=2,
  )
  assert_eq(AsyncRead::read(buffered, dst, max_len=3), 3)

  assert_eq(
    try {
      ignore(AsyncBufWriter::new(AsyncMemoryWriter::new(), capacity=0))
      false
    } catch {
      _ => true
    },
    true,
  )
  let direct = AsyncBufWriter::new(AsyncMemoryWriter::new(), capacity=2)
  assert_eq(AsyncWrite::write(direct, b"large", offset=0, len=5), 5)
  AsyncWrite::flush(direct)
  let finished = AsyncBufWriter::finish(
    AsyncBufWriter::new(AsyncMemoryWriter::new(), capacity=2),
  )
  ignore(finished)
}

///|
async test "async file adapters support read-only open and direct runtime adapters" {
  ensure_async_test_dir()
  let path = async_test_dir + "/adapter.bin"
  write_file(path, b"adapter"[:])
  let file = AsyncFile::open_read(path)
  let data = FixedArray::make(7, (0).to_byte())
  AsyncRead::read_exact(file, data)
  assert_eq(data.unsafe_reinterpret_as_bytes(), b"adapter")
  AsyncClose::close(file)
  let closed_seek = try {
    ignore(AsyncSeek::stream_position(file))
    false
  } catch {
    _ => true
  }
  assert_eq(closed_seek, true)

  let runtime_file = @fs.open(path, mode=@fs.ReadOnly)
  let runtime_data = FixedArray::make(7, (0).to_byte())
  assert_eq(AsyncRead::read(runtime_file, runtime_data), 7)
  runtime_file.close()
  let runtime_writer = @fs.open(
    path,
    mode=@fs.WriteOnly,
    create_mode=@fs.CreateOrTruncate,
  )
  assert_eq(AsyncWrite::write(runtime_writer, b"ok", offset=0, len=2), 2)
  AsyncWrite::flush(runtime_writer)
  runtime_writer.close()
}

///|
enum InvalidAsyncReader {
  InvalidAsyncReader
}

///|
impl AsyncRead for InvalidAsyncReader with fn read(
  _self,
  _destination,
  offset? = 0,
  max_len? = 0,
) {
  ignore(offset)
  if max_len == 0 {
    -1
  } else {
    max_len + 1
  }
}

///|
enum InvalidAsyncWriter {
  InvalidAsyncWriter
}

///|
impl AsyncWrite for InvalidAsyncWriter with fn write(
  _self,
  _source,
  offset~,
  len~,
) {
  ignore(offset)
  if len == 0 {
    -1
  } else {
    len + 1
  }
}

///|
impl AsyncWrite for InvalidAsyncWriter with fn flush(_self) {
  ()
}

///|
async test "async contract and closed-state branches are explicit" {
  let dst = FixedArray::make(2, (0).to_byte())
  assert_eq(
    try {
      ignore(AsyncRead::read_exact(InvalidAsyncReader::InvalidAsyncReader, dst))
      false
    } catch {
      _ => true
    },
    true,
  )
  assert_eq(
    try {
      ignore(AsyncRead::read_to_end(InvalidAsyncReader::InvalidAsyncReader))
      false
    } catch {
      _ => true
    },
    true,
  )
  assert_eq(
    try {
      ignore(
        AsyncWrite::write_all(InvalidAsyncWriter::InvalidAsyncWriter, b"x"),
      )
      false
    } catch {
      _ => true
    },
    true,
  )

  let memory = AsyncMemoryReader::new(b"x"[:])
  assert_eq(
    try {
      ignore(AsyncRead::read(memory, dst, offset=2, max_len=1))
      false
    } catch {
      _ => true
    },
    true,
  )
  let writer = AsyncMemoryWriter::new()
  assert_eq(
    try {
      ignore(AsyncWrite::write(writer, b"x", offset=2, len=1))
      false
    } catch {
      _ => true
    },
    true,
  )
  AsyncClose::close(writer)
  assert_eq(AsyncClose::is_closed(writer), true)
  assert_eq(
    try {
      ignore(AsyncWrite::write(writer, b"x", offset=0, len=1))
      false
    } catch {
      _ => true
    },
    true,
  )
  AsyncClose::close(writer)
}

///|
async test "async buffered wrappers cover EOF, invalid ranges, and write failures" {
  let reader = AsyncBufReader::new(
    AsyncMemoryReader::new(b"abc"[:]),
    capacity=2,
  )
  let invalid = try {
    ignore(
      AsyncRead::read(
        reader,
        FixedArray::make(1, (0).to_byte()),
        offset=2,
        max_len=1,
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_eq(invalid, true)
  let line = AsyncBufRead::read_until(reader, b'\n')
  assert_eq(line, b"abc")
  assert_eq(AsyncBufRead::fill_buf(reader).to_owned(), [])
  assert_eq(AsyncBufReader::get_ref(reader).position, 3)
  assert_eq(
    try {
      AsyncBufRead::consume(reader, 1)
      false
    } catch {
      _ => true
    },
    true,
  )
  let zero = AsyncBufWriter::new(AlwaysZeroAsyncWriter::Zero, capacity=2)
  ignore(AsyncWrite::write(zero, b"x", offset=0, len=1))
  assert_eq(
    try {
      AsyncWrite::flush(zero)
      false
    } catch {
      _ => true
    },
    true,
  )
  let invalid_writer = AsyncBufWriter::new(AsyncMemoryWriter::new(), capacity=2)
  assert_eq(
    try {
      ignore(AsyncWrite::write(invalid_writer, b"x", offset=2, len=1))
      false
    } catch {
      _ => true
    },
    true,
  )
  ignore(AsyncBufWriter::get_ref(invalid_writer))

  let contract_writer = AsyncBufWriter::new(
    InvalidAsyncWriter::InvalidAsyncWriter,
    capacity=2,
  )
  ignore(AsyncWrite::write(contract_writer, b"x", offset=0, len=1))
  assert_eq(
    try {
      ignore(AsyncWrite::flush(contract_writer))
      false
    } catch {
      _ => true
    },
    true,
  )
}

///|
async test "async native wrappers reject operations after close" {
  ensure_async_test_dir()
  let path = async_test_dir + "/closed.bin"
  let file = AsyncFile::create(path)
  AsyncClose::close(file)
  let dst = FixedArray::make(1, (0).to_byte())
  assert_eq(
    try {
      ignore(AsyncRead::read(file, dst))
      false
    } catch {
      _ => true
    },
    true,
  )
  assert_eq(
    try {
      ignore(AsyncWrite::write(file, b"x", offset=0, len=1))
      false
    } catch {
      _ => true
    },
    true,
  )
  assert_eq(
    try {
      ignore(AsyncSeek::seek(file, Current(0L)))
      false
    } catch {
      _ => true
    },
    true,
  )
  assert_eq(
    try {
      ignore(AsyncSeek::seek(file, Start(-1L)))
      false
    } catch {
      _ => true
    },
    true,
  )

  let listener = AsyncTcpListener::bind("127.0.0.1:0")
  AsyncClose::close(listener)
  assert_eq(
    try {
      ignore(listener.accept())
      false
    } catch {
      _ => true
    },
    true,
  )
}

///|
async test "async buffered paths flush full buffers and copy files" {
  let empty = AsyncBufReader::new(AsyncMemoryReader::new(b""[:]), capacity=2)
  let one = FixedArray::make(1, (0).to_byte())
  assert_eq(AsyncRead::read(empty, one), 0)

  let writer = AsyncBufWriter::new(AsyncMemoryWriter::new(), capacity=2)
  ignore(AsyncWrite::write(writer, b"a", offset=0, len=1))
  ignore(AsyncWrite::write(writer, b"b", offset=0, len=1))
  ignore(AsyncWrite::write(writer, b"c", offset=0, len=1))
  AsyncWrite::flush(writer)
  assert_eq(AsyncBufWriter::get_ref(writer).to_bytes(), b"abc")

  ensure_async_test_dir()
  let source_path = async_test_dir + "/copy-source.bin"
  let destination_path = async_test_dir + "/copy-destination.bin"
  write_file(source_path, b"copy-file"[:])
  let progress = copy_file(source_path, destination_path, buffer_size=3)
  assert_eq(progress.bytes_copied, 9)
  assert_eq(
    try {
      ignore(
        copy(
          AsyncMemoryReader::new(b"x"[:]),
          AsyncMemoryWriter::new(),
          buffer_size=0,
        ),
      )
      false
    } catch {
      _ => true
    },
    true,
  )
}
