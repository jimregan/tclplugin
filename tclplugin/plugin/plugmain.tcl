# plugmain.tcl --
#
#   Plugin startup, setup and initialization script.
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
# SCCS: @(#) plugmain.tcl 1.81 97/12/04 13:54:21


# Set our base name (used for error reporting):

set ::Name "InProc Tcl Plugin"

# load the common part of the startup (provides SetupLogging,
# SetupConsole, NotifyError etc...)

package require setup 1.0

# Initialize logging. This will require the log package,
# start it, and make it available globally:

SetupLogging

log {} "Plugin(library) = $plugin(library)"

# We need the safe::loadTk command. However, we don't want to require that
# Tk be initialized just to obtain access to this function, so instead, we 
# add tk_library to the # auto_path to make sure it will be found by unknown.

lappend auto_path $tk_library

log {} "AutoPath = $auto_path"

# Initialiaze the configuration (install time / raw parameters):

SetupConfig

# Compute what directory to use for temporary files:
# If it has not been set already in the config

if {![info exists ::cfg::Tmp]} {

    if {[info exists env(TEMP)]} {
	set ::cfg::Tmp $env(TEMP)
    } elseif {[info exists env(TMP)]} {
	set ::cfg::Tmp $env(TMP)
    } else {
	if {"$tcl_platform(platform)" == "windows"} {
	    set ::cfg::Tmp c:/tmp
	} elseif {"$tcl_platform(platform)" == "macintosh"} {
	    # The Mac always has an env var TEMP_FOLDER.
	    # (dln: never say always, use info exists instead ;-)

	    set ::cfg::Tmp $env(TEMP_FOLDER)
	} else {
	    set username unknown
	    catch {set username $env(LOGNAME)}
	    catch {set username $env(USER)}
	    set ::cfg::Tmp /tmp/$username
	}
    }

    # Export our findings (for remoted).
    set env(TEMP) $::cfg::Tmp
}

if {[catch {file mkdir $env(TEMP)} msg]} {
    log {} "Can't create storage directory: $msg" ERROR
}

# Make note that we are not yet ready (with respect to
# server connect, browser version...)

set plugin(ready) 0
set plugin(uaConf) 0

# This procedure starts a new server and connects to it. It performs
# a handshake with the server to ensure that the server is properly
# started.

proc npInit {} {
    global tcl_platform env plugin tcl_version

    # Check whether we are on a Mac. If so, always run in-process.

    if {"$tcl_platform(platform)" == "macintosh"} {
	inprocInit
	return
    }

    # If the env var TCL_PLUGIN_WISH is set, use it to select a default
    # executable.

    if {[info exists env(TCL_PLUGIN_WISH)]} {
	set wish $env(TCL_PLUGIN_WISH)
    } else {
	# default is now back to not to start the wish
	set wish 0
    }
    if {"$wish" == "0"} {
	inprocInit
	return
    }
    if {("$wish" == "1") || (![file executable $wish])} {
	set wish $::plugin(executable)
	if {![file executable $wish]} {
	    log {} \
		"revert to in-process execution, can't use \"$wish\"" \
		ERROR
	    inprocInit
	    return
	}
    }

    log {} "Will attempt to use \"$wish\""

    # Save the current environment so that we can restore it after init. We
    # set env(TCL_PLUGIN_WISH) but it does not accumulate so we are OK.

    set localEnv [array get env]

    # don't use the same file for the server !
    if {[info exists env(TCL_PLUGIN_LOGFILE)]} {
	set curfname $env(TCL_PLUGIN_LOGFILE);

	# check we have a filename and not a channel:

	if {[catch {fconfigure $curfname}]} {
	    set newfname \
		    "[file rootname $curfname]D[file extension $curfname]"
	    set env(TCL_PLUGIN_LOGFILE) $newfname;
	    log {} "$wish will use file \"$newfname\" for logging" WARNING
	}
    }

    # We are going to try External process:

    package require rpi 1.0;
    set srv [::rpi::newServer 0 localhost]

    if {[catch {NpExec $wish [file join $plugin(library) remoted.tcl] \
	    [::rpi::iget $srv Port]} msg]} {
        log {} "External wish \"$wish\" startup error: $msg - falling back to inprocess" ERROR

	# Restore environement

	array set env $localEnv

	# Shutdown the server

	::rpi::delete $srv;

	# Fall back to inproc

	inprocInit

	return
    }

    # Restore the environment to what it was when we started.

    array set env $localEnv


    # We need to return now and we will complete the initilization
    # at NewInstance time (including the fall back to inproc)

    set plugin(server) $srv;

}

# This procedure determines if the environment variable TCL_PLUGIN_DEBUG is
# set. If so, and we are on Unix, it writes a ~/.gdbinit file and waits for
# the user to start the debugger running on the sub-process. If not, it
# calls exec with the passed arguments.

