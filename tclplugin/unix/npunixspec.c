/* 
 * npUnixSpecific.c --
 *
 *	This file contains implementations of Unix specific Netscape plugin
 *	APIs. These APIs are not defined on other platforms.
 *
 * CONTACT:		sunscript-plugin@sunscript.sun.com
 *
 * AUTHORS:		Jacob Levy			Laurent Demailly
 *			jyl@eng.sun.com			demailly@eng.sun.com
 *			jyl@tcl-tk.com			L@demailly.com
 *
 * Please contact us directly for questions, comments and enhancements.
 *
 * Copyright (c) 1995 Sun Microsystems, Inc.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npunixspec.c 1.7 97/12/04 10:31:59
 */

#include	"np.h"

/*
 * Static variables used in this file:
 */

static char msgBuf[1024];

/*
 *----------------------------------------------------------------------
 *
 * NPP_GetMIMEDescription --
 *
 *	Called by the Navigator to get a string that describes the MIME
 *	types implemented by the plugin.
 *
 * Results:
 *	A string describing the application/x-tcl MIME type.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

char *
NPP_GetMIMEDescription()
{
    return "application/x-tcl:.tcl:Tcl Web Applets";
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_GetValue --
 *
 *	Called by the Navigator to get the values of informational
 *	variables implemented by the plugin.
 *
 * Results:
 *	The string containing the informational value is returned in an
 *	output parameter, and the function returns a Netscape error code.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

	/* ARGSUSED */
NPError
NPP_GetValue(void *future, NPPVariable variable, void *value)
{
    NPError err = NPERR_NO_ERROR;

    switch (variable) {
        case NPPVpluginNameString:
            sprintf(msgBuf, "Tcl Plugin %s", NPTCL_PATCH_LEVEL);
            *((char **)value) = msgBuf;
            break;
        case NPPVpluginDescriptionString:
            sprintf(msgBuf,
            "Tcl Plugin %s (%s). Executes tclets found in Web pages.\
	     See the <a href=http://sunscript.sun.com/plugin/>Tcl\
	     Plugin</a> home page for more details.",
                    NPTCL_PATCH_LEVEL,
		    NPTCL_INTERNAL_VERSION);
            *((char **)value) = msgBuf;
            break;
        default:
            err = NPERR_GENERIC_ERROR;
    }
    return err;
}

