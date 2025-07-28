///将字符串转换为UTF-8编码字节
pub fn string_to_utf8_bytes(s: String) -> Bytes {
  let result: Array[Byte] = []
  let len = s.length()
  let mut i = 0

  while i < len {
    let cu1 = s[i]

    // 检查是否是高代理项（0xD800 ~ 0xDBFF）
    if cu1 >= 0xD800 && cu1 <= 0xDBFF && (i + 1 < len) {
      let cu2 = s[i + 1]
      // 检查是否是低代理项（0xDC00 ~ 0xDFFF）
      if cu2 >= 0xDC00 && cu2 <= 0xDFFF {
        // 组合 surrogate pair 得到 Unicode code point
        let high = cu1 - 0xD800
        let low = cu2 - 0xDC00
        let code_point = 0x10000 + ((high << 10) | low)

        // 编码成 UTF-8 (4 bytes)
        result.push((0xF0 | (code_point >> 18)).to_byte())
        result.push((0x80 | ((code_point >> 12) & 0x3F)).to_byte())
        result.push((0x80 | ((code_point >> 6) & 0x3F)).to_byte())
        result.push((0x80 | (code_point & 0x3F)).to_byte())

        i += 2
        continue
      }
    }

    // 非 surrogate 或不成对的高位项，按普通 UTF-8 编码
    if cu1 <= 0x7F {
      result.push(cu1.to_byte())
    } else if cu1 <= 0x7FF {
      result.push((0xC0 | (cu1 >> 6)).to_byte())
      result.push((0x80 | (cu1 & 0x3F)).to_byte())
    } else {
      result.push((0xE0 | (cu1 >> 12)).to_byte())
      result.push((0x80 | ((cu1 >> 6) & 0x3F)).to_byte())
      result.push((0x80 | (cu1 & 0x3F)).to_byte())
    }

    i += 1
  }

  Bytes::from_array(result)
}

// utils.mbt

pub suberror Utf8DecodeError(String)

pub fn utf8_bytes_to_string(b: Bytes) -> String raise Utf8DecodeError {
  let mut result = ""
  let mut i = 0
  let data = b.to_array()
  let len = data.length()

  while i < len {
    let byte = data[i].to_int()
    if byte < 0x80 {
      result = result + Int::unsafe_to_char(byte).to_string()
      i += 1
    } else if (byte >> 5) == 0x6 { // 2-byte
      if i + 1 >= len {
        raise Utf8DecodeError("Invalid UTF-8: Unexpected end at 2-byte sequence")
      }
      let byte2 = data[i+1].to_int()
      if (byte2 >> 6) != 0x2 {
        raise Utf8DecodeError("Invalid UTF-8: Bad continuation byte at 2-byte sequence")
      }
      let cp = ((byte & 0x1F) << 6) | (byte2 & 0x3F)
      result = result + Int::unsafe_to_char(cp).to_string()
      i += 2
    } else if (byte >> 4) == 0xE { // 3-byte
      if i + 2 >= len {
        raise Utf8DecodeError("Invalid UTF-8: Unexpected end at 3-byte sequence")
      }
      let byte2 = data[i+1].to_int()
      let byte3 = data[i+2].to_int()
      if (byte2 >> 6) != 0x2 || (byte3 >> 6) != 0x2 {
        raise Utf8DecodeError("Invalid UTF-8: Bad continuation bytes at 3-byte sequence")
      }
      let cp = ((byte & 0x0F) << 12) | ((byte2 & 0x3F) << 6) | (byte3 & 0x3F)
      result = result + Int::unsafe_to_char(cp).to_string()
      i += 3
    } else if (byte >> 3) == 0x1E { // 4-byte
      if i + 3 >= len {
        raise Utf8DecodeError("Invalid UTF-8: Unexpected end at 4-byte sequence")
      }
      let byte2 = data[i+1].to_int()
      let byte3 = data[i+2].to_int()
      let byte4 = data[i+3].to_int()
      if (byte2 >> 6) != 0x2 || (byte3 >> 6) != 0x2 || (byte4 >> 6) != 0x2 {
        raise Utf8DecodeError("Invalid UTF-8: Bad continuation bytes at 4-byte sequence")
      }
      let cp = ((byte & 0x07) << 18) | ((byte2 & 0x3F) << 12) | ((byte3 & 0x3F) << 6) | (byte4 & 0x3F)
      result = result + Int::unsafe_to_char(cp).to_string()
      i += 4
    } else {
      raise Utf8DecodeError("Invalid UTF-8: Unknown byte pattern")
    }
  }

  result
}

///| 通过特定字节定界符将“字节”对象分为多个段。
/// 返回一个`array [byte]`的数组，不包括定界符。
pub fn split_bytes(buf: Bytes, delimiter: Byte) -> Array[Array[Byte]] {
  let result: Array[Array[Byte]] = []
  let current: Array[Byte] = []
  let arr = buf.to_array()

  for b in arr {
    if b == delimiter {
      
      let segment: Array[Byte] = []
      for c in current {
        segment.push(c)
      }
      result.push(segment)
      current.clear()
    } else {
      current.push(b)
    }
  }

  
  let last: Array[Byte] = []
  for c in current {
    last.push(c)
  }
  result.push(last)

  result
}

///| 通过一个字节定界符将“数组[字节）`将[字节]`将其划分为段。
/// 等效于`split_bytes（bytes :: from_array（...））`
pub fn split_array_bytes(arr: Array[Byte], delimiter: Byte) -> Array[Array[Byte]] {
  split_bytes(Bytes::from_array(arr), delimiter)
}

test "string_to_utf8_bytes and utf8_bytes_to_string - round trip" {
  let s = "Hello, 世界! 👋"
  let bytes = string_to_utf8_bytes(s)
  let recovered = utf8_bytes_to_string(bytes)
  assert_eq(recovered, s)
}

test "utf8_bytes_to_string - invalid continuation byte" {
  let bad_bytes = Bytes::from_array([0xE4, 0x7F]) // E4 should be followed by 2 continuation bytes
  let result = (try? utf8_bytes_to_string(bad_bytes))
  assert_eq(result.is_err(),true)
}

test "utf8_bytes_to_string - unexpected end of input" {
  let bad_bytes = Bytes::from_array([0xF0, 0x9F]) // Incomplete 4-byte sequence
  let result = (try? utf8_bytes_to_string(bad_bytes))
  assert_eq(result.is_err(),true)
}

test "split_bytes and split_array_bytes produce same result" {
  let arr = [1, 2, 0, 3, 0, 4, 5]
  let data = readInts(arr)
  let bytes = Bytes::from_array(data)
  let a = 0 // Using 0 as delimiter
  let delimiter = a.to_byte() // Using 0 as delimiter
  let r1 = split_bytes(bytes, delimiter)
  let r2 = split_array_bytes(data, delimiter)
  assert_eq(r1, r2)
  assert_eq(r1.length(), 3)
  assert_eq(r1[0], [1, 2])
  assert_eq(r1[1], [3])
  assert_eq(r1[2], [4, 5])
}

test "split_bytes - no delimiter present" {
  let arr = [65, 66, 67]
  let data = readInts(arr)
  let a = 0
  let parts = split_array_bytes(data, a.to_byte())
  assert_eq(parts.length(), 1)
  assert_eq(parts[0], data)
}

