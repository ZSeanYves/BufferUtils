///|
fn[T] capture_buffer_result(
  f : () -> T raise BufferError,
) -> Result[T, BufferError] {
  try f() |> Ok catch {
    error => Err(error)
  }
}

///|
test "immutable bytes slices share storage and keep independent cursors" {
  let bytes = SharedBytes::from_array([b'a', b'b', b'c', b'd', b'e', b'f'][:])
  let cloned = bytes.clone()
  let prefix = bytes.split_to(3)
  assert_eq(prefix.view(), [b'a', b'b', b'c'])
  assert_eq(bytes.view(), [b'd', b'e', b'f'])
  prefix.advance(1)
  assert_eq(prefix.view(), [b'b', b'c'])
  assert_eq(bytes.view(), [b'd', b'e', b'f'])
  assert_eq(cloned.view(), [b'a', b'b', b'c', b'd', b'e', b'f'])
  assert_eq(cloned.copied_bytes(), 0)
}

///|
test "bytes copy_to writes into a caller-owned subview" {
  let bytes = SharedBytes::from_array([b'a', b'b', b'c'][:])
  let dst = Array::make(5, b'-')
  assert_eq(bytes.copy_to(dst.mut_view(start=1, end=3)), 2)
  assert_eq(dst, [b'-', b'a', b'b', b'-', b'-'])
  assert_eq(bytes.view(), [b'c'])
}

///|
test "typed integer helpers round trip both endian orders" {
  let mutable = BytesMut::new()
  mutable.put_u16_be(0x1234U.to_uint16())
  mutable.put_u16_le(0x5678U.to_uint16())
  mutable.put_u32_be(0x89ABCDEFU)
  mutable.put_u32_le(0x01234567U)
  mutable.put_u64_be(0x0123456789ABCDEFUL)
  mutable.put_u64_le(0xFEDCBA9876543210UL)
  let bytes = mutable.freeze()
  assert_eq(bytes.get_u16_be(), 0x1234U.to_uint16())
  assert_eq(bytes.get_u16_le(), 0x5678U.to_uint16())
  assert_eq(bytes.get_u32_be(), 0x89ABCDEFU)
  assert_eq(bytes.get_u32_le(), 0x01234567U)
  assert_eq(bytes.get_u64_be(), 0x0123456789ABCDEFUL)
  assert_eq(bytes.get_u64_le(), 0xFEDCBA9876543210UL)
  assert_eq(bytes.remaining(), 0)
}

///|
test "invalid UTF-8 does not advance the cursor" {
  let bytes = SharedBytes::from_array([(255).to_byte(), b'a'][:])
  let result = capture_buffer_result(() => bytes.get_utf8(1))
  assert_eq(result is Err(BufferError::InvalidUtf8), true)
  assert_eq(bytes.remaining(), 2)
}

///|
test "UTF-8 append and decode use exact byte boundaries" {
  let mutable = BytesMut::new(capacity=1)
  mutable.put_utf8("MoonBit 月")
  let bytes = mutable.freeze()
  inspect(bytes.get_utf8(bytes.remaining()), content="MoonBit 月")
}

///|
test "freeze and split are zero-copy until a mutation" {
  let mutable = BytesMut::from_array([b'a', b'b', b'c', b'd'][:])
  let frozen = mutable.freeze()
  assert_eq(frozen.copied_bytes(), 0)
  mutable.put_byte(b'e')
  assert_eq(frozen.view(), [b'a', b'b', b'c', b'd'])
  assert_eq(mutable.view(), [b'a', b'b', b'c', b'd', b'e'])
  assert_eq(mutable.copied_bytes(), 4)
}

///|
test "mutable split siblings detach on mutation" {
  let mutable = BytesMut::from_array([b'a', b'b', b'c', b'd'][:])
  let suffix = mutable.split_to(2)
  suffix.put_byte(b'x')
  assert_eq(mutable.view(), [b'c', b'd'])
  assert_eq(suffix.view(), [b'a', b'b', b'x'])
}

///|
test "capacity limit rejects growth without changing contents" {
  let mutable = BytesMut::new(capacity=2, max_capacity=3)
  mutable.put_slice([b'a', b'b'][:])
  let result = capture_buffer_result(() => mutable.put_slice([b'c', b'd'][:]))
  assert_eq(result is Err(BufferError::CapacityOverflow(_, _)), true)
  assert_eq(mutable.view(), [b'a', b'b'])
}

