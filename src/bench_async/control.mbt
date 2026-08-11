///|
struct AsyncControlCounters {
  operations : Int64
  bytes : Int64
  copied_bytes : Int64
  await_points : Int64
  failures : Int64
}

///|
struct AsyncControlStats {
  iterations : Int
  median_us : Double
  p95_us : Double
  counters : AsyncControlCounters
  samples : Array[Double]
}

///|
struct ReadyReadProbe {
  mut calls : Int64
}

///|
impl @async_io.AsyncRead for ReadyReadProbe with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  if max_len == 0 {
    return 0
  }
  destination[offset] = b'R'
  self.calls += 1L
  1
}

///|
struct PendingReadProbe {
  mut calls : Int64
}

///|
impl @async_io.AsyncRead for PendingReadProbe with fn read(
  self,
  destination,
  offset? = 0,
  max_len? = destination.length() - offset,
) {
  if max_len == 0 {
    return 0
  }
  @async.pause()
  destination[offset] = b'P'
  self.calls += 1L
  1
}

///|
struct ShortProgressWriter {
  scratch : FixedArray[Byte]
  mut calls : Int64
  mut bytes : Int64
}

///|
impl @async_io.AsyncWrite for ShortProgressWriter with fn write(
  self,
  source,
  offset~,
  len~,
) {
  let count = Int::min(len, self.scratch.length())
  self.scratch.blit_from_bytes(0, source, offset, count)
  self.calls += 1L
  self.bytes += count.to_int64()
  count
}

///|
impl @async_io.AsyncWrite for ShortProgressWriter with fn flush(_self) {
  ()
}

///|
struct ShutdownFailureWriter {
  mut calls : Int64
}

///|
impl @async_io.AsyncWrite for ShutdownFailureWriter with fn write(
  _self,
  _source,
  offset~,
  len~,
) {
  ignore(offset)
  len
}

///|
impl @async_io.AsyncWrite for ShutdownFailureWriter with fn flush(_self) {
  ()
}

///|
impl @async_io.AsyncWrite for ShutdownFailureWriter with fn shutdown(self) {
  self.calls += 1L
  raise @io.io_error(@io.Backend, "benchmark shutdown failure")
}

///|
async fn run_ready_control(iterations : Int) -> (Double, AsyncControlCounters) {
  let reader : ReadyReadProbe = { calls: 0L }
  let destination = FixedArray::make(1, (0).to_byte())
  let started = @mbench.monotonic_clock_start()
  for _ in 0..<iterations {
    if @async_io.AsyncRead::read(reader, destination) != 1 {
      fail("ready async control lost progress")
    }
  }
  let elapsed = @mbench.monotonic_clock_end(started)
  benchmark_keeper.keep(destination[0])
  (
    elapsed,
    {
      operations: iterations.to_int64(),
      bytes: reader.calls,
      copied_bytes: reader.calls,
      await_points: reader.calls,
      failures: 0L,
    },
  )
}

///|
async fn run_pending_control(
  iterations : Int,
) -> (Double, AsyncControlCounters) {
  let reader : PendingReadProbe = { calls: 0L }
  let destination = FixedArray::make(1, (0).to_byte())
  let started = @mbench.monotonic_clock_start()
  for _ in 0..<iterations {
    if @async_io.AsyncRead::read(reader, destination) != 1 {
      fail("pending async control lost progress")
    }
  }
  let elapsed = @mbench.monotonic_clock_end(started)
  benchmark_keeper.keep(destination[0])
  (
    elapsed,
    {
      operations: iterations.to_int64(),
      bytes: reader.calls,
      copied_bytes: reader.calls,
      await_points: reader.calls,
      failures: 0L,
    },
  )
}

///|
async fn run_short_progress_control(
  iterations : Int,
) -> (Double, AsyncControlCounters) {
  let payload = Bytes::makei(1024, index => (index % 251).to_byte())
  let writer : ShortProgressWriter = {
    scratch: FixedArray::make(16, (0).to_byte()),
    calls: 0L,
    bytes: 0L,
  }
  let started = @mbench.monotonic_clock_start()
  for _ in 0..<iterations {
    @async_io.AsyncWrite::write_all(writer, payload)
  }
  let elapsed = @mbench.monotonic_clock_end(started)
  benchmark_keeper.keep(writer.scratch[0])
  (
    elapsed,
    {
      operations: iterations.to_int64(),
      bytes: 1024L * iterations.to_int64(),
      copied_bytes: writer.bytes,
      await_points: writer.calls,
      failures: 0L,
    },
  )
}

