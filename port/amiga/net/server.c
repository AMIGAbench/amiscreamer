/*
 * server.c - amiscreamer_server: the network game's host without a station of its own: every player joins it
 * (--join <server>[:port], the launcher's NETMODE=JOIN); only it needs its UDP port open to the internet.  It passes
 * the messages and the race states on and keeps the members' list; lobby after lobby, until CTRL-C (AmigaOS) /
 * SIGINT, SIGTERM (Linux).
 *   amiscreamer_server [--port N]
 * Built from the game's transport (net.c with NET_SERVER): AmigaOS (68020, bsdsocket.library) and Linux.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "net.h"

int net_host_server(void);
int net_server_count(void);
void net_server_stop(void);
int net_wait(int ms);
extern int net_host_port;

#if !defined(AMIGA) || defined(AMIGA_NULL)
#include <signal.h>
static volatile sig_atomic_t s_stop;
static void on_signal(int s) { (void)s; s_stop = 1; }
#endif

int main(int argc, char **argv)
{
    for (int i = 1; i < argc; i++) {
        if ((!strcmp(argv[i], "--port") || !strcmp(argv[i], "-p")) && i + 1 < argc) net_host_port = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--quiet") || !strcmp(argv[i], "-q")) { }
        else { fprintf(stderr, "usage: amiscreamer_server [--port N]\n"); return 5; }
    }
#if !defined(AMIGA) || defined(AMIGA_NULL)
    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
#endif
    if (net_host_server()) { fprintf(stderr, "amiscreamer_server: UDP port %d not to be had\n", net_host_port); return 10; }
    printf("amiscreamer_server: AmiScreamer network game on UDP port %d (CTRL-C ends)\n", net_host_port);
    fflush(stdout);
    for (;;) {
        const int w = net_wait(5);
        if (w == -2) break;
#if !defined(AMIGA) || defined(AMIGA_NULL)
        if (s_stop) break;
#endif
        net_pump();
    }
    net_server_stop();
    printf("amiscreamer_server: ended\n");
    return 0;
}
