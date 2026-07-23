///|
pub fn tcp_shutdown_example(
  stream : @native.NativeTcpStream,
) -> Unit raise @io.IoError {
  stream.set_timeouts(5000, 5000)
  stream.shutdown_write()
}
