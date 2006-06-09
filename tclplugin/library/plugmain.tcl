# plugmain.tcl --
#
#   Plugin startup, setup and initialization script.
#   This is the first script that should be sourced.
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

package require Tcl 8.4
package require Tk 8.4

# we provide plugin functionalities:
# keep in sync with plugin version
package provide plugin 3.1

namespace eval ::plugin {
    # Set our base name (used for error reporting):
    variable NAME "InProc Tcl Plugin"
}

set plugin(library) [file dirname [info script]]

# Allow plugin subdirectories to be recognized for their own packages
if {[lsearch -exact $auto_path $plugin(library)] < 0} {
    lappend auto_path $plugin(library)
}

# load the common part of the startup (provides SetupLogging,
# SetupConsole, NotifyError etc...)
package require plugin::common 1.0

# Initialize logging. This will require the log package,
# start it, and make it available globally:
SetupLogging $::plugin::NAME

# These variables are set by the nptcl dll.  This check is to allow
# simple testing by the user.
if {![info exists plugin(patchLevel)]} {
    puts stderr "WARNING: plugin(patchLevel) not found.\
	\nplugin package is only to be loaded by nptcl library."
    set plugin(patchLevel) TESTING
    set plugin(pkgVersion) TESTING
    set plugin(release)    TESTING
}
::pluglog::log MAIN "PLUGIN(LIBRARY) = $plugin(library)"
::pluglog::log MAIN "PATCHLEVEL      = $plugin(patchLevel)"
::pluglog::log MAIN "PKGVERSION      = $plugin(pkgVersion)"
::pluglog::log MAIN "TCL_PATCHLEVEL  = $tcl_patchLevel"
::pluglog::log MAIN "AUTO_PATH       = $auto_path"
::pluglog::log MAIN "INFO_NOE        = [info nameofexecutable]"
::pluglog::log MAIN "INFO_LIB        = [info library]"

# Initialiaze the configuration (install time / raw parameters):
SetupConfig

::pluglog::log MAIN "PLUGIN(RELEASE) = $plugin(release)"

# Compute what directory to use for temporary files:
# If it has not been set already in the config

if {![info exists ::cfg::Tmp]} {
    if {[info exists env(TEMP)]} {
	set ::cfg::Tmp $env(TEMP)
    } elseif {[info exists env(TMP)]} {
	set ::cfg::Tmp $env(TMP)
    } elseif {[info exists env(TEMP_FOLDER)]} {
	# The Mac has an env var TEMP_FOLDER.
	set ::cfg::Tmp $env(TEMP_FOLDER)
    } elseif {$::tcl_platform(platform) eq "windows"} {
	# should look in registry
	set ::cfg::Tmp c:/tmp
    } else {
	set ::cfg::Tmp /tmp/plugin-$::tcl_platform(user)
    }

    # Export our findings (for remoted).
    set env(TEMP) $::cfg::Tmp
}

if {[catch {file mkdir $env(TEMP)} msg]} {
    ::pluglog::log MAIN "Can't create storage directory: $msg" ERROR
}

# Make note that we are not yet ready (with respect to
# server connect, browser version...)

set plugin(ready) 0

# The primary init proc.  It sees whether we want an external process
# and can create one, otherwise uses (falls back to) inprocess.
proc ::plugin::init {} {
    set code [catch {init_extern} res]
    if {$code} {
	::pluglog::log plugin::init "init_extern error: $res\
		\nfalling back to inproc"
    }
    if {$code || $res == 0} {
	init_inproc
    }
}

