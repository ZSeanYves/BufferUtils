///|
fn[T, E : Error] capture_wb_result(f : () -> T raise E) -> Result[T, E] {
  try f() |> Ok catch {
    error => Err(error)
  }
}

///|
test "shared storage defensive helpers cover bounds and adoption errors" {
  assert_true(
    capture_wb_result(() => next_shared_capacity(2147483647, 4)) is Err(_),
  )
  assert_eq(next_shared_capacity(1073741824, 4), 2147483647)
  assert_true(
    capture_wb_result(() => {
      ignore(adopt_shared_storage(FixedArray::make(1, b'x'), 1, 0, 0))
    })
    is Err(_),
  )
}
