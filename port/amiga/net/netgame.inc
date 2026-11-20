/*
 * netgame.inc - THE NETWORK GAME -- the original's own network game (game mode 0x10), its screens and its order of
 * things; main.c includes this in the Amiga builds only.
 *
 *  - NETWORK GAME -> the name -> the car -> THE PLAYERS' LIST (0x2d7c4, netH/L.pcx): the menu's texts 48 / 51 / 52,
 *    each station's name with its car's picture (the menu sprite car + 0x10), the own one first, two columns.  The
 *    lobby records are the original's (0x12099c + station * 0x38: champ word, command, station, name, car, track,
 *    laps, difficulty, flags, 0x11d230, address), little-endian on the wire.
 *  - ENTER (two stations or more) -> command 2 three times; station 0 draws the station that picks the track
 *    (0x107fd & 7) and tells it (0x8844, reliable).  NOBODY STAYS ON THE LIST: the picker goes to the track screen
 *    (sending 3 = its track and 0x8844 every picture), every other station to the STAND-BY screen (0x120994 = 1:
 *    menu3h/l.pcx, texts 45 / 49, the picker's name and the track it has on its screen, live; sending 0x8844 every
 *    picture; ESC does nothing there).  The picker's ENTER: command 4 (track, laps, difficulty, flags) -> all race.
 *  - The race (0x2a558, race_load): the loading picture; no computer opponents, the stations' grid places; three
 *    start barriers as the original's net_exchange(0x50) (one after the cars are set up, the loading picture still
 *    up; two on the black screen before the loop): each waits for a state of that round from every station still
 *    there (a station silent for 0x50 * 0.8 s is given up, the others still awaited); then station 0 sets the
 *    countdown's start on the shared clock and every station's countdown is that clock (the same moment
 *    everywhere).  Each station drives its own car (handicap 0x10d6e0), sends its state; the others' cars are drawn
 *    from theirs (predicted, the error faded, snapped beyond 3000), bumped into both ways (player2.c: the hitter
 *    moves itself out and tells the other through its flags), counted in the standings; one race clock for all
 *    (net_clock_apply: from the earliest start, the finish line's crossing interpolated).  A finisher waits on the
 *    end display (text 23) until every other station is in or gone.
 *  - After it: THE FINAL RESULTS (champ5h/l.pcx, text 50, "\x01n. NAME MM.SS.CC \x02CAR", built once), RETURN /
 *    ESC; a single race ends the session BEFORE the page (back to the main menu), a championship sends its
 *    result (command 5) AFTER the page and goes back to the list with its table.
 *  - Championship: station 0 switches with LEFT / RIGHT, tracks 1..6 forward, station
 *    0's laps / difficulty / flags, 10-8-6-5-4-3-2-1, ties shared, no late joining (T_LOCK every second),
 *    leavers keep their points; its state in station 0's word +0x00, the results as command 5.
 * Its state outlives the program's parts (os_slot 13); the transport is amiga/net/net.c.
 */
#include "net.h"

#define NG_PAGE 11
enum { C_HERE = 0, C_LEAVE = 1, C_START = 2, C_TRACK = 3, C_GO = 4, C_RESULT = 5, C_PICKER = 0x8844, C_RACE = 0x1234 };
static const int ng_points[8] = { 10, 8, 6, 5, 4, 3, 2, 1 };
static const int ng_lapv[4] = { 3, 5, 10, 25 };

typedef struct { uint32_t champ, cmd, station; char name[4]; uint32_t car, track, laps, diff, flags, x24; uint8_t addr[16]; } ng_rec;
typedef struct { uint8_t slot; char name[4]; int pts, left, place[6], got, pos; float time; } ng_ch;

typedef struct {
    ng_rec rec[256];                /* the stations' last records, by slot */
    int my_car, my_flags;           /* the own car; the picture cheats on (0x30: MIRRO / UPDOW) */
    int phase;                      /* 0 the list, 1 waiting for the picker's number, 2 STAND-BY, 3 picking, 4 go */
    int picker, picker_seen;        /* the picking station's number; its track heard (command 3) */
    uint8_t picker_slot;
    int track, laps, diff, flags;   /* the race's (track 0..11 as the menu's pick; diff the menu's 0..3) */
    int race, pending, back;
    uint8_t rs[NET_MAX]; int rn;    /* the race's stations (slots), grid order */
    uint8_t race_no;                /* the race's number (its states carry it: an older race's are never taken) */
    uint32_t here_t, lock_t;
    int ch_on, ch_races, chn;       /* championship */
    uint32_t ch_results_t;          /* the own result reported (net_ms; 0 = not yet): 60 s from then */
    ng_ch ch[NET_MAX];
    struct { uint8_t slot; int got, fin; float time; } res[NET_MAX];   /* the last race's results */
    int resn;
    int shot_lobby, shot_standby, shot_champ;   /* (OS_NETSHOTDIR: written; shot_champ a bit a race) */
} ng_keep;

static ng_keep *NG(void)
{
    ng_keep *k = os_slot(13);
    if (!k && (k = os_keep_calloc(1, sizeof *k))) os_slot_set(13, k);
    return k;
}

