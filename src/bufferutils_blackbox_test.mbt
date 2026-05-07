///|
/// Reader tests
test "reader reads all bytes from non-empty input" {
  let reader = new_reader(Bytes::from_array([1, 2, 3]))
  assert_eq(reader.read_remaining(), [1, 2, 3])
  assert_eq(reader.is_empty(), true)
}

///|
test "read_byte advances position" {
  let reader = new_reader(Bytes::from_array([10, 20]))
  assert_eq(reader.position(), 0)
  assert_eq(reader.read_byte(), 10)
  assert_eq(reader.position(), 1)
}

///|
test "peek_byte does not advance position" {
  let reader = new_reader(Bytes::from_array([7, 8]))
  assert_eq(reader.peek_byte(), 7)
  assert_eq(reader.position(), 0)
  assert_eq(reader.read_byte(), 7)
}

///|
test "single byte reader can be consumed exactly once" {
  let reader = new_reader(Bytes::from_array([42]))
  assert_eq(reader.read_byte(), 42)
  let result = try? reader.read_byte()
  assert_eq(result is Err(_), true)
}

///|
test "read_exact zero bytes is allowed" {
  let reader = new_reader(Bytes::from_array([1, 2]))
  assert_eq(reader.read_exact(0), [])
  assert_eq(reader.position(), 0)
}

///|
test "read_exact returns requested bytes" {
  let reader = new_reader(Bytes::from_array([1, 2, 3, 4]))
  assert_eq(reader.read_exact(3), [1, 2, 3])
  assert_eq(reader.position(), 3)
}

///|
test "read_exact underflow when remaining bytes are insufficient" {
  let reader = new_reader(Bytes::from_array([1, 2]))
  let result = try? reader.read_exact(3)
  assert_eq(result is Err(_), true)
}

///|
test "skip advances position within bounds" {
  let reader = new_reader(Bytes::from_array([1, 2, 3, 4]))
  reader.skip(2)
  assert_eq(reader.position(), 2)
  assert_eq(reader.read_byte(), 3)
}

///|
test "skip zero keeps reader position unchanged" {
  let reader = new_reader(Bytes::from_array([1, 2]))
  reader.skip(0)
  assert_eq(reader.position(), 0)
  assert_eq(reader.read_byte(), 1)
}

///|
test "skip beyond end raises underflow" {
  let reader = new_reader(Bytes::from_array([1, 2]))
  let result = try? reader.skip(3)
  assert_eq(result is Err(_), true)
}

///|
test "skip negative raises invalid input" {
  let reader = new_reader(Bytes::from_array([1, 2]))
  let result = try? reader.skip(-1)
  assert_eq(result is Err(_), true)
}

///|
test "rewind resets reader position" {
  let reader = new_reader(Bytes::from_array([1, 2, 3]))
  ignore(reader.read_byte())
  ignore(reader.read_byte())
  reader.rewind()
  assert_eq(reader.position(), 0)
  assert_eq(reader.read_byte(), 1)
}

///|
test "empty buffer read raises underflow" {
  let reader = new_reader(Bytes::from_array([]))
  let result = try? reader.read_byte()
  assert_eq(result is Err(_), true)
}

///|
test "remaining never returns negative" {
  let reader = new_reader(Bytes::from_array([1]))
  ignore(reader.read_byte())
  assert_eq(reader.remaining(), 0)
}

///|
test "read_remaining consumes remaining bytes" {
  let reader = new_reader(Bytes::from_array([1, 2, 3]))
  ignore(reader.read_byte())
  assert_eq(reader.read_remaining(), [2, 3])
  assert_eq(reader.position(), 3)
  assert_eq(reader.is_empty(), true)
}

///|
test "reader handles 10000 bytes when reading byte by byte" {
  let data : Array[Byte] = []
  for i in 0..<10000 {
    data.push((i % 256).to_byte())
  }
  let reader = new_reader(Bytes::from_array(data))
  let out : Array[Byte] = []
  for _ in 0..<10000 {
    out.push(reader.read_byte())
  }
  assert_eq(out.length(), 10000)
  assert_eq(out[0], 0)
  assert_eq(out[9999], (9999 % 256).to_byte())
}

///|
test "reader peek_byte repeated calls do not advance position" {
  let reader = new_reader(Bytes::from_array([9, 8, 7]))
  assert_eq(reader.peek_byte(), 9)
  assert_eq(reader.peek_byte(), 9)
  assert_eq(reader.position(), 0)
}

///|
test "reader skip to end then read_byte raises underflow" {
  let reader = new_reader(Bytes::from_array([1, 2, 3]))
  reader.skip(3)
  let result = try? reader.read_byte()
  assert_eq(result is Err(_), true)
}

///|
test "reader read_exact can consume exact remaining bytes" {
  let reader = new_reader(Bytes::from_array([1, 2, 3, 4]))
  ignore(reader.read_byte())
  assert_eq(reader.read_exact(3), [2, 3, 4])
  assert_eq(reader.remaining(), 0)
}

///|
test "reader read_remaining second call returns empty array" {
  let reader = new_reader(Bytes::from_array([1, 2]))
  assert_eq(reader.read_remaining(), [1, 2])
  assert_eq(reader.read_remaining(), [])
}

///|
test "reader rewind after eof allows rereading" {
  let reader = new_reader(Bytes::from_array([1, 2, 3]))
  assert_eq(reader.read_remaining(), [1, 2, 3])
  reader.rewind()
  assert_eq(reader.read_exact(3), [1, 2, 3])
}

///|
/// Writer tests
test "new_fixed_writer succeeds with positive capacity" {
  let writer = new_fixed_writer(4)
  assert_eq(writer.capacity(), 4)
  assert_eq(writer.remaining_capacity(), 4)
}

