///|
let native_test_dir = ".tmp/bufferutils-native"

///|
fn ensure_native_test_dir() -> Unit raise @fs.IOError {
  if !@fs.path_exists(".tmp") {
    @fs.create_dir(".tmp")
  }
  if !@fs.path_exists(native_test_dir) {
    @fs.create_dir(native_test_dir)
  }
}

///|
test "NativeFile v1 streams, flushes, seeks, and closes" {
  ensure_native_test_dir()
  let path = native_test_dir + "/roundtrip.bin"
  let writer = NativeFile::create(path)
  @io.Write::write_all(writer, [b'a', b'b', b'c', b'd'][:])
  @io.Write::flush(writer)
  assert_eq(@io.Seek::seek(writer, @io.Start(1L)), 1L)
  @io.Write::write_all(writer, [b'Z'][:])
  @io.Close::close(writer)
  assert_eq(@io.Close::is_closed(writer), true)

  let reader = NativeFile::open_read(path)
  let output = Array::make(4, (0).to_byte())
  @io.Read::read_exact(reader, output.mut_view())
  assert_eq(output, [b'a', b'Z', b'c', b'd'])
  assert_eq(@io.Seek::seek(reader, @io.End(-1L)), 3L)
  let tail = Array::make(1, (0).to_byte())
  assert_eq(@io.Read::read(reader, tail.mut_view()), 1)
  assert_eq(tail[0], b'd')
  @io.Close::close(reader)
}

///|
test "NativeFile fixed-array reads honor destination offsets" {
  ensure_native_test_dir()
  let path = native_test_dir + "/fixed-read.bin"
  @fs.write_bytes_to_file(path, Bytes::from_array([b'a', b'b', b'c', b'd'][:]))
  let reader = NativeFile::open_read(path)
  let destination = FixedArray::make(6, b'-')
  assert_eq(@io.Read::read_fixed(reader, destination, 2, 3), 3)
  assert_eq(destination[0], b'-')
  assert_eq(destination[1], b'-')
  assert_eq(destination[2], b'a')
  assert_eq(destination[3], b'b')
  assert_eq(destination[4], b'c')
  assert_eq(destination[5], b'-')
  assert_eq(@io.Read::read_fixed(reader, destination, 0, 0), 0)
  let invalid = try {
    ignore(@io.Read::read_fixed(reader, destination, -1, 1))
    false
  } catch {
    error => error.kind() == @io.InvalidInput
  }
  assert_eq(invalid, true)
  @io.Close::close(reader)
  let closed = try {
    ignore(@io.Read::read_fixed(reader, destination, 0, 1))
    false
  } catch {
    error => error.kind() == @io.Closed
  }
  assert_eq(closed, true)
}

///|
test "NativeFile v1 reports closed and missing resources structurally" {
  let missing = try {
    ignore(NativeFile::open_read(native_test_dir + "/missing.bin"))
    false
  } catch {
    error => error.kind() == @io.NotFound && error.raw_code() != 0
  }
  assert_eq(missing, true)
  let missing_map = try {
    ignore(MappedBytes::open(native_test_dir + "/missing.bin"))
    false
  } catch {
    error => error.kind() == @io.NotFound && error.raw_code() != 0
  }
  assert_eq(missing_map, true)
}

///|
test "NativeFile v1 append preserves existing bytes" {
  ensure_native_test_dir()
  let path = native_test_dir + "/append.bin"
  let first = NativeFile::create(path)
  @io.Write::write_all(first, [b'a', b'b'][:])
  @io.Close::close(first)
  let second = NativeFile::append(path)
  @io.Write::write_all(second, [b'c', b'd'][:])
  @io.Close::close(second)
  let reader = NativeFile::open_read(path)
  let output = Array::make(4, (0).to_byte())
  @io.Read::read_exact(reader, output.mut_view())
  assert_eq(output, [b'a', b'b', b'c', b'd'])
  @io.Close::close(reader)
}

