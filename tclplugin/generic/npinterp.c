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
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npinterp.c 1.10 97/09/26 07:27:38
 */

#include	"np.h"

/*
 * Static variables in this file:
 */

static Tcl_Interp *npInterp = (Tcl_Interp *) NULL;

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

    if (npInterp != NULL) {
        NpPanic("Called CreateInterp when we already have one!");
    }

    npInterp = Tcl_CreateInterp();
    if (npInterp == (Tcl_Interp *) NULL) {
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

