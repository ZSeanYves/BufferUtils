///|
fn repeated_bytes(len : Int, value : Byte) -> Array[Byte] {
  let data : Array[Byte] = []
  data.resize(len, value)
  data
}

///|
extern "C" fn native_debug_live_mmap_owner_count() -> Int = "bufferutils_native_mmap_live_owner_count"

///|
extern "C" fn native_debug_live_mmap_view_count() -> Int = "bufferutils_native_mmap_live_view_count"

///|
test "native mmap view rejects empty path" {
  let result = try? new_mmap_file_view("")
  assert_eq(result is Err(_), true)
}

///|
test "native mmap view reports missing file" {
  let result = try? new_mmap_file_view(
    ".tmp/bufferutils-native-tests/mmap-does-not-exist.bin",
  )
  assert_eq(result is Err(_), true)
}

///|
test "native mmap view supports empty files with zero length" {
  let path = native_test_path("native-mmap-empty.bin")
  write_fixture(path, [])
  let view = new_mmap_file_view(path)
  assert_eq(view.len(), 0)
  assert_eq(view.copy_range(0, 0), [])
  assert_eq(view.count_byte(0), 0)
  assert_eq(view.index_of([]), 0)
  assert_eq(view.index_of([1]), -1)
  assert_eq(view.equals([]), true)
  assert_eq(view.equals([1]), false)
  assert_eq(view.starts_with([]), true)
  assert_eq(view.starts_with([1]), false)
  assert_eq(view.crc32(), 0)
  let first = view.checksum_u64()
  let second = view.checksum_u64()
  assert_eq(first, second)
  assert_eq(view.find_byte(0), -1)
  let copied_path = native_test_path("native-mmap-empty-copy.bin")
  view.copy_to_file(copied_path)
  assert_eq(read_fixture(copied_path), [])
  let byte_result = try? view.read_byte_at(0)
  assert_eq(byte_result is Err(_), true)
  view.close()
}

///|
test "native mmap view reads small file without copying whole payload into MoonBit" {
  let path = native_test_path("native-mmap-small.bin")
  write_fixture(path, [1, 2, 3, 4, 5])
  let view = new_mmap_file_view(path)
  assert_eq(view.len(), 5)
  assert_eq(view.owner_ref_count(), 1)
  assert_eq(view.read_byte_at(0), 1)
  assert_eq(view.read_byte_at(4), 5)
  assert_eq(view.copy_range(0, 0), [])
  assert_eq(view.copy_range(0, 5), [1, 2, 3, 4, 5])
  assert_eq(view.copy_range(5, 0), [])
  assert_eq(view.copy_range(1, 3), [2, 3, 4])
  assert_eq(view.count_byte(1), 1)
  assert_eq(view.count_byte(3), 1)
  assert_eq(view.count_byte(9), 0)
  assert_eq(view.index_of([]), 0)
  assert_eq(view.index_of([1]), 0)
  assert_eq(view.index_of([2, 3]), 1)
  assert_eq(view.index_of([4, 5]), 3)
  assert_eq(view.index_of([1, 2, 3, 4, 5]), 0)
  assert_eq(view.index_of([1, 2, 3, 4, 5, 6]), -1)
  assert_eq(view.index_of([8]), -1)
  assert_eq(view.equals([1, 2, 3, 4, 5]), true)
  assert_eq(view.equals([1, 2, 3, 4]), false)
  assert_eq(view.equals([1, 2, 3, 4, 6]), false)
  assert_eq(view.find_byte(1), 0)
  assert_eq(view.find_byte(3), 2)
  assert_eq(view.find_byte(5), 4)
  assert_eq(view.find_byte(4), 3)
  assert_eq(view.find_byte(9), -1)
  assert_eq(view.starts_with([]), true)
  assert_eq(view.starts_with([1, 2, 3]), true)
  assert_eq(view.starts_with([1, 2, 3, 4, 5]), true)
  assert_eq(view.starts_with([1, 2, 3, 4, 5, 6]), false)
  assert_eq(view.starts_with([1, 3]), false)
  assert_eq(view.crc32(), 0x470B99F4)
  let first = view.checksum_u64()
  let second = view.checksum_u64()
  assert_eq(first, second)
  let copied_path = native_test_path("native-mmap-small-copy.bin")
  view.copy_to_file(copied_path)
  assert_eq(read_fixture(copied_path), [1, 2, 3, 4, 5])
  view.close()
}

