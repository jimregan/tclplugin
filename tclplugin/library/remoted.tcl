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

# Set our base name (used for error reporting) if it was not set yet.

if {![info exists ::Name]} {
    set ::Name "External Tcl Plugin Server"
}

# Compute plugin(library) from the script being loaded:

set plugin(library) [file dirname [info script]]
set plugin(topdir)  $plugin(library)

# This procedure is used by commands that execute code in the spawning
# process:
set ::msgNum   0
proc pnExecute {cmd key aList} {
    incr ::msgNum
    ::rpi::invoke $::Cli "::pn$cmd $key $aList"
}

# We redefine bgerror to log messages, because we may not have any
# visible presence.
proc bgerror {msg} {
    ::pluglog::log {} "bgerror $msg ($::errorInfo)" ERROR
    puts stderr "BgError: $msg\n$::errorInfo"
}

# The following procedure initializes the server:
proc remotedInit {} {
    global argc argv env auto_path errorInfo plugin tk_version tk_library

    # Update the auto-path so that we can find other scripts in the plugin
    # library:

    if {[lsearch -exact $auto_path $plugin(topdir)] < 0} {
	lappend auto_path $plugin(topdir)
    }

    # common Setup

    package require setup 1.0

    SetupLogging

    SetupConfig

    # Check that we received the right argument(s):

    if {$argc != 1} {
	NotifyError wishd "wrong # args ($argc): should be\n\
		\"wish wishd.tcl port\""
	exit
    }

    ::pluglog::log {} "AutoPath = $auto_path"

    # The correct value has been set by our caller:
    if {![info exists ::cfg::Tmp]} {
	set ::cfg::Tmp $env(TEMP)
    }

    # And we also need the browser package which implements the
    # browser specific stuff:
    package require browser 1.0

    # Connect to our spawner:
    package require rpi 1.0
    if {[catch {set ::Cli [::rpi::newClient\
	    localhost [lindex $argv 0] localhost]} msg]} {
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
remotedInit

::pluglog::log {} "remoted.tcl init done"
