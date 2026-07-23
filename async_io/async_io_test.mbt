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
  assert_eq(writer.bytes(), b"hello")
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
async test "buffered shutdown flushes pending bytes before the inner shutdown" {
  let probe : ShutdownProbe = { events: [] }
  let writer = AsyncBufWriter::new(probe, capacity=8)
  ignore(AsyncWrite::write(writer, b"ok", offset=0, len=2))
  AsyncWrite::shutdown(writer)
  assert_eq(writer.get_ref().events, ["write", "shutdown"])
}

///|
async test "copy and copy_bidirectional report committed bytes" {
  let source = AsyncMemoryReader::new(b"copy"[:])
  let destination = AsyncMemoryWriter::new()
  assert_eq(copy(source, destination, buffer_size=2), 4)
  assert_eq(destination.bytes(), b"copy")

  let left : TestDuplex = { incoming: b"left", position: 0, outgoing: [] }
  let right : TestDuplex = { incoming: b"right", position: 0, outgoing: [] }
  assert_eq(copy_bidirectional(left, right), (4, 5))
  assert_eq(Bytes::from_array(left.outgoing), b"right")
  assert_eq(Bytes::from_array(right.outgoing), b"left")
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
  assert_eq(AsyncBufWriter::get_ref(writer).bytes(), b"abc")

  ensure_async_test_dir()
  let source_path = async_test_dir + "/copy-source.bin"
  let destination_path = async_test_dir + "/copy-destination.bin"
  write_file(source_path, b"copy-file"[:])
  let progress = copy_file(source_path, destination_path, buffer_size=3)
  assert_eq(progress.bytes, 9)
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
