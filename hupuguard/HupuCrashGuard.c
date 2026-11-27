// HupuCrashGuard v3 — diagnostic anti-exit guard for Hupu 8.2.70 (works
// for the whole 8.2.x generation) on iOS 27.
//
// Established facts this build is based on (2026-11-24, device logs +
// static audit):
//   - The cracked 8.2.70 package is byte-clean vs. Apple's own code
//     directory hashes; the LCSign re-sign is identical in entitlements
//     to the working 8.1.9 package. Clean install, no leftover state.
//   - Mac Console unified log shows SpringBoard reporting
//     "Process exited: <RBSProcessExitContext| voluntary>" ~0.3 s after
//     launch, before the scene client connects, before any network
//     request by the main process. The LLVM profile runtime flushing
//     /default.profraw at the end proves the libc exit path (atexit /
//     destructors) ran: the app terminates *itself* during earliest
//     startup — an anti-tamper / re-sign self-check bailing out.
//   - v1/v2 of this guard (8.2.67) interposed exit/_exit/kill/
//     pthread_kill/raise/abort/__assert_rtn and swizzled
//     -[UIApplication terminateWithSuccess]; the signed test package
//     was verified to contain the dylib, correctly signed and loaded —
//     and the app still exited. So the exit channel is one v2 did not
//     cover, or the check's decision happens on a surface v2 did not
//     observe.
//
// What v3 changes vs. v2:
//   1. LOGGING GOES TO THE UNIFIED LOG (os_log, subsystem
//      "com.hp.guard", category "hpguard", public format) in addition
//      to the $TMPDIR file. v1/v2 logged only to the app container's
//      tmp, which the user cannot retrieve on a non-jailbroken phone,
//      so we never learned whether any hook even fired. With os_log,
//      the user streams Mac Console while launching and every blocked
//      call shows up live, tagged HPGUARD.
//   2. EVERY LOG LINE CARRIES THE CALLER: return address, image name
//      and offset within the image (via dladdr). If a check consults a
//      signing API and then exits, the caller offset identifies the
//      exact function in the 172 MB main binary so the check can be
//      patched precisely instead of blind-blocked.
//   3. NEW EXIT CHANNELS COVERED: syscall() (SYS_exit / SYS_kill are
//      filtered; SYS_csops / SYS_csops_audittoken are logged with op
//      and caller, then forwarded), pthread_exit (logged, then the
//      calling thread is parked — pthread_exit never returns by
//      contract, so returning would corrupt the caller's assumptions;
//      parking keeps the process alive if any other thread can finish
//      startup, and if the parked thread was the startup thread the
//      20 s launch watchdog kills the app *with* a report, which is
//      itself a diagnosis), _Exit (via the _exit replacement slot —
//      _Exit and _exit are the same libSystem entry).
//   4. SIGNING-CHECK SURFACES: SecCodeCheckValidity and
//      SecCodeCheckValidityWithErrors are interposed to log the caller
//      and report success (errSecSuccess, errors=NULL) — if the check
//      asks the Security framework "am I valid?", it now hears "yes".
//      -[NSBundle appStoreReceiptURL] is swizzled to log its caller
//      (then call through): if the check consults the receipt, we see
//      it, even though a valid store receipt cannot be fabricated.
//   Fail-open: anything unexpected falls back to stock behavior.

#include <stdlib.h>
#include <signal.h>
#include <pthread.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <fcntl.h>
#include <stdarg.h>
#include <dlfcn.h>
#include <os/log.h>
#include <objc/runtime.h>
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <Security/SecCode.h>
#include <sys/syscall.h>

extern void __assert_rtn(const char *, const char *, int, const char *);

// ---------------------------------------------------------------- log

static os_log_t hp_oslog(void) {
    static os_log_t log;
    if (!log) log = os_log_create("com.hp.guard", "hpguard");
    return log;
}

