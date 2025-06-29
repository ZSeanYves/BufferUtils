///|
pub trait BufReadable {
  read_byte(Self) -> Byte raise BufferError
  peek(Self) -> Byte raise BufferError
  is_empty(Self) -> Bool
  reader_rewind(Self) -> Unit
  reader_remaining(Self) -> Int
  skip(Self, Int) -> Unit
}

///|
pub trait BufWritable {
  write_byte(Self, Byte) -> Unit raise BufferError
  write_all(Self, Array[Byte]) -> Unit raise BufferError
  flush(Self) -> Array[Byte] raise BufferError
  clear(Self) -> Unit
  writer_rewind(Self) -> Unit
  writer_remaining(Self) -> Int
}
