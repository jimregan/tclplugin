/*
 * np.h --
 *
 *	Declarations of functions and entry points for the Tcl Netscape
 *	plugin.
 *
 * CONTACT:		tclplugin-core@lists.sourceforge.net
 *
 * Copyright (c) 1996-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 * Copyright (c) 2002-2005 ActiveState Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS:  @(#) $Id$
 */

#ifndef _NP
#define _NP

#include <tcl.h>

#ifdef HAVE_STDLIB_H
#include <stdlib.h> /* for getenv */
#endif

#if (TCL_MAJOR_VERSION < 8) \
	|| ((TCL_MAJOR_VERSION == 8) && (TCL_MINOR_VERSION < 4))
#error "Tcl Browser Plugin requires Tcl 8.4+"
#endif

#ifdef WIN32

#  include <windows.h>

#  define dlclose(path)		((void *) FreeLibrary((HMODULE) path))
#  define DLSYM(handle, symbol, type, proc) \
	(proc = (type) GetProcAddress((HINSTANCE) handle, symbol))

#  define snprintf _snprintf

#  define HAVE_UNISTD_H 1

#  ifndef	F_OK
#    define	F_OK	0
#  endif

#  ifndef SHLIB_SUFFIX
#    define SHLIB_SUFFIX ".dll"
#  endif

#elif defined(XP_MACOSX) /* Mac OS X */

#  include <stdio.h>
#  include <Carbon/Carbon.h>

#  if HAVE_UNISTD_H
#	include <sys/types.h>
#	include <unistd.h>
#  endif

#  ifndef SHLIB_SUFFIX
#    define SHLIB_SUFFIX ".dylib"
#  endif

#    include <dlfcn.h>
#  define HMODULE void *
#  define DLSYM(handle, symbol, type, proc) \
	(proc = (type) dlsym(handle, symbol))

#  define HIBYTE(i) (i >> 8)
#  define LOBYTE(i) (i & 0xff)

#else /* UNIX */

#  include <stdio.h>

#  define HIBYTE(i) (i >> 8)
#  define LOBYTE(i) (i & 0xff)

#  if HAVE_UNISTD_H
#	include <sys/types.h>
#	include <unistd.h>
#  endif

#  if defined(__hpux)

/* HPUX requires shl_* routines */
#    include <dl.h>
#    define HMODULE shl_t
#    define dlopen(libname, flags)	shl_load(libname, \
	BIND_DEFERRED|BIND_VERBOSE|DYNAMIC_PATH, 0L)
#    define dlclose(path)		shl_unload((shl_t) path)
#    define DLSYM(handle, symbol, type, proc) \
	if (shl_findsym(&handle, symbol, (short) TYPE_PROCEDURE, \
		(void *) &proc) != 0) { proc = NULL; }

#  ifndef SHLIB_SUFFIX
#    define SHLIB_SUFFIX ".sl"
#  endif

#  else

#    include <dlfcn.h>
#    define HMODULE void *
#    define DLSYM(handle, symbol, type, proc) \
	(proc = (type) dlsym(handle, symbol))

#  ifndef SHLIB_SUFFIX
#    define SHLIB_SUFFIX ".so"
#  endif

/*
 * FIX: For other non-dl systems, we need alternatives here
 */

#  endif

/*
 * Shared functions:
 */

EXTERN void		NpXtStopNotifier _ANSI_ARGS_((void));

#endif /* PLATFORM DEFS */

#ifndef MAX_PATH
#define MAX_PATH 1024
#endif

/*
 * Tcl Plugin version identifiers
 * (the 3 strings are computed from the 4 internal numbers)
 */
#define NPTCL_VERSION		PACKAGE_VERSION
#define NPTCL_PATCH_LEVEL	PACKAGE_PATCHLEVEL
#define NPTCL_INTERNAL_VERSION	PACKAGE_PATCHLEVEL

#define NPTCL_MAJOR_VERSION	3
#define NPTCL_MINOR_VERSION	0
#define NPTCL_RELEASE_LEVEL	0
#define NPTCL_RELEASE_SERIAL	1

