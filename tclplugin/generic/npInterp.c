/* 
 * npinterp.c --
 *
 *	Implements access to the main interpreter for the Tcl plugin.
 *
 * CONTACT:		tclplugin-core@lists.sourceforge.net
 *
 * ORIGINAL AUTHORS:	Jacob Levy			Laurent Demailly
 *
 * Copyright (c) 1995-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 * Copyright (c) 2002 ActiveState Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS:  @(#) $Id$
 */

#include "np.h"
#include <string.h>

/*
 * Static variables in this file:
 */

static Tcl_Interp *npInterp = (Tcl_Interp *) NULL;

#ifdef USE_TCL_STUBS
static void *tclHandle      = (void *) NULL;
static void *tkHandle       = (void *) NULL;
#endif

#ifdef WIN32
#include <windows.h>
#ifndef TCL_LIB_FILE
#   define TCL_LIB_FILE "tcl81.dll"
#endif

#ifdef USE_TCL_STUBS
#define dlopen(path, flags)	((void *) LoadLibrary(path))
#define dlsym(handle, symbol)	GetProcAddress((HINSTANCE) handle, symbol)
#define dlclose(path)		((void *) FreeLibrary((HMODULE) path))
#endif

#else

#include <dlfcn.h>
#ifndef TCL_LIB_FILE
#  define TCL_LIB_FILE "libtcl8.3.so"
#endif

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
    static Tcl_Interp * (* createInterp)() = NULL;
    static void (* findExecutable)(char *) = NULL;
    static int (*tkInit)(Tcl_Interp *)     = NULL;
    static int (*tkSafeInit)(Tcl_Interp *) = NULL;
    /*
     * We want the Tcl_InitStubs func static to ourselves - before Tcl
     * is loaded dyanmically and possibly changes it.
     */
    static CONST char *(*initstubs)(Tcl_Interp *, CONST char *, int)
	= Tcl_InitStubs;
#ifdef WIN32
    char name[MAX_PATH];
#endif

    NpLog("ENTERING NpCreateMainInterp\n", 0,0,0);

    if (npInterp != NULL) {
	NpLog("LEAVING NpCreateMainInterp - USE EXISTING 0x%x\n",
		(int) npInterp, 0, 0);
	return npInterp;
    }

#ifdef USE_TCL_STUBS
    /*
     * Determine the libname and version number dynamically
     */
    if (tclHandle == NULL) {
	char *pos, libname[256] = TCL_LIB_FILE;
	if (strlen(TCL_LIB_FILE) < 3) {
	    NpPanic("Invalid base Tcl library filename provided!");
	}
	NpLog("Searching for tcl lib based on %s\n", (int) TCL_LIB_FILE, 0, 0);
	pos = strstr(libname, "tcl")+4;
	if (*pos == '.') {
	    pos++;
	}
	*pos = '5'; /* count down from '4' to '1'*/
	while (!tclHandle && (--*pos > '0')) {
	    tclHandle = dlopen(libname, RTLD_NOW | RTLD_GLOBAL);
	}
	if (!tclHandle) {
	    NpPanic("Failed to load Tcl dll!");
	}
	NpLog("Loaded tcl lib %s\n", (int) libname, 0, 0);

	/*
	 * Derive the name of Tk's library from Tcl's.
	 * Should work on all platforms
	 */
	pos = strstr(libname, "tcl")+2;
	*pos-- = 'k';
	while (pos > libname) {
	    *pos-- = pos[-1];
	}
	tkHandle = dlopen(libname+1, RTLD_NOW | RTLD_GLOBAL);
	if (!tkHandle) {
	    NpPanic("Failed to load Tk dll!");
	}
	NpLog("Loaded tk lib %s\n", (int) libname+1, 0, 0);

	createInterp = (Tcl_Interp * (*)()) dlsym(tclHandle,
		"Tcl_CreateInterp");
	findExecutable = (void (*)(char *)) dlsym(tclHandle,
		"Tcl_FindExecutable");

	tkInit     = (int (*)(Tcl_Interp *)) dlsym(tkHandle, "Tk_Init");
	tkSafeInit = (int (*)(Tcl_Interp *)) dlsym(tkHandle, "Tk_SafeInit");
    }
