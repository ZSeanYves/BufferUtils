///|
let native_test_output_root = ".tmp"

///|
let native_test_output_dir = ".tmp/bufferutils-native-tests"

///|
fn ensure_native_test_output_dir() -> Unit raise @fs.IOError {
  if !@fs.path_exists(native_test_output_root) {
    @fs.create_dir(native_test_output_root)
  }
  if !@fs.path_exists(native_test_output_dir) {
    @fs.create_dir(native_test_output_dir)
  }
}

///|
fn native_test_path(name : String) -> String raise @fs.IOError {
  ensure_native_test_output_dir()
  native_test_output_dir + "/" + name
}

///|
fn write_fixture(path : String, data : Array[Byte]) -> Unit raise @fs.IOError {
  @fs.write_bytes_to_file(path, @bufferutils.array_to_bytes(data))
}

///|
fn read_fixture(path : String) -> Array[Byte] raise @fs.IOError {
  @fs.read_file_to_bytes(path).to_array()
}

///|
fn pattern_bytes(len : Int) -> Array[Byte] {
  let out : Array[Byte] = []
  for i in 0..<len {
    out.push((i % 256).to_byte())
  }
  out
}

///|
fn read_all_native(
  path : String,
  chunk_size : Int,
) -> Array[Byte] raise @bufferutils.BufferError {
  let source = new_native_file_source(path)
  let out : Array[Byte] = []
  while true {
    let chunk = source.read_chunk(chunk_size)
    if chunk.length() == 0 {
      break
    }
    out.append(chunk[:])
  }
  source.close()
  out
}

///|
fn read_all_native_buffered(
  path : String,
  capacity : Int,
) -> Array[Byte] raise @bufferutils.BufferError {
  let reader = new_native_buf_reader(path, capacity)
  let out = reader.read_to_end()
  reader.close()
  out
}

///|
test "native backend version probe returns expected value" {
  assert_eq(native_backend_version(), 100)
}

///|
test "native file source rejects empty path" {
  let result = try? new_native_file_source("")
  assert_eq(result is Err(_), true)
}

///|
test "native file source reports missing file" {
  let result = try? new_native_file_source(
    ".tmp/bufferutils-native-tests/does-not-exist.bin",
  )
  assert_eq(result is Err(_), true)
}

///|
test "native file source reads empty file and stays at eof" {
  let path = native_test_path("native-empty.bin")
  write_fixture(path, [])
  let source = new_native_file_source(path)
  assert_eq(source.read_chunk(1024), [])
  assert_eq(source.read_chunk(8), [])
  source.close()
  assert_eq(source.is_closed(), true)
}

///|
test "native file source read_chunk zero returns empty array" {
  let path = native_test_path("native-zero-chunk.bin")
  write_fixture(path, [1, 2, 3])
  let source = new_native_file_source(path)
  assert_eq(source.read_chunk(0), [])
  assert_eq(source.read_chunk(2), [1, 2])
  source.close()
}

///|
test "native file source read_chunk negative raises invalid input" {
  let path = native_test_path("native-negative-chunk.bin")
  write_fixture(path, [1, 2, 3])
  let source = new_native_file_source(path)
  let result = try? source.read_chunk(-1)
  assert_eq(result is Err(_), true)
  source.close()
}

///|
test "native file source reads small file in multiple chunks with stable eof" {
  let path = native_test_path("native-small.bin")
  write_fixture(path, [1, 2, 3, 4, 5])
  let source = new_native_file_source(path)
  assert_eq(source.read_chunk(2), [1, 2])
  assert_eq(source.read_chunk(2), [3, 4])
  assert_eq(source.read_chunk(2), [5])
  assert_eq(source.read_chunk(2), [])
  assert_eq(source.read_chunk(2), [])
  source.close()
}

///|
test "native file source close is idempotent and read after close errors" {
  let path = native_test_path("native-source-close.bin")
  write_fixture(path, [1, 2, 3])
  let source = new_native_file_source(path)
  source.close()
  source.close()
  assert_eq(source.is_closed(), true)
  let result = try? source.read_chunk(1)
  assert_eq(result is Err(_), true)
}

