/* 
 * npinterp.c --
 *
 *	Implements access to the main interpreter for the Tcl plugin.
 *
 * CONTACT:		tclplugin-core at lists.sourceforge.net
 *
 * Copyright (c) 1995-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 * Copyright (c) 2002-2006 ActiveState Software Inc.
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

static HMODULE tclHandle = NULL;	/* should be the same in any thread */
static char dllName[MAX_PATH] = "";
#ifdef USE_TCL_STUBS
static int tclHandleCnt  = 0;		/* only close on last count */
#endif

static Tcl_Interp * (* tcl_createInterp)() = NULL;
static int (* tcl_createThread)(Tcl_ThreadId *, Tcl_ThreadCreateProc,
	ClientData, int, int) = NULL;
static void (* tcl_findExecutable)(char *) = NULL;
static int (* tclKit_AppInit)(Tcl_Interp *) = NULL;
/*
 * We want the Tcl_InitStubs func static to ourselves - before Tcl
 * is loaded dynamically and possibly changes it.
 */
static volatile CONST char *(* tcl_initStubs)(Tcl_Interp *, CONST char *, int)
    = Tcl_InitStubs;

/*
 * We possibly have per-thread interpreters, as well as one constant, global
 * main intepreter.  The main interpreter runs from NP_Initialize to
 * NP_Shutdown.  tsd interps are used for each instance, but the main
 * interpreter will be used if it is in the same thread.
 *
 * XXX [hobbs]: While we have made some efforts to allow for multi-thread
 * safety, this is not currently in use.  Firefox (up to 1.5) runs all plugin
 * instances in one thread, and we have requested the same from the
 * accompanying pluginhostctrl ActiveX control.  The threading bits here are
 * mostly functional, but require marshalling via a master thread to guarantee
 * fully thread-safe operation.
 */
typedef struct ThreadSpecificData {
    Tcl_Interp *interp;
} ThreadSpecificData;

static Tcl_ThreadDataKey dataKey;
static Tcl_Interp *mainInterp = NULL;


/*
 *----------------------------------------------------------------------
 *
 * NpInitInterp --
 *
 *	Initializes a main or instance interpreter.
 *
 * Results:
 *	A standard Tcl error code.
 *
 * Side effects:
 *	Initializes the interp.
 *
 *----------------------------------------------------------------------
 */

int
NpInitInterp(Tcl_Interp *interp)
{
    Tcl_Preserve((ClientData) interp);

    NpLog("tcl_Init(%p) func %p %p\n", interp, tclKit_AppInit, Tcl_Init);
    if (tclKit_AppInit(interp) != TCL_OK) {
	CONST char *msg = Tcl_GetVar(interp, "errorInfo", TCL_GLOBAL_ONLY);
	NpLog(">>> NpInitInterp %s error:\n%s\n",
		(tclKit_AppInit == Tcl_Init) ? "Tcl_Init" : "TclKit_AppInit",
		msg);
	NpPlatformMsg("Failed to initialize Tcl!", "NpInitInterp");
	return TCL_ERROR;
    }

    /*
     * Set sharedlib in interp while we are here.  This will be used to
     * base the location of the default pluginX.Y package in the stardll
     * usage scenario.
     */
    if (Tcl_SetVar2(interp, "plugin", "sharedlib", dllName, TCL_GLOBAL_ONLY)
	    == NULL) {
	NpPlatformMsg("Failed to set plugin(sharedlib)!", "NpInitInterp");
	return TCL_ERROR;
    }

    /*
     * The plugin doesn't directly call Tk C APIs - it's all managed at
     * the Tcl level, so we can just pkg req Tk here instead of calling
     * Tk_InitStubs.
     */
    NpLog("package require Tk\n", interp);
    if (Tcl_PkgRequire(interp, "Tk", "8.4", 0) == NULL) {
	NpPlatformMsg(Tcl_GetStringResult(interp),
		"NpInitInterp Tcl_PkgRequire(Tk)");
	NpPlatformMsg("Failed to create initialize Tk", "NpInitInterp");
	return TCL_ERROR;
    }

    return TCL_OK;
}

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
    ThreadSpecificData *tsdPtr;
    Tcl_Interp *interp;

    NpLog("ENTERING NpCreateMainInterp\n");

