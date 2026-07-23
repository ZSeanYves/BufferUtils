///|
test "async runtime errors map to portable IoError categories" {
  let missing : Error = @os_error.OSError::OSError(2, context="missing")
  let mapped = map_async_error("read", missing)
  try {
    raise mapped
  } catch {
    @syncio.IoError::Io(failure) => assert_eq(failure.kind, @syncio.NotFound)
    _ => assert_true(false)
  }
  let denied : Error = @os_error.OSError::OSError(13, context="denied")
  try {
    raise map_async_error("open", denied)
  } catch {
    @syncio.IoError::Io(failure) =>
      assert_true(
        failure.kind == @syncio.PermissionDenied ||
        failure.kind == @syncio.Backend,
      )
    _ => assert_true(false)
  }
  let existing = @syncio.io_error(@syncio.Closed, "close")
  let preserved = map_async_error("close", existing)
  try {
    raise preserved
  } catch {
    @syncio.IoError::Io(failure) => assert_eq(failure.kind, @syncio.Closed)
    _ => assert_true(false)
  }
  let unknown : Error = Failure::Failure("backend")
  try {
    raise map_async_error("unknown", unknown)
  } catch {
    @syncio.IoError::Io(failure) => assert_eq(failure.kind, @syncio.Backend)
    _ => assert_true(false)
  }
  ignore(
    map_async_error(
      "connect",
      @os_error.OSError::OSError(111, context="refused"),
    ),
  )
  ignore(
    map_async_error(
      "interrupt",
      @os_error.OSError::OSError(4, context="interrupted"),
    ),
  )
  ignore(
    map_async_error(
      "poll",
      @os_error.OSError::OSError(11, context="would block"),
    ),
  )
}
