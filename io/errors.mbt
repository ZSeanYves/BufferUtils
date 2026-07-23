///|
/// Portable categories for synchronous I/O failures.
pub(all) enum IoErrorKind {
  InvalidInput
  InvalidData
  NotFound
  PermissionDenied
  WouldBlock
  TimedOut
  ConnectionReset
  ConnectionRefused
  BrokenPipe
  NotConnected
  AddressInUse
  AddressNotAvailable
  UnexpectedEof
  WriteZero
  Interrupted
  Closed
  NotSeekable
  StorageFull
  OutOfMemory
  Unsupported
  Backend
  ContractViolation
} derive(Eq, @debug.Debug)

///|
/// Structured context retained for retry and diagnosis.
pub(all) struct IoFailure {
  kind : IoErrorKind
  operation : String
  context : String
  path : String
  raw_code : Int
  progress : Int
  message : String
} derive(Eq, @debug.Debug)

///|
/// Errors raised by the synchronous I/O traits.
pub suberror IoError {
  Io(IoFailure)
} derive(Eq, @debug.Debug)

///|
/// Construct a structured I/O error.
pub fn io_error(
  kind : IoErrorKind,
  operation : String,
  context? : String = "",
  path? : String = "",
  raw_code? : Int = 0,
  progress? : Int = 0,
  message? : String = "",
) -> IoError {
  IoError::Io({ kind, operation, context, path, raw_code, progress, message })
}

///|
/// Return the partial progress reported by an error.
pub fn IoError::progress(self : IoError) -> Int {
  match self {
    Io(failure) => failure.progress
  }
}

///|
/// Return the portable error category.
pub fn IoError::kind(self : IoError) -> IoErrorKind {
  match self {
    Io(failure) => failure.kind
  }
}

///|
pub fn IoError::operation(self : IoError) -> String {
  match self {
    Io(failure) => failure.operation
  }
}

///|
pub fn IoError::context(self : IoError) -> String {
  match self {
    Io(failure) => failure.context
  }
}

///|
pub fn IoError::path(self : IoError) -> String {
  match self {
    Io(failure) => failure.path
  }
}

///|
pub fn IoError::raw_code(self : IoError) -> Int {
  match self {
    Io(failure) => failure.raw_code
  }
}

///|
pub fn IoError::message(self : IoError) -> String {
  match self {
    Io(failure) => failure.message
  }
}

///|
pub fn IoError::is_interrupted(self : IoError) -> Bool {
  self.kind() == Interrupted
}

///|
/// Add progress completed by an outer operation before this error occurred.
pub fn IoError::add_progress(self : IoError, completed : Int) -> IoError {
  match self {
    Io(failure) => {
      let progress = if completed > 2147483647 - failure.progress {
        2147483647
      } else {
        completed + failure.progress
      }
      IoError::Io({ ..failure, progress, })
    }
  }
}

///|
/// Validate a byte count returned by a trait implementation.
fn validate_progress(
  operation : String,
  count : Int,
  requested : Int,
) -> Unit raise IoError {
  if count < 0 || count > requested {
    raise io_error(
      ContractViolation,
      operation,
      message="backend returned an invalid byte count",
    )
  }
}
