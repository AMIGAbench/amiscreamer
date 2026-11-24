/*
 * drive.c - the player's car, ported from STARTL.EXE.
 *
 * Every frame the game runs (0x2002f) these on the player record at 0xf918:
 *
 *   0x16f24  integrate: move the car, apply wall shove, wrap the angles
 *   0x15a70  -> 0x18a04 race clock, 0x18da0 ENGINE + GEARBOX, 0x16094 THROTTLE,
 *               0x16140 BRAKE, 0x1628c STEERING
 *   0x15b9c  -> 0x168a4 suspension bob, 0x17d04 SKID / SPIN, 0x1813c surface
 *               sound, 0x18518 crash states, 0x188a8 spin recovery, 0x19970 smoke
 *   0x15aa8  -> 0x1820c lap markers, 0x19490 lap count, 0x11e74/0x11f98/0x16b88
 *               body-corner collision, 0x11a30 wheel contact, 0x16c90 WALL HIT,
 *               0x16698 ride height from the four wheels
 *
 * The routines in capitals are ported below, line for line where the
 * decompiler output was complete (build/decomp/player_update.c keeps it).
 * The collision (which corner is off the track, which wall is nearest) is in
 * main.c, player_walls(), also from the game; so are the four-wheel ground
 * contact (player_contact), the suspension (suspension_step), the crash and
 * the smoke.
 *
 * THE DAMPING TABLE.  The game smooths values with
 *     v = (v - target) * damp[i] + target                     (0x22b60)
 * where damp[i] comes from a table built at start-up (0x1571c) for every
 * frame rate:
 *     damp[fps][i] = pow(0.5 + i * 0.005, 50 / (fps + 1))
 * so `i` is a stiffness from 0.5 (snappy) to 0.995 (lazy), defined at 50
 * frames a second.  The port steps the physics at exactly 50 Hz.
 */
#include "drive.h"

#include <math.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "port.h"

#define FPS 50.0f

#ifdef OS_ORIG_TICK
/* AMIGA: the original's damping rows, K[r][i] = pow(0.5 + 0.005 i, 50 / (r + 1)), r = 1 / the smoothed step
   (0..49: at exactly 50 pictures a second the original reads past its table -- here
   held to the last row); each row made once */
#define DAMP_ROWS 50
/* (g_dt_smooth, g_dt_raw, g_dt500, g_dt1000: in amiga/sys/game_68k.s, where the vasm reads them) */
extern float g_dt500, g_dt1000, g_dt2000, g_dt6000;
static float tabs[DAMP_ROWS][128];
static uint8_t row_made[DAMP_ROWS];
static float *tab = tabs[DAMP_ROWS - 1];
static int g_row = DAMP_ROWS - 1;
static void row_make(int r)
{
    if (row_made[r]) return;
    for (int i = 0; i < 128; i++) tabs[r][i] = powf(0.5f + (float)i * 0.005f, 50.0f / ((float)r + 1.0f));
    row_made[r] = 1;
}
void drive_timing(int ticks)
{
    g_dt_raw = (float)ticks * 0.01f;
    float v = (g_dt_smooth * 9.0f + g_dt_raw) / 10.0f;
    if (!(v < 0.2f)) v = 0.2f;
    if (!(v > 0.02f)) v = 0.02f;
    g_dt_smooth = v;
    g_dt500 = v * 500.0f;                   /* (for the vasm: dt * 500 / 1000 as gcc rounds them) */
    g_dt1000 = v * 1000.0f;
    g_dt2000 = v * 2000.0f;
    g_dt6000 = v * 6000.0f;
    int r = (int)(1.0f / v);
    if (r > DAMP_ROWS - 1) r = DAMP_ROWS - 1;
    if (r < 0) r = 0;
    row_make(r);
    g_row = r;
    tab = tabs[r];
}
void drive_timing_reset(void) { g_dt_smooth = 0.0f; }
static float damp(int i)
{
    if ((unsigned)i < 128u) { row_make(g_row); return tab[i]; }
    return powf(0.5f + (float)i * 0.005f, 50.0f / ((float)g_row + 1.0f));
}
#else
static float tab[128];          /* damp's values (dr68k reads them all: damp_tab) */
static uint8_t known[128];
static float damp(int i)
{
    /* (a pure function of i: worked out once each, the same powf -- no powf, and on a 68060 no FPSP trap, a step) */
    if ((unsigned)i < 128u) {
        if (!known[i]) { tab[i] = powf(0.5f + (float)i * 0.005f, 50.0f / (FPS + 1.0f)); known[i] = 1; }
        return tab[i];
    }
    return powf(0.5f + (float)i * 0.005f, 50.0f / (FPS + 1.0f));
}
#endif

