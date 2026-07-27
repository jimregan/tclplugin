/* 
 * nptcl.c --
 *
 *	Implements the glue between Tcl script and
 *	the plugin stub in the WWW browser.
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
 * SCCS: @(#) nptcl.c 1.75 98/01/15 13:28:42
 * RCS:  @(#) $Id$
 */

#include	"np.h"
#include "tclMiscUtils.h"
/*
 * Stack counter
 */
static int stack = 0;
static int instances = 0;
static int shutdown = 0;

int streams = 0;

#ifdef USE_TK_STUBS
#undef Tk_Init
#define Tk_Init PnTkInit
#undef Tk_SafeInit
#define Tk_SafeInit PnTkSafeInit
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
NpEnter(msg)
    CONST char *msg;
{
    int oldServiceMode = Tcl_SetServiceMode(TCL_SERVICE_NONE);
    stack++;

    NpLog("Entered %s, old serviceMode == %d (all=%d)\n",
          (int)msg, oldServiceMode, TCL_SERVICE_ALL);
    NpLog("Stack=%d, instance = %d, streams =%d\n", stack, instances, streams);
    if (shutdown) {
	NpLog("SERIOUS ERROR: called NpEnter while shutdown\n", 0, 0, 0);
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
 *	Potentially unblocks Tcl from servicing its own events. We set
 *	the Tcl behavior to what it was before the matching call to
 *	NpSuspendEvents. If the new mode is TCL_SERVICE_ALL, we must also
 *	schedule a timer to ensure that Tcl will get a chance to service
 *	any events it queued and deferred.
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
NpLeave(msg, oldServiceMode)
    CONST char *msg;
    int oldServiceMode;
{
    NpLog("Leaving %s, old serviceMode == %d (all=%d)\n",
          (int)msg, oldServiceMode, TCL_SERVICE_ALL);

    NpLog("Stack=%d, instance = %d, streams =%d\n", stack, instances, streams);

    if (shutdown) {
	NpLog("SERIOUS ERROR: called NpLeave while shutdown\n", 0, 0, 0);
    }

    Tcl_SetServiceMode(oldServiceMode);

    stack--;
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

void
NpPanic(msg)
    char *msg;
{
    NpPlatformMsg(msg, "PANIC");
    abort();
}

/*
 *----------------------------------------------------------------------
 *
 * Plug_Init --
 *
 *	Sets the plugin version strings and library and sets Tcl/Tk
 *      library path accordingly. Also adds utility commands to the interp.
 *
 * Results:
 *	A standard Tcl result.
 *
 * Side effects:
 *
 *----------------------------------------------------------------------
 */

int
Plug_Init(interp, externalFlag)
    Tcl_Interp *interp;
    int externalFlag;
{
    /* This script sets the tcl and tk library relative to the plugin(library)
     * to ensure 'our' version is used whatever the external setting are.
     * It also sources the init.tcl (replacement for the Tcl_Init() call)
     * and workaround the fact that env(TK_LIBRARY) overrides anything the
     * C side could try to set. It also sets env(TCL_LIBRARY) for the same
     * reason and for use of foreign 'external' wish.
     * UPDATE: We stop doing that in order to support user's external
     *         wish which might need other things. The downside is that
     *         we have more workarounds to putback in plugmain.tcl and
     *         remoted.tcl
     */
    static char initScript[] ="global plugin tcl_library tk_library\n\
#  Get the parent of all the dirs:\n\
set plugin(topdir) [file dirname $plugin(library)]\n\
set tcl_library [file join $plugin(topdir) \"tcl\"]\n\
#  Prevent init.tcl from adding random (build time) paths to the auto_path\n\
catch {unset tcl_pkgPath}\n\
# source the 'right' init.tcl\n\
source [file join $tcl_library init.tcl]\n\
#  Export this tcl_library through our env() so the\n\
#  remote process will eventually get it.\n\
#set env(TCL_LIBRARY) $tcl_library\n\
#  Update the auto_path so that we can find other scripts in\n\
#  sub directories of $plugin(topdir) by auto-loading:\n\
lappend auto_path $plugin(topdir)\n\
#  Tk:\n\
set tk_library [file join $plugin(topdir) \"tk\"]\n\
#  Export this tk_library through our env() so the\n\
#  remote process will eventually get it and work around Tk_Init\n\
#  'feature' of preferring then env var over anything.\n\
#set env(TK_LIBRARY) $tk_library\n\
#  Make package require Tk work:\n\
package ifneeded Tk $tk_version {load {} Tk}";
    /*
     * Set the plugin versions and patchLevel.
     */

    Tcl_SetVar2(interp, "plugin", "version", NPTCL_VERSION, TCL_GLOBAL_ONLY);
    Tcl_SetVar2(interp, "plugin", "patchLevel", NPTCL_PATCH_LEVEL,
            TCL_GLOBAL_ONLY);
    Tcl_SetVar2(interp, "plugin", "pkgVersion", NPTCL_INTERNAL_VERSION,
            TCL_GLOBAL_ONLY);

    /*
     * Allow our interp to load Tk on demand
     * Pitfall: We must pass NULL as the first argument or loading in this
     *          interp will not do anything !
     */

    Tcl_StaticPackage(NULL, "Tk", Tk_Init, Tk_SafeInit);
    Tcl_SetVar(interp, "tk_version", TK_VERSION, TCL_GLOBAL_ONLY);

    /*
     * Add some generic C side utilities
     */
    Tcl_StaticPackage(NULL, "tcl::utils-C", Tclutils_Init, Tclutils_SafeInit);

    /*
     * Perform platform specific initialization: 
     *    finding and setting the plugin(dir)
     */

    if (NpPlatformInit(interp, externalFlag) != TCL_OK) {
	NpPlatformMsg(Tcl_GetStringResult(interp),
		"Plug_Init (platform init)");
        return TCL_ERROR;
    }

    if (Np_Eval(interp, initScript) != TCL_OK) {
	NpPlatformMsg(Tcl_GetStringResult(interp),
		"Plug_Init (initScript)");
        return TCL_ERROR;
    }

    return TCL_OK;
}

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
NpInit(interp)
    Tcl_Interp *interp;
{
#ifdef MAC_TCL
    char command[] = "source -rsrc plugmain.tcl";
#else
    char command[] = "source [file join $plugin(library) plugmain.tcl]";
#endif
    
    /*
     * Install hash tables for instance tokens and stream tokens.
     */

    NpInitTokenTables(interp);
   
    /* 
     * We do not call Tcl_Init because the only thing it does is find
     * and source init.tcl and set $tcl_library. This is done by our
     * replacement code: Plug_Init.
     */

    /*
     * Common part of the initialization whether in netscape or as
     * tclshp
     */

    if (Plug_Init(interp, 1 /* inBrowser */ ) != TCL_OK) {
	/* Error reporting has been done already */
	return TCL_ERROR;
    }

    /*
     * Initialize the Plugin->Netscape interface commands.
     * These are commands that can be invoked from the plugin
     * to perform special operations on the hosting browser:
     * (To call the NPN_... APIs)
     */

    if (PnInit(interp) != TCL_OK) {
        NpPlatformMsg(Tcl_GetStringResult(interp), "NpInit (Pn functions)");
        return TCL_ERROR;
    } else {
        Tcl_StaticPackage(interp, "pni", PnInit, PnSafeInit);
    }

    /*
     * Call to tcl side script to finish the initialization:
     */

    if (Np_Eval(interp, command) != TCL_OK) {
        NpPlatformMsg(Tcl_GetVar(interp,"errorInfo",TCL_GLOBAL_ONLY), 
		"NpInit (eval plugmain.tcl)");
        return TCL_ERROR;
    }
    
    return TCL_OK;
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
NpShutdown(interp)
    Tcl_Interp *interp;
{
    char command[] = "npShutDown";

    (void) Np_Eval(interp, command);

    /*
     * Remove the token tables.
     */

    NpDeleteTokenTables(interp);
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

jref
NPP_GetJavaClass()
{
    NpLog("NPP_GetJavaClass()\n", 0, 0, 0);
    return NULL;
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
    Tcl_Interp *interp ;

    NpStartLog(NP_LOG_FILENAME);

    if (shutdown) {
	NpLog("WARNING: we were not unloaded after shutdown\n",
		0 , 0, 0);
    }

    NpLog("Entering NPP_Initialize (%d %d %d)\n", stack, instances, streams);
    shutdown = 0;

    interp = NpCreateMainInterp();
    
    stack = 0;
    instances = 0;
    streams = 0;

    /*
     * We need to service all events for initilization and
     * so that when matching calls to NpSuspendEvents/NpRestoreEvents 
     * happen, the final mode will again be TCL_SERVICE_ALL.
     */

    Tcl_SetServiceMode(TCL_SERVICE_ALL);

    /*
     * We rely on NpInit to inform the user if initialization failed.
     */

    NpLog("before NpInit\n", 0, 0, 0);

    if (NpInit(interp) != TCL_OK) {
	return NPERR_GENERIC_ERROR;
    }


    NpLog("Done with NPP_Initialize\n", 0, 0, 0);
    return NPERR_NO_ERROR;
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
	NpLog("Old service mode is not TCL_SERVICE_ALL!\n",
		0, 0, 0);
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
    
    if (stack != 0) {
	NpLog("SERIOUS ERROR (potential crash): Invalid shutdown stack = %d\n",
		stack, 0, 0);
    }
    if (instances != 0) {
	NpLog("ERROR Invalid shutdown instances count = %d\n", instances,
		0 , 0);
    }
    if (streams != 0) {
	NpLog("ERROR Invalid shutdown streams count = %d\n", streams,
		0 , 0);
    }

    shutdown = 1;

    NpLog("Exiting shutdown\n",0 ,0 , 0);

/* 
   NpStopLog();
 */
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
NPP_New(NPMIMEType pluginType, NPP This, uint16 mode, int16 argc,
	char *argn[], char *argv[], NPSavedData *savedPtr)
{
    Tcl_Interp *interp;
    Tcl_DString ds;
    int i;
    int oldServiceMode;

    if (shutdown) {
	NPP_Initialize();
	NpLog("WARNING: we had to call Initialize from NPP_New\n", 
		0 , 0, 0);
    }

    oldServiceMode= NpEnter("NPP_New");
    
    instances++;

    /*
     * Platform specific initialization. 
     * On unix it will start the notifier in the context of that instance.
     */

    NpPlatformNew(This);

    /*
     * Ensure that This->pdata has a distinguished uninitialized (NULL)
     * value.
     */

    This->pdata = (void *) NULL;

    /*
     * Get the main interpreter.
     */
    
    interp = NpGetMainInterp();
    
    /*
     * Register this instance of the Tcl plugin.
     */
    
    NpRegisterToken((ClientData) This, interp, NPTCL_INSTANCE);

    
    Tcl_DStringInit(&ds);
    Tcl_DStringAppendElement(&ds, "npNewInstance");
    Tcl_DStringAppendElement(&ds,
            NpGetTokenName((ClientData) This, interp, NPTCL_INSTANCE));
    Tcl_DStringStartSublist(&ds);
    for (i = 0; i < argc; i++) {
        Tcl_DStringAppendElement(&ds, argn[i]);
        Tcl_DStringAppendElement(&ds, argv[i]);
    }
    Tcl_DStringAppendElement(&ds, "embed_mode");
    switch (mode) {
        case NP_EMBED:
            Tcl_DStringAppendElement(&ds, "embed");
            break;
        case NP_FULL:
            Tcl_DStringAppendElement(&ds, "full");
            break;
        default:
	    Tcl_DStringAppendElement(&ds, "hidden");
	    NpLog("Undefined mode (%d) in NPP_New, assuming 'hidden'\n",
		    mode, 0, 0);
            break;
    }
    Tcl_DStringEndSublist(&ds);

    if (Np_Eval(interp, Tcl_DStringValue(&ds)) != TCL_OK) {
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

    Tcl_DStringFree(&ds);
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
NPP_Destroy(This, savePtrPtr)
    NPP This;
    NPSavedData **savePtrPtr;
{
    Tcl_Interp  *interp;
    Tcl_DString ds;
    int oldServiceMode = NpEnter("NPP_Destroy");

    interp = NpGetMainInterp();

    /*
     * Tell Tcl that we are destroying this instance:
     */
    
    Tcl_DStringInit(&ds);
    Tcl_DStringAppendElement(&ds, "npDestroyInstance");
    Tcl_DStringAppendElement(&ds,
            NpGetTokenName((ClientData) This, interp, NPTCL_INSTANCE));

    if (Np_Eval(interp, Tcl_DStringValue(&ds)) != TCL_OK) {
        NpPlatformMsg(Tcl_GetStringResult(interp), "npDestroyInstance");
    }

    Tcl_DStringFree(&ds);

    /*
     * Forget the association between this container and the instance
     * pointer (or whatever NpPlatformSetWindow could have done) :
     */

    NpPlatformDestroy(This);

    NpUnregisterToken(interp,
            NpGetTokenName((ClientData) This, interp, NPTCL_INSTANCE),
            NPTCL_INSTANCE);


    instances--;
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
NPP_SetWindow(This, window)
    NPP This;
    NPWindow *window;
{
    Tcl_DString ds;
    char buf[256];
    Tcl_Interp *interp;
    int oldServiceMode = NpEnter("NPP_SetWindow");

    interp = NpGetMainInterp();

    if (window == NULL) {
	NpLog(">>> NPP_SetWindow (%p) called with NULL NPWindow\n", (int)This,
		0, 0);
    } else {
	NpLog("*** NPP_SetWindow this %p npwindow %p npwin->window %p\n",
		(int) This, (int) window, (int) window->window);

	if (window->window == NULL) {
	    NpLog(">>> Ignoring NPP_SetWindow with NULL window (%d x %d)\n",
		    (int)window->width, (int)window->height, 0);
	} else {
	    NpLog("*** NPP_SetWindow Size %d x %d\n", 
		    (int)window->width, (int)window->height, 0);

	    /*
	     * Call platform specific call which will remember that 
	     * this window is a container for the supplied instance
	     * pointer and eventually deal with the focus, etc... :
	     */

	    NpPlatformSetWindow(This, window);

	    /*
	     * Now tell the tcl side about this new container window:
	     */
    
	    Tcl_DStringInit(&ds);
	    Tcl_DStringAppendElement(&ds, "npSetWindow");
	    Tcl_DStringAppendElement(&ds,
		    NpGetTokenName((ClientData) This, interp, NPTCL_INSTANCE));
	    sprintf(buf, " 0x%x %d %d %d %d %d %d %d %d",
		    (int) window->window,
		    (int) window->x, (int) window->y,
		    (int) window->width, (int) window->height,
		    (int) window->clipRect.top, (int) window->clipRect.left,
		    (int) window->clipRect.bottom,
		    (int) window->clipRect.right);
	    Tcl_DStringAppend(&ds, buf, -1);

	    if (Np_Eval(interp, Tcl_DStringValue(&ds)) != TCL_OK) {
		NpPlatformMsg(Tcl_GetStringResult(interp), "npSetWindow");
		Tcl_DStringFree(&ds);
		NpLeave("NPP_SetWindow err", oldServiceMode);
		return NPERR_GENERIC_ERROR;    
	    }
	    Tcl_DStringFree(&ds);
	}
    }
    NpLeave("NPP_SetWindow ok", oldServiceMode);
    return NPERR_NO_ERROR;
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
