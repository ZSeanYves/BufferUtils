///|
let bench_output_root = ".tmp"

///|
let bench_output_dir = ".tmp/bufferutils-bench"

///|
let warmup_samples = 10

///|
let measured_samples = 30

///|
let benchmark_batches = 3

///|
let minimum_sample_us = 10000.0

///|
let maximum_iterations = 4194304

///|
let benchmark_keeper : @mbench.Bench = @mbench.Bench()

///|
let bench_sizes : Array[Int] = [1024, 1024 * 1024]

///|
struct BenchCounters {
  copied_bytes : Int64
  underlying_calls : Int64
  syscalls : Int64
}

///|
struct PreparedRun {
  run : () -> Unit raise
  observe : () -> BenchCounters
  cleanup : () -> Unit raise
}

///|
struct BenchmarkCase {
  name : String
  size : Int
  bytes_per_iteration : Int64
  prepare : (Int) -> PreparedRun raise
}

///|
struct BenchStats {
  iterations : Int
  median_us : Double
  p95_us : Double
  counters : BenchCounters
}

///|
struct CyclingReader {
  data : Array[Byte]
  mut position : Int
  mut calls : Int
}

///|
fn CyclingReader::new(data : Array[Byte]) -> CyclingReader {
  { data, position: 0, calls: 0 }
}

///|
fn CyclingReader::calls(self : CyclingReader) -> Int {
  self.calls
}

///|
impl @io.Read for CyclingReader with fn read(self, dst, offset, length) {
  if length == 0 {
    return 0
  }
  if self.position == self.data.length() {
    self.position = 0
  }
  let count = Int::min(length, self.data.length() - self.position)
  for i in 0..<count {
    dst[offset + i] = self.data[self.position + i]
  }
  self.position += count
  self.calls += 1
  count
}

///|
struct CountingWriter {
  max_chunk : Int
  scratch : FixedArray[Byte]
  mut calls : Int
  mut bytes : Int64
  mut checksum : Int
}

///|
fn CountingWriter::new(
  max_chunk? : Int = 2147483647,
  scratch_capacity? : Int = 8192,
) -> CountingWriter {
  {
    max_chunk,
    scratch: FixedArray::make(scratch_capacity, (0).to_byte()),
    calls: 0,
    bytes: 0L,
    checksum: 0,
  }
}

///|
impl @io.Write for CountingWriter with fn write(self, src, offset, length) {
  let count = Int::min(length, Int::min(self.max_chunk, self.scratch.length()))
  for i in 0..<count {
    self.scratch[i] = src[offset + i]
  }
  let mut checksum = self.checksum
  if count > 0 {
    checksum = (
        checksum +
        self.scratch[0].to_int() +
        self.scratch[count - 1].to_int() +
        count
      ) %
      65521
  }
  self.checksum = checksum
  self.calls += 1
  self.bytes += count.to_int64()
  count
}

///|
impl @io.Write for CountingWriter with fn flush(_self) {
  ()
}

///|
fn CountingWriter::calls(self : CountingWriter) -> Int {
  self.calls
}

///|
fn CountingWriter::observed_bytes(self : CountingWriter) -> Int64 {
  benchmark_keeper.keep(self.checksum)
  self.bytes
}

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
fn empty_counters() -> BenchCounters {
  { copied_bytes: 0L, underlying_calls: 0L, syscalls: 0L }
}

///|
fn p95(samples : Array[Double]) -> Double {
  let index = (samples.length() * 95 + 99) / 100 - 1
  samples[Int::max(0, Int::min(index, samples.length() - 1))]
}

///|
fn median(samples : Array[Double]) -> Double {
  let middle = samples.length() / 2
  if samples.length() % 2 == 0 {
    (samples[middle - 1] + samples[middle]) / 2.0
  } else {
    samples[middle]
  }
}

///|
fn run_prepared(prepared : PreparedRun) -> Double raise {
  let started = @mbench.monotonic_clock_start()
  (prepared.run)()
  @mbench.monotonic_clock_end(started)
}

