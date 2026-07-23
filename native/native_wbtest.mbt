///|
test "native error classification covers portable categories" {
  assert_eq(native_error_kind(12), @io.Interrupted)
  assert_eq(native_error_kind(14), @io.PermissionDenied)
  assert_eq(native_error_kind(9), @io.NotSeekable)
}
