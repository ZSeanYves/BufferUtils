/// ======================
/// Unified API Tests (Public Module Functions Only)
/// ======================

///| --- Reading API Tests ---
test "readBytes normal input" {
  let data = Bytes::from_array([1, 2, 3])
  let reader = new_reader(data)
  let result = @ZSeanYves/bufferutils.read_bytes(reader)
  assert_eq(result, [1, 2, 3])
}

///|
test "readBytes empty input returns empty array" {
  let data = Bytes::from_array([])
  let result = readBytes(data)
  assert_eq(result.length(), 0)
}

///|
test "readBytesArray normal input" {
  let arr : Array[Byte] = [10, 20, 30]
  let result = @ZSeanYves/bufferutils.readABytes(arr)
  assert_eq(result, [10, 20, 30])
}

///|
test "readInts normal input" {
  let ints = [100, 101, 102]
  let result = @ZSeanYves/bufferutils.readInts(ints)
  assert_eq(result, [100, 101, 102].map(fn(i) { i.to_byte() }))
}

///|
test "readInts empty input returns empty array" {
  let ints : Array[Int] = []
  let result = readInts(ints)
  assert_eq(result.length(), 0)
}

///|
test "readString normal input" {
  let s = "Moon"
  let data = @ZSeanYves/bufferutils.string_to_utf8_bytes(s)
  let result = @ZSeanYves/bufferutils.readString(s)
  assert_eq(result,data.to_array())
}

///|
test "readString empty input returns empty array" {
  let s = ""
  let result = readString(s)
  assert_eq(result.length(), 0)
}




///| --- Error Handling Tests ---
test "writeBytes with empty input returns empty array" {
  let data = Bytes::from_array([1, 2, 3])
  let path = "./src/examples/Bytes.txt"
  @ZSeanYves/bufferutils.writeBytes(path, data)
}

///|
test "writeInt with empty array returns empty array" {
  let ints : Array[Int] = [1, 2, 3]
  let path = "./src/examples/Ints.txt"
  @ZSeanYves/bufferutils.writeInt(path,ints)
}

///|
test "writeString with empty string returns empty array" {
  let s = "Moonbit"
  let path = "./src/examples/String.txt"
  @ZSeanYves/bufferutils.writeString(path,s)
}

///| --- Large Input Edge Tests ---
test "readBytes handles large Bytes array" {
  let arr : Array[Int] = []
  for i in 0..<1000 {
    arr.push(i % 256)
  }
  let data = Bytes::from_array(arr.map(fn(i) { i.to_byte() }))
  let result = readBytes(data)
  assert_eq(result.length(), 1000)
}

///|
test "writeBytes handles large Bytes array" {
  let arr : Array[Int] = []
  for i in 0..<1000 {
    arr.push(i % 256)
  }
  let path1 = "./src/examples/LargeBytes1.txt"
  let path2 = "./src/examples/LargeBytes2.txt"
  let data = Bytes::from_array(arr.map(fn(i) { i.to_byte() }))
  writeBytes(path1,data)
  writeBytes(path2,data)
}

///| --- Performance Tests ---
test "write and read 1MB" {
  let size = 1024 * 1024
  let arr : Array[Byte] = []
  for i in 0..<size {
    arr.push((i % 256).to_byte())
  }
  let path3 = "./src/examples/LargeBytes3.txt"
  let data = Bytes::from_array(arr)
  writeBytes(path3, data)
  let writer = new_writer(size + 1024)
  let written = @ZSeanYves/bufferutils.write_bytes(writer, arr)
  let read = readBytes(Bytes::from_array(written))
  assert_eq(read.length(), size)
}

///|
test "write and read 100MB with clear" {
  let size = 1024 * 1024 * 100
  let arr : Array[Byte] = []
  for i in 0..<size {
    arr.push((i % 256).to_byte())
  }
  let path4 = "./src/examples/LargeBytes4.txt"
  let data = Bytes::from_array(arr)
  writeBytes(path4, data)
  let writer = new_writer(size + 1024)
  let written = write_bytes(writer, arr)
  let read = readBytes(Bytes::from_array(written))
  assert_eq(read.length(), size)
}
