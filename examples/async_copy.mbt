///|
pub async fn async_copy_example(
  source_path : StringView,
  destination_path : StringView,
) -> Int {
  let progress = @asyncio.copy_file(
    source_path,
    destination_path,
    buffer_size=64 * 1024,
  )
  progress.bytes
}
