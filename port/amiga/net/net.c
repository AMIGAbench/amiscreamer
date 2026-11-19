/*
 * net.c - THE NETWORK GAME's transport (net.h): the session core and the platform's UDP, in one file, with its own
 * protocol and every piece of state in one block that outlives the program's parts (os_slot 14) -- the parts put the
 * program's statics back.
 * Built into the game (AMIGA: bsdsocket.library; AMIGA_NULL, the qemu test: POSIX) and into amiscreamer_server
 * (NET_SERVER: a host without a station of its own, its state a static).
 *
 * The wire: 'A' 'S' version type sender-slot, then by type --
 *   JOIN (guest -> host)              WELCOME slot            REJECT (full, locked, closing)
 *   LIST n slots                      MSG from to seq16 len16 payload (seq 0: unreliable)       ACK seq16
 *   STATES {slot len serial32 data}*  (guest -> host: its own; host -> guest: the others' latest, each NET_STATE_MS)
 *   BYE   PING t32   PONG t32 host32   LOCK 0/1 (station 0 -> host)
 */
#include "net.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NC_VER       1              /* AmiScreamer's own wire ('A' 'S'): the 'S' 'N' 3 wire is turned away -- the two
                                       do not play together */
#define NC_PEER_MS   30000          /* nothing from a station so long: gone (a track's loading takes a while) */
#define NC_RESEND_MS 250
#define NC_TRIES     40
#define NC_OLD_MS    1000           /* an older state (the station in the menu, the race over) is not passed on */
#define NC_QUEUE     64
enum { T_JOIN = 1, T_WELCOME, T_REJECT, T_LIST, T_MSG, T_ACK, T_STATES, T_BYE, T_PING, T_LOCK, T_PONG };   /* (T_MSG = its T_IPX) */

typedef struct {
    int      mode, open, has_self, locked, clk_ok, clk_n, clk_i, n;
    uint8_t  self, slot[NET_MAX];
    uint32_t hip;
    int      hport;
    int32_t  clk_off;
    struct { uint32_t rtt; int32_t off; } clk[8];
    struct { uint32_t ip; int port; uint32_t last; int bye; } peer[256];
    uint16_t rseq;
    uint32_t last_bundle, last_ping, last_list, last_pump, last_state_tx, state_serial;
    struct { int used; uint8_t to; uint16_t seq; uint16_t len; uint32_t t; int tries; uint8_t d[NET_PAY + 16]; } pend[48];
    uint16_t seen[256][16];
    uint8_t  seen_i[256];
    struct { int valid; uint16_t len; uint32_t t, rx, serial; uint8_t d[NET_SMAX]; } st[256];
    struct { uint8_t from; uint16_t len; uint8_t d[NET_PAY]; } q[NC_QUEUE];
    int      qh, qn;
    long     fd;
    char     why[96];
} netall;

#ifdef NET_SERVER
static netall z_static;
static netall *Z = &z_static;
#define ZZ() (Z)
#else
void *os_slot(int id);
void os_slot_set(int id, void *p);
void *os_keep_calloc(size_t n, size_t each);
static netall *zz(void)
{
    netall *z = os_slot(14);
    if (!z && (z = os_keep_calloc(1, sizeof *z))) { z->fd = -1; z->self = 0xff; os_slot_set(14, z); }
    return z;
}
#define ZZ() zz()
#endif

