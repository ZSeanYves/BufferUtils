///|
fn native_error_kind(code : Int) -> @io.IoErrorKind {
  match code {
    12 => @io.Interrupted
    13 => @io.NotFound
    14 => @io.PermissionDenied
    15 => @io.WouldBlock
    16 => @io.TimedOut
    17 => @io.ConnectionReset
    18 => @io.BrokenPipe
    19 => @io.ConnectionRefused
    20 => @io.NotConnected
    21 => @io.AddressInUse
    22 => @io.AddressNotAvailable
    23 => @io.StorageFull
    24 => @io.OutOfMemory
    7 => @io.InvalidInput
    8 => @io.Closed
    9 => @io.NotSeekable
    11 => @io.Unsupported
    _ => @io.Backend
  }
}

///|
fn native_error(
  operation : String,
  path : String,
  code : Int,
  progress? : Int = 0,
  raw_code? : Int = 0,
) -> @io.IoError {
  @io.io_error(
    native_error_kind(code),
    operation,
    path~,
    raw_code=if raw_code == 0 { code } else { raw_code },
    progress~,
    message="native platform operation failed",
  )
}

///|
fn native_path(path : String) -> Bytes raise @io.IoError {
  if path == "" {
    raise @io.io_error(@io.InvalidInput, "open", path~, message="path is empty")
  }
  @utf8.encode(path)
}

///|
/// Native file creation and access policy.
pub struct NativeOpenOptions {
  read : Bool
  write : Bool
  append : Bool
  create : Bool
  truncate : Bool
  create_new : Bool
}

///|
pub fn NativeOpenOptions::new() -> NativeOpenOptions {
  {
    read: false,
    write: false,
    append: false,
    create: false,
    truncate: false,
    create_new: false,
  }
}

///|
pub fn NativeOpenOptions::read() -> NativeOpenOptions {
  { ..NativeOpenOptions::new(), read: true }
}

///|
pub fn NativeOpenOptions::write() -> NativeOpenOptions {
  { ..NativeOpenOptions::new(), write: true }
}

///|
pub fn NativeOpenOptions::write_truncate() -> NativeOpenOptions {
  { ..NativeOpenOptions::new(), write: true, create: true, truncate: true }
}

///|
pub fn NativeOpenOptions::write_append() -> NativeOpenOptions {
  { ..NativeOpenOptions::new(), write: true, append: true, create: true }
}

///|
pub fn NativeOpenOptions::read_write() -> NativeOpenOptions {
  { ..NativeOpenOptions::new(), read: true, write: true }
}

///|
pub fn NativeOpenOptions::write_create_new() -> NativeOpenOptions {
  { ..NativeOpenOptions::new(), write: true, create_new: true }
}

///|
fn NativeOpenOptions::mode(self : NativeOpenOptions) -> Int {
  64 +
  (if self.read { 1 } else { 0 }) +
  (if self.write { 2 } else { 0 }) +
  (if self.append { 4 } else { 0 }) +
  (if self.create || self.create_new { 8 } else { 0 }) +
  (if self.truncate { 16 } else { 0 }) +
  (if self.create_new { 32 } else { 0 })
}

///|
/// A thread-safe external native file resource.
pub struct NativeFile {
  path : String
  handle : NativeFileHandle
  readable : Bool
  writable : Bool
}

///|
pub fn NativeFile::open_read(path : String) -> NativeFile raise @io.IoError {
  NativeFile::open(path, {
    read: true,
    write: false,
    append: false,
    create: false,
    truncate: false,
    create_new: false,
  })
}

///|
pub fn NativeFile::open(
  path : String,
  options : NativeOpenOptions,
) -> NativeFile raise @io.IoError {
  if !options.read && !options.write {
    raise @io.io_error(
      @io.InvalidInput,
      "open",
      path~,
      message="read or write is required",
    )
  }
  let encoded = native_path(path)
  let handle = native_file_open_ffi(encoded, encoded.length(), options.mode())
  if native_file_is_closed_ffi(handle) != 0 {
    raise native_error(
      "open",
      path,
      native_file_error_ffi(handle),
      raw_code=native_file_os_error_ffi(handle),
    )
  }
  { path, handle, readable: options.read, writable: options.write }
}

