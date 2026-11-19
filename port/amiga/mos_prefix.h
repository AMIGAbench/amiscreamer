/* mos_prefix.h - included first in the MorphOS build (PowerPC, amiga/Makefile.mos): the layout checks of the
   structures the 68k kernels read by their offsets (_Static_assert) do not hold on the PowerPC (its alignment) --
   and need not: there are no 68k kernels in this build, only the C */
#ifndef OS_MOS_PREFIX_H
#define OS_MOS_PREFIX_H
#define _Static_assert(cond, msg) extern int os_mos_no_static_assert
#endif