float drive_damp(int i) { return damp(i); }

static void approach(float *v, float target, int i)        /* 0x22b60 */
{
    *v = (*v - target) * damp(i) + target;
}

/* 0x220fc: the same for an angle -- near the target it eases through a sine */
static void approach_angle(float *v, float target, int i)
{
    if (fabsf(target - *v) < 1.5707963f)
        *v = sinf(*v - target) * damp(i) + target;
    else
        *v = (*v - target) * damp(i) + target;
}

static float sqrt0(float x) { return x < 0.0f ? 0.0f : sqrtf(x); }   /* 0x22bcc */

/* per-gear pull, the table at 0x1d84 in the data segment */
static const float GEAR_PULL[8] = { 0.0f, 5.0f, 3.5f, 2.0f, 0.95f, 0.78f, 0.72f, 0.0f };

/* --------------------------------------------------------------- CARS.DTR */

/* values carry a type letter: d decimal, f float, x hex, s string */
static double dtr_num(const char *tok)
{
    if (tok[0] == 'x') return (double)strtoul(tok + 1, NULL, 16);
    return atof(tok + 1);
}

int cars_dtr_load(car_spec *out, int max, const char *path)
{
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    char line[512];
    int in = 0, n = 0, field = 0;
    while (fgets(line, sizeof line, f) && n < max) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (!in) { if (!strncmp(p, "CARS_DATA", 9)) in = 1; continue; }
        if (!strncmp(p, "END_LIST", 8)) break;
        for (char *tok = strtok(p, " \t\r\n"); tok; tok = strtok(NULL, " \t\r\n")) {
            if (tok[0] == '*') break;                  /* comment to end of line */
            car_spec *c = &out[n];
            switch (field) {
            case 0:
                memset(c, 0, sizeof *c);
                snprintf(c->name, sizeof c->name, "%s", tok + 1);
                break;
            case 1: c->livery    = (int)dtr_num(tok); break;
            case 2: c->maxspd    = (float)dtr_num(tok); break;
            case 3: c->maxrpm    = (float)dtr_num(tok); break;
            case 4: c->grip      = (float)dtr_num(tok); break;
            case 5: c->accel     = (float)dtr_num(tok); break;
            case 6: c->automatic = (int)dtr_num(tok); break;
            case 7: c->nshift    = (int)dtr_num(tok); break;
            default: c->ratio[field - 7] = (float)dtr_num(tok); break;   /* 1..6 */
            }
            if (++field == 14) { field = 0; n++; }
        }
    }
    fclose(f);
    return n;
}

/* ------------------------------------------------------------------ set-up */

/* the tail of 0x136c8: turn the table row into the constants the frame uses */
void drive_init(car_state *c, const car_spec *spec, float wheelbase)
{
#ifdef OS_ORIG_TICK
    const float rear_z = c->rear_z;                  /* (the caller's: kept over a reset) */
    memset(c, 0, sizeof *c);
    c->rear_z = rear_z;
#else
    memset(c, 0, sizeof *c);
#endif
    c->spec = *spec;
    c->wheelbase = wheelbase;
    c->surface = 1.0f;
    c->k_rpm          = spec->maxrpm / spec->maxspd * 0.02223f;
    c->k_engine_brake = spec->maxspd * 0.03f;
    c->k_brake        = spec->maxspd * 0.3f;
    c->k_wall         = spec->maxspd * 0.3f;
    c->grip_slide     = spec->grip * 16000.0f;
    c->grip_spin      = spec->grip * 26000.0f;
    c->grip_decel     = spec->grip * 16000.0f;
    c->grip_lock      = spec->grip * 11500.0f;
}

float drive_kmh(const car_state *c) { return c->speed * 340.0f / 21000.0f; }

/* ------------------------------------------------------------------ 0x18da0 */