///|
pub fn NativeFile::create(path : String) -> NativeFile raise @io.IoError {
  NativeFile::open(path, {
    read: false,
    write: true,
    append: false,
    create: true,
    truncate: true,
    create_new: false,
  })
}

///|
pub fn NativeFile::append(path : String) -> NativeFile raise @io.IoError {
  NativeFile::open(path, {
    read: false,
    write: true,
    append: true,
    create: true,
    truncate: false,
    create_new: false,
  })
}

///|
pub fn NativeFile::path(self : NativeFile) -> String {
  self.path
}

///|
pub impl @io.Read for NativeFile with fn read(self, dst, offset, length) {
  if !self.readable {
    raise native_error("read", self.path, 7)
  }
  if offset < 0 || length < 0 || offset > dst.length() - length {
    raise @io.io_error(@io.InvalidInput, "read", path=self.path)
  }
  if length == 0 {
    return 0
  }
  let count = native_file_read_ffi(self.handle, dst, offset, length)
  if count < 0 {
    raise native_error(
      "read",
      self.path,
      -count,
      raw_code=native_file_os_error_ffi(self.handle),
    )
  }
  count
}

///|
/// Native fixed-array reads write directly into the caller's destination.
pub impl @io.Read for NativeFile with fn read_fixed(
  self,
  destination,
  offset,
  max_len,
) {
  if !self.readable {
    raise native_error("read", self.path, 7)
  }
  if offset < 0 || max_len < 0 || offset > destination.length() - max_len {
    raise @io.io_error(@io.InvalidInput, "read", path=self.path)
  }
  if max_len == 0 {
    return 0
  }
  let count = native_file_read_ffi(self.handle, destination, offset, max_len)
  if count < 0 {
    raise native_error(
      "read",
      self.path,
      -count,
      raw_code=native_file_os_error_ffi(self.handle),
    )
  }
  count
}

///|
pub impl @io.Read for NativeFile with fn read_vectored(self, destinations) {
  if !self.readable {
    raise native_error("read_vectored", self.path, 7)
  }
  if native_file_is_read_vectored_ffi(self.handle) == 0 {
    for destination in destinations {
      if !destination.is_empty() {
        return @io.Read::read(
          self,
          destination.data(),
          destination.offset(),
          destination.len(),
        )
      }
    }
    return 0
  }
  let count = Int::min(destinations.length(), 64)
  let buffers = FixedArray::make(count, FixedArray::make(0, (0).to_byte()))
  let offsets = FixedArray::make(count, 0)
  let lengths = FixedArray::make(count, 0)
  for i in 0..<count {
    buffers[i] = destinations[i].data()
    offsets[i] = destinations[i].offset()
    lengths[i] = destinations[i].len()
  }
  let result = native_file_read_vectored_ffi(
    self.handle,
    buffers,
    offsets,
    lengths,
    count,
  )
  if result < 0 {
    raise native_error(
      "read_vectored",
      self.path,
      -result,
      raw_code=native_file_os_error_ffi(self.handle),
    )
  }
  result
}

///|
pub impl @io.Read for NativeFile with fn is_read_vectored(self) {
  native_file_is_read_vectored_ffi(self.handle) != 0
}

///|
pub impl @io.Write for NativeFile with fn write(self, src, offset, length) {
  if !self.writable {
    raise native_error("write", self.path, 7)
  }
  if offset < 0 || length < 0 || offset > src.length() - length {
    raise @io.io_error(@io.InvalidInput, "write", path=self.path)
  }
  if length == 0 {
    return 0
  }
  let count = native_file_write_ffi(self.handle, src, offset, length)
  if count < 0 {
    raise native_error(
      "write",
      self.path,
      -count,
      raw_code=native_file_os_error_ffi(self.handle),
    )
  }
  count
}

