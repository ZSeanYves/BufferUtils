/// Convert a String into UTF-8 encoded Bytes
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