static void nlog(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
#include <stdarg.h>
static void nlog(const char *fmt, ...)
{
    va_list a;
    va_start(a, fmt);
    fputs("net: ", stderr);
    vfprintf(stderr, fmt, a);
    fputc('\n', stderr);
    va_end(a);
}
#if defined(OS_RELEASE_H) && !defined(NET_SERVER)
#define nlog(...) ((void)0)       /* (the release game: not what the network does -- only (nlog)(...), what went wrong) */
#endif

/* ---------------------------------------------------------------- the platform: a clock, one UDP socket */
#if defined(AMIGA) && !defined(AMIGA_NULL)
#include <exec/types.h>
#include <exec/io.h>
#include <devices/timer.h>
#include <dos/dos.h>
#include <proto/exec.h>
#include <proto/timer.h>
#ifdef OS_MOS
#include <proto/socket.h>
#else
#include <proto/bsdsocket.h>
#endif
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/errno.h>
#include <netinet/in.h>
#include <netdb.h>
struct Library *SocketBase;
#ifdef NET_SERVER
#ifdef OS_MOS
struct Library *TimerBase;
#else
struct Device *TimerBase;
#endif
static struct timerequest s_treq;
#elif !defined(OS_MOS)
extern struct Device *TimerBase;                /* (sdl_amiga.c's) */
#endif
uint32_t net_ms(void)
{
#ifdef NET_SERVER
    if (!TimerBase) {
        if (OpenDevice((CONST_STRPTR)TIMERNAME, UNIT_MICROHZ, (struct IORequest *)&s_treq, 0)) return 0;
        TimerBase = (void *)s_treq.tr_node.io_Device;
    }
#endif
#ifdef OS_MOS
    struct TimeVal tv;
    GetSysTime(&tv);
    return (uint32_t)tv.tv_secs * 1000u + (uint32_t)tv.tv_micro / 1000u;
#else
    /* the E clock: steady (GetSysTime is the wall clock -- set by hand or by SNTP it would jump the shared clock) */
    struct EClockVal ev;
    const ULONG f = ReadEClock(&ev);
    if (!f) {
        struct timeval tv;
        GetSysTime(&tv);
        return (uint32_t)tv.tv_secs * 1000u + (uint32_t)tv.tv_micro / 1000u;
    }
    const uint64_t t = (uint64_t)ev.ev_hi << 32 | ev.ev_lo;
    return (uint32_t)(t / f * 1000u + t % f * 1000u / f);
#endif
}
static int udp_open(int port)
{
    netall *z = ZZ();
    if (!SocketBase && !(SocketBase = OpenLibrary((CONST_STRPTR)"bsdsocket.library", 4))) {
        snprintf(z->why, sizeof z->why, "no TCP/IP stack (bsdsocket.library)");
        return -1;
    }
    LONG fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET; a.sin_port = htons((UWORD)port); a.sin_addr.s_addr = htonl(INADDR_ANY);
    LONG one = 1;
    if (bind(fd, (struct sockaddr *)&a, sizeof a) < 0 || IoctlSocket(fd, FIONBIO, (char *)&one) < 0) {
        CloseSocket(fd);
        snprintf(z->why, sizeof z->why, "UDP port %d not to be had", port);
        return -1;
    }
    z->fd = fd;
    return 0;
}
static int udp_resolve(const char *name, uint32_t *ip)
{
    unsigned v[4]; char c;
    if (sscanf(name, "%u.%u.%u.%u%c", &v[0], &v[1], &v[2], &v[3], &c) == 4 && v[0] < 256 && v[1] < 256 && v[2] < 256 && v[3] < 256) {
        *ip = v[0] << 24 | v[1] << 16 | v[2] << 8 | v[3];
        return 0;
    }
    struct hostent *h = gethostbyname((void *)name);
    if (!h || h->h_addrtype != AF_INET || !h->h_addr_list[0]) return -1;
    const UBYTE *p = (const UBYTE *)h->h_addr_list[0];
    *ip = (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
    return 0;
}
static void udp_send(uint32_t ip, int port, const void *b, int n)
{
    netall *z = ZZ();
    if (z->fd < 0) return;
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET; a.sin_port = htons((UWORD)port); a.sin_addr.s_addr = htonl(ip);
    sendto(z->fd, (UBYTE *)b, n, 0, (struct sockaddr *)&a, sizeof a);
}
static int udp_recv(void *b, int max, uint32_t *ip, int *port)
{
    netall *z = ZZ();
    if (z->fd < 0) return -1;
    struct sockaddr_in a;
#ifdef OS_MOS
    LONG l = sizeof a;
#else
    socklen_t l = sizeof a;
#endif
    LONG r = recvfrom(z->fd, (UBYTE *)b, max, 0, (struct sockaddr *)&a, (void *)&l);
    if (r < 0) return Errno() == EWOULDBLOCK || Errno() == ECONNREFUSED ? 0 : -1;
    *ip = ntohl(a.sin_addr.s_addr); *port = ntohs(a.sin_port);
    return (int)r;
}
static void udp_close(void)
{
    netall *z = ZZ();
    if (z->fd >= 0) CloseSocket(z->fd);
    z->fd = -1;
}
#ifdef NET_SERVER
int net_wait(int ms)                            /* the server: a packet within ms? -2 = CTRL-C */
{
    netall *z = ZZ();
    if (z->fd < 0) return -1;
    fd_set rf;
    FD_ZERO(&rf); FD_SET(z->fd, &rf);
    struct timeval tv;
#ifdef OS_MOS
    tv.tv_sec = (ULONG)ms / 1000; tv.tv_usec = (ULONG)(ms % 1000) * 1000;
#else
    tv.tv_secs = (ULONG)ms / 1000; tv.tv_micro = (ULONG)(ms % 1000) * 1000;
#endif
    ULONG sig = SIGBREAKF_CTRL_C;
    LONG r = WaitSelect(z->fd + 1, &rf, NULL, NULL, (void *)&tv, &sig);
    if (sig & SIGBREAKF_CTRL_C) return -2;
    return r < 0 ? -1 : r > 0;
}
#endif
#else   /* POSIX: the qemu test, amiscreamer_server on Linux */
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
uint32_t net_ms(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint32_t)t.tv_sec * 1000u + (uint32_t)(t.tv_nsec / 1000000);
}
static int udp_open(int port)
{
    netall *z = ZZ();
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) { snprintf(z->why, sizeof z->why, "no socket"); return -1; }
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET; a.sin_port = htons((uint16_t)port); a.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(fd, (struct sockaddr *)&a, sizeof a) < 0 || fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) < 0) {
        close(fd);
        snprintf(z->why, sizeof z->why, "UDP port %d not to be had", port);
        return -1;
    }
    z->fd = fd;
    return 0;
}
static int udp_resolve(const char *name, uint32_t *ip)
{
    struct in_addr in;
    if (inet_aton(name, &in)) { *ip = ntohl(in.s_addr); return 0; }
#ifndef NET_NO_RESOLVE
    struct hostent *h = gethostbyname(name);
    if (!h || h->h_addrtype != AF_INET || !h->h_addr_list[0]) return -1;
    memcpy(&in, h->h_addr_list[0], 4);
    *ip = ntohl(in.s_addr);
    return 0;
#else
    return -1;
#endif
}
static void udp_send(uint32_t ip, int port, const void *b, int n)
{
    netall *z = ZZ();
    if (z->fd < 0) return;
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET; a.sin_port = htons((uint16_t)port); a.sin_addr.s_addr = htonl(ip);
    sendto((int)z->fd, b, (size_t)n, 0, (struct sockaddr *)&a, sizeof a);
}
static int udp_recv(void *b, int max, uint32_t *ip, int *port)
{
    netall *z = ZZ();
    if (z->fd < 0) return -1;
    struct sockaddr_in a;
    socklen_t l = sizeof a;
    ssize_t r = recvfrom((int)z->fd, b, (size_t)max, 0, (struct sockaddr *)&a, &l);
    if (r < 0) return errno == EAGAIN || errno == EWOULDBLOCK || errno == ECONNREFUSED ? 0 : -1;
    *ip = ntohl(a.sin_addr.s_addr); *port = ntohs(a.sin_port);
    return (int)r;
}
static void udp_close(void)
{
    netall *z = ZZ();
    if (z->fd >= 0) close((int)z->fd);
    z->fd = -1;
}
#ifdef NET_SERVER
int net_wait(int ms)
{
    netall *z = ZZ();
    if (z->fd < 0) return -1;
    fd_set rf;
    FD_ZERO(&rf); FD_SET((int)z->fd, &rf);
    struct timeval tv = { ms / 1000, (ms % 1000) * 1000 };
    int r = select((int)z->fd + 1, &rf, NULL, NULL, &tv);
    return r < 0 ? (errno == EINTR ? 0 : -1) : r > 0;
}
#endif
#endif

