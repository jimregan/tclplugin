# browser.tcl --
#
#	Application specific implementation of the APIs,
#	Tcl Plugin implementation.
#
# CONTACT:      tclplugin-core@lists.sourceforge.net
#
# ORIGINAL AUTHORS:      Jacob Levy              Laurent Demailly
#
# Copyright (c) 1996-1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
# Copyright (c) 2002 ActiveState Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# RCS:  @(#) $Id$

# we provide browser functionalities:

package provide browser 1.0

# We require logging
package require log 1.0

# we need url parsing tools:
package require url 1.0

# we need the (v)wait package:
package require wait 1.1

# we need error handling from policy (and safe base loading):
# (v1.2 of policies imply at least 1.1 of safefeature which includes
#  checkArgs)

package require policy 1.3

# We need the base64 logo
package require plugin::logo 1.0

# We use misc utilities
package require tcl::utils 1.0

# Note: the code below is separated into sections and might
#       be split into separate files at some point for additional
#       clarity. meanwhile, please pay attention to the sections.

# The config mechanism (cfg::) is supposed to be initialized
# before this package is required. ::cfg::implNs must be defined

namespace eval $::cfg::implNs {

    # used features
    namespace import ::safe::error ::log::log ::safe::interpAlias

    # exported APIs. We export the "private" APIs ISet and IUnset for
    # sub-packages of this package.

    namespace export iget iexists ISet IUnset

    # default url fetching timeout

    variable timeout 120000

    # private Idle tasks list

    variable IdleTasks {}

    # flag to prevent IdleTasks processing

    variable DontDoIdle 0

    # State variables for each slave are internally stored as arrays
    # called "S${slave}", only the following 5 functions should
    # access those arrays directly:
    
    # Public function to check if a given state attribute is available

    proc iexists {slave attribute} {
	variable S${slave}
	info exists S${slave}($attribute)
    }

    # Public function to get state informations

    proc iget {slave attribute} {
	variable S${slave}
	if {[info exists S${slave}($attribute)]} {
	    set S${slave}($attribute)
	} else {
	    error "unknown attribute $attribute"
	}
    }

    # Private functions/shortcuts to change state informations

    proc ISet {slave attribute value} {
	variable S${slave}
	set S${slave}($attribute) $value
    }

    proc IAppend {slave attribute data} {
	variable S${slave}
	append S${slave}($attribute) $data
    }

    proc ILappend {slave attribute elem} {
	variable S${slave}
	lappend S${slave}($attribute) $elem
    }

    proc IIncr {slave attribute {value 1}} {
	variable S${slave}
	incr S${slave}($attribute) $value
    }

    proc IUnset {slave args} {
	variable S${slave}
	# if no args are givens, it means destroy everything
	if {[llength $args] == 0} {
	    unset S${slave}
	} else {
	    foreach attribute $args {
		unset S${slave}($attribute)
	    }
	}
    }

    # End of functions that can access directly the slave's state.

    ### Aliases directly provided to the tclet by the plugin implementation ###

    # The list of the attributes that the slave can access is kept
    # in the safeAttributes variable defined in installed.cfg

    # The alias that the slave will use to get controlled access to the state:

    proc IGetAlias {slave {attribute ""}} {
	if {[string equal "" $attribute]} {
	    # everything is wanted
	    set res {}
	    foreach attribute $::cfg::safeAttributes {
		if {[iexists $slave $attribute]} {
		    lappend res $attribute [iget $slave $attribute]
		}
	    }
	    return $res
	} else {
	    if {[lsearch -exact $::cfg::safeAttributes $attribute] >= 0} {
		return [iget $slave $attribute]
	    } else {
		error "illegal attribute \"$attribute\""
	    }
	}
    }

    # The alias that the slave will use to tell something to the master
    # (essentially for debugging purpose)

    proc LogAlias {slave args} {
	# remove all special chars
	set str [join $args]
	regsub -nocase -all "\[^ -~\]+" $str {_} str
	log $slave $str "SLAVE"
    }

    # This alias let the slave use the safe part of the "wm" command
    # (this should eventually move into tk's safetk.tcl)
    # We don't allow setting of options (like geometry), just querying

    proc WmAlias {slave args} {
	set allowedList {geometry state withdraw deiconify}
	if {[llength $args] != 2} {
	    error "wrong # args: should be \"wm option window\""
	}
	set option [lindex $args 0]
	set window [lindex $args 1]
	set usage "should be one of [join $allowedList ", "]."
	return [::safe::invokeAndLog $slave wm\
		[::safefeature::checkArgs $allowedList $usage $option 0]\
		$window]
    }

    ######### START of Tcl side implementation of NPP_ APIs ########

    #
    # Start of code section that implements the tcl side of NPP_'s api
    #

    # Because of the way the hosting browser API is set
    # We have a 3 steps initialization
    #    1+ New Instance : create the interps, install basic
    #       features in it and return it's name
    #    2+ New Window   : assign a (new) window to the interp
    #       (thus load tk in it) {this corresponds to the first
    #        SetWindow from the hosting browser}
    #    3+ New Code   : attach information about the tclet
    #       into it and start the tclet. 
    #       {this is first NewStream+WriteStream+DestroyStream}
    #

    #
    # Instance Handling functions
    #

