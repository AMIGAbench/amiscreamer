/* screamer_inst - Hilfsprogramm des Amiga-Installers (installer_amiga/Install-Screamer).
 *   screamer_inst cfg   <ziel>                  SCREAMER.CFG, CONFIG/SETUP.CFG, CONFIG/CONTROLS.CFG (falls fehlt)
 *   screamer_inst music <cd-pfad> <musikverz>   CD-Audiospuren lesen (SCSI direkt) und nach trackNN.raw wandeln
 *   screamer_inst gog   <setup.exe> <ziel>      Spieldateien aus dem GOG-Installationsprogramm (inst_gog.c)
 *   screamer_inst gogmusic <setup.exe> <musikverz>  CD-Musik aus SCREAM.gog des GOG-Installationsprogramms
 *   -de als erstes Argument: Meldungen deutsch (Vorgabe englisch).
 * Rückgabe 0 = ok, 10 = Warnung (z. B. Laufwerk liefert kein CD-DA), 20 = Fehler. Kern: inst_core.c. */
#include <exec/types.h>
#include <exec/memory.h>
#include <exec/io.h>
#include <dos/dos.h>
#include <dos/dosextens.h>
#include <dos/filehandler.h>
#include <devices/scsidisk.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "inst_core.h"
#include "inst_gog.h"

#ifndef INST_VERSTAG                            /* (tools/amiga_installer.sh: VERSION_AMIGA and the date of the source) */
#define INST_VERSTAG "$VER: amiscreamer_inst 0.0 (01.01.2026)"
#endif
static const char s_ver[] __attribute__((used)) = INST_VERSTAG;

/* Eigener Stapel (libnix swapstack, -Wl,-u,___stkinit wie das Spiel): aus der Shell kommen sonst nur 4 KB, zlib, Musik-
 * umwandlung und Ausgabe brauchen mehr (GOG-Musik stürzte mit 8000000B ab) */
unsigned long __stack = 65536;
/* libnix prüft in stdio selbst auf Ctrl-C und beendet dann sofort (exit, ohne Aufräumen: angefangene trackNN.raw blieb
 * liegen). Abfrage nur über die eigenen Prüfstellen (SetSignal), die angefangene Dateien löschen. */
void __chkabort(void) {}

/* Meldungen englisch, mit -de deutsch; Umlaute als ISO-8859-1 (Amiga-Konsole), nicht UTF-8 */
static int s_de;
#define T(de, en) (s_de ? (de) : (en))

static uint8_t *load(const char *p, size_t *n)
{
    FILE *f = fopen(p, "rb");
    if (!f)
        return NULL;
    fseek(f, 0, SEEK_END);
    long l = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *b = l > 0 ? malloc((size_t)l) : NULL;
    if (!b || fread(b, 1, (size_t)l, f) != (size_t)l) {
        fclose(f);
        free(b);
        return NULL;
    }
    fclose(f);
    *n = (size_t)l;
    return b;
}

static int save(const char *p, const void *d, size_t n)
{
    FILE *f = fopen(p, "wb");
    int ok = f && fwrite(d, 1, n, f) == n;
    if (f && fclose(f))
        ok = 0;
    return ok;
}

static void join(char *o, size_t n, const char *dir, const char *name)
{
    snprintf(o, n, "%s", dir);
    AddPart((STRPTR)o, (CONST_STRPTR)name, (ULONG)n);
}

/* ---------------------------------------------------------------- cfg */
static int cmd_cfg(const char *dir)
{
    char p[300], q[300];
    uint8_t s[0x90];
    join(p, sizeof p, dir, "SCREAMER.CFG");
    if (!save(p, screamer_cfg, strlen(screamer_cfg))) {
        printf(T("Kann %s nicht schreiben\n", "Cannot write %s\n"), p);
        return 20;
    }
    join(p, sizeof p, dir, "CONFIG");
    BPTR l = Lock((CONST_STRPTR)p, ACCESS_READ);
    if (!l)
        l = CreateDir((CONST_STRPTR)p);
    if (l)
        UnLock(l);
    join(p, sizeof p, dir, "CONFIG/SETUP.CFG");
    setup_cfg(s);
    if (!save(p, s, sizeof s)) {
        printf(T("Kann %s nicht schreiben\n", "Cannot write %s\n"), p);
        return 20;
    }
    join(p, sizeof p, dir, "CONFIG/CONTROLS.CFG");
    if (!(l = Lock((CONST_STRPTR)p, ACCESS_READ))) {      /* eigene Tastenbelegung bleibt */
        size_t n = 0;
        join(q, sizeof q, dir, "CONFIG/DEFCTRL.CFG");
        uint8_t *d = load(q, &n);
        if (!d || !save(p, d, n)) {
            printf(T("Kann %s nicht anlegen\n", "Cannot create %s\n"), p);
            free(d);
            return 20;
        }
        free(d);
    } else
        UnLock(l);
    printf(T("Konfiguration geschrieben\n", "Configuration written\n"));
    return 0;
}