///|
test "MappedBytes v1 shares slices and closes idempotently" {
  ensure_native_test_dir()
  let path = native_test_dir + "/mapped.bin"
  @fs.write_bytes_to_file(
    path,
    Bytes::from_array([b'a', b'b', b'c', b'd', b'e'][:]),
  )
  let root = MappedBytes::open(path)
  let slice = root.slice(1, 3)
  assert_eq(root.len(), 5)
  assert_eq(slice.len(), 3)
  assert_eq(slice.read_byte_at(0), b'b')
  assert_eq(slice.find_byte(b'd'), 2)
  assert_eq(slice.copy_range(0, 3), Bytes::from_array([b'b', b'c', b'd'][:]))
  assert_eq(@io.Seek::seek(slice, @io.End(-1L)), 2L)
  let tail = Array::make(1, (0).to_byte())
  @io.Read::read_exact(slice, tail.mut_view())
  assert_eq(tail[0], b'd')
  @io.Close::close(root)
  assert_eq(@io.Close::is_closed(slice), false)
  @io.Close::close(slice)
  @io.Close::close(slice)
  assert_eq(@io.Close::is_closed(slice), true)
}

///|
test "NativeTcp v1 performs a loopback roundtrip and closes idempotently" {
  let listener = NativeTcpListener::bind("127.0.0.1", 0)
  let port = listener.local_port()
  assert_true(port > 0)
  let client = NativeTcpStream::connect("127.0.0.1", port)
  let server = listener.accept()

  @io.Write::write_all(client, [b'p', b'i', b'n', b'g'][:])
  @io.Write::flush(client)
  let request = FixedArray::make(6, b'-')
  assert_eq(@io.Read::read_fixed(server, request, 1, 4), 4)
  assert_eq(request.unsafe_reinterpret_as_bytes(), b"-ping-")
  assert_eq(@io.Read::read_fixed(server, request, 0, 0), 0)
  let invalid_read = try {
    ignore(@io.Read::read_fixed(server, request, -1, 1))
    false
  } catch {
    error => error.kind() == @io.InvalidInput
  }
  assert_eq(invalid_read, true)

  @io.Write::write_all(server, [b'p', b'o', b'n', b'g'][:])
  let response = Array::make(4, (0).to_byte())
  @io.Read::read_exact(client, response.mut_view())
  assert_eq(response, [b'p', b'o', b'n', b'g'])

  @io.Close::close(client)
  @io.Close::close(client)
  let closed_read = try {
    ignore(@io.Read::read_fixed(client, request, 0, 1))
    false
  } catch {
    error => error.kind() == @io.Closed
  }
  assert_eq(closed_read, true)
  @io.Close::close(server)
  @io.Close::close(listener)
  assert_eq(@io.Close::is_closed(client), true)
  assert_eq(@io.Close::is_closed(listener), true)
}

///|
test "Native resources reject operations after close and wrong access mode" {
  ensure_native_test_dir()
  let path = native_test_dir + "/access.bin"
  let writer = NativeFile::create(path)
  let read_wrong = try {
    ignore(@io.Read::read(writer, Array::make(1, (0).to_byte()).mut_view()))
    false
  } catch {
    error => error.kind() == @io.InvalidInput
  }
  assert_eq(read_wrong, true)
  let fixed_read_wrong = try {
    ignore(@io.Read::read_fixed(writer, FixedArray::make(1, b'\x00'), 0, 1))
    false
  } catch {
    error => error.kind() == @io.InvalidInput
  }
  assert_eq(fixed_read_wrong, true)
  @io.Close::close(writer)
  let closed_write = try {
    ignore(@io.Write::write(writer, [b'x'][:]))
    false
  } catch {
    error => error.kind() == @io.Closed
  }
  assert_eq(closed_write, true)

  let reader = NativeFile::open_read(path)
  let write_wrong = try {
    ignore(@io.Write::write(reader, [b'x'][:]))
    false
  } catch {
    error => error.kind() == @io.InvalidInput
  }
  assert_eq(write_wrong, true)
  @io.Close::close(reader)

  let mapped = MappedBytes::open(path)
  let bad_slice = try {
    ignore(mapped.slice(99, 1))
    false
  } catch {
    error => error.kind() == @io.InvalidInput
  }
  assert_eq(bad_slice, true)
  @io.Close::close(mapped)
  let closed_map = try {
    ignore(mapped.read_byte_at(0))
    false
  } catch {
    error => error.kind() == @io.Closed
  }
  assert_eq(closed_map, true)

  let listener = NativeTcpListener::bind("127.0.0.1", 0)
  @io.Close::close(listener)
  let closed_listener = try {
    ignore(listener.local_port())
    false
  } catch {
    error => error.kind() == @io.Closed
  }
  assert_eq(closed_listener, true)
}
