# utils.tcl --
#
#	Some general utilities which does not fit anywhere else
#       (used by the Tcl plugin but could be useful anywhere).
#
# Copyright (c) 1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
# Copyright (c) 2002 ActiveState Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# RCS:  @(#) $Id$

# Nb: if the version below is changed to reflect changes in APIs
#     the version number of plugtcl should be changed too because
#     plugtcl 'includes' this package.

package provide tcl::utils 1.0

package require log 1.0

namespace eval ::tcl {
    namespace export autoReset

    # A clean (does not delete some of the defined procs) and
    # complete (remove the unloaded packages infos) version of auto_reset

    proc autoReset {} {
	global auto_execs auto_index auto_oldpath
	catch {unset auto_execs}
	catch {unset auto_index}
	catch {unset auto_oldpath}
	# Remove package information for un-required packages
	foreach pkg [package names] {
	    if {[package provide $pkg]=={}} {
		package forget $pkg
	    }
	}
    }

} ; # end of namespace eval ...

