/* 
 * tclMiscUtils.c --
 *
 *	This file contains a miscellaneous utilities.
 *
 * Copyright (c) 1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) tclMiscUtils.c 1.4 97/12/01 23:42:39
 * RCS:  @(#) $Id$
 *
 */

#include "tclMiscUtils.h"


/*
 *----------------------------------------------------------------------
 *
 * TclUtils_QuoteObjCmd --
 *
 *	Quotes a Tcl 8.0 binary string such as it contains 
 *      only ascii7 printable characters
 *      the remaining characters being escaped by \ such as
 *      subst [quote $anyString] == $anyString                  (*)
 *	and
 *	eval set a \"[quote $anyString]\" == $anyString
 *
 *      using 'usual' (and shortest) quoting like "\n" for \n 
 *	and smart "A\1B" for 'A','\001','B' while doing "1\0012" for
 *	'1','\001','2'
 *
 *	It also works for C string quoting too.
 *
 *      Note*: when/if subst will be/were binary clean
 *
 * Results:
 *	The quoted string.
 *
 * Side effects:
 *	None
 *
 * Warning:
 *	This will probably be broken by 8.1.
 *
 *----------------------------------------------------------------------
 */

int
TclUtils_QuoteObjCmd (dummy, interp, objc, objv)
    ClientData dummy;		/* Not used. */
    Tcl_Interp *interp;		/* Current interpreter. */
    int objc;			/* Number of arguments. */
    Tcl_Obj *CONST objv[];	/* The argument objects. */
{
    char c,*bytes;
    int  ci, length, i, n;
    unsigned int uc;
    Tcl_Obj *result;
    char buf[4]; /* to hold a 8 bits (0-377) octal number + null */

    if (objc != 2) {
    	Tcl_WrongNumArgs(interp, 1, objv, "string");
	return TCL_ERROR;
    }
    bytes = Tcl_GetStringFromObj(objv[1], &length);
    if (bytes == NULL) {
	Tcl_AppendResult(interp, 
		"argument generated NULL string representation!", 
		(char *) NULL);
	return TCL_ERROR;
    }
    result = Tcl_GetObjResult(interp);
    /*
     * A table would certainly be faster but we want short code
     * and the compiler might eventually be smart enough to generate
     * a sparse table lookup itself ?
     *
     */

    for (i = 0; i < length; i++, bytes++) {
	ci = c = *bytes;
	if (ci > 255 ) {
	    Tcl_ResetResult(interp);
	    Tcl_AppendResult(interp,
		    "argument generated character greater than 255!",
		    (char *) NULL);
	    return TCL_ERROR;
	}
	if (ci < -128 ) {
	    Tcl_ResetResult(interp);
	    Tcl_AppendResult(interp,
		    "argument generated character lower than -128!",
		    (char *) NULL);
	    return TCL_ERROR;
	} 
	uc =  (unsigned int) ( ( ci < 0 ) ? ( (256 + ci) & 0xff ) : ci );
	if ( (c == '\\') || (c == '[') || (c == '$') || (c == '"') ) {
	     Tcl_AppendToObj(result, "\\", 1);
	     Tcl_AppendToObj(result, bytes, 1);
	} else if ( c == '\007') {
	    Tcl_AppendToObj(result, "\\a", 2);
	} else if ( c == '\010') {
	    Tcl_AppendToObj(result, "\\b", 2);
	} else if ( c == '\011' ) {
	    Tcl_AppendToObj(result, "\\t", 2);
	} else if ( c == '\012' ) {
	    Tcl_AppendToObj(result, "\\n", 2);
	} else if ( c == '\013' ) {
	    Tcl_AppendToObj(result, "\\v", 2);
	} else if ( c == '\014' ) {
	    Tcl_AppendToObj(result, "\\f", 2);
	} else if ( c == '\015' ) {
	    Tcl_AppendToObj(result, "\\r", 2);
	} else if ( (uc >= 32) && (uc <128) ) {
	    /* normal character */

	    Tcl_AppendToObj(result, bytes, 1);
	} else {
	    /* high or low bits character */

	    Tcl_AppendToObj(result, "\\", 1);
	    
	    /*
	     * Determine if we can use the short version
	     */
	    if ( uc >= 0100 ) {
		n = 3;
	    } else {
		n = (uc >= 010) ? 2 : 1;
		/*
		 * If we are at the end of the string, we can't use
		 * the short version (someone might append "0" later)
		 */
		if (i+1 == length) {
		    n = 3;
		} else {
		    /*
		     * If the next char is a digit, we can either.
		     */
		    c = *(bytes+1) ;
		    if ( (c >= '0') && (c <= '9') ) {
			n = 3;
		    }
		}
	    }

	    sprintf(buf, "%0*o", n, uc);
	    Tcl_AppendToObj(result, buf, n);
	}
    }
    return TCL_OK;
}


int Tclutils_Init(interp)
    Tcl_Interp *interp; /* The current Tcl interpreter */
{
    Tcl_CreateObjCommand(interp, "::tcl::quote", TclUtils_QuoteObjCmd,
	    NULL, NULL);
    if (Tcl_PkgProvide(interp, "tcl::utils-C", TCLUTILS_VERSION_STRING) 
	    != TCL_OK) {
	return TCL_ERROR;
    }
    return TCL_OK;
}


