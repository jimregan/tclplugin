/*
 * npVersion.h --
 *
 *	Defines the global version identifiers for use throughout the sources.
 *
 * Copyright (c) 1996-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS:  @(#) $Id$
 */

#ifndef _NPVERSION
#define _NPVERSION

#ifndef _TCL
#define RESOURCE_INCLUDED
#include <tcl.h>
#endif


#define NPTCL_HOMEPAGE	"http://dev.scriptics.com/software/plugin/"

#define NPTCL_MAJOR_VERSION 2
#define NPTCL_MINOR_VERSION 2
#define NPTCL_RELEASE_LEVEL TCL_ALPHA_RELEASE
#define NPTCL_RELEASE_SERIAL 1



/* no need to edit below here */

#define NPTCL_VERSION \
	STRINGIFY(JOIN(NPTCL_MAJOR_VERSION, JOIN(., NPTCL_MINOR_VERSION)))

#if	NPTCL_RELEASE_LEVEL == TCL_ALPHA_RELEASE
#	define NPTCL_PATCH_LEVEL \
		STRINGIFY( \
			JOIN(JOIN(NPTCL_MAJOR_VERSION, \
			JOIN(., NPTCL_MINOR_VERSION)), \
			JOIN(a, NPTCL_RELEASE_SERIAL)))

#elif	NPTCL_RELEASE_LEVEL == TCL_BETA_RELEASE
#	define NPTCL_PATCH_LEVEL \
		STRINGIFY( \
			JOIN(JOIN(NPTCL_MAJOR_VERSION, \
			JOIN(., NPTCL_MINOR_VERSION)), \
			JOIN(b, NPTCL_RELEASE_SERIAL)))

#elif	NPTCL_RELEASE_LEVEL == TCL_FINAL_RELEASE
#	define NPTCL_PATCH_LEVEL \
		STRINGIFY( \
			JOIN(JOIN(NPTCL_MAJOR_VERSION, \
			JOIN(., NPTCL_MINOR_VERSION)), \
			JOIN(., NPTCL_RELEASE_SERIAL)))

#else
#	error "bad release level"
#endif


#endif  /* #ifndef _NPVERSION */