#ifdef USE_TCL_STUBS
    /*
     * Determine the libname and version number dynamically
     */
    if (tclHandle == NULL) {
	/*
	 * First see if some other part didn't already load Tcl.
	 */
	DLSYM(tclHandle, "Tcl_CreateInterp", Tcl_Interp * (*)(),
		tcl_createInterp);

	if ((tcl_createInterp == NULL)
		&& (NpLoadLibrary(&tclHandle, dllName, MAX_PATH)
			!= TCL_OK)) {
	    NpPlatformMsg("Failed to load Tcl dll!", "NpCreateMainInterp");
	    return NULL;
	}
	NpLog("NpCreateMainInterp: Using dll '%s'\n", dllName);

	tclHandleCnt++;
	DLSYM(tclHandle, "Tcl_CreateInterp", Tcl_Interp * (*)(),
		tcl_createInterp);
	if (tcl_createInterp == NULL) {
#ifndef WIN32
	    char *error = dlerror();
	    if (error != NULL) {
		NpPlatformMsg(error, "NpCreateMainInterp");
	    }
#endif
	    return NULL;
	}
	DLSYM(tclHandle, "Tcl_CreateThread", int (*)(Tcl_ThreadId *,
		      Tcl_ThreadCreateProc, ClientData, int, int),
		tcl_createThread);
	DLSYM(tclHandle, "Tcl_FindExecutable", void (*)(char *),
		tcl_findExecutable);

	DLSYM(tclHandle, "TclKit_AppInit", int (*)(Tcl_Interp *),
		tclKit_AppInit);
	if ((tclKit_AppInit != NULL) && (dllName[0] != '\0')) {
	    char * (* tclKit_SetKitPath)(char *);
	    /*
	     * We need to see if this has TclKit_SetKitPath
	     */
	    NpLog("NpCreateMainInterp: SetKitPath(%s)\n", dllName);
	    DLSYM(tclHandle, "TclKit_SetKitPath", char * (*)(char *),
		    tclKit_SetKitPath);
	    if (tclKit_SetKitPath != NULL) {
		tclKit_SetKitPath(dllName);
	    }
	}
    } else {
	tclHandleCnt++;
    }
#else
    tcl_createInterp   = Tcl_CreateInterp;
    tcl_findExecutable = Tcl_FindExecutable;
