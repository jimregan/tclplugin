/*
 * npUnix.c --
 *
 * Netscape Client Plugin API
 * - Wrapper function to interface with the Netscape Navigator
 *
 * Copyright (c) 2002 ActiveState Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS:  @(#) $Id$
 */

#define XP_UNIX 1

#include <stdio.h>
#include "npapi.h"
#include "npupp.h"


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
 * NP_GetMIMEDescription
 *	- Netscape needs to know about this symbol
 *	- Netscape uses the return value to identify when an object instance
 *	  of this plugin should be created.
 */
char *
NP_GetMIMEDescription(void)
{
    return NPP_GetMIMEDescription();
}

/*
 * NP_GetValue [optional]
 *	- Netscape needs to know about this symbol.
 *	- Interfaces with plugin to get values for predefined variables
 *	  that the navigator needs.
 */
NPError
NP_GetValue(void *future, NPPVariable variable, void *value)
{
    return NPP_GetValue(future, variable, value);
}