///|
fn calibrate(case : BenchmarkCase) -> Int raise {
  let mut iterations = 1
  let mut elapsed = 0.0
  while elapsed < minimum_sample_us && iterations < maximum_iterations {
    let prepared = (case.prepare)(iterations)
    elapsed = run_prepared(prepared)
    ignore((prepared.observe)())
    (prepared.cleanup)()
    if elapsed < minimum_sample_us {
      iterations = Int::min(maximum_iterations, iterations * 2)
    }
  }
  iterations
}

///|
fn measure_at(case : BenchmarkCase, iterations : Int) -> BenchStats raise {
  for _ in 0..<warmup_samples {
    let prepared = (case.prepare)(iterations)
    ignore(run_prepared(prepared))
    ignore((prepared.observe)())
    (prepared.cleanup)()
  }
  let samples : Array[Double] = []
  let mut counters = empty_counters()
  for _ in 0..<measured_samples {
    let prepared = (case.prepare)(iterations)
    samples.push(run_prepared(prepared))
    counters = (prepared.observe)()
    (prepared.cleanup)()
  }
  samples.sort()
  { iterations, median_us: median(samples), p95_us: p95(samples), counters }
}

///|
fn measure_until_stable(
  case : BenchmarkCase,
  iterations : Int,
) -> BenchStats raise {
  let stats = measure_at(case, iterations)
  if stats.median_us >= minimum_sample_us || iterations >= maximum_iterations {
    stats
  } else {
    measure_until_stable(case, Int::min(maximum_iterations, iterations * 2))
  }
}

///|
fn measure(case : BenchmarkCase) -> BenchStats raise {
  measure_until_stable(case, calibrate(case))
}

///|
fn throughput(bytes : Int64, micros : Double) -> Double {
  if micros <= 0.0 {
    0.0
  } else {
    bytes.to_double() / 1048576.0 / (micros / 1000000.0)
  }
}

///|
fn print_result(case : BenchmarkCase, batch : Int, stats : BenchStats) -> Unit {
  let bytes = case.bytes_per_iteration * stats.iterations.to_int64()
  println(
    "moonbit,\{case.name},\{case.size},\{batch},\{stats.iterations},\{stats.median_us},\{stats.p95_us},\{bytes},\{stats.counters.copied_bytes},\{stats.counters.underlying_calls},\{stats.counters.syscalls},\{throughput(bytes, stats.median_us)}",
  )
}

///|
fn shared_clone_case(size : Int) -> BenchmarkCase {
  let source = @buffer.SharedBytes::from_array(pattern_bytes(size)[:])
  {
    name: "buffer_shared_clone",
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let sink = Ref(0)
      {
        run: () => {
          let mut checksum = 0
          for _ in 0..<iterations {
            checksum += source.clone().remaining()
          }
          sink.val = checksum
        },
        observe: () => {
          ignore(sink.val)
          { ..empty_counters(), copied_bytes: source.copied_bytes().to_int64() }
        },
        cleanup: () => (),
      }
    },
  }
}

///|
fn shared_slice_case(size : Int) -> BenchmarkCase {
  let source = @buffer.SharedBytes::from_array(pattern_bytes(size)[:])
  {
    name: "buffer_shared_slice",
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let sink = Ref(0)
      {
        run: () => {
          let mut checksum = 0
          for _ in 0..<iterations {
            checksum += source.slice(0, source.remaining()).remaining()
          }
          sink.val = checksum
        },
        observe: () => {
          ignore(sink.val)
          { ..empty_counters(), copied_bytes: source.copied_bytes().to_int64() }
        },
        cleanup: () => (),
      }
    },
  }
}

///|
fn shared_split_case(size : Int) -> BenchmarkCase {
  let source = @buffer.SharedBytes::from_array(pattern_bytes(size)[:])
  {
    name: "buffer_shared_split",
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let sink = Ref(0)
      {
        run: () => {
          let mut checksum = 0
          for _ in 0..<iterations {
            let cursor = source.clone()
            checksum += cursor.split_to(size / 2).remaining()
          }
          sink.val = checksum
        },
        observe: () => {
          ignore(sink.val)
          { ..empty_counters(), copied_bytes: source.copied_bytes().to_int64() }
        },
        cleanup: () => (),
      }
    },
  }
}

