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
    let bytes = buffer.unsafe_reinterpret_as_bytes()
    @async.protect_from_cancel(() => {
      AsyncWrite::write_all(writer, bytes, offset=0, len=count)
      total += count
    })
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
    let left_to_right = group.spawn(() => {
      let count = copy(left, right)
      AsyncWrite::shutdown(right)
      count
    })
    let right_to_left = group.spawn(() => {
      let count = copy(right, left)
      AsyncWrite::shutdown(left)
      count
    })
    (left_to_right.wait(), right_to_left.wait())
  })
}