///|
test "new_growing_writer succeeds with positive capacity" {
  let writer = new_growing_writer(4)
  assert_eq(writer.capacity(), 4)
  writer.reserve(5)
  assert_eq(writer.capacity() >= 5, true)
}

///|
test "new_fixed_writer zero capacity raises invalid capacity" {
  let result = try? new_fixed_writer(0)
  assert_eq(result is Err(_), true)
}

///|
test "new_growing_writer zero capacity raises invalid capacity" {
  let result = try? new_growing_writer(0)
  assert_eq(result is Err(_), true)
}

///|
test "new_writer remains fixed-capacity by default" {
  let writer = new_writer(4)
  writer.write_all([1, 2, 3, 4])
  let result = try? writer.write_byte(5)
  assert_eq(result is Err(_), true)
}

///|
test "new_writer negative capacity raises invalid capacity" {
  let result = try? new_writer(-1)
  assert_eq(result is Err(_), true)
}

///|
test "fixed writer write_byte appends data" {
  let writer = new_fixed_writer(2)
  writer.write_byte(1)
  assert_eq(writer.flush_to_bytes(), [1])
  assert_eq(writer.len(), 1)
}

///|
test "fixed writer write_all appends data atomically" {
  let writer = new_fixed_writer(4)
  writer.write_all([1, 2])
  writer.write_all([3, 4])
  assert_eq(writer.flush_to_bytes(), [1, 2, 3, 4])
}

///|
test "fixed writer overflows on write_byte after full capacity" {
  let writer = new_fixed_writer(1)
  writer.write_byte(1)
  let result = try? writer.write_byte(2)
  assert_eq(result is Err(_), true)
}

///|
test "fixed writer write_all overflow raises error" {
  let writer = new_fixed_writer(2)
  let result = try? writer.write_all([1, 2, 3])
  assert_eq(result is Err(_), true)
}

///|
test "fixed writer write_all overflow does not partially write" {
  let writer = new_fixed_writer(3)
  writer.write_all([1, 2])
  let result = try? writer.write_all([3, 4])
  assert_eq(result is Err(_), true)
  assert_eq(writer.flush_to_bytes(), [1, 2])
}

///|
test "flush_to_bytes returns current bytes without clearing" {
  let writer = new_fixed_writer(4)
  writer.write_all([9, 8])
  assert_eq(writer.flush_to_bytes(), [9, 8])
  assert_eq(writer.len(), 2)
}

///|
test "reserve zero does not change writer state" {
  let writer = new_fixed_writer(4)
  writer.write_all([1, 2])
  writer.reserve(0)
  assert_eq(writer.capacity(), 4)
  assert_eq(writer.flush_to_bytes(), [1, 2])
}

///|
test "clear resets fixed writer state" {
  let writer = new_fixed_writer(4)
  writer.write_all([1, 2, 3])
  writer.clear()
  assert_eq(writer.len(), 0)
  assert_eq(writer.remaining_capacity(), 4)
  assert_eq(writer.is_empty(), true)
}

///|
test "fixed writer remaining capacity reaches zero when full" {
  let writer = new_fixed_writer(2)
  writer.write_all([1, 2])
  assert_eq(writer.remaining_capacity(), 0)
}

///|
test "fixed writer reserve beyond capacity raises overflow" {
  let writer = new_fixed_writer(2)
  writer.write_all([1])
  let result = try? writer.reserve(2)
  assert_eq(result is Err(_), true)
}

///|
test "fixed writer ensure_capacity beyond capacity raises overflow" {
  let writer = new_fixed_writer(2)
  let result = try? writer.ensure_capacity(3)
  assert_eq(result is Err(_), true)
}

///|
test "growing writer expands on write_byte" {
  let writer = new_growing_writer(1)
  writer.write_byte(1)
  writer.write_byte(2)
  assert_eq(writer.capacity() >= 2, true)
  assert_eq(writer.flush_to_bytes(), [1, 2])
}

///|
test "growing writer expands on write_all" {
  let writer = new_growing_writer(2)
  writer.write_all([1, 2, 3, 4, 5])
  assert_eq(writer.capacity() >= 5, true)
  assert_eq(writer.flush_to_bytes(), [1, 2, 3, 4, 5])
}

///|
test "growing writer preserves existing data across expansion" {
  let writer = new_growing_writer(2)
  writer.write_all([10, 20])
  writer.write_all([30, 40, 50])
  assert_eq(writer.flush_to_bytes(), [10, 20, 30, 40, 50])
}

///|
test "growing writer reserve increases capacity when needed" {
  let writer = new_growing_writer(2)
  writer.write_all([1, 2])
  let before = writer.capacity()
  writer.reserve(10)
  assert_eq(writer.capacity() > before, true)
  assert_eq(writer.capacity() >= 12, true)
}

///|
test "growing writer ensure_capacity increases capacity when needed" {
  let writer = new_growing_writer(2)
  writer.ensure_capacity(10)
  assert_eq(writer.capacity() >= 10, true)
}

///|
test "growing writer clear keeps expanded capacity" {
  let writer = new_growing_writer(2)
  writer.write_all([1, 2, 3, 4, 5])
  let grown_capacity = writer.capacity()
  writer.clear()
  assert_eq(writer.len(), 0)
  assert_eq(writer.capacity(), grown_capacity)
}

///|
test "reserve negative raises invalid input" {
  let writer = new_fixed_writer(2)
  let result = try? writer.reserve(-1)
  assert_eq(result is Err(_), true)
}

///|
test "ensure_capacity negative raises invalid input" {
  let writer = new_fixed_writer(2)
  let result = try? writer.ensure_capacity(-1)
  assert_eq(result is Err(_), true)
}