/* ---------------------------------------------------------------- the core */
static void wr16(uint8_t *p, uint32_t v) { p[0] = (uint8_t)(v >> 8); p[1] = (uint8_t)v; }
static uint32_t rd16(const uint8_t *p) { return (uint32_t)p[0] << 8 | p[1]; }
static void wr32(uint8_t *p, uint32_t v) { wr16(p, v >> 16); wr16(p + 2, v); }
static uint32_t rd32(const uint8_t *p) { return rd16(p) << 16 | rd16(p + 2); }

static int slot_index(netall *z, uint8_t s)
{
    for (int i = 0; i < z->n; i++) if (z->slot[i] == s) return i;
    return -1;
}
static void member_add(netall *z, uint8_t s)
{
    if (slot_index(z, s) >= 0 || z->n >= NET_MAX) return;
    int i = z->n++;
    while (i > 0 && z->slot[i - 1] > s) { z->slot[i] = z->slot[i - 1]; i--; }
    z->slot[i] = s;
}
static void member_del(netall *z, uint8_t s)
{
    int i = slot_index(z, s);
    if (i < 0) return;
    memmove(z->slot + i, z->slot + i + 1, (size_t)(z->n - i - 1));
    z->n--;
}
static int head(netall *z, uint8_t *b, int type) { b[0] = 'A'; b[1] = 'S'; b[2] = NC_VER; b[3] = (uint8_t)type; b[4] = z->self; return 5; }
static void send_peer(netall *z, uint8_t peer, const uint8_t *b, int n)
{
    if (z->mode == NET_JOIN) udp_send(z->hip, z->hport, b, n);
    else if (z->peer[peer].ip && !z->peer[peer].bye) udp_send(z->peer[peer].ip, z->peer[peer].port, b, n);
}
static void send_all(netall *z, const uint8_t *b, int n)
{
    if (z->mode == NET_JOIN) { send_peer(z, 0, b, n); return; }
    for (int i = 0; i < z->n; i++) if (z->slot[i] != z->self) send_peer(z, z->slot[i], b, n);
}
static void send_list(netall *z)
{
    uint8_t b[32];
    int o = head(z, b, T_LIST);
    b[o++] = (uint8_t)z->n;
    for (int i = 0; i < z->n; i++) b[o++] = z->slot[i];
    send_all(z, b, o);
    z->last_list = net_ms();
}
static void send_msg(netall *z, uint8_t peer, uint8_t from, uint8_t to, int rel, const uint8_t *pay, int len)
{
    uint8_t b[NET_PAY + 16];
    int o = head(z, b, T_MSG);
    uint16_t seq = 0;
    if (rel) { if (!++z->rseq) z->rseq = 1; seq = z->rseq; }
    b[o++] = from; b[o++] = to;
    wr16(b + o, seq); wr16(b + o + 2, (uint32_t)len); o += 4;
    memcpy(b + o, pay, (size_t)len); o += len;
    send_peer(z, peer, b, o);
    if (!rel) return;
    for (int i = 0; i < (int)(sizeof z->pend / sizeof z->pend[0]); i++)
        if (!z->pend[i].used) {
            z->pend[i].used = 1; z->pend[i].to = peer; z->pend[i].seq = seq; z->pend[i].len = (uint16_t)o;
            z->pend[i].t = net_ms(); z->pend[i].tries = 0;
            memcpy(z->pend[i].d, b, (size_t)o);
            return;
        }
}
/* the lobby command of a message (+0x04, little-endian) */
static uint32_t msg_cmd(const uint8_t *d, int len) { return len >= 8 ? d[4] | d[5] << 8 | d[6] << 16 | (uint32_t)d[7] << 24 : 0xffffffffu; }
/* what is sent again and again anyway (presence 0, the picker's track 3, the picker 0x8844): a newer one of the
   same station takes the older one's place, and these are the only ones ever dropped */