# This procedure starts a new server and connects to it. It performs a
# handshake with the server to ensure that the server is properly started.
proc ::plugin::init_extern {} {
    global plugin

    # Run out-of-process by default on Unix only.
    set wish [string equal $::tcl_platform(platform) "unix"]

    # If the env var TCL_PLUGIN_WISH is set, use it to select a default
    # executable.
    if {[info exists ::env(TCL_PLUGIN_WISH)]} {
	set wish $::env(TCL_PLUGIN_WISH)
    }
    if {[string is false -strict $wish]} {
	return 0
    }

    if {[string is true -strict $wish] || ![file executable $wish]} {
	set wish $plugin(executable)
	if {![file executable $wish]} {
	    ::pluglog::log init_extern \
		"revert to in-process execution, can't use \"$wish\"" ERROR
	    return 0
	}
    }
    ::pluglog::log init_extern "Will attempt to use \"$wish\""

    # We are going to try External process:
    package require rpi 1.0
    set srv    [::rpi::newServer 0 localhost]
    set port   [::rpi::iget $srv Port]
    # remoted will require ::argv and ::plugin(library) to be set
    # based off 'info script'.
    set script [file join $plugin(library) remoted.tcl]
    if {[lindex [file system $script] 0] ne "native"} {
	::pluglog::log init_extern "Must copy $plugin(library) to $::cfg::Tmp"
	set targetdir $::cfg::Tmp/[file tail $plugin(library)]
	catch {file delete -force $targetdir}
	file copy $plugin(library) $::cfg::Tmp
	if {$::tcl_platform(platform) eq "unix"} {
	    file attributes $targetdir -permissions u+rwx,go-rwx
	}
	set script [file join $targetdir remoted.tcl]
    }

    # This method would opens a pipe with args that we can still talk to.
    # To work in a fully enclosed environment, we could pass the script
    # over the pipe (set argc/argv/plugin(library) first).
    ::pluglog::log init_extern "Opening pipe to '$wish'"
    if {[catch {set fid [open "|[list $wish] $script -port $port" r+]} msg]} {
	::pluglog::log init_extern "External wish \"$wish\" startup error:\
		\n$msg\nFalling back to inprocess" ERROR
	# Shutdown the server
	::rpi::delete $srv
	return 0
    }
    fconfigure $fid -blocking 0
    set plugin(fid) $fid
    ::pluglog::log init_extern "Opened pipe (fid $fid)"

    # We need to return now and we will complete the initilization
    # at NewInstance time (including the fall back to inproc)
    set plugin(server) $srv

    return 1
}

# This sets up the "Execute" and "NpExecute" procs which will either do a
# remote evaluation when we use an external wish, or directly evaluate
# the arguments if we are executing in the same process.
proc ::plugin::SetupExecute {inproc} {
    if {$inproc} {
	::pluglog::log {} "configuring npExecute and friends for INPROC"
	# N->P
	# find the command in the configured implementation namespace
	proc ::npExecute {cmd name aList} {
	    npEval ${::cfg::implNs}::$cmd $name $aList
	}
	proc ::npSpawn {cmd name aList} {
	    npEval ${::cfg::implNs}::$cmd $name $aList
	}
	proc ::npEval {cmd name aList} {
	    if {[catch {eval [list $cmd $name] $aList} res]} {
		set ::savedErrorInfo($cmd) $::errorInfo
		return -code error $res
	    }
	    return $res
	}
	# P->N
	proc ::pnExecute {cmd name aList} {
	    npEval pn$cmd $name $aList
	}
    } else {
	::pluglog::log {} "configuring npExecute and friends for OUTPROC"
	# N->P   (P->N is on the remoted.tcl side)
	proc ::npExecute {cmd name aList} {
	    ::rpi::invoke $::plugin::CLIENT "\${cfg::implNs}::$cmd $name $aList"
	}
	proc ::npSpawn {cmd name aList} {
	    ::rpi::spawn $::plugin::CLIENT "\${cfg::implNs}::$cmd $name $aList"
	}

	# We do not define pnExecute because it is defined in remoted.tcl
	# and the in-process one should never get called.
    }
}

# Only one of the two following function will be called :

