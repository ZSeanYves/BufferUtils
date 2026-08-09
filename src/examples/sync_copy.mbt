///|
pub fn sync_copy_example(
  source_path : String,
  destination_path : String,
) -> Unit raise @io.IoError {
  let source = @native.NativeFile::open_read(source_path)
  let destination = @native.NativeFile::open(
    destination_path,
    @native.NativeOpenOptions::write_truncate(),
  )
  let buffered_source = @io.BufReader::new(source, capacity=8192)
  let buffered_destination = @io.BufWriter::new(destination, capacity=8192)
  let chunk = FixedArray::make(64 * 1024, (0).to_byte())
  while true {
    let count = @io.Read::read(buffered_source, chunk, 0, chunk.length())
    if count == 0 {
      break
    }
    let bytes = chunk.unsafe_reinterpret_as_bytes()
    @io.write_all_bytes(buffered_destination, bytes, offset=0, len=count)
  }
  @io.Write::flush(buffered_destination)
  buffered_destination.get_ref().sync_all()
  @io.Close::close(buffered_source.get_ref())
  @io.Close::close(buffered_destination.get_ref())
}