///|
test "write_all empty input does not change writer state" {
  let writer = new_fixed_writer(2)
  writer.write_all([])
  assert_eq(writer.len(), 0)
  assert_eq(writer.flush_to_bytes(), [])
}

///|
test "growing writer handles large write" {
  let writer = new_growing_writer(4)
  let data : Array[Byte] = []
  for i in 0..<10000 {
    data.push((i % 256).to_byte())
  }
  writer.write_all(data)
  let out = writer.flush_to_bytes()
  assert_eq(out.length(), 10000)
  assert_eq(out[0], 0)
  assert_eq(out[9999], (9999 % 256).to_byte())
}

///|
test "growing writer handles repeated small writes" {
  let writer = new_growing_writer(2)
  for i in 0..<32 {
    writer.write_byte((i % 256).to_byte())
  }
  let out = writer.flush_to_bytes()
  assert_eq(out.length(), 32)
  assert_eq(out[0], 0)
  assert_eq(out[31], 31)
}

///|
test "fixed writer can be filled exactly to capacity" {
  let writer = new_fixed_writer(4)
  writer.write_all([1, 2, 3, 4])
  assert_eq(writer.len(), 4)
  assert_eq(writer.remaining_capacity(), 0)
}

///|
test "fixed writer raises overflow after exact fill" {
  let writer = new_fixed_writer(2)
  writer.write_all([1, 2])
  let result = try? writer.write_byte(3)
  assert_eq(result is Err(_), true)
}

///|
test "growing writer expands from tiny capacity to 10000 bytes" {
  let writer = new_growing_writer(1)
  let data : Array[Byte] = []
  for i in 0..<10000 {
    data.push((i % 256).to_byte())
  }
  writer.write_all(data)
  assert_eq(writer.capacity() >= 10000, true)
  assert_eq(writer.len(), 10000)
}

///|
test "growing writer reserve never shrinks capacity" {
  let writer = new_growing_writer(2)
  writer.reserve(10)
  let grown = writer.capacity()
  writer.reserve(1)
  assert_eq(writer.capacity(), grown)
}

///|
test "ensure_capacity below current capacity keeps capacity unchanged" {
  let writer = new_growing_writer(4)
  writer.ensure_capacity(16)
  let grown = writer.capacity()
  writer.ensure_capacity(8)
  assert_eq(writer.capacity(), grown)
}

///|
test "fixed writer clear keeps capacity unchanged" {
  let writer = new_fixed_writer(4)
  writer.write_all([1, 2, 3, 4])
  writer.clear()
  assert_eq(writer.capacity(), 4)
}

///|
/// Convert tests
test "bytes_to_array converts bytes to array" {
  let data = Bytes::from_array([1, 2, 3])
  assert_eq(bytes_to_array(data), [1, 2, 3])
}

///|
test "array_to_bytes converts array to bytes" {
  let data : Array[Byte] = [4, 5, 6]
  assert_eq(array_to_bytes(data), Bytes::from_array([4, 5, 6]))
}

///|
test "ints_to_bytes converts valid integers" {
  assert_eq(ints_to_bytes([0, 127, 255]), [0, 127, 255])
}

///|
test "ints_to_bytes rejects negative integers" {
  let result = try? ints_to_bytes([-1])
  assert_eq(result is Err(_), true)
}

///|
test "ints_to_bytes rejects values above 255" {
  let result = try? ints_to_bytes([256])
  assert_eq(result is Err(_), true)
}

///|
test "ascii string round-trip" {
  let bytes = string_to_utf8_bytes("MoonBit")
  assert_eq(utf8_bytes_to_string(bytes), "MoonBit")
}

///|
test "chinese string round-trip" {
  let bytes = string_to_utf8_bytes("测试")
  assert_eq(utf8_bytes_to_string(bytes), "测试")
}

///|
test "emoji string round-trip" {
  let bytes = string_to_utf8_bytes("👋🌍")
  assert_eq(utf8_bytes_to_string(bytes), "👋🌍")
}

///|
test "empty string utf8 round-trip" {
  let bytes = string_to_utf8_bytes("")
  assert_eq(utf8_bytes_to_string(bytes), "")
}

///|
test "invalid utf8 raises decode error" {
  let bytes = Bytes::from_array([0xE4, 0x7F])
  let result = try? utf8_bytes_to_string(bytes)
  assert_eq(result is Err(_), true)
}

///|
test "ints_to_bytes accepts 0 and 255" {
  assert_eq(ints_to_bytes([0, 255]), [0, 255])
}

///|
/// Split tests
test "split_bytes normal delimiter" {
  let bytes = Bytes::from_array([1, 2, 0, 3, 4])
  assert_eq(split_bytes(bytes, (0).to_byte()), [[1, 2], [3, 4]])
}

///|
test "split_bytes with no delimiter returns single segment" {
  let bytes = Bytes::from_array([1, 2, 3])
  assert_eq(split_bytes(bytes, (0).to_byte()), [[1, 2, 3]])
}

///|
test "split_bytes preserves leading empty segment" {
  let bytes = Bytes::from_array([0, 1, 2])
  assert_eq(split_bytes(bytes, (0).to_byte()), [[], [1, 2]])
}

///|
test "split_bytes preserves trailing empty segment" {
  let bytes = Bytes::from_array([1, 2, 0])
  assert_eq(split_bytes(bytes, (0).to_byte()), [[1, 2], []])
}

///|
test "split_bytes preserves repeated delimiters" {
  let bytes = Bytes::from_array([1, 0, 0, 2])
  assert_eq(split_bytes(bytes, (0).to_byte()), [[1], [], [2]])
}

///|
test "split_bytes on empty input returns single empty segment" {
  let bytes = Bytes::from_array([])
  assert_eq(split_bytes(bytes, (0).to_byte()), [[]])
}

