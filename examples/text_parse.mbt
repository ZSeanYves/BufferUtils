///|
pub fn parse_lines_example(data : Bytes) -> Array[String] raise @io.IoError {
  let reader = @io.BufReader::new(@io.MemoryReader::new(data), capacity=128)
  reader.lines()
}
