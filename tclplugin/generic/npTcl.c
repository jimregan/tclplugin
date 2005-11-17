/* 
 * nptcl.c --
 *
 *	Implements the glue between Tcl script and
 *	the plugin stub in the WWW browser.
 *
 * CONTACT:		tclplugin-core@lists.sourceforge.net
 *
 * Copyright (c) 1995-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 * Copyright (c) 2002-2005 ActiveState Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS:  @(#) $Id$
 */

#include "np.h"

/*
 * Stack counter
 */
static int nptcl_stack		= 0;
static int nptcl_instances	= 0;
static int nptcl_shutdown	= 0;

TCL_DECLARE_MUTEX(pluginMutex)


/*
 *----------------------------------------------------------------------
 *
 * NpInit --
 *
 *	Creates the main interpreter, initializes Tcl and the Plugin
 *
 * Results:
 *	A standard Tcl result.
 *
 * Side effects:
 *	Prepares for using Tcl in this process.
 *
 *----------------------------------------------------------------------
 */

int
NpInit(Tcl_Interp *interp)
{
    Tcl_DString dsAddPath;

    /*
     * Install hash tables for instance tokens and stream tokens.
     */

    NpLog(">>> NpInit(%p)\n", interp);
    NpInitTokenTables(interp);

    /*
     * Initialize the Plugin->Netscape interface commands.
     * These are commands that can be invoked from the plugin
     * to perform special operations on the hosting browser:
     * (To call the NPN_... APIs)
     */

    NpLog("NpInit: PnInit(%p)\n", interp);
    if (PnInit(interp) != TCL_OK) {
        NpPlatformMsg(Tcl_GetStringResult(interp), "NpInit (Pn functions)");
        return TCL_ERROR;
    }

    /*
     * Set the plugin versions and patchLevel.
     */

    Tcl_SetVar2(interp, "plugin", "version", NPTCL_VERSION, TCL_GLOBAL_ONLY);
    Tcl_SetVar2(interp, "plugin", "patchLevel", NPTCL_PATCH_LEVEL,
            TCL_GLOBAL_ONLY);
    Tcl_SetVar2(interp, "plugin", "pkgVersion", NPTCL_INTERNAL_VERSION,
            TCL_GLOBAL_ONLY);

    /*
     * Check for plugin directory next to sharedlib.  If it exists, extend
     * the auto_path before requiring the plugin package.
     * plugin(sharedlib) is set in NpCreateMainInterp.
     */
    Tcl_DStringInit(&dsAddPath);
    Tcl_DStringAppend(&dsAddPath,
	    "set plugin(pkgPath) \"[file dirname $plugin(sharedlib)]/plugin"
	    NPTCL_VERSION "\"\n"
	    "if {[file exists $plugin(pkgPath)]} {\n"
	    "    lappend ::auto_path $plugin(pkgPath)\n"
	    "} else {\n"
	    "    unset plugin(pkgPath)\n"
	    "}\n", -1
	);
    if (Tcl_EvalEx(interp, Tcl_DStringValue(&dsAddPath), -1,
		TCL_EVAL_GLOBAL | TCL_EVAL_DIRECT) != TCL_OK) {
	NpPlatformMsg(Tcl_GetStringResult(interp), "Plug_Init/SetAutoPath");
	Tcl_DStringFree(&dsAddPath);
        return TCL_ERROR;
    }
    Tcl_DStringFree(&dsAddPath);

    if (Tcl_PkgRequire(interp, "plugin", NPTCL_VERSION, 0) == NULL) {
	NpPlatformMsg(Tcl_GetStringResult(interp), "Plug_Init/PkgRequire");
        return TCL_ERROR;
    }

    /*
     * Perform platform specific initialization.
     */

    if (NpPlatformInit(interp, 1 /* external */) != TCL_OK) {
	NpPlatformMsg(Tcl_GetStringResult(interp), "Plug_Init/NpPlatformInit");
        return TCL_ERROR;
    }

    NpLog(">>> NpInit finished OK\n");
    return TCL_OK;
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_Initialize --
 *
 *	Initializes a plugin instance.
 *
 * Results:
 *	A Netscape error code.
 *
 * Side effects:
 *	None at present.
 *
 *----------------------------------------------------------------------
 */

NPError
NPP_Initialize()
{
    Tcl_Interp *interp;
    char *logfile = NP_LOG;

    if (logfile == NULL) {
	logfile = getenv("TCL_PLUGIN_DLL_LOGFILE");
    }
    if (logfile) {
	NpStartLog(logfile);
    }

    nptcl_stack		= 0;
    nptcl_instances	= 0;
    nptcl_shutdown	= 0;

    NpLog("NPP_Initialize [STACK=%d, INSTANCES=%d, STREAMS=%d]\n",
	    nptcl_stack, nptcl_instances, NpTclStreams(0));

    interp = NpCreateMainInterp();
    if (interp == NULL) {
	NpLog("NPP_Initialize: interp == NULL\n");
	return NPERR_GENERIC_ERROR;
    }

    /*
     * We need to service all events for initilization and
     * so that when matching calls to NpEnter/NpLeave 
     * happen, the final mode will again be TCL_SERVICE_ALL.
     */

    NpLog("Service ALL events [STACK=%d, INSTANCES=%d, STREAMS=%d]\n",
	    nptcl_stack, nptcl_instances, NpTclStreams(0));
    Tcl_SetServiceMode(TCL_SERVICE_ALL);

    /*
     * We rely on NpInit to inform the user if initialization failed.
     */

    if (NpInit(interp) != TCL_OK) {
	NpLog("NPP_Initialize: NpInterp != TCL_OK\n");
	return NPERR_GENERIC_ERROR;
    }

    NpLog("NPP_Initialize FINISHED OK\n");
    return NPERR_NO_ERROR;
}

/*
 *----------------------------------------------------------------------
 *
 * NpShutdown --
 *
 *	Informs Tcl that we are in shutdown processing, and stops event
 *	processing.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Stops event processing.
 *
 *----------------------------------------------------------------------
 */

void
NpShutdown(Tcl_Interp *interp)
{
    (void) Tcl_EvalEx(interp, "npShutDown", -1, TCL_EVAL_GLOBAL);

    /*
     * Remove the token tables.
     */

    NpDeleteTokenTables(interp);
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_Shutdown --
 *
 *	Shuts down the main interpreter and prepare the unloading of
 *      Tcl plugin library
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Cleans up Tcl.
 *
 *----------------------------------------------------------------------
 */

void
NPP_Shutdown()
{ 
    int oldServiceMode = NpEnter("NPP_Shutdown");


    if (oldServiceMode != TCL_SERVICE_ALL) {
	NpLog("Old service mode is not TCL_SERVICE_ALL!\n");
    }

    /*
     * Let Tcl know about the impending shutdown.
     */

    NpShutdown(NpGetMainInterp());

    /*
     * Deal with any pending events one last time:
     */
    NpLeave("NPP_Shutdown", TCL_SERVICE_ALL);

    Tcl_ServiceAll();

    Tcl_MutexFinalize(&pluginMutex);

    /*
     * Shut down the main Tcl interpreter.
     */
    NpDestroyMainInterp();

    /*
     * Last platform dependant cleanup before the library becomes unloaded.
     * On Unix it will stop the notifier. On the Mac it will free the low
     * level memory allocated for Tcl. Thus no Tcl code nor access to
     * memory allocated with ckalloc() should occur beyond that point.
     */
    NpPlatformShutdown();

    if (nptcl_stack != 0) {
	NpLog("SERIOUS ERROR (potential crash): Invalid shutdown stack = %d\n",
		nptcl_stack);
    }
    if (nptcl_instances != 0) {
	NpLog("ERROR Invalid shutdown instances count = %d\n",
		nptcl_instances);
    }
    if (NpTclStreams(0) != 0) {
	NpLog("ERROR Invalid shutdown streams count = %d\n", NpTclStreams(0));
    }

    nptcl_shutdown = 1;

    NpLog("EXITING SHUTDOWN\n");

    /* NpStopLog(); */
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_New --
 *
 *	Creates a new instance of the plugin. Initializes the Tcl
 *	interpreter for this instance and adds the Netscape plugin
 *	specific commands to the interpreter.
 *
 * Results:
 *	A standard Netscape error code.
 *
 * Side effects:
 *	Creates a new Tcl interpreter and a number of new Tcl commands.
 *
 * NB: It seem that we must use ANSI (ISO) C definition with prototypes
 * for that function, otherwise the int16 arguments will not have the
 * proper width (unexpected promotion to int...)
 *
 *----------------------------------------------------------------------
 */

NPError NP_LOADDS
NPP_New(NPMIMEType pluginType, NPP instance, uint16 mode, int16 argc,
	char *argn[], char *argv[], NPSavedData *savedPtr)
{
    int i, oldServiceMode;
    Tcl_Interp *interp;
    Tcl_Obj *objPtr;

    if (instance == NULL) {
	NpLog(">>> NPP_New NULL instance\n");
	return NPERR_INVALID_INSTANCE_ERROR;
    }

    if (nptcl_shutdown) {
	NPP_Initialize();
	NpLog("WARNING: we had to call Initialize from NPP_New\n");
    }

    oldServiceMode = NpEnter("NPP_New");
    
    nptcl_instances++;

    /*
     * Ensure that instance->pdata has a distinguished uninitialized (NULL)
     * value.
     */

    instance->pdata = (void *) NULL;

    /*
     * Platform specific initialization. 
     * On unix it will start the notifier in the context of that instance.
     */

    NpPlatformNew(instance);

    /*
     * Get the main interpreter.
     */
    
    interp = NpGetMainInterp();

    /*
     * Register this instance of the Tcl plugin.
     */

    NpRegisterToken((ClientData) instance, interp, NPTCL_INSTANCE);

    objPtr = Tcl_NewObj();
    Tcl_ListObjAppendElement(NULL, objPtr,
	    Tcl_NewStringObj("npNewInstance", -1));
    Tcl_ListObjAppendElement(NULL, objPtr,
	    Tcl_NewLongObj((long) instance));
    for (i = 0; i < argc; i++) {
	Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewStringObj(argn[i], -1));
	Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewStringObj(argv[i], -1));
    }
    Tcl_ListObjAppendElement(NULL, objPtr,
	    Tcl_NewStringObj("embed_mode", -1));
    switch (mode) {
        case NP_EMBED:
	    Tcl_ListObjAppendElement(NULL, objPtr,
		    Tcl_NewStringObj("embed", -1));
            break;
        case NP_FULL:
	    Tcl_ListObjAppendElement(NULL, objPtr,
		    Tcl_NewStringObj("full", -1));
            break;
        default:
	    Tcl_ListObjAppendElement(NULL, objPtr,
		    Tcl_NewStringObj("hidden", -1));
	    NpLog("Undefined mode (%d) in NPP_New, assuming 'hidden'\n", mode);
            break;
    }
    Tcl_IncrRefCount(objPtr);
    if (Tcl_EvalObjEx(interp, objPtr, TCL_EVAL_GLOBAL|TCL_EVAL_DIRECT)
	    != TCL_OK) {
	NpPlatformMsg(Tcl_GetVar(interp, "errorInfo", TCL_GLOBAL_ONLY),
		"npNewInstance");
        /*
         * Do not return an error to the container because this may
         * cause the container to destroy the instance, and we would
         * get out of sync with the container because we do not get
         * any further invocations for this instance. The problem here
         * is that different browsers handle errors at this stage differently
         * so we do not know if it is safe to unregister the token yet.
         */
    }
    Tcl_DecrRefCount(objPtr);

    NpLeave("NPP_New", oldServiceMode);
    return NPERR_NO_ERROR;
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_Destroy --
 *
 *	Destroys the instance.
 *
 * Results:
 *	A standard Netscape error code.
 *
 * Side effects:
 *	Destroys the instance and its embedded Tcl applet.
 *
 *----------------------------------------------------------------------
 */

	/* ARGSUSED */
NPError NP_LOADDS
NPP_Destroy(NPP instance, NPSavedData **savePtrPtr)
{
    int oldServiceMode;
    Tcl_Interp  *interp;
    Tcl_Obj *objPtr;

    if (instance == NULL) {
	NpLog(">>> NPP_Destroy NULL instance\n");
	return NPERR_INVALID_INSTANCE_ERROR;
    }

    oldServiceMode = NpEnter("NPP_Destroy");

    interp = NpGetMainInterp();

    /*
     * Tell Tcl that we are destroying this instance:
     */
    
    objPtr = Tcl_NewObj();
    Tcl_ListObjAppendElement(NULL, objPtr,
	    Tcl_NewStringObj("npDestroyInstance", -1));
    Tcl_ListObjAppendElement(NULL, objPtr,
	    Tcl_NewLongObj((long) instance));

    Tcl_IncrRefCount(objPtr);
    if (Tcl_EvalObjEx(interp, objPtr, TCL_EVAL_GLOBAL|TCL_EVAL_DIRECT)
	    != TCL_OK) {
        NpPlatformMsg(Tcl_GetStringResult(interp), "npDestroyInstance");
    }
    Tcl_DecrRefCount(objPtr);

    /*
     * Forget the association between this container and the instance
     * pointer (or whatever NpPlatformSetWindow could have done) :
     */

    NpPlatformDestroy(instance);

    NpUnregisterToken(interp, (void *) instance, NPTCL_INSTANCE);

    nptcl_instances--;

    NpLeave("NPP_Destroy", oldServiceMode);
    return NPERR_NO_ERROR;
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_SetWindow --
 *
 *	Associate a Netscape window with the plugin.
 *
 * Results:
 *	A standard Netscape error code.
 *
 * Side effects:
 *	Initializes Tk in the instance if it has not yet been initialized.
 *
 *----------------------------------------------------------------------
 */

NPError NP_LOADDS
NPP_SetWindow(NPP instance, NPWindow *window)
{
    Tcl_Interp *interp;
    NPError rv = NPERR_NO_ERROR;
    int oldServiceMode;

    if (instance == NULL) {
	NpLog(">>> NPP_SetWindow NULL instance\n");
	return NPERR_INVALID_INSTANCE_ERROR;
    }

    if (window == NULL) {
	NpLog(">>> NPP_SetWindow(%p) NPWindow == NULL\n", instance);
	return NPERR_GENERIC_ERROR;
    }

    oldServiceMode = NpEnter("NPP_SetWindow");

    NpLog("*** NPP_SetWindow instance %p window %p\n",
	    instance, window);

    interp = NpGetMainInterp();

    if (window->window == NULL) {
	NpLog(">>> Ignoring NPP_SetWindow with NULL window (%d x %d)\n",
		window->width, window->height);
    } else {
	char buf[256];
	Tcl_Obj *objPtr;

	snprintf(buf, 256, "0x%x +%d+%d %dx%d",
		(int) window->window,
		(int) window->x, (int) window->y,
		(int) window->width, (int) window->height);
	NpLog("*** NPP_SetWindow %s\n", buf);

	/*
	 * Call platform specific call which will remember that 
	 * this window is a container for the supplied instance
	 * pointer and eventually deal with the focus, etc... :
	 */

	NpPlatformSetWindow(instance, window);

	/*
	 * Now tell the tcl side about this new container window:
	 */

	objPtr = Tcl_NewObj();
	Tcl_ListObjAppendElement(NULL, objPtr,
		Tcl_NewStringObj("npSetWindow", -1));
	Tcl_ListObjAppendElement(NULL, objPtr,
		Tcl_NewLongObj((long) instance));
	Tcl_ListObjAppendElement(NULL, objPtr,
		Tcl_NewLongObj((long) window->window));
	Tcl_ListObjAppendElement(NULL, objPtr,
		Tcl_NewLongObj((long) window->x));
	Tcl_ListObjAppendElement(NULL, objPtr,
		Tcl_NewLongObj((long) window->y));
	Tcl_ListObjAppendElement(NULL, objPtr,
		Tcl_NewLongObj((long) window->width));
	Tcl_ListObjAppendElement(NULL, objPtr,
		Tcl_NewLongObj((long) window->height));
	Tcl_ListObjAppendElement(NULL, objPtr,
		Tcl_NewLongObj((long) window->clipRect.top));
	Tcl_ListObjAppendElement(NULL, objPtr,
		Tcl_NewLongObj((long) window->clipRect.left));
	Tcl_ListObjAppendElement(NULL, objPtr,
		Tcl_NewLongObj((long) window->clipRect.bottom));
	Tcl_ListObjAppendElement(NULL, objPtr,
		Tcl_NewLongObj((long) window->clipRect.right));

	Tcl_IncrRefCount(objPtr);
	if (Tcl_EvalObjEx(interp, objPtr, TCL_EVAL_GLOBAL|TCL_EVAL_DIRECT)
		!= TCL_OK) {
	    NpPlatformMsg(Tcl_GetStringResult(interp), "npSetWindow");
	    rv = NPERR_GENERIC_ERROR;
	}
	Tcl_DecrRefCount(objPtr);
	Tcl_ServiceAll();
    }

    NpLeave("NPP_SetWindow", oldServiceMode);
    return rv;
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_Print --
 *
 *	Pretends to print.
 *
 * Results:
 *	A standard Netscape error code.
 *
 * Side effects:
 *	Doesn't do squat.
 *
 *----------------------------------------------------------------------
 */

	/* ARGSUSED */
void NP_LOADDS
NPP_Print(NPP instance, NPPrint *printInfo)
{
    /* Unimplemented for now. */
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_GetValue --
 *
 *     Does ...
 *
 * Results:
 *     In this plugin, always NULL.
 *
 * Side effects:
 *     None.
 *
 *----------------------------------------------------------------------
 */

NPError
NPP_GetValue(NPP instance, NPPVariable variable, void *value)
{
    static char msgBuf[512];
    NPError rv = NPERR_NO_ERROR;

    NpLog("NPP_GetValue(%p, %p, %p)\n", instance, variable, value);
    if (instance == NULL) {
	NpLog(">>> NPP_GetValue NULL instance\n");
	/* return NPERR_INVALID_INSTANCE_ERROR; */
    }

    switch (variable) {
        case NPPVpluginNameString:
            snprintf(msgBuf, 512, "Tcl Plugin %s", NPTCL_PATCH_LEVEL);
            *((char **)value) = msgBuf;
            break;
        case NPPVpluginDescriptionString:
            snprintf(msgBuf, 512,
		    "TCL Plugin %s (%s). Executes tclets found in Web pages.\
See the <a href=\"http://www.tcl.tk/software/plugin/\">Tcl Plugin</a> \
home page for more details.",
                    NPTCL_PATCH_LEVEL, NPTCL_INTERNAL_VERSION);
            *((char **)value) = msgBuf;
            break;
	case NPPVpluginWindowBool:
	case NPPVpluginTransparentBool:
	case NPPVjavaClass:
	case NPPVpluginWindowSize:
	case NPPVpluginTimerInterval:
	case NPPVpluginScriptableInstance:
	case NPPVpluginScriptableIID:
	case NPPVjavascriptPushCallerBool:
	case NPPVpluginKeepLibraryInMemory:
        default:
            rv = NPERR_GENERIC_ERROR;
    }
    return rv;
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_SetValue --
 *
 *     Does ...
 *
 * Results:
 *     In this plugin, always NULL.
 *
 * Side effects:
 *     None.
 *
 *----------------------------------------------------------------------
 */

NPError
NPP_SetValue(NPP instance, NPNVariable variable, void *value)
{
    NPError rv = NPERR_NO_ERROR;

    NpLog("NPP_SetValue(%p, %p, %p)\n", variable, value);
    if (instance == NULL) {
	NpLog(">>> NPP_SetValue NULL instance\n");
	return NPERR_INVALID_INSTANCE_ERROR;
    }
    return rv;
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_HandleEvent --
 *
 *     Does ...
 *
 * Results:
 *     In this plugin, always 0.
 *
 * Side effects:
 *     None.
 *
 *----------------------------------------------------------------------
 */

int16
NPP_HandleEvent(NPP instance, void* event)
{
    uint16 rv = 0;

    NpLog("NPP_HandleEvent(%p)\n", event);
    if (instance == NULL) {
	NpLog(">>> NPP_HandleEvent NULL instance\n");
	return NPERR_INVALID_INSTANCE_ERROR;
    }
    return rv;
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_GetJavaClass --
 *
 *	Declares which classes we are going to use in the plugin and
 *	returns a pointer to the wrapper class for this plugin.
 *
 * Results:
 *	In this plugin, always NULL.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */
#ifdef OJI
jref
NPP_GetJavaClass()
{
    NpLog("NPP_GetJavaClass()\n");
    return NULL;
}
#endif

/*
 *----------------------------------------------------------------------
 *
 * NpEnter --
 *
 *	Called upon enter of any NPP_ functions to stops Tcl
 *      from servicing its own events.
 *
 * Results:
 *	The old service mode which must be passed to NpLeave
 *
 * Side effects:
 *	Stops Tcl from servicing events. The events are being queued.
 *
 *----------------------------------------------------------------------
 */

int
NpEnter(CONST char *msg)
{
    int oldServiceMode;

    Tcl_MutexLock(&pluginMutex);
    oldServiceMode = Tcl_SetServiceMode(TCL_SERVICE_NONE);
    nptcl_stack++;

    NpLog("ENTERED %s,\toldServiceMode == %d\n\t", msg, oldServiceMode);
    NpLog("[[ STACK = %d, INSTANCES = %d, STREAMS = %d ]]\n",
	    nptcl_stack, nptcl_instances, NpTclStreams(0));

    if (nptcl_shutdown) {
	NpLog("SERIOUS ERROR: called NpEnter while shutdown\n");
    }

    return oldServiceMode;
}

/*
 *----------------------------------------------------------------------
 *
 * NpLeave --
 *
 *      Undo what NpEnter did. To be called before returning to caller
 *      by each NPP_ function.
 *	Potentially unblocks Tcl from servicing its own events.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Queued events might be serviced in the future.
 *
 *----------------------------------------------------------------------
 */

void
NpLeave(CONST char *msg, int oldServiceMode)
{
    if (nptcl_shutdown) {
	NpLog("SERIOUS ERROR: called NpLeave while shutdown\n");
    }

    nptcl_stack--;

    NpLog("LEAVING %s,\toldServiceMode == %d\n\t", msg, oldServiceMode);

    NpLog("[[ STACK = %d, INSTANCES = %d, STREAMS = %d ]]\n",
	    nptcl_stack, nptcl_instances, NpTclStreams(0));

    Tcl_SetServiceMode(oldServiceMode);
    Tcl_MutexUnlock(&pluginMutex);
}

/*
 *----------------------------------------------------------------------
 *
 * NpPanic --
 *
 *	Implementation of panic for the Tcl plugin.
 *
 * Results:
 *	None -- never returns.
 *
 * Side effects:
 *	Terminates the current process.
 *
 *----------------------------------------------------------------------
 */

EXTERN void
NpPanic(char *msg)
{
    NpPlatformMsg(msg, "PANIC");
    abort();
}
