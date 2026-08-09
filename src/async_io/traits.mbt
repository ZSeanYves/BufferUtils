///|
/// The origin used by asynchronous seek operations.
pub(all) enum AsyncSeekFrom {
  Start(Int64)
  Current(Int64)
  End(Int64)
} derive(Eq, @debug.Debug)

///|
/// A cancellation-aware asynchronous byte reader.
pub(open) trait AsyncRead {
  async fn read(Self, FixedArray[Byte], offset? : Int, max_len? : Int) -> Int
  async fn read_exact(Self, FixedArray[Byte], offset? : Int, len? : Int) -> Unit = _
  async fn read_to_end(Self) -> Bytes = _
  async fn read_u8(Self) -> Byte = _
  async fn read_i8(Self) -> Int = _
  async fn read_u16_be(Self) -> UInt16 = _
  async fn read_u16_le(Self) -> UInt16 = _
  async fn read_i16_be(Self) -> Int16 = _
  async fn read_i16_le(Self) -> Int16 = _
  async fn read_u32_be(Self) -> UInt = _
  async fn read_u32_le(Self) -> UInt = _
  async fn read_i32_be(Self) -> Int = _
  async fn read_i32_le(Self) -> Int = _
  async fn read_f32_be(Self) -> Float = _
  async fn read_f32_le(Self) -> Float = _
  async fn read_u64_be(Self) -> UInt64 = _
  async fn read_u64_le(Self) -> UInt64 = _
  async fn read_i64_be(Self) -> Int64 = _
  async fn read_i64_le(Self) -> Int64 = _
  async fn read_f64_be(Self) -> Double = _
  async fn read_f64_le(Self) -> Double = _
}

///|
async fn[R : AsyncRead] read_unsigned(
  reader : R,
  width : Int,
  little_endian : Bool,
) -> UInt64 {
  let data = FixedArray::make(width, (0).to_byte())
  AsyncRead::read_exact(reader, data)
  let bytes = data.unsafe_reinterpret_as_bytes()
  if width == 1 {
    bytes[0].to_uint64()
  } else if width == 2 {
    if little_endian {
      bytes.unsafe_read_uint16_le(0).to_uint64()
    } else {
      bytes.unsafe_read_uint16_be(0).to_uint64()
    }
  } else if width == 4 {
    if little_endian {
      bytes.unsafe_read_uint32_le(0).to_uint64()
    } else {
      bytes.unsafe_read_uint32_be(0).to_uint64()
    }
  } else if little_endian {
    bytes.unsafe_read_uint64_le(0)
  } else {
    bytes.unsafe_read_uint64_be(0)
  }
}

///|
impl AsyncRead with fn read_u8(self) {
  read_unsigned(self, 1, false).to_byte()
}

///|
impl AsyncRead with fn read_i8(self) {
  let value = read_unsigned(self, 1, false).to_int()
  if value < 128 {
    value
  } else {
    value - 256
  }
}

///|
impl AsyncRead with fn read_u16_be(self) {
  read_unsigned(self, 2, false).to_uint16()
}

///|
impl AsyncRead with fn read_u16_le(self) {
  read_unsigned(self, 2, true).to_uint16()
}

///|
impl AsyncRead with fn read_i16_be(self) {
  Int16::reinterpret_from_uint16(read_unsigned(self, 2, false).to_uint16())
}

///|
impl AsyncRead with fn read_i16_le(self) {
  Int16::reinterpret_from_uint16(read_unsigned(self, 2, true).to_uint16())
}

///|
impl AsyncRead with fn read_u32_be(self) {
  read_unsigned(self, 4, false).to_uint()
}

///|
impl AsyncRead with fn read_u32_le(self) {
  read_unsigned(self, 4, true).to_uint()
}

///|
impl AsyncRead with fn read_i32_be(self) {
  read_unsigned(self, 4, false).to_uint().reinterpret_as_int()
}

///|
impl AsyncRead with fn read_i32_le(self) {
  read_unsigned(self, 4, true).to_uint().reinterpret_as_int()
}

///|
impl AsyncRead with fn read_f32_be(self) {
  Float::reinterpret_from_uint(read_unsigned(self, 4, false).to_uint())
}

///|
impl AsyncRead with fn read_f32_le(self) {
  Float::reinterpret_from_uint(read_unsigned(self, 4, true).to_uint())
}

///|
impl AsyncRead with fn read_u64_be(self) {
  read_unsigned(self, 8, false)
}

///|
impl AsyncRead with fn read_u64_le(self) {
  read_unsigned(self, 8, true)
}

///|
impl AsyncRead with fn read_i64_be(self) {
  read_unsigned(self, 8, false).reinterpret_as_int64()
}

///|
impl AsyncRead with fn read_i64_le(self) {
  read_unsigned(self, 8, true).reinterpret_as_int64()
}

