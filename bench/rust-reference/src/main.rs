use bytes::Bytes;
use std::collections::HashMap;
use std::fs::{OpenOptions, create_dir_all};
use std::hint::black_box;
use std::io::{self, BufReader, BufWriter, IoSlice, Read, Write};
use std::pin::Pin;
use std::sync::OnceLock;
use std::task::{Context, Poll};
use std::time::Instant;
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};

const WARMUPS: usize = 10;
const SAMPLES: usize = 30;
const MIN_SAMPLE_US: f64 = 10_000.0;
const MAX_ITERATIONS: usize = 16_777_216;
const SHARED_ITERATIONS_PATH: &str = ".tmp/bufferutils-bench/shared-iterations.csv";

#[derive(Clone, Copy, Default)]
struct Counters {
    copied_bytes: u64,
    underlying_calls: u64,
    syscalls: u64,
}

struct Stats {
    iterations: usize,
    median_us: f64,
    p95_us: f64,
    counters: Counters,
    samples: Vec<f64>,
}

fn pattern_bytes(len: usize) -> Vec<u8> {
    (0..len).map(|index| (index % 251) as u8).collect()
}

fn elapsed_us(started: Instant) -> f64 {
    started.elapsed().as_secs_f64() * 1_000_000.0
}

fn percentile_95(samples: &[f64]) -> f64 {
    let index = ((samples.len() * 95).div_ceil(100)).saturating_sub(1);
    samples[index.min(samples.len() - 1)]
}

fn median(samples: &[f64]) -> f64 {
    let middle = samples.len() / 2;
    if samples.len().is_multiple_of(2) {
        (samples[middle - 1] + samples[middle]) / 2.0
    } else {
        samples[middle]
    }
}

fn forced_iterations(name: &str, size: usize) -> Option<usize> {
    if !std::path::Path::new(SHARED_ITERATIONS_PATH).is_file() {
        return None;
    }
    static ITERATIONS: OnceLock<HashMap<(String, usize), usize>> = OnceLock::new();
    let map = ITERATIONS.get_or_init(|| {
        let mut values = HashMap::new();
        if let Ok(contents) = std::fs::read_to_string(SHARED_ITERATIONS_PATH) {
            for line in contents.lines().skip(1) {
                let fields: Vec<_> = line.split(',').collect();
                if fields.len() == 3 {
                    if let (Ok(parsed_size), Ok(iterations)) =
                        (fields[1].parse::<usize>(), fields[2].parse::<usize>())
                    {
                        values.insert((fields[0].to_string(), parsed_size), iterations);
                    }
                }
            }
        }
        values
    });
    Some(
        map.get(&(name.to_string(), size))
            .copied()
            .unwrap_or_else(|| panic!("shared iteration map is missing {name}/{size}")),
    )
}

fn measure<S, Setup, Run, Observe>(
    setup: &Setup,
    run: &Run,
    observe: &Observe,
    forced: Option<usize>,
) -> Stats
where
    Setup: Fn(usize) -> S,
    Run: Fn(&mut S, usize),
    Observe: Fn(&S, usize) -> Counters,
{
    let mut iterations = forced.unwrap_or(1);
    if forced.is_none() {
        loop {
            let mut state = setup(iterations);
            let started = Instant::now();
            run(&mut state, iterations);
            let elapsed = elapsed_us(started);
            black_box(observe(&state, iterations));
            if elapsed >= MIN_SAMPLE_US || iterations >= MAX_ITERATIONS {
                break;
            }
            iterations = (iterations * 2).min(MAX_ITERATIONS);
        }
    }

    loop {
        for _ in 0..WARMUPS {
            let mut state = setup(iterations);
            run(&mut state, iterations);
            black_box(observe(&state, iterations));
        }
        let mut samples = Vec::with_capacity(SAMPLES);
        let mut counters = Counters::default();
        for _ in 0..SAMPLES {
            let mut state = setup(iterations);
            let started = Instant::now();
            run(&mut state, iterations);
            samples.push(elapsed_us(started));
            counters = observe(&state, iterations);
            black_box(counters.copied_bytes);
        }
        samples.sort_by(f64::total_cmp);
        let median_us = median(&samples);
        if forced.is_some() || median_us >= MIN_SAMPLE_US || iterations >= MAX_ITERATIONS {
            return Stats {
                iterations,
                median_us,
                p95_us: percentile_95(&samples),
                counters,
                samples,
            };
        }
        iterations = (iterations * 2).min(MAX_ITERATIONS);
    }
}

