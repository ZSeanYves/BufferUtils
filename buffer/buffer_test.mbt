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
fn bytes_mut_model_holds(seed : UInt, steps : Int) -> Bool {
  try {
    let mutable = BytesMut::new(max_capacity=20000)
    let model : Array[Byte] = []
    let mut state = seed
    for _ in 0..<steps {
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
          if frozen.view() != model || frozen.copied_bytes() != copied_before {
            return false
          }
        }
        _ =>
          if !model.is_empty() {
            let count = (state % (model.length() + 1).reinterpret_as_uint()).reinterpret_as_int()
            let prefix = mutable.split_to(count)
            if prefix.view() != model[0:count] {
              return false
            }
            let remaining = model.length() - count
            for i in 0..<remaining {
              model[i] = model[count + i]
            }
            model.resize(remaining, (0).to_byte())
            prefix.put_byte((state >> 16).to_byte())
          }
      }
      if mutable.view() != model {
        return false
      }
    }
    true
  } catch {
    _ => false
  }
}

///|
test "BytesMut fixed-seed model is replayable across 10000 operations" {
  let seed = 0xC0FFEEU
  let steps = 10000
  if !bytes_mut_model_holds(seed, steps) {
    let mut low = 1
    let mut high = steps
    while low < high {
      let middle = low + (high - low) / 2
      if bytes_mut_model_holds(seed, middle) {
        low = middle + 1
      } else {
        high = middle
      }
    }
    fail("BytesMut model failed: seed=0xC0FFEE minimal_prefix=\{low}")
  }
}

///|
fn shared_bytes_model_holds(seed : UInt, steps : Int) -> Bool {
  try {
    let initial = Array::make(4096, (0).to_byte())
    for i in 0..<initial.length() {
      initial[i] = ((i * 37 + 11) % 256).to_byte()
    }
    let bytes = SharedBytes::from_array(initial[:])
    let model = initial.copy()
    let mut state = seed
    for _ in 0..<steps {
      state = state * 1664525U + 1013904223U
      let length = model.length()
      let at = if length == 0 {
        0
      } else {
        (state % (length + 1).reinterpret_as_uint()).reinterpret_as_int()
      }
      match state % 6 {
        0 => {
          bytes.advance(at)
          let remaining = length - at
          for i in 0..<remaining {
            model[i] = model[i + at]
          }
          model.resize(remaining, (0).to_byte())
        }
        1 => {
          bytes.truncate(at)
          model.truncate(at)
        }
        2 => {
          let suffix = bytes.split_off(at)
          if suffix.view() != model[at:] {
            return false
          }
          model.truncate(at)
        }
        3 => {
          let prefix = bytes.split_to(at)
          if prefix.view() != model[0:at] {
            return false
          }
          let remaining = length - at
          for i in 0..<remaining {
            model[i] = model[i + at]
          }
          model.resize(remaining, (0).to_byte())
        }
        4 => {
          let clone = bytes.clone()
          let slice = bytes.slice(at, length)
          if clone.view() != model || slice.view() != model[at:] {
            return false
          }
        }
        _ => {
          bytes.clear()
          model.truncate(0)
        }
      }
      if bytes.view() != model {
        return false
      }
    }
    true
  } catch {
    _ => false
  }
}

