/* 
 * npUnixPlat.c --
 *
 *	Platform specific routines: Unix version.
 *
 * CONTACT:		tclplugin-core@lists.sourceforge.net
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

#include	"np.h"

/*
 * Static functions used in this file:
 */


/*
 *----------------------------------------------------------------------
 *
 * NpPlatformMsg --
 *
 *	Display a message to the user of the plugin.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Displays a message.
 *
 *----------------------------------------------------------------------
 */

void
NpPlatformMsg(CONST84 char *msg, char *title)
{
    NpLog("MSG [%s]: %s\n", (int) title, (int) msg, 0);
    fprintf(stderr, "MSG [%s]: %s\n", title, msg);
}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformInit --
 *
 *	Initialize the plugin script running inside the plugin Tcl
 *	interpreter.
 *
 * Results:
 *	A standard Tcl result.
 *
 * Side effects:
 *	Whatever the script does.
 *
 *----------------------------------------------------------------------
 */

int
NpPlatformInit(interp, inBrowser)
    Tcl_Interp *interp;
    int inBrowser;
{
    /*
     * We don't require special initialization.  The generic
     * package require plugin should work for us.
     */
    return TCL_OK;
}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformSetWindow --
 *
 *	Make sure that the embeding will work by registering handlers for
 *      the given window.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Set up handlers to propagate the focus into a Tk application,
 *      from outside.
 *
 *----------------------------------------------------------------------
 */

void
NpPlatformSetWindow(NPP instance, NPWindow *npwindow)
{
}

/*
 *----------------------------------------------------------------------
 *
 * NpDestroy --
 *
 *	Forgets the association between this instance pointer and
 *	a container window.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Syncs the X display so that the window is guaranteed to be
 *	destroyed before the call returns. (?)
 *
 *----------------------------------------------------------------------
 */

	/* ARGSUSED */
void
NpPlatformDestroy(instance)
    NPP instance;
{
}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformNew --
 *
 *	Unix specific code to do for each instance: attach the notifier
 *      to instance context
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

void
NpPlatformNew(instance)
    NPP instance;
{
}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformShutdown --
 *
 *	Unlinks the Tk notifier from the external event loop.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

void
NpPlatformShutdown()
{
}
