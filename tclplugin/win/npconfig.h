/*
 * npconfig.h.in --
 *
 *	Configuration header file for Win32 version of Tcl plugin.
 *
 * CONTACT:     plugin@scriptics.com
 *
 * AUTHORS:     Jacob Levy              Laurent Demailly
 *              jyl@eng.sun.com         demailly@eng.sun.com
 *              jyl@tcl-tk.com          L@demailly.com
 *
 * Please contact us directly for questions, comments and enhancements.
 *
 * Copyright (c) 1995-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npconfig.h 1.9 98/01/13 17:49:33
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
#define NPTCL_VERSION "2.1"
#define NPTCL_PATCH_LEVEL "2.1b1"
#define NPTCL_INTERNAL_VERSION "2.1.0"
 
#define NPTCL_MAJOR_VERSION 2
#define NPTCL_MINOR_VERSION 1
#define NPTCL_RELEASE_LEVEL 1
#define NPTCL_RELEASE_SERIAL 1

/*
 * Look for this key in the registry to find the library where the
 * plugin initialization scripts are installed.
 */

#define TCL_PLUGIN_DIR_KEY	"Software\\Scriptics\\Tcl Plugin\\2.1"

#endif /* _NPCONFIG */
