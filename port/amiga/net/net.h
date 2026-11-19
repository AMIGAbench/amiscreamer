/*
 * net.h - THE NETWORK GAME's transport (Amiga build only): UDP over the TCP/IP stack (bsdsocket.library; the qemu
 * test: POSIX sockets), a star round one host --
 * a playing game (--host / NETMODE=HOST) or amiscreamer_server -- that passes everything on.  Its types
 * and fields under AmiScreamer's own mark ('A' 'S', version 1): programs of the 'S' 'N' 3 wire are turned away.
 *  - members by slot (the host's own station slot 0, the server has none); stations = the members in slot order;
 *  - messages (the lobby's, the results'): to one slot or all, reliable ones acknowledged and sent again;
 *  - race states: the station's own, at most every NET_STATE_MS, the host bundles the others' latest for each guest;
 *  - one clock for all (the host's; guests by PING/PONG, the fastest of the last exchanges).
 * Its state lives in memory that outlives the program's parts (os_slot), the socket too.
 */
#ifndef OS_NET_H
#define OS_NET_H
#include <stdint.h>

#define NET_MAX      8          /* stations (the original's network cars: 8) */
#define NET_PORT     10623
#define NET_STATE_MS 30
#define NET_PAY      240        /* a message's largest payload */
#define NET_SMAX     0x60       /* a race state (head 0xc, data 0x4c, two clocks) */
enum { NET_OFF = 0, NET_HOST = 1, NET_JOIN = 2 };

int  net_start(void);           /* from OS_NETMODE / OS_NETHOST: 0 = a session (joined or hosting), -1 = none */
int  net_mode(void);            /* NET_OFF / NET_HOST / NET_JOIN */
int  net_on(void);              /* a session that has its own station */
void net_pump(void);            /* receive, resend, bundle; often (it asks the stack at most every 2 ms) */
void net_close(void);           /* BYE, the socket shut */
int  net_count(void);           /* stations */
uint8_t net_slot_at(int i);     /* the i-th station's slot */
int  net_index(uint8_t slot);   /* a slot's station number, -1 = gone */
int  net_self(void);            /* own slot (0xff: none yet) */
int  net_me(void);              /* own station number */
const char *net_why(void);      /* why there is no session */
/* messages: to = a slot or 0xff (all others); 0 = queued */
int  net_send(uint8_t to, int reliable, const void *p, int len);
int  net_recv(uint8_t *from, void *p, int max);      /* length, 0 = none */
/* race states */
void net_state_send(const void *p, int len);         /* at most every NET_STATE_MS */
void net_state_force(const void *p, int len);        /* now (the start's barrier) */
const uint8_t *net_state(uint8_t slot, int *len, uint32_t *rx_ms, uint32_t *serial);   /* latest, NULL = none */
void net_states_clear(void);    /* every station's state forgotten (a new race: none of the last one's taken) */
int  net_clock(uint32_t *ms);   /* the shared clock (ms); 0 = not yet known (a guest) */
uint32_t net_ms(void);          /* this machine's clock (ms) */
void net_lock(int on);          /* station 0: no new stations (a championship runs) */

#endif