# One-time init for the external process (remote) case
proc ::plugin::init_server {} {
    SetupExecute 0

    SetupConsole

    # Send all this in one chunk, it's much faster.
    # We don't use array set/get as some of the plugin array might be private.
    # We don't send plugin(release) as it's now shared in installed.cfg
    foreach var {
	::plugin(version) ::plugin(pkgVersion) ::plugin(patchLevel)
    } {
	lappend todo [list set $var [set $var]]
    }
    ::rpi::invoke $::plugin::CLIENT [join $todo \n]
}

# One-time init for the in-process (local) case
proc ::plugin::init_inproc {} {
    SetupExecute 1

    # We are in process - we need the browser package
    package require plugin::browser 1.0

    # Initialize 'browser' (wherever it has been effectively installed)
    # (common inproc/outproc browser specific init)

    ${::cfg::implNs}::init

    ::pluglog::log init_inproc "plugin started in-process."
}

# Big init completion and synchronisation between instances proc :
proc ::plugin::init_complete_pipeversion {name} {
    global plugin

    # Are we already ready ?
    if {$plugin(ready)} {
	return
    }
    ::pluglog::log $name "Plugin not ready..."

    if {[info exists plugin(server)]} {
	# External process was established
	set fid $plugin(server)
	if {[catch {eof $fid} eof] || $eof} {
	    # We've lost connection ...
	    ::pluglog::log {} "No connection to external process (EOF $eof).\
			Falling back to inprocess" ERROR
	    # Unset server - it is no longer valid, and init inproc stuff
	    unset plugin(server)
	    ::plugin::init_inproc
	} else {
	    ::pluglog::log $name "Initializing external process communication"
	    ::plugin::init_server
	}
    }
    # setup the available commands based on UserAgent...
    npExecute ConfigureCommands $name {}
    set plugin(ready) 1
}

# Big init completion and synchronisation between instances proc :
proc ::plugin::init_complete {name} {
    global plugin

    # Are we already ready ?
    if {$plugin(ready)} {
	return
    }
    ::pluglog::log $name "Plugin not ready..."

    # Are we waiting for server connection
    if {[info exists plugin(server)]} {
	set srv $plugin(server)

	# Wait for the remote process to connect to us - 5s default timeout
	#::rpi::iset $srv timeout 5000 ; # timeout in msec
	if {[catch {::rpi::serverWaitConnect $srv ::plugin::CLIENT} msg]} {
	    # We timed out, fall back
	    # (NB: We should kill the exec'ed process (using $plugin(pid)))
	    ::pluglog::log {} "No connection to external process: $msg\
			\nFalling back to inprocess" ERROR
	    # Unset server - it is no longer valid, and init inproc stuff
	    unset plugin(server)
	    ::plugin::init_inproc
	} else {
	    ::pluglog::log $name "Initializing external process communication"
	    ::plugin::init_server
	}
	# We close the listening server (1 connection only)
	::rpi::delete $srv
    }
    # setup the available commands based on UserAgent...
    npExecute ConfigureCommands $name {}
    set plugin(ready) 1
}

#
# Netscape -> Plugin APIs :
#
#

# This procedure is called when the plugin stub is shut down:
proc npShutDown {} {
    ::pluglog::log npShutDown "Plugin entered npShutDown"

    # Work around Tcl bug where the sockets aren't being (always) closed
    # when we destroy the interp

    if {[info exists ::plugin::CLIENT]} {
	if {[catch {::rpi::delete $::plugin::CLIENT} msg]} {
	    set msg "error deleting client socket ${::plugin::CLIENT}: $msg"
	} else {
	    set msg "sucessfully deleted client socket $::plugin::CLIENT"
	}
    } else {
	set msg "No peer socket to delete"
    }
    ::pluglog::log npShutDown $msg

    if {0} {
	# [hobbs] - this appears old and no longer necessary for v3.
	# Work around a Tk bug where Tk can try to map a destroyed but never
	# mapped window when the interpreter is deleted.
	# nb: This might kill the current interp (so code after this statement
	#     might never be executed)
	destroy .
    }

    ::pluglog::log npShutDown "Plugin done with npShutDown"
}

