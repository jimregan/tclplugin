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
# Copyright (c) 2002 ActiveState Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# RCS:  @(#) $Id$

# Called with the following arguments:
# argv[0] == port number to connect to on the local host.

package require Tcl 8.0
package require Tk 8.0

# Set our base name (used for error reporting) if it was not set yet.

if {![info exists ::Name]} {
    set ::Name "External Tcl Plugin Server"
}

# Compute plugin(library) from the script being loaded:

set plugin(library) [file dirname [info script]]
set plugin(topdir)  $plugin(library)

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

    if {![string match "*Plugin*" $::tcl_patchLevel]} {
	log {} "Likely failure upcoming because of invalid tcl\
		version: $::tcl_patchLevel" WARNING
    }

    if {![file exists [file join $tk_library safetk.tcl]]} {
	set p $tk_library
	set tk_library [file join $plugin(topdir) $tkdir]
	if {[string compare $p $tk_library] == 0} {
	    set msg "Installation problem: can't find safetk.tcl in \"$p\""
	    log {} $msg ERROR
	    NotifyError "Fatal" $msg
	    exit -1
	}
	log {} "no safetk.tcl in \"$p\", switching to \"$tk_library\"!" WARNING
	if {![file exists [file join $tk_library safetk.tcl]]} {
	    log {} "no safetk.tcl in $tk_library either! aborting" ERROR
	    NotifyError "Fatal" "can't find safetk.tcl in \"$p\"\
		    nor in\ \"$tk_library\" misconfiguration somewhere..."
	    exit -1
	}
    }

    log {} "AutoPath = $auto_path"

    # The correct value has been set by our caller:
    if {![info exists ::cfg::Tmp]} {
	set ::cfg::Tmp $env(TEMP)
    }

    # And we also need the browser package which implements the
    # browser specific stuff:

    package require browser 1.0

    # Connect to our spawner:

    package require rpi 1.0;
    if {[catch {set ::Cli [::rpi::newClient\
	    localhost [lindex $argv 0] localhost]} msg]} {
	puts stderr "FATAL: wishd.tcl: Can not connect back : $msg"
	exit
    }

    # Install our own limk down handler

    proc ::rpi::linkDown {args} {
	log {} "LinkDown ($args): bye bye !" WARNING
	set ::Exiting 1
	exit
    }

    # Initialize 'browser' (wherever it has been effectively installed)
    # (common inproc/outproc browser specific init)

    ${::cfg::implNs}::init

}

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
    log {} "bgerror $msg ($::errorInfo)" ERROR
    puts stderr "BgError: $msg\n$::errorInfo"
}


# Initialize everything:

remotedInit

log {} "remoted.tcl init done"

# Now wait forever (or at least until someone set the ::Exiting variable).

vwait ::Exiting

