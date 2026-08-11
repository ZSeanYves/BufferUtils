///|
struct SharedPendingReader {
  mut calls : Int
}

///|
impl AsyncRead for SharedPendingReader with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  if max_len == 0 {
    return 0
  }
  if self.calls == 0 {
    self.calls += 1
    @async.pause()
    destination[offset] = b'p'
    return 1
  }
  0
}

///|
struct SharedReadCancelReader {
  mut calls : Int
}

///|
struct InvalidSharedReader {}

///|
impl AsyncRead for InvalidSharedReader with fn read(
  _self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  ignore(max_len)
  destination.length() + 1
}

///|
impl AsyncRead for SharedReadCancelReader with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  if max_len == 0 {
    return 0
  }
  if self.calls == 0 {
    self.calls += 1
    destination[offset] = b'r'
    return 1
  }
  @async.pause()
  0
}

///|
struct SharedWriteCancelWriter {
  output : Array[Byte]
  mut calls : Int
}

///|
struct SharedPartialThenZeroWriter {
  output : Array[Byte]
  mut calls : Int
}

///|
impl AsyncWrite for SharedPartialThenZeroWriter with fn write(
  self,
  source,
  offset~,
  len~,
) {
  if self.calls > 0 {
    return 0
  }
  self.calls += 1
  let count = Int::min(2, len)
  for i in 0..<count {
    self.output.push(source[offset + i])
  }
  count
}

///|
impl AsyncWrite for SharedPartialThenZeroWriter with fn flush(_self) {
  ()
}

///|
impl AsyncWrite for SharedWriteCancelWriter with fn write(
  self,
  source,
  offset~,
  len~,
) {
  if self.calls == 0 {
    let count = Int::min(2, len)
    for i in 0..<count {
      self.output.push(source[offset + i])
    }
    self.calls += 1
    @async.pause()
    return count
  }
  let count = len
  for i in 0..<count {
    self.output.push(source[offset + i])
  }
  self.calls += 1
  count
}

///|
impl AsyncWrite for SharedWriteCancelWriter with fn flush(_self) {
  ()
}

///|
async test "async shared streaming preserves ownership and ranges" {
  let reader = AsyncMemoryReader::new(b"payload"[:])
  let shared = read_to_shared_bytes(reader)
  assert_eq(shared.to_bytes(), b"payload")
  let clone = shared.clone()
  assert_true(
    physical_equal(shared.as_bytes_view().data(), clone.as_bytes_view().data()),
  )
  let materialized = read_to_end(AsyncMemoryReader::new(b"payload"[:]))
  assert_false(physical_equal(shared.as_bytes_view().data(), materialized))

  let source = @buffer.SharedBytes::from_array(
    [b'_', b'a', b'b', b'c', b'd', b'e', b'f', b'_'][:],
  )
  let partial : ShortAsyncWriter = { output: [], max_chunk: 2 }
  assert_eq(write_shared(partial, source, offset=1, len=4), 2)
  assert_eq(Bytes::from_array(partial.output), b"ab")
  let complete : ShortAsyncWriter = { output: [], max_chunk: 2 }
  write_all_shared(complete, source, offset=1, len=6)
  assert_eq(Bytes::from_array(complete.output), b"abcdef")
  assert_eq(read_to_shared_bytes(AsyncMemoryReader::new(b""[:])).len(), 0)
}

///|
async test "async shared streaming preserves pending then EOF" {
  let pending : SharedPendingReader = { calls: 0 }
  assert_eq(read_to_shared_bytes(pending).to_bytes(), b"p")
}

///|
async test "async shared read rejects invalid progress" {
  let invalid = try {
    ignore(read_to_shared_bytes(InvalidSharedReader::{  }))
    false
  } catch {
    error => async_error_has_kind(error, @syncio.ContractViolation)
  }
  assert_true(invalid)
}

///|
async test "async shared write rejects invalid ranges and progress" {
  let source = @buffer.SharedBytes::from_array([b'a', b'b', b'c'][:])
  let invalid_range = try {
    ignore(write_shared(AsyncMemoryWriter::new(), source, offset=2, len=2))
    false
  } catch {
    error => async_error_has_kind(error, @syncio.InvalidInput)
  }
  assert_true(invalid_range)

  let zero = try {
    write_all_shared(AlwaysZeroAsyncWriter::Zero, source)
    false
  } catch {
    error => async_error_has_kind(error, @syncio.WriteZero)
  }
  assert_true(zero)

  let invalid_progress = try {
    ignore(write_shared(InvalidAsyncWriter::InvalidAsyncWriter, source))
    false
  } catch {
    error => async_error_has_kind(error, @syncio.ContractViolation)
  }
  assert_true(invalid_progress)
}

///|
async test "async shared write reports cumulative failure progress" {
  let source = @buffer.SharedBytes::from_array([b'a', b'b', b'c'][:])
  let partial : PartialThenFailWriter = { output: [], calls: 0 }
  let progress = try {
    write_all_shared(partial, source)
    -1
  } catch {
    @syncio.IoError::Io(failure) => failure.progress
    _ => -1
  }
  assert_eq(progress, 2)
  assert_eq(Bytes::from_array(partial.output), b"ab")

  let zero : SharedPartialThenZeroWriter = { output: [], calls: 0 }
  let zero_progress = try {
    write_all_shared(zero, source)
    -1
  } catch {
    @syncio.IoError::Io(failure) => failure.progress
    _ => -1
  }
  assert_eq(zero_progress, 2)
  assert_eq(Bytes::from_array(zero.output), b"ab")
}

///|
async test "async shared read cancellation occurs after completed chunk" {
  let reader : SharedReadCancelReader = { calls: 0 }
  let cancelled = Ref(false)
  @async.with_task_group(group => {
    let task = group.spawn(() => ignore(read_to_shared_bytes(reader)))
    @async.pause()
    task.cancel()
    try task.wait() catch {
      error => cancelled.val = @async.is_cancellation_error(error)
    } noraise {
      _ => fail("shared read cancellation unexpectedly completed")
    }
  })
  assert_eq(reader.calls, 1)
  assert_true(cancelled.val)
}

///|
async test "async shared write cancellation preserves committed short write" {
  let writer : SharedWriteCancelWriter = { output: [], calls: 0 }
  let source = @buffer.SharedBytes::from_array(
    [b'a', b'b', b'c', b'd', b'e', b'f'][:],
  )
  let cancelled = Ref(false)
  @async.with_task_group(group => {
    let task = group.spawn(() => write_all_shared(writer, source))
    @async.pause()
    task.cancel()
    try task.wait() catch {
      error => cancelled.val = @async.is_cancellation_error(error)
    } noraise {
      _ => fail("shared write cancellation unexpectedly completed")
    }
  })
  assert_true(cancelled.val)
  assert_eq(Bytes::from_array(writer.output), b"ab")
}
