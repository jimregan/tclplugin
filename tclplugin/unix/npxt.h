/*
 * npxt.h --
 *
 *	Header file for Xt notifier for the plugin.
 *
 * CONTACT:		tclplugin-core@lists.sourceforge.net
 *
 * Copyright (c) 1996-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS:  @(#) $Id$
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
