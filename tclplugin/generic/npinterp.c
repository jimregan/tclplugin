/* 
 * npinterp.c --
 *
 *	Implements access to the main interpreter for the Tcl plugin.
 *
 * CONTACT:		sunscript-plugin@sunscript.sun.com
 *
 * AUTHORS:		Jacob Levy			Laurent Demailly
 *			jyl@eng.sun.com			demailly@eng.sun.com
 *			jyl@tcl-tk.com			L@demailly.com
 *
 * Please contact us directly for questions, comments and enhancements.
 *
 * Copyright (c) 1995-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npinterp.c 1.10 97/09/26 07:27:38
 * RCS:  @(#) $Id$
 */

#include	"np.h"

#ifndef USE_TCL_STUBS
#define Tcl_InitStubs(interp, version, exact) Tcl_PkgRequire(interp, "Tcl", TCL_VERSION, 1)
#endif

/*
 * Static variables in this file:
 */

static Tcl_Interp *npInterp = (Tcl_Interp *) NULL;
static void *tclHandle = (void *) NULL;
static void *tkHandle = (void *) NULL;

#ifdef _WIN32

#include <windows.h>
#define TCL_LIB_FILE "tcl81.dll"
#define dlopen(path, flags) ((void *) LoadLibrary(path))
#define dlsym(handle, symbol) GetProcAddress((HINSTANCE) handle, symbol)

#else

#include <dlfcn.h>

#endif

/*
 * In some systems, like SunOS 4.1.3, the RTLD_NOW flag isn't defined
 * and this argument to dlopen must always be 1.  The RTLD_GLOBAL
 * flag is needed on some systems (e.g. SCO and UnixWare) but doesn't
 * exist on others;  if it doesn't exist, set it to 0 so it has no effect.
 */

#ifndef RTLD_NOW
#   define RTLD_NOW 1
#endif

#ifndef RTLD_GLOBAL
#   define RTLD_GLOBAL 0
#endif

static char libname[] = TCL_LIB_FILE;


/*
 *----------------------------------------------------------------------
 *
 * NpCreateMainInterp --
 *
 *	Create the main interpreter.
 *
 * Results:
 *	The pointer to the main interpreter.
 *
 * Side effects:
 *	Will panic if called twice. (Must call DestroyMainInterp in between)
 *
 *----------------------------------------------------------------------
 */

Tcl_Interp *
NpCreateMainInterp()
{
    Tcl_Interp * (* createInterp)();
    char *pos;

    if (npInterp != NULL) {
        NpPanic("Called CreateInterp when we already have one!");
    }
#ifdef USE_TCL_STUBS
    /* Determine the libname and version number dynamically */

    strcpy(libname, TCL_LIB_FILE); /* in case it is clobbered */
    pos = strstr(libname,"tcl")+4;
    if (*pos == '.') {
	pos++;
    }
    *pos = '4'; /* count down from '3' to '1'*/
    while(!tclHandle && (--*pos>'0')) {
	tclHandle = dlopen(libname, RTLD_NOW | RTLD_GLOBAL);
    }
    if (!tclHandle) {
	goto failed;
    }
    /* Derive the name of Tk's library from Tcl's. Should work on all platforms */
    pos = strstr(libname,"tcl")+2;
    *pos-- = 'k';
    while (pos > libname) {
	*pos-- = pos[-1];
    }
    tkHandle = dlopen(libname+1, RTLD_NOW | RTLD_GLOBAL);
    createInterp = (Tcl_Interp * (*)()) dlsym(tclHandle, "Tcl_CreateInterp");
#else
    createInterp = Tcl_CreateInterp;
#endif
    npInterp = createInterp();
    if (npInterp == (Tcl_Interp *) NULL || Tcl_InitStubs(npInterp, "8.0", 0) == NULL) {
	failed:
        NpPanic("Failed to create main interpreter!");
    }

    /*
     * From now until shutdown we need this interp alive, hence we
     * preserve it here and release it at NpDestroyInterp time.
     */

    Tcl_Preserve((ClientData) npInterp);

    return npInterp;
}

/*
 *----------------------------------------------------------------------
 *
 * NpGetMainInterp --
 *
 *	Gets the main interpreter. It must exist or we panic.
 *
 * Results:
 *	The main interpreter.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

Tcl_Interp *
NpGetMainInterp()
{
    if (npInterp == NULL) {
        NpPanic("BUG: Main interpreter does not exist");
    }
    return npInterp;
}

/*
 *----------------------------------------------------------------------
 *
 * NpDestroyMainInterp --
 *
 *	Destroys the main interpreter and performs cleanup actions.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Destroys the main interpreter and unloads Tcl.
 *
 *----------------------------------------------------------------------
 */

void
NpDestroyMainInterp()
{
    
    /*
     * We are not going to use the main interpreter after this point
     * because this may be the last call from Netscape.
     */

    Tcl_DeleteInterp(npInterp);
    Tcl_Release((ClientData) npInterp);
    npInterp = (Tcl_Interp *) NULL;

    /*
     * We are done using Tcl, so call Tcl_Finalize to get it to
     * unload cleanly.
     */

    Tcl_Finalize();
}

/*
 *----------------------------------------------------------------------
 *
 * PnTkInit --
 *
 *	Initialize Tk.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	.
 *
 *----------------------------------------------------------------------
 */

int
PnTkInit(Tcl_Interp *interp)
{
    static int (*initTk)(Tcl_Interp *) = (int (*)(Tcl_Interp *)) NULL;
    if (!initTk) {
	initTk = (int (*)(Tcl_Interp *)) dlsym(tkHandle, "Tk_Init");
	if (!initTk) {
	    return TCL_ERROR;
	}
    }
    return initTk(interp);
}

/*
 *----------------------------------------------------------------------
 *
 * PnTkSafeInit --
 *
 *	Initialize Safe Tk.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	.
 *
 *----------------------------------------------------------------------
 */

int
PnTkSafeInit(Tcl_Interp *interp)
{
    static int (*initTk)(Tcl_Interp *) = (int (*)(Tcl_Interp *)) NULL;
    if (!initTk) {
	initTk = (int (*)(Tcl_Interp *)) dlsym(tkHandle, "Tk_SafeInit");
	if (!initTk) {
	    return TCL_ERROR;
	}
    }
    return initTk(interp);
}
