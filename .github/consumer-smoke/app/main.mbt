///|
fn main {
  @smoke.sync_native_smoke() catch {
    error => abort("bufferutils consumer smoke failed: \{error}")
  }
  println("bufferutils consumer smoke passed")
}
