#include <stdint.h>

#ifndef MOONBIT_FFI_EXPORT
#define MOONBIT_FFI_EXPORT
#endif

#include <errno.h>

#if defined(_WIN32)
#include <winsock2.h>
#else
#include <sys/socket.h>
#endif

MOONBIT_FFI_EXPORT int32_t bufferutils_async_tcp_shutdown(int32_t fd,
                                                           int32_t how) {
#if defined(_WIN32)
  int native_how = how == 0 ? SD_RECEIVE : (how == 1 ? SD_SEND : SD_BOTH);
  int result = shutdown((SOCKET)(uintptr_t)(uint32_t)fd, native_how);
  if (result == 0 || WSAGetLastError() == WSAENOTCONN) return 0;
  return (int32_t)WSAGetLastError();
#else
  int native_how = how == 0 ? SHUT_RD : (how == 1 ? SHUT_WR : SHUT_RDWR);
  int result = shutdown((int)fd, native_how);
  if (result == 0 || errno == ENOTCONN) return 0;
  return errno == 0 ? EIO : errno;
#endif
}
