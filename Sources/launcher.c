// 用法: astris-launch [-f] [-c config.env] <dylib> <log> <astris-binary> [args...]
//
// 在独立会话中启动 Astris（关终端 / Ctrl-C 不影响），DYLD_INSERT_LIBRARIES 只进入 Astris 的环境。
// 给了 -c 时会留下一个很小的监视进程盯着 config.env：文件一变就把内容通过管道送进 Astris 里的
// dylib（Astris 是沙盒进程，自己读不了这个文件），dylib 解析后立即套用，不用重启。
// Astris 退出后监视进程自动退出。-f 为前台模式：Astris 继承终端的输出，本进程等它结束。
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#define FD_ENV "ASTRIS_MOUSE_CONFIG_FD"
#define FILE_ENV "ASTRIS_MOUSE_CONFIG_FILE"
#define SETTLE_MS 300

static void usage(const char *argv0) {
    fprintf(stderr, "usage: %s [-f] [-c config.env] <dylib> <log> <astris-binary> [args...]\n", argv0);
    exit(2);
}

static char *read_whole_file(const char *path, size_t *len) {
    *len = 0;
    int fd = open(path, O_RDONLY);
    if (fd < 0) return NULL;
    size_t cap = 4096, n = 0;
    char *buf = malloc(cap);
    for (;;) {
        if (n == cap) { cap *= 2; buf = realloc(buf, cap); }
        ssize_t r = read(fd, buf + n, cap - n);
        if (r < 0) { if (errno == EINTR) continue; break; }
        if (r == 0) break;
        n += (size_t)r;
    }
    close(fd);
    *len = n;
    return buf;
}

static int write_all(int fd, const void *data, size_t len) {
    const char *p = data;
    while (len > 0) {
        ssize_t w = write(fd, p, len);
        if (w < 0) { if (errno == EINTR) continue; return -1; }
        p += w;
        len -= (size_t)w;
    }
    return 0;
}

// 帧格式：4 字节大端长度 + 文件内容；文件不存在时长度为 0
static int send_frame(int fd, const char *buf, size_t len) {
    uint32_t be = htonl((uint32_t)len);
    if (write_all(fd, &be, sizeof be) < 0) return -1;
    return len ? write_all(fd, buf, len) : 0;
}

static void split_path(const char *path, char *dir, size_t dirsz) {
    const char *slash = strrchr(path, '/');
    if (!slash) { snprintf(dir, dirsz, "."); return; }
    size_t n = (size_t)(slash - path);
    if (n == 0) n = 1;
    if (n >= dirsz) n = dirsz - 1;
    memcpy(dir, path, n);
    dir[n] = 0;
}

static void watch_config(const char *cfg_path, pid_t child, int wfd) {
    signal(SIGPIPE, SIG_IGN);
    char dir[4096];
    split_path(cfg_path, dir, sizeof dir);

    int kq = kqueue();
    if (kq < 0) { perror("[astris-launch] kqueue"); return; }

    struct kevent ev;
    EV_SET(&ev, child, EVFILT_PROC, EV_ADD | EV_CLEAR, NOTE_EXIT, 0, NULL);
    if (kevent(kq, &ev, 1, NULL, 0, NULL) < 0) {
        fprintf(stderr, "[astris-launch] Astris (pid %d) already gone, not watching config\n", child);
        return;
    }
    // 盯目录：编辑器常用"写临时文件再改名"的方式保存，文件本身的 fd 会失效，目录事件不会漏
    int dirfd = open(dir, O_EVTONLY);
    if (dirfd >= 0) {
        EV_SET(&ev, dirfd, EVFILT_VNODE, EV_ADD | EV_CLEAR, NOTE_WRITE | NOTE_DELETE | NOTE_RENAME, 0, NULL);
        kevent(kq, &ev, 1, NULL, 0, NULL);
    }
    fprintf(stderr, "[astris-launch] watching %s (save to apply, no restart needed)\n", cfg_path);

    int filefd = -1;
    char *last = NULL;
    size_t last_len = 0;
    int have_last = 0;
    int dirty = 1; // 启动先送一次当前内容

    for (;;) {
        if (filefd < 0) {
            filefd = open(cfg_path, O_EVTONLY);
            if (filefd >= 0) {
                EV_SET(&ev, filefd, EVFILT_VNODE, EV_ADD | EV_CLEAR,
                       NOTE_WRITE | NOTE_EXTEND | NOTE_DELETE | NOTE_RENAME | NOTE_ATTRIB, 0, NULL);
                kevent(kq, &ev, 1, NULL, 0, NULL);
            }
        }
        struct timespec settle = { 0, SETTLE_MS * 1000000L };
        struct kevent out;
        int r = kevent(kq, NULL, 0, &out, 1, dirty ? &settle : NULL);
        if (r < 0) {
            if (errno == EINTR) continue;
            perror("[astris-launch] kevent");
            break;
        }
        if (r == 0) {
            // 事件停了 300ms 再读，避开编辑器分多步写文件的中间状态
            dirty = 0;
            if (filefd >= 0) { close(filefd); filefd = -1; } // 重新 open，跟上被替换的文件
            size_t len = 0;
            char *buf = read_whole_file(cfg_path, &len);
            int same = have_last && len == last_len && (len == 0 || memcmp(buf, last, len) == 0);
            if (same) { free(buf); continue; }
            if (send_frame(wfd, buf, len) < 0) {
                fprintf(stderr, "[astris-launch] config pipe closed (%s), stopping\n", strerror(errno));
                free(buf);
                break;
            }
            fprintf(stderr, "[astris-launch] %s %s (%zu bytes)\n",
                    buf ? "sent" : "missing", cfg_path, len);
            free(last);
            last = buf;
            last_len = len;
            have_last = 1;
            continue;
        }
        if (out.filter == EVFILT_PROC) {
            fprintf(stderr, "[astris-launch] Astris exited, config watcher stopping\n");
            break;
        }
        if (out.filter == EVFILT_VNODE) {
            dirty = 1;
            if ((int)out.ident == filefd && (out.fflags & (NOTE_DELETE | NOTE_RENAME))) {
                close(filefd);
                filefd = -1;
            }
        }
    }
    free(last);
}

