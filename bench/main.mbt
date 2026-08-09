///|
let bench_output_root = ".tmp"

///|
let bench_output_dir = ".tmp/bufferutils-bench"

///|
let warmup_samples = 10

///|
let measured_samples = 30

///|
let minimum_sample_us = 10000.0

///|
let maximum_iterations = 16777216

///|
let shared_iterations_path = ".tmp/bufferutils-bench/shared-iterations.csv"

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
  samples : Array[Double]
}

///|
struct CyclingReader {
  data : FixedArray[Byte]
  mut position : Int
  mut calls : Int
  mut bytes : Int64
}

///|
fn CyclingReader::new(data : FixedArray[Byte]) -> CyclingReader {
  { data, position: 0, calls: 0, bytes: 0L }
}

///|
fn CyclingReader::calls(self : CyclingReader) -> Int {
  self.calls
}

///|
fn CyclingReader::observed_bytes(self : CyclingReader) -> Int64 {
  self.bytes
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
  FixedArray::unsafe_blit(dst, offset, self.data, self.position, count)
  self.position += count
  self.calls += 1
  self.bytes += count.to_int64()
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
  self.scratch.blit_from_bytes(0, src, offset, count)
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
impl @io.Write for CountingWriter with fn write_vectored(self, sources) {
  let limit = Int::min(self.max_chunk, self.scratch.length())
  let mut accepted = 0
  for source in sources {
    let count = Int::min(source.len(), limit - accepted)
    if count > 0 {
      self.scratch.blit_from_bytes(
        accepted,
        source.data(),
        source.offset(),
        count,
      )
      accepted += count
    }
    if accepted == limit {
      break
    }
  }
  if accepted > 0 {
    self.checksum = (
        self.checksum +
        self.scratch[0].to_int() +
        self.scratch[accepted - 1].to_int() +
        accepted
      ) %
      65521
  }
  self.calls += 1
  self.bytes += accepted.to_int64()
  accepted
}

///|
impl @io.Write for CountingWriter with fn is_write_vectored(_self) {
  true
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
fn workload_multiplier(case : BenchmarkCase) -> Int {
  if case.name == "sync_vectored_bulk" {
    16
  } else if case.name == "sync_vectored_fallback" {
    2
  } else if case.name == "sync_bufreader_bypass" {
    2
  } else if case.name == "buffer_shared_clone" ||
    case.name == "buffer_shared_slice" ||
    case.name == "buffer_shared_split" {
    4
  } else if case.size == 1024 &&
    (
      case.name == "sync_bufreader_small" ||
      case.name == "sync_raw_small_write" ||
      case.name == "sync_bufwriter_small" ||
      case.name == "sync_short_write_16"
    ) {
    4
  } else {
    1
  }
}

///|
fn run_prepared(prepared : PreparedRun) -> Double raise {
  let started = @mbench.monotonic_clock_start()
  (prepared.run)()
  @mbench.monotonic_clock_end(started)
}

///|
fn calibrate(case : BenchmarkCase, initial_iterations : Int) -> Int raise {
  let mut iterations = initial_iterations
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
  {
    iterations,
    median_us: median(samples),
    p95_us: p95(samples),
    counters,
    samples,
  }
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
fn parse_positive_int(value : StringView) -> Int? {
  let parsed : Int = @string.from_str(value) catch { _ => return None }
  if parsed > 0 {
    Some(parsed)
  } else {
    None
  }
}

///|
fn forced_iterations(name : String, size : Int) -> Int? raise @fs.IOError {
  if !@fs.path_exists(shared_iterations_path) {
    return None
  }
  let contents = @fs.read_file_to_string(shared_iterations_path)
  for line in contents.split("\n") {
    let fields = line.split(",")
    let row_name = fields.next()
    let row_size = fields.next()
    let row_iterations = fields.next()
    if fields.next() is None &&
      row_name == Some(name) &&
      row_size.bind(parse_positive_int) == Some(size) {
      return row_iterations.bind(parse_positive_int)
    }
  }
  abort("shared iteration map is missing {name}/{size}")
}

///|
fn measure(case : BenchmarkCase, initial_iterations : Int) -> BenchStats raise {
  match forced_iterations(case.name, case.size) {
    Some(iterations) if iterations <= maximum_iterations =>
      return measure_at(case, iterations)
    Some(_) => abort("shared iteration count exceeds the benchmark limit")
    None => ()
  }
  let calibrated = calibrate(case, initial_iterations)
  let expanded = Int::min(
    maximum_iterations,
    calibrated * workload_multiplier(case),
  )
  measure_until_stable(case, expanded)
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
fn copy_scope(name : String) -> String {
  if name.has_prefix("buffer_") {
    "library-cow"
  } else if name.has_prefix("native_") || name == "tcp_loopback" {
    "unavailable"
  } else {
    "fixture-observed"
  }
}

///|
fn append_auxiliary_rows(
  raw : StringBuilder,
  evidence : StringBuilder,
  case : BenchmarkCase,
  batch : Int,
  stats : BenchStats,
) -> Unit {
  for index, elapsed in stats.samples {
    raw.write_string(
      "moonbit,\{case.name},\{case.size},\{batch},\{index + 1},\{stats.iterations},\{elapsed}\n",
    )
  }
  evidence.write_string(
    "moonbit,\{case.name},\{case.size},\{batch},\{stats.iterations},\{stats.counters.copied_bytes},\{stats.counters.underlying_calls},\{stats.counters.syscalls},\{copy_scope(case.name)}\n",
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
      let sink = Ref(source.clone())
      {
        run: () => {
          for _ in 0..<iterations {
            sink.val = source.clone()
          }
        },
        observe: () => {
          benchmark_keeper.keep(sink.val.remaining())
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
      let sink = Ref(source.clone())
      {
        run: () => {
          for _ in 0..<iterations {
            sink.val = source.slice(0, source.remaining())
          }
        },
        observe: () => {
          benchmark_keeper.keep(sink.val.remaining())
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
      let sink = Ref(source.clone())
      {
        run: () => {
          for _ in 0..<iterations {
            let cursor = source.clone()
            sink.val = cursor.split_to(size / 2)
          }
        },
        observe: () => {
          benchmark_keeper.keep(sink.val.remaining())
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
          { ..empty_counters(), copied_bytes: 0L }
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
  let payload_fixed = FixedArray::from_array(payload[:])
  {
    name: "sync_raw_read",
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let reader = CyclingReader::new(payload_fixed)
      let output = FixedArray::make(size, (0).to_byte())
      {
        run: () => {
          for _ in 0..<iterations {
            @io.read_exact_fixed(reader, output, 0, size)
          }
        },
        observe: () => {
          copied_bytes: reader.observed_bytes(),
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
  let payload_fixed = FixedArray::from_array(payload[:])
  {
    name,
    size,
    bytes_per_iteration: size.to_int64(),
    prepare: iterations => {
      let reader = @io.BufReader::new(
        CyclingReader::new(payload_fixed),
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
          copied_bytes: reader.get_ref().observed_bytes(),
          underlying_calls: reader.underlying_read_calls().to_int64(),
          syscalls: 0,
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
              let accepted = @io.Write::write(
                writer, payload_bytes, offset, count,
              )
              if accepted != count {
                fail("raw small-write benchmark lost progress")
              }
              offset += count
            }
          }
        },
        observe: () => {
          let copied = writer.observed_bytes()
          {
            copied_bytes: copied,
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
              let accepted = @io.Write::write(
                writer, payload_bytes, offset, count,
              )
              if accepted != count {
                fail("buffered small-write benchmark lost progress")
              }
              offset += count
            }
            @io.Write::flush(writer)
          }
        },
        observe: () => {
          let copied = writer.get_ref().observed_bytes()
          {
            copied_bytes: copied,
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
          let copied = writer.observed_bytes()
          {
            copied_bytes: copied,
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
          let copied = writer.observed_bytes()
          {
            copied_bytes: copied,
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
fn vectored_bulk_case() -> BenchmarkCase raise @io.IoError {
  let first = b"vec"
  let second = b"tored"
  let sources = [
    @io.IoSlice::new(first, 0, first.length()),
    @io.IoSlice::new(second, 0, second.length()),
  ]
  {
    name: "sync_vectored_bulk",
    size: 8,
    bytes_per_iteration: 8L,
    prepare: iterations => {
      let writer = CountingWriter::new(scratch_capacity=8)
      {
        run: () => {
          for _ in 0..<iterations {
            let count = @io.Write::write_vectored(writer, sources[:])
            if count != 8 {
              fail("bulk vectored benchmark lost progress")
            }
          }
        },
        observe: () => {
          let copied = writer.observed_bytes()
          {
            copied_bytes: copied,
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
          { copied_bytes: 0L, underlying_calls: syscalls, syscalls }
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
          { copied_bytes: 0L, underlying_calls: syscalls, syscalls }
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
fn includes_case(selected : String?, name : String) -> Bool {
  selected is None || selected == Some(name)
}

///|
fn benchmark_cases(
  selected : String?,
) -> Array[BenchmarkCase] raise @io.IoError {
  let cases : Array[BenchmarkCase] = []
  if includes_case(selected, "sync_vectored_fallback") {
    cases.push(vectored_write_case())
  }
  if includes_case(selected, "sync_vectored_bulk") {
    cases.push(vectored_bulk_case())
  }
  for size in bench_sizes {
    if includes_case(selected, "buffer_shared_clone") {
      cases.push(shared_clone_case(size))
    }
    if includes_case(selected, "buffer_shared_slice") {
      cases.push(shared_slice_case(size))
    }
    if includes_case(selected, "buffer_shared_split") {
      cases.push(shared_split_case(size))
    }
    if includes_case(selected, "buffer_freeze") {
      cases.push(freeze_case(size))
    }
    if size == 1024 * 1024 && includes_case(selected, "buffer_cow_mutation") {
      cases.push(cow_case(size))
    }
    if size == 1024 * 1024 && includes_case(selected, "buffer_growth") {
      cases.push(growth_case(size))
    }
    if includes_case(selected, "sync_raw_read") {
      cases.push(raw_read_case(size))
    }
    if includes_case(selected, "sync_bufreader_small") {
      cases.push(buffered_read_case(size, 32, "sync_bufreader_small"))
    }
    if includes_case(selected, "sync_raw_small_write") {
      cases.push(raw_write_case(size, 32, "sync_raw_small_write"))
    }
    if includes_case(selected, "sync_bufwriter_small") {
      cases.push(buffered_write_case(size, 32, "sync_bufwriter_small"))
    }
    if size >= 8192 && includes_case(selected, "sync_bufreader_bypass") {
      cases.push(buffered_read_case(size, size, "sync_bufreader_bypass"))
    }
    if size >= 8192 && includes_case(selected, "sync_bufwriter_bypass") {
      cases.push(buffered_write_case(size, size, "sync_bufwriter_bypass"))
    }
    if size == 1024 && includes_case(selected, "sync_short_write_16") {
      cases.push(short_write_case(size, 16))
    }
    if includes_case(selected, "native_file_write") {
      cases.push(native_write_case(size))
    }
    if includes_case(selected, "native_file_read") {
      cases.push(native_read_case(size))
    }
    if includes_case(selected, "native_mmap_scan") {
      cases.push(mmap_case(size))
    }
  }
  cases
}

///|
fn selected_batch() -> Int {
  let args = @env.args()
  if args.length() < 2 || args.length() > 4 {
    abort("usage: bench BATCH [CASE] [MULTIPLIER]")
  }
  match args[1] {
    "1" => 1
    "2" => 2
    "3" => 3
    _ => abort("benchmark batch must be 1, 2, or 3")
  }
}

///|
fn iteration_multiplier() -> Int {
  128
}

///|
fn selected_case() -> String? {
  let args = @env.args()
  if args.length() >= 3 {
    if args[2] == "__all__" {
      None
    } else {
      Some(args[2])
    }
  } else {
    None
  }
}

///|
fn run_benchmarks(batch : Int, selected : String?) -> Unit raise {
  ensure_bench_output_dir()
  let raw = StringBuilder()
  raw.write_string(
    "implementation,name,size,batch,sample,iterations,elapsed_us\n",
  )
  let evidence = StringBuilder()
  evidence.write_string(
    "implementation,name,size,batch,iterations,observed_copied_bytes,underlying_calls,syscalls,copy_scope\n",
  )
  println(
    "implementation,name,size,batch,iterations,median_us,p95_us,bytes,copied_bytes,underlying_calls,syscalls,median_mib_per_s",
  )
  let cases = benchmark_cases(selected)
  let multiplier = iteration_multiplier()
  for case in cases {
    let stats = measure(case, multiplier)
    print_result(case, batch, stats)
    append_auxiliary_rows(raw, evidence, case, batch, stats)
  }
  @fs.write_string_to_file(
    bench_output_dir + "/moonbit-raw-batch-\{batch}.csv",
    raw.to_string(),
  )
  @fs.write_string_to_file(
    bench_output_dir + "/moonbit-copy-evidence-batch-\{batch}.csv",
    evidence.to_string(),
  )
}

///|
fn main {
  run_benchmarks(selected_batch(), selected_case()) catch {
    error => {
      println("benchmark failed")
      println(error)
      abort("benchmark execution failed")
    }
  }
}
