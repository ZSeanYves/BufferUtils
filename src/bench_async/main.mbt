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
let bench_output_root = ".tmp"

///|
let bench_output_dir = ".tmp/bufferutils-bench"

///|
let benchmark_keeper : @mbench.Bench = @mbench.Bench()

///|
struct AsyncBenchCounters {
  copied_bytes : Int64
  underlying_calls : Int64
  syscalls : Int64
}

///|
struct AsyncBenchStats {
  iterations : Int
  median_us : Double
  p95_us : Double
  counters : AsyncBenchCounters
  samples : Array[Double]
}

///|
struct RepeatingAsyncReader {
  data : FixedArray[Byte]
  mut position : Int
  mut remaining_bytes : Int64
  mut calls : Int64
  mut bytes : Int64
}

///|
impl @async_io.AsyncRead for RepeatingAsyncReader with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  if self.remaining_bytes == 0L || max_len == 0 {
    return 0
  }
  if self.position == self.data.length() {
    self.position = 0
  }
  let count = Int::min(
    max_len,
    Int::min(self.data.length() - self.position, self.remaining_bytes.to_int()),
  )
  self.data.blit_to(
    destination,
    src_offset=self.position,
    dst_offset=offset,
    len=count,
  )
  self.position += count
  self.remaining_bytes -= count.to_int64()
  self.calls += 1L
  self.bytes += count.to_int64()
  count
}

///|
struct CountingAsyncWriter {
  scratch : FixedArray[Byte]
  mut bytes : Int64
  mut calls : Int64
  mut checksum : Int
}

///|
impl @async_io.AsyncWrite for CountingAsyncWriter with fn write(
  self,
  source,
  offset~,
  len~,
) {
  let count = Int::min(len, self.scratch.length())
  self.scratch.blit_from_bytes(0, source, offset, count)
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
  self.bytes += count.to_int64()
  self.calls += 1L
  count
}

///|
impl @async_io.AsyncWrite for CountingAsyncWriter with fn flush(_self) {
  ()
}

///|
fn pattern_bytes(len : Int) -> Array[Byte] {
  Array::makei(len, i => (i % 251).to_byte())
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
fn p95(samples : Array[Double]) -> Double {
  let index = (samples.length() * 95 + 99) / 100 - 1
  samples[Int::max(0, Int::min(index, samples.length() - 1))]
}

///|
async fn run_async_copy_once(
  payload : Array[Byte],
  iterations : Int,
) -> (Double, AsyncBenchCounters) {
  let total = payload.length().to_int64() * iterations.to_int64()
  let reader : RepeatingAsyncReader = {
    data: FixedArray::from_array(payload[:]),
    position: 0,
    remaining_bytes: total,
    calls: 0L,
    bytes: 0L,
  }
  let writer : CountingAsyncWriter = {
    scratch: FixedArray::make(payload.length(), (0).to_byte()),
    bytes: 0L,
    calls: 0L,
    checksum: 0,
  }
  let started = @mbench.monotonic_clock_start()
  let copied = @async_io.copy(reader, writer, buffer_size=8192)
  let elapsed = @mbench.monotonic_clock_end(started)
  benchmark_keeper.keep(writer.checksum)
  if copied.to_int64() != total || writer.bytes != total {
    fail("async copy benchmark lost progress")
  }
  (
    elapsed,
    {
      copied_bytes: reader.bytes + writer.bytes,
      underlying_calls: reader.calls + writer.calls,
      syscalls: 0L,
    },
  )
}

///|
async fn run_tcp_loopback_once(
  payload : Array[Byte],
  iterations : Int,
) -> (Double, AsyncBenchCounters) {
  let listener = @async_io.AsyncTcpListener::bind("127.0.0.1:0")
  let client = @async_io.AsyncTcpStream::connect(
    "127.0.0.1",
    listener.local_port(),
  )
  let server = listener.accept()
  let response = FixedArray::make(payload.length(), (0).to_byte())
  let payload_bytes = Bytes::from_array(payload)
  let elapsed = Ref(0.0)
  @async.with_task_group(group => {
    let echo = group.spawn(() => {
      let request = FixedArray::make(payload.length(), (0).to_byte())
      for _ in 0..<iterations {
        @async_io.AsyncRead::read_exact(server, request)
        @async_io.AsyncWrite::write_all(
          server,
          request.unsafe_reinterpret_as_bytes(),
        )
      }
    })
    let started = @mbench.monotonic_clock_start()
    for _ in 0..<iterations {
      @async_io.AsyncWrite::write_all(client, payload_bytes)
      @async_io.AsyncRead::read_exact(client, response)
    }
    elapsed.val = @mbench.monotonic_clock_end(started)
    echo.wait()
  })
  @async_io.AsyncClose::close(client)
  @async_io.AsyncClose::close(server)
  @async_io.AsyncClose::close(listener)
  (elapsed.val, { copied_bytes: 0L, underlying_calls: 0L, syscalls: 0L })
}

///|
async fn run_case_once(
  name : String,
  payload : Array[Byte],
  iterations : Int,
) -> (Double, AsyncBenchCounters) {
  if name == "async_copy" {
    run_async_copy_once(payload, iterations)
  } else {
    run_tcp_loopback_once(payload, iterations)
  }
}

///|
fn iteration_limit(name : String, payload_size : Int) -> Int {
  if name == "async_copy" {
    Int::max(1, 2147483647 / payload_size)
  } else {
    maximum_iterations
  }
}

///|
fn workload_multiplier(name : String, payload_size : Int) -> Int {
  if name == "async_copy" && payload_size == 1024 {
    16
  } else if name == "async_copy" {
    2
  } else {
    1
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
      match row_iterations.bind(parse_positive_int) {
        Some(iterations) => return Some(iterations)
        None => abort("shared iteration map has an invalid count")
      }
    }
  }
  abort("shared iteration map is missing a requested case")
}

