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
  assert_true(
    try {
      ignore(@io.Write::write(writer, b"x", 2, 1))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(writer.path(), path)
  ignore(@io.Write::write(writer, b"", 0, 0))
  @io.Write::write_all(writer, [b'a', b'b', b'c', b'd'][:])
  @io.Write::flush(writer)
  assert_eq(@io.Seek::seek(writer, @io.Start(1L)), 1L)
  @io.Write::write_all(writer, [b'Z'][:])
  @io.Close::close(writer)
  assert_eq(@io.Close::is_closed(writer), true)

  let reader = NativeFile::open_read(path)
  let direct = FixedArray::make(1, (0).to_byte())
  assert_eq(@io.Read::read(reader, direct, 0, 0), 0)
  assert_eq(@io.Seek::stream_position(reader), 0L)
  let output = Array::make(4, (0).to_byte())
  @io.Read::read_exact(reader, output.mut_view())
  assert_eq(output, [b'a', b'Z', b'c', b'd'])
  assert_eq(@io.Seek::seek(reader, @io.End(-1L)), 3L)
  assert_eq(@io.Seek::seek(reader, @io.Current(0L)), 3L)
  let tail = Array::make(1, (0).to_byte())
  assert_eq(@io.Read::read_array(reader, tail.mut_view()), 1)
  assert_eq(tail[0], b'd')
  @io.Close::close(reader)
  assert_true(
    try {
      ignore(@io.Read::read(reader, direct, 0, 1))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@io.Seek::seek(reader, @io.Current(0L)))
      false
    } catch {
      _ => true
    },
  )
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
test "NativeFile vectored I/O preserves ordering and syscall accounting" {
  ensure_native_test_dir()
  let path = native_test_dir + "/vectored.bin"
  let writer = NativeFile::create(path)
  let before_write = writer.write_syscalls()
  let sources = [
    @io.IoSlice::new(b"", 0, 0),
    @io.IoSlice::new(b"-ab-", 1, 2),
    @io.IoSlice::new(b"cd", 0, 2),
  ]
  let write_vectored = @io.Write::is_write_vectored(writer)
  let written = @io.Write::write_vectored(writer, sources[:])
  assert_eq(written, if write_vectored { 4 } else { 2 })
  assert_eq(writer.write_syscalls() - before_write, 1)
  if !write_vectored {
    assert_eq(@io.Write::write(writer, b"cd", 0, 2), 2)
  }
  @io.Close::close(writer)

  let reader = NativeFile::open_read(path)
  let first = FixedArray::make(3, b'-')
  let second = FixedArray::make(3, b'-')
  let before_read = reader.read_syscalls()
  let destinations = [
    @io.IoSliceMut::new(first, 1, 2),
    @io.IoSliceMut::new(second, 0, 2),
  ]
  let read_vectored = @io.Read::is_read_vectored(reader)
  let read = @io.Read::read_vectored(reader, destinations[:])
  assert_eq(read, if read_vectored { 4 } else { 2 })
  if !read_vectored {
    assert_eq(@io.Read::read(reader, second, 0, 2), 2)
  }
  assert_eq(first.unsafe_reinterpret_as_bytes(), b"-ab")
  assert_eq(second.unsafe_reinterpret_as_bytes(), b"cd-")
  assert_eq(
    reader.read_syscalls() - before_read,
    if read_vectored {
      1
    } else {
      2
    },
  )
  let empty = [@io.IoSliceMut::new(first, 0, 0)]
  assert_eq(@io.Read::read_vectored(reader, empty[:]), 0)
  assert_eq(
    reader.read_syscalls() - before_read,
    if read_vectored {
      1
    } else {
      2
    },
  )
  @io.Close::close(reader)
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
  let mapped_dst = FixedArray::make(1, (0).to_byte())
  assert_eq(@io.Read::read(slice, mapped_dst, 0, 0), 0)
  assert_true(
    try {
      ignore(@io.Read::read(slice, mapped_dst, 2, 1))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(@io.Seek::seek(slice, @io.Start(0L)), 0L)
  assert_eq(@io.Seek::stream_position(slice), 0L)
  assert_eq(@io.Seek::seek(slice, @io.Current(1L)), 1L)
  assert_true(
    try {
      ignore(@io.Seek::seek(slice, @io.Start(-1L)))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(slice.copy_range(9, 1))
      false
    } catch {
      _ => true
    },
  )
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
  assert_true(
    try {
      ignore(slice.slice(0, 0))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(slice.copy_range(0, 0))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(slice.find_byte(b'a'))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "NativeTcp performs a loopback roundtrip and closes idempotently" {
  let listener = NativeTcpListener::bind("127.0.0.1", 0)
  let port = listener.local_port()
  assert_true(port > 0)
  let client = NativeTcpStream::connect("127.0.0.1", port)
  let server = listener.accept()
  assert_true(client.local_port() > 0)
  assert_eq(client.peer_port(), port)
  let empty = FixedArray::make(1, (0).to_byte())
  assert_eq(@io.Read::read(client, empty, 0, 0), 0)
  assert_eq(@io.Write::write(client, b"", 0, 0), 0)

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
  client.set_timeouts(1000, 1000)
  client.shutdown_both()
  server.shutdown_both()

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
test "NativeTcp uses one vectored syscall per ordered message" {
  let listener = NativeTcpListener::bind("127.0.0.1", 0)
  let client = NativeTcpStream::connect("127.0.0.1", listener.local_port())
  let server = listener.accept()
  let before_write = client.write_syscalls()
  let message = [
    @io.IoSlice::new(b"vec", 0, 3),
    @io.IoSlice::new(b"tored", 0, 5),
  ]
  assert_eq(@io.Write::write_vectored(client, message[:]), 8)
  assert_eq(client.write_syscalls() - before_write, 1)
  assert_eq(@io.Write::is_write_vectored(client), true)
  let left = FixedArray::make(3, (0).to_byte())
  let right = FixedArray::make(5, (0).to_byte())
  let destinations = [
    @io.IoSliceMut::new(left, 0, 3),
    @io.IoSliceMut::new(right, 0, 5),
  ]
  let before_read = server.read_syscalls()
  assert_eq(@io.Read::read_vectored(server, destinations[:]), 8)
  assert_eq(left.unsafe_reinterpret_as_bytes(), b"vec")
  assert_eq(right.unsafe_reinterpret_as_bytes(), b"tored")
  assert_eq(server.read_syscalls() - before_read, 1)
  assert_eq(@io.Read::is_read_vectored(server), true)
  @io.Close::close(client)
  @io.Close::close(server)
  @io.Close::close(listener)
}

///|
test "Native TCP validates ranges and closed resource errors" {
  let invalid_host = try {
    ignore(NativeTcpStream::connect("", 1))
    false
  } catch {
    error => error.kind() == @io.InvalidInput
  }
  assert_true(invalid_host)
  assert_true(
    try {
      ignore(NativeTcpStream::connect("127.0.0.1", 70000))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(NativeTcpListener::bind("127.0.0.1", 70000))
      false
    } catch {
      _ => true
    },
  )
  let listener = NativeTcpListener::bind("127.0.0.1", 0)
  let client = NativeTcpStream::connect("127.0.0.1", listener.local_port())
  let server = listener.accept()
  let destination = FixedArray::make(1, (0).to_byte())
  assert_true(
    try {
      ignore(@io.Read::read(client, destination, 2, 1))
      false
    } catch {
      error => error.kind() == @io.InvalidInput
    },
  )
  assert_true(
    try {
      ignore(@io.Write::write(client, b"x", 2, 1))
      false
    } catch {
      error => error.kind() == @io.InvalidInput
    },
  )
  assert_true(
    try {
      client.set_timeouts(-1, 1)
      false
    } catch {
      error => error.kind() == @io.InvalidInput
    },
  )
  client.shutdown_read()
  client.shutdown_write()
  @io.Close::close(client)
  @io.Close::close(server)
  @io.Close::close(listener)
  assert_true(
    try {
      ignore(@io.Read::read(client, destination, 0, 1))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@io.Write::write(client, b"x", 0, 1))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      client.shutdown_read()
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      client.shutdown_write()
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      client.shutdown_both()
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      client.set_timeouts(1, 1)
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(client.local_port())
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(client.peer_port())
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(listener.accept())
      false
    } catch {
      _ => true
    },
  )
}

///|
test "Native resources reject operations after close and wrong access mode" {
  ensure_native_test_dir()
  let path = native_test_dir + "/access.bin"
  let writer = NativeFile::create(path)
  let read_wrong = try {
    ignore(
      @io.Read::read_array(writer, Array::make(1, (0).to_byte()).mut_view()),
    )
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
    ignore(@io.Write::write_array(writer, [b'x'][:]))
    false
  } catch {
    error => error.kind() == @io.Closed
  }
  assert_eq(closed_write, true)

  let reader = NativeFile::open_read(path)
  let write_wrong = try {
    ignore(@io.Write::write_array(reader, [b'x'][:]))
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

///|
test "NativeOpenOptions and durability APIs cover resource paths" {
  ensure_native_test_dir()
  let path = native_test_dir + "/open-options.bin"
  ignore(NativeOpenOptions::read())
  ignore(NativeOpenOptions::write())
  let writer = NativeFile::open(path, NativeOpenOptions::write_truncate())
  @io.Write::write_all(writer, [b'a', b'b'][:])
  writer.sync_data()
  writer.sync_all()
  @io.Close::close(writer)

  let reader_writer = NativeFile::open(path, NativeOpenOptions::read_write())
  ignore(@io.Seek::seek(reader_writer, @io.End(0L)))
  @io.Write::write_all(reader_writer, [b'c'][:])
  @io.Close::close(reader_writer)

  let appended = NativeFile::open(path, NativeOpenOptions::write_append())
  @io.Write::write_all(appended, [b'd'][:])
  @io.Close::close(appended)
  let create_new = try {
    ignore(NativeFile::open(path, NativeOpenOptions::write_create_new()))
    false
  } catch {
    _ => true
  }
  assert_true(create_new)
}

///|
test "NativeFile validates empty paths, modes, and closed durability" {
  assert_true(
    try {
      ignore(NativeFile::open_read(""))
      false
    } catch {
      error => error.kind() == @io.InvalidInput
    },
  )
  assert_true(
    try {
      ignore(NativeFile::open("unused", NativeOpenOptions::new()))
      false
    } catch {
      error => error.kind() == @io.InvalidInput
    },
  )
  let file = NativeFile::open_read(native_test_dir + "/roundtrip.bin")
  let dst = FixedArray::make(1, (0).to_byte())
  assert_true(
    try {
      ignore(@io.Read::read(file, dst, 2, 1))
      false
    } catch {
      error => error.kind() == @io.InvalidInput
    },
  )
  @io.Close::close(file)
  assert_true(
    try {
      file.sync_all()
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      file.sync_data()
      false
    } catch {
      _ => true
    },
  )
}
