/*
 * npMac.h --
 *
 *	Mac specific #include directives.
 *
 * AUTHOR: Jim Ingham			jim.ingham@eng.sun.com
 *
 * Please contact me directly for questions, comments and enhancements.
 *
 * Copyright (c) 1997 Sun Microsystems, Inc.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npmac.h 1.1 97/12/02 21:40:15
 *
 */

#ifndef _NPMAC
#define _NPMAC

#include "np.h"
#include "npapi.h"

#include	<stdio.h>

#if HAVE_UNISTD_H
#	include <types.h>
#	include <unistd.h>
#endif

#include <tcl.h>
#include <tk.h>
#include <tkInt.h>
#include <tkMacInt.h>
#include <Quickdraw.h>

#define TCL_THREAD_STACK_SIZE (256*1024)

typedef struct PluginInstance {
    NPP plugin;
    NPRect oldClip;
	NPWindow *npWin;
    Tk_Window tkWin;
} PluginInstance;
	
#endif /* _NPMAC */