/* ---------------------------------------------------------------- music */
static struct IOStdReq *s_io;
static UBYTE s_sense[32];

/* SCSI-Befehl (lesend), 0 = ok */
static int scsi_read(const UBYTE *cdb, int cl, void *buf, ULONG len)
{
    struct SCSICmd sc;
    memset(&sc, 0, sizeof sc);
    sc.scsi_Data = (UWORD *)buf;
    sc.scsi_Length = len;
    sc.scsi_Command = (UBYTE *)cdb;
    sc.scsi_CmdLength = (UWORD)cl;
    sc.scsi_Flags = SCSIF_READ | SCSIF_AUTOSENSE;
    sc.scsi_SenseData = s_sense;
    sc.scsi_SenseLength = sizeof s_sense;
    s_io->io_Command = HD_SCSICMD;
    s_io->io_Data = &sc;
    s_io->io_Length = sizeof sc;
    if (DoIO((struct IORequest *)s_io) || sc.scsi_Status)
        return 1;
    return 0;
}

/* Gerät und Unit des Laufwerks hinter einem DOS-Pfad (z. B. CD0: oder der Name der CD) */
static int find_device(const char *path, char *dev, size_t dn, ULONG *unit)
{
    struct DevProc *dp = GetDeviceProc((CONST_STRPTR)path, NULL);
    if (!dp)
        return 1;
    int rc = 1;
    struct DosList *dl = LockDosList(LDF_DEVICES | LDF_READ);
    while ((dl = NextDosEntry(dl, LDF_DEVICES))) {
        if (dl->dol_Task != dp->dvp_Port)
            continue;
        struct FileSysStartupMsg *fs = (struct FileSysStartupMsg *)BADDR(dl->dol_misc.dol_handler.dol_Startup);
        if ((ULONG)fs > 1024 && TypeOfMem(fs)) {
            UBYTE *b = (UBYTE *)BADDR(fs->fssm_Device);
            if (b && TypeOfMem(b) && b[0] < dn) {
                memcpy(dev, b + 1, b[0]);
                dev[b[0]] = 0;
                *unit = fs->fssm_Unit;
                rc = 0;
            }
        }
        break;
    }
    UnLockDosList(LDF_DEVICES | LDF_READ);
    FreeDeviceProc(dp);
    return rc;
}

static int wout(void *ctx, const uint8_t *p, size_t n) { return fwrite(p, 1, n, (FILE *)ctx) != n; }

enum { SECT = 2352, NSEC = 16 };