///|
async fn run_accumulation_control(
  iterations : Int,
  materialize : Bool,
) -> (Double, AsyncControlCounters) {
  let payload = FixedArray::makei(1024, index => (index % 251).to_byte())
  let total_bytes = Ref(0L)
  let total_calls = Ref(0L)
  let copied_bytes = Ref(0L)
  let checksum = Ref(0)
  let started = @mbench.monotonic_clock_start()
  for _ in 0..<iterations {
    let reader : RepeatingAsyncReader = {
      data: payload,
      position: 0,
      remaining_bytes: 1024L,
      calls: 0L,
      bytes: 0L,
    }
    if materialize {
      let bytes = @async_io.read_to_end(reader)
      checksum.val = (checksum.val + bytes[0].to_int()) % 65521
      copied_bytes.val += reader.bytes + bytes.length().to_int64()
    } else {
      let bytes = @async_io.read_to_shared_bytes(reader)
      checksum.val = (checksum.val + bytes.as_bytes_view()[0].to_int()) % 65521
      copied_bytes.val += reader.bytes
    }
    total_bytes.val += reader.bytes
    total_calls.val += reader.calls + 1L
  }
  let elapsed = @mbench.monotonic_clock_end(started)
  benchmark_keeper.keep(checksum.val)
  (
    elapsed,
    {
      operations: iterations.to_int64(),
      bytes: total_bytes.val,
      copied_bytes: copied_bytes.val,
      await_points: total_calls.val,
      failures: 0L,
    },
  )
}

///|
async fn run_shared_read_control(
  iterations : Int,
) -> (Double, AsyncControlCounters) {
  run_accumulation_control(iterations, false)
}

///|
async fn run_materialized_read_control(
  iterations : Int,
) -> (Double, AsyncControlCounters) {
  run_accumulation_control(iterations, true)
}

///|
async fn run_typed_read_control(
  iterations : Int,
) -> (Double, AsyncControlCounters) {
  let reader : RepeatingAsyncReader = {
    data: FixedArray::makei(8, index => (index + 1).to_byte()),
    position: 0,
    remaining_bytes: 8L * iterations.to_int64(),
    calls: 0L,
    bytes: 0L,
  }
  let checksum = Ref(0UL)
  let started = @mbench.monotonic_clock_start()
  for _ in 0..<iterations {
    checksum.val = checksum.val ^ @async_io.AsyncRead::read_u64_be(reader)
  }
  let elapsed = @mbench.monotonic_clock_end(started)
  benchmark_keeper.keep(checksum.val)
  (
    elapsed,
    {
      operations: iterations.to_int64(),
      bytes: reader.bytes,
      copied_bytes: reader.bytes,
      await_points: reader.calls,
      failures: 0L,
    },
  )
}

///|
async fn run_typed_write_control(
  iterations : Int,
) -> (Double, AsyncControlCounters) {
  let writer : CountingAsyncWriter = {
    scratch: FixedArray::make(8, (0).to_byte()),
    bytes: 0L,
    calls: 0L,
    checksum: 0,
  }
  let started = @mbench.monotonic_clock_start()
  for _ in 0..<iterations {
    @async_io.AsyncWrite::write_u64_be(writer, 0x0102030405060708UL)
  }
  let elapsed = @mbench.monotonic_clock_end(started)
  benchmark_keeper.keep(writer.checksum)
  (
    elapsed,
    {
      operations: iterations.to_int64(),
      bytes: writer.bytes,
      copied_bytes: writer.bytes,
      await_points: writer.calls,
      failures: 0L,
    },
  )
}

///|
async fn run_shutdown_failure_control(
  iterations : Int,
) -> (Double, AsyncControlCounters) {
  let writer : ShutdownFailureWriter = { calls: 0L }
  let failures = Ref(0L)
  let started = @mbench.monotonic_clock_start()
  for _ in 0..<iterations {
    try @async_io.AsyncWrite::shutdown(writer) catch {
      _ => failures.val += 1L
    } noraise {
      _ => fail("shutdown failure control unexpectedly succeeded")
    }
  }
  let elapsed = @mbench.monotonic_clock_end(started)
  (
    elapsed,
    {
      operations: iterations.to_int64(),
      bytes: 0L,
      copied_bytes: 0L,
      await_points: writer.calls,
      failures: failures.val,
    },
  )
}