///|
test "native file source reads large file by chunk without full snapshot" {
  let path = native_test_path("native-large-10mb.bin")
  let data = pattern_bytes(10 * 1024 * 1024)
  write_fixture(path, data)
  let out = read_all_native(path, 4096)
  assert_eq(out.length(), data.length())
  assert_eq(out[0], 0)
  assert_eq(out[out.length() - 1], data[data.length() - 1])
}

///|
test "native file sink rejects empty path" {
  let result = try? new_native_file_sink("", NativeFileMode::Overwrite)
  assert_eq(result is Err(_), true)
}

///|
test "native file sink overwrite mode creates a new file" {
  let path = native_test_path("native-overwrite-create.bin")
  let sink = new_native_file_sink(path, NativeFileMode::Overwrite)
  sink.write_all([1, 2, 3])
  sink.flush()
  sink.close()
  assert_eq(read_fixture(path), [1, 2, 3])
}

///|
test "native file sink overwrite mode replaces old contents" {
  let path = native_test_path("native-overwrite-replace.bin")
  write_fixture(path, [9, 9, 9, 9])
  let sink = new_native_file_sink(path, NativeFileMode::Overwrite)
  sink.write_all([1, 2, 3])
  sink.flush()
  sink.close()
  assert_eq(read_fixture(path), [1, 2, 3])
}

///|
test "native file sink append mode appends to existing contents" {
  let path = native_test_path("native-append.bin")
  write_fixture(path, [1, 2, 3])
  let sink = new_native_file_sink(path, NativeFileMode::Append)
  sink.write_all([4, 5])
  sink.flush()
  sink.close()
  assert_eq(read_fixture(path), [1, 2, 3, 4, 5])
}

///|
test "native file sink empty write and empty flush succeed" {
  let path = native_test_path("native-empty-write.bin")
  let sink = new_native_file_sink(path, NativeFileMode::Overwrite)
  sink.write_all([])
  sink.flush()
  sink.close()
  assert_eq(read_fixture(path), [])
}

///|
test "native file sink close flushes pending bytes before releasing handle" {
  let path = native_test_path("native-close-flushes.bin")
  let sink = new_native_file_sink(path, NativeFileMode::Overwrite)
  sink.write_all([7, 8, 9])
  sink.close()
  assert_eq(read_fixture(path), [7, 8, 9])
}

///|
test "native file sink close is idempotent and rejects write or flush after close" {
  let path = native_test_path("native-sink-close.bin")
  let sink = new_native_file_sink(path, NativeFileMode::Overwrite)
  sink.write_all([9, 8, 7])
  sink.close()
  sink.close()
  assert_eq(sink.is_closed(), true)
  let write_result = try? sink.write_all([6])
  let flush_result = try? sink.flush()
  assert_eq(write_result is Err(_), true)
  assert_eq(flush_result is Err(_), true)
}

///|
test "native sink overwrite then native source read roundtrip works" {
  let path = native_test_path("native-roundtrip-small.bin")
  let data = @bufferutils.ints_to_bytes([1, 2, 3, 4, 5])
  let sink = new_native_file_sink(path, NativeFileMode::Overwrite)
  sink.write_all(data)
  sink.flush()
  sink.close()
  assert_eq(read_all_native(path, 2), data)
}

///|
test "native sink append twice then native source read preserves order" {
  let path = native_test_path("native-roundtrip-append.bin")
  let first = new_native_file_sink(path, NativeFileMode::Overwrite)
  first.write_all([1, 2, 3])
  first.close()

  let second = new_native_file_sink(path, NativeFileMode::Append)
  second.write_all([4, 5])
  second.close()

  assert_eq(read_all_native(path, 3), [1, 2, 3, 4, 5])
}

///|
test "native sink output can be read by root file source" {
  let path = native_test_path("native-to-root-source.bin")
  let data = pattern_bytes(64 * 1024)
  let sink = new_native_file_sink(path, NativeFileMode::Overwrite)
  sink.write_all(data)
  sink.close()

  let source = @bufferutils.new_file_source(path)
  assert_eq(source.read_to_end(), data)
}

///|
test "root file sink output can be read by native source" {
  let path = native_test_path("root-to-native-source.bin")
  let data = pattern_bytes(1024 * 1024)
  let sink = @bufferutils.new_file_sink(path)
  sink.write(data)
  sink.flush()

  assert_eq(read_all_native(path, 4096), data)
}

