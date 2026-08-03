///|
/// Lazy UTF-8 lines over a buffered reader.
pub struct Lines[R] {
  reader : BufReader[R]
}

///|
fn[R] Lines::new(reader : BufReader[R]) -> Lines[R] {
  { reader, }
}

///|
pub fn[R] Lines::into_inner(self : Lines[R]) -> BufReader[R] {
  self.reader
}

///|
/// Read the next line, excluding `LF` and an optional preceding `CR`.
pub fn[R : Read] Lines::next(self : Lines[R]) -> String? raise IoError {
  let bytes : Array[Byte] = []
  let count = BufRead::read_until(self.reader, b'\n', bytes)
  if count == 0 {
    return None
  }
  if bytes.last() == Some(b'\n') {
    bytes.truncate(bytes.length() - 1)
    if bytes.last() == Some(b'\r') {
      bytes.truncate(bytes.length() - 1)
    }
  }
  let fixed = FixedArray::from_array(bytes[:])
  let text = @utf8.decode(fixed.unsafe_reinterpret_as_bytes()[:]) catch {
    _ =>
      raise io_error(InvalidData, "Lines::next", message="input is not UTF-8")
  }
  Some(text)
}

///|
/// Lazy byte segments over a buffered reader.
pub struct Split[R] {
  reader : BufReader[R]
  delimiter : Byte
}

///|
fn[R] Split::new(reader : BufReader[R], delimiter : Byte) -> Split[R] {
  { reader, delimiter }
}

///|
pub fn[R] Split::into_inner(self : Split[R]) -> BufReader[R] {
  self.reader
}

///|
/// Read the next segment without the delimiter.
pub fn[R : Read] Split::next(self : Split[R]) -> Bytes? raise IoError {
  let bytes : Array[Byte] = []
  let count = BufRead::read_until(self.reader, self.delimiter, bytes)
  if count == 0 {
    return None
  }
  if bytes.last() == Some(self.delimiter) {
    bytes.truncate(bytes.length() - 1)
  }
  Some(Bytes::from_array(bytes[:]))
}