///|
test "split_bytes all delimiters preserves all empty segments" {
  let bytes = Bytes::from_array([0, 0, 0])
  assert_eq(split_bytes(bytes, (0).to_byte()), [[], [], [], []])
}

///|
/// MemorySource tests
test "empty memory source returns zero bytes" {
  let source = new_memory_source(Bytes::from_array([]))
  let dst = Array::makei(4, fn(_i) { (0).to_byte() })
  assert_eq(source.read(dst), 0)
  assert_eq(source.remaining(), 0)
}

///|
test "memory source reads less than destination length" {
  let source = new_memory_source(Bytes::from_array([1, 2]))
  let dst = Array::makei(4, fn(_i) { (0).to_byte() })
  let count = source.read(dst)
  assert_eq(count, 2)
  assert_eq(dst[0], 1)
  assert_eq(dst[1], 2)
  assert_eq(source.remaining(), 0)
}

///|
test "memory source supports multiple reads" {
  let source = new_memory_source(Bytes::from_array([1, 2, 3, 4]))
  let first = Array::makei(2, fn(_i) { (0).to_byte() })
  let second = Array::makei(3, fn(_i) { (0).to_byte() })
  assert_eq(source.read(first), 2)
  assert_eq(first, [1, 2])
  assert_eq(source.read(second), 2)
  assert_eq(second[0], 3)
  assert_eq(second[1], 4)
  assert_eq(source.read(second), 0)
}

///|
test "memory source read_to_end returns remaining bytes" {
  let source = new_memory_source(Bytes::from_array([1, 2, 3, 4]))
  let first = Array::makei(1, fn(_i) { (0).to_byte() })
  ignore(source.read(first))
  assert_eq(source.read_to_end(), [2, 3, 4])
  assert_eq(source.read_to_end(), [])
}

///|
test "memory source rewind resets position" {
  let source = new_memory_source(Bytes::from_array([5, 6, 7]))
  let dst = Array::makei(2, fn(_i) { (0).to_byte() })
  ignore(source.read(dst))
  assert_eq(source.position(), 2)
  source.rewind()
  assert_eq(source.position(), 0)
  assert_eq(source.remaining(), 3)
}

///|
test "memory source can read 10000 bytes in chunks" {
  let data : Array[Byte] = []
  for i in 0..<10000 {
    data.push((i % 256).to_byte())
  }
  let source = new_memory_source(Bytes::from_array(data))
  let chunk = Array::makei(128, fn(_i) { (0).to_byte() })
  let out : Array[Byte] = []
  while true {
    let count = source.read(chunk)
    if count == 0 {
      break
    }
    for i in 0..<count {
      out.push(chunk[i])
    }
  }
  assert_eq(out.length(), 10000)
  assert_eq(out[0], 0)
  assert_eq(out[9999], (9999 % 256).to_byte())
}

///|
/// MemorySink tests
test "new memory sink is empty" {
  let sink = new_memory_sink()
  assert_eq(sink.is_empty(), true)
  assert_eq(sink.len(), 0)
}

///|
test "memory sink appends bytes across writes" {
  let sink = new_memory_sink()
  sink.write([1, 2])
  sink.write([3, 4])
  assert_eq(sink.len(), 4)
  assert_eq(sink.to_bytes(), [1, 2, 3, 4])
}

///|
test "memory sink flush is a no-op" {
  let sink = new_memory_sink()
  sink.write([9, 8])
  sink.flush()
  assert_eq(sink.to_bytes(), [9, 8])
}

///|
test "memory sink clear removes all data" {
  let sink = new_memory_sink()
  sink.write([1, 2, 3])
  sink.clear()
  assert_eq(sink.is_empty(), true)
  assert_eq(sink.to_bytes(), [])
}

///|
/// BufReader tests
test "new_buf_reader rejects non-positive capacity" {
  let source = new_memory_source(Bytes::from_array([1]))
  let result = try? new_buf_reader(source, 0)
  assert_eq(result is Err(_), true)
}

///|
test "buf reader read_byte crosses refill boundaries" {
  let source = new_memory_source(Bytes::from_array([1, 2, 3, 4, 5]))
  let reader = new_buf_reader(source, 2)
  assert_eq(reader.read_byte(), 1)
  assert_eq(reader.read_byte(), 2)
  assert_eq(reader.read_byte(), 3)
  assert_eq(reader.read_byte(), 4)
  assert_eq(reader.read_byte(), 5)
  assert_eq(reader.is_eof(), true)
}

///|
test "buf reader read_exact smaller than capacity" {
  let source = new_memory_source(Bytes::from_array([1, 2, 3]))
  let reader = new_buf_reader(source, 4)
  assert_eq(reader.read_exact(2), [1, 2])
}

///|
test "buf reader read_exact larger than capacity" {
  let source = new_memory_source(Bytes::from_array([1, 2, 3, 4, 5]))
  let reader = new_buf_reader(source, 2)
  assert_eq(reader.read_exact(5), [1, 2, 3, 4, 5])
}

///|
test "buf reader read_exact beyond remaining raises underflow" {
  let source = new_memory_source(Bytes::from_array([1, 2]))
  let reader = new_buf_reader(source, 2)
  let result = try? reader.read_exact(3)
  assert_eq(result is Err(_), true)
}

///|
test "buf reader read_to_end reads all data" {
  let source = new_memory_source(Bytes::from_array([1, 2, 3, 4]))
  let reader = new_buf_reader(source, 2)
  assert_eq(reader.read_to_end(), [1, 2, 3, 4])
  assert_eq(reader.is_eof(), true)
}