proc NpExec {executable script port} {
    global env tcl_platform plugin

    # If we are on a Unix box, LD_LIBRARY_PATH needs to be updated to
    # enable the external executable to find its shared libraries.
    #
    # If we are on Windows, likewise update the Path or PATH env var.

    if {"$tcl_platform(platform)" == "unix"} {
	if {[info exists env(LD_LIBRARY_PATH)]} {
	    set env(LD_LIBRARY_PATH) \
		"$plugin(sharedLibraryDir):$env(LD_LIBRARY_PATH)"
	} else {
	    set env(LD_LIBRARY_PATH) $plugin(sharedLibraryDir)
	}
    } elseif {"$tcl_platform(platform)" == "windows"} {
	if {[info exists env(PATH)]} {
	    set env(PATH) "$plugin(sharedLibraryDir);$env(PATH)"
	} elseif {[info exists env(Path)]} {
	    set env(Path) "$plugin(sharedLibraryDir);$env(Path)"
	} else {
	    set env(Path) $plugin(sharedLibraryDir)
	}
    }

    if {([info exists env(TCL_PLUGIN_DEBUG)]) && \
	    ("$tcl_platform(platform)" == "unix")} {
	# This is (not)nicely smashing one's .gdbinit ...
	set fd [open [file join $env(HOME) .gdbinit] w]
	puts $fd "set args $script $port $tclversion"
	puts $fd "exec-file $executable"
	close $fd
	log {} "Not exec'ed but written suitable ~/.gdbinit instead -- start gdb" WARNING;
	return
    }

    log {} "about to exec \"$executable $script $port\""

    set ::WishPid [exec $executable $script $port &]
    log {} "Exec ok (pid $::WishPid)";
}


#
# Netscape -> Plugin APIs :
#
#

# This procedure is called when the plugin stub is shut down:

proc npShutDown {} {

    log {} "Plugin entered npShutDown";

    # Work around Tcl bug where the sockets aren't being (always) closed
    # when we destroy the interp

    if {[info exists ::Cli]} {
	if {[catch {::rpi::delete $::Cli} msg]} {
	    log {} "error deleting client socket ${::Cli}: $msg"
	} else {
	    log {} "sucessfully deleted client socket $::Cli"
	}
    } else {
	log {} "No peer socket to delete"
    }

    # Work around a Tk bug where Tk can try to map a destroyed but never
    # mapped window when the interpreter is deleted.
    # nb: This might kill the current interp (so code after this statement
    #     might never be executed)
    catch {destroy .}

    log {} "Plugin done with npShutDown";
}

#
# Generate generic np* Netscape -> Plugin APIs
#

# the strings API and EXEC will be replaced in the target proc:
set npAPIbody {
    if {![info exists ::id2name($id)]} {
	set msg "called API with unknown instance id \"$id\""
	log {} $msg ERROR;
	return -code error $msg;
    }
    set name $::id2name($id)
    log $name "called API $args" DEBUG;
    if {[catch {EXEC API $name $args} res]} {
	set msg "in API: $res";
	log $name $msg ERROR
	return -code error $msg
    }
}

# Synchronous ones
foreach api {
    NewStream DestroyStream WriteStream
} {
    regsub -all API  $npAPIbody $api body
    regsub -all EXEC $body npExecute body
    # Generic wrapper: generated by substituting the name of the API being
    # called into a standard body.
    proc np$api {id args} $body
}

# Asynchronous ones
foreach api {
    SetWindow 
} {
    regsub -all API  $npAPIbody $api body
    regsub -all EXEC $body npSpawn   body

    # Generic wrapper: generated by substituting the name of the API being
    # called into a standard body.

    proc np$api {id args} $body
}

# Big init completion and synchronisation between instances proc :

proc CompleteInit {name} {
    global plugin

    # Are we already ready ?
    if {$plugin(ready)} {
	return
    }
    log $name "Plugin not ready...";

    # Are we waiting for server connection
    if {[info exists plugin(server)]} {

	set srv $plugin(server);

	set plugin(fallBackToInProc) 0

	# Wait if someone is waiting already

	if {[::wait::wait $name "server ($srv) ack"]==0} {

	    # Wait for the remote process to connect to us
	    set plugin(srvInitDone) 0

	    # set timeout to 10s {for slow machines} (default is 5s)
	    ::rpi::iset $srv timeout 10000

	    if {[catch {::rpi::serverWaitConnect $srv ::Cli} msg]} {
		# We timed out, fall back
		# (NB: We should kill the exec'ed process (using $::WishPid))
		log {} "No connection from external wish received ($msg)\
			falling back to inprocess" ERROR;
		::rpi::delete $srv;
		set plugin(fallBackToInProc) 1
	    } else {
		# We close the listening server (1 connection only)
		::rpi::delete $srv;
		set plugin(ready) 1
		log $name "Marking the plugin as ready (and fully unwinded)";
	    }
	} else {
	    log $name "We've wait so it should be 'almost' ready now\
		    (except for the unwind)";
	    if {![info exists ::Cli]} {
		log $name "Except that we don't have the connection!\
			fall back! to inproc...";
		set plugin(fallBackToInProc) 1
	    }
	}

	# Really complete the init (the first to exit the waits above
	# will do that:)

	if {$plugin(srvInitDone)==0} {
	    set plugin(srvInitDone) 1
	    if {$plugin(fallBackToInProc)} {
		unset plugin(server)
		inprocInit
		CompleteInit $name
		return
	    }
	    log $name "initializing the communication procs"
	    serverInit
	    # setup the available commands based on UserAgent...
	    npExecute ConfigureCommands $name {}
	}

    } else {

	# In Proc case:

	# setup the available commands based on UserAgent...
	npExecute ConfigureCommands $name {}

	set plugin(ready) 1

    }

}