    proc NewInstance {name args} {
	global plugin
	variable apiVersion
	variable userAgent
	
	# Create the interpreter for this instance and enable the package
	# and policy mechanism:

	# We reduce the accessPath to a known limited safe set
	# (note that if we loadTk in the interp, tk_library
	#  will be added too)
	# If one needs to add more to this path,
	# it can easily do it with safe::interpAddToAccessPath
	# during siteSafeInit stage
	# Note that we need to call ::safe::AddSubDirs to reproduce
	# safe tcl's behavior
	set name [::safe::interpCreate $name -accessPath\
		[::safe::AddSubDirs [list $::tcl_library $::plugin(topdir)]]]

	# Install the policy mechanism
	# (this will also install aliases and hide some potentially
	#  dangerous commands)

	::safe::installPolicy $name

	# install the "iget" mechanism for the slave

	interpAlias $name getattr [namespace current]::IGetAlias

	# install the "log" mechanism for the slave
	# (we don't use interpAlias to avoid double logging)

	interp alias $name log {} [namespace current]::LogAlias $name

	# Remember we've not seen a stream for this tclet so far
	# (the first one ought to be the tclet src=)

	ISet $name gotFirstStream 0

	# We have 2 things that might prevent us from
	# starting the tclet at some point :
	#   + we haven't received the originURL yet
	#   + we haven't received the window yet (and Tk is needed)
	# so we set "waiting" to 2 initially, we decrement it when
	# the above are met (in any order) {using DecrWaiting}
	# and when it does to 0, the tclet is 'run' {by DecrWaiting}:

	ISet $name waiting 2

	# Initialize the flag telling if the logo has been installed
	# (and thus needs to be removed before launching the tclet)

	ISet $name hasLogo 0

	# Install the arguments

	installArgs $name $args

	# Set version variables into the Tclet.

	# transfer 'benign' part of the plugin() array :
	foreach part {version patchLevel release} {
	    interp eval $name [list set plugin($part) $plugin($part)]
	}

	# Set a package version, so a Tclet can do
	# package require plugin 2.0.3
	# and be sure to run with a version newer than a given release.

	interp eval $name [list package provide plugin $plugin(pkgVersion)]

	# Try to load site specific stuff into the new slave interpreter. 
	# This hook can be used to initialize the slave interpreter with Tix,
	# Incr Tcl etc etc.
	# siteSafeInit must have been defined when we called "siteInit"
	# or before (no auto-loading).

	if {[info commands siteSafeInit] == "siteSafeInit"} {
	    # If an error occur we don't do anything special beside logging
	    # it, the "siteSafeInit" has to handle it as they wish.
	    if {[catch {siteSafeInit $name [iget $name browserArgs]} msg]} {
		log $name "siteSafeInit error : $msg" ERROR
	    }
	}

	# Set the userAgent and apiVersion for access by the slave
	ISet $name userAgent $userAgent
	ISet $name apiVersion $apiVersion

	log $name "New Instance initialized"
	
	if {[iexists $name Script]} {
	    # We must set the origin, but we must also return to our caller
	    # so we do that in "after idle"

	    # Prevent anyone else from changing it
	    ISet $name originURL {WAITING}

	    AddToScript $name [iget $name Script]

	    AddIdleTask [list SetPageOrigin $name]
	}

	# When time will permit, load some utilities in the slave
	# (like the non GUI version of bgerror (which will be overridden
	#  if we load tk by the plugtk package))

        BgSpawn $name 1 {package require plugtcl 1.1}

	# If we will not use Tk, we don't have to wait for the window
	# and this might eventually trigger the script above
	# (if we had the originURL)

	if {![iget $name Tk]} {
	    DecrWaiting $name
	}

	return $name
    }

    # Called to destroy an instance (and it's interp, state,...) :

    proc DestroyInstance {name} {
	log $name "entering DestroyInstance"

	# Remove wait handlers associated with this Tclet:

	# TO BE DONE

	# Remove the window

	# Destroy the slave interpreter:

	if {[catch {::safe::interpDelete $name} msg]} {
	    log $name "Destroy of slave \"$name\" failed: $msg" ERROR
	}

	# Discard all the information associated with the destroyed
	# Tclet:

	if {[catch {IUnset $name} msg]} {
	    log $name "No state left to unset: $msg" WARNING
	}

	log $name "done with DestroyInstance"
    }

    #
    # Window Handling functions
    #

    # This procedure is called to assign a window to the new instance.

    proc SetWindow {name win x y width height \
	    cliptop clipleft clipbottom clipright} {

	if {![iexists $name Tk]} {
	    error "invalid interp \"$name\""
	}

	if {![iget $name Tk]} {
	    log $name "Ignoring SetWindow (non-Tk applet)"
	    return
	}

	log $name [info level 0] NOTICE

	set winGeom ${width}x${height}

	# Check if we already have a window for that Tclet.

	if {[iexists $name window]} {
	    # Check if the window is the same.

	    set oldwin [iget $name window]
	    if {![string equal $oldwin $win]} {
		# On Unix (at least) Netscape (specially NS3)
		# tend to "change" the X window sometimes
		# (particularly when you resize but sometimes at
		#  early stages of page loading too :/)
		# Ideally we should reparent Tk's . to that new window
		# or, as this is not currently possible with Tk's embedding
		# start a new interpreter and transfer the tclet there
		# (the tclet would need to use the persistent storage to
		# save it's state in that case, by binding on .'s destruction)
		# but that would mean transferring the complicated startup
		# state in the master too. Difficult with the current
		# implementation. To be solved later.
		log $name "Window changed: used to be $oldwin, now $win\
			(probable tk destruction problem upcoming)" WARNING
	    }

	    # Check if something actually changed

	    if {[string equal [iget $name windowGeometry] $winGeom]} {
		log $name "Bogus setWindow with nothing new ?"
	    } else {
		# This is a resize event:
		ResizeWindow $name $win $winGeom $x $y $width $height \
		    $cliptop $clipleft $clipbottom $clipright
	    }
	} else {
	    NewWindow $name $win $winGeom $x $y $width $height \
		$cliptop $clipleft $clipbottom $clipright
	}

	return
    }