#
# Generate generic np* Netscape -> Plugin APIs
#

# the strings API and EXEC will be replaced in the target proc:
set npAPIbody {
    if {![info exists ::id2name($id)]} {
	set msg "called API with unknown instance id \"$id\""
	::pluglog::log {} $msg ERROR
	return -code error $msg
    }
    set name $::id2name($id)
    ::pluglog::log $name "called API $args" DEBUG
    if {[catch {EXEC API $name $args} res]} {
	set msg "in API: $res"
	::pluglog::log $name $msg ERROR
	return -code error $msg
    }
}

# Synchronous ones
foreach api {
    NewStream DestroyStream WriteStream
} {
    # Generic wrapper: generated by substituting the name of the API being
    # called into a standard body.
    proc np$api {id args} \
	[string map [list API $api EXEC npExecute] $npAPIbody]
}

# Asynchronous ones
foreach api {
    SetWindow
} {
    # Generic wrapper: generated by substituting the name of the API being
    # called into a standard body.
    proc np$api {id args} \
	[string map [list API $api EXEC npSpawn] $npAPIbody]
}

# New instance is special, there is a return value : the
# 'nice' name of the slave that we will use later on
# In fact we generate our name here
set ::plugin::TcletId 0
proc npNewInstance {id args} {
    variable ::plugin::TcletId
    incr TcletId
    set name "tclet$TcletId"
    if {[info exists ::id2name($id)]} {
	set msg "called NewInstance with id '$id' already known!"
	::pluglog::log $name $msg ERROR
	return -code error $msg
    }
    ::pluglog::log $name "NewInstance: Assigned name '$name' to token '$id'"
    set ::id2name($id) $name
    set ::name2id($name) $id

    # Complete the initialization
    ::plugin::init_complete $name

    ::pluglog::log $name "called npNewInstance $args" DEBUG
    if {[catch {npExecute NewInstance $name $args} res]} {
	::pluglog::log $name $res ERROR
	return -code error $res
    }
}

proc npDestroyInstance {id args} {
    if {![info exists ::id2name($id)]} {
	set msg "called DestroyInstance with unknown instance id \"$id\""
	::pluglog::log {} $msg ERROR
	return -code error $msg
    }
    set name $::id2name($id)
    ::pluglog::log $name "called DestroyInstance $args" DEBUG
    if {[catch {npExecute DestroyInstance $name $args} res]} {
	::pluglog::log $name $res ERROR
	unset ::id2name($id)
	unset ::name2id($name)
	return -code error $res
    }
#    ::pluglog::log $name "going to spawn DestroyInstance"
#    npSpawn DestroyInstance $name $args
#    ::pluglog::log $name "done spawn DestroyInstance"

    unset ::id2name($id)
    unset ::name2id($name)
}

#
# Plugin -> Netscape APIs:
#
# Also generated:

set pnAPIbody {
    if {![info exists ::name2id($name)]} {
	set msg "called API with unknown name \"$name\""
	::pluglog::log {} $msg ERROR
	return -code error $msg
    }
    set id $::name2id($name)
    ::pluglog::log $name "called API $args" DEBUG
    if {[catch {uplevel #0 pniAPI $id $args} res]} {
	set msg "in API: $res"
	::pluglog::log $name $msg ERROR
	return -code error $msg
    }
    set res
}

foreach api {
    Status GetURL OpenStream WriteToStream CloseStream
    PostURL UserAgent ApiVersion
} {
    # Generic wrapper: generated by substituting the API being called into
    # a standard body.

    proc pn$api {name args} [string map [list API $api] $pnAPIbody]
}


# This procedure handles background errors:
proc bgerror {msg} {
    ::pluglog::log {} "bgerror $msg ($::errorInfo)" ERROR
    puts stderr "BgError: $msg\n$::errorInfo"
}

# Do the plugin initialization
::plugin::init

::pluglog::log MAIN "pluginmain.tcl initialized."