static void engine(car_state *c, const drive_input *in)
{
    const car_spec *s = &c->spec;
    const float M = s->maxrpm, dt = DRIVE_DT;

    /* 0x18df0 -> 0x193e7: until the green light none of the gearbox or the
       drive is run -- the engine just follows the pedal, as it does in
       neutral.  So the player can rev on the grid, and an automatic car held
       over 8500 rpm at the green takes first with its wheels spinning. */
#ifdef OS_ORIG_TICK
    /* 0x18db0 with 0x118e1d bit 6 (the time is up, or the car has finished: 0x20ec8 sets it): no gearbox and no
       drive -- the engine just follows the pedal (j 0x3d) and the speed is left to the brake the caller forces
       (0x200 on the brake's axis); stopped: neutral */
    if (c->timeout) {
        approach(&c->rpm, c->throttle * M, 0x3d);
        if (c->speed < dt * 500.0f) c->gear = 0;
        return;
    }
#endif
    if (c->waiting) {
        approach(&c->rpm, c->throttle * M, 0x4b);
        if (c->speed < dt * 500.0f) c->gear = 0;
        return;
    }

    if (!s->automatic) {
        if (in->shift > 0 && c->gear < s->nshift) c->gear++;
        if (in->shift < 0 && c->gear > 0)         c->gear--;
    } else {
        /* change up past 8500 rpm, down below 4000 (each nudged by the gear) */
        if (c->rpm > (float)(c->gear + 8500)) {
            if (c->gear < s->nshift) c->gear++;
        } else if (c->rpm < (float)(4000 - c->gear) && c->gear > 1) {
            c->gear--;
        }
        if (c->launch) c->gear = 1;
    }

    if (c->gear == 0) {
        /* neutral: the car coasts down and the engine follows the pedal */
        c->speed -= dt * 500.0f;
        if (c->speed < 0.0f) c->speed = 0.0f;
        approach(&c->rpm, c->throttle * M, 0x4b);
    } else {
        float ratio = s->ratio[c->gear];
#ifdef OS_ORIG_TICK
        /* +0x510: the cap is 1000 under the top speed on the flat, lower uphill (0x18f..: sin(pitch) x 4000 more) */
        const float slope = sinf(c->pitch);
        float top = s->maxspd - (slope * 4.0f + 1.0f) * 1000.0f;
#else
        float top = s->maxspd;                       /* +0x510, the speed cap */
#endif

        /*
         * Normally the engine is locked to the wheels.  The exception is
         * pulling away: high revs and almost no speed with the pedal down --
         * the wheels spin (state 5), the revs fall and the car gains a flat
         * 1000 units/s each second until the two meet.
         */
        if (c->rpm <= s->grip * 6000.0f || c->speed >= 2000.0f) {
            c->rpm = ratio * c->speed * c->k_rpm;
#ifdef OS_ORIG_TICK
            if (c->launch) c->launch_end = 1;        /* (state 5 -> 6: no grip work this step) */
#endif
            c->launch = 0;
        } else if (in->throttle > 200.0f / 1023.0f) {
#ifdef OS_ORIG_TICK
            if (!c->crash) c->launch = 1;            /* (0x19478: a state only over none) */
#else
            c->launch = 1;
#endif
            c->rpm -= dt * 500.0f;
        } else {
            c->rpm = ratio * c->speed * c->k_rpm;
#ifdef OS_ORIG_TICK
            if (c->launch) c->launch_end = 1;
#endif
            c->launch = 0;
        }

        /* how hard this gear pulls: strongest in the middle of its range */
        float vgear = M / (c->k_rpm * ratio);        /* speed at max rpm */
        float pull, curve;
        if (s->nshift == 1) {
            pull  = s->accel;
            curve = sqrt0(1.0f - c->speed / vgear);  /* argument not recovered:
                                                        only the one-gear "Raz
                                                        car" takes this path */
        } else {
            float a = (2.0f - (vgear - c->speed) / (vgear * 0.5f)) - 1.0f;
            if (c->gear == 1 && a < 0.0f) a = 0.2f;
            curve = (1.0f + sinf(a * 1.5707964f)) * 0.5f;
            pull  = s->accel * GEAR_PULL[c->gear];
        }
#ifdef OS_ORIG_TICK
        if (c->rpm < c->throttle * M)                /* (uphill the engine gains less: sin(pitch) x 100 rpm/s) */
            c->rpm += (c->throttle * pull * curve - slope * 100.0f) * dt;
#else
        if (c->rpm < c->throttle * M)
            c->rpm += c->throttle * pull * curve * dt;
#endif

        if (c->rpm <= M) {
            if (c->throttle * M < c->rpm) {          /* engine braking */
                c->rpm -= sqrt0(c->rpm / M) * c->k_engine_brake * dt;
                if (c->rpm < M * c->throttle) c->rpm = M * c->throttle;
            }
        } else {                                     /* over-revving */
#ifdef OS_ORIG_TICK
            c->rpm -= (slope * 100.0f + 4000.0f + (c->rpm - M) * 2.0f) * dt;
#else
            c->rpm -= (c->rpm - M) * 2.0f * dt;
#endif
            if (c->rpm < M * c->throttle) c->rpm = M * c->throttle;
        }

        float before = c->speed;
        c->speed = c->launch ? c->speed + dt * 1000.0f
                             : c->rpm / (c->k_rpm * ratio);
        if (c->speed > top) c->speed = top;
        /* slowing faster than the tyres can manage locks them */
        if (c->grip_decel * dt < before - c->speed) c->lock = 1.0f;
    }

    /* stopped: back to neutral.  (From there the automatic box revs up in
       neutral and takes first again past 8500 rpm, which is the launch.) */
    if (c->speed < dt * 500.0f) c->gear = 0;
}