///|
test "buf reader read_to_end handles inputs larger than capacity" {
  let source = new_memory_source(Bytes::from_array([1, 2, 3, 4, 5, 6, 7]))
  let reader = new_buf_reader(source, 3)
  let out = reader.read_to_end()
  assert_eq(out.length(), 7)
  assert_eq(out[0], 1)
  assert_eq(out[6], 7)
}

///|
test "buf reader with capacity one still reads to end" {
  let source = new_memory_source(Bytes::from_array([1, 2, 3, 4]))
  let reader = new_buf_reader(source, 1)
  assert_eq(reader.read_to_end(), [1, 2, 3, 4])
}

///|
test "buf reader with capacity larger than input still reads correctly" {
  let source = new_memory_source(Bytes::from_array([1, 2, 3]))
  let reader = new_buf_reader(source, 16)
  assert_eq(reader.read_to_end(), [1, 2, 3])
}

///|
test "buf reader consume advances within buffered data" {
  let source = new_memory_source(Bytes::from_array([1, 2, 3, 4]))
  let reader = new_buf_reader(source, 4)
  assert_eq(reader.fill_buf(), 4)
  reader.consume(2)
  assert_eq(reader.buffered_len(), 2)
  assert_eq(reader.read_byte(), 3)
}

///|
test "buf reader consume negative raises invalid input" {
  let source = new_memory_source(Bytes::from_array([1, 2]))
  let reader = new_buf_reader(source, 2)
  ignore(reader.fill_buf())
  let result = try? reader.consume(-1)
  assert_eq(result is Err(_), true)
}

///|
test "buf reader consume zero is allowed" {
  let source = new_memory_source(Bytes::from_array([1, 2]))
  let reader = new_buf_reader(source, 2)
  ignore(reader.fill_buf())
  reader.consume(0)
  assert_eq(reader.buffered_len(), 2)
}

///|
test "buf reader consume beyond buffered length raises underflow" {
  let source = new_memory_source(Bytes::from_array([1, 2]))
  let reader = new_buf_reader(source, 2)
  ignore(reader.fill_buf())
  let result = try? reader.consume(3)
  assert_eq(result is Err(_), true)
}

///|
test "buf reader buffered_len never becomes negative" {
  let source = new_memory_source(Bytes::from_array([1]))
  let reader = new_buf_reader(source, 1)
  assert_eq(reader.buffered_len(), 0)
  ignore(reader.read_byte())
  assert_eq(reader.buffered_len(), 0)
}

///|
test "empty buf reader read_byte raises underflow" {
  let source = new_memory_source(Bytes::from_array([]))
  let reader = new_buf_reader(source, 2)
  let result = try? reader.read_byte()
  assert_eq(result is Err(_), true)
}

///|
/// BufWriter tests
test "new_buf_writer rejects non-positive capacity" {
  let sink = new_memory_sink()
  let result = try? new_buf_writer(sink, 0)
  assert_eq(result is Err(_), true)
}

///|
test "buf writer write_byte flushes into sink" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 2)
  writer.write_byte(1)
  writer.flush()
  let sink = writer.into_inner()
  assert_eq(sink.to_bytes(), [1])
}

///|
test "buf writer write_byte auto flushes when buffer fills" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 2)
  writer.write_byte(1)
  writer.write_byte(2)
  writer.write_byte(3)
  let sink = writer.into_inner()
  assert_eq(sink.to_bytes(), [1, 2, 3])
}

///|
test "buf writer write_all small chunk stays buffered until flush" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 8)
  writer.write_all([1, 2, 3])
  assert_eq(writer.buffered_len(), 3)
  let sink = writer.into_inner()
  assert_eq(sink.to_bytes(), [1, 2, 3])
}

///|
test "buf writer write_all large chunk can bypass buffer" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 2)
  writer.write_all([1, 2, 3, 4, 5])
  assert_eq(writer.buffered_len(), 0)
  let sink = writer.into_inner()
  assert_eq(sink.to_bytes(), [1, 2, 3, 4, 5])
}

///|
test "buf writer flush on empty buffer succeeds" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 2)
  writer.flush()
  assert_eq(writer.buffered_len(), 0)
}

///|
test "buf writer flush resets buffered length" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 4)
  writer.write_all([1, 2])
  writer.flush()
  assert_eq(writer.buffered_len(), 0)
}

///|
test "buf writer into_inner returns complete data" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 2)
  writer.write_all([1, 2, 3, 4, 5])
  let sink = writer.into_inner()
  assert_eq(sink.to_bytes(), [1, 2, 3, 4, 5])
}

///|
test "buf writer preserves order across small writes" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 3)
  writer.write_all([1])
  writer.write_all([2, 3])
  writer.write_all([4, 5])
  let sink = writer.into_inner()
  assert_eq(sink.to_bytes(), [1, 2, 3, 4, 5])
}

///|
test "buf writer handles large array writes" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 16)
  let data : Array[Byte] = []
  for i in 0..<4096 {
    data.push((i % 256).to_byte())
  }
  writer.write_all(data)
  let sink = writer.into_inner()
  let out = sink.to_bytes()
  assert_eq(out.length(), 4096)
  assert_eq(out[0], 0)
  assert_eq(out[4095], (4095 % 256).to_byte())
}

///|
test "buf writer with capacity one handles repeated writes" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 1)
  for i in 0..<8 {
    writer.write_byte((i % 256).to_byte())
  }
  let sink = writer.into_inner()
  assert_eq(sink.to_bytes(), [0, 1, 2, 3, 4, 5, 6, 7])
}

///|
test "buf writer multiple flushes preserve data" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 2)
  writer.write_all([1, 2])
  writer.flush()
  writer.flush()
  writer.write_all([3, 4])
  writer.flush()
  let sink = writer.into_inner()
  assert_eq(sink.to_bytes(), [1, 2, 3, 4])
}

