# remoted.tcl --
#
#   Remote server main/init and specific implementation
#   (common parts in browser.tcl)
#
# CONTACT:	tclplugin-core@lists.sourceforge.net
#
# ORIGINAL AUTHORS:	Jacob Levy		Laurent Demailly
#
# Copyright (c) 1996-1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
# Copyright (c) 2002-2004 ActiveState Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# RCS:  @(#) $Id$

# Called with the following arguments:
# argv[0] == port number to connect to on the local host.

package require Tcl 8.2
package require Tk 8.2

# Set our base name (used for error reporting)
namespace eval ::plugin {
    variable NAME "External Tcl Plugin Server"
}

# Compute plugin(library) from the script being loaded:
set plugin(library) [file dirname [info script]]

# Allow plugin subdirectories to be recognized for their own packages
if {[lsearch -exact $auto_path $plugin(library)] < 0} {
    lappend auto_path $plugin(library)
}

# common Setup
package require plugin::common 1.0

# This procedure is used by commands that execute code in the spawning
# process:
set ::msgNum   0
proc pnExecute {cmd key aList} {
    incr ::msgNum
    ::rpi::invoke $::plugin::CLIENT [concat [list ::pn$cmd $key] $aList]
}

# We redefine bgerror to log messages, because we may not have any
# visible presence.
proc bgerror {msg} {
    ::pluglog::log {} "bgerror $msg ($::errorInfo)" ERROR
    puts stderr "BgError: $msg\n$::errorInfo"
}

proc usage {} {
    puts stderr "usage: -port port -delay delay"
    exit 1
}

# The following procedure initializes the server:
proc remotedInit {args} {
    set host "localhost" ; # don't allow configure on this yet
    set port ""
    set delay 0

    foreach {key val} $args {
	switch -exact -- $key {
	    -port	{ set port $val }
	    -delay	{ set delay $val }
	    default	{ usage }
	}
    }
    if {![string is integer -strict $port]} {
	usage
    }

    SetupLogging $::plugin::NAME

    SetupConfig

    ::pluglog::log {} "AUTO_PATH = $::auto_path"

    # The correct value has been set by our caller:
    if {![info exists ::cfg::Tmp]} {
	set ::cfg::Tmp $::env(TEMP)
    }

    # And we also need the browser package which implements the
    # browser specific stuff:
    package require plugin::browser 1.0

    # Connect to our spawner:
    package require rpi 1.0
    if {$delay} {
	after $delay [list set ::GO 1]
	vwait ::GO
    }
    if {[catch {set ::plugin::CLIENT \
		    [::rpi::newClient $host $port $host]} msg]} {
	puts stderr "FATAL: wishd.tcl: Can not connect back : $msg"
	exit
    }

    # Install our own link down handler
    proc ::rpi::linkDown {args} {
	::pluglog::log {} "LinkDown ($args): bye bye !" WARNING
	set ::Exiting 1
	exit
    }

    # Initialize 'browser' (wherever it has been effectively installed)
    # (common inproc/outproc browser specific init)
    ${::cfg::implNs}::init

}

# Initialize everything:
eval [linsert $argv 0 remotedInit]

::pluglog::log {} "remoted.tcl init done"