static int msg_repeated(uint32_t c) { return c == 0 || c == 3 || c == 0x8844; }
static void queue_msg(netall *z, uint8_t from, const uint8_t *d, int len)
{
    /* (the queue is never filled with repeats, commands are never lost) */
    const uint32_t c = msg_cmd(d, len);
    if (msg_repeated(c))
        for (int i = 0; i < z->qn; i++) {
            const int k = (z->qh + i) % NC_QUEUE;
            if (z->q[k].from == from && msg_cmd(z->q[k].d, z->q[k].len) == c) {
                memcpy(z->q[k].d, d, (size_t)len); z->q[k].len = (uint16_t)len;
                return;
            }
        }
    if (z->qn >= NC_QUEUE) {
        if (msg_repeated(c)) return;                     /* (full: a repeat is lost, it comes again) */
        int drop = -1;                                   /* a command: the oldest repeat makes room */
        for (int i = 0; i < z->qn && drop < 0; i++)
            if (msg_repeated(msg_cmd(z->q[(z->qh + i) % NC_QUEUE].d, z->q[(z->qh + i) % NC_QUEUE].len))) drop = i;
        if (drop < 0) return;
        for (int i = drop; i > 0; i--) z->q[(z->qh + i) % NC_QUEUE] = z->q[(z->qh + i - 1) % NC_QUEUE];
        z->qh = (z->qh + 1) % NC_QUEUE; z->qn--;
    }
    int k = (z->qh + z->qn++) % NC_QUEUE;
    z->q[k].from = from; z->q[k].len = (uint16_t)len;
    memcpy(z->q[k].d, d, (size_t)len);
}
static void set_state(netall *z, uint8_t s, const uint8_t *d, int len, uint32_t serial)
{
    if (len > NET_SMAX) return;
    z->st[s].valid = 1; z->st[s].len = (uint16_t)len; z->st[s].t = z->st[s].rx = net_ms(); z->st[s].serial = serial;
    memcpy(z->st[s].d, d, (size_t)len);
}
static int seen(netall *z, uint8_t from, uint16_t seq)
{
    for (int i = 0; i < 16; i++) if (z->seen[from][i] == seq) return 1;
    z->seen[from][z->seen_i[from]++ & 15] = seq;
    return 0;
}
static void clock_sample(netall *z, uint32_t t0, uint32_t th)
{
    uint32_t t1 = net_ms(), rtt = t1 - t0;
    if (rtt > 5000) return;
    z->clk[z->clk_i].rtt = rtt;
    z->clk[z->clk_i].off = (int32_t)(th + rtt / 2 - t1);
    z->clk_i = (z->clk_i + 1) % 8;
    if (z->clk_n < 8) z->clk_n++;
    int b = 0;
    for (int i = 1; i < z->clk_n; i++) if (z->clk[i].rtt < z->clk[b].rtt) b = i;
    z->clk_off = z->clk[b].off; z->clk_ok = 1;
}
static int peer_of(netall *z, uint32_t ip, int port)
{
    for (int i = 0; i < z->n; i++) {
        uint8_t s = z->slot[i];
        if (s != z->self && z->peer[s].ip == ip && z->peer[s].port == port) return s;
    }
    return -1;
}
static int free_slot(netall *z)
{
    for (int s = 1; s < 255; s++) if (slot_index(z, (uint8_t)s) < 0) return s;
    return -1;
}

