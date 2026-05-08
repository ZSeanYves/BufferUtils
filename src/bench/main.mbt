///|
let bench_output_root = ".tmp"

///|
let bench_output_dir = ".tmp/bufferutils-bench"

///|
let bench_runs = 5

///|
let bench_warmup_runs = 1

///|
let bench_sizes : Array[(String, Int)] = [
  ("1KB", 1024),
  ("64KB", 64 * 1024),
  ("1MB", 1024 * 1024),
  ("10MB", 10 * 1024 * 1024),
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
fn bench_path(name : String) -> String raise @fs.IOError {
  ensure_bench_output_dir()
  bench_output_dir + "/" + name
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
fn default_stream_capacity(bytes_len : Int) -> Int {
  if bytes_len < 8192 {
    1024
  } else {
    8192
  }
}

///|
fn throughput_mib_per_s(bytes_len : Int, mean_us : Double) -> Double {
  if mean_us <= 0.0 {
    0.0
  } else {
    let mib = bytes_len.to_double() / 1048576.0
    mib / (mean_us / 1000000.0)
  }
}

///|
fn measure_mean_us(
  warmup_runs : Int,
  runs : Int,
  f : () -> Unit raise,
) -> Double raise {
  for _ in 0..<warmup_runs {
    f()
  }
  let total_us = for i = 0, sum = 0.0; i < runs; i = i + 1 {
    let started = @mbench.monotonic_clock_start()
    f()
    let elapsed_us = @mbench.monotonic_clock_end(started)
    continue i + 1, sum + elapsed_us
  } nobreak {
    sum
  }
  total_us / runs.to_double()
}

///|
fn print_header() -> Unit {
  println("name,size,bytes,temp_file,mean_us,throughput_mib_per_s,runs")
}

///|
fn print_result(
  name : String,
  size_label : String,
  bytes_len : Int,
  temp_file : Bool,
  mean_us : Double,
  runs : Int,
) -> Unit {
  println(
    "\{name},\{size_label},\{bytes_len},\{temp_file},\{mean_us},\{throughput_mib_per_s(bytes_len, mean_us)},\{runs}",
  )
}

///|
fn bench_buffer_reader(bytes_len : Int) -> Unit raise {
  let data = pattern_bytes(bytes_len)
  let bytes = @bufferutils.array_to_bytes(data)
  let reader = @bufferutils.new_reader(bytes)
  let out : Array[Byte] = []
  for _ in 0..<bytes_len {
    out.push(reader.read_byte())
  }
  ignore(out.length())
}

///|
fn bench_buffer_writer_fixed(bytes_len : Int) -> Unit raise {
  let data = pattern_bytes(bytes_len)
  let writer = @bufferutils.new_fixed_writer(bytes_len)
  writer.write_all(data)
  ignore(writer.flush_to_bytes().length())
}

///|
fn bench_buffer_writer_growing(bytes_len : Int) -> Unit raise {
  let data = pattern_bytes(bytes_len)
  let writer = @bufferutils.new_growing_writer(1)
  writer.write_all(data)
  ignore(writer.flush_to_bytes().length())
}

///|
fn bench_buf_reader_read_to_end(bytes_len : Int) -> Unit raise {
  let data = pattern_bytes(bytes_len)
  let source = @bufferutils.new_memory_source(@bufferutils.array_to_bytes(data))
  let reader = @bufferutils.new_buf_reader(
    source,
    default_stream_capacity(bytes_len),
  )
  ignore(reader.read_to_end().length())
}

///|
fn bench_buffer_reader_remaining_slice(bytes_len : Int) -> Unit {
  let data = pattern_bytes(bytes_len)
  let reader = @bufferutils.new_reader(@bufferutils.array_to_bytes(data))
  ignore(reader.remaining_slice().length())
}

///|
fn bench_buffer_reader_peek_slice(bytes_len : Int) -> Unit raise {
  let data = pattern_bytes(bytes_len)
  let reader = @bufferutils.new_reader(@bufferutils.array_to_bytes(data))
  ignore(reader.peek_slice(bytes_len).length())
}

///|
fn bench_file_source_peek_remaining(path : String) -> Unit raise {
  let source = @bufferutils.new_file_source(path)
  ignore(source.peek_remaining().length())
}

///|
fn bench_buf_writer_write_all_flush(bytes_len : Int) -> Unit raise {
  let data = pattern_bytes(bytes_len)
  let sink = @bufferutils.new_memory_sink()
  let writer = @bufferutils.new_buf_writer(
    sink,
    default_stream_capacity(bytes_len),
  )
  writer.write_all(data)
  writer.flush()
  ignore(writer.into_inner().len())
}

///|
fn prepare_file_source_fixture(
  size_label : String,
  bytes_len : Int,
) -> String raise {
  let path = bench_path("file_source_\{size_label}.bin")
  let data = pattern_bytes(bytes_len)
  @fs.write_bytes_to_file(path, @bufferutils.array_to_bytes(data))
  path
}

///|
fn bench_file_source_snapshot(path : String) -> Unit raise {
  let source = @bufferutils.new_file_source(path)
  ignore(source.read_to_end().length())
}

///|
fn bench_native_file_source_read_chunk(
  path : String,
  bytes_len : Int,
) -> Unit raise {
  let source = @native.new_native_file_source(path)
  let chunk_size = default_stream_capacity(bytes_len)
  let mut total = 0
  while true {
    let chunk = source.read_chunk(chunk_size)
    if chunk.length() == 0 {
      break
    }
    total += chunk.length()
  }
  source.close()
  ignore(total)
}

///|
fn bench_native_buf_reader_read_to_end(
  path : String,
  bytes_len : Int,
) -> Unit raise {
  let reader = @native.new_native_buf_reader(
    path,
    default_stream_capacity(bytes_len),
  )
  ignore(reader.read_to_end().length())
  reader.close()
}

///|
fn prepare_file_sink_path(size_label : String) -> String raise @fs.IOError {
  bench_path("file_sink_\{size_label}.bin")
}

///|
fn bench_file_sink_flush(path : String, bytes_len : Int) -> Unit raise {
  let data = pattern_bytes(bytes_len)
  let sink = @bufferutils.new_file_sink(path)
  sink.write(data)
  sink.flush()
}

///|
fn prepare_native_file_sink_path(
  size_label : String,
) -> String raise @fs.IOError {
  bench_path("native_file_sink_\{size_label}.bin")
}

///|
fn bench_native_file_sink_write_flush(
  path : String,
  bytes_len : Int,
) -> Unit raise {
  let data = pattern_bytes(bytes_len)
  let sink = @native.new_native_file_sink(
    path,
    @native.NativeFileMode::Overwrite,
  )
  sink.write_all(data)
  sink.flush()
  sink.close()
}

///|
fn prepare_native_buf_writer_path(
  size_label : String,
) -> String raise @fs.IOError {
  bench_path("native_buf_writer_\{size_label}.bin")
}

///|
fn bench_native_buf_writer_write_flush(
  path : String,
  bytes_len : Int,
) -> Unit raise {
  let data = pattern_bytes(bytes_len)
  let writer = @native.new_native_buf_writer(
    path,
    default_stream_capacity(bytes_len),
    @native.NativeFileMode::Overwrite,
  )
  writer.write_all(data)
  writer.flush()
  writer.close()
}

///|
fn run_benchmark_case(
  name : String,
  size_label : String,
  bytes_len : Int,
  temp_file : Bool,
  bench_case : () -> Unit raise,
) -> Unit raise {
  let mean_us = measure_mean_us(bench_warmup_runs, bench_runs, bench_case)
  print_result(name, size_label, bytes_len, temp_file, mean_us, bench_runs)
}

///|
fn run_all_benchmarks() -> Unit raise {
  print_header()
  for size_entry in bench_sizes {
    let (size_label, bytes_len) = size_entry

    run_benchmark_case(
      "memory_buffer_reader_sequential_read",
      size_label,
      bytes_len,
      false,
      fn() raise { bench_buffer_reader(bytes_len) },
    )

    run_benchmark_case(
      "memory_buffer_writer_fixed_write",
      size_label,
      bytes_len,
      false,
      fn() raise { bench_buffer_writer_fixed(bytes_len) },
    )

    run_benchmark_case(
      "memory_buffer_writer_growing_write",
      size_label,
      bytes_len,
      false,
      fn() raise { bench_buffer_writer_growing(bytes_len) },
    )

    run_benchmark_case(
      "memory_streaming_buf_reader_read_to_end",
      size_label,
      bytes_len,
      false,
      fn() raise { bench_buf_reader_read_to_end(bytes_len) },
    )

    run_benchmark_case(
      "memory_buffer_reader_remaining_slice_experimental",
      size_label,
      bytes_len,
      false,
      fn() { bench_buffer_reader_remaining_slice(bytes_len) },
    )

    run_benchmark_case(
      "memory_buffer_reader_peek_slice_experimental",
      size_label,
      bytes_len,
      false,
      fn() raise { bench_buffer_reader_peek_slice(bytes_len) },
    )

    run_benchmark_case(
      "memory_streaming_buf_writer_write_all_flush",
      size_label,
      bytes_len,
      false,
      fn() raise { bench_buf_writer_write_all_flush(bytes_len) },
    )

    let file_source_path = prepare_file_source_fixture(size_label, bytes_len)
    run_benchmark_case(
      "file_memory_source_read_snapshot",
      size_label,
      bytes_len,
      true,
      fn() raise { bench_file_source_snapshot(file_source_path) },
    )

    run_benchmark_case(
      "file_memory_source_peek_remaining_experimental",
      size_label,
      bytes_len,
      true,
      fn() raise { bench_file_source_peek_remaining(file_source_path) },
    )

    run_benchmark_case(
      "native_file_source_read_chunk_experimental",
      size_label,
      bytes_len,
      true,
      fn() raise {
        bench_native_file_source_read_chunk(file_source_path, bytes_len)
      },
    )

    run_benchmark_case(
      "native_buffered_reader_read_to_end_experimental",
      size_label,
      bytes_len,
      true,
      fn() raise {
        bench_native_buf_reader_read_to_end(file_source_path, bytes_len)
      },
    )

    let file_sink_path = prepare_file_sink_path(size_label)
    run_benchmark_case(
      "file_memory_sink_flush_write",
      size_label,
      bytes_len,
      true,
      fn() raise { bench_file_sink_flush(file_sink_path, bytes_len) },
    )

    let native_file_sink_path = prepare_native_file_sink_path(size_label)
    run_benchmark_case(
      "native_file_sink_write_flush_experimental",
      size_label,
      bytes_len,
      true,
      fn() raise {
        bench_native_file_sink_write_flush(native_file_sink_path, bytes_len)
      },
    )

    let native_buf_writer_path = prepare_native_buf_writer_path(size_label)
    run_benchmark_case(
      "native_buffered_writer_write_flush_experimental",
      size_label,
      bytes_len,
      true,
      fn() raise {
        bench_native_buf_writer_write_flush(native_buf_writer_path, bytes_len)
      },
    )
  }
}

///|
fn main {
  run_all_benchmarks() catch {
    err => {
      println("benchmark failed")
      println(err)
    }
  }
}