///|
pub impl @io.Write for NativeFile with fn write_vectored(self, sources) {
  if !self.writable {
    raise native_error("write_vectored", self.path, 7)
  }
  if native_file_is_write_vectored_ffi(self.handle) == 0 {
    for source in sources {
      if !source.is_empty() {
        return @io.Write::write(
          self,
          source.data(),
          source.offset(),
          source.len(),
        )
      }
    }
    return 0
  }
  let count = Int::min(sources.length(), 64)
  let buffers = FixedArray::make(count, b"")
  let offsets = FixedArray::make(count, 0)
  let lengths = FixedArray::make(count, 0)
  for i in 0..<count {
    buffers[i] = sources[i].data()
    offsets[i] = sources[i].offset()
    lengths[i] = sources[i].len()
  }
  let result = native_file_write_vectored_ffi(
    self.handle,
    buffers,
    offsets,
    lengths,
    count,
  )
  if result < 0 {
    raise native_error(
      "write_vectored",
      self.path,
      -result,
      raw_code=native_file_os_error_ffi(self.handle),
    )
  }
  result
}

///|
pub impl @io.Write for NativeFile with fn is_write_vectored(self) {
  native_file_is_write_vectored_ffi(self.handle) != 0
}

///|
pub fn NativeFile::read_syscalls(self : NativeFile) -> Int {
  native_file_read_syscalls_ffi(self.handle)
}

///|
pub fn NativeFile::write_syscalls(self : NativeFile) -> Int {
  native_file_write_syscalls_ffi(self.handle)
}

///|
pub impl @io.Write for NativeFile with fn flush(_self) {
  ()
}

///|
/// Flush file metadata and contents to stable storage.
pub fn NativeFile::sync_all(self : NativeFile) -> Unit raise @io.IoError {
  let status = native_file_sync_ffi(self.handle, 0)
  if status != 0 {
    raise native_error(
      "sync_all",
      self.path,
      status,
      raw_code=native_file_os_error_ffi(self.handle),
    )
  }
}

///|
/// Flush file data without requiring metadata persistence.
pub fn NativeFile::sync_data(self : NativeFile) -> Unit raise @io.IoError {
  let status = native_file_sync_ffi(self.handle, 1)
  if status != 0 {
    raise native_error(
      "sync_data",
      self.path,
      status,
      raw_code=native_file_os_error_ffi(self.handle),
    )
  }
}

///|
fn native_seek_parts(from : @io.SeekFrom) -> (Int64, Int) {
  match from {
    @io.Start(offset) => (offset, 0)
    @io.Current(offset) => (offset, 1)
    @io.End(offset) => (offset, 2)
  }
}

///|
pub impl @io.Seek for NativeFile with fn seek(self, from) {
  let (offset, whence) = native_seek_parts(from)
  let position = native_file_seek_ffi(self.handle, offset, whence)
  if position < 0L {
    raise native_error(
      "seek",
      self.path,
      (-position).to_int(),
      raw_code=native_file_os_error_ffi(self.handle),
    )
  }
  position
}

///|
pub impl @io.Seek for NativeFile with fn stream_position(self) {
  @io.Seek::seek(self, @io.Current(0L))
}

///|
pub impl @io.Close for NativeFile with fn close(self) {
  let status = native_file_close_ffi(self.handle)
  if status != 0 {
    raise native_error(
      "close",
      self.path,
      status,
      raw_code=native_file_os_error_ffi(self.handle),
    )
  }
}

///|
pub impl @io.Close for NativeFile with fn is_closed(self) {
  native_file_is_closed_ffi(self.handle) != 0
}

///|
/// A read-only mmap view backed by a ref-counted external owner.
pub struct MappedBytes {
  path : String
  handle : NativeMappedHandle
  mut position : Int
}