///|
test "BytesMut matches an array model across 10000 deterministic operations" {
  let mutable = BytesMut::new(max_capacity=20000)
  let model : Array[Byte] = []
  let mut state = 0xC0FFEEU
  for _ in 0..<10000 {
    state = state * 1664525U + 1013904223U
    match state % 4 {
      0 => {
        let value = (state >> 8).to_byte()
        mutable.put_byte(value)
        model.push(value)
      }
      1 =>
        if !model.is_empty() {
          let length = (state % (model.length() + 1).reinterpret_as_uint()).reinterpret_as_int()
          mutable.truncate(length)
          model.truncate(length)
        }
      2 => {
        let copied_before = mutable.copied_bytes()
        let frozen = mutable.freeze()
        assert_eq(frozen.view(), model)
        assert_eq(frozen.copied_bytes(), copied_before)
      }
      _ =>
        if !model.is_empty() {
          let count = (state % (model.length() + 1).reinterpret_as_uint()).reinterpret_as_int()
          let prefix = mutable.split_to(count)
          assert_eq(prefix.view(), model[0:count])
          let remaining = model.length() - count
          for i in 0..<remaining {
            model[i] = model[count + i]
          }
          model.resize(remaining, (0).to_byte())
          prefix.put_byte((state >> 16).to_byte())
          assert_eq(mutable.view(), model)
        }
    }
    assert_eq(mutable.view(), model)
  }
}

///|
test "SharedBytes basic helpers and bounds errors are stable" {
  let empty = SharedBytes::new()
  assert_eq(empty.len(), 0)
  assert_eq(empty.is_empty(), true)
  assert_eq(empty.to_array(), [])
  assert_eq(
    capture_buffer_result(() => empty.get_u8()) is Err(Underflow(_, _)),
    true,
  )

  let bytes = SharedBytes::from_array([b'a', b'b', b'c'][:])
  assert_eq(bytes.chunk().view(), [b'a', b'b', b'c'])
  assert_eq(
    capture_buffer_result(() => bytes.slice(-1, 1)) is Err(InvalidRange(_)),
    true,
  )
  assert_eq(
    capture_buffer_result(() => bytes.split_to(4)) is Err(Underflow(_, _)),
    true,
  )
  assert_eq(
    capture_buffer_result(() => bytes.advance(4)) is Err(Underflow(_, _)),
    true,
  )
  assert_eq(
    capture_buffer_result(() => bytes.get_utf8(4)) is Err(Underflow(_, _)),
    true,
  )
}

///|
test "SharedBytes fixed-array adoption validates the complete range" {
  let backing = FixedArray::make(4, b'x')
  let adopted = SharedBytes::from_fixed_array(backing, 1, 3)
  assert_eq(adopted.to_bytes(), b"xx")
  assert_eq(
    capture_buffer_result(() => SharedBytes::from_fixed_array(backing, -1, 2))
    is Err(InvalidRange(_)),
    true,
  )
  assert_eq(
    capture_buffer_result(() => SharedBytes::from_fixed_array(backing, 3, 2))
    is Err(InvalidRange(_)),
    true,
  )
  assert_eq(
    capture_buffer_result(() => SharedBytes::from_fixed_array(backing, 0, 5))
    is Err(InvalidRange(_)),
    true,
  )
  let empty = SharedBytes::from_fixed_array(backing, 2, 2)
  assert_eq(empty.is_empty(), true)
}

///|
test "BytesMut management and split_off preserve contents" {
  assert_eq(
    capture_buffer_result(() => BytesMut::new(capacity=-1))
    is Err(InvalidRange(_)),
    true,
  )
  let mutable = BytesMut::new(capacity=8, max_capacity=16)
  assert_true(mutable.capacity() >= 8)
  assert_eq(mutable.is_empty(), true)
  mutable.put_slice([b'a', b'b', b'c', b'd'][:])
  mutable.truncate(2)
  mutable.put_byte(b'Z')
  assert_eq(mutable.view(), [b'a', b'b', b'Z'])
  let suffix = mutable.split_off(1)
  assert_eq(mutable.view(), [b'a'])
  assert_eq(suffix.view(), [b'b', b'Z'])
  suffix.with_writable(view => view[0] = b'B')
  assert_eq(suffix.view(), [b'B', b'Z'])
  mutable.clear()
  mutable.put_bytes(suffix.freeze())
  assert_eq(mutable.view(), [b'B', b'Z'])
  assert_eq(
    capture_buffer_result(() => mutable.truncate(3)) is Err(InvalidRange(_)),
    true,
  )
  assert_eq(
    capture_buffer_result(() => mutable.split_to(3)) is Err(Underflow(_, _)),
    true,
  )
  assert_eq(
    capture_buffer_result(() => mutable.split_off(3)) is Err(InvalidRange(_)),
    true,
  )
  assert_eq(
    capture_buffer_result(() => mutable.reserve(-1))
    is Err(CapacityOverflow(_, _)),
    true,
  )
}

