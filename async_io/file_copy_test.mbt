///|
let async_test_dir = ".tmp/bufferutils-async-tests"

///|
async fn ensure_async_test_dir() -> Unit {
  if !@fs.exists(".tmp") {
    @fs.mkdir(".tmp")
  }
  if !@fs.exists(async_test_dir) {
    @fs.mkdir(async_test_dir)
  }
}

///|
async test "async copy reuses bounded chunks and reports committed progress" {
  ensure_async_test_dir()
  let source = async_test_dir + "/copy-source.bin"
  let destination = async_test_dir + "/copy-destination.bin"
  let data = b"0123456789abcdef"
  write_file(source, data[:])
  let observations : Array[Int] = []
  let progress = copy_file(source, destination, buffer_size=3, on_progress=fn(
    current,
  ) {
    observations.push(current.bytes)
  })
  assert_eq(progress.bytes, data.length())
  assert_eq(progress.write_calls, 6)
  assert_eq(progress.read_calls, 7)
  assert_eq(observations, [3, 6, 9, 12, 15, 16])
  assert_eq(read_file(destination), data)
}

///|
async test "async copy rejects a non-positive buffer size before opening files" {
  let failed = try {
    ignore(copy_file("unused-source", "unused-destination", buffer_size=0))
    false
  } catch {
    _ => true
  }
  assert_eq(failed, true)
}

///|
async test "async copy cancellation leaves only committed progress observable" {
  ensure_async_test_dir()
  let source = async_test_dir + "/cancel-source.bin"
  let destination = async_test_dir + "/cancel-destination.bin"
  let data = Bytes::makei(1024 * 1024, i => (i % 251).to_byte())
  write_file(source, data[:])
  let mut committed = 0
  let mut cancelled = false
  @async.with_task_group(root => {
    let task = root.spawn(() => {
      copy_file(source, destination, buffer_size=1, on_progress=fn(current) {
        committed = current.bytes
      })
    })
    @async.pause()
    task.cancel()
    try task.wait() catch {
      error => cancelled = @async.is_cancellation_error(error)
    } noraise {
      _ => ()
    }
  })
  assert_eq(cancelled, true)
  assert_eq(committed < data.length(), true)
  if @fs.exists(destination) {
    assert_eq(read_file(destination).length(), committed)
  }
}
