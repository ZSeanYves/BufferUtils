///|
pub impl AsyncRead for @fs.File with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  @runtime_io.Reader::read(self, destination, offset~, max_len~) catch {
    err => raise map_async_error("async file read", err)
  }
}

///|
pub impl AsyncWrite for @fs.File with fn write(self, source, offset~, len~) {
  @runtime_io.Writer::write_once(self, source, offset~, len~) catch {
    err => raise map_async_error("async file write", err)
  }
}

///|
pub impl AsyncWrite for @fs.File with fn flush(self) {
  self.sync() catch {
    err => raise map_async_error("async file flush", err)
  }
}

///|
pub impl AsyncRead for @socket.Tcp with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  @runtime_io.Reader::read(self, destination, offset~, max_len~) catch {
    err => raise map_async_error("async tcp read", err)
  }
}

///|
pub impl AsyncWrite for @socket.Tcp with fn write(self, source, offset~, len~) {
  @runtime_io.Writer::write_once(self, source, offset~, len~) catch {
    err => raise map_async_error("async tcp write", err)
  }
}

///|
pub impl AsyncWrite for @socket.Tcp with fn flush(_self) {
  ()
}

///|
pub impl AsyncWrite for @socket.Tcp with fn shutdown(self) {
  let status = async_tcp_shutdown_ffi(self.fd(), 1)
  if status != 0 {
    raise @syncio.io_error(
      @syncio.Backend,
      "async tcp shutdown",
      raw_code=status,
      message="runtime TCP write-half shutdown failed",
    )
  }
}

///|
/// A file adapter with an explicit offset independent from the runtime stream.
pub struct AsyncFile {
  file : @fs.File
  mut position : Int64
  mut closed : Bool
}

///|
pub async fn AsyncFile::open_read(path : StringView) -> AsyncFile {
  { file: @fs.open(path, mode=@fs.ReadOnly), position: 0L, closed: false }
}

///|
pub async fn AsyncFile::create(path : StringView) -> AsyncFile {
  {
    file: @fs.open(path, mode=@fs.ReadWrite, create_mode=@fs.CreateOrTruncate),
    position: 0L,
    closed: false,
  }
}

///|
pub impl AsyncRead for AsyncFile with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  if self.closed {
    raise @syncio.io_error(@syncio.Closed, "async file read")
  }
  let count = self.file.read_at(
    destination,
    position=self.position,
    offset~,
    len=max_len,
  ) catch {
    err => raise map_async_error("async file read_at", err)
  }
  self.position += count.to_int64()
  count
}

///|
pub impl AsyncWrite for AsyncFile with fn write(self, source, offset~, len~) {
  if self.closed {
    raise @syncio.io_error(@syncio.Closed, "async file write")
  }
  self.file.write_at(source[offset:offset + len], position=self.position) catch {
    err => raise map_async_error("async file write_at", err)
  }
  self.position += len.to_int64()
  len
}

///|
pub impl AsyncWrite for AsyncFile with fn flush(self) {
  self.file.sync() catch {
    err => raise map_async_error("async file flush", err)
  }
}

///|
pub impl AsyncSeek for AsyncFile with fn seek(self, from) {
  if self.closed {
    raise @syncio.io_error(@syncio.Closed, "async file seek")
  }
  let target = match from {
    Start(offset) => offset
    Current(offset) => self.position + offset
    End(offset) => {
      let size = self.file.size() catch {
        err => raise map_async_error("async file size", err)
      }
      size + offset
    }
  }
  if target < 0L {
    raise @syncio.io_error(@syncio.InvalidInput, "async file seek")
  }
  self.position = target
  target
}

///|
pub impl AsyncSeek for AsyncFile with fn stream_position(self) {
  self.seek(Current(0L))
}

///|
pub impl AsyncClose for AsyncFile with fn close(self) {
  if !self.closed {
    self.file.close()
    self.closed = true
  }
}

///|
pub impl AsyncClose for AsyncFile with fn is_closed(self) {
  self.closed
}

///|
/// A runtime TCP adapter with deterministic close state.
pub struct AsyncTcpStream {
  stream : @socket.Tcp
  mut closed : Bool
}

///|
pub async fn AsyncTcpStream::connect(
  host : StringView,
  port : Int,
) -> AsyncTcpStream {
  { stream: @socket.Tcp::connect_to_host(host, port~), closed: false }
}

///|
pub impl AsyncRead for AsyncTcpStream with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  if self.closed {
    raise @syncio.io_error(@syncio.Closed, "async tcp read")
  }
  @runtime_io.Reader::read(self.stream, destination, offset~, max_len~) catch {
    err => raise map_async_error("async tcp read", err)
  }
}

///|
pub impl AsyncWrite for AsyncTcpStream with fn write(
  self,
  source,
  offset~,
  len~,
) {
  if self.closed {
    raise @syncio.io_error(@syncio.Closed, "async tcp write")
  }
  @runtime_io.Writer::write_once(self.stream, source, offset~, len~) catch {
    err => raise map_async_error("async tcp write", err)
  }
}

///|
pub impl AsyncWrite for AsyncTcpStream with fn flush(_self) {
  ()
}

///|
pub impl AsyncWrite for AsyncTcpStream with fn shutdown(self) {
  if self.closed {
    raise @syncio.io_error(@syncio.Closed, "async tcp shutdown")
  }
  let status = async_tcp_shutdown_ffi(self.stream.fd(), 1)
  if status != 0 {
    raise @syncio.io_error(
      @syncio.Backend,
      "async tcp shutdown",
      raw_code=status,
      message="runtime TCP write-half shutdown failed",
    )
  }
}

///|
pub impl AsyncClose for AsyncTcpStream with fn close(self) {
  if !self.closed {
    self.stream.close()
    self.closed = true
  }
}

///|
pub impl AsyncClose for AsyncTcpStream with fn is_closed(self) {
  self.closed
}

///|
/// A runtime TCP listener that yields close-aware stream adapters.
pub struct AsyncTcpListener {
  server : @socket.TcpServer
  mut closed : Bool
}

///|
pub async fn AsyncTcpListener::bind(address : String) -> AsyncTcpListener {
  { server: @socket.TcpServer(@socket.Addr::parse(address)), closed: false }
}

///|
pub fn AsyncTcpListener::local_port(self : AsyncTcpListener) -> Int {
  self.server.addr.port()
}

///|
pub async fn AsyncTcpListener::accept(
  self : AsyncTcpListener,
) -> AsyncTcpStream {
  if self.closed {
    raise @syncio.io_error(@syncio.Closed, "async tcp accept")
  }
  let (stream, _) = self.server.accept()
  { stream, closed: false }
}

///|
pub impl AsyncClose for AsyncTcpListener with fn close(self) {
  if !self.closed {
    self.server.close()
    self.closed = true
  }
}

///|
pub impl AsyncClose for AsyncTcpListener with fn is_closed(self) {
  self.closed
}