///|
async fn run_cancel_control(iterations : Int) -> (Double, AsyncControlCounters) {
  let cancellations = Ref(0L)
  let started = @mbench.monotonic_clock_start()
  for _ in 0..<iterations {
    @async.with_task_group(group => {
      let (writer, reader) = @async_io.duplex(capacity=1)
      let waiting = group.spawn(() => {
        let destination = FixedArray::make(1, (0).to_byte())
        ignore(@async_io.AsyncRead::read(reader, destination))
      })
      @async.pause()
      waiting.cancel()
      try waiting.wait() catch {
        error =>
          if @async.is_cancellation_error(error) {
            cancellations.val += 1L
          } else {
            raise error
          }
      } noraise {
        _ => fail("cancel control unexpectedly completed")
      }
      @async_io.AsyncClose::close(writer)
      @async_io.AsyncClose::close(reader)
    })
  }
  let elapsed = @mbench.monotonic_clock_end(started)
  (
    elapsed,
    {
      operations: iterations.to_int64(),
      bytes: 0L,
      copied_bytes: 0L,
      await_points: iterations.to_int64() * 2L,
      failures: cancellations.val,
    },
  )
}

///|
async fn run_large_lines_control(
  iterations : Int,
) -> (Double, AsyncControlCounters) {
  let line_size = 65536
  let data = FixedArray::make(line_size, b'a')
  data[line_size - 1] = b'\n'
  let reader : RepeatingAsyncReader = {
    data,
    position: 0,
    remaining_bytes: line_size.to_int64() * iterations.to_int64(),
    calls: 0L,
    bytes: 0L,
  }
  let lines = @async_io.AsyncBufReader::new(reader, capacity=8192).lines()
  let checksum = Ref(0)
  let started = @mbench.monotonic_clock_start()
  for _ in 0..<iterations {
    match lines.next() {
      Some(line) => checksum.val = (checksum.val + line.length()) % 65521
      None => fail("large-line control reached EOF before the final line")
    }
  }
  if lines.next() is Some(_) {
    fail("large-line control did not report EOF")
  }
  let elapsed = @mbench.monotonic_clock_end(started)
  benchmark_keeper.keep(checksum.val)
  (
    elapsed,
    {
      operations: iterations.to_int64() + 1L,
      bytes: reader.bytes,
      copied_bytes: reader.bytes,
      await_points: reader.calls + 1L,
      failures: 0L,
    },
  )
}

///|
async fn run_no_delimiter_split_control(
  iterations : Int,
) -> (Double, AsyncControlCounters) {
  let segment_size = 65536
  let data = FixedArray::make(segment_size, b's')
  let cursors = Array::makei(iterations, _ => {
    let reader : RepeatingAsyncReader = {
      data,
      position: 0,
      remaining_bytes: segment_size.to_int64(),
      calls: 0L,
      bytes: 0L,
    }
    @async_io.AsyncBufReader::new(reader, capacity=8192).split(b',')
  })
  let total_calls = Ref(0L)
  let total_bytes = Ref(0L)
  let checksum = Ref(0)
  let started = @mbench.monotonic_clock_start()
  for cursor in cursors {
    match cursor.next() {
      Some(segment) => {
        if segment.length() != segment_size {
          fail("no-delimiter split control lost bytes")
        }
        checksum.val = (checksum.val + segment[0].to_int()) % 65521
      }
      None => fail("no-delimiter split control returned no segment")
    }
    if cursor.next() is Some(_) {
      fail("no-delimiter split control did not report EOF")
    }
    let reader = cursor.into_inner().get_ref()
    total_calls.val += reader.calls
    total_bytes.val += reader.bytes
  }
  let elapsed = @mbench.monotonic_clock_end(started)
  benchmark_keeper.keep(checksum.val)
  (
    elapsed,
    {
      operations: iterations.to_int64() * 2L,
      bytes: total_bytes.val,
      copied_bytes: total_bytes.val,
      await_points: total_calls.val + iterations.to_int64(),
      failures: 0L,
    },
  )
}

