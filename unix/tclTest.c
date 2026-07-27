/* 
 * tclAppInit.c --
 *
 *	Based on the default version of the main program and Tcl_AppInit
 *	procedure for Tcl applications (without Tk).
 *
 * Copyright (c) 1993 The Regents of the University of California.
 * Copyright (c) 1994-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) tclAppInit.c 1.3 97/09/17 14:12:04
 * RCS:  @(#) $Id$
 */

#include "np.h"

/*
 * The following variable is a special hack that is needed in order for
 * Sun shared libraries to be used for Tcl.
 */

extern int matherr();
int *tclDummyMathPtr = (int *) matherr;



/*
 *----------------------------------------------------------------------
 *
 * main --
 *
 *	This is the main program for the application.
 *
 * Results:
 *	None: Tcl_Main never returns here, so this procedure never
 *	returns either.
 *
 * Side effects:
 *	Whatever the application does.
 *
 *----------------------------------------------------------------------
 */

int
main(argc, argv)
    int argc;			/* Number of command-line arguments. */
    char **argv;		/* Values of command-line arguments. */
{
    Tcl_Interp *interp;

/*************************   round 1  *********************/

    NpStartLog();

    interp = Tcl_CreateInterp();

    Tcl_Preserve((ClientData) interp);


    if (Plug_Init(interp) == TCL_ERROR) {
	return TCL_ERROR;
    }


    Tcl_SetServiceMode(TCL_SERVICE_ALL);


    if (Tcl_Eval(interp, "source foo1.tcl") != TCL_OK) {
	fprintf(stderr, "err1: %s\n", Tcl_GetStringResult(interp));
    }


    Tcl_DeleteInterp(interp);

    Tcl_Release((ClientData) interp);

    Tcl_Finalize();


/*************************   round 2  *********************/



    interp = Tcl_CreateInterp();

    Tcl_Preserve((ClientData) interp);

    if (Plug_Init(interp) == TCL_ERROR) {
	return TCL_ERROR;
    }


    Tcl_SetServiceMode(TCL_SERVICE_ALL);
    if (Tcl_Eval(interp, "source foo2.tcl") != TCL_OK) {
	fprintf(stderr, "err2: %s\n", Tcl_GetStringResult(interp));
    }

    Tcl_DeleteInterp(interp);

    Tcl_Release((ClientData) interp);

    Tcl_Finalize();

    NpStopLog();

}
