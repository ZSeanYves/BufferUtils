///|
/// Present two buffers as one logical cursor without concatenating storage.
pub struct BufChain[A, B] {
  first : A
  second : B
}

///|
pub fn[A, B] BufChain::new(first : A, second : B) -> BufChain[A, B] {
  { first, second }
}

///|
pub fn[A, B] BufChain::into_parts(self : BufChain[A, B]) -> (A, B) {
  (self.first, self.second)
}

///|
pub impl[A : Buf, B : Buf] Buf for BufChain[A, B] with fn remaining(self) {
  let first = Buf::remaining(self.first)
  let second = Buf::remaining(self.second)
  if first > 2147483647 - second {
    2147483647
  } else {
    first + second
  }
}

///|
pub impl[A : Buf, B : Buf] Buf for BufChain[A, B] with fn chunk(self) {
  if Buf::remaining(self.first) > 0 {
    Buf::chunk(self.first)
  } else {
    Buf::chunk(self.second)
  }
}

///|
pub impl[A : Buf, B : Buf] Buf for BufChain[A, B] with fn advance(self, count) {
  if count < 0 || count > Buf::remaining(self) {
    raise BufferError::Underflow(count, Buf::remaining(self))
  }
  let first = Buf::remaining(self.first)
  let from_first = Int::min(count, first)
  Buf::advance(self.first, from_first)
  Buf::advance(self.second, count - from_first)
}

///|
pub impl[A : Buf, B : Buf] Buf for BufChain[A, B] with fn copy_to(self, dst) {
  let first = Buf::copy_to(self.first, dst)
  if first == dst.length() {
    first
  } else {
    first + Buf::copy_to(self.second, dst.mut_view(start=first))
  }
}

///|
/// Limit a buffer cursor to at most `limit` bytes.
pub struct BufTake[B] {
  inner : B
  mut limit : Int
}

///|
pub fn[B] BufTake::new(inner : B, limit : Int) -> BufTake[B] raise BufferError {
  if limit < 0 {
    raise BufferError::InvalidRange("buffer limit must be non-negative")
  }
  { inner, limit }
}

///|
pub fn[B] BufTake::into_inner(self : BufTake[B]) -> B {
  self.inner
}

///|
pub fn[B : Buf] BufTake::limit(self : BufTake[B]) -> Int {
  Int::min(self.limit, Buf::remaining(self.inner))
}

///|
pub impl[B : Buf] Buf for BufTake[B] with fn remaining(self) {
  self.limit()
}

///|
pub impl[B : Buf] Buf for BufTake[B] with fn chunk(self) {
  let chunk = Buf::chunk(self.inner)
  {
    data: chunk.data,
    start: chunk.start,
    end: chunk.start + Int::min(chunk.remaining(), self.limit()),
    copied_bytes: chunk.copied_bytes,
  }
}

///|
pub impl[B : Buf] Buf for BufTake[B] with fn advance(self, count) {
  if count < 0 || count > self.limit() {
    raise BufferError::Underflow(count, self.limit())
  }
  Buf::advance(self.inner, count)
  self.limit -= count
}

///|
pub impl[B : Buf] Buf for BufTake[B] with fn copy_to(self, dst) {
  let count = Int::min(dst.length(), self.limit())
  let progress = Buf::copy_to(self.inner, dst.mut_view(end=count))
  self.limit -= progress
  progress
}