    # Virtual Window 'resize' event

    proc ResizeWindow {name win winGeom x y width height ct cl cb cr} {
	# This *should* be handled by embedding but
	# apparently is not (yet?).

	log $name [info level 0] NOTICE
	ISet $name windowGeometry $winGeom
	ISet $name completeWindowGeometry \
	    [list $x $y $width $height $ct $cl $cb $cr]
	ISet $name width $width
	ISet $name height $height

	# We can't assume that "wm" will be hidden. It may have been
	# re-exposed by a security policy.

	if {[lsearch -exact [interp hidden $name] wm] >= 0} {
	    interp invokehidden $name wm geometry . $winGeom
	} else {
	    if {[catch {interp eval $name wm geometry . $winGeom} msg]} {
		log $name "Changing the geometry in the slave: $msg" ERROR
	    }
	}

	# Only update the embed_args if there are no values for width
	# and height. In the other cases the Tclet can use winfo geometry.
	# -- commented out until proved necessary
	
#	foreach v {height width} {
#	    if {![iexists $name ${v}Set]} {
#		ISet $name ${v}Set [set $v]
#		if {[catch {interp eval $name\
#			[list set embed_args($v) [set $v]]} msg]} {
#		    log $name "Could not set embed_args($v) : $msg" WARNING
#		} else {
#		    log $name "Successfully set embed_args($v) to [set $v]"
#		}
#	    }
#	}

    }

    # Virtual New Window event
    # (actually it might be that the window was first
    #  destroyed and then a new one is given...)

    proc NewWindow {name win geom x y w h ct cl cb cr} {
	
	# Prevent idle tasks processing
	variable DontDoIdle 1

	log $name [info level 0] NOTICE

	# If we had a window before for this interp,
	# The browser is probably trying to resize us the hard way,
	# unfortunately Tk will not reload a second time... (yet)
	# {In fact tk should survive the deletion of . and only
	#  go away when we explicitly ask it to, *or* it should
	#  be reloadable several times (but that's less efficient)}

	if {[iexists $name windowGeometry]} {
	    log $name "We had a window before and reloading\
		    tk will most probably fail now..." WARNING
	}

	ISet $name window $win

	# Nb: the 'main' made sure that we will find safe::loadTk
	# (by adding tk_library to the auto_path)

	if {[catch {::safe::loadTk $name -use $win} msg]} {
	    # The load failed, if another try is made later, it will
	    # probably just crash (verified on Unix) so we kill
	    # the interp
	    set msg "Tk load failed: $msg (-> destroying $name)"
	    log $name "Tk load failed: $msg" ERROR
	    IUnset $name window
	    if {[catch {DestroyInstance $name} err]} {
		log $name "failed to destroy instance after Tk load failure:\
			$err" ERROR
	    }
	    set DontDoIdle 0
	    return -code error $msg
	}

	log $name "loaded Tk" NOTICE

	# Set the font scaling to 1.0 has it has no meaning in the plugin
	# context where things are expressed in pixels and not in points

	if {[catch {interp invokehidden $name tk scaling 1.0} err]} {
	    log $name "NewWindow invokehidden tk scaling: $err" ERROR
	    if {[catch {interp eval $name tk scaling 1.0} err]} {
		log $name "NewWindow tk scaling: $err" ERROR
	    }
	}

	# Set the appname

	if {[catch {interp invokehidden $name tk appname $name} err]} {
	    log $name "NewWindow invokehidden tk appname: $err" ERROR
	    if {[catch {interp eval $name tk appname $name} err]} {
		log $name "NewWindow tk appname: $err" ERROR
	    }
	}

	# Set up the "wm" alias

	interpAlias $name wm [namespace current]::WmAlias

	# Set the window size so Tk and the container have the same notion:

	ResizeWindow $name $win $geom $x $y $w $h $ct $cl $cb $cr

        # Make the size stay the same (by default):

        interp eval $name {pack propagate . false}

	# If we don't have a script ready to run
	# we install our 'please wait'/'logo'

	if {(![iexists $name Script]) && (![iexists $name script])} {

	    log $name "window script not ready : putting the banner on"

	    # Remember we did something (so we undo before launching tclet)
	    ISet $name hasLogo 1

	    # Show the logo and tell the user that something is going on
	    # (loading). We will remove this UI before evaluating the Tclet
	    # code. We leave the tclplogo image/data on purpose so that the
	    # can use it too if it wants to.
	    # The event management/timing here is tricky.

	    interp eval $name {
		frame .logo
		label .logo.l1 -text "Tclet loading"
		label .logo.l2 -text "Please Wait..." 
		pack .logo.l2 .logo.l1 -side bottom
	    }
	    if {($w >= $::plugin::logo(width)) \
		    && ($h >= $::plugin::logo(height))} {
		interp eval $name [list image create photo TclpLogo \
			-format gif -data $::plugin::logo(data)]
		interp eval $name { pack [label .logo.i -image TclpLogo] }
	    }
	    interp eval $name {
		grid .logo
		update idletasks
	    }
	}

	# Restore the ability to process idle tasks

	set DontDoIdle 0

	# We will load basic (tk) utilities like the (graphical)
	# (bg)error handler:

        BgSpawn $name 1 {package require plugtk 1.0}

	# This will eventually schedule the start the tclet if it has a script
	# already ready. This must be done after the above so the (bg)error
	# handler is installed first.

	DecrWaiting $name
    }


    #
    # Stream Handling functions
    #

