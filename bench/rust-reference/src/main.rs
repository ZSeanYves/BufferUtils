use bytes::Bytes;
use std::hint::black_box;
use std::io::{self, BufReader, BufWriter, Read, Write};
use std::pin::Pin;
use std::task::{Context, Poll};
use std::time::Instant;
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};

const WARMUPS: usize = 10;
const SAMPLES: usize = 30;
const BATCHES: usize = 3;
const MIN_SAMPLE_US: f64 = 10_000.0;
const MAX_ITERATIONS: usize = 16_777_216;

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

fn measure<S, Setup, Run, Observe>(setup: &Setup, run: &Run, observe: &Observe) -> Stats
where
    Setup: Fn(usize) -> S,
    Run: Fn(&mut S, usize),
    Observe: Fn(&S, usize) -> Counters,
{
    let mut iterations = 1;
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
        if median_us >= MIN_SAMPLE_US || iterations >= MAX_ITERATIONS {
            return Stats {
                iterations,
                median_us,
                p95_us: percentile_95(&samples),
                counters,
            };
        }
        iterations = (iterations * 2).min(MAX_ITERATIONS);
    }
}

fn print_case<S, Setup, Run, Observe>(
    name: &str,
    size: usize,
    setup: Setup,
    run: Run,
    observe: Observe,
) where
    Setup: Fn(usize) -> S,
    Run: Fn(&mut S, usize),
    Observe: Fn(&S, usize) -> Counters,
{
    for batch in 1..=BATCHES {
        let stats = measure(&setup, &run, &observe);
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
    }
}

struct CyclingReader {
    data: Vec<u8>,
    position: usize,
    calls: u64,
}

impl CyclingReader {
    fn new(data: Vec<u8>) -> Self {
        Self {
            data,
            position: 0,
            calls: 0,
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
        Ok(count)
    }
}

struct CountingWriter {
    max_chunk: usize,
    calls: u64,
    bytes: u64,
    checksum: u64,
}

struct AsyncRepeatingReader {
    data: Vec<u8>,
    position: usize,
    remaining: usize,
    calls: u64,
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
        Poll::Ready(Ok(()))
    }
}

struct AsyncCountingWriter {
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
        for byte in source {
            self.checksum = (self.checksum + *byte as u64) % 65_521;
        }
        self.bytes += source.len() as u64;
        self.calls += 1;
        Poll::Ready(Ok(source.len()))
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
    fn new(max_chunk: usize) -> Self {
        Self {
            max_chunk,
            calls: 0,
            bytes: 0,
            checksum: 0,
        }
    }
}

