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
}

///|
struct RepeatingAsyncReader {
  data : Array[Byte]
  mut position : Int
  mut remaining_bytes : Int64
  mut calls : Int64
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
  for i in 0..<count {
    destination[offset + i] = self.data[self.position + i]
  }
  self.position += count
  self.remaining_bytes -= count.to_int64()
  self.calls += 1L
  count
}

///|
struct CountingAsyncWriter {
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
  let mut checksum = self.checksum
  for i in 0..<len {
    checksum = (checksum + source[offset + i].to_int()) % 65521
  }
  self.checksum = checksum
  self.bytes += len.to_int64()
  self.calls += 1L
  len
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
    data: payload,
    position: 0,
    remaining_bytes: total,
    calls: 0L,
  }
  let writer : CountingAsyncWriter = { bytes: 0L, calls: 0L, checksum: 0 }
  let started = @mbench.monotonic_clock_start()
  let copied = @async_io.copy(reader, writer, buffer_size=8192)
  let elapsed = @mbench.monotonic_clock_end(started)
  if copied.to_int64() != total || writer.bytes != total {
    fail("async copy benchmark lost progress")
  }
  (
    elapsed,
    {
      copied_bytes: total * 2L,
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
  let total = payload.length().to_int64() * iterations.to_int64()
  (
    elapsed.val,
    { copied_bytes: total * 2L, underlying_calls: 0L, syscalls: 0L },
  )
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
async fn measure_case(name : String, payload : Array[Byte]) -> AsyncBenchStats {
  let mut iterations = 1
  let mut elapsed = 0.0
  while elapsed < minimum_sample_us && iterations < maximum_iterations {
    let (sample, _) = run_case_once(name, payload, iterations)
    elapsed = sample
    if elapsed < minimum_sample_us {
      iterations = Int::min(maximum_iterations, iterations * 2)
    }
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
    if median_us >= minimum_sample_us || iterations >= maximum_iterations {
      return { iterations, median_us, p95_us: p95(samples), counters }
    }
    iterations = Int::min(maximum_iterations, iterations * 2)
  }
  abort("unreachable async benchmark loop")
}

///|
fn throughput(bytes : Int64, micros : Double) -> Double {
  bytes.to_double() / 1048576.0 / (micros / 1000000.0)
}

///|
async fn print_case(name : String, size : Int) -> Unit {
  let payload = pattern_bytes(size)
  for batch in 1..<=benchmark_batches {
    let stats = measure_case(name, payload)
    let bytes = size.to_int64() * stats.iterations.to_int64()
    println(
      "moonbit,\{name},\{size},\{batch},\{stats.iterations},\{stats.median_us},\{stats.p95_us},\{bytes},\{stats.counters.copied_bytes},\{stats.counters.underlying_calls},\{stats.counters.syscalls},\{throughput(bytes, stats.median_us)}",
    )
  }
}

///|
async fn main {
  println(
    "implementation,name,size,batch,iterations,median_us,p95_us,bytes,copied_bytes,underlying_calls,syscalls,median_mib_per_s",
  )
  for size in [1024, 1024 * 1024] {
    print_case("async_copy", size)
    print_case("tcp_loopback", size)
  }
}