    proc NewStream {name stream url mimetype lastModified size} {
	# We still canonicalize the url so we can use string compare
	# safely.

	set canonicalURL [::url::canonic $url]

	# Do we know about this stream?
	#
	# BUG: This does not work for redirections, as Netscape does
	# not tell us about the original URL when we get called
	# instead, the URL will be the redirected one and we will not
	# find the stream.

	if {[iexists $name stream,handler:$canonicalURL]} {

	    # Yes: this stream is being sent because of a previous
	    # request to fetch the content of the url.

	    set handlersList [iget $name stream,handler:$canonicalURL]
	    IUnset $name stream,handler:$canonicalURL

	    # We should really keep some list of open  and link them
	    # with "wait" tokens, this is needed for the TIMEOUT proper
	    # handling. better handling later.

	    ISet $name openUrl:$canonicalURL $stream

	    ISet $name stream,$stream,writeHandler [lindex $handlersList 1]
	    ISet $name stream,$stream,endHandler   [lindex $handlersList 2]

	    set newHandler [lindex $handlersList 0]
	    if {![string equal $newHandler {}]} {
		eval $newHandler \
		     [list $name $stream $url $mimetype $lastModified $size]
	    }
	} else {

	    # No: so this should be first stream ever for this tclet 
	    # which contains the tcl code to be executed.
	    # We thus register a special callback for it.

	    if {![iexists $name gotFirstStream]} {
		log $name "Unknown Instance for this stream !" ERROR
		error "Unknown Instance $name  for this stream $stream ($url)!"
	    }

	    if {![iget $name gotFirstStream]} {

		ISet $name gotFirstStream 1

		ISet $name stream,$stream,writeHandler {}
		ISet $name stream,$stream,endHandler   EvalInTclet

		# Store properties of the Tclet's url
		# if this hasn't been done already
		# (ie:. if no script= tags have been specified)

		if {![iexists $name originURL]} {
		    InitState $name $url
		}

	    } else {

		# NOTE (TBD):
		#
		# If we are expecting only one url at that point
		# we could guess that it's the one we expect
		# even if the url is different (probably because
		# of a redirect).

		set msg "Unexpected stream $stream \"$url\" ($canonicalURL)"
		log $name $msg ERROR

		# Lets not annoy the user, it could be just a timeout
		
		#return -code error "$name: $msg"
		return "$name: $msg"
	    }
	}

	# Store the meta information known about the stream.

	ISet $name stream,$stream,lastModified $lastModified
	ISet $name stream,$stream,size $size
	ISet $name stream,$stream,url $canonicalURL
	ISet $name stream,$stream,mimetype $mimetype

	# Ensure that the data is recorded as empty initially for the
	# stream so that the end-of-stream handler can return an empty
	# data item.

	ISet $name stream,$stream,data {}

	log $name "New stream $stream $url ($canonicalURL) $size bytes" NOTICE

	return "ok"
    }

    # The following procedure writes a chunk of data to a stream:

    proc WriteStream {name stream length chunk} {
	log $name "$length additional bytes received for $stream"

	if {![iexists $name stream,$stream,writeHandler]} {
	    log $name "unknown stream $stream while writing" ERROR
	    return
	}

	IAppend $name stream,$stream,data $chunk
	log $name "stored data for $stream in stream,$stream,data attr"

	set handler [iget $name stream,$stream,writeHandler]

	if {![string equal $handler ""]} {
	    log $name \
		"evaling write handler $handler $name $stream $length $chunk"
	    eval $handler [list $name $stream $length $chunk]
	}
    }

    # DestroyStream, means we can actually process the stream:

    proc DestroyStream {name stream reason} {
	log $name "destroy stream ($reason) $stream"

	if {![iexists $name stream,$stream,endHandler]} {
	    log $name "unknown stream $stream at end" ERROR
	    return
	}
	    
	set handler [iget $name stream,$stream,endHandler]
	if {[iexists $name stream,$stream,data]} {
	    set data [iget $name stream,$stream,data]
	} else {
	    log $name "$stream has no data"
	    set data {}
	}

	# Remove from the openUrl:$url
	# (before calling the handler, to avoid possible recursion)

	if {[iexists $name stream,$stream,url]} {
	    set url [iget $name stream,$stream,url]
	    log $name "stream $stream has url $url"
	    if {[iexists $name openUrl:$url]} {
		set s [iget $name openUrl:$url]
		if {$s == $stream} {
		    log $name "removing stream $stream from openUrl list"
		    IUnset $name openUrl:$url
		} else {
		    log $name "streamm mismatch same url for $s and $stream"\
			    WARNING
		}
	    } else {
		log $name "but url $url is not in openUrls (ok for src='s url)"
	    }
	} else {
	    log $name "stream $stream has no url !"
	}

	if {![string equal $handler ""]} {
	    # Catch so we do the cleanup even it it fails
	    # and we don't annoy the user
	    if {[catch {eval $handler\
		    [list $name $stream $reason $data]} msg]} {
		log $name "error in end handler $handler $stream $reason:\
			$msg" ERROR
	    }
	} else {
	    log $name "Unhandled End of stream $stream: $reason" WARNING
	}


	# It's possible that some fields have not been set, because the
	# stream was registered from openStream, so we catch around trying
	# to unset them: 

	foreach field {
	    writeHandler endHandler
	    lastModified size url mimetype
	} {
	    if {[catch {IUnset $name stream,$stream,$field} msg]} {
		log $name "stream $stream had no $field"
	    }
	}
    }

    ######### END of Tcl side implementation of NPP_ APIs ########

    #
    # Other/General functions
    #

    # This procedure is called once we know the URL for the instance,
    # to store information about the originating URL and the originating
    # host from which the Tclet was loaded.

