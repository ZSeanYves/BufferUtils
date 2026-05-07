///|
test "fixed writer overflow keeps internal buffer unchanged" {
  let writer = new_fixed_writer(3)
  writer.write_all([1, 2])
  let before = writer.buf.copy()
  let result = try? writer.write_all([3, 4])
  assert_eq(result is Err(_), true)
  assert_eq(writer.buf, before)
  assert_eq(writer.pos, 2)
  assert_eq(writer.capacity, 3)
}

///|
test "growing writer reserve never shrinks internal capacity" {
  let writer = new_growing_writer(2)
  writer.reserve(10)
  let expanded = writer.capacity
  writer.reserve(1)
  assert_eq(writer.capacity, expanded)
}

///|
test "growing writer clear keeps expanded internal capacity" {
  let writer = new_growing_writer(2)
  writer.write_all(pattern_bytes(10))
  let expanded = writer.capacity
  writer.clear()
  assert_eq(writer.capacity, expanded)
  assert_eq(writer.pos, 0)
  assert_eq(writer.buf.length(), 0)
}

///|
test "buf reader fill_buf does not refill while buffered bytes remain" {
  let source = new_memory_source(Bytes::from_array([1, 2, 3, 4]))
  let reader = new_buf_reader(source, 2)
  assert_eq(reader.fill_buf(), 2)
  let source_pos = reader.source.position()
  reader.consume(1)
  assert_eq(reader.fill_buf(), 1)
  assert_eq(reader.source.position(), source_pos)
}

///|
test "buf reader large capacity performs a single source fill" {
  let source = new_memory_source(Bytes::from_array([1, 2, 3]))
  let reader = new_buf_reader(source, 8)
  assert_eq(reader.fill_buf(), 3)
  assert_eq(reader.end, 3)
  assert_eq(reader.source.position(), 3)
  assert_eq(reader.fill_buf(), 3)
  assert_eq(reader.source.position(), 3)
}

///|
test "buf reader capacity one refills one byte at a time" {
  let source = new_memory_source(Bytes::from_array([1, 2, 3]))
  let reader = new_buf_reader(source, 1)
  assert_eq(reader.fill_buf(), 1)
  assert_eq(reader.source.position(), 1)
  reader.consume(1)
  assert_eq(reader.fill_buf(), 1)
  assert_eq(reader.source.position(), 2)
}

///|
test "buf writer small writes stay buffered until flush" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 4)
  writer.write_all([1, 2])
  assert_eq(writer.buf, [1, 2])
  assert_eq(writer.sink.to_bytes(), [])
}

///|
test "buf writer large write bypasses local buffer when empty" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 2)
  writer.write_all([1, 2, 3])
  assert_eq(writer.buf.length(), 0)
  assert_eq(writer.sink.to_bytes(), [1, 2, 3])
}

///|
test "buf writer repeated flush does not duplicate sink bytes" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 2)
  writer.write_all([1, 2])
  writer.flush()
  let once = writer.sink.to_bytes()
  writer.flush()
  assert_eq(writer.sink.to_bytes(), once)
}

///|
test "file sink flush updates flushed_len over accumulated data" {
  let path = test_output_path("whitebox_file_sink_flush.bin")
  let sink = new_file_sink(path)
  sink.write([1, 2])
  assert_eq(sink.flushed_len, 0)
  sink.flush()
  assert_eq(sink.flushed_len, 2)
  sink.write([3])
  assert_eq(sink.pending_len(), 1)
  sink.flush()
  assert_eq(sink.flushed_len, 3)
  assert_eq(read_test_bytes(path), [1, 2, 3])
}

///|
test "file sink clear resets accumulated data and flushed_len" {
  let path = test_output_path("whitebox_file_sink_clear.bin")
  let sink = new_file_sink(path)
  sink.write([1, 2, 3])
  sink.flush()
  sink.clear()
  assert_eq(sink.data, [])
  assert_eq(sink.flushed_len, 0)
}

///|
test "file source snapshot ignores later file rewrites" {
  let path = test_output_path("whitebox_file_source_snapshot.bin")
  write_test_bytes(path, [1, 2, 3])
  let source = new_file_source(path)
  write_test_bytes(path, [9, 9, 9])
  assert_eq(source.read_to_end(), [1, 2, 3])
}

///|
test "file source rewind only resets snapshot position" {
  let path = test_output_path("whitebox_file_source_rewind.bin")
  write_test_bytes(path, [4, 5, 6])
  let source = new_file_source(path)
  let dst = Array::makei(2, fn(_i) { (0).to_byte() })
  ignore(source.read(dst))
  write_test_bytes(path, [7, 8, 9])
  source.rewind()
  assert_eq(source.read_to_end(), [4, 5, 6])
}

///|
test "file buf writer large write bypasses local buffer into sink" {
  let path = test_output_path("whitebox_file_buf_writer_bypass.bin")
  let writer = new_file_buf_writer(path, 2)
  writer.write_all([1, 2, 3, 4])
  assert_eq(writer.buffered_len(), 0)
  assert_eq(writer.sink.to_bytes(), [1, 2, 3, 4])
  assert_eq(writer.sink.pending_len(), 4)
}

///|
test "file buf writer flush clears local buffer and disk pending bytes" {
  let path = test_output_path("whitebox_file_buf_writer_flush.bin")
  let writer = new_file_buf_writer(path, 4)
  writer.write_all([1, 2])
  assert_eq(writer.buffered_len(), 2)
  writer.flush()
  assert_eq(writer.buffered_len(), 0)
  assert_eq(writer.sink.pending_len(), 0)
  assert_eq(read_test_bytes(path), [1, 2])
}