static void wle(uint8_t *p, uint32_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24); }
static uint32_t rle(const uint8_t *p) { return p[0] | p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static uint32_t fbits(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }
static float bitsf(uint32_t u) { float f; memcpy(&f, &u, 4); return f; }

static const char *ng_name(uint8_t slot)
{
    if (slot == net_self()) return g_save.name;
    ng_keep *k = NG();
    return k->rec[slot].name[0] ? k->rec[slot].name : "???";
}
static int ng_car_of(uint8_t slot) { return slot == net_self() ? NG()->my_car : (int)NG()->rec[slot].car; }

/* (OS_NETSHOTDIR=<dir>: the test's pictures, each once) */
static void ng_shot(const char *what)
{
    const char *d = getenv("OS_NETSHOTDIR");
    if (!d) return;
    char f[256];
    int me = net_me();
    if (NG()->race) for (int i = 0; i < NG()->rn; i++) if (NG()->rs[i] == net_self()) me = i;
    if (me <= 0) snprintf(f, sizeof f, "%s/%s.ppm", d, what);
    else snprintf(f, sizeof f, "%s/%s_s%d.ppm", d, what, me);
    write_ppm(f);
    printf("net: picture %s\n", f);
}

/* the own record (0x2dddc net_fill) on the wire: 0xc + 0x74 bytes, as the original sends */
static void ng_send(uint32_t cmd, int reliable, uint32_t track, uint32_t x18, uint32_t x1c)
{
    ng_keep *k = NG();
    uint8_t b[0x80];
    memset(b, 0, sizeof b);
    wle(b + 0, net_me() == 0 ? (uint32_t)(k->ch_on | k->ch_races << 8) : 0);
    wle(b + 4, cmd);
    wle(b + 8, (uint32_t)net_me());
    memcpy(b + 0xc, g_save.name, 3);
    wle(b + 0x10, (uint32_t)k->my_car);
    wle(b + 0x14, track);
    wle(b + 0x18, x18 != 0xffffffffu ? x18 : (uint32_t)ng_lapv[g_opt_laps & 3]);
    wle(b + 0x1c, x1c != 0xffffffffu ? x1c : (uint32_t)g_opt_diff);
    wle(b + 0x20, cmd == C_GO ? (uint32_t)k->flags : (uint32_t)((k->my_flags & 0x30) | (k->track > 5 ? 8 : 0)));   /* 0x11d274 */
    wle(b + 0x24, 0x100u | k->race_no);                     /* 0x11d230 (nonzero), its low byte the race's number */
    b[0x28] = (uint8_t)net_self(); b[0x29] = 'S';
    net_send(0xff, reliable, b, sizeof b);
}
static void ng_store(uint8_t from, const uint8_t *b, int n)
{
    if (n < 0x38) return;
    ng_rec *r = &NG()->rec[from];
    r->champ = rle(b); r->cmd = rle(b + 4); r->station = rle(b + 8);
    memcpy(r->name, b + 0xc, 3); r->name[3] = 0;
    r->car = rle(b + 0x10); r->track = rle(b + 0x14); r->laps = rle(b + 0x18); r->diff = rle(b + 0x1c);
    r->flags = rle(b + 0x20); r->x24 = rle(b + 0x24); memcpy(r->addr, b + 0x28, 16);
}
static void ng_store_id(uint8_t from, const uint8_t *b, int n)   /* every message carries its sender's name and car */
{
    if (n < 0x38 || from == net_self()) return;
    ng_rec *r = &NG()->rec[from];
    memcpy(r->name, b + 0xc, 3); r->name[3] = 0;
    r->car = rle(b + 0x10);
    if (rle(b + 0x24) & 0x100) r->x24 = rle(b + 0x24);
}
static void ng_lock_pump(void)                   /* netchamp.c lock_pump: station 0 repeats T_LOCK every second */
{
    ng_keep *k = NG();
    if (!net_on() || net_me() != 0 || !k->ch_on || !k->ch_races) return;
    if (net_ms() - k->lock_t >= 1000) { k->lock_t = net_ms(); net_lock(1); }
}

/* ---------------------------------------------------------------- the championship */
static void ch_new(void)
{
    ng_keep *k = NG();
    k->ch_races = 0; k->chn = net_count(); k->ch_results_t = 0;
    for (int i = 0; i < k->chn; i++) {
        memset(&k->ch[i], 0, sizeof k->ch[i]);
        k->ch[i].slot = net_slot_at(i);
        snprintf(k->ch[i].name, sizeof k->ch[i].name, "%s", ng_name(net_slot_at(i)));
        k->ch[i].got = 2; k->ch[i].pos = i + 1;
    }
}
static void ch_reset(void)
{
    ng_keep *k = NG();
    k->ch_races = 0; k->chn = 0; k->ch_results_t = 0;
}
static int ch_results_complete(void)            /* every expected one in, or 60 s after the own result (nch_own_result) */
{
    ng_keep *k = NG();
    if (!k->ch_races) return 1;
    for (int c = 0; c < k->chn; c++)
        if (k->ch[c].got == 0 && !k->ch[c].left && net_index(k->ch[c].slot) >= 0)
            return k->ch_results_t && net_ms() - k->ch_results_t > 60000;
    return 1;
}
/* the order: points, then more 1st places, more 2nd, ... 8th, then the last race's place (not in = behind); 0 = equal */
static int ch_cmp(const ng_ch *a, const ng_ch *b, int races)
{
    if (a->pts != b->pts) return a->pts > b->pts ? -1 : 1;
    for (int p = 1; p <= 8; p++) {
        int na = 0, nb = 0;
        for (int q = 0; q < races; q++) { na += a->place[q] == p; nb += b->place[q] == p; }
        if (na != nb) return na > nb ? -1 : 1;
    }
    if (races > 0) {
        const int pa = a->place[races - 1], pb = b->place[races - 1];
        if (pa != pb) return pa < pb ? -1 : 1;
    }
    return 0;
}
static void ch_score(void)                     /* the race's points, once all results are in (or the time is up) */
{
    ng_keep *k = NG();
    int ord[NET_MAX], n = 0;
    for (int c = 0; c < k->chn; c++) if (k->ch[c].got == 1) ord[n++] = c;
    for (int a = 0; a < n; a++) for (int b = a + 1; b < n; b++) {      /* by time; the same time: the smaller slot first */
        const ng_ch *A = &k->ch[ord[a]], *B = &k->ch[ord[b]];
        if (B->time < A->time || (B->time == A->time && B->slot < A->slot)) { const int t = ord[a]; ord[a] = ord[b]; ord[b] = t; }
    }
    const int r = k->ch_races - 1;
    for (int c = 0; c < k->chn; c++) k->ch[c].place[r] = 99;
    for (int j = 0; j < n; j++) { k->ch[ord[j]].pts += ng_points[j < 8 ? j : 7]; k->ch[ord[j]].place[r] = j + 1; }
    for (int c = 0; c < k->chn; c++) { if (net_index(k->ch[c].slot) < 0) k->ch[c].left = 1; k->ch[c].got = 2; }
    for (int a = 0; a < k->chn; a++)
        for (int b = a + 1; b < k->chn; b++)
            if (ch_cmp(&k->ch[b], &k->ch[a], k->ch_races) < 0) { const ng_ch t = k->ch[a]; k->ch[a] = k->ch[b]; k->ch[b] = t; }
    for (int c = 0; c < k->chn; c++)                /* only those equal in everything share a place */
        k->ch[c].pos = c > 0 && !ch_cmp(&k->ch[c], &k->ch[c - 1], k->ch_races) ? k->ch[c - 1].pos : c + 1;
    printf("net: championship after race %d:", k->ch_races);
    for (int c = 0; c < k->chn; c++) printf("  %d. %s %d pts%s", k->ch[c].pos, k->ch[c].name, k->ch[c].pts, k->ch[c].left ? " (left)" : "");
    printf("\n");
}
static void ch_race_begins(int races)            /* a championship race starts: its results awaited */
{
    ng_keep *k = NG();
    if (!k->ch_races && !k->chn) ch_new();
    k->ch_races = races;
    k->ch_results_t = 0;
    for (int c = 0; c < k->chn; c++) if (!k->ch[c].left) k->ch[c].got = 0;
}
static void ng_take_result(uint8_t from, const uint8_t *b, int n)   /* command 5 */
{
    ng_keep *k = NG();
    if (n < 0x38 || rle(b + 4) != C_RESULT) return;
    for (int c = 0; c < k->chn; c++)
        if (k->ch[c].slot == from && (int)rle(b + 0x1c) == k->ch_races - 1 && k->ch[c].got != 2) {
            k->ch[c].got = rle(b + 0x18) ? 1 : 3; k->ch[c].time = bitsf(rle(b + 0x14));
        }
}
/* nch_on_packet: everyone follows station 0's word (+0x00: bit 0 on, bits 8-15 the races started) in every packet */
static void ng_word(uint8_t from, const uint8_t *b)
{
    ng_keep *k = NG();
    if (from == net_self() || net_index(from) != 0) return;
    const uint32_t w = rle(b);
    const int on = (int)(w & 1), races = (int)(w >> 8 & 0xff);
    if (k->ch_on && !on && k->ch_races) ch_reset();         /* (station 0 turned it off: over) */
    k->ch_on = on;
    if (on && races > k->ch_races && races <= 6) ch_race_begins(races);
}
/* what every receiving loop does with a message besides its own: the word, the results */
static void ng_common(uint8_t from, const uint8_t *b, int n)
{
    if (n < 0x38) return;
    ng_store_id(from, b, n);
    ng_word(from, b);
    if (rle(b + 4) == C_RESULT) ng_take_result(from, b, n);
}

/* ---------------------------------------------------------------- the list */
static void ng_race_list(void)                  /* the stations there now, grid order */
{
    ng_keep *k = NG();
    k->rn = net_count();
    for (int i = 0; i < k->rn; i++) k->rs[i] = net_slot_at(i);
}
static void ng_take_go(const uint8_t *b)        /* command 4: the picker's record is the race's */
{
    ng_keep *k = NG();
    k->track = (int)rle(b + 0x14); k->laps = (int)rle(b + 0x18); k->diff = (int)rle(b + 0x1c); k->flags = (int)rle(b + 0x20);
    if (k->track < 0 || k->track > 11) k->track = 0;
    if (k->diff < 0 || k->diff > 3) k->diff = 1;
    if (rle(b + 0x24) & 0xff) k->race_no = (uint8_t)rle(b + 0x24);
    k->phase = 4;
}
static uint8_t ng_next_race_no(void)            /* the race's number: one more than any known */
{
    ng_keep *k = NG();
    int m = k->race_no;
    for (int i = 0; i < net_count(); i++) {
        const uint8_t s = net_slot_at(i);
        if (s != net_self() && k->rec[s].x24 & 0x100) {
            const int v = (int)(k->rec[s].x24 & 0xff);
            if ((uint8_t)(v - m) < 128) m = v;
        }
    }
    m = (m + 1) & 0xff;
    return (uint8_t)(m ? m : 1);
}
static void ng_pick_done(int picker)            /* the picker known: STAND-BY, or pick */
{
    ng_keep *k = NG();
    k->picker = picker; k->picker_slot = net_slot_at(picker);
    if (picker != net_me()) {                   /* (menu_pages.c ~575: 0x120994 = 1, sfx 7) */
        k->phase = 2; k->picker_seen = 0;
        if (k->rec[k->picker_slot].name[0] && k->rec[k->picker_slot].track < 12) k->track = (int)k->rec[k->picker_slot].track;
        snd_play(7);
        return;
    }
    if (k->ch_on) {                             /* championship: no picking, track k forward, station 0's options */
        if (!k->ch_races) { ch_new(); net_lock(1); k->lock_t = net_ms(); }
        k->track = k->ch_races; k->laps = ng_lapv[g_opt_laps & 3]; k->diff = g_opt_diff; k->flags = k->my_flags & 0x30;
        k->race_no = ng_next_race_no();
        ch_race_begins(k->ch_races + 1);
        ng_send(C_TRACK, 0, (uint32_t)k->track, (uint32_t)k->laps, (uint32_t)k->diff);
        ng_send(C_GO, 1, (uint32_t)k->track, (uint32_t)k->laps, (uint32_t)k->diff);
        k->phase = 4;
        return;
    }
    if (k->track < 0 || k->track > 11) k->track = 0;
    k->phase = 3;                               /* the track screen (menu_goto(3)) */
}
static int ng_draw_picker(void)                 /* station 0 (0x2d8f7): r = the timer & 7, within the stations */
{
    int r = (int)(SDL_GetTicks() / 10 & 7);
    if (r >= net_count()) r = net_count() - ((r & 1) + 1);
    if (r < 0) r = 0;
    if (NG()->ch_on) r = 0;
    return r;
}

/* each picture of the list / STAND-BY: 1 = the race starts, 2 = this station picks the track, -1 = leave */
static int ng_lobby_pump(void)
{
    ng_keep *k = NG();
    net_pump();
    if (!net_on()) return -1;
    ng_lock_pump();
    if (k->phase == 0 && net_ms() - k->here_t >= 200) { k->here_t = net_ms(); ng_send(C_HERE, 0, (uint32_t)k->track, 0xffffffffu, 0xffffffffu); }
    if (k->phase == 2) ng_send(C_PICKER, 0, (uint32_t)k->picker, 0xffffffffu, 0xffffffffu);    /* (STAND-BY: every picture) */
    uint8_t from, b[NET_PAY];
    int n, out = 0;
    while ((n = net_recv(&from, b, sizeof b)) > 0) {
        if (n < 0x38) continue;
        const uint32_t cmd = rle(b + 4);
        ng_common(from, b, n);
        if (k->phase == 2) {                    /* STAND-BY: only the picker's */
            if (from != k->picker_slot) continue;
            if (cmd == C_TRACK) { ng_store(from, b, n); k->track = (int)rle(b + 0x14); k->picker_seen = 1; }
            else if (cmd == C_LEAVE) return -1;
            else if (cmd == C_GO) { ng_store(from, b, n); ng_take_go(b); break; }
            continue;
        }
        if (cmd == C_HERE) { ng_store(from, b, n); continue; }
        if (cmd == C_LEAVE) { memset(&k->rec[from], 0, sizeof k->rec[from]); continue; }
        if (cmd == C_START && k->phase == 0) {
            if (net_me() == 0) {
                const int r = ng_draw_picker();
                ng_send(C_PICKER, 1, (uint32_t)r, 0xffffffffu, 0xffffffffu);
                ng_pick_done(r);
                if (k->phase == 3) { out = 2; break; }
            } else k->phase = 1;
        } else if (cmd == C_PICKER && k->phase == 1) {           /* (any 0x8844 carries the picker) */
            const int r = (int)rle(b + 0x14);
            if (r >= 0 && r < net_count()) {
                ng_pick_done(r);
                if (k->phase == 3) { out = 2; break; }
            }
        } else if (cmd == C_TRACK && net_count() <= 1 && k->phase == 0) {
            return -1;
        } else if (cmd == C_GO && (k->phase == 1 || (k->ch_on && k->phase == 0)) && net_index(from) >= 0) {
            ng_store(from, b, n); ng_take_go(b); break;
        }
    }
    if (k->ch_races && ch_results_complete()) {
        int any = 0;
        for (int c = 0; c < k->chn; c++) if (k->ch[c].got != 2) any = 1;
        if (any) ch_score();
    }
    if (k->phase == 4) { ng_race_list(); k->phase = 0; return 1; }
    return out;
}

/* the list (0x2d7c4) or the STAND-BY screen; bg = netH/L resp. menu3h/l */
static void ng_lobby_draw(const uint8_t *bg)
{
    ng_keep *k = NG();
    char t[0x80];
    if (bg) pic_put(bg, 0);
    if (k->phase == 2) {                        /* STAND-BY (menu_pages.c ~640-665), once the picker is known */
        hud_text_centred(2, g_menu_text[45], 3, 2);
        hud_text_centred(0x50, ng_name(k->picker_slot), 2, 2);
        hud_text_centred(0x6e, g_menu_text[49], 2, 2);
        const int tr = k->track >= 0 && k->track < 12 ? k->track : 0;
        hud_text_centred(0x96, g_menu_track[tr], 3, 2);
        return;
    }                                            /* (phase 1, the picker not yet known: the list) */
    const int n = net_count(), self = net_me();
    hud_text_centred(4, g_menu_text[48], 2, 2);
    if (!k->ch_races) hud_text_centred(0x14, g_menu_text[51], 0, 2);
    if (n > 1 && (!k->ch_on || self == 0)) hud_text_centred(0xba, g_menu_text[52], 0, 2);
    if (!k->ch_races) {
        hud_text_centred(0x1e, k->ch_on ? "RACE TYPE: CHAMPIONSHIP (6 RACES)" : "RACE TYPE: SINGLE RACE", 0, 2);
        if (k->ch_on && self != 0 && n > 1) hud_text_centred(0xba, "THE FIRST PLAYER STARTS THE RACE", 0, 2);
    } else {                                    /* the table instead of the cars */
        snprintf(t, sizeof t, "CHAMPIONSHIP - RACE %d OF 6", k->ch_races);
        hud_text_centred(0x24, t, 0, 2);
        hud_text(0x30, 0x34, "POS  NAME       RACE  TOTAL", 0, 2, 1);
        int y = 0x42;
        for (int i = 0; i < k->chn && i < 8; i++, y += 0xc) {
            snprintf(t, sizeof t, "%d.", k->ch[i].pos > 0 ? k->ch[i].pos : i + 1); hud_text(0x30, y, t, 0, 2, 1);
            snprintf(t, sizeof t, "%s%s", k->ch[i].name, k->ch[i].left ? " (LEFT)" : ""); hud_text(0x4c, y, t, 0, 2, 1);
            const int pl = k->ch[i].place[k->ch_races - 1];
            snprintf(t, sizeof t, "%d", pl >= 1 && pl <= 8 ? ng_points[pl - 1] : 0); hud_text(0xb4, y, t, 0, 2, 1);
            snprintf(t, sizeof t, "%d", k->ch[i].pts); hud_text(0xd8, y, t, 0, 2, 1);
        }
        if (!ch_results_complete()) hud_text_centred(0xa8, "WAITING FOR RESULTS", 0, 2);
        else if (k->ch_races >= 6) {
            int nc = 0;
            char who[64] = "";
            for (int i = 0; i < k->chn && k->ch[i].pos == 1; i++, nc++) {
                const size_t l = strlen(who);
                snprintf(who + l, sizeof who - l, "%s%s", nc ? " & " : "", k->ch[i].name);
            }
            snprintf(t, sizeof t, "%s: %s", nc > 1 ? "CHAMPIONS" : "CHAMPION", who);
            hud_text_centred(0xa8, t, 0, 2);
        } else {
            snprintf(t, sizeof t, "NEXT: %s", g_menu_track[k->ch_races]);
            hud_text_centred(0xa8, t, 0, 2);
        }
        return;
    }
    int y = 0x34, x = 0xc;
    hud_text(x, y, g_save.name, 0, 2, 1);
    hud_sprite_draw(x + 0x21, y - 0xf, k->my_car + 0x10);
    x += 0x9c;
    for (int i = 0, j = 0; i < n; i++) {
        if (i == self) continue;
        const uint8_t s = net_slot_at(i);
        hud_text(x, y, ng_name(s), 0, 2, 1);
        hud_sprite_draw(x + 0x21, y - 0xf, ng_car_of(s) + 0x10);
        if (j & 1) x += 0x9c; else { y += 0x26; x -= 0x9c; }
        j++;
    }
}
/* after ng_lobby_draw: the test's pictures of the list and of STAND-BY */
static void ng_lobby_shots(void)
{
    ng_keep *k = NG();
    if (!getenv("OS_NETSHOTDIR")) return;
    if (!k->shot_lobby && k->phase == 0 && !k->ch_races && net_count() >= 2) {
        int named = 1;
        for (int i = 0; i < net_count(); i++) if (net_slot_at(i) != net_self() && !k->rec[net_slot_at(i)].name[0]) named = 0;
        if (named) { k->shot_lobby = 1; ng_shot("lobby"); }
    }
    if (!k->shot_standby && k->phase == 2 && k->picker_seen) { k->shot_standby = 1; ng_shot("standby"); }
    if (k->phase == 0 && k->ch_races && !(k->shot_champ >> k->ch_races & 1) && ch_results_complete()) {
        char w[16];
        snprintf(w, sizeof w, "champ%d", k->ch_races);
        k->shot_champ |= 1 << k->ch_races;
        ng_shot(w);
    }
}

static void ng_reset_keep(void)                 /* the session over: what stays is the own car and track */
{
    ng_keep *k = NG();
    const int car = k->my_car, track = k->track, flags = k->my_flags;
    memset(k, 0, sizeof *k);
    k->my_car = car; k->track = track; k->my_flags = flags;
}
static void ng_leave(void)                       /* 0x2df68 net_leave: command 1, the session closed */
{
    ng_keep *k = NG();
    if (net_on()) {
        ng_send(C_LEAVE, 1, 0, 0xffffffffu, 0xffffffffu);
        const uint32_t t0 = net_ms();
        while (net_ms() - t0 < 300) net_pump();       /* (its acknowledgement) */
        if (k->ch_on && net_me() == 0) net_lock(0);
    }
    net_close();
    ng_reset_keep();
}

/* a key on the list: 1 = left it, 2 = this station picks the track, 3 = the race */
static int ng_lobby_key(int key)
{
    ng_keep *k = NG();
    if (key == SDLK_ESCAPE) {                   /* (menu.c:333: only on the list; on STAND-BY nothing) */
        if (k->phase != 0) return 0;
        ng_leave();
        return 1;
    }
    if (k->phase != 0) return 0;
    if ((key == SDLK_LEFT || key == SDLK_RIGHT) && net_me() == 0 && !k->ch_races) { k->ch_on ^= 1; snd_play(2); }
    if (key == SDLK_RETURN || key == SDLK_KP_ENTER || key == SDLK_SPACE) {      /* 0x28cba: st == 8 */
        if (k->ch_on && (net_me() != 0 || !ch_results_complete())) return 0;
        if (k->ch_on && k->ch_races >= 6) { ch_reset(); k->ch_on = 0; net_lock(0); snd_play(2); return 0; }
        if (net_count() < 2) return 0;
        for (int i = 0; i < 3; i++) ng_send(C_START, 1, (uint32_t)k->track, 0xffffffffu, 0xffffffffu);
        if (net_me() == 0) {                    /* (the original's broadcast reaches the sender too) */
            const int r = ng_draw_picker();
            ng_send(C_PICKER, 1, (uint32_t)r, 0xffffffffu, 0xffffffffu);
            ng_pick_done(r);
            if (k->phase == 3) return 2;
            if (k->phase == 4) { ng_race_list(); k->phase = 0; return 3; }
            return 0;
        }
        k->phase = 1;
    }
    return 0;
}

/* the track screen while this station picks (0x2cc98 menu_state3): its track (3) and the picker (0x8844), each
   picture, unreliable */
static void ng_track_frame(int track)
{
    ng_keep *k = NG();
    net_pump();
    k->track = track;
    ng_lock_pump();
    ng_send(C_TRACK, 0, (uint32_t)track, 0xffffffffu, 0xffffffffu);
    ng_send(C_PICKER, 0, (uint32_t)k->picker, 0xffffffffu, 0xffffffffu);
    uint8_t from, b[NET_PAY];
    int n;
    while ((n = net_recv(&from, b, sizeof b)) > 0) {
        ng_common(from, b, n);
        if (n >= 0x38 && rle(b + 4) == C_HERE) ng_store(from, b, n);
    }
}
static void ng_track_enter(int track, int cheat)   /* ENTER on it (menu.c:608): command 4 to all, the race */
{
    ng_keep *k = NG();
    k->track = track; k->laps = ng_lapv[g_opt_laps & 3]; k->diff = g_opt_diff;
    k->flags = (cheat & 0x30) | (track > 5 ? 8 : 0);
    k->race_no = ng_next_race_no();
    ng_send(C_GO, 1, (uint32_t)track, (uint32_t)k->laps, (uint32_t)k->diff);
    ng_race_list();
    k->phase = 0;
}

/* ---------------------------------------------------------------- the race */
typedef struct {
    float x, y, z, yaw, pitch, roll, speed, steer, progress, time;
    int32_t phase, env;
    uint32_t bits;                  /* 0-3 the barrier's round (4: racing), 4 finished, 5 crashing, 8-15 the stations
                                       this car hit (race index bits: player +0x2fc), 16-23 the race's number */
    uint32_t start;                 /* station 0: the countdown's start on the shared clock (ms), 0 = not yet */
    uint32_t cstart;                /* the sender's race clock's start on the shared clock (s_start_own), 0 = not yet */
    float bx, by;                   /* the bump vector (+0x80c / +0x814) */
} ng_state;                                      /* (in the 0x4c bytes of the race packet) */
typedef char ng_state_fits[sizeof(ng_state) <= 0x4c ? 1 : -1];
static scene_object *ng_obj[NET_MAX];
static scene_object *ng_shadow[NET_MAX];
static car_pose ng_pose[NET_MAX];
static struct {
    float px, py, pz, vx, vy, vz, ex, ey, ez;    /* the last sample, its speed (units / ms), the shown one's error */
    uint32_t t1, serial, rx, heard, cstart, bits;
    int have, gone, fin, round, fresh;
    double off;                                  /* the smoothing: receipt - send time, the least */
    int off_ok, shown_ok;
    uint32_t shown;                              /* the last picture's own clock (ms) */
    float progress, time, bx, by;
} ng_r[NET_MAX];
static int ng_round;
static uint32_t ng_start_at;                     /* the countdown's start on the shared clock (station 0 decides) */
static uint32_t ng_own_cstart, ng_prev_clk, ng_hitmask, ng_tx_t;
static int ng_was_fin, ng_green_said;
static float ng_prev_x, ng_prev_y, ng_scale = 1.0f, ng_bx, ng_by;

static int ng_my_index(void)
{
    ng_keep *k = NG();
    for (int i = 0; i < k->rn; i++) if (k->rs[i] == net_self()) return i;
    return 0;
}
static int ng_grid(void) { return NG()->race ? ng_my_index() : -1; }

/* the own state: the packet (head 0xc: magic 0x1234, station; 0x4c data; the sender's shared clock) */
static void ng_state_out(int force)
{
    ng_keep *k = NG();
    const uint32_t t = net_ms();
    if (!force && t - ng_tx_t < NET_STATE_MS) return;
    ng_tx_t = t;
    uint8_t p[NET_SMAX];
    memset(p, 0, sizeof p);
    wle(p + 4, C_RACE);
    wle(p + 8, (uint32_t)ng_my_index());
    ng_state s;
    memset(&s, 0, sizeof s);
    if (g_pobj) {
        s.x = g_pobj->x; s.y = g_pobj->y; s.z = g_pobj->z; s.yaw = g_pobj->yaw; s.pitch = g_pobj->pitch; s.roll = g_pobj->roll;
        s.phase = g_pobj->phase;
    }
    s.speed = g_pc.speed; s.steer = g_pc.steer; s.progress = g_progress; s.time = g_total_time;
    s.env = g_ppose.env;
    s.bits = (uint32_t)(ng_round & 15) | (g_finished ? 0x10u : 0) | (g_crash.on ? 0x20u : 0) | (ng_hitmask & 0xff) << 8
           | (uint32_t)k->race_no << 16;
    s.start = ng_start_at; s.cstart = ng_own_cstart; s.bx = ng_bx; s.by = ng_by;
    memcpy(p + 0xc, &s, sizeof s);
    wle(p + 0xc + 0x4c, net_ms());               /* the sender's own clock (the receiver's smoothing) */
    wle(p + 0xc + 0x50, ng_own_cstart);
    net_state_force(p, sizeof p);
    ng_hitmask = 0;                              /* (told) */
}
/* THE OTHER CARS' SMOOTHING: a state comes every ~30 ms,
   irregularly through the host; shown = last state + speed (from the sender's times) * its age, the age on the
   sender's clock through the least offset receipt - send time seen (a steady delay instead of the arrival's jitter);
   the jump at a new state is kept as an error and dies away over ~100 ms; over 3000 units at once */
static void ng_pred(int i, uint32_t L, float *out)
{
    double age = (double)L - ng_r[i].off - (double)ng_r[i].t1;
    if (age < 0.0) age = 0.0;
    if (age > 250.0) age = 250.0;
    out[0] = ng_r[i].px + ng_r[i].vx * (float)age;
    out[1] = ng_r[i].py + ng_r[i].vy * (float)age;
    out[2] = ng_r[i].pz + ng_r[i].vz * (float)age;
}
static void ng_sample(int i, uint32_t t, float x, float y, float z)
{
    const uint32_t L = net_ms();
    float old[3], nw[3];
    if (ng_r[i].have) {
        const int32_t dt = (int32_t)(t - ng_r[i].t1);
        if (dt <= 0) return;                     /* the same (a bundle again) or an older one */
        ng_pred(i, L, old);
        old[0] += ng_r[i].ex; old[1] += ng_r[i].ey; old[2] += ng_r[i].ez;
        const float rd = dt < 500 ? 1.0f / (float)dt : 0.0f;
        ng_r[i].vx = 0.5f * ng_r[i].vx + 0.5f * (x - ng_r[i].px) * rd;
        ng_r[i].vy = 0.5f * ng_r[i].vy + 0.5f * (y - ng_r[i].py) * rd;
        ng_r[i].vz = 0.5f * ng_r[i].vz + 0.5f * (z - ng_r[i].pz) * rd;
    }
    const double d = (double)L - (double)t;
    if (!ng_r[i].off_ok || d < ng_r[i].off) { ng_r[i].off = d; ng_r[i].off_ok = 1; }
    ng_r[i].t1 = t; ng_r[i].px = x; ng_r[i].py = y; ng_r[i].pz = z;
    if (ng_r[i].have) {
        ng_pred(i, L, nw);
        ng_r[i].ex = old[0] - nw[0]; ng_r[i].ey = old[1] - nw[1]; ng_r[i].ez = old[2] - nw[2];
        if (ng_r[i].ex * ng_r[i].ex + ng_r[i].ey * ng_r[i].ey + ng_r[i].ez * ng_r[i].ez > 3000.0f * 3000.0f)
            ng_r[i].ex = ng_r[i].ey = ng_r[i].ez = 0.0f;
    } else ng_r[i].ex = ng_r[i].ey = ng_r[i].ez = 0.0f;
}
static void ng_show(int i, scene_object *c)    /* each picture: the shown place */
{
    const uint32_t L = net_ms();
    const uint32_t dtf = ng_r[i].shown_ok ? L - ng_r[i].shown : 0;
    ng_r[i].shown = L; ng_r[i].shown_ok = 1;
    ng_r[i].off += (double)dtf * 0.001;          /* the clocks drift apart: the offset gives slowly */
    const float f = 1.0f / (1.0f + (float)dtf / 100.0f);
    float pr[3];
    ng_pred(i, L, pr);
    ng_r[i].ex *= f; ng_r[i].ey *= f; ng_r[i].ez *= f;
    c->x = pr[0] + ng_r[i].ex; c->y = pr[1] + ng_r[i].ey; c->z = pr[2] + ng_r[i].ez;
    if (getenv("OS_NETSMOOTHLOG")) printf("smooth %d %u %.1f %.1f\n", i, (unsigned)L, (double)c->x, (double)c->y);   /* (the test) */
}

/* station i's latest state of this race; new = not seen before */
static int ng_peek(int i, ng_state *o, uint32_t *clk, uint32_t *serial)
{
    int len;
    uint32_t rx;
    const uint8_t *d = net_state(NG()->rs[i], &len, &rx, serial);
    if (!d || len < 0xc + (int)sizeof *o || rle(d + 4) != C_RACE) return 0;
    memcpy(o, d + 0xc, sizeof *o);
    if ((o->bits >> 16 & 0xff) != NG()->race_no) return 0;      /* (an older race's) */
    *clk = rle(d + 0xc + 0x4c);
    return 1;
}
static int ng_state_in(int i, ng_state *o, uint32_t *clk)
{
    uint32_t serial;
    if (!ng_peek(i, o, clk, &serial) || serial == ng_r[i].serial) return 0;
    ng_r[i].serial = serial; ng_r[i].rx = ng_r[i].heard = net_ms();
    if ((int)(o->bits & 15) > ng_r[i].round) ng_r[i].round = (int)(o->bits & 15);
    if (o->cstart) ng_r[i].cstart = o->cstart;
    ng_r[i].bits = o->bits;
    return 1;
}
static void ng_gone(int i, const char *why)      /* net_gone: -2, the car and its shadow hidden */
{
    if (ng_r[i].gone) return;
    ng_r[i].gone = 1;
    /* (out of sight, far beyond the drawing distance: the renderers take every car as having a mesh) */
    if (ng_obj[i]) { ng_obj[i]->x = ng_obj[i]->y = 1.0e8f; }
    if (ng_shadow[i]) { ng_shadow[i]->x = ng_shadow[i]->y = 1.0e8f; }
    printf("net: station %d (%s) given up: %s\n", i, ng_name(NG()->rs[i]), why);
}

/* after opponents_init (race_init_net 0x12d0c): the other stations' cars on their grid places, and the first of the
   three start barriers */
static void ng_barrier_round(int round);
static void ng_race_init(const path *r)
{
    ng_keep *k = NG();
    memset(ng_obj, 0, sizeof ng_obj); memset(ng_shadow, 0, sizeof ng_shadow); memset(ng_r, 0, sizeof ng_r);
    ng_round = 0; ng_start_at = 0; ng_own_cstart = 0; ng_prev_clk = 0; ng_hitmask = 0; ng_tx_t = 0;
    ng_was_fin = 0; ng_green_said = 0; ng_scale = 1.0f; ng_bx = ng_by = 0.0f;
    net_states_clear();                          /* (no state of an earlier race: D1) */
    k->resn = k->rn;
    for (int i = 0; i < k->rn; i++) { k->res[i].slot = k->rs[i]; k->res[i].got = 0; k->res[i].fin = 0; k->res[i].time = 0.0f; }
    for (int i = 0; i < k->rn && g_ncar < MAX_CARS - 2; i++) {
        if (k->rs[i] == net_self() || i >= g_nopp_spl) continue;
        scene_object *c = &g_car[g_ncar++];
        memset(c, 0, sizeof *c);
        int row = ng_car_of(k->rs[i]);
        if (g_nspec > 0) row = (row % g_nspec + g_nspec) % g_nspec;
        int model = g_nspec > 0 ? atoi(g_spec[row].name + 4) : 0;
        if (model < 0 || model > 6 || !car_mesh_ok[model]) model = 0;
        c->m = &car_mesh[model]; c->v = model; c->radius = 1200.0f;
        c->phase = (g_nspec > 0 ? g_spec[row].livery : 0) | 0x4000;
        memset(&ng_pose[i], 0, sizeof ng_pose[i]);
        c->pose = &ng_pose[i];
        const gspline *sp = &g_opp_spl[i];
        const int32_t *nd = sp->node[sp->start];
        float A[2], B[2], C[2], pos[2], der[2];
        opp_piece(sp, sp->start, 0, A, B, C);
        opp_curve(A, B, C, 0.0f, pos, der);
        c->x = (float)nd[1]; c->y = (float)nd[2]; c->yaw = atan2f(der[0], -der[1]);
        c->z = r->p[0][2];
        surface_z(c->x, c->y, c->z, &c->z);
        ng_obj[i] = c;
        ng_shadow[i] = shadow_new();
        shadow_follow(ng_shadow[i], c);
        ng_r[i].px = c->x; ng_r[i].py = c->y; ng_r[i].pz = c->z;
    }
    if (k->laps > 0) g_total_laps = k->laps;
    printf("net: a race (number %d) of %d stations on track %d, %d laps, difficulty %d, flags %x%s, this one on grid place %d\n",
           k->race_no, k->rn, k->track + 1, g_total_laps, k->diff, (unsigned)k->flags, k->ch_on ? " (championship)" : "",
           ng_my_index() + 1);
    if (getenv("OS_NETSLOW")) SDL_Delay((Uint32)atoi(getenv("OS_NETSLOW")));   /* (the test: a slow machine's loading) */
    ng_barrier_round(1);                         /* (race.c:791: net_exchange(0x50), the loading picture still up) */
}

/* net_exchange(0x50): the own state of this round out (at once, then again and again) until every station still
   there has sent one of this round; a station not heard of for 0x50 * 0.8 s is given up, the rest still awaited.
   Nothing drawn: the screen stays as it is.  Guests also wait for the shared clock. */
static void ng_barrier_round(int round)
{
    ng_keep *k = NG();
    ng_round = round;
    const uint32_t t0 = net_ms();
    uint32_t tx = 0;
    for (int i = 0; i < k->rn; i++) ng_r[i].heard = t0;
    int first = 1;
    for (;;) {
        net_pump();
        const uint32_t now = net_ms();
        if (first || now - tx >= 250) { tx = now; first = 0; ng_state_out(1); }
        {   uint8_t from, b[NET_PAY];             /* (lobby messages meanwhile: the results, the word) */
            int n;
            while ((n = net_recv(&from, b, sizeof b)) > 0) ng_common(from, b, n);
        }
        int all = 1;
        for (int i = 0; i < k->rn; i++) {
            if (k->rs[i] == net_self() || ng_r[i].gone) continue;
            if (net_index(k->rs[i]) < 0) { ng_gone(i, "left the session"); continue; }
            ng_state o; uint32_t clk;
            ng_state_in(i, &o, &clk);
            if (ng_r[i].round >= round) continue;
            /* (signed: a state taken just now is a millisecond younger than `now`) */
            if ((int32_t)(now - ng_r[i].heard) > (int32_t)(0x50u * 800u)) { ng_gone(i, "no answer at the start"); continue; }
            all = 0;
        }
        uint32_t sh;
        if (!net_clock(&sh) && now - t0 < 10000) all = 0;
        if (all) break;
        SDL_PumpEvents();
        SDL_Delay(5);
    }
    uint32_t sh;
    net_clock(&sh);
    printf("net: barrier %d passed (shared clock %u, %u ms)\n", round, (unsigned)sh, (unsigned)(net_ms() - t0));
}
/* race_load's end (race.c:538-541): the black screen (the music already on), barriers 2 and 3; then station 0 sets
   the countdown's start for all on the shared clock */
static void ng_barrier(SDL_Renderer *ren, SDL_Texture *tex)
{
    if (fb) memset(fb, 0, FB_BYTES);
    {
        show_picture(tex);
        SDL_RenderClear(ren);
        SDL_RenderCopy(ren, tex, NULL, NULL);
        SDL_RenderPresent(ren);
    }
    if (getenv("OS_NETSLOW")) SDL_Delay((Uint32)atoi(getenv("OS_NETSLOW")));   /* (the test: a slow machine's loading) */
    ng_barrier_round(2);
    ng_barrier_round(3);
    if (ng_my_index() == 0) {                     /* station 0: the countdown starts for all at once, 0.5 s from now */
        uint32_t now;
        net_clock(&now);
        ng_start_at = now + 500;
        if (!ng_start_at) ng_start_at = 1;
        ng_round = 4;
        ng_state_out(1);
    }
    ng_round = 4;
    printf("net: all stations there%s\n", ng_my_index() == 0 ? ", the countdown starts in 0.5 s" : "");
}

/* the countdown on the shared clock: until the green light the race clock IS the time since station 0's start
   (every station's lights at the same moment, whatever its pictures cost); 1 = done here, 0 = count on as ever */
static int ng_clock(float *clk)
{
    ng_keep *k = NG();
    if (!k->race || *clk >= RACE_HOLD) return 0;
    uint32_t now;
    const int ok = net_clock(&now);
    if (!ng_start_at && k->rn > 0) {
        if (k->rs[0] == net_self()) ng_start_at = 1;            /* (cannot happen: station 0 set it) */
        else if (net_index(k->rs[0]) < 0 || ng_r[0].gone) { ng_start_at = now ? now : 1; printf("net: station 0 gone, the countdown starts now\n"); }
        else {
            ng_state o; uint32_t c, serial;
            if (ng_peek(0, &o, &c, &serial) && o.start) ng_start_at = o.start;
        }
    }
    if (!ng_start_at || !ok) { *clk = 0.0f; return 1; }
    const int32_t d = (int32_t)(now - ng_start_at);
    *clk = d <= 0 ? 0.0f : (float)d / 1000.0f;
    if (*clk >= RACE_HOLD && !ng_green_said) {
        ng_green_said = 1;
        printf("net: GREEN at shared clock %u (countdown started %u)\n", (unsigned)now, (unsigned)ng_start_at);
    }
    return 1;
}

/* the handicap (player.c 325-347, +0x300): the own car's move scaled by rank/n*s + (1-s), s = (sqrt(n/10)-0.3)*0.7 */
static void ng_handicap(float x0, float y0)
{
    ng_keep *k = NG();
    if (!k->race || k->rn < 1) return;
    const float n = (float)k->rn, s = (sqrtf(n * 0.1f) - 0.3f) * 0.7f;
    const float target = (float)g_player_rank / n * s + (1.0f - s);
    if (!g_crash.on) ng_scale = (ng_scale - target) * drive_damp(0x58) + target;
    g_pc.x = x0 + (g_pc.x - x0) * ng_scale;
    g_pc.y = y0 + (g_pc.y - y0) * ng_scale;
}

/* where the move from (x0, y0) to (x1, y1) enters the finish circle (marker 0): 0..1, 1 = not to be worked out */
static float ng_finish_frac(float x0, float y0, float x1, float y1)
{
    if (g_nmark < 1) return 1.0f;
    const marker *m = &g_mark[0];
    const float dx = x1 - x0, dy = y1 - y0, fx = x0 - m->x, fy = y0 - m->y;
    const float a = dx * dx + dy * dy, b = 2.0f * (fx * dx + fy * dy), c = fx * fx + fy * fy - m->radius * m->radius;
    if (a < 1e-6f || c <= 0.0f) return 1.0f;
    const float disc = b * b - 4.0f * a * c;
    if (disc < 0.0f) return 1.0f;
    const float f = (-b - sqrtf(disc)) / (2.0f * a);
    return f < 0.0f || f > 1.0f ? 1.0f : f;
}

/* every other station in (finished), gone, or silent 10 s: the end display may end (race_end_rest 0x...) */
static int ng_all_in(void)
{
    ng_keep *k = NG();
    if (!k->race) return 1;
    static uint32_t said;
    for (int i = 0; i < k->rn; i++) {
        if (k->rs[i] == net_self() || ng_r[i].gone || net_index(k->rs[i]) < 0) continue;
        if (!ng_r[i].fin) {
            if (net_ms() - said > 5000) { said = net_ms(); printf("net: waiting at the end for station %d (%s)\n", i, ng_name(k->rs[i])); }
            return 0;
        }
    }
    return 1;
}

/* the radar's dots of the stations still racing (hud.c 396-401) */
static void ng_radar(const car_state *c, float s, float cs, float sn)
{
    ng_keep *k = NG();
    if (!k->race) return;
    for (int i = 0; i < k->rn; i++) {
        const scene_object *o = ng_obj[i];
        if (!o || !o->m || ng_r[i].fin || ng_r[i].gone) continue;
        const float dx = o->x - c->x, dy = o->y - c->y;
        hud_sprite_px((int)(39.0f * (float)g_s - (dy * sn + dx * cs) * s), (int)(159.0f * (float)g_s + (dy * cs - dx * sn) * s), 5);
    }
}

/* each step after player_env: the own state out, the others' cars, bumps, the place, the race clock */
static void ng_step(void)
{
    ng_keep *k = NG();
    if (!k->race || !g_pobj) return;
    net_pump();
    ng_lock_pump();
    {   uint8_t from, b[NET_PAY];                 /* (results and the word of the others during the race) */
        int n;
        while ((n = net_recv(&from, b, sizeof b)) > 0) ng_common(from, b, n);
    }
    const int me = ng_my_index();
    uint32_t now;
    net_clock(&now);
    /* net_clock_apply: one race clock for all -- from the earliest start of any station's race clock */
    if (g_clock_on && !ng_was_fin && !ng_own_cstart) ng_own_cstart = now ? now : 1;
    uint32_t ref = ng_own_cstart;
    for (int i = 0; i < k->rn; i++)
        if (i != me && ng_r[i].cstart && (!ref || (int32_t)(ng_r[i].cstart - ref) < 0)) ref = ng_r[i].cstart;
    const float shared_t = ng_own_cstart && (int32_t)(now - ref) > 0 ? (float)(int32_t)(now - ref) / 1000.0f : 0.0f;
    if (g_clock_on && !g_finished && ng_own_cstart) g_total_time = shared_t;
    if (getenv("OS_NETFINISH") && !g_finished && g_race_clock >= RACE_HOLD + (float)atof(getenv("OS_NETFINISH")) + 0.5f * me) {
        g_finished = 1;                           /* (the test: in after <s> seconds, 0.5 s a station) */
        g_total_time = ng_own_cstart ? shared_t : g_race_clock - RACE_HOLD;
        ng_was_fin = 1;
        printf("net: finished (test) in %.2f s (shared clock)\n", (double)g_total_time);
    }
    if (g_finished && !ng_was_fin) {              /* the finish: the time back to where the line was crossed */
        ng_was_fin = 1;
        if (ng_own_cstart) {
            const float f = ng_prev_clk ? ng_finish_frac(ng_prev_x, ng_prev_y, g_pc.x, g_pc.y) : 1.0f;
            g_total_time = shared_t - (ng_prev_clk ? (1.0f - f) * (float)(int32_t)(now - ng_prev_clk) / 1000.0f : 0.0f);
        }
        printf("net: finished in %.2f s (shared clock)\n", (double)g_total_time);
    }
    ng_prev_clk = now; ng_prev_x = g_pc.x; ng_prev_y = g_pc.y;
    if (ng_round < 4) ng_round = 4;
    int ahead = 0, fin_ahead = 0;
    for (int i = 0; i < k->rn; i++) {
        if (i == me) continue;
        scene_object *c = ng_obj[i];
        ng_r[i].fresh = 0;
        if (!ng_r[i].gone && net_index(k->rs[i]) < 0) ng_gone(i, "left the session");
        if (!ng_r[i].gone && ng_r[i].have && net_ms() - ng_r[i].rx > 10000) ng_gone(i, "no state for 10 s");
        if (!ng_r[i].gone) {
            ng_state o;
            uint32_t clk;
            if (ng_state_in(i, &o, &clk)) {
                ng_r[i].fresh = 1;
                if (c && !ng_r[i].fin) {
                    ng_sample(i, clk, o.x, o.y, o.z);
                    c->yaw = o.yaw; c->pitch = o.pitch; c->roll = o.roll; c->phase = o.phase;
                    ng_pose[i].env = o.env;
                    wheels_step(&ng_pose[i], o.speed, o.steer, DRIVE_DT);
                }
                ng_r[i].have = 1; ng_r[i].progress = o.progress; ng_r[i].time = o.time;
                ng_r[i].bx = o.bx; ng_r[i].by = o.by;
                if (o.bits & 0x10) {
                    ng_r[i].fin = 1;
                    for (int q = 0; q < k->resn; q++)
                        if (k->res[q].slot == k->rs[i]) { k->res[q].got = 1; k->res[q].fin = 1; k->res[q].time = o.time; }
                }
            } else if (c && ng_r[i].have && !ng_r[i].fin)
                wheels_step(&ng_pose[i], hypotf(ng_r[i].vx, ng_r[i].vy) * 1000.0f, ng_pose[i].steer * 1.5f, DRIVE_DT);
            if (c && c->m && ng_r[i].have && !ng_r[i].fin) ng_show(i, c);   /* (a finished car stays where it stopped) */
            if (c && ng_shadow[i]) shadow_follow(ng_shadow[i], c);
        }
        /* the standings: racing, every other car (gone and finished too, by their last progress) ahead of the own;
           finished, those in before the own time */
        if (ng_r[i].have) {
            if (!g_finished && ng_r[i].progress > g_progress) ahead++;
            if (g_finished && ng_r[i].fin && ng_r[i].time < g_total_time) fin_ahead++;
        }
    }
    /* player_net_collide (player2.c 533-604): the hitter moves itself out and tells the other (flags), the other
       takes the reversed bump */
    if (!g_crash.on && g_pobj->m) {
        for (int i = 0; i < k->rn; i++) {
            scene_object *c = ng_obj[i];
            if (i == me || !c || !c->m || ng_r[i].gone || ng_r[i].fin || !ng_r[i].have) continue;
            if (me < 8 && (ng_r[i].bits >> 8 & 0xff) & (1u << me)) {
                if (ng_r[i].fresh) {                /* it hit this one: player_net_response(0) */
                    ph_fx();
                    g_pc.shove = 5000.0f; g_pc.shove_x = -ng_r[i].bx; g_pc.shove_y = -ng_r[i].by;
                    g_car_contact = 1;
                }
                continue;
            }
            if (ng_r[i].bits & 0x20) continue;      /* (it is crashing) */
            if (fabsf(c->x - g_pc.x) >= 1500.0f || fabsf(c->y - g_pc.y) >= 1500.0f) continue;
            float ax[2], ay[2], ar, bx[2], by[2], br;
            car_circles(g_pobj->m, g_pc.x, g_pc.y, g_pc.yaw, ax, ay, &ar);
            car_circles(c->m, c->x, c->y, c->yaw, bx, by, &br);
            const float rr = ar + br;
            int hit = 0;
            for (int p = 0; p < 2 && !hit; p++)
                for (int q = 0; q < 2 && !hit; q++) {
                    const float ddx = ax[p] - bx[q], ddy = ay[p] - by[q], dd = sqrtf(ddx * ddx + ddy * ddy);
                    if (dd < rr && dd > 0.001f) {   /* player_net_response(1) */
                        const float ux = ddx / dd, uy = ddy / dd;
                        ph_fx();
                        g_pc.shove = 5000.0f; g_pc.shove_x = ux; g_pc.shove_y = uy;
                        ng_bx = ux; ng_by = uy;
                        g_pc.x += rr * ux - ddx; g_pc.y += rr * uy - ddy;
                        ng_hitmask |= 1u << i;
                        g_car_contact = 1;
                        hit = 1;
                    }
                }
        }
    }
    ng_state_out(0);
    g_player_rank = 1 + (g_finished ? fin_ahead : ahead);    /* (net_rank after the finish) */
}

/* after the race (0x2a558 menu.c 1215-1282): the FINAL RESULTS page (champ5, text 50, built once) if this station's
   race was finished; 1 = back to the list (a championship), 0 = the session over (a single race: the main menu) */
static int ng_results(SDL_Renderer *ren, SDL_Texture *tex)
{
    ng_keep *k = NG();
    const int fin = g_finished && !g_game_over;
    const int champ = k->ch_on && net_on();
    const float own_time = g_total_time;
    for (int q = 0; q < k->resn; q++) if (k->res[q].slot == net_self()) { k->res[q].got = 1; k->res[q].fin = fin; k->res[q].time = own_time; }
    if (!champ) net_close();                     /* (a single race: BYE before the page, no command 1) */
    printf("net: (finished %d, game over %d, time %.2f)\n", g_finished, g_game_over, (double)own_time);
    printf("net: results of the race on track %d:", k->track + 1);
    for (int q = 0; q < k->resn; q++)
        printf("  slot %d %s %s %.2f", k->res[q].slot, ng_name(k->res[q].slot), k->res[q].got && k->res[q].fin ? "in" : "-", (double)k->res[q].time);
    printf("\n");
    if (fin) {
        /* menu_load: the menu's fonts, sprites and texts back (this is the race's part: its own are loaded) */
        g_fnt_file = "build/dec/GRAF/MENUL.FNT";
        g_spr_file = "build/dec/GRAF/MENUL.SPR";
        hud_load();
        text_lines("build/dec/LOCAL/MENU.TXT", g_menu_text, 60);
        {   static char lines[96][40];
            const int n = text_lines("build/dec/LOCAL/CARDAT.TXT", lines, 96);
            g_nmenu_car = 0;
            for (int i = 0; i + 4 < n && g_nmenu_car < MENU_CARS; i += 6)
                snprintf(g_menu_car[g_nmenu_car++].name, sizeof g_menu_car[0].name, "%.23s", lines[i]);
        }
        static uint8_t bg[FB_MAXW * FB_MAXH];
        static uint32_t pal[256];
        const int have_bg = pcx_load("build/dec/GRAF/CHAMP5L.PCX", bg, pal);     /* (1 = loaded) */
        g_show_fade = 1.0f; g_show_to_k = 0.0f;
        if (have_bg) pic_put(bg, 0); else memset(fb, 0, FB_BYTES);
        hud_text_centred(2, g_menu_text[50], 3, 2);
        /* the entries: the own car and every one in (net car == -3), station order; a bubble by time, ">=" swaps */
        int idx[NET_MAX], cnt = 0;
        float tim[NET_MAX];
        for (int q = 0; q < k->resn && cnt < 8; q++)
            if (k->res[q].got && k->res[q].fin) { idx[cnt] = q; tim[cnt] = k->res[q].time; cnt++; }
        for (int a = 0; a < cnt - 1; a++)
            for (int j = 0; j < cnt - 1 - a; j++)
                if (tim[j] >= tim[j + 1]) {
                    const float t = tim[j]; tim[j] = tim[j + 1]; tim[j + 1] = t;
                    const int u = idx[j]; idx[j] = idx[j + 1]; idx[j + 1] = u;
                }
        for (int j = 0; j < cnt; j++) {
            char line[96];
            const float t = tim[j];
            const int s = (int)t, cs = (int)((t - truncf(t)) * 100.0f);
            int car = ng_car_of(k->res[idx[j]].slot);
            if (car < 0 || car >= g_nmenu_car) car = 0;
            snprintf(line, sizeof line, "\x01%d. %s %02d.%02d.%02d \x02%s", j + 1, ng_name(k->res[idx[j]].slot), s / 60, s % 60, cs,
                     g_nmenu_car > 0 ? g_menu_car[car].name : "");
            hud_text(0x20, 0x40 + j * 0x10, line, 0, 2, 1);
        }
        if (have_bg) memcpy(g_pal, pal, sizeof g_pal);          /* (its palette after the drawing) */
        if (getenv("OS_NETSHOT")) write_ppm(getenv("OS_NETSHOT"));
        ng_shot("results");
        const uint32_t t0 = SDL_GetTicks();
        const int autoexit = getenv("OS_NETAUTO") != NULL;
        for (;;) {
            if (champ) {                              /* (the session stays: keep it answered) */
                net_pump();
                uint8_t from, b[NET_PAY];
                int n;
                while ((n = net_recv(&from, b, sizeof b)) > 0) ng_common(from, b, n);
            }
            show_picture(tex);
            SDL_RenderClear(ren);
            SDL_RenderCopy(ren, tex, NULL, NULL);
            SDL_RenderPresent(ren);
            int key = 0;
            SDL_Event ev;
            while (SDL_PollEvent(&ev)) {
                if (ev.type == SDL_QUIT) key = 1;
                if (ev.type == SDL_KEYDOWN && (ev.key.keysym.sym == SDLK_RETURN || ev.key.keysym.sym == SDLK_KP_ENTER ||
                                               ev.key.keysym.sym == SDLK_ESCAPE)) key = 1;
            }
            if (key || (autoexit && SDL_GetTicks() - t0 > 2000)) break;
            SDL_Delay(10);
        }
    }
    k->race = 0;
    {   SDL_Event ev_;                            /* (keys pressed in the race are not the list's: 0x11fb68, held keys locked) */
        while (SDL_PollEvent(&ev_)) {}
    }
    if (champ && net_on()) {                      /* command 5 only now (menu.c 1270): +0x14 time, +0x18 in, +0x1c race */
        ng_send(C_RESULT, 1, fbits(own_time), (uint32_t)(fin != 0), (uint32_t)(k->ch_races - 1));
        for (int c = 0; c < k->chn; c++) if (k->ch[c].slot == net_self()) { k->ch[c].got = fin ? 1 : 3; k->ch[c].time = own_time; }
        k->ch_results_t = net_ms(); if (!k->ch_results_t) k->ch_results_t = 1;
        k->phase = 0;
        return 1;                                 /* the championship: back to the list */
    }
    if (net_on()) net_close();
    ng_reset_keep();
    return 0;
}