///|
fn freeze_case(size : Int) -> BenchmarkCase {
  let payload = pattern_bytes(size)
  {
    name: "buffer_freeze",
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let buffer = @buffer.BytesMut::from_array(payload[:])
      let sink = Ref(0)
      {
        run: () => {
          let mut checksum = 0
          for _ in 0..<iterations {
            checksum += buffer.freeze().remaining()
          }
          sink.val = checksum
        },
        observe: () => {
          ignore(sink.val)
          { ..empty_counters(), copied_bytes: buffer.copied_bytes().to_int64() }
        },
        cleanup: () => (),
      }
    },
  }
}

///|
fn cow_case(size : Int) -> BenchmarkCase {
  let payload = pattern_bytes(size)
  {
    name: "buffer_cow_mutation",
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let buffers = Array::makei(iterations, _ => {
        let buffer = @buffer.BytesMut::from_array(payload[:])
        ignore(buffer.freeze())
        buffer
      })
      {
        run: () => {
          for buffer in buffers {
            buffer.put_byte(b'X')
          }
        },
        observe: () => {
          let mut copied = 0L
          for buffer in buffers {
            copied += buffer.copied_bytes().to_int64()
          }
          { ..empty_counters(), copied_bytes: copied }
        },
        cleanup: () => (),
      }
    },
  }
}

///|
fn growth_case(size : Int) -> BenchmarkCase {
  let initial = pattern_bytes(size / 2)
  let suffix = pattern_bytes(size - size / 2)
  {
    name: "buffer_growth",
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let buffers = Array::makei(iterations, _ => {
        @buffer.BytesMut::from_array(initial[:])
      })
      {
        run: () => {
          for buffer in buffers {
            buffer.put_slice(suffix[:])
          }
        },
        observe: () => {
          let mut copied = 0L
          for buffer in buffers {
            copied += buffer.copied_bytes().to_int64()
          }
          { ..empty_counters(), copied_bytes: copied }
        },
        cleanup: () => (),
      }
    },
  }
}

///|
fn raw_read_case(size : Int) -> BenchmarkCase {
  let payload = pattern_bytes(size)
  {
    name: "sync_raw_read",
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let reader = CyclingReader::new(payload)
      let output = FixedArray::make(size, (0).to_byte())
      {
        run: () => {
          for _ in 0..<iterations {
            @io.read_exact_fixed(reader, output, 0, size)
          }
        },
        observe: () => {
          copied_bytes: size.to_int64() * iterations.to_int64(),
          underlying_calls: reader.calls().to_int64(),
          syscalls: 0,
        },
        cleanup: () => (),
      }
    },
  }
}

///|
fn buffered_read_case(
  size : Int,
  request_size : Int,
  name : String,
) -> BenchmarkCase {
  let payload = pattern_bytes(size)
  {
    name,
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let reader = @io.BufReader::new(
        CyclingReader::new(payload),
        capacity=8192,
      )
      let output = FixedArray::make(size, (0).to_byte())
      {
        run: () => {
          for _ in 0..<iterations {
            let mut offset = 0
            while offset < size {
              let count = @io.Read::read(
                reader,
                output,
                offset,
                Int::min(request_size, size - offset),
              )
              if count == 0 {
                fail("buffered benchmark reached unexpected EOF")
              }
              offset += count
            }
          }
        },
        observe: () => {
          let copies = if request_size >= 8192 { 1L } else { 2L }
          {
            copied_bytes: size.to_int64() * iterations.to_int64() * copies,
            underlying_calls: reader.underlying_read_calls().to_int64(),
            syscalls: 0,
          }
        },
        cleanup: () => (),
      }
    },
  }
}

