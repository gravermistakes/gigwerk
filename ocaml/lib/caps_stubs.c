/* Capability primitives.
 *
 * The whole ocap claim rests on one syscall: openat2 with RESOLVE_BENEATH.
 * The kernel refuses to resolve outside the directory the fd names -- not the
 * library, not a path-validation function that could have a bug in it. ".."
 * and absolute paths fail with EXDEV before any file is touched.
 *
 * A dirfd is therefore a real capability: holding it grants exactly the
 * subtree, and there is no parent to walk to. */

#define _GNU_SOURCE
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef SYS_openat2
#define SYS_openat2 437
#endif

#ifndef RESOLVE_BENEATH
#define RESOLVE_BENEATH 0x08
#endif
#ifndef RESOLVE_NO_SYMLINKS
#define RESOLVE_NO_SYMLINKS 0x04
#endif
#ifndef RESOLVE_NO_MAGICLINKS
#define RESOLVE_NO_MAGICLINKS 0x02
#endif

struct gw_open_how {
  uint64_t flags;
  uint64_t mode;
  uint64_t resolve;
};

static void gw_fail(const char *what) {
  char buf[256];
  snprintf(buf, sizeof buf, "%s: %s", what, strerror(errno));
  caml_failwith(buf);
}

/* Open a directory as a capability root. O_PATH would be tighter but openat2
 * needs a resolvable dirfd, so O_RDONLY|O_DIRECTORY it is. */
CAMLprim value gw_open_dir(value path) {
  CAMLparam1(path);
  int fd = open(String_val(path), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (fd < 0) gw_fail("open_dir");
  CAMLreturn(Val_int(fd));
}

CAMLprim value gw_close_fd(value fd) {
  CAMLparam1(fd);
  close(Int_val(fd));
  CAMLreturn(Val_unit);
}

/* Read a file beneath the capability root. The dirfd never leaves C, so OCaml
 * code cannot construct a path that escapes -- there is nothing to escape with. */
CAMLprim value gw_read_at(value dirfd, value name) {
  CAMLparam2(dirfd, name);
  CAMLlocal1(out);
  struct gw_open_how how;
  memset(&how, 0, sizeof how);
  how.flags = O_RDONLY | O_CLOEXEC;
  how.resolve = RESOLVE_BENEATH | RESOLVE_NO_SYMLINKS | RESOLVE_NO_MAGICLINKS;

  int fd = (int)syscall(SYS_openat2, Int_val(dirfd), String_val(name),
                        &how, sizeof how);
  if (fd < 0) gw_fail("read_at");

  size_t cap = 65536, len = 0;
  char *buf = malloc(cap);
  if (!buf) { close(fd); caml_failwith("read_at: out of memory"); }
  for (;;) {
    if (len == cap) {
      cap *= 2;
      char *nb = realloc(buf, cap);
      if (!nb) { free(buf); close(fd); caml_failwith("read_at: out of memory"); }
      buf = nb;
    }
    ssize_t n = read(fd, buf + len, cap - len);
    if (n < 0) { free(buf); close(fd); gw_fail("read_at"); }
    if (n == 0) break;
    len += (size_t)n;
  }
  close(fd);
  out = caml_alloc_initialized_string(len, buf);
  free(buf);
  CAMLreturn(out);
}

/* Does this kernel have openat2? Reported, not assumed. */
CAMLprim value gw_have_openat2(value unit) {
  CAMLparam1(unit);
  struct gw_open_how how;
  memset(&how, 0, sizeof how);
  how.flags = O_RDONLY;
  how.resolve = RESOLVE_BENEATH;
  int fd = (int)syscall(SYS_openat2, AT_FDCWD, ".", &how, sizeof how);
  if (fd >= 0) { close(fd); CAMLreturn(Val_true); }
  CAMLreturn(errno == ENOSYS ? Val_false : Val_true);
}
