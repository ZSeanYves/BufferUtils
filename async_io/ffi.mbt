///|
/// Performs a platform half-close without copying or taking ownership of the
/// runtime socket. `how = 1` means write-half shutdown.
extern "C" fn async_tcp_shutdown_ffi(fd : @async_types.Fd, how : Int) -> Int = "bufferutils_async_tcp_shutdown"