///|
fn raw_write_case(size : Int, chunk_size : Int, name : String) -> BenchmarkCase {
  let payload = pattern_bytes(size)
  let payload_bytes = Bytes::from_array(payload)
  {
    name,
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let writer = CountingWriter::new(scratch_capacity=chunk_size)
      {
        run: () => {
          for _ in 0..<iterations {
            let mut offset = 0
            while offset < size {
              let count = Int::min(chunk_size, size - offset)
              @io.write_all_bytes(writer, payload_bytes, offset~, len=count)
              offset += count
            }
          }
        },
        observe: () => {
          ignore(writer.observed_bytes())
          {
            copied_bytes: size.to_int64() * iterations.to_int64(),
            underlying_calls: writer.calls().to_int64(),
            syscalls: 0,
          }
        },
        cleanup: () => (),
      }
    },
  }
}

///|
fn buffered_write_case(
  size : Int,
  chunk_size : Int,
  name : String,
) -> BenchmarkCase {
  let payload = pattern_bytes(size)
  let payload_bytes = Bytes::from_array(payload)
  {
    name,
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let scratch_capacity = if chunk_size >= 8192 { chunk_size } else { 8192 }
      let writer = @io.BufWriter::new(
        CountingWriter::new(scratch_capacity~),
        capacity=8192,
      )
      {
        run: () => {
          for _ in 0..<iterations {
            let mut offset = 0
            while offset < size {
              let count = Int::min(chunk_size, size - offset)
              @io.write_all_bytes(writer, payload_bytes, offset~, len=count)
              offset += count
            }
            @io.Write::flush(writer)
          }
        },
        observe: () => {
          let copies = if chunk_size >= 8192 { 1L } else { 2L }
          {
            copied_bytes: size.to_int64() * iterations.to_int64() * copies,
            underlying_calls: writer.underlying_write_calls().to_int64(),
            syscalls: 0,
          }
        },
        cleanup: () => (),
      }
    },
  }
}

///|
fn short_write_case(size : Int, max_chunk : Int) -> BenchmarkCase {
  let payload = pattern_bytes(size)
  let payload_bytes = Bytes::from_array(payload)
  {
    name: "sync_short_write_\{max_chunk}",
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let writer = CountingWriter::new(max_chunk~, scratch_capacity=max_chunk)
      {
        run: () => {
          for _ in 0..<iterations {
            @io.write_all_bytes(writer, payload_bytes)
          }
        },
        observe: () => {
          ignore(writer.observed_bytes())
          {
            copied_bytes: size.to_int64() * iterations.to_int64(),
            underlying_calls: writer.calls().to_int64(),
            syscalls: 0,
          }
        },
        cleanup: () => (),
      }
    },
  }
}

///|
fn vectored_write_case() -> BenchmarkCase {
  let first = [b'v', b'e', b'c']
  let second = [b't', b'o', b'r', b'e', b'd']
  let sources : Array[ArrayView[Byte]] = [first[:], second[:]]
  {
    name: "sync_vectored_fallback",
    size: 8,
    bytes_per_iteration: 8L,
    prepare: iterations => {
      let writer = CountingWriter::new(scratch_capacity=8)
      {
        run: () => {
          for _ in 0..<iterations {
            @io.write_all_vectored(writer, sources[:])
          }
        },
        observe: () => {
          ignore(writer.observed_bytes())
          {
            copied_bytes: 16L * iterations.to_int64(),
            underlying_calls: writer.calls().to_int64(),
            syscalls: 0,
          }
        },
        cleanup: () => (),
      }
    },
  }
}

///|
let path_sequence : Ref[Int] = Ref(0)

///|
fn unique_bench_path(label : String) -> String raise @fs.IOError {
  ensure_bench_output_dir()
  path_sequence.val += 1
  bench_output_dir + "/\{label}-\{path_sequence.val}.bin"
}

