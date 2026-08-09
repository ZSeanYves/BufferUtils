///|
#borrow(handle)
extern "C" fn native_test_file_close_race_ffi(handle : NativeFileHandle) -> Int = "bufferutils_test_file_close_race"

///|
#borrow(handle)
extern "C" fn native_test_tcp_close_race_ffi(
  handle : NativeSocketHandle,
) -> Int = "bufferutils_test_tcp_close_race"

///|
#borrow(handle)
extern "C" fn native_test_mapped_close_race_ffi(
  handle : NativeMappedHandle,
) -> Int = "bufferutils_test_mapped_close_race"

///|
test "native error classification covers portable categories" {
  let cases = [
    (12, @io.Interrupted),
    (13, @io.NotFound),
    (14, @io.PermissionDenied),
    (15, @io.WouldBlock),
    (16, @io.TimedOut),
    (17, @io.ConnectionReset),
    (18, @io.BrokenPipe),
    (19, @io.ConnectionRefused),
    (20, @io.NotConnected),
    (21, @io.AddressInUse),
    (22, @io.AddressNotAvailable),
    (23, @io.StorageFull),
    (24, @io.OutOfMemory),
    (7, @io.InvalidInput),
    (8, @io.Closed),
    (9, @io.NotSeekable),
    (11, @io.Unsupported),
    (999, @io.Backend),
  ]
  for entry in cases {
    assert_eq(native_error_kind(entry.0), entry.1)
  }
}

///|
test "native C helpers race file socket and mmap operations with close" {
  if !@fs.path_exists(".tmp") {
    @fs.create_dir(".tmp")
  }
  let path = ".tmp/bufferutils-native-close-race.bin"
  @fs.write_bytes_to_file(path, Bytes::from_array(Array::make(4096, b'x')[:]))

  let file = NativeFile::open(path, NativeOpenOptions::read_write())
  assert_eq(native_test_file_close_race_ffi(file.handle), 0)
  assert_eq(@io.Close::is_closed(file), true)

  let mapped = MappedBytes::open(path)
  assert_eq(native_test_mapped_close_race_ffi(mapped.handle), 0)
  assert_eq(@io.Close::is_closed(mapped), true)

  let listener = NativeTcpListener::bind("127.0.0.1", 0)
  let client = NativeTcpStream::connect("127.0.0.1", listener.local_port())
  let server = listener.accept()
  @io.Write::write_all(client, Array::make(4096, b'x')[:])
  assert_eq(native_test_tcp_close_race_ffi(server.handle), 0)
  assert_eq(@io.Close::is_closed(server), true)
  @io.Close::close(client)
  @io.Close::close(listener)
}
