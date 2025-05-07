/// ======================
/// Unified API Tests (Public Module Functions Only)
/// ======================

/// --- Reading API Tests ---

test "readBytes normal input" {
  let data = Bytes::from_array([1, 2, 3])
  let result = @ZSeanYves/bufferutils.readBytes(data)
  assert_eq!(result, [1, 2, 3])
}

test "readBytes empty input returns empty array" {
  let data = Bytes::from_array([])
  let result = @ZSeanYves/bufferutils.readBytes(data)
  assert_eq!(result.length(), 0)
}

test "readBytesArray normal input" {
  let arr: Array[Byte] = [10, 20, 30]
  let result = @ZSeanYves/bufferutils.readBytesArray(arr)
  assert_eq!(result, [10, 20, 30])
}

test "readInts normal input" {
  let ints = [100, 101, 102]
  let result = @ZSeanYves/bufferutils.readInts(ints)
  assert_eq!(result, [100, 101, 102])
}

test "readInts empty input returns empty array" {
  let ints: Array[Int] = []
  let result = @ZSeanYves/bufferutils.readInts(ints)
  assert_eq!(result.length(), 0)
}

test "readString normal input" {
  let s = "Moon"
  let result = @ZSeanYves/bufferutils.readString(s)
  assert_eq!(result.length(), 4)
}

test "readString empty input returns empty array" {
  let s = ""
  let result = @ZSeanYves/bufferutils.readString(s)
  assert_eq!(result.length(), 0)
}

/// --- Writing API Tests ---

test "writeBytes normal Bytes input" {
  let data = Bytes::from_array([4, 5, 6])
  let result = @ZSeanYves/bufferutils.writeBytes(data)
  assert_eq!(result, [4, 5, 6])
}

test "writeBytesClear normal Bytes input" {
  let data = Bytes::from_array([7, 8])
  let result = @ZSeanYves/bufferutils.writeBytesClear(data)
  assert_eq!(result, [7, 8])
}

test "writeInt normal Int array" {
  let ints = [200, 201, 202]
  let result = @ZSeanYves/bufferutils.writeInt(ints)
  assert_eq!(result, [200, 201, 202])
}

test "writeIntClear normal Int array" {
  let ints = [203, 204]
  let result = @ZSeanYves/bufferutils.writeIntClear(ints)
  assert_eq!(result, [203, 204])
}

test "writeString normal String input" {
  let s = "Bit"
  let result = @ZSeanYves/bufferutils.writeString(s)
  assert_eq!(result.length(), 3)
}

test "writeStringClear normal String input" {
  let s = "Lang"
  let result = @ZSeanYves/bufferutils.writeStringClear(s)
  assert_eq!(result.length(), 4)
}

/// --- Error Handling Tests ---

test "writeBytes with empty input returns empty array" {
  let data = Bytes::from_array([])
  let result = @ZSeanYves/bufferutils.writeBytes(data)
  assert_eq!(result.length(), 0)
}

test "writeInt with empty array returns empty array" {
  let ints: Array[Int] = []
  let result = @ZSeanYves/bufferutils.writeInt(ints)
  assert_eq!(result.length(), 0)
}

test "writeString with empty string returns empty array" {
  let s = ""
  let result = @ZSeanYves/bufferutils.writeString(s)
  assert_eq!(result.length(), 0)
}

/// --- Large Input Edge Tests ---
test "readBytes handles large Bytes array" {
  let arr:Array[Int] = []
  for i in 0..<1000 {
    arr.push(i % 256)
  }
  let data = Bytes::from_array(arr.map(fn(i) { i.to_byte() }))
  let result = @ZSeanYves/bufferutils.readBytes(data)
  assert_eq!(result.length(), 1000)
}

test "writeBytes handles large Bytes array" {
  let arr:Array[Int] = []
  for i in 0..<1000 {
    arr.push(i % 256)
  }
  let data = Bytes::from_array(arr.map(fn(i) { i.to_byte() }))
  let result1 = @ZSeanYves/bufferutils.writeBytes(data)
  let result2= @ZSeanYves/bufferutils.writeBytes(data,cap=1000)
  assert_eq!(result1.length(), 0)
  assert_eq!(result2.length(), 1000)
}

/// --- Performance Tests ---
test "performance test - write and read 1MB Bytes" {
  let size = 1024 * 1024  # 1MB
  let data = Bytes::from_array(Array::init(size, fn(i) { (i % 256).to_byte() }))

  let start_write = time::now()
  let written = @ZSeanYves/bufferutils.writeBytes(data)
  let write_time = time::now() - start_write

  let start_read = time::now()
  let read = @ZSeanYves/bufferutils.readBytes(Bytes::from_array(written))
  let read_time = time::now() - start_read

  inspect!("Write 1MB time", write_time)
  inspect!("Read 1MB time", read_time)
  assert_eq!(read.length(), size)
}

test "performance test - write and read 10MB Bytes" {
  let size = 10 * 1024 * 1024  # 10MB
  let data = Bytes::from_array(Array::init(size, fn(i) { (i % 256).to_byte() }))

  let start_write = time::now()
  let written = @ZSeanYves/bufferutils.writeBytes(data)
  let write_time = time::now() - start_write

  let start_read = time::now()
  let read = @ZSeanYves/bufferutils.readBytes(Bytes::from_array(written))
  let read_time = time::now() - start_read

  inspect!("Write 10MB time", write_time)
  inspect!("Read 10MB time", read_time)
  assert_eq!(read.length(), size)
}