///|
test "buf writer flush before into_inner keeps final data correct" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 2)
  writer.write_all([5, 6])
  writer.flush()
  let sink = writer.into_inner()
  assert_eq(sink.to_bytes(), [5, 6])
}

///|
test "buf writer ignores empty writes" {
  let sink = new_memory_sink()
  let writer = new_buf_writer(sink, 4)
  writer.write_all([])
  let sink = writer.into_inner()
  assert_eq(sink.to_bytes(), [])
}

///|
/// FileSink tests
test "new file sink rejects empty path" {
  let result = try? new_file_sink("")
  assert_eq(result is Err(_), true)
}

///|
test "new file sink starts with zero pending bytes" {
  let sink = new_file_sink(test_output_path("file_sink_empty.bin"))
  assert_eq(sink.pending_len(), 0)
}

///|
test "file sink write increases pending length" {
  let sink = new_file_sink(test_output_path("file_sink_pending.bin"))
  sink.write([1, 2, 3])
  assert_eq(sink.pending_len(), 3)
}

///|
test "file sink flush writes bytes to file" {
  let path = test_output_path("file_sink_flush.bin")
  let sink = new_file_sink(path)
  sink.write([1, 2, 3])
  sink.flush()
  let written = read_test_bytes(path)
  assert_eq(written, [1, 2, 3])
  assert_eq(sink.pending_len(), 0)
}

///|
test "file sink empty flush does not fail" {
  let path = test_output_path("file_sink_empty_flush.bin")
  let sink = new_file_sink(path)
  sink.flush()
  let written = read_test_bytes(path)
  assert_eq(written, [])
}

///|
test "file sink preserves order across multiple writes and flushes" {
  let path = test_output_path("file_sink_multiple_flushes.bin")
  let sink = new_file_sink(path)
  sink.write([1, 2])
  sink.flush()
  sink.write([3, 4])
  sink.flush()
  let written = read_test_bytes(path)
  assert_eq(written, [1, 2, 3, 4])
}

///|
test "file sink clear resets pending bytes and flush writes empty file" {
  let path = test_output_path("file_sink_clear.bin")
  let sink = new_file_sink(path)
  sink.write([9, 8, 7])
  sink.clear()
  assert_eq(sink.pending_len(), 0)
  sink.flush()
  let written = read_test_bytes(path)
  assert_eq(written, [])
}

///|
/// FileBufWriter tests
test "new file buf writer rejects non-positive capacity" {
  let result = try? new_file_buf_writer(
    test_output_path("file_writer_bad.bin"),
    0,
  )
  assert_eq(result is Err(_), true)
}

///|
test "new file buf writer rejects empty path" {
  let result = try? new_file_buf_writer("", 4)
  assert_eq(result is Err(_), true)
}

///|
test "file buf writer write_byte and flush writes correct file" {
  let path = test_output_path("file_writer_byte.bin")
  let writer = new_file_buf_writer(path, 2)
  writer.write_byte(65)
  writer.flush()
  let written = read_test_bytes(path)
  assert_eq(written, [65])
}

///|
test "file buf writer auto flushes when capacity is exceeded" {
  let path = test_output_path("file_writer_autoflush.bin")
  let writer = new_file_buf_writer(path, 2)
  writer.write_byte(1)
  writer.write_byte(2)
  writer.write_byte(3)
  writer.flush()
  let written = read_test_bytes(path)
  assert_eq(written, [1, 2, 3])
}

///|
test "file buf writer write_all small chunk flushes correctly" {
  let path = test_output_path("file_writer_small_chunk.bin")
  let writer = new_file_buf_writer(path, 8)
  writer.write_all([1, 2, 3])
  writer.flush()
  let written = read_test_bytes(path)
  assert_eq(written, [1, 2, 3])
}

///|
test "file buf writer write_all large chunk writes correctly" {
  let path = test_output_path("file_writer_large_chunk.bin")
  let writer = new_file_buf_writer(path, 2)
  writer.write_all([1, 2, 3, 4, 5])
  writer.flush()
  let written = read_test_bytes(path)
  assert_eq(written, [1, 2, 3, 4, 5])
}

///|
test "file buf writer preserves order across multiple small writes" {
  let path = test_output_path("file_writer_order.bin")
  let writer = new_file_buf_writer(path, 3)
  writer.write_all([1])
  writer.write_all([2, 3])
  writer.write_all([4, 5])
  writer.flush()
  let written = read_test_bytes(path)
  assert_eq(written, [1, 2, 3, 4, 5])
}

///|
test "file buf writer empty write does not change output" {
  let path = test_output_path("file_writer_empty_write.bin")
  let writer = new_file_buf_writer(path, 4)
  writer.write_all([])
  writer.flush()
  let written = read_test_bytes(path)
  assert_eq(written, [])
}

///|
test "file buf writer empty flush does not fail" {
  let path = test_output_path("file_writer_empty_flush.bin")
  let writer = new_file_buf_writer(path, 4)
  writer.flush()
  let written = read_test_bytes(path)
  assert_eq(written, [])
}

///|
test "file buf writer handles large array writes" {
  let path = test_output_path("file_writer_large_array.bin")
  let writer = new_file_buf_writer(path, 16)
  let data : Array[Byte] = []
  for i in 0..<4096 {
    data.push((i % 256).to_byte())
  }
  writer.write_all(data)
  writer.flush()
  let written = read_test_bytes(path)
  assert_eq(written.length(), 4096)
  assert_eq(written[0], 0)
  assert_eq(written[4095], (4095 % 256).to_byte())
}