// caller: a return address inside the calling image (may be NULL).
static void hp_log(const char *what, long arg, void *caller) {
    char img[128] = "?";
    unsigned long long off = 0;
    if (caller) {
        Dl_info di;
        if (dladdr(caller, &di) && di.dli_fname) {
            const char *base = strrchr(di.dli_fname, '/');
            snprintf(img, sizeof(img), "%s", base ? base + 1 : di.dli_fname);
            off = (unsigned long long)((char *)caller - (char *)di.dli_fbase);
        }
    }
    os_log_error(hp_oslog(), "HPGUARD %{public}s(%ld) caller=%{public}s+0x%llx",
                 what, arg, img, off);
    const char *tmp = getenv("TMPDIR");
    char path[512];
    if (tmp && tmp[0]) {
        snprintf(path, sizeof(path), "%s/HupuCrashGuard.log", tmp);
    } else {
        snprintf(path, sizeof(path), "/tmp/HupuCrashGuard.log");
    }
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    char buf[256];
    int n = snprintf(buf, sizeof(buf), "HPGUARD %s(%ld) caller=%s+0x%llx pid=%d\n",
                     what, arg, img, off, (int)getpid());
    if (n > 0) (void)!write(fd, buf, (size_t)n);
    close(fd);
}

#define HP_CALLER (__builtin_return_address(0))

// ---------------------------------------------------------------- exit

static void hp_exit(int status) {
    hp_log("exit", status, HP_CALLER);
    // Return: the caller continues as if exit had not been requested.
}

static void hp__exit(int status) {
    hp_log("_exit/_Exit", status, HP_CALLER);
}

// ---------------------------------------------------------------- kill

static int hp_is_fatal(int sig) {
    return sig == SIGKILL || sig == SIGTERM || sig == SIGABRT ||
           sig == SIGHUP  || sig == SIGINT  || sig == SIGQUIT;
}

static int hp_kill(pid_t pid, int sig) {
    if ((pid == getpid() || pid <= 0) && hp_is_fatal(sig)) {
        hp_log("kill", sig, HP_CALLER);
        return 0;
    }
    return kill(pid, sig); // interposer's own binds are not interposed
}

static int hp_pthread_kill(pthread_t thread, int sig) {
    (void)thread;
    if (hp_is_fatal(sig)) {
        hp_log("pthread_kill", sig, HP_CALLER);
        return 0;
    }
    return pthread_kill(thread, sig);
}

static int hp_raise(int sig) {
    if (hp_is_fatal(sig)) {
        hp_log("raise", sig, HP_CALLER);
        return 0;
    }
    return raise(sig);
}

// ---------------------------------------------------------------- abort

static void hp_abort(void) {
    hp_log("abort", 0, HP_CALLER);
}

static void hp_assert_rtn(const char *func, const char *file, int line, const char *expr) {
    (void)func; (void)file; (void)expr;
    hp_log("__assert_rtn", line, HP_CALLER);
}

// ---------------------------------------------------------------- pthread_exit

static void hp_pthread_exit(void *value) {
    (void)value;
    hp_log("pthread_exit", 0, HP_CALLER);
    // pthread_exit never returns by contract; park this thread instead
    // of letting the process die with it. If this was the startup
    // thread, the launch watchdog will kill the app with a report —
    // which still tells us this was the channel.
    for (;;) pause();
}

// ---------------------------------------------------------------- syscall

static long (*hp_real_syscall)(int, ...) = NULL;
static __thread int hp_in_syscall = 0;

static long hp_syscall(int n, ...) {
    va_list ap;
    va_start(ap, n);
    long a1 = va_arg(ap, long);
    long a2 = va_arg(ap, long);
    long a3 = va_arg(ap, long);
    long a4 = va_arg(ap, long);
    long a5 = va_arg(ap, long);
    long a6 = va_arg(ap, long);
    va_end(ap);
    void *caller = HP_CALLER;
    if (!hp_real_syscall) {
        hp_real_syscall = (long (*)(int, ...))dlsym(RTLD_DEFAULT, "syscall");
        if (!hp_real_syscall) return -1;
    }
    if (hp_in_syscall) {
        return hp_real_syscall(n, a1, a2, a3, a4, a5, a6);
    }
    hp_in_syscall = 1;
    long r;
    if (n == SYS_exit) {
        hp_log("syscall(SYS_exit)", a1, caller);
        r = 0; // pretend success; caller continues
    } else if (n == SYS_kill) {
        pid_t pid = (pid_t)a1;
        int sig = (int)a2;
        if ((pid == getpid() || pid <= 0) && hp_is_fatal(sig)) {
            hp_log("syscall(SYS_kill)", sig, caller);
            r = 0;
        } else {
            r = hp_real_syscall(n, a1, a2, a3, a4, a5, a6);
        }
    } else if (n == SYS_csops || n == SYS_csops_audittoken) {
        // a2 = op. Log the consultation (who asks the kernel about its
        // own code signing, with which op) and forward untouched:
        // faking kernel answers blind is worse than learning from them.
        hp_log(n == SYS_csops ? "syscall(SYS_csops)" : "syscall(SYS_csops_audittoken)",
               a2, caller);
        r = hp_real_syscall(n, a1, a2, a3, a4, a5, a6);
    } else {
        r = hp_real_syscall(n, a1, a2, a3, a4, a5, a6);
    }
    hp_in_syscall = 0;
    return r;
}

