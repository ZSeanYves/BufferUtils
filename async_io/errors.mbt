///|
/// Normalize errors crossing the async adapter boundary. Cancellation and
/// already structured I/O errors retain their identity; runtime OS failures
/// receive the same portable categories as synchronous I/O.
fn map_async_error(operation : String, err : Error) -> Error {
  if @async.is_cancellation_error(err) {
    return err
  }
  match err {
    @syncio.IoError::Io(_) => err
    @os_error.OSError::OSError(code, context~) as os_error => {
      let kind = if os_error.is_ENOENT() || os_error.is_ENOTDIR() {
        @syncio.NotFound
      } else if os_error.is_EACCES() {
        @syncio.PermissionDenied
      } else if os_error.is_ECONNREFUSED() {
        @syncio.ConnectionRefused
      } else if os_error.is_EINTR() {
        @syncio.Interrupted
      } else if os_error.is_nonblocking_io_error() {
        @syncio.WouldBlock
      } else {
        @syncio.Backend
      }
      @syncio.io_error(
        kind,
        operation,
        context~,
        raw_code=code,
        message=os_error.to_string(),
      )
    }
    _ => @syncio.io_error(@syncio.Backend, operation, message=err.to_string())
  }
}