///|
async fn measure_case(
  name : String,
  payload : Array[Byte],
  initial_iterations : Int,
) -> AsyncBenchStats {
  let mut iterations = initial_iterations
  let limit = iteration_limit(name, payload.length())
  let forced = forced_iterations(name, payload.length())
  match forced {
    Some(value) if value <= limit => iterations = value
    Some(_) => abort("shared iteration count exceeds the async benchmark limit")
    None => ()
  }
  iterations = Int::min(iterations, limit)
  let mut elapsed = 0.0
  while forced is None && elapsed < minimum_sample_us && iterations < limit {
    let (sample, _) = run_case_once(name, payload, iterations)
    elapsed = sample
    if elapsed < minimum_sample_us {
      iterations = Int::min(limit, iterations * 2)
    }
  }
  if forced is None {
    iterations = Int::min(
      limit,
      iterations * workload_multiplier(name, payload.length()),
    )
  }
  while true {
    for _ in 0..<warmup_samples {
      ignore(run_case_once(name, payload, iterations))
    }
    let samples : Array[Double] = []
    let mut counters : AsyncBenchCounters = {
      copied_bytes: 0L,
      underlying_calls: 0L,
      syscalls: 0L,
    }
    for _ in 0..<measured_samples {
      let (sample, observed) = run_case_once(name, payload, iterations)
      samples.push(sample)
      counters = observed
    }
    samples.sort()
    let median_us = median(samples)
    if forced is Some(_) ||
      median_us >= minimum_sample_us ||
      iterations >= limit {
      return { iterations, median_us, p95_us: p95(samples), counters, samples }
    }
    iterations = Int::min(limit, iterations * 2)
  }
  abort("unreachable async benchmark loop")
}

///|
fn throughput(bytes : Int64, micros : Double) -> Double {
  bytes.to_double() / 1048576.0 / (micros / 1000000.0)
}

///|
async fn print_case(
  name : String,
  size : Int,
  batch : Int,
  raw : StringBuilder,
  evidence : StringBuilder,
  multiplier : Int,
) -> Unit {
  let payload = pattern_bytes(size)
  let stats = measure_case(name, payload, multiplier)
  let bytes = size.to_int64() * stats.iterations.to_int64()
  println(
    "moonbit,\{name},\{size},\{batch},\{stats.iterations},\{stats.median_us},\{stats.p95_us},\{bytes},\{stats.counters.copied_bytes},\{stats.counters.underlying_calls},\{stats.counters.syscalls},\{throughput(bytes, stats.median_us)}",
  )
  for index, elapsed in stats.samples {
    raw.write_string(
      "moonbit,\{name},\{size},\{batch},\{index + 1},\{stats.iterations},\{elapsed}\n",
    )
  }
  let scope = if name == "tcp_loopback" {
    "unavailable"
  } else {
    "fixture-observed"
  }
  evidence.write_string(
    "moonbit,\{name},\{size},\{batch},\{stats.iterations},\{stats.counters.copied_bytes},\{stats.counters.underlying_calls},\{stats.counters.syscalls},\{scope}\n",
  )
}

///|
fn selected_batch() -> Int {
  let args = @env.args()
  if args.length() < 2 || args.length() > 4 {
    abort("usage: bench_async BATCH [CASE] [MULTIPLIER]")
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
async fn main {
  let batch = selected_batch()
  let args = @env.args()
  let selected = if args.length() >= 3 && args[2] != "__all__" {
    Some(args[2])
  } else {
    None
  }
  let multiplier = iteration_multiplier()
  if !@fs.path_exists(bench_output_root) {
    @fs.create_dir(bench_output_root)
  }
  if !@fs.path_exists(bench_output_dir) {
    @fs.create_dir(bench_output_dir)
  }
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
  for size in [1024, 1024 * 1024] {
    if selected is None || selected == Some("async_copy") {
      print_case("async_copy", size, batch, raw, evidence, multiplier)
    }
    if selected is None || selected == Some("tcp_loopback") {
      print_case("tcp_loopback", size, batch, raw, evidence, multiplier)
    }
  }
  write_control_benchmarks(batch, selected)
  @fs.write_string_to_file(
    bench_output_dir + "/moonbit-async-raw-batch-\{batch}.csv",
    raw.to_string(),
  )
  @fs.write_string_to_file(
    bench_output_dir + "/moonbit-async-copy-evidence-batch-\{batch}.csv",
    evidence.to_string(),
  )
}
