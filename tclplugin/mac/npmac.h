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
 * SCCS: @(#) npmac.h 1.2 97/12/16 18:01:58
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

#include <Threads.h>

#define TCL_THREAD_STACK_SIZE (256*1024)

int	NpMacServiceNpScript(void);
void	NpMacWakeUpTclThread(int serviceMode);
void 	NpMacDoACompleteEval(int serviceMode);

EXTERN ThreadID gTclThread;     /* The ThreadID of the Tcl thread */
EXTERN ThreadID gMainThread;    /* The ThreadID of the thread we started in */
	
#endif /* _NPMAC */
