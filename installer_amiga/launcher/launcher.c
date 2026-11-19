/* Starter für Screamer (Amiga, MUI): Programmwahl (ASL), Bildschirm RTG/AGA, Fenster, Ton Paula/AHI mit AHI-Modus,
 * Einzel-/Mehrspieler mit Gastgeber/Beitreten (Musik nur im Spiel, Optionen-Menü). Erweiterung des Ports, kein Original-Code (docs/amiga.md).
 *  - Spieleinstellungen: CONFIG/AMIGA.CFG im Verzeichnis des gewählten Programms, dieselbe Datei wie Setup und Spiel
 *    (SCREEN/SOUND/AHIMODE/NETMODE/NETHOST); fremde Zeilen bleiben erhalten, eine alte MUSIC-Zeile wird entfernt.
 *  - eigene Angaben (PROGRAM/WINDOW/SCALE): CONFIG/LAUNCHER.CFG im Verzeichnis des Starters.
 *  - Steuerung (Fenster „Tasten und Joypad“): Tasten der 6 Aktionen in CONFIG/CONTROLS.CFG (Tastaturmodus wie das
 *    Original-Setup), Knöpfe des Pads im Rennen als PADGAS ... PADPAUSE in AMIGA.CFG (src/game/input.c).
 *  - Start mit Taskpriorität 0, Fenster und Skalierung als Argumente (--window, --scale N).
 * Texte englisch eingebaut, Übersetzung per Katalog amiscreamer_launcher.catalog (launcher_strings.h). */
#include <exec/types.h>
#ifndef IPTR
typedef ULONG IPTR;                             /* NDK 3.9 kennt IPTR nicht */
#endif
#include <exec/execbase.h>
#include <dos/dos.h>
#include <dos/dostags.h>
#include <graphics/gfxbase.h>
#include <libraries/mui.h>
#include <libraries/asl.h>
#include <libraries/gadtools.h>
#include <libraries/locale.h>
#include <devices/ahi.h>
#include <devices/inputevent.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/intuition.h>
#include <proto/muimaster.h>
#include <proto/locale.h>
#include <proto/ahi.h>
#include <proto/graphics.h>
#include <proto/keymap.h>
#include <clib/alib_protos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "launcher_strings.h"
/* MUI 3.8 (muimaster 19.x) genügt; der MUI-Header der Toolchain setzt MUIMASTER_VMIN auf 20 (MUI 4/5 SDK) -> unter
 * MUI 3.8 schlug OpenLibrary fehl ("Benötigt muimaster.library V19"). Fest auf 19, wie Meldung und Doku. */
#undef MUIMASTER_VMIN
#define MUIMASTER_VMIN 19
#include "rawkey.h"

#ifndef AFF_68080
#define AFF_68080 (1 << 10)
#endif
#define LAUNCHER_VERSION "1.01"
#define NET_PORT 10623                          /* wie src/game/net.h */
#define CFG_MAX 2048

static const char s_ver[] __attribute__((used)) = "$VER: amiscreamer_launcher " LAUNCHER_VERSION " (19.11.2026)";

struct Library *MUIMasterBase, *AHIBase, *KeymapBase;
struct LocaleBase *LocaleBase;
extern struct GfxBase *GfxBase;
static struct Catalog *s_cat;
static struct MsgPort *s_ahiport;
static struct AHIRequest *s_ahireq;

/* ------------------------------------------------------------------ Texte */
#define S(name, id, txt) [id] = txt, /* by number: number 20 (the old MUSIC text) is free */
static const char *const s_builtin[MSG_COUNT] = {LAUNCHER_STRINGS};
#undef S
static const char *T(int id)
{
    return s_cat ? (const char *)GetCatalogStr(s_cat, id, (STRPTR)s_builtin[id]) : s_builtin[id];
}

/* ------------------------------------------------------------------ Einstellungen */
enum { SCR_RTG640, SCR_RTG320, SCR_AGA320 };
enum { SND_OFF, SND_PAULA, SND_AHI };
enum { NET_OFF, NET_HOST, NET_JOIN };
static const char *const s_scrkey[3] = {"RTG640", "RTG320", "AGA320"}, *const s_sndkey[3] = {"OFF", "PAULA", "AHI"};
static const char *const s_netkey[3] = {"OFF", "HOST", "JOIN"};

static struct {
    char prog[256];
    int screen, window, scale;                  /* scale 1..3 */
    int snd;
    ULONG ahimode;
    int net;                                    /* NET_* */
    char host[128];                             /* Gastgeber/Server; Port fest 10623 (sonst adresse:port eintippen) */
    int key[6];                                 /* Scancode je Aktion (Gas, Bremse, links, rechts, hoch, runter), 0 = keine */
    int pad[7];                                 /* Pad-Knopf je Aktion (+ Pause), PB_* , -1 = keiner */
} c;

/* Steuerung: Pad-Knöpfe wie plat.h PAD_* (Reihenfolge), Schlüssel/Werte in AMIGA.CFG wie src/game/input.c */
enum { PB_LEFT, PB_RIGHT, PB_UP, PB_DOWN, PB_RED, PB_BLUE, PB_GREEN, PB_YELLOW, PB_PLAY, PB_FWD, PB_REV, PB_N };
static const char *const s_padval[PB_N] = {"LEFT", "RIGHT", "UP", "DOWN", "RED", "BLUE", "GREEN", "YELLOW", "PLAY",
                                           "FWD", "REV"};
static const char *const s_padkey[7] = {"PADGAS", "PADBRAKE", "PADLEFT", "PADRIGHT", "PADUP", "PADDOWN", "PADPAUSE"};
static const int s_pad_def[7] = {PB_RED, PB_BLUE, PB_LEFT, PB_RIGHT, PB_FWD, PB_REV, PB_PLAY};
static const int s_key_def[6] = {0x48, 0x50, 0x4b, 0x4d, 0x38, 0x1d};   /* wie DEFCTRL.CFG */
enum { CTL_SIZE = 1328 };
static uint8_t s_ctl[CTL_SIZE];                 /* CONTROLS.CFG (Little Endian) */
static int s_ctl_ok;

static char s_mydir[256];                       /* Verzeichnis des Starters */
static int s_have_rtg, s_have_aga, s_have_ahi;

/* "SCHLUESSEL=WERT" aus einem Textpuffer */
static int cfg_find(const char *buf, const char *key, char *val, int n)
{
    size_t kl = strlen(key);
    for (const char *l = buf; *l;) {
        if (!strncmp(l, key, kl) && l[kl] == '=') {
            int i = 0;
            for (l += kl + 1; *l && *l != '\r' && *l != '\n' && i < n - 1; l++)
                val[i++] = *l;
            val[i] = 0;
            return 1;
        }
        while (*l && *l != '\n')
            l++;
        while (*l == '\n' || *l == '\r')
            l++;
    }
    return 0;
}

static int file_read(const char *path, char *buf, int n)
{
    FILE *f = fopen(path, "rb");
    if (!f) {
        buf[0] = 0;
        return 0;
    }
    size_t r = fread(buf, 1, (size_t)n - 1, f);
    buf[r] = 0;
    fclose(f);
    return 1;
}

/* Verzeichnis + Name (AddPart, Amiga-Pfade) */
static void path_join(char *out, int n, const char *dir, const char *name)
{
    snprintf(out, (size_t)n, "%s", dir);
    AddPart((STRPTR)out, (CONST_STRPTR)name, (ULONG)n);
}

/* CONFIG/<name> im Verzeichnis des Programms prog */
static void prog_cfg_path(char *out, int n, const char *prog, const char *name)
{
    char dir[256], sub[64];
    snprintf(dir, sizeof dir, "%s", prog);
    *PathPart((STRPTR)dir) = 0;
    snprintf(sub, sizeof sub, "CONFIG/%s", name);
    path_join(out, n, dir, sub);
}

