# remoted.tcl --
#
#   Remote server main/init and specific implementation
#   (common parts in browser.tcl)
#
# CONTACT:	sunscript-plugin@sunscript.sun.com
#
# AUTHORS:	Jacob Levy		Laurent Demailly
#		jyl@eng.sun.com		demailly@eng.sun.com
#		jyl@tcl-tk.com		L@demailly.com
#
# Please contact us directly for questions, comments and enhancements.
#
# Copyright (c) 1996-1997 Sun Microsystems, Inc.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# SCCS: @(#) remoted.tcl 1.82 98/01/15 14:54:04

# Called with the following arguments:
# argv[0] == port number to connect to on the local host.


# Set our base name (used for error reporting) if it was not set yet.

if {![info exists ::Name]} {
    set ::Name "External Tcl Plugin Server"
}


# The following procedure initializes the server:

proc remotedInit {} {
    global argc argv env auto_path errorInfo plugin tk_version tk_library

    # version checking

    CheckVersions

    # Compute plugin(library) from the script being loaded:

    set plugin(library) [file dirname [info script]]
    set plugin(topdir) [file dirname $plugin(library)]

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
		\"wish wishd.tcl port\"";
	exit
    }

    if {![string match "*Plugin*" $::tcl_patchLevel]} {
	log {} "Likely failure upcoming because of invalid tcl\
		version: $::tcl_patchLevel" WARNING
    }

    # We will need the safe::loadTk command and we don't want to require that
    # Tk is inited just to get this function, so we simply add tk_library 
    # to the auto_path to make sure it will be found:

    if {![info exists tk_library]} {
	set tkdir "tk$tk_version"
	# We use the peer of the tcl library
	set tk_library [file join [file dirname [info library]] $tkdir]
	log {} "will try to use $tk_library for safe tk autoloading..."
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

    lappend auto_path $tk_library

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
	puts stderr "FATAL: wishd.tcl: Can not connect back : $msg";
	exit
    }

    # Install our own limk down handler

    proc ::rpi::linkDown {args} {
	log {} "LinkDown ($args): bye bye !" WARNING;
	set ::Exiting 1
	exit
    }

    # Initialize 'browser' (wherever it has been effectively installed)
    # (common inproc/outproc browser specific init)

    ${::cfg::implNs}::init

}

# This procedure checks that we have the right version of wish to work in:

proc CheckVersions {} {
    global tcl_version tk_version

    if {$tcl_version < 8.0} {
	tkLazyInit
	wm title . "Incorrect version of Tcl/Tk: $tcl_version/$tk_version"
	message .m -aspect 2000 -text "
Your version of Tcl, $tcl_version, is earlier than the required 8.0. I am
unable to use tcl$tcl_version in the external executable for the Tcl
plugin. You need an executable based on tcl8.0 or later. Aborting." 
	button .b -text dismiss -command exit
	pack .m .b;
        wm deiconify .
	vwait forever
    }
}

# This procedure is used by commands that execute code in the spawning
# process:

set ::msgNum   0
proc pnExecute {cmd key aList} {
    incr ::msgNum
    ::rpi::invoke $::Cli "::pn$cmd $key $aList";
}

# We redefine bgerror to log messages, because we may not have any
# visible presence.

proc bgerror {msg} {
    log {} "bgerror $msg ($::errorInfo)" ERROR;
    puts stderr "BgError: $msg\n$::errorInfo"
}


# Initialize everything:

remotedInit

log {} "remoted.tcl init done"

# Now wait forever (or at least until someone set the ::Exiting variable).

vwait ::Exiting