int main(int argc, char **argv) {
    int foreground = 0;
    const char *cfg_path = NULL;
    int opt;
    while ((opt = getopt(argc, argv, "fc:")) != -1) {
        switch (opt) {
        case 'f': foreground = 1; break;
        case 'c': cfg_path = optarg; break;
        default: usage(argv[0]);
        }
    }
    if (argc - optind < 3) usage(argv[0]);
    const char *dylib = argv[optind];
    const char *log = argv[optind + 1];
    const char *bin = argv[optind + 2];
    char **child_argv = &argv[optind + 2];

    int pipefd[2] = { -1, -1 };
    if (cfg_path) {
        if (pipe(pipefd) < 0) { perror("pipe"); return 1; }
        fcntl(pipefd[1], F_SETFD, FD_CLOEXEC); // 写端不进入 Astris
    }

    pid_t pid = fork();
    if (pid < 0) {
        perror("fork");
        return 1;
    }
    if (pid == 0) {
        if (!foreground) {
            setsid();
            signal(SIGHUP, SIG_IGN);
            signal(SIGINT, SIG_IGN);
            int in = open("/dev/null", O_RDONLY);
            int out = open(log, O_WRONLY | O_CREAT | O_APPEND, 0644);
            if (in >= 0) { dup2(in, 0); close(in); }
            if (out >= 0) { dup2(out, 1); dup2(out, 2); close(out); }
        }
        if (cfg_path) {
            char num[16];
            snprintf(num, sizeof num, "%d", pipefd[0]);
            setenv(FD_ENV, num, 1);
            setenv(FILE_ENV, cfg_path, 1);
        }
        setenv("DYLD_INSERT_LIBRARIES", dylib, 1);
        execv(bin, child_argv);
        perror("execv");
        _exit(127);
    }

    if (cfg_path) close(pipefd[0]);

    if (foreground) {
        fprintf(stderr, "[astris-launch] Astris pid %d\n", pid);
        if (cfg_path) watch_config(cfg_path, pid, pipefd[1]);
        int status = 0;
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
        return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
    }

    printf("%d\n", pid);
    fflush(stdout);
    if (!cfg_path) return 0;

    // 监视进程：再 fork 一次并脱离终端，让 run.sh 的 $(...) 立刻拿到 pid 返回
    pid_t watcher = fork();
    if (watcher != 0) return 0;
    setsid();
    signal(SIGHUP, SIG_IGN);
    signal(SIGINT, SIG_IGN);
    int in = open("/dev/null", O_RDONLY);
    int out = open(log, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (in >= 0) { dup2(in, 0); close(in); }
    if (out >= 0) { dup2(out, 1); dup2(out, 2); close(out); }
    watch_config(cfg_path, pid, pipefd[1]);
    return 0;
}