///|
test "native mmap view slice handles share owners safely" {
  let path = native_test_path("native-mmap-slice-owner.bin")
  write_fixture(path, [1, 2, 3, 4, 5])
  let root = new_mmap_file_view(path)
  assert_eq(root.owner_ref_count(), 1)

  let empty = root.slice_handle(0, 0)
  assert_eq(empty.len(), 0)
  assert_eq(root.owner_ref_count(), 2)
  assert_eq(empty.owner_ref_count(), 2)
  assert_eq(empty.copy_range(0, 0), [])
  empty.close()
  assert_eq(root.owner_ref_count(), 1)

  let child = root.slice_handle(1, 4)
  assert_eq(root.owner_ref_count(), 2)
  assert_eq(child.owner_ref_count(), 2)
  assert_eq(child.copy_range(0, 4), [2, 3, 4, 5])

  root.close()
  assert_eq(root.is_closed(), true)
  assert_eq(child.is_closed(), false)
  assert_eq(child.owner_ref_count(), 1)
  assert_eq(child.read_byte_at(0), 2)
  assert_eq((try? root.slice_handle(0, 0)) is Err(_), true)

  child.close()
  child.close()
}

///|
test "native mmap view final close releases owner and view entries" {
  let base_owner_count = native_debug_live_mmap_owner_count()
  let base_view_count = native_debug_live_mmap_view_count()

  let path = native_test_path("native-mmap-release-debug.bin")
  write_fixture(path, [1, 2, 3, 4])
  let root = new_mmap_file_view(path)
  assert_eq(native_debug_live_mmap_owner_count(), base_owner_count + 1)
  assert_eq(native_debug_live_mmap_view_count(), base_view_count + 1)

  let child = root.slice_handle(1, 2)
  assert_eq(native_debug_live_mmap_owner_count(), base_owner_count + 1)
  assert_eq(native_debug_live_mmap_view_count(), base_view_count + 2)

  root.close()
  assert_eq(native_debug_live_mmap_owner_count(), base_owner_count + 1)
  assert_eq(native_debug_live_mmap_view_count(), base_view_count + 1)

  child.close()
  assert_eq(native_debug_live_mmap_owner_count(), base_owner_count)
  assert_eq(native_debug_live_mmap_view_count(), base_view_count)

  child.close()
  assert_eq(native_debug_live_mmap_owner_count(), base_owner_count)
  assert_eq(native_debug_live_mmap_view_count(), base_view_count)
}

///|
test "native mmap view validates index and range bounds" {
  let path = native_test_path("native-mmap-bounds.bin")
  write_fixture(path, [10, 11, 12])
  let view = new_mmap_file_view(path)
  let negative_index = try? view.read_byte_at(-1)
  let past_end_index = try? view.read_byte_at(3)
  let negative_copy = try? view.copy_range(-1, 1)
  let negative_copy_len = try? view.copy_range(0, -1)
  let past_end_copy = try? view.copy_range(2, 2)
  let zero_past_end_copy = try? view.copy_range(4, 0)
  assert_eq(negative_index is Err(_), true)
  assert_eq(past_end_index is Err(_), true)
  assert_eq(negative_copy is Err(_), true)
  assert_eq(negative_copy_len is Err(_), true)
  assert_eq(past_end_copy is Err(_), true)
  assert_eq(zero_past_end_copy is Err(_), true)
  view.close()
}

///|
test "native mmap view slice handle validates bounds and child range" {
  let path = native_test_path("native-mmap-slice-bounds.bin")
  write_fixture(path, [10, 11, 12, 13, 14])
  let root = new_mmap_file_view(path)

  let full = root.slice_handle(0, root.len())
  assert_eq(full.copy_range(0, full.len()), [10, 11, 12, 13, 14])

  let tail = root.slice_handle(1, root.len() - 1)
  assert_eq(tail.copy_range(0, tail.len()), [11, 12, 13, 14])

  let at_end = root.slice_handle(root.len(), 0)
  assert_eq(at_end.len(), 0)
  assert_eq(at_end.copy_range(0, 0), [])

  let child = root.slice_handle(1, 3)
  assert_eq(child.len(), 3)
  assert_eq(child.read_byte_at(0), 11)
  assert_eq(child.read_byte_at(2), 13)
  assert_eq(child.copy_range(0, 3), [11, 12, 13])
  assert_eq(child.copy_range(2, 1), [13])
  assert_eq(child.copy_range(3, 0), [])
  assert_eq(child.find_byte(11), 0)
  assert_eq(child.find_byte(14), -1)
  assert_eq(child.count_byte(12), 1)
  assert_eq(child.index_of([12, 13]), 1)
  assert_eq(child.equals([11, 12, 13]), true)
  assert_eq(child.starts_with([11, 12]), true)

  assert_eq((try? root.slice_handle(root.len(), 1)) is Err(_), true)
  assert_eq((try? root.slice_handle(-1, 1)) is Err(_), true)
  assert_eq((try? root.slice_handle(0, -1)) is Err(_), true)
  assert_eq((try? child.read_byte_at(3)) is Err(_), true)
  assert_eq((try? child.copy_range(3, 1)) is Err(_), true)

  child.close()
  at_end.close()
  tail.close()
  full.close()
  root.close()
}