static void handle(netall *z, const uint8_t *b, int n, uint32_t ip, int port)
{
    if (n >= 5 && b[0] == 'S' && b[1] == 'N' && b[3] == T_JOIN && z->mode == NET_HOST) {
        /* a station of the 'S' 'N' wire joining: its REJECT in its own wire ("the host takes no one more") */
        const uint8_t r[5] = { 'S', 'N', 3, T_REJECT, 0 };
        udp_send(ip, port, r, 5);
        nlog("a station of another wire ('S' 'N') from %lu.%lu.%lu.%lu:%d turned away", (unsigned long)(ip >> 24),
             (unsigned long)(ip >> 16 & 255), (unsigned long)(ip >> 8 & 255), (unsigned long)(ip & 255), port);
        return;
    }
    if (n < 5 || b[0] != 'A' || b[1] != 'S' || b[2] != NC_VER) return;
    const int type = b[3];
    const uint8_t from = b[4];
    const uint8_t *p = b + 5;
    const int len = n - 5;
    if (z->mode == NET_HOST) {
        if (type == T_JOIN) {
            int s = peer_of(z, ip, port);
            uint8_t r[8];
            if (s < 0) {
                if (z->n >= NET_MAX || z->open != 1 || z->locked || (s = free_slot(z)) < 0) {
                    udp_send(ip, port, r, head(z, r, T_REJECT));
                    nlog("a station from %lu.%lu.%lu.%lu:%d turned away (%d there%s)", (unsigned long)(ip >> 24),
                         (unsigned long)(ip >> 16 & 255), (unsigned long)(ip >> 8 & 255), (unsigned long)(ip & 255), port,
                         z->n, z->locked ? ", a championship runs" : "");
                    return;
                }
                memset(&z->peer[s], 0, sizeof z->peer[s]);
                memset(&z->st[s], 0, sizeof z->st[s]);
                z->peer[s].ip = ip; z->peer[s].port = port;
                memset(z->seen[s], 0, sizeof z->seen[s]); z->seen_i[s] = 0;
                member_add(z, (uint8_t)s);
                nlog("station %d joined (%lu.%lu.%lu.%lu:%d), %d stations", s, (unsigned long)(ip >> 24),
                     (unsigned long)(ip >> 16 & 255), (unsigned long)(ip >> 8 & 255), (unsigned long)(ip & 255), port, z->n);
            }
            z->peer[s].last = net_ms();
            int o = head(z, r, T_WELCOME);
            r[o++] = (uint8_t)s;
            udp_send(ip, port, r, o);
            send_list(z);
            return;
        }
        int s = peer_of(z, ip, port);
        if (s < 0 || from != s) return;
        z->peer[s].last = net_ms();
    } else {
        if (ip != z->hip || port != z->hport) return;
        z->peer[0].last = net_ms();
    }
    switch (type) {
    case T_WELCOME: if (len >= 1 && z->mode == NET_JOIN) z->self = p[0]; break;
    case T_REJECT:
        if (z->mode == NET_JOIN && z->self == 0xff) { z->open = 0; snprintf(z->why, sizeof z->why, "the host takes no one more"); }
        break;
    case T_LIST:
        if (z->mode == NET_JOIN && len >= 1 && p[0] <= NET_MAX && len >= 1 + p[0]) {
            z->n = 0;
            for (int i = 0; i < p[0]; i++) member_add(z, p[1 + i]);
        }
        break;
    case T_ACK:
        if (len >= 2)
            for (int i = 0; i < (int)(sizeof z->pend / sizeof z->pend[0]); i++)
                if (z->pend[i].used && z->pend[i].seq == rd16(p) && (z->mode == NET_JOIN || z->pend[i].to == from)) z->pend[i].used = 0;
        break;
    case T_MSG: {
        if (len < 6) break;
        const uint8_t ofrom = p[0], to = p[1];
        const uint16_t seq = (uint16_t)rd16(p + 2);
        const int pl = (int)rd16(p + 4);
        if (pl > len - 6 || pl > NET_PAY) break;
        if (seq) {
            uint8_t a[8];
            int o = head(z, a, T_ACK);
            wr16(a + o, seq);
            send_peer(z, z->mode == NET_JOIN ? 0 : from, a, o + 2);
            if (seen(z, from, seq)) break;
        }
        if (z->self != 0xff && ofrom != z->self && (to == 0xff || to == z->self)) queue_msg(z, ofrom, p + 6, pl);
        if (z->mode == NET_HOST && (to == 0xff || to != z->self))
            for (int i = 0; i < z->n; i++) {
                const uint8_t t = z->slot[i];
                if (t != z->self && t != from && (to == 0xff || to == t)) send_msg(z, t, ofrom, to, seq != 0, p + 6, pl);
            }
        break;
    }
    case T_STATES: {
        int o = 0;
        while (o + 2 <= len) {
            const uint8_t sl = p[o];
            const int sz = p[o + 1];
            if (o + 2 + sz > len || sz > NET_SMAX) break;
            if (sl != z->self) set_state(z, sl, p + o + 2, sz, ++z->state_serial);
            o += 2 + sz;
        }
        break;
    }
    case T_PING:
        if (z->mode == NET_HOST && len >= 4) {
            uint8_t r[16];
            int o = head(z, r, T_PONG);
            memcpy(r + o, p, 4);
            wr32(r + o + 4, net_ms());
            send_peer(z, from, r, o + 8);
        }
        break;
    case T_PONG: if (z->mode == NET_JOIN && len >= 8) clock_sample(z, rd32(p), rd32(p + 4)); break;
    case T_LOCK:
        if (z->mode == NET_HOST && len >= 1 && z->n && from == z->slot[0] && z->locked != (p[0] != 0)) {
            z->locked = p[0] != 0;
            nlog("the session %s", z->locked ? "locked (a championship runs)" : "open again");
        }
        break;
    case T_BYE:
        if (z->mode == NET_HOST) {
            z->peer[from].bye = 1;
            member_del(z, from);
            send_list(z);
            nlog("station %d left, %d stations", from, z->n);
        } else { z->n = 0; member_add(z, z->self); }       /* the host gone: everyone else too */
        break;
    default: break;
    }
}

