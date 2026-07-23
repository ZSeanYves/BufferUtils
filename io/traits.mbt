///|
/// A validated immutable byte range used by vectored writes.
pub struct IoSlice {
  data : Bytes
  offset : Int
  length : Int
}

///|
pub fn IoSlice::new(
  data : Bytes,
  offset : Int,
  length : Int,
) -> IoSlice raise IoError {
  if offset < 0 || length < 0 || offset > data.length() - length {
    raise io_error(
      InvalidInput,
      "IoSlice::new",
      message="source range is invalid",
    )
  }
  { data, offset, length }
}

///|
pub fn IoSlice::data(self : IoSlice) -> Bytes {
  self.data
}

///|
pub fn IoSlice::offset(self : IoSlice) -> Int {
  self.offset
}

///|
pub fn IoSlice::len(self : IoSlice) -> Int {
  self.length
}

///|
pub fn IoSlice::is_empty(self : IoSlice) -> Bool {
  self.length == 0
}

///|
/// A validated mutable fixed-array range used by vectored reads.
pub struct IoSliceMut {
  data : FixedArray[Byte]
  offset : Int
  length : Int
}

///|
pub fn IoSliceMut::new(
  data : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> IoSliceMut raise IoError {
  if offset < 0 || length < 0 || offset > data.length() - length {
    raise io_error(
      InvalidInput,
      "IoSliceMut::new",
      message="destination range is invalid",
    )
  }
  { data, offset, length }
}

///|
pub fn IoSliceMut::data(self : IoSliceMut) -> FixedArray[Byte] {
  self.data
}

///|
pub fn IoSliceMut::offset(self : IoSliceMut) -> Int {
  self.offset
}

///|
pub fn IoSliceMut::len(self : IoSliceMut) -> Int {
  self.length
}

///|
pub fn IoSliceMut::is_empty(self : IoSliceMut) -> Bool {
  self.length == 0
}

///|
/// A fallible source that reads into caller-owned storage.
pub(open) trait Read {
  /// Read into a caller-owned fixed array range without an intermediate copy.
  fn read(Self, FixedArray[Byte], Int, Int) -> Int raise IoError
  /// Explicit copying adapter for ordinary mutable arrays.
  fn read_array(Self, MutArrayView[Byte]) -> Int raise IoError = _
  fn read_fixed(Self, FixedArray[Byte], Int, Int) -> Int raise IoError = _
  fn read_vectored(Self, ArrayView[IoSliceMut]) -> Int raise IoError = _
  fn read_exact(Self, MutArrayView[Byte]) -> Unit raise IoError = _
  fn is_read_vectored(Self) -> Bool = _
}

///|
/// The default fixed-array path preserves the slice-based `Read` contract.
impl Read with fn read_array(self, destination) {
  let fixed = FixedArray::make(destination.length(), (0).to_byte())
  let count = Read::read(self, fixed, 0, destination.length())
  for i in 0..<count {
    destination[i] = fixed[i]
  }
  count
}

///|
impl Read with fn read_fixed(self, destination, offset, length) {
  if offset < 0 || length < 0 || offset > destination.length() - length {
    raise io_error(
      InvalidInput,
      "read_fixed",
      message="destination range is invalid",
    )
  }
  Read::read(self, destination, offset, length)
}

///|
/// Default vectored read behavior uses the first non-empty destination.
impl Read with fn read_vectored(self, destinations) {
  for item in destinations {
    if !item.is_empty() {
      return Read::read(self, item.data(), item.offset(), item.len())
    }
  }
  0
}

///|
impl Read with fn is_read_vectored(_self) {
  false
}

///|
/// Read until the destination has been filled.
impl Read with fn read_exact(self, dst) {
  let mut completed = 0
  while completed < dst.length() {
    let count = Read::read_array(self, dst.mut_view(start=completed)) catch {
      error if error.kind() == Interrupted => {
        let progress = error.progress()
        validate_progress("read", progress, dst.length() - completed)
        if progress != 0 {
          raise io_error(
            ContractViolation,
            "read",
            progress=completed,
            message="an interrupted read reported committed bytes",
          )
        }
        continue
      }
      error => raise error.add_progress(completed)
    }
    validate_progress("read", count, dst.length() - completed)
    if count == 0 {
      raise io_error(
        UnexpectedEof,
        "read_exact",
        progress=completed,
        message="source reached EOF before filling the destination",
      )
    }
    completed += count
  }
}

///|
/// A fallible destination that may accept only part of an input view.
pub(open) trait Write {
  /// Write a range of immutable Core Bytes without copying.
  fn write(Self, Bytes, Int, Int) -> Int raise IoError
  /// Explicit copying adapter for ordinary arrays.
  fn write_array(Self, ArrayView[Byte]) -> Int raise IoError = _
  fn write_vectored(Self, ArrayView[IoSlice]) -> Int raise IoError = _
  fn flush(Self) -> Unit raise IoError
  fn write_all(Self, ArrayView[Byte]) -> Unit raise IoError = _
  fn is_write_vectored(Self) -> Bool = _
}

///|
/// Default vectored write behavior uses the first non-empty source.
impl Write with fn write_vectored(self, sources) {
  for item in sources {
    if !item.is_empty() {
      return Write::write(self, item.data(), item.offset(), item.len())
    }
  }
  0
}

///|
impl Write with fn write_array(self, source) {
  let fixed = FixedArray::from_array(source)
  let bytes = fixed.unsafe_reinterpret_as_bytes()
  Write::write(self, bytes, 0, source.length())
}

///|
impl Write with fn is_write_vectored(_self) {
  false
}

///|
/// An explicitly closeable resource. Closing is idempotent by contract.
pub(open) trait Close {
  fn close(Self) -> Unit raise IoError
  fn is_closed(Self) -> Bool
}

///|
/// Write an entire byte view, retrying ordinary short writes.
impl Write with fn write_all(self, src) {
  let mut completed = 0
  while completed < src.length() {
    let count = Write::write_array(self, src[completed:]) catch {
      error if error.kind() == Interrupted => {
        let progress = error.progress()
        validate_progress("write", progress, src.length() - completed)
        if progress != 0 {
          raise io_error(
            ContractViolation,
            "write",
            progress=completed,
            message="an interrupted write reported committed bytes",
          )
        }
        continue
      }
      error => raise error.add_progress(completed)
    }
    validate_progress("write", count, src.length() - completed)
    if count == 0 {
      raise io_error(
        WriteZero,
        "write_all",
        progress=completed,
        message="destination accepted zero bytes",
      )
    }
    completed += count
  }
}

///|
/// Fill every destination in order, preserving cumulative partial progress.
pub fn[R : Read] read_exact_vectored(
  reader : R,
  destinations : ArrayView[MutArrayView[Byte]],
) -> Unit raise IoError {
  let mut completed = 0
  for destination in destinations {
    Read::read_exact(reader, destination) catch {
      error => raise error.add_progress(completed)
    }
    completed += destination.length()
  }
}

///|
/// Fill a fixed-array range, preserving the zero-copy native destination.
pub fn[R : Read] read_exact_fixed(
  reader : R,
  destination : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> Unit raise IoError {
  if offset < 0 || length < 0 || offset > destination.length() - length {
    raise io_error(
      InvalidInput,
      "read_exact_fixed",
      message="destination range is invalid",
    )
  }
  let mut completed = 0
  while completed < length {
    let count = Read::read(
      reader,
      destination,
      offset + completed,
      length - completed,
    )
    validate_progress("read_exact_fixed", count, length - completed)
    if count == 0 {
      raise io_error(UnexpectedEof, "read_exact_fixed", progress=completed)
    }
    completed += count
  }
}

///|
/// Write every source in order, preserving cumulative partial progress.
pub fn[W : Write] write_all_vectored(
  writer : W,
  sources : ArrayView[ArrayView[Byte]],
) -> Unit raise IoError {
  let mut completed = 0
  for source in sources {
    Write::write_all(writer, source) catch {
      error => raise error.add_progress(completed)
    }
    completed += source.length()
  }
}

///|
/// Write a Core Bytes range, retrying short writes without copying.
pub fn[W : Write] write_all_bytes(
  writer : W,
  source : Bytes,
  offset? : Int = 0,
  len? : Int = source.length() - offset,
) -> Unit raise IoError {
  if offset < 0 || len < 0 || offset > source.length() - len {
    raise io_error(
      InvalidInput,
      "write_all_bytes",
      message="source range is invalid",
    )
  }
  let mut completed = 0
  while completed < len {
    let count = Write::write(
      writer,
      source,
      offset + completed,
      len - completed,
    )
    validate_progress("write_all_bytes", count, len - completed)
    if count == 0 {
      raise io_error(WriteZero, "write_all_bytes", progress=completed)
    }
    completed += count
  }
}

///|
/// A reader that exposes its current buffer for allocation-free parsing.
pub(open) trait BufRead: Read {
  fn fill_buf(Self) -> ArrayView[Byte] raise IoError
  fn consume(Self, Int) -> Unit raise IoError
  fn read_until(Self, Byte, Array[Byte]) -> Int raise IoError = _
  fn skip_until(Self, Byte) -> Int raise IoError = _
  fn read_line(Self, StringBuilder) -> Int raise IoError = _
}

///|
/// Seekable byte streams use a logical position independent of buffering.
pub(all) enum SeekFrom {
  Start(Int64)
  Current(Int64)
  End(Int64)
} derive(Eq, @debug.Debug)

///|
pub(open) trait Seek {
  fn seek(Self, SeekFrom) -> Int64 raise IoError
  fn stream_position(Self) -> Int64 raise IoError
  fn rewind(Self) -> Unit raise IoError = _
}

///|
impl Seek with fn rewind(self) {
  ignore(Seek::seek(self, Start(0L)))
}

///|
/// Read all remaining bytes and decode them as UTF-8.
pub fn[R : Read] read_to_string(reader : R) -> String raise IoError {
  let bytes : Array[Byte] = []
  ignore(read_to_end(reader, bytes))
  let core_bytes = FixedArray::from_array(bytes[:]).unsafe_reinterpret_as_bytes()
  @utf8.decode(core_bytes[:]) catch {
    _ =>
      raise io_error(
        InvalidData,
        "read_to_string",
        message="input is not UTF-8",
      )
  }
}

///|
/// Append with geometric capacity growth. Growing `ArrayView::blit_to`
/// directly reallocates to the exact new length on current Core releases.
fn append_bytes(dst : Array[Byte], src : ArrayView[Byte]) -> Unit raise IoError {
  if src.is_empty() {
    return
  }
  let start = dst.length()
  if src.length() > 2147483647 - start {
    raise io_error(InvalidInput, "append", message="byte array length overflow")
  }
  let required = start + src.length()
  if required > dst.capacity() {
    let doubled = if dst.capacity() > 1073741823 {
      2147483647
    } else {
      Int::max(1, dst.capacity() * 2)
    }
    dst.reserve_capacity(Int::max(required, doubled))
  }
  dst.resize(required, (0).to_byte())
  src.blit_to(dst, dst_offset=start)
}

///|
/// Append through and including `delimiter`, or append to EOF.
impl BufRead with fn read_until(self, delimiter, dst) {
  let initial = dst.length()
  while true {
    let available = BufRead::fill_buf(self)
    if available.is_empty() {
      break
    }
    let mut count = available.length()
    for i, byte in available {
      if byte == delimiter {
        count = i + 1
        break
      }
    }
    append_bytes(dst, available[0:count])
    BufRead::consume(self, count)
    if dst[dst.length() - 1] == delimiter {
      break
    }
  }
  dst.length() - initial
}

///|
impl BufRead with fn skip_until(self, delimiter) {
  let scratch : Array[Byte] = []
  BufRead::read_until(self, delimiter, scratch)
}

///|
/// Read a UTF-8 line, including the newline when present.
impl BufRead with fn read_line(self, dst) {
  let bytes : Array[Byte] = []
  let count = BufRead::read_until(self, b'\n', bytes)
  let core_bytes = FixedArray::from_array(bytes[:]).unsafe_reinterpret_as_bytes()
  let line = @utf8.decode(core_bytes[:]) catch {
    _ => raise io_error(InvalidData, "read_line", message="input is not UTF-8")
  }
  dst.write_string(line)
  count
}

///|
/// Read all remaining bytes into an existing array.
pub fn[R : Read] read_to_end(
  reader : R,
  dst : Array[Byte],
) -> Int raise IoError {
  let initial = dst.length()
  let scratch = FixedArray::make(8192, (0).to_byte())
  while true {
    let count = Read::read(reader, scratch, 0, scratch.length()) catch {
      error => raise error.add_progress(dst.length() - initial)
    }
    validate_progress("read", count, scratch.length())
    if count == 0 {
      break
    }
    append_bytes(dst, scratch.view(end=count))
  }
  dst.length() - initial
}
