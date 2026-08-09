///|
/// Internal storage shared by immutable and mutable handles.
///
/// `immutable` is a conservative copy-on-write marker. Once a storage is
/// exposed through `SharedBytes` or split into siblings, a later mutable
/// operation detaches before writing.
struct SharedStorage {
  data : FixedArray[Byte]
  mut immutable : Bool
  copied_bytes : Int
}

///|
/// Immutable shared byte storage represented by a backing allocation and a
/// visible range.
///
/// Copying, cloning, and slicing this value share the backing allocation. Use
/// `cursor` when an operation must consume bytes.
#valtype
pub struct SharedBytes {
  storage : SharedStorage
  start : Int
  end : Int
}

///|
/// A zero-allocation split descriptor for two ranges in one shared backing.
///
/// Access either side independently through `prefix` or `suffix`. Converting
/// both sides to a tuple with `into_parts` is an explicit allocation boundary
/// on current MoonBit native backends.
#valtype
pub struct SharedBytesSplit {
  storage : SharedStorage
  start : Int
  middle : Int
  end : Int
}

///|
/// Create immutable storage by copying an array view.
pub fn SharedBytes::from_array(data : ArrayView[Byte]) -> SharedBytes {
  {
    storage: {
      data: FixedArray::from_array(data),
      immutable: true,
      copied_bytes: 0,
    },
    start: 0,
    end: data.length(),
  }
}

///|
/// Create immutable storage by copying a fixed-array range.
///
/// Subsequent mutations to `data` cannot affect the returned value.
pub fn SharedBytes::from_fixed_array(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
) -> SharedBytes raise BufferError {
  if start < 0 || end < start || end > data.length() {
    raise BufferError::InvalidRange(
      "fixed-array range is outside the backing storage",
    )
  }
  SharedBytes::from_array(data.view(start~, end~))
}

///|
/// Adopt a fixed-array range without copying.
///
/// # Safety
///
/// The caller must ensure that `data` is never mutated while the returned value
/// or any slice derived from it is reachable. Use `from_fixed_array` unless the
/// backing allocation is exclusively owned by the library.
pub fn SharedBytes::unsafe_adopt_fixed_array(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
) -> SharedBytes raise BufferError {
  if start < 0 || end < start || end > data.length() {
    raise BufferError::InvalidRange(
      "fixed-array range is outside the backing storage",
    )
  }
  { storage: { data, immutable: true, copied_bytes: 0 }, start, end }
}

///|
/// Create an empty immutable value.
pub fn SharedBytes::new() -> SharedBytes {
  SharedBytes::from_array([][:])
}

///|
/// Return the number of visible bytes.
#inline
pub fn SharedBytes::len(self : SharedBytes) -> Int {
  self.end - self.start
}

///|
/// Test whether the visible range is empty.
pub fn SharedBytes::is_empty(self : SharedBytes) -> Bool {
  self.len() == 0
}

///|
/// Return a read-only view over the visible range without copying.
pub fn SharedBytes::view(self : SharedBytes) -> ArrayView[Byte] {
  self.storage.data.view(start=self.start, end=self.end)
}

///|
/// Return a zero-copy Core Bytes view over the shared range.
///
/// The backing storage is immutable while this value is reachable; mutable
/// siblings detach through copy-on-write before modifying it.
pub fn SharedBytes::as_bytes_view(self : SharedBytes) -> BytesView {
  self.storage.data.unsafe_reinterpret_as_bytes()[self.start:self.end]
}

///|
/// Clone the visible range in O(1).
#inline
pub fn SharedBytes::clone(self : SharedBytes) -> SharedBytes {
  self
}

///|
/// Return a shared sub-range. Indices are relative to the visible range.
#inline
pub fn SharedBytes::slice(
  self : SharedBytes,
  start : Int,
  end : Int,
) -> SharedBytes raise BufferError {
  let length = self.len()
  if start < 0 || end < start || end > length {
    raise BufferError::InvalidRange("bytes slice is outside the visible range")
  }
  if start == 0 && end == length {
    self
  } else {
    { storage: self.storage, start: self.start + start, end: self.start + end }
  }
}

///|
/// Return the first `length` visible bytes.
#inline
pub fn SharedBytes::prefix(
  self : SharedBytes,
  length : Int,
) -> SharedBytes raise BufferError {
  self.slice(0, length)
}

///|
/// Return the visible bytes beginning at `offset`.
#inline
pub fn SharedBytes::suffix(
  self : SharedBytes,
  offset : Int,
) -> SharedBytes raise BufferError {
  self.slice(offset, self.len())
}

///|
/// Split the visible range at `index` without modifying this value.
pub fn SharedBytes::split_at(
  self : SharedBytes,
  index : Int,
) -> SharedBytesSplit raise BufferError {
  if index < 0 || index > self.len() {
    raise BufferError::InvalidRange("split index is outside the visible range")
  }
  {
    storage: self.storage,
    start: self.start,
    middle: self.start + index,
    end: self.end,
  }
}

///|
/// Return the range before the split point without allocating.
#inline
pub fn SharedBytesSplit::prefix(self : SharedBytesSplit) -> SharedBytes {
  { storage: self.storage, start: self.start, end: self.middle }
}

///|
/// Return the range after the split point without allocating.
#inline
pub fn SharedBytesSplit::suffix(self : SharedBytesSplit) -> SharedBytes {
  { storage: self.storage, start: self.middle, end: self.end }
}

///|
/// Materialize both split ranges as a tuple.
pub fn SharedBytesSplit::into_parts(
  self : SharedBytesSplit,
) -> (SharedBytes, SharedBytes) {
  (self.prefix(), self.suffix())
}

///|
/// Create an independent consuming cursor over this value.
pub fn SharedBytes::cursor(self : SharedBytes) -> BytesCursor {
  BytesCursor::new(self)
}

///|
/// Explicit copy boundary to a mutable MoonBit array.
pub fn SharedBytes::to_array(self : SharedBytes) -> Array[Byte] {
  self.view().to_owned()
}

///|
/// Materialize the visible range as an owned Core Bytes value.
pub fn SharedBytes::to_bytes(self : SharedBytes) -> Bytes {
  self.as_bytes_view().to_owned()
}

///|
/// Number of bytes copied by copy-on-write for this storage.
pub fn SharedBytes::copied_bytes(self : SharedBytes) -> Int {
  self.storage.copied_bytes
}

///|
pub impl Eq for SharedBytes with fn equal(self, other) {
  self.as_bytes_view().equal(other.as_bytes_view())
}

///|
pub impl Compare for SharedBytes with fn compare(self, other) {
  let order = self.as_bytes_view().lexical_compare(other.as_bytes_view())
  if order < 0 {
    -1
  } else if order > 0 {
    1
  } else {
    0
  }
}

///|
pub impl Hash for SharedBytes with fn hash_combine(self, hasher) {
  hasher.combine(self.as_bytes_view().hash())
}

///|
pub impl @debug.Debug for SharedBytes with fn to_repr(self) {
  @debug.Repr::opaque_(
    "SharedBytes",
    @debug.Repr::array(self.view().map(byte => Repr(byte))),
  )
}