# New instance is special, there is a return value : the
# 'nice' name of the slave that we will use later on
# In fact we generate our name here

set ::TcletId 0

proc npNewInstance {id args} {

    incr ::TcletId;
    set name "tclet$::TcletId";
    if {[info exists ::id2name($id)]} {
	set msg "called NewInstance with id \"$id\" already known!!"
	log {} $msg ERROR;
	return -code error $msg;
    }
    log {} "NewInstance: Assigned name \"$name\" to token \"$id\"";
    set ::id2name($id) $name;
    set ::name2id($name) $id;

    # Complete the initialization
    CompleteInit $name;

    log $name "called npNewInstance $args" DEBUG;
    if {[catch {npExecute NewInstance $name $args} res]} {
	log $name $res ERROR
	return -code error $res
    }
}

proc npDestroyInstance {id args} {
    if {![info exists ::id2name($id)]} {
	set msg "called DestroyInstance with unknown instance id \"$id\""
	log {} $msg ERROR;
	return -code error $msg;
    }
    set name $::id2name($id)
    log $name "called DestroyInstance $args" DEBUG;
    if {[catch {npExecute DestroyInstance $name $args} res]} {
	log $name $res ERROR
	unset ::id2name($id)
	unset ::name2id($name)
	return -code error $res
    }
#    log $name "going to spawn DestroyInstance"
#    npSpawn DestroyInstance $name $args;
#    log $name "done spawn DestroyInstance"

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
	log {} $msg ERROR
	return -code error $msg
    }
    set id $::name2id($name)
    log $name "called API $args" DEBUG
    if {[catch {uplevel #0 pniAPI $id $args} res]} {
	set msg "in API: $res"
	log $name $msg ERROR
	return -code error $msg
    }
    set res
}

foreach api {
    Status GetURL OpenStream WriteToStream CloseStream
    PostURL UserAgent ApiVersion
} {
    regsub -all API $pnAPIbody $api body

    # Generic wrapper: generated by substituting the API being called into
    # a standard body.

    proc pn$api {name args} $body

}


# This sets up the "Execute" and "NpExecute procs which will either do a
# remote evaluation when we use an external wish, or directly evaluate
# the arguments if we are executing in the same process.

proc SetupExecute {inproc} {
    if {$inproc} {
	set ::inprocTk 1
	log {} "configuring npExecute and friends for INPROC"
	# N->P 
	# find the command in the configured implementation namespace
	proc npExecute {cmd name aList} {
	    npEval ${::cfg::implNs}::$cmd $name $aList;
	}
	proc npSpawn {cmd name aList} {
	    npEval ${::cfg::implNs}::$cmd $name $aList;
	}
	proc npEval {cmd name aList} {
	    if {[catch {eval $cmd $name $aList} res]} {
		set ::savedErrorInfo($cmd) $::errorInfo
		return -code error $res
	    }
	    return $res
	}
	# P->N
	proc pnExecute {cmd name aList} {
	    npEval pn$cmd $name $aList;
	}
    } else {
	set ::inprocTk 0
	log {} "configuring npExecute and friends for OUTPROC"
	# N->P   (P->N is on the remoted.tcl side)
	proc npExecute {cmd name aList} {
	    ::rpi::invoke $::Cli "\${cfg::implNs}::$cmd $name $aList"
	}
	proc npSpawn {cmd name aList} {
	    ::rpi::spawn $::Cli "\${cfg::implNs}::$cmd $name $aList"
	}

	# We do not define pnExecute because it is defined in remoted.tcl
	# and the in-process one should never get called.
    }
}

# Only one of the two following function will be called :

# Init for the remote case

proc serverInit {} {
    global plugin

    SetupExecute 0

    SetupConsole

    # Send all this in one chunk, it's much faster.
    # We don't use array set/get as some of the plugin array might be private.
    # We don't send plugin(release) as it's now shared in installed.cfg
    foreach var {
	plugin(version) plugin(pkgVersion) plugin(patchLevel)
    } {
	lappend todo [list set $var [set $var]]
    }
    ::rpi::invoke $::Cli [join $todo \n]
}

# This procedure is called once, at start-up, to initialize the in-process
# Tk server:

proc inprocInit {} {
    SetupExecute 1

    # We are in proc : we need the browser package

    package require browser 1.0

    # Initialize 'browser' (wherever it has been effectively installed)
    # (common inproc/outproc browser specific init)

    ${::cfg::implNs}::init

    log {} "plugin started in-process."
}


# This procedure handles background errors:

proc bgerror {msg} {
    log {} "bgerror $msg ($::errorInfo)" ERROR;
    puts stderr "BgError: $msg\n$::errorInfo"
}

npInit

log {} "pluginmain.tcl initialized."