///|
test "native and root file layers interoperate across multiple sizes" {
  let sizes = [0, 1, 64 * 1024, 1024 * 1024]
  for size in sizes {
    let path = native_test_path("interop-\{size}.bin")
    let data = pattern_bytes(size)

    let native_sink = new_native_file_sink(path, NativeFileMode::Overwrite)
    native_sink.write_all(data)
    native_sink.close()

    let root_source = @bufferutils.new_file_source(path)
    assert_eq(root_source.read_to_end(), data)

    let root_sink = @bufferutils.new_file_sink(path)
    root_sink.write(data)
    root_sink.flush()

    assert_eq(read_all_native(path, 2048), data)
  }
}

///|
test "native large roundtrip 10mb remains correct" {
  let path = native_test_path("native-roundtrip-10mb.bin")
  let data = pattern_bytes(10 * 1024 * 1024)
  let sink = new_native_file_sink(path, NativeFileMode::Overwrite)
  sink.write_all(data)
  sink.flush()
  sink.close()

  let out = read_all_native(path, 16 * 1024)
  assert_eq(out.length(), data.length())
  assert_eq(out[0], data[0])
  assert_eq(out[1024], data[1024])
  assert_eq(out[out.length() - 1], data[data.length() - 1])
}

///|
test "native buffered reader rejects empty path" {
  let result = try? new_native_buf_reader("", 4)
  assert_eq(result is Err(_), true)
}

///|
test "native buffered reader rejects non-positive capacity" {
  let path = native_test_path("native-buf-reader-capacity.bin")
  write_fixture(path, [1])
  let zero = try? new_native_buf_reader(path, 0)
  let negative = try? new_native_buf_reader(path, -1)
  assert_eq(zero is Err(_), true)
  assert_eq(negative is Err(_), true)
}

///|
test "native buffered reader reports missing file" {
  let result = try? new_native_buf_reader(
    ".tmp/bufferutils-native-tests/missing-buffered.bin", 4,
  )
  assert_eq(result is Err(_), true)
}

///|
test "native buffered reader handles empty file eof behavior" {
  let path = native_test_path("native-buf-empty.bin")
  write_fixture(path, [])
  let reader = new_native_buf_reader(path, 4)
  assert_eq(reader.read_to_end(), [])
  assert_eq(reader.is_eof(), true)
  assert_eq(reader.read_to_end(), [])
  let read_byte_result = try? reader.read_byte()
  assert_eq(read_byte_result is Err(_), true)
  reader.close()
}

///|
test "native buffered reader fill_buf and consume preserve buffered semantics" {
  let path = native_test_path("native-buf-fill.bin")
  write_fixture(path, [1, 2, 3, 4])
  let reader = new_native_buf_reader(path, 2)
  assert_eq(reader.fill_buf(), 2)
  assert_eq(reader.buffered_len(), 2)
  assert_eq(reader.fill_buf(), 2)
  reader.consume(1)
  assert_eq(reader.buffered_len(), 1)
  assert_eq(reader.fill_buf(), 1)
  reader.close()
}

///|
test "native buffered reader read_byte crosses refill boundaries" {
  let path = native_test_path("native-buf-read-byte.bin")
  write_fixture(path, [1, 2, 3, 4, 5])
  let reader = new_native_buf_reader(path, 2)
  let out : Array[Byte] = []
  for _ in 0..<5 {
    out.push(reader.read_byte())
  }
  assert_eq(out, [1, 2, 3, 4, 5])
  assert_eq(reader.buffered_len(), 0)
  assert_eq(reader.read_to_end(), [])
  assert_eq(reader.is_eof(), true)
  reader.close()
}

///|
test "native buffered reader read_exact supports zero short and long requests" {
  let path = native_test_path("native-buf-read-exact.bin")
  write_fixture(path, [1, 2, 3, 4, 5])
  let reader = new_native_buf_reader(path, 2)
  assert_eq(reader.read_exact(0), [])
  assert_eq(reader.read_exact(1), [1])
  assert_eq(reader.read_exact(3), [2, 3, 4])
  assert_eq(reader.read_exact(1), [5])
  let result = try? reader.read_exact(1)
  assert_eq(result is Err(_), true)
  reader.close()
}

