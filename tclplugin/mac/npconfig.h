/*
 * npconfig.h --
 *
 *	Configuration header file for the Macintosh version of Tcl plugin.
 *
 * CONTACT:     tclplugin-core@lists.sourceforge.net
 *
 * Copyright (c) 1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS:  @(#) $Id$
 */

#ifndef _NPCONFIG
#define _NPCONFIG
 
/*
 * Define PLUGIN_TRACE to have the wrapper functions print
 * messages to stderr whenever they are called.
 */
 
/* #undef PLUGIN_TRACE */
 
/*
 * Define if you have the <unistd.h> header file.
 */
 
#define HAVE_UNISTD_H 1

/*
 * Tcl Plugin version identifiers
 * (the 3 strings are computed from the 4 internal numbers)
 */
#define NPTCL_VERSION "3.0"
#define NPTCL_PATCH_LEVEL "3.0.0.3"
#define NPTCL_INTERNAL_VERSION "3.0.0.3"
 
#define NPTCL_MAJOR_VERSION 3
#define NPTCL_MINOR_VERSION 0
#define NPTCL_RELEASE_LEVEL 0
#define NPTCL_RELEASE_SERIAL 3

#endif /* _NPCONFIG */