///|
impl AsyncRead with fn read_f64_be(self) {
  read_unsigned(self, 8, false).reinterpret_as_double()
}

///|
impl AsyncRead with fn read_f64_le(self) {
  read_unsigned(self, 8, true).reinterpret_as_double()
}

///|
impl AsyncRead with fn read_exact(
  self,
  destination,
  offset? = 0,
  len? = destination.length() - offset,
) {
  if offset < 0 || len < 0 || offset > destination.length() - len {
    raise @syncio.io_error(@syncio.InvalidInput, "async read_exact")
  }
  for progress = 0; progress < len; {
    let count = self.read(
      destination,
      offset=offset + progress,
      max_len=len - progress,
    )
    if count == 0 {
      raise @syncio.io_error(
        @syncio.UnexpectedEof,
        "async read_exact",
        progress~,
      )
    }
    if count < 0 || count > len - progress {
      raise @syncio.io_error(
        @syncio.ContractViolation,
        "async read_exact",
        progress~,
      )
    }
    continue progress + count
  }
}

///|
impl AsyncRead with fn read_to_end(self) {
  let output = @buffer.BytesMut::new(capacity=8192)
  let scratch = FixedArray::make(8192, (0).to_byte())
  while true {
    let count = self.read(scratch)
    if count == 0 {
      break
    }
    if count < 0 || count > scratch.length() {
      raise @syncio.io_error(@syncio.ContractViolation, "async read_to_end")
    }
    output.put_bytes_view(scratch.unsafe_reinterpret_as_bytes()[0:count])
  }
  output.freeze().to_bytes()
}

///|
/// A cancellation-aware asynchronous byte writer.
pub(open) trait AsyncWrite {
  async fn write(Self, Bytes, offset~ : Int, len~ : Int) -> Int
  async fn flush(Self) -> Unit
  async fn shutdown(Self) -> Unit = _
  async fn write_all(Self, Bytes, offset? : Int, len? : Int) -> Unit = _
  async fn write_u8(Self, Byte) -> Unit = _
  async fn write_i8(Self, Int) -> Unit = _
  async fn write_u16_be(Self, UInt16) -> Unit = _
  async fn write_u16_le(Self, UInt16) -> Unit = _
  async fn write_i16_be(Self, Int16) -> Unit = _
  async fn write_i16_le(Self, Int16) -> Unit = _
  async fn write_u32_be(Self, UInt) -> Unit = _
  async fn write_u32_le(Self, UInt) -> Unit = _
  async fn write_i32_be(Self, Int) -> Unit = _
  async fn write_i32_le(Self, Int) -> Unit = _
  async fn write_f32_be(Self, Float) -> Unit = _
  async fn write_f32_le(Self, Float) -> Unit = _
  async fn write_u64_be(Self, UInt64) -> Unit = _
  async fn write_u64_le(Self, UInt64) -> Unit = _
  async fn write_i64_be(Self, Int64) -> Unit = _
  async fn write_i64_le(Self, Int64) -> Unit = _
  async fn write_f64_be(Self, Double) -> Unit = _
  async fn write_f64_le(Self, Double) -> Unit = _
}

///|
async fn[W : AsyncWrite] write_integer(
  writer : W,
  value : UInt64,
  width : Int,
  little_endian : Bool,
) -> Unit {
  let buffer = FixedArray::make(width, (0).to_byte())
  for index in 0..<width {
    let shift = if little_endian { index * 8 } else { (width - index - 1) * 8 }
    buffer[index] = (value >> shift).to_byte()
  }
  AsyncWrite::write_all(writer, buffer.unsafe_reinterpret_as_bytes())
}

///|
impl AsyncWrite with fn write_u8(self, value) {
  write_integer(self, value.to_uint64(), 1, false)
}

///|
impl AsyncWrite with fn write_i8(self, value) {
  if value < -128 || value > 127 {
    raise @syncio.io_error(
      @syncio.InvalidInput,
      "async write_i8",
      message="i8 value is outside [-128, 127]",
    )
  }
  write_integer(self, (value & 0xFF).to_uint64(), 1, false)
}

///|
impl AsyncWrite with fn write_u16_be(self, value) {
  write_integer(self, value.to_uint64(), 2, false)
}

///|
impl AsyncWrite with fn write_u16_le(self, value) {
  write_integer(self, value.to_uint64(), 2, true)
}

///|
impl AsyncWrite with fn write_i16_be(self, value) {
  write_integer(self, value.reinterpret_as_uint16().to_uint64(), 2, false)
}

///|
impl AsyncWrite with fn write_i16_le(self, value) {
  write_integer(self, value.reinterpret_as_uint16().to_uint64(), 2, true)
}

///|
impl AsyncWrite with fn write_u32_be(self, value) {
  write_integer(self, value.to_uint64(), 4, false)
}

///|
impl AsyncWrite with fn write_u32_le(self, value) {
  write_integer(self, value.to_uint64(), 4, true)
}