///|
async fn run_control_once(
  name : String,
  iterations : Int,
) -> (Double, AsyncControlCounters) {
  match name {
    "async_ready_read" => run_ready_control(iterations)
    "async_pending_read" => run_pending_control(iterations)
    "async_short_progress" => run_short_progress_control(iterations)
    "async_shared_read" => run_shared_read_control(iterations)
    "async_materialized_read" => run_materialized_read_control(iterations)
    "async_typed_u64_read" => run_typed_read_control(iterations)
    "async_typed_u64_write" => run_typed_write_control(iterations)
    "async_cancel" => run_cancel_control(iterations)
    "async_shutdown_failure" => run_shutdown_failure_control(iterations)
    "async_lines_large" => run_large_lines_control(iterations)
    "async_split_no_delimiter_eof" => run_no_delimiter_split_control(iterations)
    _ => abort("unknown async control benchmark")
  }
}

///|
fn control_size(name : String) -> Int {
  match name {
    "async_ready_read" | "async_pending_read" => 1
    "async_short_progress" => 1024
    "async_shared_read" | "async_materialized_read" => 1024
    "async_typed_u64_read" | "async_typed_u64_write" => 8
    "async_lines_large" | "async_split_no_delimiter_eof" => 65536
    _ => 0
  }
}

///|
async fn measure_control(name : String) -> AsyncControlStats {
  let mut iterations = 1
  let mut elapsed = 0.0
  while elapsed < minimum_sample_us && iterations < maximum_iterations {
    let (sample, _) = run_control_once(name, iterations)
    elapsed = sample
    if elapsed < minimum_sample_us {
      iterations = Int::min(maximum_iterations, iterations * 2)
    }
  }
  while true {
    for _ in 0..<warmup_samples {
      ignore(run_control_once(name, iterations))
    }
    let samples : Array[Double] = []
    let mut counters : AsyncControlCounters = {
      operations: 0L,
      bytes: 0L,
      copied_bytes: 0L,
      await_points: 0L,
      failures: 0L,
    }
    for _ in 0..<measured_samples {
      let (sample, observed) = run_control_once(name, iterations)
      samples.push(sample)
      counters = observed
    }
    samples.sort()
    let median_us = median(samples)
    if median_us >= minimum_sample_us || iterations >= maximum_iterations {
      return { iterations, median_us, p95_us: p95(samples), counters, samples }
    }
    iterations = Int::min(maximum_iterations, iterations * 2)
  }
  abort("unreachable async control benchmark loop")
}

///|
async fn write_control_benchmarks(batch : Int, selected : String?) -> Unit {
  let summary = StringBuilder()
  summary.write_string(
    "implementation,name,size,batch,iterations,median_us,p95_us,operations,bytes,copied_bytes,await_points,failures\n",
  )
  let raw = StringBuilder()
  raw.write_string(
    "implementation,name,size,batch,sample,iterations,elapsed_us\n",
  )
  for
    name in [
      "async_ready_read", "async_pending_read", "async_short_progress", "async_shared_read",
      "async_materialized_read", "async_cancel", "async_shutdown_failure", "async_typed_u64_read",
      "async_typed_u64_write", "async_lines_large", "async_split_no_delimiter_eof",
    ] {
    if selected is None || selected == Some(name) {
      let stats = measure_control(name)
      let size = control_size(name)
      summary.write_string(
        "moonbit,\{name},\{size},\{batch},\{stats.iterations},\{stats.median_us},\{stats.p95_us},\{stats.counters.operations},\{stats.counters.bytes},\{stats.counters.copied_bytes},\{stats.counters.await_points},\{stats.counters.failures}\n",
      )
      for index, sample in stats.samples {
        raw.write_string(
          "moonbit,\{name},\{size},\{batch},\{index + 1},\{stats.iterations},\{sample}\n",
        )
      }
    }
  }
  @fs.write_string_to_file(
    bench_output_dir + "/moonbit-async-control-batch-\{batch}.csv",
    summary.to_string(),
  )
  @fs.write_string_to_file(
    bench_output_dir + "/moonbit-async-control-raw-batch-\{batch}.csv",
    raw.to_string(),
  )
}