///|
test "native mmap view close is idempotent and rejects later access" {
  let path = native_test_path("native-mmap-close.bin")
  write_fixture(path, [9, 8, 7])
  let view = new_mmap_file_view(path)
  view.close()
  view.close()
  assert_eq(view.is_closed(), true)
  let read_result = try? view.read_byte_at(0)
  let copy_result = try? view.copy_range(0, 1)
  let find_result = try? view.find_byte(9)
  let count_result = try? view.count_byte(9)
  let index_result = try? view.index_of([9])
  let equals_result = try? view.equals([9, 8, 7])
  let crc32_result = try? view.crc32()
  let checksum_result = try? view.checksum_u64()
  let starts_with_result = try? view.starts_with([9])
  let ref_count_result = try? view.owner_ref_count()
  let slice_result = try? view.slice_handle(0, 0)
  let copy_to_file_result = try? view.copy_to_file(
    native_test_path("native-mmap-close-copy.bin"),
  )
  assert_eq(read_result is Err(_), true)
  assert_eq(copy_result is Err(_), true)
  assert_eq(find_result is Err(_), true)
  assert_eq(count_result is Err(_), true)
  assert_eq(index_result is Err(_), true)
  assert_eq(equals_result is Err(_), true)
  assert_eq(crc32_result is Err(_), true)
  assert_eq(checksum_result is Err(_), true)
  assert_eq(starts_with_result is Err(_), true)
  assert_eq(ref_count_result is Err(_), true)
  assert_eq(slice_result is Err(_), true)
  assert_eq(copy_to_file_result is Err(_), true)
}

///|
test "native mmap view close after failed operation remains safe" {
  let path = native_test_path("native-mmap-close-after-failed-op.bin")
  write_fixture(path, [1, 2, 3])
  let view = new_mmap_file_view(path)
  let failed = try? view.read_byte_at(3)
  assert_eq(failed is Err(_), true)
  view.close()
  assert_eq(view.is_closed(), true)
  view.close()
}

///|
test "native mmap views over different files close independently" {
  let path_a = native_test_path("native-mmap-independent-a.bin")
  let path_b = native_test_path("native-mmap-independent-b.bin")
  write_fixture(path_a, [1, 2, 3])
  write_fixture(path_b, [9, 8, 7])
  let view_a = new_mmap_file_view(path_a)
  let view_b = new_mmap_file_view(path_b)
  view_a.close()
  assert_eq(view_a.is_closed(), true)
  assert_eq(view_b.read_byte_at(0), 9)
  view_b.close()
}

///|
test "native mmap child views close independently" {
  let path = native_test_path("native-mmap-independent-children.bin")
  write_fixture(path, [1, 2, 3, 4, 5, 6])
  let root = new_mmap_file_view(path)
  let child_a = root.slice_handle(0, 2)
  let child_b = root.slice_handle(2, 4)
  assert_eq(root.owner_ref_count(), 3)

  child_a.close()
  child_a.close()
  assert_eq(root.owner_ref_count(), 2)
  assert_eq(root.read_byte_at(0), 1)
  assert_eq(child_b.copy_range(0, 4), [3, 4, 5, 6])

  root.close()
  assert_eq(child_b.owner_ref_count(), 1)
  assert_eq(child_b.read_byte_at(0), 3)
  child_b.close()
}

///|
test "native mmap view close stays safe for empty and large mappings" {
  let empty_path = native_test_path("native-mmap-close-empty.bin")
  write_fixture(empty_path, [])
  let empty_view = new_mmap_file_view(empty_path)
  empty_view.close()
  empty_view.close()
  assert_eq(empty_view.is_closed(), true)

  let large_path = native_test_path("native-mmap-close-large.bin")
  let large_data = pattern_bytes(10 * 1024 * 1024)
  write_fixture(large_path, large_data)
  let large_view = new_mmap_file_view(large_path)
  large_view.close()
  large_view.close()
  assert_eq(large_view.is_closed(), true)
}