    proc InitState {name originURL} {

	# Check that we are not setting it twice or changing it

	if {[iexists $name originURL]} {
	    set msg "Trying to change the originURL (to $originURL)\
		    while it has been set already (to [iget $name originURL])"
	    log $name $msg SECURITY
	    error $msg
	}

	# raw version "as is"

	ISet $name rawOriginURL $originURL

	if {[string equal $originURL ""]} {
	    # Empty URL == UNKNOWN
	    foreach var {URL Proto Host Port Path Key HomeDirURL SocketHost} {
		# We intentionally put a space in here so the field
		# gets all the chances to be invalid if used anywhere
		ISet $name origin$var "UNKNOWN $var"
	    }
	} else {
	    # parsed/canonical version

	    foreach var {Proto Host Port Path Key}\
		    val [::url::parse $originURL] {
		set $var $val
		ISet $name origin$var $val
	    }

	    # Recreate the canonical URL:

	    set canonicalURL [::url::format $Proto $Host $Port $Path $Key]
	    ISet $name originURL $canonicalURL
	    log $name "originURL set to \"$originURL\""

	    # Save the home url (directory) of the tclet
	    
	    ISet $name originHomeDirURL [::url::join $canonicalURL ./]

	    # We compute what host to use in socket requests with special
	    # handling for "file:" URLs that have no specified host.

	    if {[string equal $Proto "file"] && [string equal $Host ""]} {
		ISet $name originSocketHost localhost
	    } else {
		ISet $name originSocketHost $Host
	    }
	}

	# We have the origin url, cool, lets eventually schedule the 
	# tclet launch then

	DecrWaiting $name
    }

    # This procedure embodies the common part of initialization which
    # is done in the same manner whether we are in-proc or in an
    # external wish:

