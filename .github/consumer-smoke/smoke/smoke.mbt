///|
pub fn sync_native_smoke() -> Unit raise {
  let mutable = @buffer.BytesMut::new(capacity=16)
  mutable.put_u32_be(0x12345678U)
  let shared = mutable.freeze()
  guard shared.remaining() == 4 else {
    abort("shared buffer smoke test failed")
  }

  let reader = @io.BufReader::new(@io.MemoryReader::new(b"first\nsecond\n"))
  guard reader.lines().next() == Some("first") else {
    abort("synchronous cursor smoke test failed")
  }

  let listener = @native.NativeTcpListener::bind("127.0.0.1", 0)
  guard listener.local_addr().port > 0 else {
    abort("native address smoke test failed")
  }
  @io.Close::close(listener)
}

///|
pub async fn async_smoke() -> Unit {
  let source = @asyncio.AsyncMemoryReader::new(b"async-smoke"[:])
  let destination = @asyncio.AsyncMemoryWriter::new()
  let progress = @asyncio.copy(source, destination, buffer_size=4)
  guard progress == 11 && destination.to_bytes() == b"async-smoke" else {
    abort("asynchronous copy smoke test failed")
  }
}
