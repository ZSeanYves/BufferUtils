///|
pub fn parse_lines_example(data : Bytes) -> Array[String] raise @io.IoError {
  let reader = @io.BufReader::new(@io.MemoryReader::new(data), capacity=128)
  let lines = reader.lines()
  let result : Array[String] = []
  while true {
    match lines.next() {
      Some(line) => result.push(line)
      None => break
    }
  }
  result
}
