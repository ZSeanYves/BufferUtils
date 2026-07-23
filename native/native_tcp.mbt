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
pub impl @io.Read for NativeTcpStream with fn read(self, dst, offset, length) {
  if offset < 0 || length < 0 || offset > dst.length() - length {
    raise @io.io_error(@io.InvalidInput, "tcp read", path=self.host)
  }
  if length == 0 {
    return 0
  }
  let count = native_tcp_read_ffi(self.handle, dst, offset, length)
  if count < 0 {
    raise native_error(
      "tcp read",
      self.host,
      -count,
      raw_code=native_tcp_os_error_ffi(self.handle),
    )
  }
  count
}

///|
/// Native fixed-array reads avoid allocating a scratch buffer per syscall.
pub impl @io.Read for NativeTcpStream with fn read_fixed(
  self,
  destination,
  offset,
  max_len,
) {
  if offset < 0 || max_len < 0 || offset > destination.length() - max_len {
    raise @io.io_error(@io.InvalidInput, "tcp read", path=self.host)
  }
  if max_len == 0 {
    return 0
  }
  let count = native_tcp_read_ffi(self.handle, destination, offset, max_len)
  if count < 0 {
    raise native_error(
      "tcp read",
      self.host,
      -count,
      raw_code=native_tcp_os_error_ffi(self.handle),
    )
  }
  count
}

///|
pub impl @io.Write for NativeTcpStream with fn write(self, src, offset, length) {
  if offset < 0 || length < 0 || offset > src.length() - length {
    raise @io.io_error(@io.InvalidInput, "tcp write", path=self.host)
  }
  if length == 0 {
    return 0
  }
  let count = native_tcp_write_ffi(self.handle, src, offset, length)
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
pub fn NativeTcpStream::shutdown_read(
  self : NativeTcpStream,
) -> Unit raise @io.IoError {
  let status = native_tcp_shutdown_ffi(self.handle, 0)
  if status != 0 {
    raise native_error(
      "tcp shutdown_read",
      self.host,
      status,
      raw_code=native_tcp_os_error_ffi(self.handle),
    )
  }
}

///|
pub fn NativeTcpStream::shutdown_write(
  self : NativeTcpStream,
) -> Unit raise @io.IoError {
  let status = native_tcp_shutdown_ffi(self.handle, 1)
  if status != 0 {
    raise native_error(
      "tcp shutdown_write",
      self.host,
      status,
      raw_code=native_tcp_os_error_ffi(self.handle),
    )
  }
}

///|
pub fn NativeTcpStream::shutdown_both(
  self : NativeTcpStream,
) -> Unit raise @io.IoError {
  let status = native_tcp_shutdown_ffi(self.handle, 2)
  if status != 0 {
    raise native_error(
      "tcp shutdown_both",
      self.host,
      status,
      raw_code=native_tcp_os_error_ffi(self.handle),
    )
  }
}

///|
pub fn NativeTcpStream::set_timeouts(
  self : NativeTcpStream,
  read_ms : Int,
  write_ms : Int,
) -> Unit raise @io.IoError {
  if read_ms < 0 || write_ms < 0 {
    raise @io.io_error(@io.InvalidInput, "tcp timeout", path=self.host)
  }
  let status = native_tcp_timeout_ffi(self.handle, read_ms, write_ms)
  if status != 0 {
    raise native_error("tcp timeout", self.host, status)
  }
}

///|
pub fn NativeTcpStream::local_port(
  self : NativeTcpStream,
) -> Int raise @io.IoError {
  let port = native_tcp_local_port_ffi(self.handle)
  if port < 0 {
    raise native_error("tcp local_port", self.host, -port)
  }
  port
}

///|
pub fn NativeTcpStream::peer_port(
  self : NativeTcpStream,
) -> Int raise @io.IoError {
  let port = native_tcp_peer_port_ffi(self.handle)
  if port < 0 {
    raise native_error("tcp peer_port", self.host, -port)
  }
  port
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