#else
    createInterp   = Tcl_CreateInterp;
    findExecutable = Tcl_FindExecutable;
    tkInit	   = Tk_Init;
    tkSafeInit	   = Tk_SafeInit;
#endif

#ifdef WIN32
    name[0] = '\0';
#ifdef USE_TCL_STUBS
    GetModuleFileNameA((HINSTANCE) tclHandle, name, MAX_PATH);
#else
    GetModuleFileNameA(NULL, name, MAX_PATH);
#endif
    NpLog("Tcl_FindExecutable(%s)\n", (int) name, 0, 0);
    findExecutable(name);
#else
    NpLog("Tcl_FindExecutable(NULL)\n", 0, 0, 0);
    findExecutable(NULL);
#endif

    npInterp = createInterp();
    if (npInterp == (Tcl_Interp *) NULL) {
        NpPanic("Failed to create main interpreter!");
    }

    /*
     * Until Tcl_InitStubs is called, we cannot make any Tcl/Tk API
     * calls without grabbing them by symbol out of the dll.
     * This will be Tcl_PkgRequire for non-stubs builds.
     */
    NpLog("Tcl_InitStubs(%p)\n", (int) npInterp, 0, 0);
    if (initstubs(npInterp, "8.2", 0) == NULL) {
        NpPanic("Failed to create initialize Tcl stubs!");
    }

    NpLog("Tcl_Init(%p)\n", (int) npInterp, 0, 0);
    if (Tcl_Init(npInterp) != TCL_OK) {
	CONST84 char *msg = Tcl_GetVar(npInterp, "errorInfo", TCL_GLOBAL_ONLY);
	NpLog(">>> NpCreateMainInterp Tcl_Init error: %s\n", (int) msg, 0, 0);
        NpPanic("Failed to create initialize Tcl!");
    }

    NpLog("Tk_Init(%p)\n", (int) npInterp, 0, 0);
    if (tkInit(npInterp) != TCL_OK) {
	CONST84 char *msg = Tcl_GetVar(npInterp, "errorInfo", TCL_GLOBAL_ONLY);
	NpLog(">>> NpCreateMainInterp Tk_Init error: %s\n", (int) msg, 0, 0);
    }

    /*
     * Allow our interp to load Tk on demand
     * We must pass NULL as the first argument or loading in this
     * interp will not do anything !
     */

    Tcl_StaticPackage(NULL, "Tk", tkInit, tkSafeInit);
#if 0
    NpLog("NpInit: Tk_InitConsoleChannels\n", 0,0,0);
    Tk_InitConsoleChannels(npInterp);
#endif

    /*
     * From now until shutdown we need this interp alive, hence we
     * preserve it here and release it at NpDestroyInterp time.
     */

    Tcl_Preserve((ClientData) npInterp);

    NpLog("LEAVING NpCreateMainInterp interp == 0x%x\n", (int) npInterp, 0, 0);
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
    if (npInterp) {
	NpLog("Tcl_DeleteInterp(%p)\n", (int) npInterp, 0, 0);
	Tcl_DeleteInterp(npInterp);
	Tcl_Release((ClientData) npInterp);
	npInterp = (Tcl_Interp *) NULL;
    }

    /*
     * We are done using Tcl, so call Tcl_Finalize to get it to
     * unload cleanly.
     */
    Tcl_Finalize();

#ifdef USE_TCL_STUBS
    if (tkHandle) {
	dlclose(tkHandle);
	tkHandle = NULL;
    }
    if (tclHandle) {
	dlclose(tclHandle);
	tclHandle = NULL;
    }
#endif
}
