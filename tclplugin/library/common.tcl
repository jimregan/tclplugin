# common.tcl --
#
#	Plugin main and remoted common parts (setup).
#
# CONTACT:	tclplugin-core@lists.sourceforge.net
#
# ORIGINAL AUTHORS:	Jacob Levy		Laurent Demailly
#
# Copyright (c) 1996-1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
# Copyright (c) 2002-2005 ActiveState Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# RCS:  @(#) $Id$

# we provide browser functionalities:
package provide plugin::common 1.0

# We require logging (we will initialize it from here):
package require pluglog 1.1

# If no widget have been created, we withdraw the unneeded .
if {![llength [winfo children .]]} { wm withdraw . }

# Setup and eventually start logging facility:
proc SetupLogging {name} {
    global env

    lappend ::pluglog::attributes SLAVE {-background green -foreground black}

    # Set our nice name (to be seen by other apps (inspect, tkcon,...))
    tk appname $name

    # Start logging depending on environment vars.
    if {[info exists env(TCL_PLUGIN_LOGFILE)]} {
	::pluglog::setup $env(TCL_PLUGIN_LOGFILE)
    } elseif {[info exists env(TCL_PLUGIN_LOGWINDOW)]
	      && [string is true -strict $env(TCL_PLUGIN_LOGWINDOW)]} {
	::pluglog::setup window "Log: $name"
    }
}

# (Eventually) Set up a console if the user wants one:
proc SetupConsole {} {
    global env plugin

    # Create a console if the user asks for it:
    if {![info exists env(TCL_PLUGIN_CONSOLE)]} {
	::pluglog::log SetupConsole "No plugin console requested"
	return
    }

    if {[string is true $env(TCL_PLUGIN_CONSOLE)]} {
	# true value or "" means use built-in
	set cmd {
	    namespace eval ::tkcon {}
	    set ::tkcon::PRIV(protocol) {tkcon hide}
	    set ::tkcon::OPT(exec) ""
	    source [file join $plugin(library) tkcon.tcl]
	    tkcon show
	}
    } else {
	set cmd [list source $env(TCL_PLUGIN_CONSOLE)]
    }

    # these may not exist
    if {![info exists ::argv]} { set ::argv {}; set ::argc 0 }

    if {[catch {uplevel \#0 $cmd} msg]} {
	NotifyError SetupConsole\
	    "SetupConsole:\n$cmd\n----\n$::errorInfo"
	return
    }
    ::pluglog::log SetupConsole "Successfully create console"
}


# Notify user of a critical error:
proc NotifyError {name msg} {
    ::pluglog::log $name $msg ERROR

    tk_messageBox -icon error -title "Error: $::plugin::NAME"\
	    -message "$name: $msg" -type ok
}

# Configuration setup
proc SetupConfig {} {
    global plugin

    # Initialiaze the configuration (install time / raw parameters):
    package require cfg 1.0

    # one thing the installed.cfg is supposed to do is
    # to set a value for plugin(executable). initialize here it just in case.
    set plugin(executable) {}

    # We will register in the "plugin" slot but we use the semi generated
    # installed.cfg file which will point to the customizable userConfig
    # file (which is supposed to be "plugin" too but in the config/ dir)
    set configFile [file join $plugin(library) installed.cfg]
    if {[catch {::cfg::init "plugin" $configFile} msg]} {
	NotifyError Init "$msg: probable plugin install problem ($configFile)"
    }
    # Now re-init the config with the userConfig
    if {[catch {::cfg::init $::cfg::userConfig} msg]} {
	::pluglog::log {} "$msg: probable plugin configuration problem" ERROR
    }
}
