/*
 * npxt.h --
 *
 *	Header file for Xt notifier for the plugin.
 *
 * CONTACT:		sunscript-plugin@sunscript.sun.com
 *
 * AUTHORS:		Jacob Levy			Laurent Demailly
 *			jyl@eng.sun.com			demailly@eng.sun.com
 *			jyl@tcl-tk.com			L@demailly.com
 *
 * Please contact us directly for questions, comments and enhancements.
 *
 * Copyright (c) 1996-1997 Sun Microsystems, Inc.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npxt.h 1.4 97/09/26 07:25:46
 *
 */

#ifndef _NPXT
#define _NPXT

/*
 * External functions used in this file, and which are not declared in
 * tcl.h or tk.h.
 */

#include <X11/Intrinsic.h>

EXTERN XtAppContext		NpPlatformSetAppContext _ANSI_ARGS_((
				    XtAppContext appContext,
				    XtInputMask inputMask));

#endif /* _NPXT */