///|
fn native_write_case(size : Int) -> BenchmarkCase {
  let payload = pattern_bytes(size)
  {
    name: "native_file_write",
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let path = unique_bench_path("write-\{size}")
      let file = @native.NativeFile::create(path)
      {
        run: () => {
          for _ in 0..<iterations {
            @io.Write::write_all(file, payload[:])
          }
          @io.Write::flush(file)
        },
        observe: () => {
          let syscalls = file.write_syscalls().to_int64()
          {
            copied_bytes: size.to_int64() * iterations.to_int64(),
            underlying_calls: syscalls,
            syscalls,
          }
        },
        cleanup: () => {
          @io.Close::close(file)
          @fs.remove_file(path)
        },
      }
    },
  }
}

///|
fn native_read_case(size : Int) -> BenchmarkCase {
  let payload = pattern_bytes(size)
  {
    name: "native_file_read",
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let path = unique_bench_path("read-\{size}")
      let writer = @native.NativeFile::create(path)
      for _ in 0..<iterations {
        @io.Write::write_all(writer, payload[:])
      }
      @io.Close::close(writer)
      let file = @native.NativeFile::open_read(path)
      let output = Array::make(size, (0).to_byte())
      {
        run: () => {
          for _ in 0..<iterations {
            @io.Read::read_exact(file, output.mut_view())
          }
        },
        observe: () => {
          let syscalls = file.read_syscalls().to_int64()
          {
            copied_bytes: size.to_int64() * iterations.to_int64(),
            underlying_calls: syscalls,
            syscalls,
          }
        },
        cleanup: () => {
          @io.Close::close(file)
          @fs.remove_file(path)
        },
      }
    },
  }
}

///|
fn mmap_case(size : Int) -> BenchmarkCase {
  let payload = pattern_bytes(size)
  {
    name: "native_mmap_scan",
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let path = unique_bench_path("mmap-\{size}")
      let writer = @native.NativeFile::create(path)
      @io.Write::write_all(writer, payload[:])
      @io.Close::close(writer)
      let mapping = @native.MappedBytes::open(path)
      let sink = Ref(0)
      {
        run: () => {
          let mut checksum = 0
          for _ in 0..<iterations {
            checksum += mapping.find_byte(b'\xff')
          }
          sink.val = checksum
        },
        observe: () => {
          ignore(sink.val)
          empty_counters()
        },
        cleanup: () => {
          @io.Close::close(mapping)
          @fs.remove_file(path)
        },
      }
    },
  }
}

///|
fn benchmark_cases() -> Array[BenchmarkCase] {
  let cases : Array[BenchmarkCase] = [vectored_write_case()]
  for size in bench_sizes {
    cases.push(shared_clone_case(size))
    cases.push(shared_slice_case(size))
    cases.push(shared_split_case(size))
    cases.push(freeze_case(size))
    if size == 1024 * 1024 {
      cases.push(cow_case(size))
      cases.push(growth_case(size))
    }
    cases.push(raw_read_case(size))
    cases.push(buffered_read_case(size, 32, "sync_bufreader_small"))
    cases.push(raw_write_case(size, 32, "sync_raw_small_write"))
    cases.push(buffered_write_case(size, 32, "sync_bufwriter_small"))
    if size >= 8192 {
      cases.push(buffered_read_case(size, size, "sync_bufreader_bypass"))
      cases.push(buffered_write_case(size, size, "sync_bufwriter_bypass"))
    }
    if size == 1024 {
      cases.push(short_write_case(size, 16))
    }
    cases.push(native_write_case(size))
    cases.push(native_read_case(size))
    cases.push(mmap_case(size))
  }
  cases
}

///|
fn run_benchmarks() -> Unit raise {
  println(
    "implementation,name,size,batch,iterations,median_us,p95_us,bytes,copied_bytes,underlying_calls,syscalls,median_mib_per_s",
  )
  let cases = benchmark_cases()
  for batch in 1..<=benchmark_batches {
    for case in cases {
      print_result(case, batch, measure(case))
    }
  }
}

///|
fn main {
  run_benchmarks() catch {
    error => {
      println("benchmark failed")
      println(error)
      abort("benchmark execution failed")
    }
  }
}