///|
test "native buffered reader read_exact underflow may happen after partial consumption" {
  let path = native_test_path("native-buf-read-exact-underflow.bin")
  write_fixture(path, [1, 2, 3])
  let reader = new_native_buf_reader(path, 1)
  let result = try? reader.read_exact(4)
  assert_eq(result is Err(_), true)
  assert_eq(reader.is_eof(), true)
  reader.close()
}

///|
test "native buffered reader capacity one reads to end correctly" {
  let path = native_test_path("native-buf-cap-one.bin")
  let data = pattern_bytes(128)
  write_fixture(path, data)
  let reader = new_native_buf_reader(path, 1)
  assert_eq(reader.read_to_end(), data)
  assert_eq(reader.is_eof(), true)
  reader.close()
}

///|
test "native buffered reader consume validates bounds" {
  let path = native_test_path("native-buf-consume.bin")
  write_fixture(path, [1, 2, 3])
  let reader = new_native_buf_reader(path, 2)
  ignore(reader.fill_buf())
  let before = reader.buffered_len()
  reader.consume(0)
  assert_eq(reader.buffered_len(), before)
  let negative = try? reader.consume(-1)
  let too_far = try? reader.consume(3)
  assert_eq(negative is Err(_), true)
  assert_eq(too_far is Err(_), true)
  reader.close()
}

///|
test "native buffered reader close is idempotent and rejects later operations" {
  let path = native_test_path("native-buf-close.bin")
  write_fixture(path, [1, 2, 3])
  let reader = new_native_buf_reader(path, 2)
  reader.close()
  reader.close()
  assert_eq(reader.is_closed(), true)
  let fill_result = try? reader.fill_buf()
  let read_result = try? reader.read_byte()
  let consume_result = try? reader.consume(0)
  assert_eq(fill_result is Err(_), true)
  assert_eq(read_result is Err(_), true)
  assert_eq(consume_result is Err(_), true)
}

///|
test "native buffered reader reads 10mb total length correctly" {
  let path = native_test_path("native-buf-reader-10mb.bin")
  let data = pattern_bytes(10 * 1024 * 1024)
  write_fixture(path, data)
  let reader = new_native_buf_reader(path, 4096)
  let out = reader.read_to_end()
  assert_eq(out.length(), data.length())
  assert_eq(out[0], data[0])
  assert_eq(out[out.length() - 1], data[data.length() - 1])
  reader.close()
}

///|
test "native buffered writer rejects empty path" {
  let result = try? new_native_buf_writer("", 4, NativeFileMode::Overwrite)
  assert_eq(result is Err(_), true)
}

///|
test "native buffered writer rejects non-positive capacity" {
  let zero = try? new_native_buf_writer(
    native_test_output_dir + "/native-buf-writer-zero.bin",
    0,
    NativeFileMode::Overwrite,
  )
  let negative = try? new_native_buf_writer(
    native_test_output_dir + "/native-buf-writer-negative.bin",
    -1,
    NativeFileMode::Overwrite,
  )
  assert_eq(zero is Err(_), true)
  assert_eq(negative is Err(_), true)
}

///|
test "native buffered writer write_byte and flush write expected contents" {
  let path = native_test_path("native-buf-writer-byte.bin")
  let writer = new_native_buf_writer(path, 4, NativeFileMode::Overwrite)
  writer.write_byte(1)
  writer.write_byte(2)
  writer.flush()
  writer.close()
  assert_eq(read_fixture(path), [1, 2])
}

///|
test "native buffered writer write_byte across buffer boundaries preserves order" {
  let path = native_test_path("native-buf-writer-overflow.bin")
  let writer = new_native_buf_writer(path, 2, NativeFileMode::Overwrite)
  writer.write_byte(1)
  writer.write_byte(2)
  writer.write_byte(3)
  writer.write_byte(4)
  writer.write_byte(5)
  writer.close()
  assert_eq(read_fixture(path), [1, 2, 3, 4, 5])
}

///|
test "native buffered writer accepts empty write" {
  let path = native_test_path("native-buf-writer-empty.bin")
  let writer = new_native_buf_writer(path, 4, NativeFileMode::Overwrite)
  writer.write_all([])
  writer.close()
  assert_eq(read_fixture(path), [])
}

