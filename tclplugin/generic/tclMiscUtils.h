/* 
 * tclMiscUtils.h --
 *
 *	header file for miscellaneous utilities.
 *
 * Copyright (c) 1997 Sun Microsystems, Inc.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) tclMiscUtils.h 1.2 97/12/01 22:48:32
 *
 */


#include "tcl.h"

#define TCLUTILS_VERSION_STRING "1.0"

EXTERN int TclUtils_QuoteObjCmd _ANSI_ARGS_((ClientData dummy, 
	Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[]));

EXTERN int Tclutils_Init _ANSI_ARGS_((Tcl_Interp *interp));

#define Tclutils_SafeInit Tclutils_Init