// ---------------------------------------------------------------- SecCode

static OSStatus hp_SecCodeCheckValidity(SecCodeRef process, SecCSFlags flags,
                                        SecRequirementRef requirement) {
    (void)process; (void)requirement;
    hp_log("SecCodeCheckValidity->YES", (long)flags, HP_CALLER);
    return errSecSuccess;
}

static OSStatus hp_SecCodeCheckValidityWithErrors(SecCodeRef process, SecCSFlags flags,
                                                  SecRequirementRef requirement,
                                                  CFErrorRef *errors) {
    (void)process; (void)requirement;
    hp_log("SecCodeCheckValidityWithErrors->YES", (long)flags, HP_CALLER);
    if (errors) *errors = NULL;
    return errSecSuccess;
}

// ---------------------------------------------------------------- interpose

struct hp_interpose {
    void *replacement;
    void *original;
};

__attribute__((used, section("__DATA,__interpose"))) static const struct hp_interpose hp_ip_exit =
    { (void *)hp_exit, (void *)exit };
__attribute__((used, section("__DATA,__interpose"))) static const struct hp_interpose hp_ip__exit =
    { (void *)hp__exit, (void *)_exit };
__attribute__((used, section("__DATA,__interpose"))) static const struct hp_interpose hp_ip_abort =
    { (void *)hp_abort, (void *)abort };
__attribute__((used, section("__DATA,__interpose"))) static const struct hp_interpose hp_ip_assert_rtn =
    { (void *)hp_assert_rtn, (void *)__assert_rtn };
__attribute__((used, section("__DATA,__interpose"))) static const struct hp_interpose hp_ip_kill =
    { (void *)hp_kill, (void *)kill };
__attribute__((used, section("__DATA,__interpose"))) static const struct hp_interpose hp_ip_pthread_kill =
    { (void *)hp_pthread_kill, (void *)pthread_kill };
__attribute__((used, section("__DATA,__interpose"))) static const struct hp_interpose hp_ip_raise =
    { (void *)hp_raise, (void *)raise };
__attribute__((used, section("__DATA,__interpose"))) static const struct hp_interpose hp_ip_pthread_exit =
    { (void *)hp_pthread_exit, (void *)pthread_exit };
__attribute__((used, section("__DATA,__interpose"))) static const struct hp_interpose hp_ip_syscall =
    { (void *)hp_syscall, (void *)syscall };
__attribute__((used, section("__DATA,__interpose"))) static const struct hp_interpose hp_ip_sccv =
    { (void *)hp_SecCodeCheckValidity, (void *)SecCodeCheckValidity };
__attribute__((used, section("__DATA,__interpose"))) static const struct hp_interpose hp_ip_sccvwe =
    { (void *)hp_SecCodeCheckValidityWithErrors, (void *)SecCodeCheckValidityWithErrors };

// ---------------------------------------------------------------- ObjC swizzles

static void hp_terminate_noop(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    hp_log("terminateWithSuccess", 0, HP_CALLER);
}

static IMP hp_orig_receipt = NULL;
static id hp_receipt_logged(id self, SEL _cmd) {
    hp_log("appStoreReceiptURL consulted", 0, HP_CALLER);
    if (hp_orig_receipt) {
        return ((id (*)(id, SEL))hp_orig_receipt)(self, _cmd);
    }
    return nil;
}

__attribute__((constructor)) static void HupuCrashGuardInit(void) {
    Class uiapp = objc_getClass("UIApplication");
    if (uiapp) {
        Method m = class_getInstanceMethod(uiapp, sel_registerName("terminateWithSuccess"));
        if (m) {
            method_setImplementation(m, (IMP)hp_terminate_noop);
        }
    }
    Class nsbundle = objc_getClass("NSBundle");
    if (nsbundle) {
        Method m = class_getInstanceMethod(nsbundle, sel_registerName("appStoreReceiptURL"));
        if (m) {
            hp_orig_receipt = method_setImplementation(m, (IMP)hp_receipt_logged);
        }
    }
    hp_log("guard-v3-loaded", 0, NULL);
}
