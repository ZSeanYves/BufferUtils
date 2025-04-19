///黑盒测试
test "safe read from empty bytes" {
  let result = readBytes(Bytes::from_array([]))
  assert_eq!(result.length(), 0)
}

test "write from string and read back" {
  let input = "moonbit"
  let flushed = writeStringClear(input)
  let byte_array = []
  for i in 0..<input.length() {
    let b = input.charcode_at(i).to_byte()
    byte_array.push(b)
  }
  assert_eq!(flushed, byte_array)
}

test "write from int array and back" {
  let input = [65, 66, 67]
  let flushed = writeIntClear(input)
  assert_eq!(flushed, input)
}


///白盒测试
test "error raised on read from empty buffer" {
  let empty = Bytes::from_array([])
  let result = read_bytes?(empty)
  match result {
    Ok(_) => inspect!(false)
    Err(BufferError::Underflow(msg)) => inspect!(msg.contains("读取失败：到达缓冲区末尾"),content="true")
    Err(_) => inspect!(false)
  }
}

test "flush fails when buffer is empty" {
  let writer = new_writer!(16)
  let result = writer.flush?()
  match result {
    Ok(_) => inspect!(false)
    Err(BufferError::Flush(msg)) => inspect!(msg.contains("刷新失败"), content="true")
    Err(_) => inspect!(false)
  }
}

test "buffer reader reads one by one" {
  let data = Bytes::from_array([1, 2, 3])
  let reader = new_reader(data)
  let  out = []
  for i in 0..<3 {
    out.push(reader.read_byte!())
  }
  assert_eq!(out, [1, 2, 3])
}

///模拟外部调用
test "external call - write int data" {
  let data = [10, 20, 30]
  let result:Array[Int] = @ZSeanYves/bufferutils.writeInt(data)
  assert_eq!(result, [10, 20, 30])
}

test "external call - write string and clear" {
  let input = "abc"
  let result = @ZSeanYves/bufferutils.writeStringClear(input)
  assert_eq!(result, [97, 98, 99])  // "a" "b" "c"
}


test "external call - read from Bytes" {
  let data = Bytes::from_array([1, 2, 3])
  let result = @ZSeanYves/bufferutils.readBytes(data)
  assert_eq!(result, [1, 2, 3])
}

test "external call - read from Array[Byte]" {
  let result = @ZSeanYves/bufferutils.readBytesArray([4, 5, 6])
  assert_eq!(result, [4, 5, 6])
}

test "external call - read from Ints" {
  let result = @ZSeanYves/bufferutils.readInts([7, 8])
  assert_eq!(result, [7, 8])
}

test "external call - read from String" {
  let result = @ZSeanYves/bufferutils.readString("hi")
  let s = "hi"
  let a = s.charcode_at(0).to_byte()
  let b = s.charcode_at(1).to_byte()
  assert_eq!(result, [a,b])
}

test "external call - write and flush Bytes" {
  let result = @ZSeanYves/bufferutils.writeBytes(Bytes::from_array([9, 10]))
  assert_eq!(result, [9, 10])
}

test "external call - write and clear Ints" {
  let result = @ZSeanYves/bufferutils.writeIntClear([100, 101])
  assert_eq!(result, [100, 101])
}

test "external call - write and clear String" {
  let result = @ZSeanYves/bufferutils.writeStringClear("OK")
  let s = "OK"
  let a = s.charcode_at(0).to_byte()
  let b = s.charcode_at(1).to_byte()
  assert_eq!(
    result,
    [a, b]  // "O" "K"
  )
}