///|
pub fn MappedBytes::open(path : String) -> MappedBytes raise @io.IoError {
  let encoded = native_path(path)
  let handle = native_mapped_open_ffi(encoded, encoded.length())
  if native_mapped_len_ffi(handle) < 0 {
    raise native_error(
      "mmap",
      path,
      native_mapped_error_ffi(handle),
      raw_code=native_mapped_os_error_ffi(handle),
    )
  }
  { path, handle, position: 0 }
}

///|
pub fn MappedBytes::len(self : MappedBytes) -> Int {
  let length = native_mapped_len_ffi(self.handle)
  if length < 0 {
    0
  } else {
    length
  }
}

///|
pub fn MappedBytes::remaining(self : MappedBytes) -> Int {
  self.len() - self.position
}

///|
pub fn MappedBytes::slice(
  self : MappedBytes,
  start : Int,
  length : Int,
) -> MappedBytes raise @io.IoError {
  if @io.Close::is_closed(self) {
    raise native_error("mmap slice", self.path, 8)
  }
  if start < 0 || length < 0 || start > self.len() - length {
    raise @io.io_error(@io.InvalidInput, "mmap slice", path=self.path)
  }
  let handle = native_mapped_slice_ffi(self.handle, start, length)
  if native_mapped_len_ffi(handle) < 0 {
    raise native_error("mmap slice", self.path, 7)
  }
  { path: self.path, handle, position: 0 }
}

///|
pub fn MappedBytes::read_byte_at(
  self : MappedBytes,
  index : Int,
) -> Byte raise @io.IoError {
  let value = native_mapped_read_byte_ffi(self.handle, index)
  if value < 0 {
    raise native_error("mmap read", self.path, -value)
  }
  value.to_byte()
}

///|
pub fn MappedBytes::copy_range(
  self : MappedBytes,
  start : Int,
  length : Int,
) -> Bytes raise @io.IoError {
  if @io.Close::is_closed(self) {
    raise native_error("mmap copy", self.path, 8)
  }
  if start < 0 || length < 0 || start > self.len() - length {
    raise @io.io_error(@io.InvalidInput, "mmap copy", path=self.path)
  }
  native_mapped_copy_ffi(self.handle, start, length)
}

///|
pub fn MappedBytes::find_byte(
  self : MappedBytes,
  byte : Byte,
) -> Int raise @io.IoError {
  if @io.Close::is_closed(self) {
    raise native_error("mmap find", self.path, 8)
  }
  native_mapped_find_ffi(self.handle, byte.to_int())
}

///|
pub impl @io.Read for MappedBytes with fn read(self, dst, offset, length) {
  if offset < 0 || length < 0 || offset > dst.length() - length {
    raise @io.io_error(@io.InvalidInput, "mmap read", path=self.path)
  }
  let count = Int::min(length, self.remaining())
  if count == 0 {
    return 0
  }
  let bytes = native_mapped_copy_ffi(self.handle, self.position, count)
  for i in 0..<count {
    dst[offset + i] = bytes[i]
  }
  self.position += count
  count
}

///|
pub impl @io.Seek for MappedBytes with fn seek(self, from) {
  let target = match from {
    @io.Start(offset) => offset
    @io.Current(offset) => self.position.to_int64() + offset
    @io.End(offset) => self.len().to_int64() + offset
  }
  if target < 0L || target > self.len().to_int64() {
    raise @io.io_error(
      @io.InvalidInput,
      "mmap seek",
      path=self.path,
      message="seek target is outside the mapped range",
    )
  }
  self.position = target.to_int()
  target
}

///|
pub impl @io.Seek for MappedBytes with fn stream_position(self) {
  self.position.to_int64()
}

///|
pub impl @io.Close for MappedBytes with fn close(self) {
  let status = native_mapped_close_ffi(self.handle)
  if status != 0 {
    raise native_error("mmap close", self.path, status)
  }
}

///|
pub impl @io.Close for MappedBytes with fn is_closed(self) {
  native_mapped_is_closed_ffi(self.handle) != 0
}
