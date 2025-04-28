/// ======================
/// Unified API Tests (Public Module Functions Only)
/// ======================

/// --- Reading API Tests ---

test "readBytes normal input" {
  let data = Bytes::from_array([1, 2, 3])
  let result = readBytes(data)
  assert_eq!(result, [1, 2, 3])
}

test "readBytes empty input returns empty array" {
  let data = Bytes::from_array([])
  let result = readBytes(data)
  assert_eq!(result.length(), 0)
}

test "readBytesArray normal input" {
  let arr: Array[Byte] = [10, 20, 30]
  let result = readBytesArray(arr)
  assert_eq!(result, [10, 20, 30])
}

test "readInts normal input" {
  let ints = [100, 101, 102]
  let result = readInts(ints)
  assert_eq!(result, [100, 101, 102])
}

test "readInts empty input returns empty array" {
  let ints: Array[Int] = []
  let result = readInts(ints)
  assert_eq!(result.length(), 0)
}

test "readString normal input" {
  let s = "Moon"
  let result = readString(s)
  assert_eq!(result.length(), 4)
}

test "readString empty input returns empty array" {
  let s = ""
  let result = readString(s)
  assert_eq!(result.length(), 0)
}

/// --- Writing API Tests ---

test "writeBytes normal Bytes input" {
  let data = Bytes::from_array([4, 5, 6])
  let result = writeBytes(data)
  assert_eq!(result, [4, 5, 6])
}

test "writeBytesClear normal Bytes input" {
  let data = Bytes::from_array([7, 8])
  let result = writeBytesClear(data)
  assert_eq!(result, [7, 8])
}

test "writeInt normal Int array" {
  let ints = [200, 201, 202]
  let result = writeInt(ints)
  assert_eq!(result, [200, 201, 202])
}

test "writeIntClear normal Int array" {
  let ints = [203, 204]
  let result = writeIntClear(ints)
  assert_eq!(result, [203, 204])
}

test "writeString normal String input" {
  let s = "Bit"
  let result = writeString(s)
  assert_eq!(result.length(), 3)
}

test "writeStringClear normal String input" {
  let s = "Lang"
  let result = writeStringClear(s)
  assert_eq!(result.length(), 4)
}

/// --- Error Handling Tests ---

test "writeBytes with empty input returns empty array" {
  let data = Bytes::from_array([])
  let result = writeBytes(data)
  assert_eq!(result.length(), 0)
}

test "writeInt with empty array returns empty array" {
  let ints: Array[Int] = []
  let result = writeInt(ints)
  assert_eq!(result.length(), 0)
}

test "writeString with empty string returns empty array" {
  let s = ""
  let result = writeString(s)
  assert_eq!(result.length(), 0)
}

/// --- Large Input Edge Tests ---
test "readBytes handles large Bytes array" {
  let arr:Array[Int] = []
  for i in 0..<1000 {
    arr.push(i % 256)
  }
  let data = Bytes::from_array(arr.map(fn(i) { i.to_byte() }))
  let result = readBytes(data)
  assert_eq!(result.length(), 1000)
}

test "writeBytes handles large Bytes array" {
  let arr:Array[Int] = []
  for i in 0..<1000 {
    arr.push(i % 256)
  }
  let data = Bytes::from_array(arr.map(fn(i) { i.to_byte() }))
  let result1 = writeBytes(data)
  let result2=writeBytes(data,cap=1000)
  assert_eq!(result1.length(), 0)
  assert_eq!(result2.length(), 1000)
}