static int cmd_music(const char *cd, const char *outdir)
{
    char dev[64], path[300];
    ULONG unit = 0;
    int rc = 20;
    if (find_device(cd, dev, sizeof dev, &unit)) {
        printf(T("Kein Laufwerk zu %s gefunden\n", "No drive found for %s\n"), cd);
        return 20;
    }
    printf(T("CD-Laufwerk: %s Unit %lu\n", "CD drive: %s unit %lu\n"), dev, (unsigned long)unit);
    struct MsgPort *mp = CreateMsgPort();
    s_io = mp ? (struct IOStdReq *)CreateIORequest(mp, sizeof *s_io) : NULL;
    UBYTE *buf = AllocVec(NSEC * SECT, MEMF_PUBLIC);
    if (!s_io || !buf || OpenDevice((CONST_STRPTR)dev, unit, (struct IORequest *)s_io, 0)) {
        printf(T("Kann %s Unit %lu nicht \xf6" "ffnen\n", "Cannot open %s unit %lu\n"), dev, (unsigned long)unit);
        goto out_nodev;
    }
    /* Inhaltsverzeichnis (READ TOC, LBA) */
    static UBYTE toc[804];
    UBYTE cdb[12] = {0x43, 0, 0, 0, 0, 0, 0, sizeof toc >> 8, sizeof toc & 0xff, 0};
    if (scsi_read(cdb, 10, toc, sizeof toc)) {
        printf(T("Inhaltsverzeichnis der CD nicht lesbar\n", "Cannot read the table of contents of the CD\n"));
        goto out;
    }
    int nd = ((toc[0] << 8 | toc[1]) - 2) / 8;
    if (nd > 100)
        nd = 100;
    BPTR l = Lock((CONST_STRPTR)outdir, ACCESS_READ);
    if (!l)
        l = CreateDir((CONST_STRPTR)outdir);
    if (l)
        UnLock(l);
    int done = 0;
    rc = 0;
    for (int d = 0; d + 1 < nd && rc == 0; d++) {
        const UBYTE *e = toc + 4 + 8 * d, *nx = e + 8;
        int track = e[2];
        if (e[1] & 4)                           /* Datenspur */
            continue;
        ULONG lba = (ULONG)e[4] << 24 | (ULONG)e[5] << 16 | (ULONG)e[6] << 8 | e[7];
        ULONG end = (ULONG)nx[4] << 24 | (ULONG)nx[5] << 16 | (ULONG)nx[6] << 8 | nx[7];
        if (end <= lba)
            continue;
        ULONG nsec = end - lba;
        snprintf(path, sizeof path, "track%02d.raw", track);
        char full[300];
        join(full, sizeof full, outdir, path);
        FILE *f = fopen(full, "wb");
        if (!f) {
            printf(T("Kann %s nicht schreiben\n", "Cannot write %s\n"), full);
            rc = 20;
            break;
        }
        setvbuf(f, NULL, _IOFBF, 65536);
        MusConv *m = mus_begin(nsec * 588, wout, f);
        int last = -1, sect_type = 0x04;        /* READ CD: erwartete Art CD-DA */
        for (ULONG s = 0; s < nsec; s += NSEC) {
            if (SetSignal(0, SIGBREAKF_CTRL_C) & SIGBREAKF_CTRL_C) {
                printf(T("\nAbgebrochen\n", "\nAborted\n"));
                rc = 20;
                break;
            }
            ULONG n = nsec - s < NSEC ? nsec - s : NSEC, a = lba + s;
            int ok = 0;
            for (int t = 0; t < 4 && !ok; t++) {
                UBYTE rc_cdb[12] = {0xBE, (UBYTE)sect_type, a >> 24, a >> 16, a >> 8, (UBYTE)a,
                                    n >> 16, n >> 8, (UBYTE)n, 0x10, 0, 0};
                ok = !scsi_read(rc_cdb, 12, buf, n * SECT);
                if (!ok && t == 1)
                    sect_type = 0;              /* manche Laufwerke wollen „jede Art“ */
            }
            if (!ok) {
                if (!done && s == 0) {
                    printf(T("\nDas Laufwerk liefert keine CD-Audiodaten (READ CD).\n"
                             "Die Musik bitte mit dem Linux-Skript erzeugen (siehe README_de).\n",
                             "\nThe drive does not deliver CD audio data (READ CD).\n"
                             "Please create the music with the Linux script (see README_en).\n"));
                    rc = 10;
                    break;
                }
                memset(buf, 0, n * SECT);       /* Lesefehler: Stille statt Abbruch */
                printf(T("\nLesefehler bei Sektor %lu, Stille eingesetzt\n", "\nRead error at sector %lu, silence inserted\n"), (unsigned long)a);
            }
            if (mus_feed(m, buf, n * SECT / 4)) {
                printf(T("\nSchreibfehler %s\n", "\nWrite error %s\n"), full);
                rc = 20;
                break;
            }
            int pc = (int)((s + n) * 100 / nsec);
            if (pc / 5 != last) {
                last = pc / 5;
                printf(T("\rSpur %02d: %3d %%", "\rTrack %02d: %3d %%"), track, pc);
                fflush(stdout);
            }
        }
        if (rc)
            mus_abort(m);
        else if (mus_end(m))
            rc = 20;
        if (fclose(f) && !rc)
            rc = 20;
        if (rc)
            DeleteFile((CONST_STRPTR)full);
        else {
            printf(T("\rSpur %02d: fertig (%02lu:%02lu)\n", "\rTrack %02d: done (%02lu:%02lu)\n"), track, (unsigned long)(nsec / 75 / 60),
                   (unsigned long)(nsec / 75 % 60));       /* Länge des Stücks */
            done++;
        }
    }
    if (!rc)
        printf(T("%d Musikst\xfc" "cke umgewandelt\n", "%d music tracks converted\n"), done);
out:
    CloseDevice((struct IORequest *)s_io);
out_nodev:
    if (buf)
        FreeVec(buf);
    if (s_io)
        DeleteIORequest((struct IORequest *)s_io);
    if (mp)
        DeleteMsgPort(mp);
    return rc;
}

