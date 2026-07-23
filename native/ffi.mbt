///|
type NativeFileHandle

///|
type NativeMappedHandle

///|
type NativeSocketHandle

///|
#borrow(path)
extern "C" fn native_file_open_ffi(
  path : Bytes,
  length : Int,
  mode : Int,
) -> NativeFileHandle = "bufferutils_file_open"

///|
#borrow(handle, destination)
extern "C" fn native_file_read_ffi(
  handle : NativeFileHandle,
  destination : FixedArray[Byte],
  length : Int,
) -> Int = "bufferutils_file_read"

///|
#borrow(handle, source)
extern "C" fn native_file_write_ffi(
  handle : NativeFileHandle,
  source : Bytes,
  length : Int,
) -> Int = "bufferutils_file_write"

///|
#borrow(handle)
extern "C" fn native_file_flush_ffi(handle : NativeFileHandle) -> Int = "bufferutils_file_flush"

///|
#borrow(handle)
extern "C" fn native_file_seek_ffi(
  handle : NativeFileHandle,
  offset : Int64,
  whence : Int,
) -> Int64 = "bufferutils_file_seek"

///|
#borrow(handle)
extern "C" fn native_file_error_ffi(handle : NativeFileHandle) -> Int = "bufferutils_file_error"

///|
#borrow(handle)
extern "C" fn native_file_os_error_ffi(handle : NativeFileHandle) -> Int = "bufferutils_file_os_error"

///|
#borrow(handle)
extern "C" fn native_file_close_ffi(handle : NativeFileHandle) -> Int = "bufferutils_file_close"

///|
#borrow(handle)
extern "C" fn native_file_is_closed_ffi(handle : NativeFileHandle) -> Int = "bufferutils_file_is_closed"

///|
#borrow(path)
extern "C" fn native_mapped_open_ffi(
  path : Bytes,
  length : Int,
) -> NativeMappedHandle = "bufferutils_mapped_open"

///|
#borrow(handle)
extern "C" fn native_mapped_slice_ffi(
  handle : NativeMappedHandle,
  start : Int,
  length : Int,
) -> NativeMappedHandle = "bufferutils_mapped_slice"

///|
#borrow(handle)
extern "C" fn native_mapped_len_ffi(handle : NativeMappedHandle) -> Int = "bufferutils_mapped_len"

///|
#borrow(handle)
extern "C" fn native_mapped_error_ffi(handle : NativeMappedHandle) -> Int = "bufferutils_mapped_error"

///|
#borrow(handle)
extern "C" fn native_mapped_os_error_ffi(handle : NativeMappedHandle) -> Int = "bufferutils_mapped_os_error"

///|
#borrow(handle)
extern "C" fn native_mapped_read_byte_ffi(
  handle : NativeMappedHandle,
  index : Int,
) -> Int = "bufferutils_mapped_read_byte"

///|
#borrow(handle)
extern "C" fn native_mapped_copy_ffi(
  handle : NativeMappedHandle,
  start : Int,
  length : Int,
) -> Bytes = "bufferutils_mapped_copy"

///|
#borrow(handle)
extern "C" fn native_mapped_find_ffi(
  handle : NativeMappedHandle,
  value : Int,
) -> Int = "bufferutils_mapped_find"

///|
#borrow(handle)
extern "C" fn native_mapped_close_ffi(handle : NativeMappedHandle) -> Int = "bufferutils_mapped_close"

///|
#borrow(handle)
extern "C" fn native_mapped_is_closed_ffi(handle : NativeMappedHandle) -> Int = "bufferutils_mapped_is_closed"

///|
#borrow(host)
extern "C" fn native_tcp_connect_ffi(
  host : Bytes,
  host_length : Int,
  port : Int,
) -> NativeSocketHandle = "bufferutils_tcp_connect"

///|
#borrow(host)
extern "C" fn native_tcp_listen_ffi(
  host : Bytes,
  host_length : Int,
  port : Int,
) -> NativeSocketHandle = "bufferutils_tcp_listen"

///|
#borrow(listener)
extern "C" fn native_tcp_accept_ffi(
  listener : NativeSocketHandle,
) -> NativeSocketHandle = "bufferutils_tcp_accept"

///|
#borrow(listener)
extern "C" fn native_tcp_local_port_ffi(listener : NativeSocketHandle) -> Int = "bufferutils_tcp_local_port"

///|
#borrow(socket, destination)
extern "C" fn native_tcp_read_ffi(
  socket : NativeSocketHandle,
  destination : FixedArray[Byte],
  length : Int,
) -> Int = "bufferutils_tcp_read"

///|
#borrow(socket, source)
extern "C" fn native_tcp_write_ffi(
  socket : NativeSocketHandle,
  source : Bytes,
  length : Int,
) -> Int = "bufferutils_tcp_write"

///|
#borrow(socket)
extern "C" fn native_tcp_close_ffi(socket : NativeSocketHandle) -> Int = "bufferutils_tcp_close"

///|
#borrow(socket)
extern "C" fn native_tcp_is_closed_ffi(socket : NativeSocketHandle) -> Int = "bufferutils_tcp_is_closed"

///|
#borrow(socket)
extern "C" fn native_tcp_error_ffi(socket : NativeSocketHandle) -> Int = "bufferutils_tcp_error"

///|
#borrow(socket)
extern "C" fn native_tcp_os_error_ffi(socket : NativeSocketHandle) -> Int = "bufferutils_tcp_os_error"
