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
#endif

#include <windows.h>
#define dlsym(handle, symbol)	GetProcAddress((HINSTANCE) handle, symbol)
#define dlclose(path)		((void *) FreeLibrary((HMODULE) path))
#define snprintf _snprintf

#else

#include <dlfcn.h>

#endif

static HMODULE tclHandle      = NULL;


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
    static int (* tclKit_AppInit)(Tcl_Interp *) = NULL;
    /*
     * We want the Tcl_InitStubs func static to ourselves - before Tcl
     * is loaded dyanmically and possibly changes it.
     */
    static CONST char *(*initstubs)(Tcl_Interp *, CONST char *, int)
	= Tcl_InitStubs;
    char dllName[MAX_PATH];
    dllName[0] = 0;

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
	/*
	 * First see if some other part didn't already load Tcl.
	 */
	createInterp = (Tcl_Interp * (*)()) dlsym(tclHandle,
		"Tcl_CreateInterp");

	if ((createInterp == NULL)
		&& (NpLoadLibrary(&tclHandle, dllName, MAX_PATH)
			!= TCL_OK)) {
	    NpPlatformMsg("Failed to load Tcl dll!", "NpCreateMainInterp");
	    return NULL;
	}
	NpLog("NpCreateMainInterp: Using dll '%s'\n", dllName);

	createInterp = (Tcl_Interp * (*)()) dlsym(tclHandle,
		"Tcl_CreateInterp");
	if (createInterp == NULL) {
#ifndef WIN32
	    if ((error = dlerror()) != NULL) {
		NpPlatformMsg(error, "NpCreateMainInterp");
	    }
#endif
	    return NULL;
	}
	findExecutable = (void (*)(char *)) dlsym(tclHandle,
		"Tcl_FindExecutable");

	tclKit_AppInit = (int (*)(Tcl_Interp *)) dlsym(tclHandle,
		"TclKit_AppInit");
	if ((tclKit_AppInit != NULL) && (dllName[0] != '\0')) {
	    char * (* tclKit_SetKitPath)(char *);
	    /*
	     * We need to see if this has TclKit_SetKitPath
	     */
	    NpLog("NpCreateMainInterp: SetKitPath(%s)\n", dllName);
	    tclKit_SetKitPath = (char * (*)(char *)) dlsym(tclHandle,
		    "TclKit_SetKitPath");
	    if (tclKit_SetKitPath != NULL) {
		tclKit_SetKitPath(dllName);
	    }
	}
    }
#else
    createInterp   = Tcl_CreateInterp;
    findExecutable = Tcl_FindExecutable;
#endif

    if (dllName[0] == 0) {
#ifdef WIN32
	GetModuleFileNameA((HINSTANCE) tclHandle, dllName, MAX_PATH);
#elif defined(HAVE_DLADDR)
	Dl_info info;
	if (dladdr(createInterp, &info)) {
	    NpLog("NpCreateMainInterp: using dladdr '%s' => '%s'\n",
		    dllName, info.dli_fname);
	    snprintf(dllName, MAX_PATH, info.dli_fname);
	}
#endif
    }
    NpLog("Tcl_FindExecutable(%s)\n", dllName);
    findExecutable((dllName[0] == '\0') ? NULL : dllName);

    NpLog("Tcl_CreateInterp()\n");
    npInterp = createInterp();
    if (npInterp == (Tcl_Interp *) NULL) {
	NpPlatformMsg("Failed to create main interpreter!",
		"NpCreateMainInterp");
	return NULL;
    }

    /*
     * Until Tcl_InitStubs is called, we cannot make any Tcl API
     * calls without grabbing them by symbol out of the dll.
     * This will be Tcl_PkgRequire for non-stubs builds.
     */
    NpLog("Tcl_InitStubs(%p)\n", npInterp);
    if (initstubs(npInterp, "8.4", 0) == NULL) {
	NpPlatformMsg("Failed to create initialize Tcl stubs!",
		"NpCreateMainInterp");
	return NULL;
    }

    if (tclKit_AppInit == NULL) {
	tclKit_AppInit = Tcl_Init;
    }

    NpLog("tcl_Init(%p)\n", npInterp);
    if (tclKit_AppInit(npInterp) != TCL_OK) {
	CONST84 char *msg = Tcl_GetVar(npInterp, "errorInfo", TCL_GLOBAL_ONLY);
	NpLog(">>> NpCreateMainInterp tcl_Init error:\n%s\n", msg);
	NpPlatformMsg("Failed to create initialize Tcl!",
		"NpCreateMainInterp");
	return NULL;
    }

    NpLog("package require Tk\n", npInterp);
    if (Tcl_PkgRequire(npInterp, "Tk", "8.4", 0) == NULL) {
	NpPlatformMsg(Tcl_GetStringResult(npInterp),
		"NpCreateMainInterp Tcl_PkgRequire(Tk)");
	NpPlatformMsg("Failed to create initialize Tk", "NpCreateMainInterp");
	return NULL;
    }

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
    if (tclHandle) {
	dlclose(tclHandle);
	tclHandle = NULL;
    }
#endif
}
