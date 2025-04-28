pub trait BufReadable {
  read_byte(Self) -> Byte!BufferError
  peek(Self) -> Byte!BufferError
  is_empty(Self) -> Bool
  reader_rewind(Self) -> Unit
  reader_remaining(Self) -> Int
  skip(Self, Int) -> Unit
}
pub trait BufWritable {
  write_byte(Self, Byte) -> Unit!BufferError
  write_all(Self, Array[Byte]) -> Unit!BufferError
  flush(Self) -> Array[Byte]!BufferError
  clear(Self) -> Unit
  writer_rewind(Self) -> Unit
  writer_remaining(Self) -> Int
}


 