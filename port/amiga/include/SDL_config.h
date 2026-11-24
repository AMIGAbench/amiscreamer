/* SDL_config.h for the Amiga build: only SDL2's headers are used (types,
   constants, the event structures); the functions are amiga/sdl_amiga.c's. */
#ifndef SDL_config_h_
#define SDL_config_h_
#include "SDL_platform.h"
#define HAVE_STDARG_H 1
#define HAVE_STDDEF_H 1
#define HAVE_STDINT_H 1
#define HAVE_LIBC 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_MATH_H 1
#define HAVE_CTYPE_H 1
#define SDL_AUDIO_DRIVER_DUMMY 1
#define SDL_VIDEO_DRIVER_DUMMY 1
#endif