fn print_case<S, Setup, Run, Observe>(
    name: &str,
    size: usize,
    batch: usize,
    setup: Setup,
    run: Run,
    observe: Observe,
) where
    Setup: Fn(usize) -> S,
    Run: Fn(&mut S, usize),
    Observe: Fn(&S, usize) -> Counters,
{
    let stats = measure(&setup, &run, &observe, forced_iterations(name, size));
    let bytes = size as u64 * stats.iterations as u64;
    let throughput = bytes as f64 / 1_048_576.0 / (stats.median_us / 1_000_000.0);
    println!(
        "rust,{name},{size},{batch},{},{},{},{bytes},{},{},{},{throughput}",
        stats.iterations,
        stats.median_us,
        stats.p95_us,
        stats.counters.copied_bytes,
        stats.counters.underlying_calls,
        stats.counters.syscalls,
    );
    append_auxiliary(name, size, batch, &stats);
}

fn copy_scope(name: &str) -> &'static str {
    if name.starts_with("buffer_") {
        "library-cow"
    } else {
        "fixture-observed"
    }
}

fn append_auxiliary(name: &str, size: usize, batch: usize, stats: &Stats) {
    let raw_path = format!(".tmp/bufferutils-bench/rust-raw-batch-{batch}.csv");
    let evidence_path = format!(".tmp/bufferutils-bench/rust-copy-evidence-batch-{batch}.csv");
    let mut raw = OpenOptions::new().append(true).open(raw_path).unwrap();
    for (index, elapsed) in stats.samples.iter().enumerate() {
        writeln!(
            raw,
            "rust,{name},{size},{batch},{},{},{elapsed}",
            index + 1,
            stats.iterations,
        )
        .unwrap();
    }
    let mut evidence = OpenOptions::new().append(true).open(evidence_path).unwrap();
    writeln!(
        evidence,
        "rust,{name},{size},{batch},{},{},{},{},{}",
        stats.iterations,
        stats.counters.copied_bytes,
        stats.counters.underlying_calls,
        stats.counters.syscalls,
        copy_scope(name),
    )
    .unwrap();
}

struct CyclingReader {
    data: Vec<u8>,
    position: usize,
    calls: u64,
    bytes: u64,
}

impl CyclingReader {
    fn new(data: Vec<u8>) -> Self {
        Self {
            data,
            position: 0,
            calls: 0,
            bytes: 0,
        }
    }
}

impl Read for CyclingReader {
    fn read(&mut self, destination: &mut [u8]) -> io::Result<usize> {
        let destination = black_box(destination);
        if destination.is_empty() {
            return Ok(0);
        }
        if self.position == self.data.len() {
            self.position = 0;
        }
        let count = destination.len().min(self.data.len() - self.position);
        destination[..count].copy_from_slice(&self.data[self.position..self.position + count]);
        self.position += count;
        self.calls += 1;
        self.bytes += count as u64;
        Ok(count)
    }
}

struct CountingWriter {
    max_chunk: usize,
    scratch: Vec<u8>,
    calls: u64,
    bytes: u64,
    checksum: u64,
}

struct AsyncRepeatingReader {
    data: Vec<u8>,
    position: usize,
    remaining: usize,
    calls: u64,
    bytes: u64,
}

impl AsyncRead for AsyncRepeatingReader {
    fn poll_read(
        mut self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        destination: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        if self.remaining == 0 || destination.remaining() == 0 {
            return Poll::Ready(Ok(()));
        }
        if self.position == self.data.len() {
            self.position = 0;
        }
        let count = destination
            .remaining()
            .min(self.data.len() - self.position)
            .min(self.remaining);
        destination.put_slice(&self.data[self.position..self.position + count]);
        self.position += count;
        self.remaining -= count;
        self.calls += 1;
        self.bytes += count as u64;
        Poll::Ready(Ok(()))
    }
}