#ifdef BUILD_nptcl
#undef TCL_STORAGE_CLASS
#define TCL_STORAGE_CLASS DLLEXPORT
#endif /* BUILD_nptcl */

/*
 * Tcl 8.4 introduced better CONST-ness in the APIs, but we use CONST84 in
 * some cases for compatibility with earlier Tcl headers to prevent warnings.
 */
#ifndef CONST84
#  define CONST84
#endif

/*
 * Netscape APIs (needs system specific headers)
 * AIX predefines certain types that we must redefine.
 */

#ifdef _AIX
#define _PR_AIX_HAVE_BSD_INT_TYPES 1
#endif

#include "npapi.h"

/*
 * The following constant is used to tell Netscape that the plugin will
 * accept whatever amount of input is available on a stream.
 */

#define MAXINPUTSIZE		0X0FFFFFFF

/*
 * Define the names of token tables used in the plugin:
 */

#define	NPTCL_INSTANCE		"npInstance"
#define NPTCL_STREAM		"npStream"

#ifndef NP_LOG
#define NP_LOG		((char *) NULL)
#endif

EXTERN void		NpLog _ANSI_ARGS_(TCL_VARARGS(CONST char *, format));
EXTERN void		NpStartLog _ANSI_ARGS_((CONST char *filename));
EXTERN void		NpStopLog _ANSI_ARGS_((void));

/*
 * Procedures shared between various modules in the plugin:
 */

/*
 * nptcl.c
 */
extern int		NpInit _ANSI_ARGS_((Tcl_Interp *interp));
extern void		NpShutdown _ANSI_ARGS_((Tcl_Interp *interp));

/*
 * npinterp.c
 */
extern void		NpDestroyMainInterp _ANSI_ARGS_((void));
extern Tcl_Interp	*NpGetMainInterp _ANSI_ARGS_((void));
extern Tcl_Interp	*NpCreateMainInterp _ANSI_ARGS_((void));

/*
 * npstream.c
 */
extern int		NpTclStreams _ANSI_ARGS_((int incrVal));
extern int		NpEnter _ANSI_ARGS_((CONST char *msg));
extern void		NpLeave _ANSI_ARGS_((CONST char *msg,
			    int oldMode));
EXTERN void		NpPanic _ANSI_ARGS_((char *msg));

/*
 * np***plat.c
 */
extern int		NpPlatformInit _ANSI_ARGS_((Tcl_Interp *interp,
			    int externalFlag));
extern void		NpPlatformDestroy _ANSI_ARGS_((NPP This));
extern void		NpPlatformMsg _ANSI_ARGS_((CONST84 char *msg,
			    char *title));
extern void		NpPlatformNew _ANSI_ARGS_((NPP instance));
extern void		NpPlatformSetWindow _ANSI_ARGS_((NPP This,
			    NPWindow *window));
extern void		NpPlatformShutdown _ANSI_ARGS_((void));
extern int		NpLoadLibrary(HMODULE *tclHandle,
				char *dllFilename, int dllFilenameSize);

/*
 * nptoken.c
 */
extern void		NpInitTokenTables _ANSI_ARGS_((Tcl_Interp *interp));
extern void		NpDeleteTokenTables _ANSI_ARGS_((Tcl_Interp *interp));
extern void		NpRegisterToken _ANSI_ARGS_((ClientData clientData,
			    Tcl_Interp *interp, char *tokenTableID));
extern void		NpUnregisterToken _ANSI_ARGS_((Tcl_Interp *interp,
			    void *token, char *tokenTableID));
extern char		*NpGetTokenName _ANSI_ARGS_((ClientData clientData,
			    Tcl_Interp *interp, char *tableName));
extern int		NpGetAndCheckToken _ANSI_ARGS_((Tcl_Interp *interp,
			    Tcl_Obj *token, char *tableName,
			    ClientData *clientDataPtr));

/*
 * npcmd.c
 */
extern int		PnInit _ANSI_ARGS_((Tcl_Interp *interp));
extern int		PnSafeInit _ANSI_ARGS_((Tcl_Interp *interp));

#if 0
# undef TCL_STORAGE_CLASS
# define TCL_STORAGE_CLASS DLLIMPORT
#endif

#endif /* _NP */