/* ------------------------------------------------------- 0x16094 / 0x16140 */

static void pedals(car_state *c, const drive_input *in)
{
    /* no drive while sliding, locked or spinning */
#ifdef OS_ORIG_TICK
    if (c->throttle >= 0.0f && c->slide_want == 0.0f && c->lock == 0.0f && !c->spin && !c->launch && !c->launch_end
        && !c->crash && !c->timeout)
        c->throttle = in->throttle;                  /* (0x160a4: no drive while the car is in a state -- the launch, its
                                                        end, a crash -- nor once the time is up) */
#else
    if (c->throttle >= 0.0f && c->slide_want == 0.0f && c->lock == 0.0f && !c->spin)
        c->throttle = in->throttle;
#endif
    else
        c->throttle = 0.0f;

    /* 0x16174: a joystick axis IS the brake (word / 1023); a key or a button
       brings it up to full */
#ifdef OS_ORIG_TICK
    /* 0x18da0: once the time is up the brake's word is 512 -- half a trigger, a key's brake */
    const float brake_in = c->timeout ? 512.0f / 1023.0f : in->brake;
    if (brake_in <= 0.0f)    c->brake = 0.0f;
    else if (c->analog & 4)  c->brake = brake_in;
    else                     approach(&c->brake, 1.0f, 0x52);

    if (c->drift < 0.1f) {                           /* (0x16140: the drift itself, not its size) */
#else
    if (in->brake <= 0.0f)   c->brake = 0.0f;
    else if (c->analog & 4)  c->brake = in->brake;
    else                     approach(&c->brake, 1.0f, 0x52);

    if (fabsf(c->drift) < 0.1f) {
#endif
        c->speed -= c->k_brake * DRIVE_DT * c->brake;
        if (c->speed < 0.0f) c->speed = 0.0f;
        if (c->grip_lock < c->brake * c->speed && !c->spin) {
            /* braking that hard with a front wheel on the grass spins the
               car instead of locking the wheels (0x16259) */
            if (c->rough) c->spin = 1;
            else          c->lock = c->brake;
        }
    }
}

/* ------------------------------------------------------------------ 0x1628c */

#ifdef OS_ORIG_TICK
/* AMIGA: the original's whole-number turn: out = (z sin a + x cos a, z cos a - x sin a),
   each cut to a whole number as the x87 stores it (out of range: 0x80000000) */
static int32_t ftrunc32(double v) { return (v > -2147483649.0 && v < 2147483648.0) ? (int32_t)v : INT32_MIN; }
static void rot_y_i(int32_t o[2], const int32_t in[2], float a)
{
    const float co = cosf(a), si = sinf(a);
    o[0] = ftrunc32((double)in[1] * (double)si + (double)in[0] * (double)co);
    o[1] = ftrunc32((double)in[1] * (double)co - (double)in[0] * (double)si);
}
/* 0x1629c's end: the step's way round the turning circle -- the point (radius, rear axle) beside the car turned by the
   heading, and again by the turn; the chord between the two is how far the car moves next step (integrate). So the car
   swings about the rear axle's line, not along its nose (dr68k calls it through its context) */
static void dr_chord(car_state *c)
{
    const int32_t in[2] = { ftrunc32((double)c->radius), (int32_t)c->rear_z };
    int32_t a[2], b[2];
    rot_y_i(a, in, -c->yaw);
    rot_y_i(b, a, -c->turn);
    c->chord_x = (float)(int32_t)((uint32_t)a[0] - (uint32_t)b[0]);
    c->chord_y = (float)(int32_t)((uint32_t)a[1] - (uint32_t)b[1]);
}
#endif

static void steering(car_state *c, const drive_input *in)
{
    int stiff = c->launch ? 0x58
              : (c->lock == 0.0f && c->slide_want == 0.0f && !c->spin) ? 0x50 : 0x55;

    /* 18 degrees of lock at a standstill, falling to 1 degree at top speed */
    c->steer_max = (1.0f - sqrt0(c->speed / c->spec.maxspd)) * 0.296706f + 0.0174533f;

    float want = in->steer * c->steer_max;
    /* 0x163bb: a stick's wheel is where the stick is, unless the car is
       sliding or leaving the line -- then it is eased like the keys' */
    if ((c->analog & 2) && stiff == 0x50) c->steer = want;
    else approach(&c->steer, want, stiff);
    if (fabsf(c->steer) < 1e-5f) c->steer = 0.0f;
    /* 0x16458: on the grass the wheel is tugged about -- by up to 0.05 rad at a
       crawl, less the faster the car goes, one way or the other from one spot
       to the next -- and held to the lock */
    if (c->rough) {
        int spot = (int)c->x + (int)c->y;
        float tug = (float)(spot & 0x3f) * 0.0008f * ((spot & 1) ? -1.0f : 1.0f);
        c->steer += sqrt0(1.0f - c->speed / c->spec.maxspd) * tug;
        if (fabsf(c->steer) > c->steer_max) c->steer = c->steer < 0.0f ? -c->steer_max : c->steer_max;
    }

#ifdef OS_ORIG_TICK
    /* 0x1629c: no steering towards a front corner that is off the track */
    if ((c->steer > 0.0f && (c->front_out & 1)) || (c->steer < 0.0f && (c->front_out & 2)) || c->crash) c->steer = 0.0f;
#endif
    if (c->steer != 0.0f) {
        /* the car turns about a point one wheelbase / tan(lock) to its side */
        c->radius = c->wheelbase / tanf(c->steer);
        c->turn   = DRIVE_DT * c->speed / c->radius;
        c->yaw   += c->turn;
#ifdef OS_ORIG_TICK
        dr_chord(c);
#endif
    } else {
        c->radius = 0.0f;
        c->turn   = 0.0f;
    }
}

/* ------------------------------------------------------- 0x17d04 / 0x188a8 */

static void skid(car_state *c)
{
    const float dt = DRIVE_DT;

#ifdef OS_ORIG_TICK
    /* (0x17d14: nothing of this while spinning or in the launch; a lock counts only while there is time) */
    if (!c->spin && !c->launch && !c->launch_end && !c->crash) {
        if (c->lock == 0.0f || c->timeout) {
#else
    if (!c->spin) {
        if (c->lock == 0.0f) {
#endif
            /* cornering force: speed squared times how fast the heading turns,
               and more for every wheel that is on the grass -- 1000 a front
               wheel, 600 a rear one (0x17e5c) */
            float f = c->speed * c->speed * c->turn * 0.0001f / dt * c->surface
                    + (float)((c->grass[0] + c->grass[2]) * 1000 + (c->grass[1] + c->grass[3]) * 600)
                      * (c->turn < 0.0f ? -1.0f : 1.0f);
            if (fabsf(f) <= c->grip_slide) {
                c->slide_want = 0.0f;
                c->slip = 0.0f;
            } else if ((c->brake + 0.5f) * f <= c->grip_spin) {
                /*
                 * Past the limit: the body swings out (slip), and the car is
                 * to run wide at  surface * 0.2 * speed^2 / radius.
                 *
                 * THE GAME IS LOP-SIDED HERE, and the port follows it.  The
                 * force f and the turning radius carry the SIGN of the turn.
                 * The spin test just above (0x17efa..0x17f0f) compares f
                 * itself, not its size, with the limit: with f negative it
                 * can never be passed.  And the running-wide speed below is
                 * negative for a negative radius, which the `< 10` test at
                 * the end of this routine (0x1809b) wipes out every frame.
                 * So only turning the way that makes the heading GROW does a
                 * car run wide or spin from cornering alone; turning the
                 * other way the body swings out and that is all.  Until
                 * 2026-10-11 the port made both directions alike ("always
                 * outward"), which the game's code does not do.
                 */
                f += (f <= 0.0f) ? c->grip_slide : -c->grip_slide;
                c->slip = f * 0.00015f;
                if (fabsf(c->slip) > 1.53938f)
                    c->slip = (f < 0.0f ? -1.0f : 1.0f) * 1.53938f;
                c->slide_want = c->radius != 0.0f
                              ? c->surface * 0.2f * (c->speed * c->speed / c->radius) : 0.0f;
                c->slide_dx = sinf(c->yaw - 1.5707964f);
                c->slide_dy = -cosf(c->yaw - 1.5707964f);
            } else {
                c->spin = 1;                     /* too much, especially braking */
            }
        } else {
            /* wheels locked: slide straight on until the speed comes down */
            c->lock *= damp(98);
            if (c->lock * c->speed < 2000.0f) c->lock = 0.0f;
#ifdef OS_ORIG_TICK
            /* the body swings out by the lock's share of the speed, the way the car turns */
            const float share = c->lock * c->speed / c->spec.maxspd;
            approach(&c->slip, (c->turn < 0.0f ? -share : share) * dt * 7.0f, 7);
#else
            approach(&c->slip, 0.0f, 7);
#endif
            c->yaw += c->slip * 0.2f;
        }
        approach_angle(&c->drift, sqrt0(fabsf(cosf(c->roll)) * 2.0f) * c->slip, 0x5a);
    }
    approach(&c->slide, c->slide_want, 0x50);
    if (c->slide < 10.0f) c->slide = 0.0f;

    /* 0x188a8: a spin throws the tail round once and then settles */
    if (c->spin == 1) {
        float dir = (c->turn < 0.0f) ? 1.0f : -1.0f;
        c->spin = (int)lroundf(dir + 3.0f);              /* 2 or 4 */
        c->drift += dir * 6.2831855f;
    } else if (c->spin > 1) {
        float dir = (float)(c->spin - 3);
        float rate = (fabsf(c->drift) + 0.2f) / 3.1415927f * 3.0f * dt;
        int done = 0;
        if (dir > 0.0f) { c->drift -= rate; if (c->drift < 0.0f) done = 1; }
        if (dir < 0.0f) { c->drift += rate; if (c->drift > 0.0f) done = 1; }
        if (done) { c->drift = 0.0f; c->spin = 0; }
    }
}

/* ------------------------------------------------------------------ 0x16f24 */

#ifdef OS_ORIG_TICK
/* AMIGA: the original's (0x16f34): the heading put into 0..2 pi first; whole-number
   positions, cut after each move; driving straight along the heading over the slope, turning along the chord the
   steering left (|cos roll| of it); in the launch or a crash straight on, the slope not counted */
static void integrate(car_state *c)
{
    const float dt = DRIVE_DT;
    if (c->yaw < 0.0f) c->yaw += 6.2831855f;
    if (c->yaw > 6.2831855f) c->yaw -= 6.2831855f;
    if (!c->launch && !c->crash) {
        if (c->steer == 0.0f) {
            const float cp = cosf(c->pitch);
            const float a = sinf(c->yaw) * cp, b = cosf(c->yaw) * -cp;
            c->x = truncf(a * c->speed * dt + c->x);
            c->y = truncf(b * c->speed * dt + c->y);
        } else {
            const float cr = fabsf(cosf(c->roll));
            c->x = truncf(cr * c->chord_x + c->x);
            c->y = truncf(cr * c->chord_y + c->y);
        }
    } else {
        c->x = truncf(sinf(c->yaw) * c->speed * dt + c->x);
        c->y = truncf(c->y - cosf(c->yaw) * c->speed * dt);
    }
    c->x = truncf(c->shove_x * c->shove * dt + c->x);          /* shoved off a wall */
    c->y = truncf(c->shove_y * c->shove * dt + c->y);
    c->yaw_rate *= damp(80);
    c->yaw += c->yaw_rate * dt;
    c->shove *= damp(91);
    if (fabsf(c->shove) < 250.0f) c->shove = 0.0f;
    const float k = sqrt0(fabsf(cosf(c->roll)) * 2.0f);        /* running wide in a skid (0x172d8) */
    c->x = truncf(k * dt * (c->slide * c->slide_dx) + c->x);
    c->y = truncf(k * dt * (c->slide * c->slide_dy) + c->y);
}
#else
static void integrate(car_state *c)
{
    const float dt = DRIVE_DT;
    float cp = cosf(c->pitch);

    /* forward */
    c->x += sinf(c->yaw) * cp * c->speed * dt;
    c->y -= cosf(c->yaw) * cp * c->speed * dt;

    /* shoved off a wall */
    c->x += c->shove_x * c->shove * dt;
    c->y += c->shove_y * c->shove * dt;
    c->yaw_rate *= damp(80);
    c->yaw += c->yaw_rate * dt;
    c->shove *= damp(91);
    if (fabsf(c->shove) < 250.0f) c->shove = 0.0f;

    /*
     * Running wide in a skid (0x172d8): the car is moved along (sin, -cos) of
     * heading - 90 degrees by the slide speed.  The game sets that direction
     * when the slide starts (0x17f4d) and keeps it; the slide speed is never
     * negative (see the skid routine), so there is one direction only.
     */
#ifdef OS_ORIG_TICK
    float k = sqrt0(fabsf(cosf(c->roll)) * 2.0f);    /* (0x172d8: twice |cos roll| under the root) */
#else
    float k = sqrt0(fabsf(cosf(c->roll)));
#endif
    c->x += k * dt * c->slide * c->slide_dx;
    c->y += k * dt * c->slide * c->slide_dy;

    while (c->yaw < 0.0f)        c->yaw += 6.2831855f;
    while (c->yaw > 6.2831855f)  c->yaw -= 6.2831855f;
}
#endif

/* THE DRIVING IN VASM (port/amiga/sys/game_68k.s dr68k, dhw68k: do not reorder): every float operation as gcc
   compiles the functions above, sinf / cosf / tanf through C.  OS_DRASM=0 the C; =c both from the same state,
   compared to the bit */
typedef struct {
    car_state *c; const drive_input *in; const float *damp;     /*  0  4  8 */
    float (*sin)(float a);                                      /* 12  sinf itself: its fp0 as gcc uses it */
    void (*cos)(float a, float *out);                           /* 16 */
    float (*tan)(float a);                                      /* 20  tanf itself: its fp0 as gcc uses it */
    void (*chord)(car_state *c);                                /* 24  dr_chord (OS_ORIG_TICK) */
} dr_ctx;
_Static_assert(sizeof(car_spec) == 68 && offsetof(car_spec, maxspd) == 16 && offsetof(car_spec, nshift) == 36 &&
               offsetof(car_spec, ratio) == 40 && offsetof(car_state, x) == 68 && offsetof(car_state, gear) == 100 &&
               offsetof(car_state, analog) == 112 && offsetof(car_state, throttle) == 116 && offsetof(car_state, lock) == 140 &&
               offsetof(car_state, drift) == 156 && offsetof(car_state, spin) == 160 && offsetof(car_state, yaw_rate) == 164 &&
               offsetof(car_state, wheelbase) == 180 && offsetof(car_state, rough) == 188 && offsetof(car_state, slide_dx) == 192 &&
               offsetof(car_state, grass) == 200 && offsetof(car_state, k_rpm) == 216 && offsetof(car_state, grip_lock) == 244 &&
               offsetof(car_state, crash) == 260 && offsetof(car_state, chord_y) == 272 &&
               sizeof(car_state) == 276 && offsetof(drive_input, shift) == 12, "dr68k's offsets");
#if (defined(__m68k__) || defined(__mc68000__)) && !defined(GEO_C_ONLY) && !defined(SPAN_C_ONLY)
#define DR_ASM 1
void dr68k(const dr_ctx *x);
void dhw68k(const dr_ctx *x, float push_x, float push_y, float side, float wall_angle);
static void dr_cos(float a, float *out) { *out = cosf(a); }
static const float *damp_tab(void)
{
#ifdef OS_ORIG_TICK
    row_make(g_row);
    return tab;
#else
    static int made;
    if (!made) { for (int i = 0; i < 128; i++) (void)damp(i); made = 1; }
    return tab;
#endif
}
static int dr_mode(void)
{
    static int mode = -1;
    if (mode < 0) { const char *e = getenv("OS_DRASM"); mode = e && e[0] == '0' ? 0 : e && e[0] == 'c' ? 2 : 1; }
    return mode;
}
static void dr_check(const char *what, const car_state *a, const car_state *c)
{
    static long calls[2], bad;
    const int w = what[0] == 's' ? 0 : 1;
    calls[w]++;
    if (memcmp(a, c, sizeof *a) && bad++ < 10) {
        printf("drcheck: %s DIFFERS (call %ld)\n", what, calls[w]);
        for (int k = 0; k < (int)(sizeof *a / 4); k++)
            if (((const uint32_t *)a)[k] != ((const uint32_t *)c)[k])
                printf("  car byte %d: asm %08x C %08x\n", k * 4, ((const uint32_t *)a)[k], ((const uint32_t *)c)[k]);
    }
    if (w == 0 && (calls[0] & 255) == 0) printf("drcheck: %ld steps, %ld walls, %ld different\n", calls[0], calls[1], bad);
}
#endif

/* 0x16c90: glancing a wall scrubs speed by how squarely it was hit.
   `side` is (front-right corner out) - (front-left corner out): the game turns
   the nose with exactly that, so a hit with the tail alone does not steer. */
static void drive_hit_wall_c(car_state *c, float push_x, float push_y, float side,
                    float wall_angle)
{
    float len = sqrtf(push_x * push_x + push_y * push_y);
    if (len < 1e-3f) return;
    /* how squarely the wall was hit: |sin(heading + wall angle)| (0x16cec) */
    float square = fabsf(sinf(c->yaw + wall_angle));
    c->shove_x = push_x / len;
    c->shove_y = push_y / len;
    /* 0x16df4: square^4 * speed * 2 + 2000, at most 5000 -- so a glancing
       scrape gets little more than the flat 2000, and only a square hit the
       full shove */
    c->shove = square * square * square * square * c->speed * 2.0f + 2000.0f;
    if (c->shove > 5000.0f) c->shove = 5000.0f;
    c->speed -= c->speed * 0.9f * square;
    if (c->speed < 0.0f) c->speed = 0.0f;
    c->yaw_rate = side * 5.0f * square;        /* the nose is turned along the wall */
    c->lock = 0.0f;
    c->slip = 0.0f;
    c->slide_want = 0.0f;
    if (!c->spin) c->drift = 0.0f;
}

void drive_hit_wall(car_state *c, float push_x, float push_y, float side, float wall_angle)
{
#ifdef DR_ASM
    const int m = dr_mode();
    if (m) {
        const dr_ctx x = { c, NULL, damp_tab(), sinf, dr_cos, tanf, dr_chord };
        if (m == 1) { dhw68k(&x, push_x, push_y, side, wall_angle); return; }
        const car_state c0 = *c;
        dhw68k(&x, push_x, push_y, side, wall_angle);
        const car_state c1 = *c;
        *c = c0;
        drive_hit_wall_c(c, push_x, push_y, side, wall_angle);
        dr_check("wall", &c1, c);
        return;
    }
#endif
    drive_hit_wall_c(c, push_x, push_y, side, wall_angle);
}

static void drive_step_c(car_state *c, const drive_input *in)
{
    integrate(c);
    engine(c, in);
    pedals(c, in);
    steering(c, in);
    skid(c);
#ifdef OS_ORIG_TICK
    /* the car's state at the picture's end (0x15c1c): wheels spinning off the line turn it with the steering, once a
       picture, in gear; the launch's last step is over */
    if (c->launch && c->gear != 0) c->yaw += c->steer * 0.3f;
    c->launch_end = 0;
#endif
}


void drive_step(car_state *c, const drive_input *in)
{
#ifdef DR_ASM
    const int m = dr_mode();
    if (m) {
        const dr_ctx x = { c, in, damp_tab(), sinf, dr_cos, tanf, dr_chord };
        if (m == 1) { dr68k(&x); return; }
        static long kick;
        if (getenv("OS_DRKICK") && ++kick > 300 && kick % 23 == 0) {   /* (a test: the rare ways, for both alike) */
            switch ((kick / 23) % 9) {
            case 0: c->lock = 1.0f; break;
            case 1: c->spin = 1; break;
            case 2: c->rough = 1; c->grass[0] = c->grass[1] = 1; break;
            case 3: c->speed = c->spec.maxspd; c->steer = c->steer_max * ((kick & 1) ? 0.9f : -0.9f); break;
            case 4: c->analog = 6; break;
            case 5: c->waiting = 1; break;
            case 6: c->rough = 0; c->grass[0] = c->grass[1] = 0; c->analog = 0; c->waiting = 0; c->drift = 0.05f; break;
            case 7: c->timeout = 1; c->crash = 0; c->drift = -0.3f; break;
            case 8: c->timeout = 0; c->crash = 1; c->analog = (kick & 1) ? 4 : 0; break;
            }
        }
        const car_state c0 = *c;
        dr68k(&x);
        const car_state c1 = *c;
        *c = c0;
        drive_step_c(c, in);
        dr_check("step", &c1, c);
        return;
    }
#endif
    drive_step_c(c, in);
}