impl Write for CountingWriter {
    fn write(&mut self, source: &[u8]) -> io::Result<usize> {
        let source = black_box(source);
        let count = source.len().min(self.max_chunk);
        for byte in &source[..count] {
            self.checksum = (self.checksum + *byte as u64) % 65_521;
        }
        self.calls += 1;
        self.bytes += count as u64;
        Ok(count)
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

fn buffer_cases(size: usize) {
    let payload = pattern_bytes(size);
    print_case(
        "buffer_shared_clone",
        size,
        |_| Bytes::copy_from_slice(&payload),
        |source, iterations| {
            for _ in 0..iterations {
                black_box(source.clone());
            }
        },
        |_, _| Counters::default(),
    );

    let payload = pattern_bytes(size);
    print_case(
        "buffer_shared_slice",
        size,
        |_| Bytes::copy_from_slice(&payload),
        |source, iterations| {
            for _ in 0..iterations {
                black_box(source.slice(..));
            }
        },
        |_, _| Counters::default(),
    );

    let payload = pattern_bytes(size);
    print_case(
        "buffer_shared_split",
        size,
        |_| Bytes::copy_from_slice(&payload),
        |source, iterations| {
            for _ in 0..iterations {
                let mut cursor = source.clone();
                black_box(cursor.split_to(size / 2));
            }
        },
        |_, _| Counters::default(),
    );
}

fn read_cases(size: usize) {
    let payload = pattern_bytes(size);
    print_case(
        "sync_raw_read",
        size,
        |_| (CyclingReader::new(payload.clone()), vec![0; size]),
        |state, iterations| {
            for _ in 0..iterations {
                state.0.read_exact(&mut state.1).unwrap();
            }
        },
        |state, iterations| Counters {
            copied_bytes: size as u64 * iterations as u64,
            underlying_calls: state.0.calls,
            syscalls: 0,
        },
    );

    let payload = pattern_bytes(size);
    print_case(
        "sync_bufreader_small",
        size,
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
        |state, iterations| Counters {
            copied_bytes: size as u64 * iterations as u64 * 2,
            underlying_calls: state.0.get_ref().calls,
            syscalls: 0,
        },
    );

    if size >= 8192 {
        let payload = pattern_bytes(size);
        print_case(
            "sync_bufreader_bypass",
            size,
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
            |state, iterations| Counters {
                copied_bytes: size as u64 * iterations as u64,
                underlying_calls: state.0.get_ref().calls,
                syscalls: 0,
            },
        );
    }
}

fn write_cases(size: usize) {
    let payload = pattern_bytes(size);
    print_case(
        "sync_raw_small_write",
        size,
        |_| CountingWriter::new(usize::MAX),
        |writer, iterations| {
            for _ in 0..iterations {
                for chunk in payload.chunks(32) {
                    writer.write_all(chunk).unwrap();
                }
            }
        },
        |writer, _| Counters {
            copied_bytes: writer.bytes,
            underlying_calls: writer.calls,
            syscalls: 0,
        },
    );

    let payload = pattern_bytes(size);
    print_case(
        "sync_bufwriter_small",
        size,
        |_| BufWriter::with_capacity(8192, CountingWriter::new(usize::MAX)),
        |writer, iterations| {
            for _ in 0..iterations {
                for chunk in payload.chunks(32) {
                    writer.write_all(chunk).unwrap();
                }
                writer.flush().unwrap();
            }
        },
        |writer, iterations| Counters {
            copied_bytes: size as u64 * iterations as u64 * 2,
            underlying_calls: writer.get_ref().calls,
            syscalls: 0,
        },
    );

    if size >= 8192 {
        let payload = pattern_bytes(size);
        print_case(
            "sync_bufwriter_bypass",
            size,
            |_| BufWriter::with_capacity(8192, CountingWriter::new(usize::MAX)),
            |writer, iterations| {
                for _ in 0..iterations {
                    writer.write_all(&payload).unwrap();
                    writer.flush().unwrap();
                }
            },
            |writer, iterations| Counters {
                copied_bytes: size as u64 * iterations as u64,
                underlying_calls: writer.get_ref().calls,
                syscalls: 0,
            },
        );
    }

    let payload = pattern_bytes(size);
    print_case(
        "sync_short_write_16",
        size,
        |_| CountingWriter::new(16),
        |writer, iterations| {
            for _ in 0..iterations {
                writer.write_all(&payload).unwrap();
            }
        },
        |writer, _| Counters {
            copied_bytes: writer.bytes,
            underlying_calls: writer.calls,
            syscalls: 0,
        },
    );
}

fn vectored_case() {
    let sources: [&[u8]; 2] = [b"vec", b"tored"];
    print_case(
        "sync_vectored_fallback",
        8,
        |_| CountingWriter::new(usize::MAX),
        |writer, iterations| {
            for _ in 0..iterations {
                for source in sources {
                    writer.write_all(source).unwrap();
                }
            }
        },
        |writer, _| Counters {
            copied_bytes: writer.bytes,
            underlying_calls: writer.calls,
            syscalls: 0,
        },
    );
}

fn async_copy_case(size: usize) {
    let payload = pattern_bytes(size);
    print_case(
        "async_copy",
        size,
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
                },
                writer: AsyncCountingWriter {
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
        |state, _| Counters {
            copied_bytes: state.writer.bytes * 2,
            underlying_calls: state.reader.calls + state.writer.calls,
            syscalls: 0,
        },
    );
}

fn main() {
    println!(
        "implementation,name,size,batch,iterations,median_us,p95_us,bytes,copied_bytes,underlying_calls,syscalls,median_mib_per_s"
    );
    vectored_case();
    for size in [1024, 1024 * 1024] {
        buffer_cases(size);
        read_cases(size);
        write_cases(size);
        async_copy_case(size);
    }
}
