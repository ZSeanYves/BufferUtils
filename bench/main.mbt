///|
let bench_output_root = ".tmp"

///|
let bench_output_dir = ".tmp/bufferutils-bench"

///|
let bench_runs = 50

///|
let bench_warmup_runs = 5

///|
let bench_sizes : Array[(String, Int)] = [
  ("1KB", 1024),
  ("64KB", 64 * 1024),
  ("1MB", 1024 * 1024),
  ("64MB", 64 * 1024 * 1024),
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
  allocations : Int
  underlying_calls : Int
  syscalls : Int
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
    allocations: 0,
    underlying_calls: 0,
    syscalls: 0,
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
    "\{name},\{size_label},\{bytes_len},\{temp_file},\{stats.median_us},\{stats.p95_us},\{stats.min_us},\{stats.max_us},\{stats.copied_bytes},\{stats.allocations},\{stats.underlying_calls},\{stats.syscalls},\{throughput(bytes_len, stats.median_us)}",
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
fn bench_small_write(chunk_size : Int) -> Int raise {
  let writer = @io.MemoryWriter::new(max_chunk=chunk_size)
  let chunk = pattern_bytes(chunk_size)
  for _ in 0..<1024 {
    @io.Write::write_all(writer, chunk[:])
  }
  @io.Write::flush(writer)
  chunk_size * 1024
}

///|
fn bench_short_write(bytes_len : Int, max_chunk : Int) -> Int raise {
  let writer = @io.MemoryWriter::new(max_chunk~)
  @io.Write::write_all(writer, pattern_bytes(bytes_len)[:])
  @io.Write::flush(writer)
  bytes_len
}

///|
fn bench_vectored_write() -> Int raise {
  let writer = @io.MemoryWriter::new()
  let sources = [
    @io.IoSlice::new(b"vec", 0, 3),
    @io.IoSlice::new(b"tored", 0, 5),
  ]
  ignore(@io.Write::write_vectored(writer, sources[:]))
  8
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
fn bench_native_read(path : String, bytes_len : Int) -> Int raise {
  let file = @native.NativeFile::open_read(path)
  let buffer = FixedArray::make(bytes_len, (0).to_byte())
  ignore(@io.Read::read_fixed(file, buffer, 0, bytes_len))
  @io.Close::close(file)
  bytes_len
}

///|
fn bench_native_mmap(path : String, bytes_len : Int) -> Int raise {
  let mapped = @native.MappedBytes::open(path)
  // Keep the full-file scan in the native implementation. Calling the
  // per-byte accessor billions of times would benchmark FFI overhead rather
  // than mmap throughput.
  let position = mapped.find_byte(b'\xff')
  @io.Close::close(mapped)
  ignore(position)
  ignore(bytes_len)
  0
}

///|
fn run_benchmarks() -> Unit raise {
  println(
    "name,size,bytes,temp_file,median_us,p95_us,min_us,max_us,copied_bytes,allocations,underlying_calls,syscalls,median_mib_per_s",
  )
  let small_1 = measure(() => bench_small_write(1))
  print_result("sync_small_write_1B", "1B", 1024, false, small_1)
  let small_32 = measure(() => bench_small_write(32))
  print_result("sync_small_write_32B", "32B", 32 * 1024, false, small_32)
  let small_256 = measure(() => bench_small_write(256))
  print_result("sync_small_write_256B", "256B", 256 * 1024, false, small_256)
  let short_1 = measure(() => bench_short_write(64 * 1024, 1))
  print_result("sync_short_write_1B", "64KB", 64 * 1024, false, short_1)
  let short_16 = measure(() => bench_short_write(64 * 1024, 16))
  print_result("sync_short_write_16B", "64KB", 64 * 1024, false, short_16)
  let vectored = measure(() => bench_vectored_write())
  print_result("sync_vectored_write", "8B", 8, false, vectored)
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
    let native_read = measure(() => bench_native_read(path, bytes_len))
    print_result("native_file_read", size_label, bytes_len, true, native_read)
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
