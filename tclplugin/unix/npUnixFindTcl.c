/* 
 * npUnixFindTcl.c --
 *
 *	Discovers the installed path to a certain libtclX.X(g).so
 *
 * AUTHOR:	David Gravereaux <davygrvy@pobox.com>
 *
 * Copyright (c) 2000 by David Gravereaux and relinquished
 *   to Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS: @(#) $Id$
 */

#include "np.h"

/*
 *-------------------------------------------------------------------------
 *  NpPlatformFindTcl --
 *
 *	Discovers the location of a Tcl core through a combination of current
 *	path followed by a registry search.  Called in a similar manner to
 *	Tcl_PkgRequire().
 *
 *	minVer  -- minimum acceptable version, ex: "8.1".
 *	exact   -- when not zero, indicates that minVer is the only 
 *		   acceptable core wanted.
 *	dbgOnly -- only load the symbol core when not zero.
 *
 *  returns:
 *	a char * that gives the location of the proper libtclX.X(g).so requested.
 *	This char * does not need to be freed by the caller.
 *
 *  bad stuff:
 *	might over-ride development environment and use the installed one
 *	instead.  might have to 'install' libtclX.X(g).so to debug this extension.
 *
 *-------------------------------------------------------------------------
 */

char *
NpPlatformFindTcl
    (char *minVer, int exact, int dbgOnly)
{
    // add code here :)
    return NULL;
}