void net_pump(void)
{
    netall *z = ZZ();
    if (!z || !z->open) return;
    uint32_t t = net_ms();
    if (z->last_pump && t - z->last_pump > 3000)    /* (the others drop a station silent for NC_PEER_MS) */
        nlog("%lu ms without the network", (unsigned long)(t - z->last_pump));
    if (t - z->last_pump < 2) return;
    z->last_pump = t;
    static uint8_t b[1500];
    uint32_t ip;
    int port, r;
    while (z->open && (r = udp_recv(b, sizeof b, &ip, &port)) > 0) handle(z, b, r, ip, port);
    t = net_ms();
    for (int i = 0; i < (int)(sizeof z->pend / sizeof z->pend[0]); i++)
        if (z->pend[i].used && t - z->pend[i].t >= NC_RESEND_MS) {
            if (++z->pend[i].tries > NC_TRIES) { z->pend[i].used = 0; continue; }
            z->pend[i].t = t;
            send_peer(z, z->pend[i].to, z->pend[i].d, z->pend[i].len);
        }
    if (z->mode == NET_HOST) {
        for (int i = 0; i < z->n; i++) {
            const uint8_t s = z->slot[i];
            if (s != z->self && t - z->peer[s].last > NC_PEER_MS) {
                nlog("station %d does not answer any more", s);
                member_del(z, s); send_list(z); i--;
            }
        }
        if (t - z->last_bundle >= NET_STATE_MS) {          /* the others' latest states to each guest */
            z->last_bundle = t;
            for (int g = 0; g < z->n; g++) {
                const uint8_t dst = z->slot[g];
                if (dst == z->self) continue;
                static uint8_t o8[1400];
                int o = head(z, o8, T_STATES), any = 0;
                for (int i = 0; i < z->n; i++) {
                    const uint8_t s = z->slot[i];
                    if (s == dst || !z->st[s].valid || t - z->st[s].t > NC_OLD_MS) continue;
                    o8[o++] = s; o8[o++] = (uint8_t)z->st[s].len;
                    memcpy(o8 + o, z->st[s].d, z->st[s].len); o += z->st[s].len;
                    any = 1;
                }
                if (any) send_peer(z, dst, o8, o);
            }
        }
        if (t - z->last_list >= 1000) send_list(z);         /* the list: also a sign of life */
        if (z->locked && !z->has_self && !z->n) { z->locked = 0; nlog("the session open again (no one left)"); }
    } else if (z->mode == NET_JOIN && z->self != 0xff) {
        if (t - z->peer[0].last > NC_PEER_MS && z->n > 1) {
            nlog("the host does not answer any more");
            z->n = 0; member_add(z, z->self);
        }
        if (t - z->last_ping >= (z->clk_n < 8 ? 250u : 1000u)) {
            uint8_t p[12];
            int o = head(z, p, T_PING);
            z->last_ping = t;
            wr32(p + o, t);
            send_peer(z, 0, p, o + 4);
        }
    }
}