#endif

    if (dllName[0] == '\0') {
#ifdef WIN32
	GetModuleFileNameA((HINSTANCE) tclHandle, dllName, MAX_PATH);
#elif defined(HAVE_DLADDR)
	Dl_info info;
	if (dladdr(tcl_createInterp, &info)) {
	    NpLog("NpCreateMainInterp: using dladdr '%s' => '%s'\n",
		    dllName, info.dli_fname);
	    snprintf(dllName, MAX_PATH, info.dli_fname);
	}
#endif
    }
    NpLog("Tcl_FindExecutable(%s)\n", dllName);
    tcl_findExecutable((dllName[0] == '\0') ? NULL : dllName);

    /*
     * We do not operate in a fully threaded environment.  The ActiveX
     * control is set for pure single-apartment threading and Firefox runs
     * that way by default.  Otherwise we would have to create a thread for
     * the main/master and marshall calls through it.
     *   Tcl_CreateThread(&tid, ThreadCreateProc, clientData,
     *     TCL_THREAD_STACK_DEFAULT, TCL_THREAD_JOINABLE);
     */
    NpLog("Tcl_CreateInterp()\n");
    interp = tcl_createInterp();
    if (interp == (Tcl_Interp *) NULL) {
	NpPlatformMsg("Failed to create main interpreter!",
		"NpCreateMainInterp");
	return NULL;
    }

    /*
     * Until Tcl_InitStubs is called, we cannot make any Tcl API
     * calls without grabbing them by symbol out of the dll.
     * This will be Tcl_PkgRequire for non-stubs builds.
     */
    NpLog("Tcl_InitStubs(%p)\n", interp);
    if (tcl_initStubs(interp, "8.4", 0) == NULL) {
	NpPlatformMsg("Failed to create initialize Tcl stubs!",
		"NpCreateMainInterp");
	return NULL;
    }

    if (tclKit_AppInit == NULL) {
	tclKit_AppInit = Tcl_Init;
    }

    /*
     * From now until shutdown we need this interp alive, hence we
     * preserve it here and release it at NpDestroyInterp time.
     */

    tsdPtr = TCL_TSD_INIT(&dataKey);
    tsdPtr->interp = interp;
    mainInterp = interp;

    if (NpInitInterp(interp) != TCL_OK) {
	return NULL;
    }

    NpLog("LEAVING NpCreateMainInterp interp == %p\n", interp);
    return interp;
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
    if (mainInterp == NULL) {
        NpPanic("BUG: Main interpreter does not exist");
    }
    return mainInterp;
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
     * because this may be the last call from the browser.
     * Could possibly do this as a ThreadExitHandler, but that seems to
     * have race/order issues for reload in Firefox.
     */
    if (mainInterp) {
	ThreadSpecificData *tsdPtr = TCL_TSD_INIT(&dataKey);
	NpLog("Tcl_DeleteInterp(%p) MAIN\n", mainInterp);
	Tcl_DeleteInterp(mainInterp);
	Tcl_Release((ClientData) mainInterp);
	tsdPtr->interp = mainInterp = (Tcl_Interp *) NULL;
    }

    /*
     * We are done using Tcl, so call Tcl_Finalize to get it to unload
     * cleanly.  With stubs, we need to handle dll finalization.
     */

#ifdef USE_TCL_STUBS
    tclHandleCnt--;
    if (tclHandle && tclHandleCnt <= 0) {
	NpLog("Tcl_Finalize && close library\n");
	Tcl_Finalize();
	dlclose(tclHandle);
	tclHandle = NULL;
    } else {
	NpLog("Tcl_ExitThread\n");
	Tcl_ExitThread(0);
    }
#else
    NpLog("Tcl_Finalize\n");
    Tcl_Finalize();
#endif
}

/*
 *----------------------------------------------------------------------
 *
 * NpGetInstanceInterp --
 *
 *	Gets an instance interpreter.  If one doesn't exist, make a new one.
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
NpGetInstanceInterp()
{
    ThreadSpecificData *tsdPtr = TCL_TSD_INIT(&dataKey);
    Tcl_Interp *interp;

    if (tsdPtr->interp != NULL) {
	NpLog("NpGetInstanceInterp - use main interp %p\n", tsdPtr->interp);
	return tsdPtr->interp;
    }

    interp = Tcl_CreateInterp();
    NpLog("NpGetInstanceInterp - create interp %p\n", interp);

    if (NpInitInterp(interp) != TCL_OK) {
	NpLog("NpGetInstanceInterp: NpInitInterp(%p) != TCL_OK\n", interp);
	return NULL;
    }

    /*
     * We rely on NpInit to inform the user if initialization failed.
     */

    if (NpInit(interp) != TCL_OK) {
	NpLog("NpGetInstanceInterp: NpInit(%p) != TCL_OK\n", interp);
	return NULL;
    }

    return interp;
}

/*
 *----------------------------------------------------------------------
 *
 * NpDestroyInstanceInterp --
 *
 *	Destroys an instance interpreter and performs cleanup actions.
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
NpDestroyInstanceInterp(Tcl_Interp *interp)
{
    ThreadSpecificData *tsdPtr = TCL_TSD_INIT(&dataKey);

    if (tsdPtr->interp == interp) {
	NpLog("NpDestroyInstanceInterp(%p) - using main interp\n", interp);
	return;
    }
    NpLog("Tcl_DeleteInterp(%p) INSTANCE\n", interp);
    Tcl_DeleteInterp(interp);
    Tcl_Release((ClientData) interp);
}
