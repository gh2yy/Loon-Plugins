// HupuCrashGuard — anti-silent-exit guard for Hupu 8.2.67 on iOS 27.
//
// Symptom (user's device, 2026-11-01): the launch image shows, then the
// app vanishes back to the home screen and NO crash report (.ips) is
// written. A genuine crash (bad access / abort / watchdog) always leaves
// a report, so this pattern means the process terminates *itself*
// during early startup through exit()/kill()-style calls — a normal
// termination is not a crash and writes nothing.
//
// This guard interposes the self-termination entry points so the two
// remaining explanations separate cleanly:
//   - App survives with the guard  -> the exit was self-inflicted
//     in-process (an early environment check bailing out), and the
//     guard is the fix.
//   - App still dies with the guard -> the kill comes from outside the
//     process (system side); stop patching the binary.
//
// Interposed via dyld __interpose (rewrites the binds of every image
// in the process, frameworks included, before any initializer runs):
//   exit, _exit                     -> no-op (log + return)
//   kill, pthread_kill, raise       -> no-op when aimed at this process
//                                      with a fatal signal
// Swizzled in the constructor:
//   -[UIApplication terminateWithSuccess] -> no-op
// Blocked attempts are appended to $TMPDIR/HupuCrashGuard.log.
// Fail-open: any setup failure leaves stock behavior untouched.

#include <stdlib.h>
#include <signal.h>
#include <pthread.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <fcntl.h>
#include <objc/runtime.h>

// ---------------------------------------------------------------- log

static void hp_log(const char *what, long arg) {
    const char *tmp = getenv("TMPDIR");
    char path[512];
    if (tmp && tmp[0]) {
        snprintf(path, sizeof(path), "%s/HupuCrashGuard.log", tmp);
    } else {
        snprintf(path, sizeof(path), "/tmp/HupuCrashGuard.log");
    }
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    char buf[160];
    int n = snprintf(buf, sizeof(buf), "blocked %s(%ld) pid=%d\n",
                     what, arg, (int)getpid());
    if (n > 0) (void)!write(fd, buf, (size_t)n);
    close(fd);
}

// ---------------------------------------------------------------- exit

static void hp_exit(int status) {
    hp_log("exit", status);
    // Deliberately return: the caller continues as if exit had not
    // been requested. Legitimate in-process code never depends on
    // exit() having run its atexit handlers during startup.
}

static void hp__exit(int status) {
    hp_log("_exit", status);
}

// ---------------------------------------------------------------- kill

static int hp_is_fatal(int sig) {
    return sig == SIGKILL || sig == SIGTERM || sig == SIGABRT ||
           sig == SIGHUP  || sig == SIGINT  || sig == SIGQUIT;
}

static int hp_kill(pid_t pid, int sig) {
    if ((pid == getpid() || pid <= 0) && hp_is_fatal(sig)) {
        hp_log("kill", sig);
        return 0;
    }
    return kill(pid, sig); // interposer's own binds are not interposed
}

static int hp_pthread_kill(pthread_t thread, int sig) {
    (void)thread; // pthread_kill can only target this process
    if (hp_is_fatal(sig)) {
        hp_log("pthread_kill", sig);
        return 0;
    }
    return pthread_kill(thread, sig);
}

static int hp_raise(int sig) {
    if (hp_is_fatal(sig)) {
        hp_log("raise", sig);
        return 0;
    }
    return raise(sig);
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
__attribute__((used, section("__DATA,__interpose"))) static const struct hp_interpose hp_ip_kill =
    { (void *)hp_kill, (void *)kill };
__attribute__((used, section("__DATA,__interpose"))) static const struct hp_interpose hp_ip_pthread_kill =
    { (void *)hp_pthread_kill, (void *)pthread_kill };
__attribute__((used, section("__DATA,__interpose"))) static const struct hp_interpose hp_ip_raise =
    { (void *)hp_raise, (void *)raise };

// ---------------------------------------------------------------- UIApplication

static void hp_terminate_noop(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    hp_log("terminateWithSuccess", 0);
}

__attribute__((constructor)) static void HupuCrashGuardInit(void) {
    Class uiapp = objc_getClass("UIApplication");
    if (uiapp) {
        Method m = class_getInstanceMethod(uiapp, sel_registerName("terminateWithSuccess"));
        if (m) {
            method_setImplementation(m, (IMP)hp_terminate_noop);
        }
    }
    hp_log("guard-loaded", 0);
}