int net_host_port = NET_PORT;                  /* (the server's --port) */
static int session_open(netall *z, int mode, int has_self, const char *host)
{
    memset(z->peer, 0, sizeof z->peer); memset(z->st, 0, sizeof z->st); memset(z->pend, 0, sizeof z->pend);
    memset(z->seen, 0, sizeof z->seen);
    z->qh = z->qn = 0; z->n = 0; z->self = 0xff; z->locked = 0; z->clk_ok = 0; z->clk_n = z->clk_i = 0;
    z->mode = mode; z->has_self = mode == NET_HOST && has_self; z->open = 0;
    if (mode == NET_HOST) {
        if (udp_open(net_host_port)) return -1;
        z->open = 1;
        if (z->has_self) { z->self = 0; member_add(z, 0); }
        nlog("hosting on UDP port %d", net_host_port);
        return 0;
    }
    char name[128];
    snprintf(name, sizeof name, "%s", host ? host : "");
    int port = NET_PORT;
    char *c = strrchr(name, ':');
    if (c) { *c = 0; port = atoi(c + 1); }
    for (char *s = name; *s; s++) if (*s == ' ') { *s = 0; if (atoi(s + 1) > 0) port = atoi(s + 1); break; }
    if (!name[0]) { snprintf(z->why, sizeof z->why, "no host given (NETHOST)"); return -1; }
    if (udp_open(0)) return -1;
    if (udp_resolve(name, &z->hip)) { snprintf(z->why, sizeof z->why, "the host %s not found", name); udp_close(); return -1; }
    z->hport = port; z->open = 1;
    uint32_t t0 = net_ms(), last = 0;
    while (z->self == 0xff && z->open && net_ms() - t0 < 5000) {   /* JOIN until WELCOME (5 s) */
        if (net_ms() - last >= 300) {
            uint8_t j[8];
            udp_send(z->hip, z->hport, j, head(z, j, T_JOIN));
            last = net_ms();
        }
        z->last_pump = 0;
        net_pump();
    }
    if (z->self == 0xff) {
        if (!z->why[0]) snprintf(z->why, sizeof z->why, "no answer from %s:%d", name, port);
        z->open = 0; udp_close();
        return -1;
    }
    z->peer[0].last = net_ms();
    nlog("joined %s:%d as station slot %d", name, port, z->self);
    return 0;
}

#ifdef NET_SERVER
int net_host_server(void) { netall *z = ZZ(); return session_open(z, NET_HOST, 0, NULL); }
int net_server_count(void) { return ZZ()->n; }
void net_server_stop(void)
{
    netall *z = ZZ();
    uint8_t b[8];
    send_all(z, b, head(z, b, T_BYE));
    z->open = 0;
    udp_close();
}
#endif

/* at the program's end: BYE, the socket shut, bsdsocket.library closed -- a socket
   left open past the program's end leaves the TCP/IP stack with a task that is gone */
static void net_atexit(void)
{
    net_close();
#if defined(AMIGA) && !defined(AMIGA_NULL)
    if (SocketBase) { CloseLibrary(SocketBase); SocketBase = NULL; }
#endif
}

