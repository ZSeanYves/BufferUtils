///|
let bench_output_root = ".tmp"

///|
let bench_output_dir = ".tmp/bufferutils-bench"

///|
let bench_runs = 30

///|
let bench_warmup_runs = 5

///|
let bench_sizes : Array[(String, Int)] = [
  ("1KB", 1024),
  ("64KB", 64 * 1024),
  ("1MB", 1024 * 1024),
]

///|
fn ensure_bench_output_dir() -> Unit raise @fs.IOError {
  if !@fs.path_exists(bench_output_root) {
    @fs.create_dir(bench_output_root)
  }
  if !@fs.path_exists(bench_output_dir) {
    @fs.create_dir(bench_output_dir)
  }
}

///|
fn pattern_bytes(len : Int) -> Array[Byte] {
  Array::makei(len, i => (i % 251).to_byte())
}

///|
fn p95(samples : Array[Double]) -> Double {
  let index = (samples.length() * 95 + 99) / 100 - 1
  samples[Int::max(0, Int::min(index, samples.length() - 1))]
}

///|
struct BenchStats {
  median_us : Double
  p95_us : Double
  min_us : Double
  max_us : Double
  copied_bytes : Int
}

///|
fn measure(f : () -> Int raise) -> BenchStats raise {
  for _ in 0..<bench_warmup_runs {
    ignore(f())
  }
  let samples : Array[Double] = []
  let mut copied = 0
  for _ in 0..<bench_runs {
    let started = @mbench.monotonic_clock_start()
    copied = f()
    samples.push(@mbench.monotonic_clock_end(started))
  }
  samples.sort()
  let middle = bench_runs / 2
  {
    median_us: (samples[middle - 1] + samples[middle]) / 2.0,
    p95_us: p95(samples),
    min_us: samples[0],
    max_us: samples[bench_runs - 1],
    copied_bytes: copied,
  }
}

///|
fn throughput(bytes_len : Int, micros : Double) -> Double {
  if micros <= 0.0 {
    0.0
  } else {
    bytes_len.to_double() / 1048576.0 / (micros / 1000000.0)
  }
}

///|
fn print_result(
  name : String,
  size_label : String,
  bytes_len : Int,
  temp_file : Bool,
  stats : BenchStats,
) -> Unit {
  println(
    "\{name},\{size_label},\{bytes_len},\{temp_file},\{stats.median_us},\{stats.p95_us},\{stats.min_us},\{stats.max_us},\{stats.copied_bytes},\{throughput(bytes_len, stats.median_us)}",
  )
}

///|
fn bench_shared_split(bytes_len : Int) -> Int raise @buffer.BufferError {
  let mutable = @buffer.BytesMut::from_array(pattern_bytes(bytes_len)[:])
  let frozen = mutable.freeze()
  let part = frozen.slice(0, bytes_len / 2)
  ignore(part)
  frozen.copied_bytes()
}

///|
fn bench_cow_mutation(bytes_len : Int) -> Int raise @buffer.BufferError {
  let mutable = @buffer.BytesMut::from_array(pattern_bytes(bytes_len)[:])
  ignore(mutable.freeze())
  mutable.put_byte(b'X')
  mutable.copied_bytes()
}

///|
fn bench_sync_buffered_read(bytes_len : Int) -> Int raise {
  let reader = @io.MemoryReader::new(
    Bytes::from_array(pattern_bytes(bytes_len)[:]),
  )
  let buffered = @io.BufReader::new(reader, capacity=8192)
  let output : Array[Byte] = []
  ignore(@io.read_to_end(buffered, output))
  0
}

///|
fn bench_sync_raw_read(bytes_len : Int) -> Int raise {
  let reader = @io.MemoryReader::new(
    Bytes::from_array(pattern_bytes(bytes_len)[:]),
  )
  let output : Array[Byte] = []
  ignore(@io.read_to_end(reader, output))
  0
}

///|
fn bench_sync_buffered_write(bytes_len : Int) -> Int raise {
  let writer = @io.MemoryWriter::new()
  let buffered = @io.BufWriter::new(writer, capacity=8192)
  @io.Write::write_all(buffered, pattern_bytes(bytes_len)[:])
  @io.Write::flush(buffered)
  0
}

///|
fn bench_sync_raw_write(bytes_len : Int) -> Int raise {
  let writer = @io.MemoryWriter::new()
  @io.Write::write_all(writer, pattern_bytes(bytes_len)[:])
  @io.Write::flush(writer)
  0
}

///|
fn bench_path(label : String) -> String raise @fs.IOError {
  ensure_bench_output_dir()
  bench_output_dir + "/\{label}.bin"
}

///|
fn bench_native_file(path : String, bytes_len : Int) -> Int raise {
  let file = @native.NativeFile::create(path)
  @io.Write::write_all(file, pattern_bytes(bytes_len)[:])
  @io.Write::flush(file)
  @io.Close::close(file)
  0
}

///|
fn bench_native_mmap(path : String, bytes_len : Int) -> Int raise {
  let mapped = @native.MappedBytes::open(path)
  let mut checksum = 0
  for i in 0..<bytes_len {
    checksum += mapped.read_byte_at(i).to_int()
  }
  @io.Close::close(mapped)
  ignore(checksum)
  0
}

///|
fn run_benchmarks() -> Unit raise {
  println(
    "name,size,bytes,temp_file,median_us,p95_us,min_us,max_us,copied_bytes,median_mib_per_s",
  )
  for size_entry in bench_sizes {
    let (size_label, bytes_len) = size_entry
    let shared = measure(() => bench_shared_split(bytes_len))
    print_result(
      "buffer_shared_split_freeze", size_label, bytes_len, false, shared,
    )
    let cow = measure(() => bench_cow_mutation(bytes_len))
    print_result("buffer_cow_mutation", size_label, bytes_len, false, cow)
    let raw_read = measure(() => bench_sync_raw_read(bytes_len))
    print_result("sync_raw_read_to_end", size_label, bytes_len, false, raw_read)
    let read = measure(() => bench_sync_buffered_read(bytes_len))
    print_result(
      "sync_bufreader_read_to_end", size_label, bytes_len, false, read,
    )
    let raw_write = measure(() => bench_sync_raw_write(bytes_len))
    print_result("sync_raw_write_all", size_label, bytes_len, false, raw_write)
    let write = measure(() => bench_sync_buffered_write(bytes_len))
    print_result(
      "sync_bufwriter_write_flush", size_label, bytes_len, false, write,
    )
    let path = bench_path("native-\{size_label}")
    let file = measure(() => bench_native_file(path, bytes_len))
    print_result("native_file_write_flush", size_label, bytes_len, true, file)
    let mmap = measure(() => bench_native_mmap(path, bytes_len))
    print_result("native_mmap_read_scan", size_label, bytes_len, true, mmap)
  }
}

///|
fn main {
  run_benchmarks() catch {
    error => {
      println("benchmark failed")
      println(error)
    }
  }
}
