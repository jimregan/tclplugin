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
# Copyright (c) 2002-2004 ActiveState Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# RCS:  @(#) $Id$

# we provide browser functionalities:

package provide setup 1.0

# We require logging (we will initialize it from here):

package require pluglog 1.1

# tkInit : plugin aware Tk will use that proc to initialize themselves
# if it exists and thus will find directly the Tk where it is expected
# without being potentially confused by the TK_LIBRARY env var...

proc tkInit {} {
    global tk_library
    ::pluglog::log {} "direct tkInit! -> $tk_library"
    uplevel #0 [list source [file join $tk_library tk.tcl]]
#   rename tkInit {}
}

# Setup the tkLazyInit :
#
# Our caller should be running in a tcl shell which has Tk available
# for loading through the "package require Tk" command but in which
# Tk is not loaded by default (loading of Tk is delayed until the
# need arises).
#
# To ensure that Tk will be properly loaded when it is needed, the rest of
# the code relies on the existance of a "tkLazyInit" procedure. This loads
# and initializes Tk only if that was not already done (ie. lazily and only
# once).
#
# We define "tkLazyInit" below. We detect whether Tk has been already
# initialized for this executable (if we are running inside a wish for
# instance) and in that case we implement an empty "tkLazyInit" proc.
#
# Nb: "package require Tk" would do almost everything right by itself
# but it insists on creating '.' which we may not need in all cases.
# Then, when we don't need to display anything and don't need '.', we 
# we need to remember to withdraw it etc. All of this is taken care of
# in the definition of tkLazyInit.

if {[info command wm] == "wm"} {
    # Tk is already there, so define an empty lazy init procedure.

    proc tkLazyInit {} {}

    # If no widget have been created, we withdraw the unneeded .

    if {[winfo children .] == ""} {
	wm withdraw .
    }

    # Set our nice name (to be seen by other apps (inspect, tkcon,...))

    tk appname $::Name

} else {
    # No Tk, let's define a tkLazyInit *if* one is not defined already:

    if {[info proc tkLazyInit] == ""} {
	set ::TkInitialized 0;

	proc tkLazyInit {} {
	    if {$::TkInitialized} {
		# already done, nothing to do
		return
	    }
	    ::pluglog::log {} "Actually loading Tk ([info level -1])"
	    # This actually loads / initialize Tk
	    package require Tk 8.0
	    # Withdraw the "." untill someone actually need it
	    wm withdraw .
	    # Set our nice name (to be seen by other apps like inspect, tkcon)
	    tk appname $::Name
	    set ::TkInitialized 1
	}
    }
}


# Setup and eventually start logging facility:

proc SetupLogging {} {
    global env

    if {[info exists env(TCL_PLUGIN_TS)]} {
	proc ::pluglog::TS {} $env(TCL_PLUGIN_TS)
    }

    lappend ::pluglog::attributes SLAVE {-background green -foreground black}

    # Start logging depending on environment vars.
    if {[info exists env(TCL_PLUGIN_LOGFILE)] \
	    && ($env(TCL_PLUGIN_LOGFILE) != 0) } {
	::pluglog::setup $env(TCL_PLUGIN_LOGFILE)
    } elseif {([info exists env(TCL_PLUGIN_LOGWINDOW)]) \
	    && ($env(TCL_PLUGIN_LOGWINDOW) != 0)} {
	# We need Tk for logging to a window :
	tkLazyInit

	::pluglog::setup window "Log: $::Name"
    }
}

# (Eventually) Set up a console if the user wants one:

proc SetupConsole {} {
    global env plugin

    # Create a console if the user asks for it:

    ::pluglog::log {} "Console setup"
    if {[info exists env(TCL_PLUGIN_CONSOLE)] \
	    && ($env(TCL_PLUGIN_CONSOLE) != 0)} {
	if {($env(TCL_PLUGIN_CONSOLE) == 1) || \
		($env(TCL_PLUGIN_CONSOLE) == "")} {
	    set consoleFile [file join $plugin(library) console.tcl]
	} else {
	    set consoleFile $env(TCL_PLUGIN_CONSOLE)
	}
	# Load Tk if not done already:

	tkLazyInit

	if {[catch {uplevel #0 [list source $consoleFile]} msg]} {
	    NotifyError Console\
		    "loading \"$consoleFile\": $msg\n$::errorInfo"
	    return
	}
	::pluglog::log {} "Console file \"$consoleFile\" sourced ok"
    } else {
	::pluglog::log {} "No console created"
    }
}


# Notify user of a critical error:

proc NotifyError {name msg} {

    ::pluglog::log $name $msg ERROR

    # Load tk if not done already:

    tkLazyInit

    # If the main window . is iconified, our message box would not show up
    # (more like a tk bug to have application grab and iconfied dialog)
    # Also sometimes, the window is iconified but wm state returns withdraw!
    # even with an update inserted.... so we explictly check for ".c"...

    if {[wm state .]=="iconic" || [winfo exists .c]} {
	wm deiconify .
    }

    tk_messageBox -icon error -title "Error: $::Name"\
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