static int file_exists(const char *path)
{
    BPTR l = Lock((CONST_STRPTR)path, ACCESS_READ);
    if (l)
        UnLock(l);
    return l != 0;
}

/* Vorgabe-Programm nach CPU, nur vorhandene Dateien */
static void default_prog(void)
{
    UWORD af = SysBase->AttnFlags;
    const char *pref[4];
    int k = 0;
    if (af & AFF_68080)
        pref[k++] = "amiscreamer_080";
    if (af & (AFF_68060 | AFF_68080))
        pref[k++] = "amiscreamer_060";
    pref[k++] = "amiscreamer_040";
    pref[k++] = "amiscreamer_060";
    for (int i = 0; i < k; i++) {
        path_join(c.prog, sizeof c.prog, s_mydir, pref[i]);
        if (file_exists(c.prog))
            return;
    }
    path_join(c.prog, sizeof c.prog, s_mydir, pref[0]);
}

static uint32_t rd32le(const uint8_t *p) { return p[0] | p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static void wr32le(uint8_t *p, uint32_t v) { p[0] = (uint8_t)v, p[1] = (uint8_t)(v >> 8), p[2] = (uint8_t)(v >> 16), p[3] = (uint8_t)(v >> 24); }

static int file_bin(const char *path, uint8_t *buf, int n)
{
    FILE *f = fopen(path, "rb");
    if (!f)
        return 0;
    int r = (int)fread(buf, 1, (size_t)n, f);
    fclose(f);
    return r;
}

/* Tasten je Aktion aus einer CONTROLS-Datei (Eintrag i bei 28 i: +0 aktiv, +8 Gerät 1 = Tastatur, +24 Scancode) */
static void ctl_keys(const uint8_t *b, int *key)
{
    for (int i = 0; i < 6; i++) {
        const uint8_t *e = b + 28 * i;
        key[i] = rd32le(e) == 1 && rd32le(e + 8) == 1 ? (int)(rd32le(e + 24) & 0x7f) : 0;
    }
}

/* CONTROLS.CFG des Programms (sonst DEFCTRL.CFG) -> s_ctl, c.key */
static void ctl_load(const char *prog)
{
    char path[300];
    prog_cfg_path(path, sizeof path, prog, "CONTROLS.CFG");
    s_ctl_ok = file_bin(path, s_ctl, CTL_SIZE) == CTL_SIZE;
    if (!s_ctl_ok) {
        prog_cfg_path(path, sizeof path, prog, "DEFCTRL.CFG");
        s_ctl_ok = file_bin(path, s_ctl, CTL_SIZE) == CTL_SIZE;
    }
    if (s_ctl_ok)
        ctl_keys(s_ctl, c.key);
    else
        memcpy(c.key, s_key_def, sizeof c.key);
}

/* Vorgabe-Tasten aus DEFCTRL.CFG des Programms */
static void ctl_defaults(const char *prog)
{
    char path[300];
    uint8_t b[CTL_SIZE];
    prog_cfg_path(path, sizeof path, prog, "DEFCTRL.CFG");
    if (file_bin(path, b, CTL_SIZE) == CTL_SIZE)
        ctl_keys(b, c.key);
    else
        memcpy(c.key, s_key_def, sizeof c.key);
}

/* c.key -> CONTROLS.CFG (Tastaturmodus wie das Original-Setup: aktiv, digital, Tastatur, Scancode); Rest bleibt */
static int ctl_save(const char *prog, char *failed, int n)
{
    char path[300];
    if (!s_ctl_ok) {                            /* nichts als Vorlage: Datei nicht anfassen */
        snprintf(failed, (size_t)n, "%s", prog);
        return -1;
    }
    for (int i = 0; i < 6; i++) {
        uint8_t *e = s_ctl + 28 * i;
        wr32le(e, 1);
        wr32le(e + 4, 0);
        wr32le(e + 8, 1);
        wr32le(e + 24, (uint32_t)c.key[i]);
    }
    prog_cfg_path(path, sizeof path, prog, "CONTROLS.CFG");
    FILE *f = fopen(path, "wb");
    int ok = f && fwrite(s_ctl, 1, CTL_SIZE, f) == CTL_SIZE;
    if (f && fclose(f))
        ok = 0;
    if (!ok)
        snprintf(failed, (size_t)n, "%s", path);
    return ok;
}

/* Name einer Taste (DOS-Set-1-Scancode): Sondertasten fest, Zeichentasten über die Tastaturbelegung (MapRawKey) */
static const char *key_name(int sc)
{
    static const struct { uint8_t sc; const char *n; } sp[] = {
        {0x01, "ESC"}, {0x0e, "BACKSPACE"}, {0x0f, "TAB"}, {0x1c, "RETURN"}, {0x1d, "CTRL"}, {0x2a, "SHIFT L"},
        {0x36, "SHIFT R"}, {0x38, "ALT"}, {0x39, "SPACE"}, {0x3a, "CAPS LOCK"}, {0x3b, "F1"}, {0x3c, "F2"},
        {0x3d, "F3"}, {0x3e, "F4"}, {0x3f, "F5"}, {0x40, "F6"}, {0x41, "F7"}, {0x42, "F8"}, {0x43, "F9"},
        {0x44, "F10"}, {0x48, "CURSOR UP"}, {0x50, "CURSOR DOWN"}, {0x4b, "CURSOR LEFT"}, {0x4d, "CURSOR RIGHT"},
        {0x53, "DEL"}, {0x57, "HELP"}, {0x47, "NUM 7"}, {0x49, "NUM 9"}, {0x4a, "NUM -"}, {0x4c, "NUM 5"},
        {0x4e, "NUM +"}, {0x4f, "NUM 1"}, {0x51, "NUM 3"}, {0x52, "NUM 0"}, {0x37, "NUM *"}, {0x45, "NUM ("},
        {0x46, "NUM )"}};
    static char t[16];
    if (!sc)
        return T(MSG_KEY_NONE);
    for (unsigned i = 0; i < sizeof sp / sizeof sp[0]; i++)
        if (sp[i].sc == sc)
            return sp[i].n;
    for (int r = 0; r < 0x3b; r++)              /* Hauptfeld */
        if (s_raw2set1[r] == sc && r != 0x0f && r != 0x1d && r != 0x1e && r != 0x1f && r != 0x2d && r != 0x2e &&
            r != 0x2f) {
            if (KeymapBase) {
                struct InputEvent ie;
                memset(&ie, 0, sizeof ie);
                ie.ie_Class = IECLASS_RAWKEY;
                ie.ie_Code = (UWORD)r;
                char b[8];
                LONG k = MapRawKey(&ie, (STRPTR)b, sizeof b, NULL);
                if (k == 1 && (UBYTE)b[0] > ' ') {
                    t[0] = b[0] >= 'a' && b[0] <= 'z' ? (char)(b[0] - 32) : b[0];
                    t[1] = 0;
                    return t;
                }
            }
            break;
        }
    snprintf(t, sizeof t, "#%02X", sc);
    return t;
}

static void cfg_load(void)
{
    static char buf[CFG_MAX];
    char path[300], v[128];
    c.screen = s_have_rtg ? SCR_RTG640 : SCR_AGA320;
    c.scale = 1;
    c.snd = SND_PAULA;
    c.ahimode = AHI_DEFAULT_ID;
    path_join(path, sizeof path, s_mydir, "CONFIG/LAUNCHER.CFG");
    file_read(path, buf, sizeof buf);
    if (cfg_find(buf, "PROGRAM", v, sizeof v) && v[0])
        snprintf(c.prog, sizeof c.prog, "%s", v);
    else
        default_prog();
    if (cfg_find(buf, "WINDOW", v, sizeof v))
        c.window = atoi(v) != 0;
    if (cfg_find(buf, "SCALE", v, sizeof v))
        c.scale = atoi(v) < 1 ? 1 : atoi(v) > 3 ? 3 : atoi(v);
    prog_cfg_path(path, sizeof path, c.prog, "AMIGA.CFG");
    file_read(path, buf, sizeof buf);
    if (cfg_find(buf, "SCREEN", v, sizeof v))
        c.screen = !strcmp(v, "RTG640") ? SCR_RTG640 : !strcmp(v, "RTG320") ? SCR_RTG320 : SCR_AGA320;
    if (cfg_find(buf, "SOUND", v, sizeof v))
        c.snd = !strcmp(v, "AHI") ? SND_AHI : !strcmp(v, "PAULA") ? SND_PAULA : SND_OFF;
    if (cfg_find(buf, "AHIMODE", v, sizeof v))
        c.ahimode = strtoul(v, NULL, 16);
    if (cfg_find(buf, "NETMODE", v, sizeof v))
        c.net = !strcmp(v, "HOST") ? NET_HOST : !strcmp(v, "JOIN") ? NET_JOIN : NET_OFF;
    if (cfg_find(buf, "NETHOST", v, sizeof v))
        snprintf(c.host, sizeof c.host, "%s", v);
    if (c.screen != SCR_AGA320 && !s_have_rtg)
        c.screen = SCR_AGA320;
    if (c.screen == SCR_AGA320 && !s_have_aga && s_have_rtg)
        c.screen = SCR_RTG640;
    if (c.snd == SND_AHI && !s_have_ahi)
        c.snd = SND_PAULA;
    for (int a = 0; a < 7; a++) {
        c.pad[a] = s_pad_def[a];
        if (cfg_find(buf, s_padkey[a], v, sizeof v)) {
            c.pad[a] = -1;
            for (int k = 0; k < PB_N; k++)
                if (!strcmp(v, s_padval[k]))
                    c.pad[a] = k;
        }
    }
    ctl_load(c.prog);
}

/* Datei neu schreiben: eigene Schlüssel ersetzen, fremde Zeilen behalten */
static int cfg_write(const char *path, const char *head, const char *const *keys, const char *const *vals, int nk)
{
    static char old[CFG_MAX];
    file_read(path, old, sizeof old);
    FILE *f = fopen(path, "wb");
    if (!f)
        return 0;
    fprintf(f, "%s\n", head);
    for (int i = 0; i < nk; i++)
        if (vals[i])                            /* NULL: Schlüssel entfernen */
            fprintf(f, "%s=%s\n", keys[i], vals[i]);
    for (char *l = old; *l;) {
        char *e = l;
        while (*e && *e != '\n' && *e != '\r')
            e++;
        int own = *l == ';';                    /* alte Kopfzeile */
        for (int i = 0; i < nk && !own; i++) {
            size_t kl = strlen(keys[i]);
            own = !strncmp(l, keys[i], kl) && l[kl] == '=';
        }
        if (!own && e > l)
            fprintf(f, "%.*s\n", (int)(e - l), l);
        while (*e == '\n' || *e == '\r')
            e++;
        l = e;
    }
    int ok = !ferror(f);
    return fclose(f) == 0 && ok;
}

static int cfg_save(char *failed, int n)
{
    char path[300], ahi[16], win[4], scale[4];
    snprintf(ahi, sizeof ahi, "%08lX", (unsigned long)c.ahimode);
    const char *host = c.host;
    static const char *const k1[13] = {"SCREEN", "SOUND", "AHIMODE", "MUSIC", "NETMODE", "NETHOST", "PADGAS",
                                       "PADBRAKE", "PADLEFT", "PADRIGHT", "PADUP", "PADDOWN", "PADPAUSE"};
    /* MUSIC: nicht mehr im Starter (nur im Spiel über die Lautstärke im Optionen-Menü); eine alte Zeile (z. B. OFF)
     * wird entfernt, sonst bliebe die Musik ohne Einstellmöglichkeit aus */
    const char *v1[13] = {s_scrkey[c.screen], s_sndkey[c.snd], ahi, NULL, s_netkey[c.net], host};
    for (int a = 0; a < 7; a++)
        v1[6 + a] = c.pad[a] < 0 ? "NONE" : s_padval[c.pad[a]];
    prog_cfg_path(path, sizeof path, c.prog, "AMIGA.CFG");
    if (!cfg_write(path, "; AmiScreamer - geschrieben vom Starter", k1, v1, 13)) {
        snprintf(failed, (size_t)n, "%s", path);
        return 0;
    }

    path_join(path, sizeof path, s_mydir, "CONFIG");
    BPTR l = Lock((CONST_STRPTR)path, ACCESS_READ);
    if (!l)
        l = CreateDir((CONST_STRPTR)path);
    if (l)
        UnLock(l);
    path_join(path, sizeof path, s_mydir, "CONFIG/LAUNCHER.CFG");
    snprintf(win, sizeof win, "%d", c.window);
    snprintf(scale, sizeof scale, "%d", c.scale);
    static const char *const k2[3] = {"PROGRAM", "WINDOW", "SCALE"};
    const char *v2[3] = {c.prog, win, scale};
    if (!cfg_write(path, "; Screamer Launcher", k2, v2, 3)) {
        snprintf(failed, (size_t)n, "%s", path);
        return 0;
    }
    return ctl_save(c.prog, failed, n);         /* 1, 0 Schreibfehler, -1 keine Vorlage */
}

/* ------------------------------------------------------------------ AHI */
static void ahi_open(void)
{
    if (!(s_ahiport = CreateMsgPort()))
        return;
    s_ahireq = (struct AHIRequest *)CreateIORequest(s_ahiport, sizeof *s_ahireq);
    if (!s_ahireq)
        return;
    s_ahireq->ahir_Version = 4;
    if (OpenDevice((CONST_STRPTR)AHINAME, AHI_NO_UNIT, (struct IORequest *)s_ahireq, 0)) {
        s_ahireq->ahir_Std.io_Device = NULL;
        return;
    }
    AHIBase = (struct Library *)s_ahireq->ahir_Std.io_Device;
    s_have_ahi = 1;
}
static void ahi_close(void)
{
    if (AHIBase)
        CloseDevice((struct IORequest *)s_ahireq);
    if (s_ahireq)
        DeleteIORequest((struct IORequest *)s_ahireq);
    if (s_ahiport)
        DeleteMsgPort(s_ahiport);
    AHIBase = NULL;
}
static const char *ahi_name(ULONG id)
{
    static char nm[80];
    if (id == AHI_DEFAULT_ID || !AHIBase ||
        !AHI_GetAudioAttrs(id, NULL, AHIDB_Name, (ULONG)nm, AHIDB_BufferLen, sizeof nm, TAG_DONE))
        return T(MSG_AHI_DEFAULT);
    return nm;
}

/* ------------------------------------------------------------------ Oberfläche */
enum { ID_UPDATE = 1, ID_AHI, ID_START, ID_SAVE, ID_ABOUT, ID_ABOUTMUI, ID_CTRL, ID_CCLOSE, ID_KDEF, ID_PDEF,
       ID_KEYDONE, ID_KEY0 = 100, ID_PAD0 = 110 };
static const int s_act_msg[7] = {MSG_A_GAS, MSG_A_BRAKE, MSG_A_LEFT, MSG_A_RIGHT, MSG_A_UP, MSG_A_DOWN, MSG_A_PAUSE};
static Object *cwin, *o_key[6], *o_keyb[6], *o_pad[7];
static const char *s_pb_e[PB_N + 2];            /* Auswahl: keiner, PB_* */

/* Tastenfeld (Unterklasse von Text): MUIM_KeyGrab_Start zeigt „Taste drücken…“ und nimmt über einen Ereignis-Handler
 * des Fensters die nächste gedrückte Taste (Rawkey -> DOS-Set-1, rawkey.h); Esc bricht ab, Esc/P und nicht abbildbare
 * Tasten piepen. Ergebnis in s_grab_sc (0 = abgebrochen) / s_grab_idx, dann ReturnID ID_KEYDONE. */
#define MUIM_KeyGrab_Start 0xfec10001
#define MUIM_KeyGrab_Stop  0xfec10002
struct KgData { struct MUI_EventHandlerNode ehn; int on, added; };
static struct MUI_CustomClass *s_kgcl;
static Object *s_grab_obj;
static int s_grab_sc, s_grab_idx;

static void kg_stop(struct IClass *cl, Object *obj)
{
    struct KgData *d = INST_DATA(cl, obj);
    d->on = 0;
    if (d->added) {
        DoMethod(_win(obj), MUIM_Window_RemEventHandler, (IPTR)&d->ehn);
        d->added = 0;
    }
}

static ULONG kg_dispatch(register struct IClass *cl __asm("a0"), register Object *obj __asm("a2"),
                         register Msg msg __asm("a1"))
{
    struct KgData *d;
    switch (msg->MethodID) {
    case MUIM_KeyGrab_Start:
        d = INST_DATA(cl, obj);
        if (d->on || d->added)
            return 0;
        memset(&d->ehn, 0, sizeof d->ehn);
        d->ehn.ehn_Priority = 10;               /* vor den Tastenkürzeln des Fensters */
        d->ehn.ehn_Object = obj;
        d->ehn.ehn_Class = cl;
        d->ehn.ehn_Events = IDCMP_RAWKEY;
        DoMethod(_win(obj), MUIM_Window_AddEventHandler, (IPTR)&d->ehn);
        d->on = d->added = 1;
        set(obj, MUIA_Text_Contents, (IPTR)T(MSG_PRESS_KEY2));
        return 0;
    case MUIM_KeyGrab_Stop:
        kg_stop(cl, obj);
        return 0;
    case MUIM_HandleEvent: {
        struct MUIP_HandleEvent *m = (struct MUIP_HandleEvent *)msg;
        d = INST_DATA(cl, obj);
        if (!d->on || !m->imsg || m->imsg->Class != IDCMP_RAWKEY)
            return 0;
        UWORD code = m->imsg->Code;
        if (code & IECODE_UP_PREFIX)
            return MUI_EventHandlerRC_Eat;
        int k = code < sizeof s_raw2set1 ? s_raw2set1[code] : 0;
        if (code == 0x45)                       /* Esc: abbrechen */
            k = 0;
        else if (!k || k == 0x01 || k == 0x19) {   /* nicht belegbar; Esc/P sind Pause */
            DisplayBeep(NULL);
            return MUI_EventHandlerRC_Eat;
        }
        s_grab_sc = k;
        s_grab_idx = (int)muiUserData(obj);
        d->on = 0;                              /* Handler erst außerhalb des Ereignisses abmelden */
        DoMethod(_app(obj), MUIM_Application_PushMethod, (IPTR)obj, 1, MUIM_KeyGrab_Stop);
        DoMethod(_app(obj), MUIM_Application_PushMethod, (IPTR)_app(obj), 2, MUIM_Application_ReturnID, ID_KEYDONE);
        return MUI_EventHandlerRC_Eat;
    }
    case MUIM_Cleanup:
        kg_stop(cl, obj);
        break;
    }
    return DoSuperMethodA(cl, obj, msg);
}

static Object *app, *win, *o_prog, *o_screen, *o_window, *o_scale, *o_snd, *o_ahibtn, *o_ahiname;
static Object *o_mode, *o_net, *o_host, *o_hint, *l_net, *l_host, *l_hint;
static const char *s_scr_e[4], *s_snd_e[4], *s_scale_e[4], *s_mode_e[3], *s_net_e[3];
static int s_scr_map[3], s_nscr, s_snd_map[3], s_nsnd;  /* Cycle-Eintrag -> SCR_x bzw. SND_x (nur vorhandene) */
static struct NewMenu s_menu[5];

static int idx_of(const int *map, int n, int v)
{
    for (int i = 0; i < n; i++)
        if (map[i] == v)
            return i;
    return 0;
}

static LONG getl(Object *o, ULONG attr)
{
    IPTR v = 0;
    get(o, attr, &v);
    return (LONG)v;
}

/* Oberfläche -> c */
static void gui_read(void)
{
    STRPTR s = NULL;
    get(o_prog, MUIA_String_Contents, &s);
    snprintf(c.prog, sizeof c.prog, "%s", s ? (char *)s : "");
    c.screen = s_scr_map[getl(o_screen, MUIA_Cycle_Active)];
    c.window = getl(o_window, MUIA_Selected) != 0;
    c.scale = (int)getl(o_scale, MUIA_Cycle_Active) + 1;
    c.snd = s_snd_map[getl(o_snd, MUIA_Cycle_Active)];
    c.net = getl(o_mode, MUIA_Cycle_Active) ? (getl(o_net, MUIA_Cycle_Active) ? NET_JOIN : NET_HOST) : NET_OFF;
    s = NULL;
    get(o_host, MUIA_String_Contents, &s);
    const char *h = s ? (const char *)s : "";
    while (*h == ' ')
        h++;
    snprintf(c.host, sizeof c.host, "%s", h);
}

/* abhängige Felder an-/abschalten */
static void gui_ghost(void)
{
    gui_read();
    int aga = c.screen == SCR_AGA320;
    set(o_window, MUIA_Disabled, aga);
    set(o_scale, MUIA_Disabled, aga || !c.window);
    set(o_ahibtn, MUIA_Disabled, c.snd != SND_AHI);
    set(o_ahiname, MUIA_Disabled, c.snd != SND_AHI);
    set(l_net, MUIA_ShowMe, c.net != NET_OFF);  /* Zeilen unter „Spielart“ je nach Einzel-/Mehrspieler */
    set(l_host, MUIA_ShowMe, c.net == NET_JOIN);
    set(l_hint, MUIA_ShowMe, c.net == NET_HOST);
}

static Object *label1(int id) { return Label1(T(id)); }

/* Titellogo: der Block ist im verteilten Programm leer (keine Originalgrafik). Der Installer
 * („amiscreamer_inst logo“) sucht ihn in der installierten Programmdatei über die Kennungen, schreibt das Logo aus GRAF.DAT
 * der CD hinein und setzt tag auf "SCRLOGO1". Lage: tag 8, w/h/ncol/wy0/wy1/pad je UWORD, rgb[3 * 64] (Farbe i bei
 * 3 (i - 1)), px[44 * 320] (Index je Pixel, 0 = durchsichtig), end 8. Nicht static und nicht const, damit der Übersetzer
 * die Nullen nicht als Konstanten einsetzt (der Inhalt ändert sich erst in der Datei). */
enum { LOGO_MAXW = 44, LOGO_MAXH = 320, LOGO_MAXC = 64 };
struct LogoBlock { char tag[8]; UWORD w, h, ncol, wy0, wy1, pad; UBYTE rgb[3 * LOGO_MAXC]; UBYTE px[LOGO_MAXW * LOGO_MAXH];
                   char end[8]; };
struct LogoBlock screamer_logo_block = {"SCRLOGO0", 0, 0, 0, 0, 0, 0, {0}, {0}, "SCRLOGOE"};
#define LB screamer_logo_block
static int logo_ok(void)
{
    return !memcmp(LB.tag, "SCRLOGO1", 8) && LB.w == LOGO_MAXW && LB.h > 0 && LB.h <= LOGO_MAXH && LB.ncol <= LOGO_MAXC &&
           LB.wy0 <= LB.wy1 && LB.wy1 < LB.h;
}

/* Titellogo links im Hauptfenster (eigene Klasse, Unterklasse von Area): ganzes Bild mit Linien höchstens LB.h hoch,
 * mindestens die Zeilen des Worts (LB.wy0..LB.wy1); ist das Fenster niedriger, werden die Linien oben und unten
 * abgeschnitten, das Wort bleibt in der Mitte. Farben über ObtainBestPen, 0 durchsichtig. Ohne Spieldaten beim Bauen leer. */
struct LgData { LONG pen[LOGO_MAXC]; };
static struct MUI_CustomClass *s_lgcl;

static ULONG lg_dispatch(register struct IClass *cl __asm("a0"), register Object *obj __asm("a2"),
                         register Msg msg __asm("a1"))
{
    struct LgData *d = INST_DATA(cl, obj);
    switch (msg->MethodID) {
    case MUIM_Setup: {
        if (!DoSuperMethodA(cl, obj, msg))
            return FALSE;
        struct ColorMap *cm = _screen(obj)->ViewPort.ColorMap;
        d->pen[0] = -1;
        for (int i = 1; i < LB.ncol; i++) {
            const UBYTE *c = LB.rgb + 3 * (i - 1);
            d->pen[i] = ObtainBestPen(cm, c[0] * 0x01010101u, c[1] * 0x01010101u, c[2] * 0x01010101u,
                                      OBP_Precision, PRECISION_IMAGE, TAG_DONE);
        }
        return TRUE;
    }
    case MUIM_Cleanup: {
        struct ColorMap *cm = _screen(obj)->ViewPort.ColorMap;
        for (int i = 1; i < LB.ncol; i++)
            if (d->pen[i] >= 0)
                ReleasePen(cm, (ULONG)d->pen[i]);
        break;
    }
    case MUIM_AskMinMax: {
        DoSuperMethodA(cl, obj, msg);
        struct MUI_MinMax *mi = ((struct MUIP_AskMinMax *)msg)->MinMaxInfo;
        mi->MinWidth += LB.w;
        mi->DefWidth += LB.w;
        mi->MaxWidth += LB.w;
        mi->MinHeight += LB.wy1 - LB.wy0 + 1;
        mi->DefHeight += LB.h;
        mi->MaxHeight = MUI_MAXMAX;                             /* nimmt jede Höhe, zeichnet mittig */
        return 0;
    }
    case MUIM_Draw: {
        DoSuperMethodA(cl, obj, msg);
        if (!(((struct MUIP_Draw *)msg)->flags & MADF_DRAWOBJECT))
            return 0;
        struct RastPort *rp = _rp(obj);
        int vis = _mheight(obj) < LB.h ? _mheight(obj) : LB.h;
        int top = (LB.wy0 + LB.wy1 + 1) / 2 - vis / 2;       /* um die Mitte des Worts */
        if (top < 0)
            top = 0;
        if (top > LB.h - vis)
            top = LB.h - vis;
        int y0 = _mtop(obj) + (_mheight(obj) - vis) / 2;
        for (int r = 0; r < vis; r++) {                         /* je Zeile Läufe gleicher Farbe */
            const UBYTE *row = LB.px + (top + r) * LB.w;
            for (int x = 0; x < LB.w;) {
                int c = row[x], e = x + 1;
                while (e < LB.w && row[e] == c)
                    e++;
                if (c && d->pen[c] >= 0) {
                    SetAPen(rp, (ULONG)d->pen[c]);
                    RectFill(rp, _mleft(obj) + x, y0 + r, _mleft(obj) + e - 1, y0 + r);
                }
                x = e;
            }
        }
        return 0;
    }
    }
    return DoSuperMethodA(cl, obj, msg);
}

static Object *logo_obj(void)
{
    if (logo_ok() && (s_lgcl || (s_lgcl = MUI_CreateCustomClass(NULL, (ClassID)MUIC_Area, NULL, sizeof(struct LgData),
                                                                 (APTR)lg_dispatch))))
        return NewObject(s_lgcl->mcc_Class, NULL, TAG_DONE);
    return HSpace(0);
}
/* Beschriftung im Hauptfenster: alle gleich breit (längster Text), damit Felder und Knöpfe aller Gruppen bündig
 * untereinander stehen; frame = Rahmen der Zeile (Knopf/Auswahl bzw. Texteingabe) für die senkrechte Lage */
static const char *s_lw;
static Object *lab(int id, ULONG frame)
{
    return TextObject, MUIA_FramePhantomHoriz, TRUE, MUIA_Frame, frame, MUIA_Text_PreParse, (IPTR)"\33r",
        MUIA_Text_Contents, (IPTR)(id < 0 ? "" : T(id)), MUIA_FixWidthTxt, (IPTR)s_lw, MUIA_InnerLeft, 0,
        MUIA_InnerRight, 0, MUIA_Weight, 0, End;
}

static int gui_build(void)
{
    s_nscr = 0;
    if (s_have_rtg) {
        s_scr_map[s_nscr] = SCR_RTG640, s_scr_e[s_nscr++] = T(MSG_RTG640);
        s_scr_map[s_nscr] = SCR_RTG320, s_scr_e[s_nscr++] = T(MSG_RTG320);
    }
    if (s_have_aga || !s_have_rtg)
        s_scr_map[s_nscr] = SCR_AGA320, s_scr_e[s_nscr++] = T(MSG_AGA320);
    s_scr_e[s_nscr] = NULL;
    s_nsnd = 0;
    s_snd_map[s_nsnd] = SND_PAULA, s_snd_e[s_nsnd++] = T(MSG_PAULA);
    if (s_have_ahi)
        s_snd_map[s_nsnd] = SND_AHI, s_snd_e[s_nsnd++] = T(MSG_AHI);
    s_snd_map[s_nsnd] = SND_OFF, s_snd_e[s_nsnd++] = T(MSG_OFF);
    s_snd_e[s_nsnd] = NULL;
    s_scale_e[0] = "1x", s_scale_e[1] = "2x", s_scale_e[2] = "3x", s_scale_e[3] = NULL;
    s_mode_e[0] = T(MSG_SINGLE), s_mode_e[1] = T(MSG_MULTI), s_mode_e[2] = NULL;
    s_net_e[0] = T(MSG_HOST), s_net_e[1] = T(MSG_JOIN), s_net_e[2] = NULL;

    s_menu[0] = (struct NewMenu){NM_TITLE, (STRPTR)T(MSG_M_PROJECT), 0, 0, 0, 0};
    s_menu[1] = (struct NewMenu){NM_ITEM, (STRPTR)T(MSG_M_ABOUT), (STRPTR) "?", 0, 0, (APTR)ID_ABOUT};
    s_menu[2] = (struct NewMenu){NM_ITEM, (STRPTR)T(MSG_M_ABOUTMUI), 0, 0, 0, (APTR)ID_ABOUTMUI};
    s_menu[3] = (struct NewMenu){NM_ITEM, (STRPTR)T(MSG_M_QUIT), (STRPTR) "Q", 0, 0,
                                 (APTR)MUIV_Application_ReturnID_Quit};
    s_menu[4] = (struct NewMenu){NM_END, 0, 0, 0, 0, 0};

    static const int lw_ids[] = {MSG_PROGRAM, MSG_SCREEN, MSG_WINDOW, MSG_SCALE, MSG_OUTPUT, MSG_AHIMODE, MSG_CTRL_LABEL, MSG_MODE, MSG_NETROLE, MSG_ADDRESS};
    s_lw = T(lw_ids[0]);
    for (unsigned i = 1; i < sizeof lw_ids / sizeof lw_ids[0]; i++)
        if (strlen(T(lw_ids[i])) > strlen(s_lw))
            s_lw = T(lw_ids[i]);
    s_pb_e[0] = T(MSG_PB_NONE);
    for (int k = 0; k < PB_N; k++)
        s_pb_e[1 + k] = T(MSG_PB_LEFT + k);
    s_pb_e[PB_N + 1] = NULL;
    /* Steuerung: Tastatur (Name + Ändern) und Pad (Auswahl je Aktion) */
    if (!(s_kgcl = MUI_CreateCustomClass(NULL, (ClassID)MUIC_Text, NULL, sizeof(struct KgData), (APTR)kg_dispatch)))
        return 0;
    Object *kg = ColGroup(3), GroupFrameT(T(MSG_G_KEYS)), End;
    /* Tastenfeld so breit wie der längere von „Taste drücken...“ und dem längsten Tastennamen */
    const char *kw = strlen(T(MSG_PRESS_KEY2)) > strlen("CURSOR RIGHT ") ? T(MSG_PRESS_KEY2) : "CURSOR RIGHT ";
    Object *pg = ColGroup(2), GroupFrameT(T(MSG_G_PAD)), End;
    if (!kg || !pg)
        return 0;
    for (int i = 0; i < 6; i++) {
        DoMethod(kg, OM_ADDMEMBER, (IPTR)label1(s_act_msg[i]));
        DoMethod(kg, OM_ADDMEMBER, (IPTR)(o_key[i] = NewObject(s_kgcl->mcc_Class, NULL, TextFrame,
                                          MUIA_Background, MUII_TextBack, MUIA_Text_Contents, (IPTR)key_name(c.key[i]),
                                          MUIA_FixWidthTxt, (IPTR)kw, MUIA_UserData, i, TAG_DONE)));
        DoMethod(kg, OM_ADDMEMBER, (IPTR)(o_keyb[i] = SimpleButton(T(MSG_CHANGE))));
    }
    for (int a = 0; a < 7; a++) {
        DoMethod(pg, OM_ADDMEMBER, (IPTR)label1(s_act_msg[a]));
        DoMethod(pg, OM_ADDMEMBER, (IPTR)(o_pad[a] = CycleObject, MUIA_Cycle_Entries, (IPTR)s_pb_e,
                                          MUIA_Cycle_Active, c.pad[a] + 1, MUIA_CycleChain, 1, End));
    }
    Object *b_start, *b_save, *b_quit, *b_ctrl, *b_kdef, *b_pdef, *b_cclose;
    app = ApplicationObject,
        MUIA_Application_Title, (IPTR)T(MSG_TITLE),
        MUIA_Application_Version, (IPTR)s_ver,
        MUIA_Application_Copyright, (IPTR)"AmiScreamer",
        MUIA_Application_Description, (IPTR)T(MSG_DESC),
        MUIA_Application_Base, (IPTR)"SCREAMERLAUNCHER",
        MUIA_Application_Menustrip, (IPTR)MUI_MakeObject(MUIO_MenustripNM, (IPTR)s_menu, 0),
        SubWindow, (IPTR)(win = WindowObject,
            MUIA_Window_Title, (IPTR)T(MSG_TITLE),
            MUIA_Window_ID, MAKE_ID('S', 'C', 'R', 'L'),
            WindowContents, (IPTR)(HGroup,
              Child, (IPTR)logo_obj(),
              Child, (IPTR)(VGroup,                   /* VSpace oben/unten: Fenster senkrecht ziehbar, Inhalt mittig */
                Child, (IPTR)VSpace(0),
                Child, (IPTR)(ColGroup(2), GroupFrameT(T(MSG_G_PROGRAM)),
                    Child, (IPTR)lab(MSG_PROGRAM, MUIV_Frame_String),
                    Child, (IPTR)(PopaslObject,
                        MUIA_Popstring_String, (IPTR)(o_prog = StringObject, StringFrame,
                            MUIA_String_MaxLen, sizeof c.prog, MUIA_String_Contents, (IPTR)c.prog,
                            MUIA_CycleChain, 1, End),
                        MUIA_Popstring_Button, (IPTR)PopButton(MUII_PopFile),
                        ASLFR_TitleText, (IPTR)T(MSG_ASL_TITLE),
                        End),
                    End),
                Child, (IPTR)(ColGroup(2), GroupFrameT(T(MSG_G_GRAPHICS)),
                    Child, (IPTR)lab(MSG_SCREEN, MUIV_Frame_Button),
                    Child, (IPTR)(o_screen = CycleObject, MUIA_Cycle_Entries, (IPTR)s_scr_e,
                        MUIA_Cycle_Active, idx_of(s_scr_map, s_nscr, c.screen), MUIA_CycleChain, 1, End),
                    Child, (IPTR)lab(MSG_WINDOW, MUIV_Frame_Button),
                    Child, (IPTR)(HGroup, Child, (IPTR)(o_window = CheckMark(c.window)), Child, (IPTR)HSpace(0), End),
                    Child, (IPTR)lab(MSG_SCALE, MUIV_Frame_Button),
                    Child, (IPTR)(o_scale = CycleObject, MUIA_Cycle_Entries, (IPTR)s_scale_e,
                        MUIA_Cycle_Active, c.scale - 1, MUIA_CycleChain, 1, End),
                    End),
                Child, (IPTR)(ColGroup(2), GroupFrameT(T(MSG_G_SOUND)),
                    Child, (IPTR)lab(MSG_OUTPUT, MUIV_Frame_Button),
                    Child, (IPTR)(o_snd = CycleObject, MUIA_Cycle_Entries, (IPTR)s_snd_e,
                        MUIA_Cycle_Active, idx_of(s_snd_map, s_nsnd, c.snd), MUIA_CycleChain, 1, End),
                    Child, (IPTR)lab(MSG_AHIMODE, MUIV_Frame_Button),
                    Child, (IPTR)(HGroup,
                        Child, (IPTR)(o_ahiname = TextObject, TextFrame, MUIA_Background, MUII_TextBack, MUIA_Weight, 300,
                            MUIA_Text_Contents, (IPTR)ahi_name(c.ahimode), End),
                        Child, (IPTR)(o_ahibtn = SimpleButton(T(MSG_AHI_SELECT))),
                        End),
                    End),
                Child, (IPTR)(ColGroup(2), GroupFrameT(T(MSG_G_CONTROLS)),
                    Child, (IPTR)lab(MSG_CTRL_LABEL, MUIV_Frame_Button),
                    Child, (IPTR)(b_ctrl = SimpleButton(T(MSG_CONTROLS_BTN))),
                    End),
                /* Zeilen statt Spaltengruppe: MUI 3.8 verschiebt in einer ColGroup die Spalten, wenn darin Einträge
                 * ausgeblendet sind; die Beschriftungen sind ohnehin gleich breit (lab) */
                Child, (IPTR)(VGroup, GroupFrameT(T(MSG_G_GAME)),
                    Child, (IPTR)(HGroup,
                        Child, (IPTR)lab(MSG_MODE, MUIV_Frame_Button),
                        Child, (IPTR)(o_mode = CycleObject, MUIA_Cycle_Entries, (IPTR)s_mode_e,
                            MUIA_Cycle_Active, c.net != NET_OFF, MUIA_CycleChain, 1, End),
                        End),
                    Child, (IPTR)(l_net = HGroup,
                        Child, (IPTR)lab(MSG_NETROLE, MUIV_Frame_Button),
                        Child, (IPTR)(o_net = CycleObject, MUIA_Cycle_Entries, (IPTR)s_net_e,
                            MUIA_Cycle_Active, c.net == NET_JOIN, MUIA_CycleChain, 1, End),
                        End),
                    Child, (IPTR)(l_host = HGroup,
                        Child, (IPTR)lab(MSG_ADDRESS, MUIV_Frame_String),
                        Child, (IPTR)(o_host = StringObject, StringFrame, MUIA_String_MaxLen, 100,
                            MUIA_String_Contents, (IPTR)c.host, MUIA_CycleChain, 1, End),
                        End),
                    Child, (IPTR)(l_hint = HGroup,
                        Child, (IPTR)lab(-1, MUIV_Frame_None),
                        Child, (IPTR)(o_hint = TextObject, MUIA_Text_Contents, (IPTR)T(MSG_HOST_HINT), End),
                        End),
                    End),
                Child, (IPTR)(HGroup, MUIA_Group_SameSize, TRUE,
                    Child, (IPTR)(b_start = SimpleButton(T(MSG_START))),
                    Child, (IPTR)HSpace(0),
                    Child, (IPTR)(b_save = SimpleButton(T(MSG_SAVE))),
                    Child, (IPTR)HSpace(0),
                    Child, (IPTR)(b_quit = SimpleButton(T(MSG_QUIT))),
                    End),
                Child, (IPTR)VSpace(0),
                End),
              End),
            End),
        SubWindow, (IPTR)(cwin = WindowObject,
            MUIA_Window_Title, (IPTR)T(MSG_CTRL_TITLE),
            MUIA_Window_ID, MAKE_ID('S', 'C', 'R', 'C'),
            WindowContents, (IPTR)(VGroup,
                Child, (IPTR)kg,
                Child, (IPTR)(HGroup, Child, (IPTR)HSpace(0), Child, (IPTR)(b_kdef = SimpleButton(T(MSG_DEFAULTS))), End),
                Child, (IPTR)pg,
                Child, (IPTR)(HGroup, Child, (IPTR)HSpace(0), Child, (IPTR)(b_pdef = SimpleButton(T(MSG_DEFAULTS))), End),
                Child, (IPTR)(HGroup, Child, (IPTR)HSpace(0), Child, (IPTR)(b_cclose = SimpleButton(T(MSG_CLOSE))),
                    Child, (IPTR)HSpace(0), End),
                End),
            End),
        End;
    if (!app)
        return 0;
    DoMethod(win, MUIM_Notify, MUIA_Window_CloseRequest, TRUE, (IPTR)app, 2, MUIM_Application_ReturnID,
             MUIV_Application_ReturnID_Quit);
    DoMethod(b_quit, MUIM_Notify, MUIA_Pressed, FALSE, (IPTR)app, 2, MUIM_Application_ReturnID,
             MUIV_Application_ReturnID_Quit);
    DoMethod(b_start, MUIM_Notify, MUIA_Pressed, FALSE, (IPTR)app, 2, MUIM_Application_ReturnID, ID_START);
    DoMethod(b_save, MUIM_Notify, MUIA_Pressed, FALSE, (IPTR)app, 2, MUIM_Application_ReturnID, ID_SAVE);
    DoMethod(o_ahibtn, MUIM_Notify, MUIA_Pressed, FALSE, (IPTR)app, 2, MUIM_Application_ReturnID, ID_AHI);
    DoMethod(b_ctrl, MUIM_Notify, MUIA_Pressed, FALSE, (IPTR)app, 2, MUIM_Application_ReturnID, ID_CTRL);
    DoMethod(cwin, MUIM_Notify, MUIA_Window_CloseRequest, TRUE, (IPTR)app, 2, MUIM_Application_ReturnID, ID_CCLOSE);
    DoMethod(b_cclose, MUIM_Notify, MUIA_Pressed, FALSE, (IPTR)app, 2, MUIM_Application_ReturnID, ID_CCLOSE);
    DoMethod(b_kdef, MUIM_Notify, MUIA_Pressed, FALSE, (IPTR)app, 2, MUIM_Application_ReturnID, ID_KDEF);
    DoMethod(b_pdef, MUIM_Notify, MUIA_Pressed, FALSE, (IPTR)app, 2, MUIM_Application_ReturnID, ID_PDEF);
    for (int i = 0; i < 6; i++)
        DoMethod(o_keyb[i], MUIM_Notify, MUIA_Pressed, FALSE, (IPTR)app, 2, MUIM_Application_ReturnID, ID_KEY0 + i);
    for (int a = 0; a < 7; a++)
        DoMethod(o_pad[a], MUIM_Notify, MUIA_Cycle_Active, MUIV_EveryTime, (IPTR)app, 2, MUIM_Application_ReturnID,
                 ID_PAD0 + a);
    static const struct { Object **o; ULONG a; } upd[] = {
        {&o_screen, MUIA_Cycle_Active}, {&o_window, MUIA_Selected}, {&o_snd, MUIA_Cycle_Active},
        {&o_mode, MUIA_Cycle_Active},   {&o_net, MUIA_Cycle_Active}};
    for (unsigned i = 0; i < sizeof upd / sizeof upd[0]; i++)
        DoMethod(*upd[i].o, MUIM_Notify, upd[i].a, MUIV_EveryTime, (IPTR)app, 2, MUIM_Application_ReturnID,
                 ID_UPDATE);
    set(win, MUIA_Window_ActiveObject, (IPTR)b_start);
    gui_ghost();
    return 1;
}

static void msg(const char *fmt, const char *arg)
{
    MUI_Request(app, win, 0, (CONST_STRPTR)T(MSG_TITLE), (CONST_STRPTR)T(MSG_OK), (CONST_STRPTR)fmt, (IPTR)arg);
}

static void ahi_select(void)
{
    struct Window *w = NULL;
    get(win, MUIA_Window_Window, &w);
    if (!w)
        return;
    struct AHIAudioModeRequester *rq = AHI_AllocAudioRequest(AHIR_Window, (ULONG)w,
        AHIR_InitialLeftEdge, w->LeftEdge + 16, AHIR_InitialTopEdge, w->TopEdge + 16,
        AHIR_InitialWidth, w->Width - 32 > 200 ? w->Width - 32 : 200, AHIR_InitialHeight, 200, AHIR_TitleText, (ULONG)T(MSG_AHI_REQ), AHIR_DoMixFreq, FALSE, AHIR_DoDefaultMode, TRUE,
        AHIR_InitialAudioID, c.ahimode, TAG_DONE);
    if (!rq)
        return;
    set(app, MUIA_Application_Sleep, TRUE);
    if (AHI_AudioRequest(rq, TAG_DONE)) {
        c.ahimode = rq->ahiam_AudioID;
        set(o_ahiname, MUIA_Text_Contents, (IPTR)ahi_name(c.ahimode));
    }
    set(app, MUIA_Application_Sleep, FALSE);
    AHI_FreeAudioRequest(rq);
}

/* „Ändern“: Abfrage im Tastenfeld starten (eine laufende Abfrage eines anderen Felds endet ohne Änderung) */
static void key_grab(int a)
{
    if (s_grab_obj && s_grab_obj != o_key[a]) {
        DoMethod(s_grab_obj, MUIM_KeyGrab_Stop);
        for (int i = 0; i < 6; i++)
            if (o_key[i] == s_grab_obj)
                set(o_key[i], MUIA_Text_Contents, (IPTR)key_name(c.key[i]));
    }
    s_grab_obj = o_key[a];
    DoMethod(o_key[a], MUIM_KeyGrab_Start);
}

/* Abfrage beendet: Taste übernehmen (wie das Original-Setup bei anderen Aktionen löschen) oder alten Namen zeigen */
static void key_done(void)
{
    int a = s_grab_idx, sc = s_grab_sc;
    s_grab_obj = NULL;
    if (a < 0 || a >= 6)
        return;
    if (sc)
        for (int i = 0; i < 6; i++) {
            if (i != a && c.key[i] == sc)
                c.key[i] = 0;
            if (i == a)
                c.key[i] = sc;
        }
    for (int i = 0; i < 6; i++)
        set(o_key[i], MUIA_Text_Contents, (IPTR)key_name(c.key[i]));
}

/* Pad-Auswahl a geändert: ein Knopf nur für eine Aktion */
static void pad_changed(int a)
{
    int v = (int)getl(o_pad[a], MUIA_Cycle_Active) - 1;
    c.pad[a] = v;
    if (v < 0)
        return;
    for (int i = 0; i < 7; i++)
        if (i != a && c.pad[i] == v) {
            c.pad[i] = -1;
            nnset(o_pad[i], MUIA_Cycle_Active, 0);
        }
}

static void ctl_show(void)
{
    for (int i = 0; i < 6; i++)
        set(o_key[i], MUIA_Text_Contents, (IPTR)key_name(c.key[i]));
    for (int a = 0; a < 7; a++)
        nnset(o_pad[a], MUIA_Cycle_Active, c.pad[a] + 1);
}

static int save(void)
{
    char failed[300];
    gui_read();
    if (c.net == NET_JOIN && !c.host[0]) {
        msg(T(MSG_ERR_HOST), "");
        return 0;
    }
    int r = cfg_save(failed, sizeof failed);
    if (!r) {
        msg(T(MSG_ERR_SAVE), failed);
        return 0;
    }
    if (r < 0)                                  /* übrige Einstellungen sind gespeichert */
        msg(T(MSG_ERR_CTRL), failed);
    return 1;
}

/* Spiel starten: Fenster zu, synchron mit Priorität 0, Fenster wieder auf */
static void start(void)
{
    char cmd[400];
    if (!save())
        return;
    if (!file_exists(c.prog)) {
        msg(T(MSG_ERR_PROG), c.prog);
        return;
    }
    int n = snprintf(cmd, sizeof cmd, "\"%s\"", c.prog);
    if (c.window && c.screen != SCR_AGA320)
        snprintf(cmd + n, sizeof cmd - (size_t)n, c.scale > 1 ? " --scale %d" : " --window", c.scale);
    set(win, MUIA_Window_Open, FALSE);
    BPTR in = Open((CONST_STRPTR)"NIL:", MODE_OLDFILE), out = Open((CONST_STRPTR)"NIL:", MODE_NEWFILE);
    LONG rc = -1;
    if (in && out)
        rc = SystemTags((CONST_STRPTR)cmd, SYS_Input, (IPTR)in, SYS_Output, (IPTR)out, NP_Priority, 0,
                        NP_StackSize, 65536, TAG_DONE);
    if (rc == -1) {                             /* nicht gestartet: Ströme gehören noch uns */
        if (in)
            Close(in);
        if (out)
            Close(out);
    }
    set(win, MUIA_Window_Open, TRUE);
    if (rc == -1)
        msg(T(MSG_ERR_RUN), "");
    else if (rc) {
        char t[200];
        snprintf(t, sizeof t, T(MSG_ERR_RC), (long)rc);
        msg("%s", t);
    }
}

int main(void)
{
    int rc = 20;
    BPTR pd = GetProgramDir();
    if (!pd || !NameFromLock(pd, (STRPTR)s_mydir, sizeof s_mydir))
        s_mydir[0] = 0;
    if ((LocaleBase = (struct LocaleBase *)OpenLibrary((CONST_STRPTR)"locale.library", 38)))
        s_cat = OpenCatalog(NULL, (STRPTR)"amiscreamer_launcher.catalog", OC_BuiltInLanguage, (IPTR)"english",
                            TAG_DONE);
    if (!(MUIMasterBase = OpenLibrary((CONST_STRPTR)MUIMASTER_NAME, MUIMASTER_VMIN))) {
        struct EasyStruct es = {sizeof es, 0, (STRPTR)T(MSG_TITLE), (STRPTR)T(MSG_ERR_MUI), (STRPTR) "OK"};
        EasyRequestArgs(NULL, &es, NULL, NULL);
        goto out;
    }
    struct Library *cgx = OpenLibrary((CONST_STRPTR)"cybergraphics.library", 41);
    if (cgx) {
        s_have_rtg = 1;
        CloseLibrary(cgx);
    }
    s_have_aga = (GfxBase->ChipRevBits0 & GFXF_AA_ALICE) != 0;
    ahi_open();
    KeymapBase = OpenLibrary((CONST_STRPTR)"keymap.library", 37);
    cfg_load();
    if (!gui_build())
        goto out;
    set(win, MUIA_Window_Open, TRUE);
    ULONG sigs = 0;
    for (;;) {
        LONG id = (LONG)DoMethod(app, MUIM_Application_NewInput, (IPTR)&sigs);
        if (id == MUIV_Application_ReturnID_Quit)
            break;
        switch (id) {
        case ID_UPDATE: gui_ghost(); break;
        case ID_AHI: ahi_select(); break;
        case ID_SAVE: save(); break;
        case ID_START: start(); break;
        case ID_CTRL: set(cwin, MUIA_Window_Open, TRUE); break;
        case ID_CCLOSE:
            if (s_grab_obj) {                   /* Esc (MUI: Fenster schließen) während einer Abfrage: nur abbrechen */
                DoMethod(s_grab_obj, MUIM_KeyGrab_Stop);
                s_grab_obj = NULL;
                ctl_show();
                break;
            }
            set(cwin, MUIA_Window_Open, FALSE);
            break;
        case ID_KDEF:
            gui_read();
            ctl_defaults(c.prog);
            ctl_show();
            break;
        case ID_PDEF:
            memcpy(c.pad, s_pad_def, sizeof c.pad);
            ctl_show();
            break;
        default:
            if (id >= ID_KEY0 && id < ID_KEY0 + 6)
                key_grab((int)(id - ID_KEY0));
            else if (id == ID_KEYDONE)
                key_done();
            else if (id >= ID_PAD0 && id < ID_PAD0 + 7)
                pad_changed((int)(id - ID_PAD0));
            break;
        case ID_ABOUT: {
            char t[300];
            snprintf(t, sizeof t, T(MSG_ABOUT_TEXT), LAUNCHER_VERSION);
            msg("%s", t);
            break;
        }
        case ID_ABOUTMUI:
            DoMethod(app, MUIM_Application_AboutMUI, (IPTR)win);
            break;
        }
        if (sigs) {
            sigs = Wait(sigs | SIGBREAKF_CTRL_C);
            if (sigs & SIGBREAKF_CTRL_C)
                break;
        }
    }
    rc = 0;
out:
    if (app)
        MUI_DisposeObject(app);
    if (s_kgcl)
        MUI_DeleteCustomClass(s_kgcl);
    if (s_lgcl)
        MUI_DeleteCustomClass(s_lgcl);
    ahi_close();
    if (KeymapBase)
        CloseLibrary(KeymapBase);
    if (MUIMasterBase)
        CloseLibrary(MUIMasterBase);
    if (s_cat)
        CloseCatalog(s_cat);
    if (LocaleBase)
        CloseLibrary((struct Library *)LocaleBase);
    return rc;
}