/* ---------------------------------------------------------------- GOG-Installationsprogramm */
static int g_brk(void) { return (SetSignal(0, SIGBREAKF_CTRL_C) & SIGBREAKF_CTRL_C) != 0; }
static int cb_file(void *ctx, const char *name, int pct)
{
    if (g_brk())
        return 1;
    if (pct == 0 || pct == 100) {
        printf("\r%-24s %3d %%", name, pct);
        if (pct == 100)
            printf("\n");
        fflush(stdout);
    }
    return 0;
}
static int cb_track(void *ctx, int t, int pct, uint32_t sec)
{
    static int last = -1;
    if (g_brk())
        return 1;
    if (pct <= 100 && pct / 5 == last)          /* Ausgabe in 5-%-Schritten, Abbruchprüfung je Block */
        return 0;
    last = pct > 100 ? -1 : pct / 5;
    if (pct > 100)
        printf(T("\rSpur %02d: fertig (%02lu:%02lu)\n", "\rTrack %02d: done (%02lu:%02lu)\n"), t, (unsigned long)(sec / 75 / 60),
               (unsigned long)(sec / 75 % 60));
    else
        printf(T("\rSpur %02d: %3d %%", "\rTrack %02d: %3d %%"), t, pct);
    fflush(stdout);
    return 0;
}
static int cb_mkdir(void *ctx, const char *path)
{
    BPTR l = Lock((CONST_STRPTR)path, ACCESS_READ);
    if (!l)
        l = CreateDir((CONST_STRPTR)path);
    if (!l)
        return 1;
    UnLock(l);
    return 0;
}

static GogSetup *gog_start(const char *exe)
{
    char err[128];
    GogSetup *g = gog_open(exe, err, sizeof err);
    if (!g)
        printf(T("GOG-Installationsprogramm nicht lesbar: %s\n", "Cannot use the GOG installer: %s\n"), err);
    return g;
}
static int gog_rc(int rc)
{
    switch (rc) {
    case 0:
        return 0;
    case 1:
        printf(T("\nAbgebrochen\n", "\nAborted\n"));
        break;
    case 2:
        printf(T("\nLesefehler im GOG-Installationsprogramm\n", "\nRead error in the GOG installer\n"));
        break;
    case 3:
        printf(T("\nGOG-Installationsprogramm besch\xe4" "digt (Pr\xfc" "fsumme)\n", "\nGOG installer damaged (checksum)\n"));
        break;
    case 4:
        printf(T("\nSchreibfehler (Platz auf dem Ziel?)\n", "\nWrite error (space on the destination?)\n"));
        break;
    default:
        printf(T("\nDas GOG-Installationsprogramm enth\xe4" "lt die Spieldaten nicht\n",
                 "\nThe GOG installer does not contain the game data\n"));
        break;
    }
    return 20;
}

static int cmd_gog(const char *exe, const char *dir)
{
    GogSetup *g = gog_start(exe);
    if (!g)
        return 20;
    cb_mkdir(NULL, dir);
    GogCb cb = {cb_file, NULL, cb_mkdir, NULL};
    int rc = gog_install(g, dir, &cb);
    gog_close(g);
    if (!rc)
        printf(T("Spieldateien installiert\n", "Game files installed\n"));
    return gog_rc(rc);
}

static int cmd_gogmusic(const char *exe, const char *dir)
{
    GogSetup *g = gog_start(exe);
    if (!g)
        return 20;
    cb_mkdir(NULL, dir);
    GogCb cb = {NULL, cb_track, cb_mkdir, NULL};
    int n = 0, rc = gog_music(g, dir, &cb, &n);
    gog_close(g);
    if (!rc)
        printf(T("%d Musikst\xfc" "cke umgewandelt\n", "%d music tracks converted\n"), n);
    return gog_rc(rc);
}

int main(int argc, char **argv)
{
    if (argc > 1 && !strcmp(argv[1], "-de")) {
        s_de = 1;
        argc--;
        argv++;
    }
    if (argc == 3 && !strcmp(argv[1], "cfg"))
        return cmd_cfg(argv[2]);
    if (argc == 4 && !strcmp(argv[1], "music"))
        return cmd_music(argv[2], argv[3]);
    if (argc == 4 && !strcmp(argv[1], "gog"))
        return cmd_gog(argv[2], argv[3]);
    if (argc == 4 && !strcmp(argv[1], "gogmusic"))
        return cmd_gogmusic(argv[2], argv[3]);
    printf("Usage: screamer_inst [-de] cfg <dest> | music <cd-path> <music-dir>\n"
           "       | gog <setup.exe> <dest> | gogmusic <setup.exe> <music-dir>\n");
    return 20;
}
