/* 
 * npinterp.c --
 *
 *	Implements access to the main interpreter for the Tcl plugin.
 *
 * CONTACT:		tclplugin-core@lists.sourceforge.net
 *
 * Copyright (c) 1995-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 * Copyright (c) 2002-2004 ActiveState Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS:  @(#) $Id$
 */

#include "np.h"

/*
 * Static variables in this file:
 */

static Tcl_Interp *npInterp = (Tcl_Interp *) NULL;

#ifdef WIN32

#ifdef USE_TCL_STUBS
static HMODULE tclHandle      = NULL;
static HMODULE tkHandle       = NULL;
#endif

#include <windows.h>
#define dlsym(handle, symbol)	GetProcAddress((HINSTANCE) handle, symbol)
#define dlclose(path)		((void *) FreeLibrary((HMODULE) path))

#else

#include <dlfcn.h>

#ifdef USE_TCL_STUBS
static void *tclHandle      = NULL;
static void *tkHandle       = NULL;
#endif

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

    NpLog("ENTERING NpCreateMainInterp\n");

    if (npInterp != NULL) {
	NpLog("LEAVING NpCreateMainInterp - USE EXISTING 0x%x\n", npInterp);
	return npInterp;
    }

#ifdef USE_TCL_STUBS
    /*
     * Determine the libname and version number dynamically
     */
    if (tclHandle == NULL) {
#ifndef WIN32
	char *error;
#endif

	if (NpLoadLibrary(&tclHandle, &tkHandle) != TCL_OK) {
	    NpPlatformMsg("Failed to load Tcl/Tk dlls!", "NpCreateMainInterp");
	    return NULL;
	}

	createInterp = (Tcl_Interp * (*)()) dlsym(tclHandle,
		"Tcl_CreateInterp");
#ifndef WIN32
	if ((createInterp == NULL) && ((error = dlerror()) != NULL)) {
	    NpPlatformMsg(error, "NpCreateMainInterp");
	    return NULL;
	}
#endif
	findExecutable = (void (*)(char *)) dlsym(tclHandle,
		"Tcl_FindExecutable");

	tkInit     = (int (*)(Tcl_Interp *)) dlsym(tkHandle, "Tk_Init");
#ifndef WIN32
	if ((tkInit == NULL) && ((error = dlerror()) != NULL)) {
	    NpPlatformMsg(error, "NpCreateMainInterp");
	    return NULL;
	}
#endif
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
    NpLog("Tcl_FindExecutable(%s)\n", name);
    findExecutable(name);
#else
    NpLog("Tcl_FindExecutable(NULL)\n");
    findExecutable(NULL);
#endif

    NpLog("Tcl_CreateInterp()\n");
    npInterp = createInterp();
    if (npInterp == (Tcl_Interp *) NULL) {
	NpPlatformMsg("Failed to create main interpreter!",
		"NpCreateMainInterp");
	return NULL;
    }

    /*
     * Until Tcl_InitStubs is called, we cannot make any Tcl/Tk API
     * calls without grabbing them by symbol out of the dll.
     * This will be Tcl_PkgRequire for non-stubs builds.
     */
    NpLog("Tcl_InitStubs(%p)\n", npInterp);
    if (initstubs(npInterp, "8.4", 0) == NULL) {
	NpPlatformMsg("Failed to create initialize Tcl stubs!",
		"NpCreateMainInterp");
	return NULL;
    }

    NpLog("Tcl_Init(%p)\n", npInterp);
    if (Tcl_Init(npInterp) != TCL_OK) {
	CONST84 char *msg = Tcl_GetVar(npInterp, "errorInfo", TCL_GLOBAL_ONLY);
	NpLog(">>> NpCreateMainInterp Tcl_Init error: %s\n", msg);
	NpPlatformMsg("Failed to create initialize Tcl!",
		"NpCreateMainInterp");
	return NULL;
    }

    NpLog("Tk_Init(%p)\n", npInterp);
    if (tkInit(npInterp) != TCL_OK) {
	CONST84 char *msg = Tcl_GetVar(npInterp, "errorInfo", TCL_GLOBAL_ONLY);
	NpLog(">>> NpCreateMainInterp Tk_Init error: %s\n", msg);
    }

    /*
     * Allow our interp to load Tk on demand
     * We must pass NULL as the first argument or loading in this
     * interp will not do anything !
     */

    Tcl_StaticPackage(NULL, "Tk", tkInit, tkSafeInit);
#if 0
    NpLog("NpInit: Tk_InitConsoleChannels\n");
    Tk_InitConsoleChannels(npInterp);
#endif

    /*
     * From now until shutdown we need this interp alive, hence we
     * preserve it here and release it at NpDestroyInterp time.
     */

    Tcl_Preserve((ClientData) npInterp);

    NpLog("LEAVING NpCreateMainInterp interp == 0x%x\n", npInterp);
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
	NpLog("Tcl_DeleteInterp(%p)\n", npInterp);
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