///|
test "native buffered writer small buffered write flushes correctly" {
  let path = native_test_path("native-buf-writer-small.bin")
  let writer = new_native_buf_writer(path, 4, NativeFileMode::Overwrite)
  writer.write_all([1, 2, 3])
  assert_eq(writer.buffered_len(), 3)
  writer.flush()
  assert_eq(writer.buffered_len(), 0)
  writer.close()
  assert_eq(read_fixture(path), [1, 2, 3])
}

///|
test "native buffered writer large write can bypass local buffer" {
  let path = native_test_path("native-buf-writer-large.bin")
  let data = pattern_bytes(64 * 1024)
  let writer = new_native_buf_writer(path, 256, NativeFileMode::Overwrite)
  writer.write_all(data)
  assert_eq(writer.buffered_len(), 0)
  writer.close()
  assert_eq(read_all_native(path, 1024), data)
}

///|
test "native buffered writer repeated flush does not duplicate bytes" {
  let path = native_test_path("native-buf-writer-repeat-flush.bin")
  let writer = new_native_buf_writer(path, 4, NativeFileMode::Overwrite)
  writer.write_all([1, 2, 3])
  writer.flush()
  writer.flush()
  writer.close()
  assert_eq(read_fixture(path), [1, 2, 3])
}

///|
test "native buffered writer overwrite and append modes preserve expected semantics" {
  let path = native_test_path("native-buf-writer-modes.bin")
  write_fixture(path, [9, 9, 9])

  let overwrite = new_native_buf_writer(path, 4, NativeFileMode::Overwrite)
  overwrite.write_all([1, 2])
  overwrite.close()
  assert_eq(read_fixture(path), [1, 2])

  let append = new_native_buf_writer(path, 4, NativeFileMode::Append)
  append.write_all([3, 4])
  append.close()
  assert_eq(read_fixture(path), [1, 2, 3, 4])
}

///|
test "native buffered writer close flushes pending bytes" {
  let path = native_test_path("native-buf-writer-close.bin")
  let writer = new_native_buf_writer(path, 4, NativeFileMode::Overwrite)
  writer.write_all([5, 6, 7])
  writer.close()
  assert_eq(read_fixture(path), [5, 6, 7])
}

///|
test "native buffered writer close is idempotent and rejects later operations" {
  let path = native_test_path("native-buf-writer-after-close.bin")
  let writer = new_native_buf_writer(path, 4, NativeFileMode::Overwrite)
  writer.write_all([1, 2])
  writer.close()
  writer.close()
  assert_eq(writer.is_closed(), true)
  let write_result = try? writer.write_byte(3)
  let flush_result = try? writer.flush()
  assert_eq(write_result is Err(_), true)
  assert_eq(flush_result is Err(_), true)
}

///|
test "native buffered writer large 10mb write can be read back natively" {
  let path = native_test_path("native-buf-writer-10mb.bin")
  let data = pattern_bytes(10 * 1024 * 1024)
  let writer = new_native_buf_writer(path, 4096, NativeFileMode::Overwrite)
  writer.write_all(data)
  writer.close()
  let out = read_all_native(path, 16 * 1024)
  assert_eq(out.length(), data.length())
  assert_eq(out[0], data[0])
  assert_eq(out[out.length() - 1], data[data.length() - 1])
}

///|
test "native buffered roundtrip covers common sizes" {
  let sizes = [0, 1, 3, 4, 5, 64 * 1024, 1024 * 1024]
  for size in sizes {
    let path = native_test_path("native-buffered-roundtrip-\{size}.bin")
    let data = pattern_bytes(size)
    let capacity = if size <= 5 { 4 } else { 4096 }
    let writer = new_native_buf_writer(
      path,
      capacity,
      NativeFileMode::Overwrite,
    )
    writer.write_all(data)
    writer.close()
    assert_eq(read_all_native_buffered(path, capacity), data)
  }
}

///|
test "native buffered roundtrip handles 10mb" {
  let path = native_test_path("native-buffered-roundtrip-10mb.bin")
  let data = pattern_bytes(10 * 1024 * 1024)
  let writer = new_native_buf_writer(path, 8192, NativeFileMode::Overwrite)
  writer.write_all(data)
  writer.close()

  let out = read_all_native_buffered(path, 4096)
  assert_eq(out.length(), data.length())
  assert_eq(out[0], data[0])
  assert_eq(out[4096], data[4096])
  assert_eq(out[out.length() - 1], data[data.length() - 1])
}
