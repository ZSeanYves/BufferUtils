# BufferUtils 0.40 Performance Investigation

This report separates measured library performance from benchmark-fixture,
runtime, compiler, operating-system, and shared-runner effects. Passing the
regression gate means only that a corrected workload did not regress from its
committed baseline. It does not mean that BufferUtils equals Rust.

## Evidence checkpoint

GitHub Actions run
[`30924479149`](https://github.com/ZSeanYves/BufferUtils/actions/runs/30924479149)
is the authoritative corrected-fixture checkpoint for commit `6b2cdc5`. It
passed all platform, sanitizer, coverage, contract, benchmark-structure, and
noise gates. It used the MoonBit nightly available at the time,
Rust 1.97.1, `bytes` 1.12.1, and Tokio 1.53.1 on an Ubuntu 24.04 AMD EPYC 7763
hosted runner.

| Workload | MoonBit/Rust median ratio | Interpretation |
| --- | ---: | --- |
| `SharedBytes` clone/slice/split | 3.44 / 3.84-3.86 / 3.65-3.70 | O(1), but each returned handle still allocates |
| raw read, 1 KiB / 1 MiB | 1.37 / 0.90 | bulk copy is competitive once call cost is amortized |
| buffered read, 1 KiB / 1 MiB | 1.94 / 0.71 | resident bulk copy wins at scale; small calls do not |
| buffered bypass read/write | 0.93 / 0.92 | bypass paths are competitive |
| buffered write, 1 KiB / 1 MiB | 2.69 / 2.49 | checked blit and call boundaries remain |
| raw small write | 2.55-2.57 | fixture and trait boundary are call-dominated |
| short write | 2.43 | progress checks and repeated result boundaries dominate |
| vectored fallback / bulk | 1.81 / 7.46 | equal counters, but descriptor iteration and dispatch remain expensive |
| async copy, 1 KiB / 1 MiB | 10.60 / 2.25 | scheduler/continuation cost dominates small transfers |

These values are medians of the three per-batch, per-iteration ratios. They are
the committed regression baseline, not a parity claim. Any row whose median is
already above 1.05 necessarily fails the parity target regardless of its
confidence interval. The current evidence therefore proves that BufferUtils
0.40 has not reached overall Rust performance parity.

Independent-process peak RSS was about 29,000 KiB for ordinary synchronous
cases and 8,920 KiB for async copy. Growth reached 55,624 KiB and the COW stress
case reached 368,200 KiB. The high COW figure is workload-specific retained
state, not the steady-state footprint of a single buffer operation, and remains
visible rather than being normalized away.

## Confirmed root causes

### Per-byte library loops

The original reader, writer, mutable-buffer, memory-reader, typed-helper, and
async delimiter paths performed MoonBit-level byte loops. Those paths now use
`FixedArray.blit_to`, `FixedArray.blit_from_bytes`,
`blit_from_bytesview`, `FixedArray.fill`, or one checked direct typed operation.
Short-read, short-write, EOF, `Interrupted`, `WriteZero`, alias, COW, and
cancellation tests remain the correctness guard for these replacements.

### SharedBytes handle representation

Inspection of the generated release C shows `moonbit_malloc` for each returned
`SharedBytes` handle from clone/slice/split. The mutable read cursor prevents
the current compiler from representing the type as a value: an attempted
`#valtype` build was rejected with compiler diagnostic 4173, "Value type is not
allowed for struct with mutable field." Rust `Bytes` keeps its small handle in
the caller and increments shared backing metadata without allocating a second
GC object for every range operation. Full-range slice and empty-range paths can
be shortened, but they cannot erase this representation difference.

Closing this gap requires either MoonBit compiler support for an appropriate
value representation or a breaking API split between immutable shared ranges
and a separate mutable cursor. Benchmark-specific pooling or global mutable
handles would change semantics and is rejected.

### Call and trait boundary cost

Generated native code retains result wrappers, dynamic trait calls, reference
count operations, and range checks at public read/write boundaries. Rust
monomorphizes and inlines the corresponding generic fixture calls. This is most
visible in 1 KiB raw writes, short writes, and small buffered writes, where the
same payload is divided into many calls. Bulk and bypass rows demonstrate that
memory bandwidth is not the main remaining cause for those cases.

A future breaking trait change is justified only if profiler evidence shows
that the default boundary remains dominant after the bulk implementation. The
preferred options are a fixed-array bulk primitive in the core contract or
specialized concrete adapters, with ArrayView kept as an explicit copy
boundary. Adding benchmark-only public APIs is not acceptable.

Callgrind confirms the boundary counts on the final source. The selected
`SharedBytes::slice` profile invoked the slice function and allocator 688,126
times. The small buffered-write profile invoked `blit_from_bytes` 2,058,335
times while issuing only 26,751 writes to the sink. The async-copy profile
entered the copy continuation and `write_all` state machine 42,879 times. The
bulk-vectored fixture entered its write implementation 344,063 times. These
profiles also include benchmark-case construction, so instruction percentages
for the complete process are not treated as hot-path percentages.

### COW capacity amplification

Changing the in-memory writers to bulk `BytesMut` storage exposed a latent
capacity bug in the fixed-seed state model. Calling `freeze` and then appending
marked storage shared; `reserve` detached it but doubled capacity even when the
existing visible capacity was sufficient. Repeated snapshot/write cycles grew
8-byte storage to the backend array limit and failed with an allocation error.

The detach path now preserves current visible capacity when it can satisfy the
write and applies geometric growth only when capacity is actually exhausted. A
cross-backend regression test repeatedly freezes and appends while asserting
that capacity remains 8 and earlier snapshots remain unchanged. This is a
library memory fix, not an RSS-report adjustment.

### Async scheduler and await cost

Async throughput is reported separately from control operations. The control
sidecar measures ready reads, one-yield pending reads, cancellation, 16-byte
short progress, shutdown failure, 64 KiB lines, and 64 KiB no-delimiter
segments followed by EOF. It records actual operations, source bytes, source
copies, await points, and failures. The structural checker rejects a missing
progress step or invented copy count. Runtime scheduling cost remains part of
the async operation and is not relabeled as buffer-copy cost.

## Causes isolated or excluded

- Build time and build-process RSS are excluded by executing prebuilt binaries.
- MoonBit and Rust fixtures perform real bulk copies with the same payload,
  chunk, buffer size, operation order, warmups, samples, and batches.
- Full-range Rust-only `Bytes::slice` shortcuts are not used by the comparison.
- ArrayView fallback and bulk vectored semantics are independent cases.
- Synthetic memory cases report zero syscalls; native file and TCP diagnostics
  cannot explain their ratios.
- Disk cache, mmap, TCP, FFI, and native syscall results remain diagnostic where
  no structurally identical Rust workload exists.
- CPU, cgroup, toolchain, raw samples, MAD, CV, p95/median, and per-process peak
  RSS are uploaded. A noisy batch is rerun or fails; its baseline is not widened.
- Internal copies that cannot be observed without changing the release path are
  marked by scope. Only source, fixture, COW, and native counters actually
  observed by the benchmark are reported.

## Acceptance rule

Rust parity requires at least two of three batches to have a 95% confidence
upper bound no greater than 1.05 with matching structure counters. The ideal
target is a median ratio below 1.0 in at least two batches and in the merged
result. The existing 15% baseline gate detects regressions only. These are two
different decisions and reports must preserve that distinction.

No tag, package publication, or GitHub release is part of this work. Final
acceptance remains a manual review after source, sanitizer, coverage,
performance, profiler, and platform CI evidence is available.