///|
test "SharedBytes fixed-seed model is replayable across 10000 operations" {
  let seed = 0x51A4EDU
  let steps = 10000
  if !shared_bytes_model_holds(seed, steps) {
    let mut low = 1
    let mut high = steps
    while low < high {
      let middle = low + (high - low) / 2
      if shared_bytes_model_holds(seed, middle) {
        low = middle + 1
      } else {
        high = middle
      }
    }
    fail("SharedBytes model failed: seed=0x51A4ED minimal_prefix=\{low}")
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
test "SharedBytes safe fixed-array construction copies the selected range" {
  let backing = FixedArray::make(4, b'x')
  let adopted = SharedBytes::from_fixed_array(backing, 1, 3)
  assert_eq(adopted.to_bytes(), b"xx")
  backing[1] = b'z'
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
test "SharedBytes unsafe adoption and visible content traits are explicit" {
  let backing = FixedArray::from_array([b'a', b'b', b'c'][:])
  let adopted = SharedBytes::unsafe_adopt_fixed_array(backing, 0, 3)
  backing[0] = b'z'
  assert_eq(adopted.to_bytes(), b"zbc")
  let same = SharedBytes::from_array([b'z', b'b', b'c'][:])
  assert_eq(adopted, same)
  assert_eq(adopted.compare(SharedBytes::from_array([b'z', b'c'][:])), -1)
  assert_eq(adopted.compare(same), 0)
  assert_eq(adopted.compare(SharedBytes::from_array([b'y'][:])), 1)
  assert_eq(adopted.slice(0, adopted.remaining()), same)
  inspect(Repr(adopted), content="<SharedBytes: [0x7a, 0x62, 0x63]>")
  let suffix = adopted.split_off(1)
  assert_eq(adopted.to_bytes(), b"z")
  assert_eq(suffix.to_bytes(), b"bc")
  suffix.truncate(1)
  assert_eq(suffix.to_bytes(), b"b")
  suffix.clear()
  assert_true(suffix.is_empty())
}

///|
test "BytesMut zeroed extend and visible content traits" {
  let mutable = BytesMut::zeroed(3, max_capacity=6)
  assert_eq(mutable.view(), [b'\x00', b'\x00', b'\x00'])
  assert_true(mutable.has_remaining_mut())
  mutable.with_writable(view => {
    view[0] = b'a'
    view[1] = b'b'
    view[2] = b'c'
  })
  mutable.extend_from_within(1, 3)
  assert_eq(mutable.view(), [b'a', b'b', b'c', b'b', b'c'])
  assert_eq(mutable, BytesMut::from_array([b'a', b'b', b'c', b'b', b'c'][:]))
  inspect(Repr(mutable), content="<BytesMut: [0x61, 0x62, 0x63, 0x62, 0x63]>")
  assert_eq(
    capture_buffer_result(() => mutable.extend_from_within(-1, 2)) is Err(_),
    true,
  )
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
  let shared = BytesMut::new(capacity=4)
  shared.put_slice([b'a', b'b', b'c'][:])
  ignore(shared.freeze())
  assert_false(shared.try_reclaim(2))
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
  BufMut::put_bytes_view(mutable, b"Z"[:])
  let bytes = BufMut::freeze(mutable)
  assert_eq(Buf::remaining(bytes), 7)
  assert_eq(Buf::chunk(bytes).len(), 7)
  assert_eq(Buf::get_u8(bytes), b'X')
  assert_eq(Buf::get_u32_be(bytes), 0x01020304U)
  let target = Array::make(2, (0).to_byte())
  assert_eq(Buf::copy_to(bytes, target.mut_view()), 2)
  assert_eq(target, [b'Y', b'Z'])

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

///|
struct DefaultBufMutProbe {
  inner : BytesMut
}

///|
impl BufMut for DefaultBufMutProbe with fn remaining_mut(self) {
  self.inner.remaining_mut()
}

///|
impl BufMut for DefaultBufMutProbe with fn reserve(self, count) {
  self.inner.reserve(count)
}

///|
impl BufMut for DefaultBufMutProbe with fn put_byte(self, byte) {
  self.inner.put_byte(byte)
}

///|
impl BufMut for DefaultBufMutProbe with fn put_slice(self, source) {
  self.inner.put_slice(source)
}

///|
impl BufMut for DefaultBufMutProbe with fn put_bytes(self, source) {
  self.inner.put_bytes(source)
}

///|
impl BufMut for DefaultBufMutProbe with fn freeze(self) {
  self.inner.freeze()
}

///|
test "BufMut BytesView default avoids an intermediate array contract" {
  let probe : DefaultBufMutProbe = { inner: BytesMut::new() }
  BufMut::put_bytes_view(probe, b"view"[:])
  assert_eq(BufMut::freeze(probe).to_bytes(), b"view")
}

///|
test "Buf defaults cross chain boundaries and take enforces its limit" {
  let left = SharedBytes::from_array([b'\x01', b'\x02', b'\x03'][:])
  let right = SharedBytes::from_array([b'\x04', b'\xFF'][:])
  let chain = BufChain::new(left, right)
  assert_eq(Buf::get_u32_be(chain), 0x01020304U)
  assert_eq(Buf::get_i8(chain), -1)
  assert_eq(Buf::remaining(chain), 0)

  let output = BytesMut::new()
  BufMut::put_i16_le(output, Int16::from_int(-2))
  BufMut::put_f32_be(output, 1.5)
  let cursor = BufTake::new(BufMut::freeze(output), 2)
  assert_eq(Buf::get_i16_le(cursor), Int16::from_int(-2))
  assert_eq(Buf::remaining(cursor), 0)
  assert_eq(capture_buffer_result(() => Buf::get_u8(cursor)) is Err(_), true)

  let short = BufChain::new(
    SharedBytes::from_array([b'\x01'][:]),
    SharedBytes::new(),
  )
  assert_eq(capture_buffer_result(() => Buf::get_u16_be(short)) is Err(_), true)
  assert_eq(Buf::remaining(short), 1)

  let bounded = BytesMut::new(max_capacity=1)
  assert_eq(
    capture_buffer_result(() => BufMut::put_u16_be(bounded, 1U.to_uint16()))
    is Err(_),
    true,
  )
  assert_eq(bounded.len(), 0)
}

///|
fn default_cursor(
  bytes : ArrayView[Byte],
) -> BufChain[SharedBytes, SharedBytes] {
  BufChain::new(SharedBytes::new(), SharedBytes::from_array(bytes))
}

///|
test "Buf and BufMut typed defaults cover every portable scalar direction" {
  let encoded = BytesMut::new()
  BufMut::put_byte(encoded, b'\xFE')
  BufMut::put_i8(encoded, -2)
  BufMut::put_u16_be(encoded, 0x1234U.to_uint16())
  BufMut::put_u16_le(encoded, 0x1234U.to_uint16())
  BufMut::put_i16_be(encoded, Int16::from_int(-1234))
  BufMut::put_i16_le(encoded, Int16::from_int(-1234))
  BufMut::put_u32_be(encoded, 0x89ABCDEFU)
  BufMut::put_u32_le(encoded, 0x89ABCDEFU)
  BufMut::put_i32_be(encoded, -123456)
  BufMut::put_i32_le(encoded, -123456)
  BufMut::put_f32_be(encoded, 1.5)
  BufMut::put_f32_le(encoded, 1.5)
  BufMut::put_u64_be(encoded, 0x0123456789ABCDEFUL)
  BufMut::put_u64_le(encoded, 0x0123456789ABCDEFUL)
  BufMut::put_i64_be(encoded, -987654321L)
  BufMut::put_i64_le(encoded, -987654321L)
  BufMut::put_f64_be(encoded, -2.25)
  BufMut::put_f64_le(encoded, -2.25)
  assert_true(BufMut::has_remaining_mut(encoded))
  let bytes = encoded.view()
  let cursor = default_cursor(bytes)
  assert_eq(Buf::get_u8(cursor), b'\xFE')
  assert_eq(Buf::get_i8(cursor), -2)
  assert_eq(Buf::get_u16_be(cursor), 0x1234U.to_uint16())
  assert_eq(Buf::get_u16_le(cursor), 0x1234U.to_uint16())
  assert_eq(Buf::get_i16_be(cursor), Int16::from_int(-1234))
  assert_eq(Buf::get_i16_le(cursor), Int16::from_int(-1234))
  assert_eq(Buf::get_u32_be(cursor), 0x89ABCDEFU)
  assert_eq(Buf::get_u32_le(cursor), 0x89ABCDEFU)
  assert_eq(Buf::get_i32_be(cursor), -123456)
  assert_eq(Buf::get_i32_le(cursor), -123456)
  assert_eq(Buf::get_f32_be(cursor), 1.5)
  assert_eq(Buf::get_f32_le(cursor), 1.5)
  assert_eq(Buf::get_u64_be(cursor), 0x0123456789ABCDEFUL)
  assert_eq(Buf::get_u64_le(cursor), 0x0123456789ABCDEFUL)
  assert_eq(Buf::get_i64_be(cursor), -987654321L)
  assert_eq(Buf::get_i64_le(cursor), -987654321L)
  assert_eq(Buf::get_f64_be(cursor), -2.25)
  assert_eq(Buf::get_f64_le(cursor), -2.25)
  assert_eq(Buf::remaining(cursor), 0)
}

///|
test "BufChain and BufTake copy chunk and invalid paths preserve bounds" {
  let chain = BufChain::new(
    SharedBytes::from_array([b'a'][:]),
    SharedBytes::from_array([b'b', b'c'][:]),
  )
  assert_eq(chain.chunk().to_bytes(), b"a")
  let destination = Array::make(3, b'-')
  assert_eq(Buf::copy_to(chain, destination.mut_view()), 3)
  assert_eq(destination, [b'a', b'b', b'c'])
  let (first, second) = chain.into_parts()
  assert_true(first.is_empty())
  assert_true(second.is_empty())

  let source = SharedBytes::from_array([b'x', b'y', b'z'][:])
  let take = BufTake::new(source, 2)
  assert_eq(take.chunk().to_bytes(), b"xy")
  let copied = Array::make(4, b'-')
  assert_eq(Buf::copy_to(take, copied.mut_view()), 2)
  assert_eq(copied, [b'x', b'y', b'-', b'-'])
  assert_eq(take.limit(), 0)
  assert_true(take.into_inner().remaining() == 1)
  assert_eq(
    capture_buffer_result(() => BufTake::new(source, -1)) is Err(_),
    true,
  )
  let first_only = BufChain::new(
    SharedBytes::from_array([b'a', b'b'][:]),
    SharedBytes::from_array([b'c'][:]),
  )
  let one = Array::make(1, b'-')
  assert_eq(Buf::copy_to(first_only, one.mut_view()), 1)
  assert_eq(one, [b'a'])
  assert_eq(
    capture_buffer_result(() => Buf::advance(first_only, 9)) is Err(_),
    true,
  )
  let invalid_take = BufTake::new(SharedBytes::from_array([b'x'][:]), 1)
  assert_eq(
    capture_buffer_result(() => Buf::advance(invalid_take, 2)) is Err(_),
    true,
  )
}

///|
test "visible value errors equality ordering and hashing cover both outcomes" {
  let backing = FixedArray::make(1, b'x')
  assert_eq(
    capture_buffer_result(() => {
      SharedBytes::unsafe_adopt_fixed_array(backing, -1, 1)
    })
    is Err(_),
    true,
  )
  let value = SharedBytes::from_array([b'a', b'b'][:])
  assert_eq(capture_buffer_result(() => value.truncate(3)) is Err(_), true)
  assert_eq(capture_buffer_result(() => value.split_off(-1)) is Err(_), true)
  assert_eq(SharedBytes::from_array([b'\x7F'][:]).get_i8(), 127)
  assert_eq(value == SharedBytes::from_array([b'a'][:]), false)
  assert_eq(value == SharedBytes::from_array([b'a', b'c'][:]), false)
  assert_true(value.compare(SharedBytes::from_array([b'a', b'b', b'c'][:])) < 0)
  assert_eq(value.hash(), SharedBytes::from_array([b'a', b'b'][:]).hash())

  let shorter = BytesMut::from_array([b'a'][:])
  let different = BytesMut::from_array([b'a', b'c'][:])
  assert_eq(shorter == different, false)
  assert_eq(different == BytesMut::from_array([b'a', b'b'][:]), false)
  different.resize(1)
  assert_eq(different.view(), [b'a'])
  let all = different.split()
  assert_true(different.is_empty())
  assert_eq(all.view(), [b'a'])
}

///|
test "typed default underflow and invalid i8 remain atomic" {
  let one = [b'\x01'][:]
  assert_eq(Buf::get_i8(default_cursor(one)), 1)
  let checks : Array[() -> Unit raise BufferError] = [
    () => ignore(Buf::get_u16_le(default_cursor(one))),
    () => ignore(Buf::get_u32_be(default_cursor(one))),
    () => ignore(Buf::get_u32_le(default_cursor(one))),
    () => ignore(Buf::get_u64_be(default_cursor(one))),
    () => ignore(Buf::get_u64_le(default_cursor(one))),
  ]
  for check in checks {
    assert_eq(capture_buffer_result(check) is Err(_), true)
  }
  let output = BytesMut::new(max_capacity=4)
  assert_eq(
    capture_buffer_result(() => BufMut::put_i8(output, 128)) is Err(_),
    true,
  )
  assert_true(output.is_empty())
}
