///|
pub async fn[R : AsyncRead, W : AsyncWrite] copy(
  reader : R,
  writer : W,
  buffer_size? : Int = 8192,
) -> Int {
  if buffer_size <= 0 {
    raise @syncio.io_error(@syncio.InvalidInput, "async copy")
  }
  let buffer = FixedArray::make(buffer_size, (0).to_byte())
  let mut total = 0
  while true {
    let count = AsyncRead::read(reader, buffer)
    if count == 0 {
      break
    }
    let bytes = Bytes::makei(count, i => buffer[i])
    AsyncWrite::write_all(writer, bytes)
    total += count
  }
  total
}

///|
/// Copy both halves concurrently. Each result counts bytes committed to its peer.
pub async fn[A : AsyncRead + AsyncWrite, B : AsyncRead + AsyncWrite] copy_bidirectional(
  left : A,
  right : B,
) -> (Int, Int) {
  @async.with_task_group(group => {
    let left_to_right = group.spawn(() => copy(left, right))
    let right_to_left = group.spawn(() => copy(right, left))
    (left_to_right.wait(), right_to_left.wait())
  })
}
