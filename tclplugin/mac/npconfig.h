/*
 * npconfig.h --
 *
 *	Configuration header file for the Macintosh version of Tcl plugin.
 *
 * CONTACT:     sunscript-plugin@sunscript.sun.com
 *
 * Please contact us for questions, comments and enhancements.
 *
 * Copyright (c) 1997 Sun Microsystems, Inc.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npconfig.h 1.8 98/01/15 18:58:40
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
#define NPTCL_VERSION "2.0"
#define NPTCL_PATCH_LEVEL "2.0"
#define NPTCL_INTERNAL_VERSION "2.0.200"
 
#define NPTCL_MAJOR_VERSION 2
#define NPTCL_MINOR_VERSION 0
#define NPTCL_RELEASE_LEVEL 2
#define NPTCL_RELEASE_SERIAL 0

#endif /* _NPCONFIG */