struct AsyncCountingWriter {
    scratch: Vec<u8>,
    bytes: u64,
    calls: u64,
    checksum: u64,
}

impl AsyncWrite for AsyncCountingWriter {
    fn poll_write(
        mut self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        source: &[u8],
    ) -> Poll<io::Result<usize>> {
        let source = black_box(source);
        let count = source.len().min(self.scratch.len());
        self.scratch[..count].copy_from_slice(&source[..count]);
        black_box(&self.scratch[..count]);
        if count > 0 {
            self.checksum = (self.checksum
                + self.scratch[0] as u64
                + self.scratch[count - 1] as u64
                + count as u64)
                % 65_521;
        }
        self.bytes += count as u64;
        self.calls += 1;
        Poll::Ready(Ok(count))
    }

    fn poll_flush(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }

    fn poll_shutdown(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }
}

struct AsyncCopyState {
    runtime: tokio::runtime::Runtime,
    reader: AsyncRepeatingReader,
    writer: AsyncCountingWriter,
}

impl CountingWriter {
    fn new(max_chunk: usize, scratch_capacity: usize) -> Self {
        Self {
            max_chunk,
            scratch: vec![0; scratch_capacity],
            calls: 0,
            bytes: 0,
            checksum: 0,
        }
    }
}

impl Write for CountingWriter {
    fn write(&mut self, source: &[u8]) -> io::Result<usize> {
        let source = black_box(source);
        let count = source.len().min(self.max_chunk).min(self.scratch.len());
        self.scratch[..count].copy_from_slice(&source[..count]);
        black_box(&self.scratch[..count]);
        if count > 0 {
            self.checksum = (self.checksum
                + self.scratch[0] as u64
                + self.scratch[count - 1] as u64
                + count as u64)
                % 65_521;
        }
        self.calls += 1;
        self.bytes += count as u64;
        Ok(count)
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }

    fn write_vectored(&mut self, sources: &[IoSlice<'_>]) -> io::Result<usize> {
        let limit = self.max_chunk.min(self.scratch.len());
        let mut accepted = 0;
        for source in sources {
            let count = source.len().min(limit - accepted);
            self.scratch[accepted..accepted + count].copy_from_slice(&source[..count]);
            accepted += count;
            if accepted == limit {
                break;
            }
        }
        black_box(&self.scratch[..accepted]);
        if accepted > 0 {
            self.checksum = (self.checksum
                + self.scratch[0] as u64
                + self.scratch[accepted - 1] as u64
                + accepted as u64)
                % 65_521;
        }
        self.calls += 1;
        self.bytes += accepted as u64;
        Ok(accepted)
    }
}

fn buffer_cases(size: usize, batch: usize) {
    let payload = pattern_bytes(size);
    print_case(
        "buffer_shared_clone",
        size,
        batch,
        |_| (Bytes::copy_from_slice(&payload), Bytes::new()),
        |state, iterations| {
            for _ in 0..iterations {
                state.1 = state.0.clone();
                black_box(&state.1);
            }
        },
        |state, _| {
            black_box(state.1.len());
            Counters::default()
        },
    );

    let payload = pattern_bytes(size);
    print_case(
        "buffer_shared_slice",
        size,
        batch,
        |_| (Bytes::copy_from_slice(&payload), Bytes::new()),
        |state, iterations| {
            for _ in 0..iterations {
                state.1 = state.0.slice(0..state.0.len());
                black_box(&state.1);
            }
        },
        |state, _| {
            black_box(state.1.len());
            Counters::default()
        },
    );

    let payload = pattern_bytes(size);
    print_case(
        "buffer_shared_split",
        size,
        batch,
        |_| (Bytes::copy_from_slice(&payload), Bytes::new()),
        |state, iterations| {
            for _ in 0..iterations {
                let mut cursor = state.0.clone();
                state.1 = cursor.split_to(size / 2);
                black_box(&state.1);
            }
        },
        |state, _| {
            black_box(state.1.len());
            Counters::default()
        },
    );
}

fn read_cases(size: usize, batch: usize) {
    let payload = pattern_bytes(size);
    print_case(
        "sync_raw_read",
        size,
        batch,
        |_| (CyclingReader::new(payload.clone()), vec![0; size]),
        |state, iterations| {
            for _ in 0..iterations {
                state.0.read_exact(&mut state.1).unwrap();
            }
        },
        |state, _| Counters {
            copied_bytes: state.0.bytes,
            underlying_calls: state.0.calls,
            syscalls: 0,
        },
    );

    let payload = pattern_bytes(size);
    print_case(
        "sync_bufreader_small",
        size,
        batch,
        |_| {
            (
                BufReader::with_capacity(8192, CyclingReader::new(payload.clone())),
                vec![0; size],
            )
        },
        |state, iterations| {
            for _ in 0..iterations {
                for chunk in state.1.chunks_mut(32) {
                    state.0.read_exact(chunk).unwrap();
                }
            }
        },
        |state, _| Counters {
            copied_bytes: state.0.get_ref().bytes,
            underlying_calls: state.0.get_ref().calls,
            syscalls: 0,
        },
    );

    if size >= 8192 {
        let payload = pattern_bytes(size);
        print_case(
            "sync_bufreader_bypass",
            size,
            batch,
            |_| {
                (
                    BufReader::with_capacity(8192, CyclingReader::new(payload.clone())),
                    vec![0; size],
                )
            },
            |state, iterations| {
                for _ in 0..iterations {
                    state.0.read_exact(&mut state.1).unwrap();
                }
            },
            |state, _| Counters {
                copied_bytes: state.0.get_ref().bytes,
                underlying_calls: state.0.get_ref().calls,
                syscalls: 0,
            },
        );
    }
}

fn write_cases(size: usize, batch: usize) {
    let payload = pattern_bytes(size);
    print_case(
        "sync_raw_small_write",
        size,
        batch,
        |_| CountingWriter::new(usize::MAX, 32),
        |writer, iterations| {
            for _ in 0..iterations {
                for chunk in payload.chunks(32) {
                    assert_eq!(writer.write(chunk).unwrap(), chunk.len());
                }
            }
        },
        |writer, _| {
            black_box(writer.checksum);
            Counters {
                copied_bytes: writer.bytes,
                underlying_calls: writer.calls,
                syscalls: 0,
            }
        },
    );

    let payload = pattern_bytes(size);
    print_case(
        "sync_bufwriter_small",
        size,
        batch,
        |_| BufWriter::with_capacity(8192, CountingWriter::new(usize::MAX, 8192)),
        |writer, iterations| {
            for _ in 0..iterations {
                for chunk in payload.chunks(32) {
                    assert_eq!(writer.write(chunk).unwrap(), chunk.len());
                }
                writer.flush().unwrap();
            }
        },
        |writer, _| {
            black_box(writer.get_ref().checksum);
            Counters {
                copied_bytes: writer.get_ref().bytes,
                underlying_calls: writer.get_ref().calls,
                syscalls: 0,
            }
        },
    );

    if size >= 8192 {
        let payload = pattern_bytes(size);
        print_case(
            "sync_bufwriter_bypass",
            size,
            batch,
            |_| BufWriter::with_capacity(8192, CountingWriter::new(usize::MAX, size)),
            |writer, iterations| {
                for _ in 0..iterations {
                    writer.write_all(&payload).unwrap();
                    writer.flush().unwrap();
                }
            },
            |writer, _| {
                black_box(writer.get_ref().checksum);
                Counters {
                    copied_bytes: writer.get_ref().bytes,
                    underlying_calls: writer.get_ref().calls,
                    syscalls: 0,
                }
            },
        );
    }

    if size == 1024 {
        let payload = pattern_bytes(size);
        print_case(
            "sync_short_write_16",
            size,
            batch,
            |_| CountingWriter::new(16, 16),
            |writer, iterations| {
                for _ in 0..iterations {
                    writer.write_all(&payload).unwrap();
                }
            },
            |writer, _| {
                black_box(writer.checksum);
                Counters {
                    copied_bytes: writer.bytes,
                    underlying_calls: writer.calls,
                    syscalls: 0,
                }
            },
        );
    }
}

fn vectored_case(batch: usize) {
    let sources: [&[u8]; 2] = [b"vec", b"tored"];
    print_case(
        "sync_vectored_fallback",
        8,
        batch,
        |_| CountingWriter::new(usize::MAX, 8),
        |writer, iterations| {
            for _ in 0..iterations {
                for source in sources {
                    let adapted = source.to_vec();
                    writer.write_all(&adapted).unwrap();
                }
            }
        },
        |writer, _| {
            black_box(writer.checksum);
            Counters {
                copied_bytes: writer.bytes,
                underlying_calls: writer.calls,
                syscalls: 0,
            }
        },
    );

    let first = b"vec";
    let second = b"tored";
    let sources = [IoSlice::new(first), IoSlice::new(second)];
    print_case(
        "sync_vectored_bulk",
        8,
        batch,
        |_| CountingWriter::new(usize::MAX, 8),
        |writer, iterations| {
            for _ in 0..iterations {
                assert_eq!(writer.write_vectored(&sources).unwrap(), 8);
            }
        },
        |writer, _| {
            black_box(writer.checksum);
            Counters {
                copied_bytes: writer.bytes,
                underlying_calls: writer.calls,
                syscalls: 0,
            }
        },
    );
}

fn async_copy_case(size: usize, batch: usize) {
    let payload = pattern_bytes(size);
    print_case(
        "async_copy",
        size,
        batch,
        |iterations| {
            let total = size * iterations;
            AsyncCopyState {
                runtime: tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                    .unwrap(),
                reader: AsyncRepeatingReader {
                    data: payload.clone(),
                    position: 0,
                    remaining: total,
                    calls: 0,
                    bytes: 0,
                },
                writer: AsyncCountingWriter {
                    scratch: vec![0; payload.len()],
                    bytes: 0,
                    calls: 0,
                    checksum: 0,
                },
            }
        },
        |state, _| {
            let copied = state
                .runtime
                .block_on(tokio::io::copy(&mut state.reader, &mut state.writer))
                .unwrap();
            assert_eq!(copied, state.writer.bytes);
        },
        |state, _| {
            black_box(state.writer.checksum);
            Counters {
                copied_bytes: state.reader.bytes + state.writer.bytes,
                underlying_calls: state.reader.calls + state.writer.calls,
                syscalls: 0,
            }
        },
    );
}

fn main() {
    let arguments = std::env::args().collect::<Vec<_>>();
    let batch = arguments
        .get(1)
        .and_then(|value| value.parse::<usize>().ok())
        .filter(|value| (1..=3).contains(value))
        .expect("usage: bufferutils-rust-reference BATCH [CASE]");
    if arguments.len() > 3 {
        panic!("usage: bufferutils-rust-reference BATCH [CASE]");
    }
    let selected = arguments
        .get(2)
        .map(String::as_str)
        .filter(|value| *value != "__all__");
    create_dir_all(".tmp/bufferutils-bench").unwrap();
    std::fs::write(
        format!(".tmp/bufferutils-bench/rust-raw-batch-{batch}.csv"),
        "implementation,name,size,batch,sample,iterations,elapsed_us\n",
    )
    .unwrap();
    std::fs::write(
        format!(".tmp/bufferutils-bench/rust-copy-evidence-batch-{batch}.csv"),
        "implementation,name,size,batch,iterations,observed_copied_bytes,underlying_calls,syscalls,copy_scope\n",
    )
    .unwrap();
    println!(
        "implementation,name,size,batch,iterations,median_us,p95_us,bytes,copied_bytes,underlying_calls,syscalls,median_mib_per_s"
    );
    if selected.is_none()
        || selected == Some("sync_vectored_fallback")
        || selected == Some("sync_vectored_bulk")
    {
        vectored_case(batch);
    }
    for size in [1024, 1024 * 1024] {
        if selected.is_none() || selected.is_some_and(|name| name.starts_with("buffer_")) {
            buffer_cases(size, batch);
        }
        if selected.is_none()
            || selected.is_some_and(|name| name.starts_with("sync_") && name.contains("read"))
        {
            read_cases(size, batch);
        }
        if selected.is_none()
            || selected.is_some_and(|name| {
                name.starts_with("sync_") && (name.contains("write") || name.contains("vectored"))
            })
        {
            write_cases(size, batch);
        }
        if selected.is_none() || selected == Some("async_copy") {
            async_copy_case(size, batch);
        }
    }
}