///|
test "native mmap view reads single byte and medium fixtures" {
  let sizes = [1, 64 * 1024, 1024 * 1024]
  for size in sizes {
    let path = native_test_path("native-mmap-size-\{size}.bin")
    let data = pattern_bytes(size)
    write_fixture(path, data)
    let view = new_mmap_file_view(path)
    assert_eq(view.len(), size)
    if size > 0 {
      assert_eq(view.read_byte_at(0), data[0])
      assert_eq(view.read_byte_at(size - 1), data[size - 1])
    }
    let limit = if size < 16 { size } else { 16 }
    let expected : Array[Byte] = []
    expected.append(data[0:limit])
    assert_eq(view.copy_range(0, limit), expected)
    view.close()
  }
}

///|
test "native mmap view handles large 10mb fixtures" {
  let path = native_test_path("native-mmap-10mb.bin")
  let data = pattern_bytes(10 * 1024 * 1024)
  write_fixture(path, data)
  let view = new_mmap_file_view(path)
  assert_eq(view.len(), data.length())
  assert_eq(view.read_byte_at(0), data[0])
  assert_eq(view.read_byte_at(1024 * 1024), data[1024 * 1024])
  assert_eq(view.read_byte_at(data.length() - 1), data[data.length() - 1])
  view.close()
}

///|
test "native mmap view reads files written by root and native sinks" {
  let root_path = native_test_path("native-mmap-from-root.bin")
  let root_data = pattern_bytes(64 * 1024)
  let root_sink = @bufferutils.new_file_sink(root_path)
  root_sink.write(root_data)
  root_sink.flush()
  let root_view = new_mmap_file_view(root_path)
  let root_expected : Array[Byte] = []
  root_expected.append(root_data[0:8])
  assert_eq(root_view.copy_range(0, 8), root_expected)
  root_view.close()

  let native_path = native_test_path("native-mmap-from-native.bin")
  let native_data = pattern_bytes(64 * 1024)
  let native_sink = new_native_file_sink(native_path, NativeFileMode::Overwrite)
  native_sink.write_all(native_data)
  native_sink.close()
  let native_view = new_mmap_file_view(native_path)
  let native_expected : Array[Byte] = []
  native_expected.append(native_data[0:8])
  assert_eq(native_view.copy_range(0, 8), native_expected)
  native_view.close()
}

///|
test "native mmap view count byte covers no match and many matches" {
  let path = native_test_path("native-mmap-count.bin")
  write_fixture(path, [7, 7, 7, 1, 2, 7, 3, 7])
  let view = new_mmap_file_view(path)
  assert_eq(view.count_byte(7), 5)
  assert_eq(view.count_byte(1), 1)
  assert_eq(view.count_byte(9), 0)
  view.close()
}

///|
test "native mmap view count byte handles large fixtures" {
  let path = native_test_path("native-mmap-count-large.bin")
  let data = repeated_bytes(10 * 1024 * 1024, (7).to_byte())
  write_fixture(path, data)
  let view = new_mmap_file_view(path)
  assert_eq(view.count_byte(7), data.length())
  assert_eq(view.count_byte(1), 0)
  view.close()
}

///|
test "native mmap view index_of returns first repeated match" {
  let path = native_test_path("native-mmap-index.bin")
  write_fixture(path, [1, 2, 1, 2, 3, 1, 2, 3])
  let view = new_mmap_file_view(path)
  assert_eq(view.find_byte(1), view.index_of([1]))
  assert_eq(view.find_byte(2), view.index_of([2]))
  assert_eq(view.find_byte(3), view.index_of([3]))
  assert_eq(view.index_of([1, 2]), 0)
  assert_eq(view.index_of([1, 2, 3]), 2)
  assert_eq(view.index_of([2, 3]), 3)
  assert_eq(view.index_of([3, 4]), -1)
  view.close()
}

///|
test "native mmap view equals supports large equal files" {
  let path = native_test_path("native-mmap-equals-large.bin")
  let data = pattern_bytes(64 * 1024)
  write_fixture(path, data)
  let view = new_mmap_file_view(path)
  assert_eq(view.equals(data), true)
  let shorter : Array[Byte] = []
  shorter.append(data[0:1024])
  assert_eq(view.equals(shorter), false)
  view.close()
}

///|
test "native mmap view equals supports 1mb fixtures" {
  let path = native_test_path("native-mmap-equals-1mb.bin")
  let data = pattern_bytes(1024 * 1024)
  write_fixture(path, data)
  let view = new_mmap_file_view(path)
  assert_eq(view.equals(data), true)
  let different = pattern_bytes(1024 * 1024)
  different[1024] = (different[1024].to_int() ^ 0x7f).to_byte()
  assert_eq(view.equals(different), false)
  view.close()
}

