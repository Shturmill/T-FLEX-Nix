/*
 * Фальшивые aksusbd_x86_64 и hasplmd_x86_64 для проверок модуля
 * services.tflex17-licensing без настоящего Sentinel LDK (tests/default.nix).
 *
 * Ведут себя так, как этого ждут юниты systemd из архива: Type=forking —
 * родитель сразу выходит, демон остаётся. «hasplmd» дополнительно
 * проверяет, что модуль разложил файлы по путям настоящего hasplmd
 * (/var/hasplm, /etc/hasplm/templates), и отвечает по HTTP на порту 1947,
 * как Sentinel Admin Control Center.
 */
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

static int serve_1947(void)
{
    int s = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    struct sockaddr_in a;

    if (s < 0)
        return 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(1947);
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(s, (struct sockaddr *)&a, sizeof a) != 0 || listen(s, 8) != 0)
        return 1;
    for (;;) {
        static const char reply[] = "HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\n\r\nfake hasplmd\n";
        int c = accept(s, NULL, NULL);
        if (c < 0)
            continue;
        if (write(c, reply, sizeof reply - 1) < 0)
            perror("write");
        close(c);
    }
}

int main(int argc, char **argv)
{
    const char *name = strrchr(argv[0], '/');
    int is_lm;
    pid_t pid;
    struct stat st;

    name = name ? name + 1 : argv[0];
    is_lm = strstr(name, "hasplmd") != NULL;

    if (argc > 1 && strcmp(argv[1], "--version") == 0) {
        printf("fake %s\n", name);
        return 0;
    }
    if (is_lm && (stat("/var/hasplm/haspvlib_x86_64_46113.so", &st) != 0 ||
                  stat("/etc/hasplm/templates/ru.17.0.alp", &st) != 0)) {
        fprintf(stderr, "fake %s: нет файлов в /var/hasplm или /etc/hasplm/templates\n", name);
        return 1;
    }

    pid = fork();
    if (pid < 0)
        return 1;
    if (pid > 0)
        return 0;
    setsid();
    if (is_lm)
        return serve_1947();
    for (;;)
        pause();
}