///|
impl AsyncWrite with fn write_i32_be(self, value) {
  write_integer(self, value.reinterpret_as_uint().to_uint64(), 4, false)
}

///|
impl AsyncWrite with fn write_i32_le(self, value) {
  write_integer(self, value.reinterpret_as_uint().to_uint64(), 4, true)
}

///|
impl AsyncWrite with fn write_f32_be(self, value) {
  write_integer(self, value.reinterpret_as_uint().to_uint64(), 4, false)
}

///|
impl AsyncWrite with fn write_f32_le(self, value) {
  write_integer(self, value.reinterpret_as_uint().to_uint64(), 4, true)
}

///|
impl AsyncWrite with fn write_u64_be(self, value) {
  write_integer(self, value, 8, false)
}

///|
impl AsyncWrite with fn write_u64_le(self, value) {
  write_integer(self, value, 8, true)
}

///|
impl AsyncWrite with fn write_i64_be(self, value) {
  write_integer(self, value.reinterpret_as_uint64(), 8, false)
}

///|
impl AsyncWrite with fn write_i64_le(self, value) {
  write_integer(self, value.reinterpret_as_uint64(), 8, true)
}

///|
impl AsyncWrite with fn write_f64_be(self, value) {
  write_integer(self, value.reinterpret_as_uint64(), 8, false)
}

///|
impl AsyncWrite with fn write_f64_le(self, value) {
  write_integer(self, value.reinterpret_as_uint64(), 8, true)
}

///|
impl AsyncWrite with fn shutdown(self) {
  AsyncWrite::flush(self)
}

///|
impl AsyncWrite with fn write_all(
  self,
  source,
  offset? = 0,
  len? = source.length() - offset,
) {
  if offset < 0 || len < 0 || offset > source.length() - len {
    raise @syncio.io_error(@syncio.InvalidInput, "async write_all")
  }
  for progress = 0; progress < len; {
    let count = self.write(source, offset=offset + progress, len=len - progress)
    if count == 0 {
      raise @syncio.io_error(@syncio.WriteZero, "async write_all", progress~)
    }
    if count < 0 || count > len - progress {
      raise @syncio.io_error(
        @syncio.ContractViolation,
        "async write_all",
        progress~,
      )
    }
    continue progress + count
  }
}

///|
pub(open) trait AsyncBufRead: AsyncRead {
  /// The returned view borrows the reader's internal fixed buffer and is
  /// invalidated by the next reader operation.
  async fn fill_buf(Self) -> ArrayView[Byte]
  fn consume(Self, Int) -> Unit raise @syncio.IoError
  async fn has_data_left(Self) -> Bool = _
  async fn read_until(Self, Byte) -> Bytes = _
}

///|
impl AsyncBufRead with fn has_data_left(self) {
  !AsyncBufRead::fill_buf(self).is_empty()
}

///|
impl AsyncBufRead with fn read_until(self, delimiter) {
  let output : Array[Byte] = []
  while true {
    let chunk = self.fill_buf()
    if chunk.is_empty() {
      break
    }
    let mut consumed = chunk.length()
    for i in 0..<chunk.length() {
      if chunk[i] == delimiter {
        consumed = i + 1
        break
      }
    }
    let output_start = output.length()
    if consumed > 2147483647 - output_start {
      raise @syncio.io_error(
        @syncio.InvalidInput,
        "async read_until",
        message="byte sequence exceeds the maximum array length",
      )
    }
    let required = output_start + consumed
    if required > output.capacity() {
      let doubled = if output.capacity() > 1073741823 {
        2147483647
      } else {
        Int::max(1, output.capacity() * 2)
      }
      output.reserve_capacity(Int::max(required, doubled))
    }
    output.resize(required, (0).to_byte())
    chunk[0:consumed].blit_to(output, dst_offset=output_start)
    self.consume(consumed)
    if output[output.length() - 1] == delimiter {
      return Bytes::from_array(output)
    }
  }
  Bytes::from_array(output)
}

///|
pub(open) trait AsyncSeek {
  async fn seek(Self, AsyncSeekFrom) -> Int64
  async fn stream_position(Self) -> Int64 = _
  async fn rewind(Self) -> Unit = _
}

///|
impl AsyncSeek with fn stream_position(self) {
  self.seek(Current(0L))
}

///|
impl AsyncSeek with fn rewind(self) {
  ignore(self.seek(Start(0L)))
}

///|
pub(open) trait AsyncClose {
  async fn close(Self) -> Unit
  fn is_closed(Self) -> Bool
}

///|
pub async fn[R : AsyncRead] read_to_end(reader : R) -> Bytes {
  AsyncRead::read_to_end(reader)
}

///|
pub async fn[W : AsyncWrite] write_all(writer : W, bytes : Bytes) -> Unit {
  AsyncWrite::write_all(writer, bytes)
}