///|
test "typed signed float and spare-capacity APIs preserve ranges" {
  let mutable = BytesMut::new(capacity=2)
  mutable.put_i8(-1)
  mutable.put_i16_be(Int16::from_int(-1234))
  mutable.put_i32_le(-123456)
  mutable.put_i64_be(-987654321L)
  mutable.put_f32_le(1.5)
  mutable.put_f64_be(-2.25)
  let bytes = mutable.freeze()
  assert_eq(bytes.get_i8(), -1)
  assert_eq(bytes.get_i16_be(), Int16::from_int(-1234))
  assert_eq(bytes.get_i32_le(), -123456)
  assert_eq(bytes.get_i64_be(), -987654321L)
  assert_eq(bytes.get_f32_le(), 1.5)
  assert_eq(bytes.get_f64_be(), -2.25)

  let spare = BytesMut::new(capacity=4)
  let committed = spare.with_spare_capacity(2, view => {
    view[0] = b'x'
    view[1] = b'y'
    (2, 7)
  })
  assert_eq(committed, 7)
  assert_eq(spare.freeze().view(), [b'x', b'y'])
  spare.resize(4, value=b'z')
  assert_eq(spare.view(), [b'x', b'y', b'z', b'z'])
}

///|
test "split unsplit reclaim and zero-copy bytes view" {
  let mutable = BytesMut::from_array([b'a', b'b', b'c', b'd'][:])
  let prefix = mutable.split_to(2)
  assert_true(prefix.try_unsplit(mutable))
  assert_eq(prefix.view(), [b'a', b'b', b'c', b'd'])
  assert_eq(prefix.freeze().as_bytes_view().to_owned(), [b'a', b'b', b'c', b'd'])
  let reclaim = BytesMut::new(capacity=8)
  reclaim.put_slice([b'a', b'b', b'c'][:])
  ignore(reclaim.split_to(2))
  assert_true(reclaim.try_reclaim(3))
}

///|
test "buffer invalid branches and remaining typed directions" {
  let mutable = BytesMut::new(capacity=8)
  assert_eq(capture_buffer_result(() => mutable.put_i8(128)) is Err(_), true)
  assert_eq(capture_buffer_result(() => mutable.resize(-1)) is Err(_), true)
  mutable.put_i16_le(Int16::from_int(-7))
  mutable.put_i32_be(-8)
  mutable.put_i64_le(-9L)
  mutable.put_f32_be(3.5)
  mutable.put_f64_le(4.5)
  let bytes = mutable.freeze()
  assert_eq(bytes.get_i16_le(), Int16::from_int(-7))
  assert_eq(bytes.get_i32_be(), -8)
  assert_eq(bytes.get_i64_le(), -9L)
  assert_eq(bytes.get_f32_be(), 3.5)
  assert_eq(bytes.get_f64_le(), 4.5)

  let left = BytesMut::from_array([b'a', b'b'][:])
  let right = BytesMut::from_array([b'c'][:])
  assert_eq(left.try_unsplit(right), false)
  left.unsplit(right)
  assert_eq(left.view(), [b'a', b'b', b'c'])
  let shared = BytesMut::from_array([b'x', b'y', b'z'][:])
  ignore(shared.split_to(2))
  assert_eq(capture_buffer_result(() => shared.try_reclaim(-1)) is Err(_), true)
  let invalid_spare = capture_buffer_result(() => {
    ignore(shared.with_spare_capacity(1, _ => (-1, ())))
  })
  assert_eq(invalid_spare is Err(_), true)
}

///|
test "Buf and BufMut trait dispatch covers the public forwarding surface" {
  let mutable = BytesMut::new(capacity=32)
  assert_true(BufMut::remaining_mut(mutable) > 0)
  BufMut::reserve(mutable, 8)
  BufMut::put_byte(mutable, b'X')
  BufMut::put_slice(mutable, [b'\x01', b'\x02', b'\x03', b'\x04'][:])
  let extra = SharedBytes::from_array([b'Y'][:])
  BufMut::put_bytes(mutable, extra)
  let bytes = BufMut::freeze(mutable)
  assert_eq(Buf::remaining(bytes), 6)
  assert_eq(Buf::chunk(bytes).len(), 6)
  assert_eq(Buf::get_u8(bytes), b'X')
  assert_eq(Buf::get_u32_be(bytes), 0x01020304U)
  let target = Array::make(1, (0).to_byte())
  assert_eq(Buf::copy_to(bytes, target.mut_view()), 1)
  assert_eq(target[0], b'Y')

  let typed = BytesMut::new()
  typed.put_u16_be(0x1234U.to_uint16())
  typed.put_u16_le(0x5678U.to_uint16())
  typed.put_u32_le(0x89ABCDEFU)
  typed.put_u64_be(0x0123456789ABCDEFUL)
  typed.put_u64_le(0xFEDCBA9876543210UL)
  let cursor = typed.freeze()
  assert_eq(Buf::get_u16_be(cursor), 0x1234U.to_uint16())
  assert_eq(Buf::get_u16_le(cursor), 0x5678U.to_uint16())
  assert_eq(Buf::get_u32_le(cursor), 0x89ABCDEFU)
  assert_eq(Buf::get_u64_be(cursor), 0x0123456789ABCDEFUL)
  assert_eq(Buf::get_u64_le(cursor), 0xFEDCBA9876543210UL)
  Buf::advance(cursor, 0)
}
