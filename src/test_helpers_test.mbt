///|
let test_output_root = ".tmp"

///|
let test_output_dir = ".tmp/bufferutils-test-output"

///|
fn ensure_test_output_dir() -> Unit raise @fs.IOError {
  if !@fs.path_exists(test_output_root) {
    @fs.create_dir(test_output_root)
  }
  if !@fs.path_exists(test_output_dir) {
    @fs.create_dir(test_output_dir)
  }
}

///|
fn test_output_path(name : String) -> String raise @fs.IOError {
  ensure_test_output_dir()
  test_output_dir + "/" + name
}

///|
fn pattern_bytes(len : Int) -> Array[Byte] {
  let data : Array[Byte] = []
  for i in 0..<len {
    data.push((i % 256).to_byte())
  }
  data
}

///|
fn write_test_bytes(
  path : String,
  data : Array[Byte],
) -> Unit raise @fs.IOError {
  @fs.write_bytes_to_file(path, array_to_bytes(data))
}

///|
fn read_test_bytes(path : String) -> Array[Byte] raise @fs.IOError {
  bytes_to_array(@fs.read_file_to_bytes(path))
}
