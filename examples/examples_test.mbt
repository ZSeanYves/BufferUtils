///|
let examples_test_dir = ".tmp/bufferutils-examples"

///|
fn ensure_examples_test_dir() -> Unit raise @fs.IOError {
  if !@fs.path_exists(".tmp") {
    @fs.create_dir(".tmp")
  }
  if !@fs.path_exists(examples_test_dir) {
    @fs.create_dir(examples_test_dir)
  }
}

///|
fn read_example_file(path : String) -> Bytes raise @io.IoError {
  let file = @native.NativeFile::open_read(path)
  let output : Array[Byte] = []
  ignore(@io.read_to_end(file, output))
  @io.Close::close(file)
  Bytes::from_array(output)
}

///|
test "shared buffer and text examples execute" {
  let shared = shared_buffer_example()
  assert_eq(shared.remaining(), 11)
  assert_eq(parse_lines_example(b"one\ntwo\n"), ["one\n", "two\n"])
}

///|
test "sync file copy example executes" {
  ensure_examples_test_dir()
  let source = examples_test_dir + "/source.bin"
  let destination = examples_test_dir + "/destination.bin"
  @fs.write_bytes_to_file(source, b"bufferutils")
  sync_copy_example(source, destination)
  assert_eq(read_example_file(destination), b"bufferutils")
}

///|
test "TCP shutdown example executes" {
  let listener = @native.NativeTcpListener::bind("127.0.0.1", 0)
  let client = @native.NativeTcpStream::connect(
    "127.0.0.1",
    listener.local_port(),
  )
  let server = listener.accept()
  tcp_shutdown_example(client)
  @io.Close::close(client)
  @io.Close::close(server)
  @io.Close::close(listener)
}

///|
async test "async file copy example executes" {
  ensure_examples_test_dir()
  let source = examples_test_dir + "/async-source.bin"
  let destination = examples_test_dir + "/async-destination.bin"
  @fs.write_bytes_to_file(source, b"async bufferutils")
  assert_eq(async_copy_example(source, destination), 17)
  let file = @afs.open(destination, mode=@afs.ReadOnly)
  let bytes = file.read_all().binary()
  file.close()
  assert_eq(bytes, b"async bufferutils")
}