///|
test "native mmap view crc32 matches known hello fixture" {
  let path = native_test_path("native-mmap-crc32-hello.bin")
  write_fixture(path, [104, 101, 108, 108, 111])
  let view = new_mmap_file_view(path)
  assert_eq(view.crc32(), 0x3610A686)
  assert_eq(view.crc32(), 0x3610A686)
  view.close()
}

///|
test "native mmap view checksum and crc32 stay stable on large fixtures" {
  let path = native_test_path("native-mmap-checksum-large.bin")
  let data = pattern_bytes(1024 * 1024)
  write_fixture(path, data)
  let view = new_mmap_file_view(path)
  let first_crc = view.crc32()
  let second_crc = view.crc32()
  let first_checksum = view.checksum_u64()
  let second_checksum = view.checksum_u64()
  assert_eq(first_crc, second_crc)
  assert_eq(first_checksum, second_checksum)
  view.close()
}

///|
test "native mmap slice operations support crc32 checksum and copy_to_file" {
  let path = native_test_path("native-mmap-slice-ops.bin")
  let compare_path = native_test_path("native-mmap-slice-ops-compare.bin")
  let copy_path = native_test_path("native-mmap-slice-ops-copy.bin")
  write_fixture(path, [1, 2, 3, 2, 3, 4, 5])
  write_fixture(compare_path, [2, 3, 2, 3])

  let root = new_mmap_file_view(path)
  let child = root.slice_handle(1, 4)
  let compare = new_mmap_file_view(compare_path)

  assert_eq(child.find_byte(2), 0)
  assert_eq(child.find_byte(4), -1)
  assert_eq(child.count_byte(2), 2)
  assert_eq(child.count_byte(3), 2)
  assert_eq(child.index_of([]), 0)
  assert_eq(child.index_of([2]), child.find_byte(2))
  assert_eq(child.index_of([2, 3]), 0)
  assert_eq(child.index_of([3, 2]), 1)
  assert_eq(child.equals([2, 3, 2, 3]), true)
  assert_eq(child.equals([2, 3, 2]), false)
  assert_eq(child.starts_with([]), true)
  assert_eq(child.starts_with([2, 3]), true)
  assert_eq(child.starts_with([2, 3, 2, 3, 4]), false)
  assert_eq(child.crc32(), compare.crc32())
  assert_eq(child.checksum_u64(), compare.checksum_u64())
  assert_eq(child.copy_range(1, 2), [3, 2])
  child.copy_to_file(copy_path)
  assert_eq(read_fixture(copy_path), [2, 3, 2, 3])

  root.close()
  assert_eq(child.read_byte_at(0), 2)
  compare.close()
  child.close()
}

///|
test "native mmap view copy_to_file validates empty path and large copy" {
  let empty_result = try? new_mmap_file_view("")
  assert_eq(empty_result is Err(_), true)

  let path = native_test_path("native-mmap-copy-large-src.bin")
  let data = pattern_bytes(1024 * 1024)
  write_fixture(path, data)
  let view = new_mmap_file_view(path)
  let empty_path_result = try? view.copy_to_file("")
  assert_eq(empty_path_result is Err(_), true)

  let out_path = native_test_path("native-mmap-copy-large-dst.bin")
  view.copy_to_file(out_path)
  assert_eq(read_fixture(out_path), data)
  view.close()
}

///|
test "native mmap view copy_to_file supports empty and overwrite semantics" {
  let empty_src = native_test_path("native-mmap-copy-empty-src.bin")
  let empty_dst = native_test_path("native-mmap-copy-empty-dst.bin")
  write_fixture(empty_src, [])
  write_fixture(empty_dst, [1, 2, 3])
  let empty_view = new_mmap_file_view(empty_src)
  empty_view.copy_to_file(empty_dst)
  assert_eq(read_fixture(empty_dst), [])
  empty_view.close()

  let src = native_test_path("native-mmap-copy-overwrite-src.bin")
  let dst = native_test_path("native-mmap-copy-overwrite-dst.bin")
  let data = pattern_bytes(10 * 1024 * 1024)
  write_fixture(src, data)
  write_fixture(dst, [9, 9, 9])
  let view = new_mmap_file_view(src)
  view.copy_to_file(dst)
  assert_eq(read_fixture(dst), data)
  view.close()
}
