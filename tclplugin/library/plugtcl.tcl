# plugtk.tcl --
#
#	Tool kit utilities for tclets.
#       This is intended to be sourced in each Safe Tcl interp of the Plugin
#
# CONTACT:	sunscript-plugin@sunscript.sun.com
#
# AUTHORS:      Jacob Levy              Laurent Demailly
#               jyl@eng.sun.com         demailly@eng.sun.com
#               jyl@tcl-tk.com          L@demailly.com
#
# Please contact us directly for questions, comments and enhancements.
#
# Copyright (c) 1996-1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# SCCS: @(#) plugtcl.tcl 1.2 97/11/21 18:49:54
# RCS:  @(#) $Id$

package provide plugtcl 1.1

#
# Default error management for Tclets (without Tk, Tk version is in
# plugtk package)
#

proc bgerror {errmsg} {
    global errorInfo
    log "bgerror: $errmsg ($errorInfo)"
}

# This loads misc general purpose utilities
# (must not be lasy loading or the tcl::autoReset call in
#  safetcl unsafe.tcl will fail)

package require tcl::utils 1.0