    proc init {} {
	global plugin tcl_platform

	# We need to initialize the policy mechanism
	# (which in turns will use our provided "iget",...)
	
	::safe::initPolicies

	# If we are on Unix, try to load the '~/.tclpluginrc'
	# Otherwise read 'tclplugin.rc' from the plugin library.
	
	if {$tcl_platform(platform) == "unix"} {
	    set fname "~/.tclpluginrc"
	} else {
	    set fname [file join $plugin(library) "tclplugin.rc"]
	}
	if {[file exists $fname] \
		&& [catch {uplevel #0 [list source $fname]} msg]} {
	    log INIT "error sourcing $fname: $msg" ERROR
	}

	# Try to load site specific stuff into the main interpreter. This
	# hook can be used to initialize the main interpreter with Tix,
	# Incr Tcl etc etc. The siteInit procedure should be found via
        # auto-loading.
	#
	# NOTE: We do this after potentially loading '.tclpluginrc' to let
	# system wide settings override private ones. This should not be
	# construed as a security feature because .tclpluginrc can change
	# where we find siteInit, among other things..

	if {[catch {uplevel #0 siteInit} msg]} {
	    log INIT "siteInit failed ($msg)" WARNING
	}

	SetupConsole
    }


    proc SetPageOrigin {name} {
	log $name "called SetPageOrigin"

	# We must set the origin. We use the javascript trick to get the
	# page url; if it fails we call InitState with empty which
	# will safely fill the credentials with "UNKNOWNs".

	# If javascript is disabled our call back will never be called
	# and we won't get an error ! so we put a timeout and store it
	# in our 'lock'

	ISet $name originURL [list WAITING\
		[after 3000 [list [namespace current]::DonePageOrigin\
		$name none "GetURL javascript timeout (disabled?)" {}]]]

	if {[catch {GetURL $name "javascript:location.href" notused notused\
		{} {} [namespace current]::DonePageOrigin} msg]} {
	    DonePageOrigin $name none "GetURL javascript error:$msg" {}
	}
    }

    proc DonePageOrigin {name stream reason data} {
	
	# Done:

	# Remove the timeout handler

	set id [iget $name originURL]
	after cancel [lindex $id 1]

	# Remove the 'lock' on originURL

	IUnset $name originURL

	if {[string equal $reason "EOF"]} {
	    log $name "got page source url ($stream): \"$data\""
	    InitState $name $data
	} else {
	    log $name "can't get page source url ($stream): $reason" WARNING
	    InitState $name {}
	}
	
	if {[iexists $name ToLaunch]} {
	    log $name "will start tclet!"
	    LaunchTclet $name {}
	}
    }

    # Called by NewInstance to set and parse the arguments

    proc installArgs {name arguments} {
	# Save raw arguments:

	ISet $name browserRawArgs $arguments

	# Default value
	ISet $name Tk 1

	# Html tags are case insensitive, so make sure the names for
	# the tags are all in lower case:

	foreach {tag value} $arguments {
	    set ntag [string tolower $tag]
	    set narg($ntag) $value
	    # The "script=" tag is special, it eventually replaces
	    # the src= tag
	    switch -exact -- $ntag {
		"script" {
		    ISet $name Script $value
		    # Nb: as we will use this script, we must thus set the
		    # "origin" of this tclet to the page and not to
		    # whatever the stream origin would be for instance.
		    # This is done at the end of NewInstance.
		}
		"tk" {
		    log $name "tk specified ($value)" DEBUG
		    ISet $name Tk [string is true -strict $value]
		}
		"hidden" {
		    log $name "hidden specified ($value)" DEBUG
		    ISet $name Tk 0
		}
	    }
	    # Special handling for height and width for backward compatibility
	    # (used in ResizeWindow)   - removed until proved necessary.
#	    foreach v {height width} {
#		if {[string equal $ntag $v]} {
#		    ISet $name ${v}Set $value
#		    break
#		}
#	    }
	}
	
	set narglst [array get narg]

	# Save the processed args:

	ISet $name browserArgs $narglst

	# The Tclet should really use "getattr browserArgs" to get the
	# arguments but for backward compatibility we install them in the array
	# embed_args. This name is kept even though it is not style guide
	# compliant, for backwards compatibility:

	interp eval $name [list array set embed_args $narglst]

    }


    # Get the user agent (represents the embedding browser version etc.)
    # and decide, based on that, whether to disable some of the
    # commands.  
   
    proc ConfigureCommands {name} {
	global plugin
	variable userAgent
	variable apiVersion
	
	set userAgent [pnExecute UserAgent $name {}]
	set vl [pnExecute ApiVersion $name {}]

	# We only use the first two elements of the list, which are the
	# version numbers of the Netscape->plugin side. The other two are
	# the version numbers of the plugin->Netscape side of the API.

	set apiVersion [lindex $vl 0].[lindex $vl 1]

	log $name "set [namespace current]::userAgent=($userAgent)"

	# Disable advanced commands if the container browser does not
	# support them. Currently we know that Microsoft Internet Explorer
	# does not provide full support.

	switch -glob -- $userAgent {
	    "Microsoft Internet Explorer*" {
		DisableCommands $userAgent
	    }
	    default {}
	}
    
    }

    # Disable commands that do not work properly in some browsers:

    proc DisableCommands {ua} {
	foreach cmd {openStream writeToStream closeStream GetURL PostURL} {
	    log {} "Disabling command $cmd for $ua"
	    proc $cmd {name args} [list error "$cmd is disabled in $ua"]
	}
    }


    ######## 'Tasks' management utility functions ########

    # Background wrapper for logging and to avoid spurious
    # bgerror when evaluating in slave:

    # if direct is 1 : we directly execute code
    #           is 0 : we execute tclet code wrapped around bgerror checking

    proc BgEval {name direct cmd} {
	# Prevent idle tasks processing
	variable DontDoIdle 1

	log $name "Actually Executing code in tclet"
	if {$direct} {
	    set expr $cmd
	} else {
	    # First remove what we've eventually put at "NewWindow" time
	    if {[iget $name hasLogo]} {
		ISet $name hasLogo 0
		if {[catch {interp eval $name {destroy .l}} msg]} {
		    log $name "removing splash screen failure (tk destroyed) :\
			    $msg" ERROR
		}
	    }
	    # We workaround non binary cleaness of after and try to
	    # use our installed bgerror.
	    set expr {set plugin(ret) [}
	    append expr [list catch\
		    [list uplevel #0 [LfConvert $cmd]] plugin(res)]
	    # only launch the error console if there is really an 
	    # "error" (=1) return code
	    append expr {]; if {$plugin(ret)==1} {bgerror $plugin(res)};}
	    # still, we return what we got.
	    append expr {return -code $plugin(ret)\
			     -errorinfo $::errorInfo $plugin(res)}
	}
	set ret [catch {interp eval $name $expr} res]
	if {$ret} {
	    log $name "Slave eval ($direct) return code $ret ($cmd): $res"\
		    ERROR
	} else {
	    log $name "Done Executing tclet code: $res"
	}
 	set DontDoIdle 0
    }

    # Will evaluate "cmd" in the slave when idle:

    proc BgSpawn {name direct cmd} {
	AddIdleTask [list BgEval $name $direct $cmd]
    }

    # Work around after idle non binary cleanness wrappers 
    # And "task management"

    proc AddIdleTask {cmd {first 0}} {
	variable IdleTasks
	set l [llength $IdleTasks]
	if {$first} {
	    log IDLE "Inserting \"$cmd\" first in IdleTasks list ($l)"
	    # (nb: works for empty list only with tcl8.0p1)
	    set IdleTasks [lreplace $IdleTasks 0 -1 $cmd]
	} else {
	    log IDLE "Appending \"$cmd\" to IdleTasks list ($l)"
	    lappend IdleTasks $cmd
	}
	after idle [namespace current]::DoIdle
    }

    proc DoIdle {} {
	variable IdleTasks
	variable DontDoIdle
	set l [llength $IdleTasks]
	if {$l <= 0} {
	    log IDLE "Called DoIdle with empty IdleTasks list !" ERROR
	    set DontDoIdle 0
	} else {
	    if {$DontDoIdle} {
		log IDLE "*** Can't do Idle now, postponing ($DontDoIdle)"
		if {[incr DontDoIdle]>200} {
		    # this should never happen...
		    set IdleTasks {}
		    set msg "BUG tight event loop or missing\
			    'set DontDoIdle 0': removing all idle tasks"
		    log IDLE $msg ERROR
		    NotifyError DoIdle $msg
		    return
		}		
		# We can not just after idle because all idle tasks
		# are processed now and we would go into a tight loop
		after 0 [list after idle [namespace current]::DoIdle]
		return
	    }
	    set cmd [lindex $IdleTasks 0]
	    set IdleTasks [lrange $IdleTasks 1 end]
	    # Eval it here 
	    # (could be namespace eval [namespace current] but we don't need 
	    #  really that context)
	    log IDLE "Idle task ($l): \"$cmd\""
	    eval $cmd
	}
    }


    # If the waiting counter is 0 or less, actually launch the
    # code :

    proc EventuallyLaunch {name} {
	if {[iget $name waiting] <=0} {
	    # Reset the counter to 0 so we don't go too far in negative
	    # if called again later:
	    ISet $name waiting 0
	    if {[iexists $name ToLaunch]} {
		# What we have to do :
		set script [iget $name ToLaunch]
		# This part is for recording the total script for
		# later authentification/signature purposes for instance
		# and so we know if we need to install the logo/please wait
		if {[iexists $name script]} {
		    IAppend $name script "\n$script"
		} else {
		    ISet $name script $script
		}
		# Remove 'ToLaunch' content so we don't evaluate things twice
		IUnset $name ToLaunch
		# Prepare for launch (when idle)
		log $name "actually scheduling the tclet launch now"
		BgSpawn $name 0 $script
	    } else {
		log $name "would launch the tclet, but nothing to launch now!"
	    }
	} else {
	    log $name "not yet ready to go ([iget $name waiting] to go)"
	}
    }

    # Decrement the ref counting of tasks we are still waiting 
    # completion, if it reaches 0 then actually launch the tclet:

    proc DecrWaiting {name} {
	log $name "decrementing the waiting counter ([iget $name waiting])"
	IIncr $name waiting -1
	EventuallyLaunch $name
    }

    # Add to the code to launch whenever possible
    # and record everything which has been evaluated in the tclet :

    proc AddToScript {name script} {
	# Record what we have to do when ready
	IAppend $name ToLaunch "$script\n"
    }

    # Start a tclet coming from a stream:

    proc EvalInTclet {name stream reason data} {
	if {[string equal $reason "EOF"]} {
	    if {[string length $data] == 0} {
		NotifyError $name "document [iget $name originURL]\
			contains no data"
		return
	    }
	    AddToScript $name $data
	    EventuallyLaunch $name
	} else {
	    log $name "Tclet code's stream $stream ended with reason $reason"\
		    ERROR
	}
    }

    # Binary clean line feed conversion. We unfortunately need this
    # because the Tcl core currently breaks if we give it a line like
    # '\'+'<white spaces>'+'<newline>'. This will not work for everything
    # (ie if you have binary data with "\r" inside they will be changed).

    proc LfConvert {str} {
	return [string map [list "\r\n" "\n" "\r" "\n"] $str]
    }

    #### Url fetching/posting (for the url feature) utility/helper functions:

    # This procedure does the actual work of fetching the URL:

    proc GetURL {name url notusedData notusedFromFile \
		 newCallBack writeCallBack endCallBack} {
	if {[iexists $name stream,handler:$url]} {
	    error "not supported: multiple pending requests for same URL\
		    ($url)"
	}
	
	ISet $name stream,handler:$url \
		[list $newCallBack $writeCallBack $endCallBack]

	pnExecute GetURL $name [list $url]
    }

    # This procedure does the actual work of posting to a URL:

    proc PostURL {name url data fromFile \
		  newCallBack writeCallBack endCallBack} {
	if {[iexists $name stream,handler:$url]} {
	    error "not supported: multiple pending requests for same URL\
		    ($url)"
	}
	
	ISet $name stream,handler:$url \
		[list $newCallBack $writeCallBack $endCallBack]

	pnExecute PostURL $name [list $url {} $data $fromFile]
    }

    # Those helper functions should move to some cgi package

    # Encode name/value pairs
    # based on http2.0's FormatQuery and dl's cgi hacks

    proc EncodeAll {listOfArgs} {
	set res {}
	set sep ""
	foreach arg $listOfArgs {
	    append res $sep [EncodeOne $arg]
	    if {[string equal $sep "="]} {
		set sep &
	    } else {
		set sep =
	    }
	}
	return $res
    }

    # Encode to x-www-urlencoded, accepts binary input

    proc EncodeOne {str} {
	set res {}
	foreach chunk [split $str \0] {
	    regsub -all "\[^+ \na-zA-Z0-9\]" $chunk\
		    {%[format %.2x [scan \\& %c v; set v]]} chunk
	    lappend res [subst $chunk]
	}
	set res [join $res %00]
	return [string map [list + "%2b" " " + "\n" "%0a"] $res]
    }

    # Temporary file for posts

    proc TempFile {name data} {
	set fname [file join $::cfg::Tmp $name]
	log $name "creating temp file $fname"
	set fd [open $fname w]
	puts $fd $data
	close $fd
	return $fname
    }


    # This function encodes the given data if "raw" isn't requested.
    # As it seems that data transmitted directly does not work
    # properly in most cases, we always use an intermediate file
    # (The drawback is that we don't know when the file can be removed
    #  and we might write on a file which is in use by a previous request)

    proc EncodeIt {name data raw} {
	if {!$raw} {
	    set data [EncodeAll $data]
	    set data [join [list \
		    "Content-type: application/x-www-form-urlencoded" \
		    "Content-length: [string length $data]" \
		    "" \
		    "$data"] \
		    "\n"]
	}
	# Always use the file option
	set data [TempFile $name $data]
	set fromFile 1
	return [list $data $fromFile]
    }


    # Helper procedure that computes wrapped callbacks, potentially blocks
    # and calls the worker function to actually fetch the data:

    proc CommonFetcher {op name url data fromFile newCB writeCB endCB
			aTimeout} {

	# Compute the various callbacks:

	if {[string equal $newCB {}]} {
	    set newCallBackHandler {}
	} else {
	    set newCallBackHandler [list streamCallBackHandler $newCB]
	}

	if {[string equal $writeCB {}]} {
	    set writeCallBackHandler {}
	} else {
	    set writeCallBackHandler [list streamCallBackHandler $writeCB]
	}

	if {[string equal $endCB {}]} {
	    set blocking 1
	    set token [::wait::token]
	    set endCallBackHandler [list genericEndHandler $token]
	    # Check the validity of the timeout argument
			    
	    # If no timeout was specified, use the default value:
	    if {[string equal $aTimeout {}]} {
		variable timeout
		set aTimeout $timeout
	    } elseif {![string is integer -strict $aTimeout]} {
		error "invalid timeout \"$aTimeout\""
	    }
	} else {
	    set blocking 0
	    set endCallBackHandler [list streamCallBackHandler $endCB]
	}

	# Register the callbacks and actually call the API (op):

	$op $name $url $data $fromFile $newCallBackHandler \
		$writeCallBackHandler $endCallBackHandler

	# If we wanted to block, block now, else return the end callback:

	if {$blocking} {
	    # Block until end of stream:
	    set resCode [catch {::wait::hold $token $name\
		    "commonFetcher:$op" $aTimeout} res]
	    if {$resCode && ([lindex $::errorCode 0] == "TIMEOUT")} {
		# We need to cleanup the stream
		log $name "timeout, cleaning up for \"$url\"" WARNING
		DestroyStreamFromUrl $name $url TIMEOUT
		error "timeout"
	    }
	    return -code $resCode -errorcode $::errorCode $res
	} else {
	    return $endCB
	}
    }

    # Cleans up a waited for stream by its url.

    proc DestroyStreamFromUrl {name url reason} {
	if {[iexists $name stream,handler:$url]} {
	    log $name "DestroyStreamFromUrl ($reason): we did not even had\
		    the new stream for $url" WARNING
	    IUnset $name stream,handler:$url
	} elseif {[iexists $name openUrl:$url]} {
	    set stream [iget $name openUrl:$url]
	    log $name "DestroyStreamFromUrl ($reason): will close $stream"
	    DestroyStream $name $stream $reason
	} else {
	    log $name "DestroyStreamFromUrl ($reason): can not find \"$url\""\
		    ERROR
	}
    }

    # This callback is called when the user registered a callback to be
    # called when some stream events occurs:

    proc streamCallBackHandler {callback name stream args} {
	# we can't use after idle in slave, it's not binary safe
	BgEval $name 0 "$callback $args"
	#SpawnCB $name "$callback $args"
    }

    # This callback releases a blocking geturl or posturl call:

    proc genericEndHandler {token name stream reason data} {
	log $name "calling endGenericHandler $name $stream $reason"
	if {[string equal $reason "EOF"]} {
	    ::wait::release $token $name "endGenericHandler" ok $data
	} else {
	    ::wait::release $token $name "endGenericHandler" error \
		    "abnormal end of stream: $reason"
	}
    }

    #### Stream (for the stream feature) utility/helper functions:

    # This helper routine records the stream as belonging to this Tclet
    # and sets up ForgetStream as an end-of-stream handler.

    proc RecordStream {name stream} {
	ISet $name streamsToBrowser,$stream $stream
	ISet $name stream,$stream,endHandler ForgetStream
    }

    # This routine checks if a given stream is associated with this Tclet.

    proc OwnsStream {name stream} {
	iexists $name streamsToBrowser,$stream
    }

    # This routine removes the association between a stream and a Tclet.

    proc ForgetStream {name stream reason dataPlaceHolder} {
	log $name "forgetting stream $stream : $reason"
	IUnset $name streamsToBrowser,$stream
    }

    ######### START of 'features' implementation (calling NPN_ APIs) ########

    # Procedures below this line implement callbacks from the tclet
    # into the hosting application (eg: 'NPN_' entry points for
    # netscape).
    #
    # Functions called from the slave (through the security checking 
    # aliases of safetcl/ features):
    #

    # This function is called by the feature for a slave to fetch a URL:

    proc getURL {name url {Timeout {}} {newCB {}} {writeCB {}} {endCB {}}} {
	CommonFetcher GetURL $name $url {} 0 $newCB $writeCB $endCB $Timeout
    }

    # This function is called by the feature for a slave to send mail:
    # (it is just a shortcut for displayForm to empty target of a
    #  mailto: url)

    proc sendMail {name where data} {
	displayForm $name "mailto:$where" {} $data 1
    }

    # This function is called by the feature for a slave to post a form:

    proc getForm {name url data {raw 0} {Timeout {}} {newCB {}} {writeCB {}}\
	    {endCB {}} } {
	foreach {data fromFile} [EncodeIt $name $data $raw] {}
	CommonFetcher PostURL $name $url $data $fromFile $newCB \
		      $writeCB $endCB $Timeout
    }

    # This procedure is called by the feature for a slave to display a form:

    proc displayForm {name url target data {raw 0}} {
	foreach {data fromFile} [EncodeIt $name $data $raw] {}
	pnExecute PostURL $name [list $url $target $data $fromFile]
    }

    # This procedure implements the displayURL feature:

    proc displayURL {name url frame} {
	pnExecute GetURL $name [list $url $frame]
    }

    # Short cut for javascript get urls

    proc javascript {name script {callback ""}} {
	log $name "called javascript:$script, callback $callback"
	getURL $name javascript:$script 1000 {} {} $callback
    }

    # This routine displays a status message:

    proc status {name message} {
	log $name "status \"$message\"" NOTICE
	pnExecute Status $name [list $message]
    }

    # This routine opens a stream to a target frame.

    proc openStream {name target {type "text/html"}} {
	set stream [pnExecute OpenStream $name [list $type $target]]
	if {[OwnsStream $name $stream]} {
	    log $name "duplicate stream $stream for target $target" WARNING
	} else {
	    log $name "openStream \"$target\" --> \"$stream\""
	    RecordStream $name $stream
	}
	return $stream
    }

    # This routine writes to a stream opened by openStream.

    proc writeToStream {name stream contents} {
	if {![OwnsStream $name $stream]} {
	    error "permission denied" \
		  "slave $name tried to write to unknown stream $stream"
	}
	log $name "writeToStream \"$stream\" \"$contents\"" NOTICE
	pnExecute WriteToStream $name [list $stream $contents]
    }

    # This routine closes a stream opened by openStream.

    proc closeStream {name stream} {
	if {![OwnsStream $name $stream]} {
	    error "permission denied" \
		  "slave $name tried to close unknown stream $stream"
	}
	log $name "closeStream \"$stream\"" NOTICE
	pnExecute CloseStream $name [list $stream]
    }

}
