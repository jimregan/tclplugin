/*
 * npUnix.h --
 *
 *	Unix specific #include directives.
 *
 * AUTHORS: Jacob Levy			jyl@eng.sun.com
 *					jyl@best.com
 *          Laurent Demailly            demailly@eng.sun.com
 *                                      dl@mail.box.eu.org
 *
 * Please contact us directly for questions, comments and enhancements.
 *
 * Copyright (c) 1996 Sun Microsystems, Inc.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npunix.h 1.7 97/09/29 15:07:55
 *
 */

#ifndef _NPUNIX
#define _NPUNIX

#include	<stdio.h>

#if HAVE_UNISTD_H
#	include <sys/types.h>
#	include <unistd.h>
#endif

/*
 * Shared functions:
 */

EXTERN void		NpXtStopNotifier _ANSI_ARGS_((void));

#endif /* _NPUNIX */