int net_start(void)
{
    netall *z = ZZ();
    if (!z) return -1;
    static int exit_set;
    if (!exit_set) { exit_set = 1; atexit(net_atexit); }
    if (z->open) return 0;                                  /* (still in a session: from the part before) */
    z->why[0] = 0;
    const char *m = getenv("OS_NETMODE"), *h = getenv("OS_NETHOST");
    int mode = !m ? NET_OFF : !strcmp(m, "host") ? NET_HOST : !strcmp(m, "join") ? NET_JOIN : NET_OFF;
    if (mode == NET_OFF) { snprintf(z->why, sizeof z->why, "no network set (NETMODE / --host / --join)"); return -1; }
    if (session_open(z, mode, 1, h)) { (nlog)("%s", z->why); return -1; }
    return 0;
}
int net_mode(void) { netall *z = ZZ(); return z && z->open ? z->mode : NET_OFF; }
int net_on(void) { netall *z = ZZ(); return z && z->open && z->self != 0xff; }
const char *net_why(void) { netall *z = ZZ(); return z ? z->why : "no memory"; }
void net_close(void)
{
    netall *z = ZZ();
    if (!z || !z->open) return;
    uint8_t b[8];
    send_all(z, b, head(z, b, T_BYE));
    z->open = 0;
    udp_close();
    nlog("session closed");
}
int net_count(void) { netall *z = ZZ(); return z && z->open ? z->n : 0; }
uint8_t net_slot_at(int i) { netall *z = ZZ(); return z && i >= 0 && i < z->n ? z->slot[i] : 0xff; }
int net_index(uint8_t s) { netall *z = ZZ(); return z ? slot_index(z, s) : -1; }
int net_self(void) { netall *z = ZZ(); return z ? z->self : 0xff; }
int net_me(void) { netall *z = ZZ(); return z ? slot_index(z, z->self) : -1; }
int net_send(uint8_t to, int reliable, const void *p, int len)
{
    netall *z = ZZ();
    if (!z || !z->open || len > NET_PAY) return -1;
    if (z->mode == NET_JOIN) send_msg(z, 0, z->self, to, reliable, p, len);
    else for (int i = 0; i < z->n; i++) {                   /* the host: straight to each */
        const uint8_t t = z->slot[i];
        if (t != z->self && (to == 0xff || to == t)) send_msg(z, t, z->self, to, reliable, p, len);
    }
    return 0;
}
int net_recv(uint8_t *from, void *p, int max)
{
    netall *z = ZZ();
    if (!z || !z->qn) return 0;
    const int k = z->qh;
    z->qh = (z->qh + 1) % NC_QUEUE; z->qn--;
    int n = z->q[k].len < max ? z->q[k].len : max;
    *from = z->q[k].from;
    memcpy(p, z->q[k].d, (size_t)n);
    return n;
}
void net_state_send(const void *p, int len)
{
    netall *z = ZZ();
    if (!z || !z->open || z->self == 0xff || len > NET_SMAX) return;
    const uint32_t t = net_ms();
    if (t - z->last_state_tx < NET_STATE_MS) return;
    z->last_state_tx = t;
    net_state_force(p, len);
}
void net_state_force(const void *p, int len)
{
    netall *z = ZZ();
    if (!z || !z->open || z->self == 0xff || len > NET_SMAX) return;
    if (z->mode == NET_HOST) { set_state(z, z->self, p, len, ++z->state_serial); return; }   /* (bundled from here) */
    uint8_t b[NET_SMAX + 16];
    int o = head(z, b, T_STATES);
    b[o++] = z->self; b[o++] = (uint8_t)len;
    memcpy(b + o, p, (size_t)len); o += len;
    send_peer(z, 0, b, o);
}
const uint8_t *net_state(uint8_t s, int *len, uint32_t *rx, uint32_t *serial)
{
    netall *z = ZZ();
    if (!z || !z->st[s].valid) return NULL;
    if (len) *len = z->st[s].len;
    if (rx) *rx = z->st[s].rx;
    if (serial) *serial = z->st[s].serial;
    return z->st[s].d;
}
void net_states_clear(void)
{
    netall *z = ZZ();
    if (z) memset(z->st, 0, sizeof z->st);
}
int net_clock(uint32_t *ms)
{
    netall *z = ZZ();
    if (!z || z->mode == NET_HOST || !z->open) { *ms = net_ms(); return 1; }
    *ms = net_ms() + (uint32_t)z->clk_off;
    return z->clk_ok;
}
void net_lock(int on)
{
    netall *z = ZZ();
    if (!z || !z->open) return;
    if (z->mode == NET_HOST) { z->locked = on; return; }
    uint8_t b[8];
    int o = head(z, b, T_LOCK);
    b[o++] = (uint8_t)(on != 0);
    send_peer(z, 0, b, o);
}
