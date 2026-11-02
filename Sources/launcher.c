// 用法: astris-launch <dylib> <log> <astris-binary> [args...]
// 在独立会话中启动 Astris（关终端 / Ctrl-C 不影响），DYLD_INSERT_LIBRARIES 只进入 Astris 的环境。
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 4) {
        fprintf(stderr, "usage: %s <dylib> <log> <astris-binary> [args...]\n", argv[0]);
        return 2;
    }
    const char *dylib = argv[1];
    const char *log = argv[2];
    const char *bin = argv[3];

    pid_t pid = fork();
    if (pid < 0) {
        perror("fork");
        return 1;
    }
    if (pid > 0) {
        printf("%d\n", pid);
        return 0;
    }

    setsid();
    signal(SIGHUP, SIG_IGN);
    signal(SIGINT, SIG_IGN);

    int in = open("/dev/null", O_RDONLY);
    int out = open(log, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (in >= 0) { dup2(in, 0); close(in); }
    if (out >= 0) { dup2(out, 1); dup2(out, 2); close(out); }

    setenv("DYLD_INSERT_LIBRARIES", dylib, 1);
    execv(bin, &argv[3]);
    perror("execv");
    _exit(127);
}
