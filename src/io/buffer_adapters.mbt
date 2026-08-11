///|
/// Expose an in-memory `Buf` as a synchronous reader.
pub struct BufReaderAdapter[B] {
  inner : B
}

///|
pub fn[B] BufReaderAdapter::new(inner : B) -> BufReaderAdapter[B] {
  { inner, }
}

///|
pub fn[B] BufReaderAdapter::get_ref(self : BufReaderAdapter[B]) -> B {
  self.inner
}

///|
pub fn[B] BufReaderAdapter::into_inner(self : BufReaderAdapter[B]) -> B {
  self.inner
}

///|
pub impl[B : @buffer.Buf] Read for BufReaderAdapter[B] with fn read(
  self,
  destination,
  offset,
  length,
) {
  if offset < 0 || length < 0 || offset > destination.length() - length {
    raise io_error(InvalidInput, "BufReaderAdapter::read")
  }
  @buffer.Buf::copy_to(
    self.inner,
    destination.mut_view(start=offset, end=offset + length),
  )
}

///|
pub impl[B : @buffer.Buf] BufRead for BufReaderAdapter[B] with fn fill_buf(self) {
  @buffer.Buf::chunk(self.inner).view()
}

///|
pub impl[B : @buffer.Buf] BufRead for BufReaderAdapter[B] with fn consume(
  self,
  count,
) {
  @buffer.Buf::advance(self.inner, count) catch {
    error =>
      raise io_error(
        InvalidInput,
        "BufReaderAdapter::consume",
        message=@debug.render(Repr(error)),
      )
  }
}

///|
/// Expose an in-memory `BufMut` as a synchronous writer.
pub struct BufMutWriterAdapter[B] {
  inner : B
}

///|
pub fn[B] BufMutWriterAdapter::new(inner : B) -> BufMutWriterAdapter[B] {
  { inner, }
}

///|
pub fn[B] BufMutWriterAdapter::get_ref(self : BufMutWriterAdapter[B]) -> B {
  self.inner
}

///|
pub fn[B] BufMutWriterAdapter::into_inner(self : BufMutWriterAdapter[B]) -> B {
  self.inner
}

///|
/// Freeze the wrapped mutable buffer and return its initialized range without
/// materializing it.
pub fn[B : @buffer.BufMut] BufMutWriterAdapter::into_shared_bytes(
  self : BufMutWriterAdapter[B],
) -> @buffer.SharedBytes {
  @buffer.BufMut::freeze(self.inner)
}

///|
pub impl[B : @buffer.BufMut] Write for BufMutWriterAdapter[B] with fn write(
  self,
  source,
  offset,
  length,
) {
  if offset < 0 || length < 0 || offset > source.length() - length {
    raise io_error(InvalidInput, "BufMutWriterAdapter::write")
  }
  @buffer.BufMut::put_bytes_view(self.inner, source[offset:offset + length]) catch {
    error =>
      raise io_error(
        WriteZero,
        "BufMutWriterAdapter::write",
        message=@debug.render(Repr(error)),
      )
  }
  length
}

///|
pub impl[B : @buffer.BufMut] Write for BufMutWriterAdapter[B] with fn flush(
  _self,
) {
  ()
}