///|
test "file buf writer and reader handle 10000 byte roundtrip" {
  let path = test_output_path("file_writer_reader_10000.bin")
  let writer = new_file_buf_writer(path, 32)
  let data : Array[Byte] = []
  for i in 0..<10000 {
    data.push((i % 256).to_byte())
  }
  writer.write_all(data)
  writer.flush()
  let reader = new_file_buf_reader(path, 64)
  let out = reader.read_to_end()
  assert_eq(out.length(), 10000)
  assert_eq(out[0], 0)
  assert_eq(out[9999], (9999 % 256).to_byte())
}

///|
test "file writer multiple flushes preserve accumulated file contents" {
  let path = test_output_path("file_writer_multiple_flushes.bin")
  let writer = new_file_buf_writer(path, 2)
  writer.write_all([1, 2])
  writer.flush()
  writer.flush()
  writer.write_all([3, 4, 5])
  writer.flush()
  let reader = new_file_buf_reader(path, 2)
  assert_eq(reader.read_to_end(), [1, 2, 3, 4, 5])
}

///|
test "file source empty file read_to_end returns empty array" {
  let path = test_output_path("file_source_empty_to_end.bin")
  write_test_bytes(path, [])
  let source = new_file_source(path)
  assert_eq(source.read_to_end(), [])
}

///|
test "file buf reader handles file size equal to capacity" {
  let path = test_output_path("file_reader_equal_capacity.bin")
  write_test_bytes(path, [1, 2, 3, 4])
  let reader = new_file_buf_reader(path, 4)
  assert_eq(reader.read_to_end(), [1, 2, 3, 4])
}

///|
test "file buf reader handles file size one larger than capacity" {
  let path = test_output_path("file_reader_capacity_plus_one.bin")
  write_test_bytes(path, [1, 2, 3, 4, 5])
  let reader = new_file_buf_reader(path, 4)
  assert_eq(reader.read_to_end(), [1, 2, 3, 4, 5])
}

///|
/// FileSource tests
test "new file source rejects empty path" {
  let result = try? new_file_source("")
  assert_eq(result is Err(_), true)
}

///|
test "new file source reports missing file" {
  let result = try? new_file_source(test_output_dir + "/missing-source.bin")
  assert_eq(result is Err(_), true)
}

///|
test "file source handles empty file snapshots" {
  let path = test_output_path("file_source_empty.bin")
  write_test_bytes(path, [])
  let source = new_file_source(path)
  assert_eq(source.len(), 0)
  assert_eq(source.position(), 0)
  assert_eq(source.remaining(), 0)
  let dst = Array::makei(2, fn(_i) { (0).to_byte() })
  assert_eq(source.read(dst), 0)
}

///|
test "file source single byte file reads correctly" {
  let path = test_output_path("file_source_single.bin")
  write_test_bytes(path, [99])
  let source = new_file_source(path)
  let dst = Array::makei(2, fn(_i) { (0).to_byte() })
  assert_eq(source.read(dst), 1)
  assert_eq(dst[0], 99)
  assert_eq(source.remaining(), 0)
}

///|
test "file source len position and remaining are correct" {
  let path = test_output_path("file_source_len.bin")
  write_test_bytes(path, [1, 2, 3, 4])
  let source = new_file_source(path)
  assert_eq(source.len(), 4)
  assert_eq(source.position(), 0)
  assert_eq(source.remaining(), 4)
  assert_eq(source.path(), path)
}

///|
test "file source supports chunked reads and eof" {
  let path = test_output_path("file_source_chunked.bin")
  write_test_bytes(path, [10, 20, 30, 40])
  let source = new_file_source(path)
  let first = Array::makei(2, fn(_i) { (0).to_byte() })
  let second = Array::makei(3, fn(_i) { (0).to_byte() })
  assert_eq(source.read(first), 2)
  assert_eq(first, [10, 20])
  assert_eq(source.position(), 2)
  assert_eq(source.remaining(), 2)
  assert_eq(source.read(second), 2)
  assert_eq(second[0], 30)
  assert_eq(second[1], 40)
  assert_eq(source.read(second), 0)
}

///|
test "file source read_to_end returns remaining bytes" {
  let path = test_output_path("file_source_to_end.bin")
  write_test_bytes(path, [1, 2, 3, 4, 5])
  let source = new_file_source(path)
  let dst = Array::makei(2, fn(_i) { (0).to_byte() })
  ignore(source.read(dst))
  assert_eq(source.read_to_end(), [3, 4, 5])
  assert_eq(source.remaining(), 0)
  assert_eq(source.read_to_end(), [])
}

///|
test "file source rewind allows rereading the snapshot" {
  let path = test_output_path("file_source_rewind.bin")
  write_test_bytes(path, [7, 8, 9])
  let source = new_file_source(path)
  let dst = Array::makei(2, fn(_i) { (0).to_byte() })
  ignore(source.read(dst))
  source.rewind()
  assert_eq(source.position(), 0)
  assert_eq(source.read_to_end(), [7, 8, 9])
}

///|
/// FileBufReader tests
test "new file buf reader rejects empty path" {
  let result = try? new_file_buf_reader("", 4)
  assert_eq(result is Err(_), true)
}

///|
test "new file buf reader rejects non-positive capacity" {
  let path = test_output_path("file_reader_bad_capacity.bin")
  write_test_bytes(path, [1])
  let result = try? new_file_buf_reader(path, 0)
  assert_eq(result is Err(_), true)
}

///|
test "new file buf reader reports missing file" {
  let result = try? new_file_buf_reader(
    test_output_dir + "/missing-reader.bin",
    4,
  )
  assert_eq(result is Err(_), true)
}

///|
test "file buf reader reads first byte" {
  let path = test_output_path("file_reader_first_byte.bin")
  write_test_bytes(path, [1, 2, 3])
  let reader = new_file_buf_reader(path, 2)
  assert_eq(reader.read_byte(), 1)
}

