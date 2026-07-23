///|
fn native_host(host : String) -> Bytes raise @io.IoError {
  if host == "" {
    raise @io.io_error(@io.InvalidInput, "tcp", message="host is empty")
  }
  @utf8.encode(host)
}

///|
/// A blocking native TCP byte stream.
pub struct NativeTcpStream {
  host : String
  port : Int
  handle : NativeSocketHandle
}

///|
pub fn NativeTcpStream::connect(
  host : String,
  port : Int,
) -> NativeTcpStream raise @io.IoError {
  let encoded = native_host(host)
  let handle = native_tcp_connect_ffi(encoded, encoded.length(), port)
  if native_tcp_is_closed_ffi(handle) != 0 {
    raise native_error(
      "tcp connect",
      host,
      native_tcp_error_ffi(handle),
      raw_code=native_tcp_os_error_ffi(handle),
    )
  }
  { host, port, handle }
}

///|
pub impl @io.Read for NativeTcpStream with fn read(self, dst) {
  if dst.is_empty() {
    return 0
  }
  let scratch = FixedArray::make(dst.length(), (0).to_byte())
  let count = native_tcp_read_ffi(self.handle, scratch, scratch.length())
  if count < 0 {
    raise native_error(
      "tcp read",
      self.host,
      -count,
      raw_code=native_tcp_os_error_ffi(self.handle),
    )
  }
  for i in 0..<count {
    dst[i] = scratch[i]
  }
  count
}

///|
pub impl @io.Write for NativeTcpStream with fn write(self, src) {
  if src.is_empty() {
    return 0
  }
  let bytes = Bytes::from_array(src)
  let count = native_tcp_write_ffi(self.handle, bytes, bytes.length())
  if count < 0 {
    raise native_error(
      "tcp write",
      self.host,
      -count,
      raw_code=native_tcp_os_error_ffi(self.handle),
    )
  }
  count
}

///|
pub impl @io.Write for NativeTcpStream with fn flush(_self) {
  ()
}

///|
pub impl @io.Close for NativeTcpStream with fn close(self) {
  let status = native_tcp_close_ffi(self.handle)
  if status != 0 {
    raise native_error(
      "tcp close",
      self.host,
      status,
      raw_code=native_tcp_os_error_ffi(self.handle),
    )
  }
}

///|
pub impl @io.Close for NativeTcpStream with fn is_closed(self) {
  native_tcp_is_closed_ffi(self.handle) != 0
}

///|
/// A blocking native TCP listener.
pub struct NativeTcpListener {
  host : String
  handle : NativeSocketHandle
}

///|
pub fn NativeTcpListener::bind(
  host : String,
  port : Int,
) -> NativeTcpListener raise @io.IoError {
  let encoded = native_host(host)
  let handle = native_tcp_listen_ffi(encoded, encoded.length(), port)
  if native_tcp_is_closed_ffi(handle) != 0 {
    raise native_error(
      "tcp bind",
      host,
      native_tcp_error_ffi(handle),
      raw_code=native_tcp_os_error_ffi(handle),
    )
  }
  { host, handle }
}

///|
pub fn NativeTcpListener::local_port(
  self : NativeTcpListener,
) -> Int raise @io.IoError {
  let port = native_tcp_local_port_ffi(self.handle)
  if port < 0 {
    raise native_error(
      "tcp local_port",
      self.host,
      -port,
      raw_code=native_tcp_os_error_ffi(self.handle),
    )
  }
  port
}

///|
pub fn NativeTcpListener::accept(
  self : NativeTcpListener,
) -> NativeTcpStream raise @io.IoError {
  let handle = native_tcp_accept_ffi(self.handle)
  if native_tcp_is_closed_ffi(handle) != 0 {
    raise native_error(
      "tcp accept",
      self.host,
      native_tcp_error_ffi(handle),
      raw_code=native_tcp_os_error_ffi(handle),
    )
  }
  { host: self.host, port: self.local_port(), handle }
}

///|
pub impl @io.Close for NativeTcpListener with fn close(self) {
  let status = native_tcp_close_ffi(self.handle)
  if status != 0 {
    raise native_error(
      "tcp listener close",
      self.host,
      status,
      raw_code=native_tcp_os_error_ffi(self.handle),
    )
  }
}

///|
pub impl @io.Close for NativeTcpListener with fn is_closed(self) {
  native_tcp_is_closed_ffi(self.handle) != 0
}