///|
test "file buf reader read_byte crosses refill boundaries" {
  let path = test_output_path("file_reader_refill.bin")
  write_test_bytes(path, [1, 2, 3, 4, 5])
  let reader = new_file_buf_reader(path, 2)
  assert_eq(reader.read_byte(), 1)
  assert_eq(reader.read_byte(), 2)
  assert_eq(reader.read_byte(), 3)
  assert_eq(reader.read_byte(), 4)
  assert_eq(reader.read_byte(), 5)
  assert_eq(reader.is_eof(), true)
}

///|
test "file buf reader read_exact smaller than capacity" {
  let path = test_output_path("file_reader_exact_small.bin")
  write_test_bytes(path, [1, 2, 3])
  let reader = new_file_buf_reader(path, 4)
  assert_eq(reader.read_exact(2), [1, 2])
}

///|
test "file buf reader read_exact larger than capacity" {
  let path = test_output_path("file_reader_exact_large.bin")
  write_test_bytes(path, [1, 2, 3, 4, 5])
  let reader = new_file_buf_reader(path, 2)
  assert_eq(reader.read_exact(5), [1, 2, 3, 4, 5])
}

///|
test "file buf reader read_exact beyond remaining raises underflow" {
  let path = test_output_path("file_reader_exact_underflow.bin")
  write_test_bytes(path, [1, 2])
  let reader = new_file_buf_reader(path, 2)
  let result = try? reader.read_exact(3)
  assert_eq(result is Err(_), true)
}

///|
test "file buf reader read_to_end reads complete file" {
  let path = test_output_path("file_reader_to_end.bin")
  write_test_bytes(path, [1, 2, 3, 4])
  let reader = new_file_buf_reader(path, 2)
  assert_eq(reader.read_to_end(), [1, 2, 3, 4])
  assert_eq(reader.is_eof(), true)
}

///|
test "file buf reader read_to_end handles large files" {
  let path = test_output_path("file_reader_large.bin")
  let data = pattern_bytes(4096)
  write_test_bytes(path, data)
  let reader = new_file_buf_reader(path, 32)
  let out = reader.read_to_end()
  assert_eq(out.length(), 4096)
  assert_eq(out[0], 0)
  assert_eq(out[4095], (4095 % 256).to_byte())
}

///|
test "file buf reader consume works within current buffer" {
  let path = test_output_path("file_reader_consume.bin")
  write_test_bytes(path, [1, 2, 3, 4])
  let reader = new_file_buf_reader(path, 4)
  assert_eq(reader.fill_buf(), 4)
  reader.consume(2)
  assert_eq(reader.buffered_len(), 2)
  assert_eq(reader.read_byte(), 3)
}

///|
test "file buf reader consume negative raises invalid input" {
  let path = test_output_path("file_reader_consume_negative.bin")
  write_test_bytes(path, [1, 2])
  let reader = new_file_buf_reader(path, 2)
  ignore(reader.fill_buf())
  let result = try? reader.consume(-1)
  assert_eq(result is Err(_), true)
}

///|
test "file buf reader consume beyond buffer raises underflow" {
  let path = test_output_path("file_reader_consume_underflow.bin")
  write_test_bytes(path, [1, 2])
  let reader = new_file_buf_reader(path, 2)
  ignore(reader.fill_buf())
  let result = try? reader.consume(3)
  assert_eq(result is Err(_), true)
}

///|
test "file buf reader empty file read_byte raises underflow" {
  let path = test_output_path("file_reader_empty.bin")
  write_test_bytes(path, [])
  let reader = new_file_buf_reader(path, 2)
  let result = try? reader.read_byte()
  assert_eq(result is Err(_), true)
}

///|
test "file buf reader empty file read_to_end returns empty array" {
  let path = test_output_path("file_reader_empty_to_end.bin")
  write_test_bytes(path, [])
  let reader = new_file_buf_reader(path, 2)
  assert_eq(reader.read_to_end(), [])
}

///|
/// File roundtrip tests
test "file writer and file reader roundtrip smaller than capacity" {
  let path = test_output_path("roundtrip_small.bin")
  let writer = new_file_buf_writer(path, 8)
  writer.write_all([1, 2, 3])
  writer.flush()
  let reader = new_file_buf_reader(path, 8)
  assert_eq(reader.read_to_end(), [1, 2, 3])
}

///|
test "file writer and file reader roundtrip equal to capacity" {
  let path = test_output_path("roundtrip_equal.bin")
  let writer = new_file_buf_writer(path, 4)
  writer.write_all([1, 2, 3, 4])
  writer.flush()
  let reader = new_file_buf_reader(path, 4)
  assert_eq(reader.read_to_end(), [1, 2, 3, 4])
}

///|
test "file writer and file reader roundtrip larger than capacity" {
  let path = test_output_path("roundtrip_large.bin")
  let writer = new_file_buf_writer(path, 2)
  writer.write_all([1, 2, 3, 4, 5])
  writer.flush()
  let reader = new_file_buf_reader(path, 2)
  assert_eq(reader.read_to_end(), [1, 2, 3, 4, 5])
}

///|
test "file writer and file reader roundtrip handles 4096 plus bytes" {
  let path = test_output_path("roundtrip_4096.bin")
  let writer = new_file_buf_writer(path, 32)
  let data : Array[Byte] = []
  for i in 0..<5000 {
    data.push((i % 256).to_byte())
  }
  writer.write_all(data)
  writer.flush()
  let reader = new_file_buf_reader(path, 64)
  let out = reader.read_to_end()
  assert_eq(out.length(), 5000)
  assert_eq(out[0], 0)
  assert_eq(out[4999], (4999 % 256).to_byte())
}
