# browser.tcl --
#
#	Application specific implementation of the APIs,
#	Tcl Plugin implementation.
#
# CONTACT:      tclplugin-core@lists.sourceforge.net
#
# Copyright (c) 1996-1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
# Copyright (c) 2002-2004 ActiveState Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# RCS:  @(#) $Id$

# We require http::formatQuery
package require http 2

# We require logging
package require pluglog 1.0

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

# we provide browser functionalities:
package provide browser 1.0

# Note: the code below is separated into sections and might
#       be split into separate files at some point for additional
#       clarity. meanwhile, please pay attention to the sections.

# The config mechanism (cfg::) is supposed to be initialized
# before this package is required. ::cfg::implNs must be defined

namespace eval $::cfg::implNs {

    # used features
    namespace import ::safe::error ::safe::interpAlias

    # exported APIs. We export the "private" APIs ISet and IUnset for
    # sub-packages of this package.
    namespace export iget iexists ISet IUnset

    # default url fetching timeout
    variable timeout 120000

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
	regsub -nocase -all "\[^ -~\]+" [join $args] {_} str
	::pluglog::log $slave $str "SLAVE"
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

    proc NewInstance {slave args} {
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
	set slave [::safe::interpCreate $slave -accessPath\
		[::safe::AddSubDirs [list $::tcl_library $::plugin(topdir)]]]

	# Install the policy mechanism
	# (this will also install aliases and hide some potentially
	#  dangerous commands)

	::safe::installPolicy $slave

	# install the "iget" mechanism for the slave

	interpAlias $slave getattr [namespace current]::IGetAlias

	# install the "log" mechanism for the slave
	# (we don't use interpAlias to avoid double logging)

	interp alias $slave ::pluglog::log {} [namespace current]::LogAlias $slave

	# Remember we've not seen a stream for this tclet so far
	# (the first one ought to be the tclet src=)

	ISet $slave gotFirstStream 0

	# We have 2 things that might prevent us from
	# starting the tclet at some point :
	#   + we haven't received the originURL yet
	#   + we haven't received the window yet (and Tk is needed)
	# so we set "waiting" to 2 initially, we decrement it when
	# the above are met (in any order) {using DecrWaiting}
	# and when it does to 0, the tclet is 'run' {by DecrWaiting}:

	ISet $slave waiting 2

	# Initialize the flag telling if the logo has been installed
	# (and thus needs to be removed before launching the tclet)

	ISet $slave hasLogo 0

	# Install the arguments

	installArgs $slave $args

	# Set version variables into the Tclet.

	# transfer 'benign' part of the plugin() array :
	foreach part {version patchLevel release} {
	    interp eval $slave [list set plugin($part) $plugin($part)]
	}

	# Set a package version, so a Tclet can do
	# package require plugin 2.0.3
	# and be sure to run with a version newer than a given release.

	interp eval $slave [list package provide plugin $plugin(pkgVersion)]

	# Try to load site specific stuff into the new slave interpreter. 
	# This hook can be used to initialize the slave interpreter with Tix,
	# Incr Tcl etc etc.
	# siteSafeInit must have been defined when we called "siteInit"
	# or before (no auto-loading).

	if {[info commands siteSafeInit] == "siteSafeInit"} {
	    # If an error occur we don't do anything special beside logging
	    # it, the "siteSafeInit" has to handle it as they wish.
	    if {[catch {siteSafeInit $slave [iget $slave browserArgs]} msg]} {
		::pluglog::log $slave "siteSafeInit error : $msg" ERROR
	    }
	}

	# Set the userAgent and apiVersion for access by the slave
	ISet $slave userAgent $userAgent
	ISet $slave apiVersion $apiVersion

	::pluglog::log $slave "New Instance initialized"

	if {[iexists $slave Script]} {
	    # We must set the origin, but we must also return to our caller
	    # so we do that in "after idle"

	    # Prevent anyone else from changing it
	    ISet $slave originURL {WAITING}

	    AddToScript $slave [iget $slave Script]

	    after idle [list [namespace current]::SetPageOrigin $slave]
	}

	# When time will permit, load some utilities in the slave
	# (like the non GUI version of bgerror (which will be overridden
	#  if we load tk by the plugtk package))

        BgSpawn $slave 1 {package require plugtcl 1.1}

	# If we will not use Tk, we don't have to wait for the window
	# and this might eventually trigger the script above
	# (if we had the originURL)

	if {![iget $slave Tk]} {
	    DecrWaiting $slave
	}

	return $slave
    }

    # Called to destroy an instance (and it's interp, state,...) :

    proc DestroyInstance {slave} {
	::pluglog::log $slave "entering DestroyInstance"

	# Remove wait handlers associated with this Tclet:

	# TO BE DONE

	# Remove the window

	# Destroy the slave interpreter:

	if {[catch {::safe::interpDelete $slave} msg]} {
	    ::pluglog::log $slave "Destroy of slave \"$slave\" failed: $msg" ERROR
	}

	# Discard all the information associated with the destroyed
	# Tclet:

	if {[catch {IUnset $slave} msg]} {
	    ::pluglog::log $slave "No state left to unset: $msg" WARNING
	}

	::pluglog::log $slave "done with DestroyInstance"
    }

    #
    # Window Handling functions
    #

    # This procedure is called to assign a window to the new instance.

    proc SetWindow {slave win x y width height \
	    cliptop clipleft clipbottom clipright} {

	if {![iexists $slave Tk]} {
	    error "invalid interp \"$slave\""
	}

	if {![iget $slave Tk]} {
	    ::pluglog::log $slave "Ignoring SetWindow (non-Tk applet)"
	    return
	}

	::pluglog::log $slave [info level 0] NOTICE

	set winGeom ${width}x${height}

	# Check if we already have a window for that Tclet.

	if {[iexists $slave window]} {
	    # Check if the window is the same.

	    set oldwin [iget $slave window]
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
		::pluglog::log $slave "Window changed: used to be $oldwin, now $win\
			(probable tk destruction problem upcoming)" WARNING
	    }

	    # Check if something actually changed

	    if {[string equal [iget $slave windowGeometry] $winGeom]} {
		::pluglog::log $slave "Bogus setWindow with nothing new ?"
	    } else {
		# This is a resize event:
		ResizeWindow $slave $win $winGeom $x $y $width $height \
		    $cliptop $clipleft $clipbottom $clipright
	    }
	} else {
	    NewWindow $slave $win $winGeom $x $y $width $height \
		$cliptop $clipleft $clipbottom $clipright
	}

	return
    }

    # Virtual Window 'resize' event

    proc ResizeWindow {slave win winGeom x y width height ct cl cb cr} {
	# This *should* be handled by embedding but apparently is not (yet?).

	::pluglog::log $slave [info level 0] NOTICE
	ISet $slave windowGeometry $winGeom
	ISet $slave completeWindowGeometry \
	    [list $x $y $width $height $ct $cl $cb $cr]
	ISet $slave width $width
	ISet $slave height $height

	# We can't assume that "wm" will be hidden. It may have been
	# re-exposed by a security policy.

	if {[lsearch -exact [interp hidden $slave] wm] >= 0} {
	    interp invokehidden $slave wm geometry . $winGeom
	} else {
	    if {[catch {interp eval $slave wm geometry . $winGeom} msg]} {
		::pluglog::log $slave "Changing the geometry in the slave: $msg" ERROR
	    }
	}

	# Only update the embed_args if there are no values for width
	# and height. In the other cases the Tclet can use winfo geometry.
	# -- commented out until proved necessary

#	foreach v {height width} {
#	    if {![iexists $slave ${v}Set]} {
#		ISet $slave ${v}Set [set $v]
#		if {[catch {interp eval $slave\
#			[list set embed_args($v) [set $v]]} msg]} {
#		    ::pluglog::log $slave "Could not set embed_args($v) : $msg" WARNING
#		} else {
#		    ::pluglog::log $slave "Successfully set embed_args($v) to [set $v]"
#		}
#	    }
#	}

    }

    # Virtual New Window event
    # (actually it might be that the window was first
    #  destroyed and then a new one is given...)

    proc NewWindow {slave win geom x y w h ct cl cb cr} {
	::pluglog::log $slave [info level 0] NOTICE

	# If we had a window before for this interp,
	# The browser is probably trying to resize us the hard way,
	# unfortunately Tk will not reload a second time... (yet)
	# {In fact tk should survive the deletion of . and only
	#  go away when we explicitly ask it to, *or* it should
	#  be reloadable several times (but that's less efficient)}

	if {[iexists $slave windowGeometry]} {
	    ::pluglog::log $slave "We had a window before and reloading\
		    tk will most probably fail now..." WARNING
	}

	ISet $slave window $win

	# Nb: the 'main' made sure that we will find safe::loadTk
	# (by adding tk_library to the auto_path)

	if {[catch {::safe::loadTk $slave -use $win} msg]} {
	    # The load failed, if another try is made later, it will
	    # probably just crash (verified on Unix) so we kill
	    # the interp
	    set msg "Tk load failed: $msg (-> destroying $slave)"
	    ::pluglog::log $slave "Tk load failed: $msg" ERROR
	    IUnset $slave window
	    if {[catch {DestroyInstance $slave} err]} {
		::pluglog::log $slave "failed to destroy instance after Tk load failure:\
			$err" ERROR
	    }
	    return -code error $msg
	}

	::pluglog::log $slave "loaded Tk" NOTICE

	# Set the font scaling to 1.0 has it has no meaning in the plugin
	# context where things are expressed in pixels and not in points

	if {[catch {interp invokehidden $slave tk scaling 1.0} err]} {
	    ::pluglog::log $slave "NewWindow invokehidden tk scaling: $err" ERROR
	    if {[catch {interp eval $slave tk scaling 1.0} err]} {
		::pluglog::log $slave "NewWindow tk scaling: $err" ERROR
	    }
	}

	# Set the appname

	if {[catch {interp invokehidden $slave tk appname $slave} err]} {
	    ::pluglog::log $slave "NewWindow invokehidden tk appname: $err" ERROR
	    if {[catch {interp eval $slave tk appname $slave} err]} {
		::pluglog::log $slave "NewWindow tk appname: $err" ERROR
	    }
	}

	# Set up the "wm" alias

	interpAlias $slave wm [namespace current]::WmAlias

	# Set the window size so Tk and the container have the same notion:

	ResizeWindow $slave $win $geom $x $y $w $h $ct $cl $cb $cr

        # Make the size stay the same (by default):

        interp eval $slave {pack propagate . false}

	# If we don't have a script ready to run
	# we install our 'please wait'/'logo'

	if {(![iexists $slave Script]) && (![iexists $slave script])} {

	    ::pluglog::log $slave \
		"window script not ready : putting the banner on"

	    # Remember we did something (so we undo before launching tclet)
	    ISet $slave hasLogo 1

	    # Show the logo and tell the user that something is going on
	    # (loading). We will remove this UI before evaluating the Tclet
	    # code. We leave the tclplogo image/data on purpose so that the
	    # can use it too if it wants to.
	    # The event management/timing here is tricky.

	    interp eval $slave {
		frame .logo
		label .logo.l1 -text "Tclet loading"
		label .logo.l2 -text "Please Wait..." 
		pack .logo.l2 .logo.l1 -side bottom
	    }
	    if {($w >= $::plugin::logo(width)) \
		    && ($h >= $::plugin::logo(height))} {
		interp eval $slave [list image create photo TclpLogo \
			-format gif -data $::plugin::logo(data)]
		interp eval $slave { pack [label .logo.i -image TclpLogo] }
	    }
	    interp eval $slave {
		grid .logo
		update idletasks
	    }
	}

	# We will load basic (tk) utilities like the (graphical)
	# (bg)error handler:

        BgSpawn $slave 1 {package require plugtk 1.0}

	# This will eventually schedule the start the tclet if it has a script
	# already ready. This must be done after the above so the (bg)error
	# handler is installed first.

	DecrWaiting $slave
    }


    #
    # Stream Handling functions
    #

    proc NewStream {slave stream url mimetype lastModified size} {
	# We still canonicalize the url so we can use string compare
	# safely.

	set canonicalURL [::url::canonic $url]

	# Do we know about this stream?
	#
	# BUG: This does not work for redirections, as Netscape does
	# not tell us about the original URL when we get called
	# instead, the URL will be the redirected one and we will not
	# find the stream.

	if {[iexists $slave stream,handler:$canonicalURL]} {
	    # Yes: this stream is being sent because of a previous
	    # request to fetch the content of the url.

	    set handlersList [iget $slave stream,handler:$canonicalURL]
	    IUnset $slave stream,handler:$canonicalURL

	    # We should really keep some list of open  and link them
	    # with "wait" tokens, this is needed for the TIMEOUT proper
	    # handling. better handling later.

	    ISet $slave openUrl:$canonicalURL $stream

	    ISet $slave stream,$stream,writeHandler [lindex $handlersList 1]
	    ISet $slave stream,$stream,endHandler   [lindex $handlersList 2]

	    set newHandler [lindex $handlersList 0]
	    if {[llength $newHandler]} {
		eval [linsert $newHandler end \
			  $slave $stream $url $mimetype $lastModified $size]
	    }
	} else {

	    # No: so this should be first stream ever for this tclet 
	    # which contains the tcl code to be executed.
	    # We thus register a special callback for it.

	    if {![iexists $slave gotFirstStream]} {
		::pluglog::log $slave "Unknown Instance for this stream!" ERROR
		error "Unknown Instance $slave  for this stream $stream ($url)!"
	    }

	    if {![iget $slave gotFirstStream]} {
		ISet $slave gotFirstStream 1

		ISet $slave stream,$stream,writeHandler {}
		ISet $slave stream,$stream,endHandler   EvalInTclet

		# Store properties of the Tclet's url
		# if this hasn't been done already
		# (ie:. if no script= tags have been specified)
		if {![iexists $slave originURL]} {
		    InitState $slave $url
		}

	    } else {
		# NOTE (TBD):
		#
		# If we are expecting only one url at that point
		# we could guess that it's the one we expect
		# even if the url is different (probably because
		# of a redirect).

		set msg "Unexpected stream $stream \"$url\" ($canonicalURL)"
		::pluglog::log $slave $msg ERROR

		# Lets not annoy the user, it could be just a timeout

		#return -code error "$slave: $msg"
		return "$slave: $msg"
	    }
	}

	# Store the meta information known about the stream.

	ISet $slave stream,$stream,lastModified $lastModified
	ISet $slave stream,$stream,size $size
	ISet $slave stream,$stream,url $canonicalURL
	ISet $slave stream,$stream,mimetype $mimetype

	# Ensure that the data is recorded as empty initially for the
	# stream so that the end-of-stream handler can return an empty
	# data item.

	ISet $slave stream,$stream,data {}

	::pluglog::log $slave \
	    "New stream $stream $url ($canonicalURL) $size bytes" NOTICE

	return "ok"
    }

    # The following procedure writes a chunk of data to a stream:

    proc WriteStream {slave stream length chunk} {
	::pluglog::log $slave "$length additional bytes received for $stream"

	if {![iexists $slave stream,$stream,writeHandler]} {
	    ::pluglog::log $slave "unknown stream $stream while writing" ERROR
	    return
	}

	# convert from external encoding to utf-8 using charset arg..
	if {[interp eval $slave [list info exists embed_args(charset)]]} {
	    set enc [interp eval $slave [list set embed_args(charset)]]
	    set encs [encoding names]
	    if {[lsearch -exact $encs $enc] > -1} {
		set chunk [encoding convertfrom $encoding $chunk]
	    }
	}

	IAppend $slave stream,$stream,data $chunk
	::pluglog::log $slave \
	    "stored data for $stream in stream,$stream,data attr"

	set handler [iget $slave stream,$stream,writeHandler]

	if {![string equal $handler ""]} {
	    ::pluglog::log $slave \
		"evaling write handler $handler $slave $stream $length $chunk"
	    eval [linsert $handler end $slave $stream $length $chunk]
	}
    }

    # DestroyStream, means we can actually process the stream:

    proc DestroyStream {slave stream reason} {
	::pluglog::log $slave "destroy stream ($reason) $stream"

	if {![iexists $slave stream,$stream,endHandler]} {
	    ::pluglog::log $slave "unknown stream $stream at end" ERROR
	    return
	}

	set handler [iget $slave stream,$stream,endHandler]
	if {[iexists $slave stream,$stream,data]} {
	    set data [iget $slave stream,$stream,data]
	} else {
	    ::pluglog::log $slave "$stream has no data"
	    set data {}
	}

	# Remove from the openUrl:$url
	# (before calling the handler, to avoid possible recursion)

	if {[iexists $slave stream,$stream,url]} {
	    set url [iget $slave stream,$stream,url]
	    ::pluglog::log $slave "stream $stream has url $url"
	    if {[iexists $slave openUrl:$url]} {
		set s [iget $slave openUrl:$url]
		if {$s == $stream} {
		    ::pluglog::log $slave \
			"removing stream $stream from openUrl list"
		    IUnset $slave openUrl:$url
		} else {
		    ::pluglog::log $slave \
			"streamm mismatch same url for $s and $stream"\
			WARNING
		}
	    } else {
		::pluglog::log $slave \
		    "but url $url is not in openUrls (ok for src='s url)"
	    }
	} else {
	    ::pluglog::log $slave "stream $stream has no url !"
	}

	if {[llength $handler]} {
	    # Catch so we do the cleanup even it it fails
	    # and we don't annoy the user
	    if {[catch {eval [linsert $handler end \
				  $slave $stream $reason $data]} msg]} {
		::pluglog::log $slave \
		    "error in end handler $handler $stream $reason: $msg" ERROR
	    }
	} else {
	    ::pluglog::log $slave "Unhandled End of stream $stream: $reason" \
		WARNING
	}


	# It's possible that some fields have not been set, because the
	# stream was registered from openStream, so we catch around trying
	# to unset them: 

	foreach field {
	    writeHandler endHandler
	    lastModified size url mimetype
	} {
	    if {[catch {IUnset $slave stream,$stream,$field} msg]} {
		::pluglog::log $slave "stream $stream had no $field"
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

    proc InitState {slave originURL} {

	# Check that we are not setting it twice or changing it

	if {[iexists $slave originURL]} {
	    set msg "Trying to change the originURL (to $originURL)\
		    while it has been set already (to [iget $slave originURL])"
	    ::pluglog::log $slave $msg SECURITY
	    error $msg
	}

	# raw version "as is"

	ISet $slave rawOriginURL $originURL

	if {[string equal $originURL ""]} {
	    # Empty URL == UNKNOWN
	    foreach var {URL Proto Host Port Path Key HomeDirURL SocketHost} {
		# We intentionally put a space in here so the field
		# gets all the chances to be invalid if used anywhere
		ISet $slave origin$var "UNKNOWN $var"
	    }
	} else {
	    # parsed/canonical version

	    foreach var {Proto Host Port Path Key}\
		    val [::url::parse $originURL] {
		set $var $val
		ISet $slave origin$var $val
	    }

	    # Recreate the canonical URL:

	    set canonicalURL [::url::format $Proto $Host $Port $Path $Key]
	    ISet $slave originURL $canonicalURL
	    ::pluglog::log $slave "originURL set to \"$originURL\""

	    # Save the home url (directory) of the tclet

	    ISet $slave originHomeDirURL [::url::join $canonicalURL ./]

	    # We compute what host to use in socket requests with special
	    # handling for "file:" URLs that have no specified host.

	    if {[string equal $Proto "file"] && [string equal $Host ""]} {
		ISet $slave originSocketHost localhost
	    } else {
		ISet $slave originSocketHost $Host
	    }
	}

	# We have the origin url, cool, lets eventually schedule the 
	# tclet launch then

	DecrWaiting $slave
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
	    ::pluglog::log INIT "error sourcing $fname: $msg" ERROR
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
	    ::pluglog::log INIT "siteInit failed ($msg)" WARNING
	}

	SetupConsole
    }


    proc SetPageOrigin {slave} {
	::pluglog::log $slave "called SetPageOrigin"

	# We must set the origin. We use the javascript trick to get the
	# page url; if it fails we call InitState with empty which
	# will safely fill the credentials with "UNKNOWNs".

	# If javascript is disabled our call back will never be called
	# and we won't get an error ! so we put a timeout and store it
	# in our 'lock'

	ISet $slave originURL [list WAITING\
		[after 3000 [list [namespace current]::DonePageOrigin\
		$slave none "GetURL javascript timeout (disabled?)" {}]]]

	if {[catch {GetURL $slave "javascript:location.href" notused notused\
		{} {} [namespace current]::DonePageOrigin} msg]} {
	    DonePageOrigin $slave none "GetURL javascript error:$msg" {}
	}
    }

    proc DonePageOrigin {slave stream reason data} {

	# Done:

	# Remove the timeout handler

	set id [iget $slave originURL]
	after cancel [lindex $id 1]

	# Remove the 'lock' on originURL

	IUnset $slave originURL

	if {[string equal $reason "EOF"]} {
	    ::pluglog::log $slave "got page source url ($stream): \"$data\""
	    InitState $slave $data
	} else {
	    ::pluglog::log $slave "can't get page source url ($stream): $reason" WARNING
	    InitState $slave {}
	}

	if {[iexists $slave ToLaunch]} {
	    ::pluglog::log $slave "will start tclet!"
	    LaunchTclet $slave {}
	}
    }

    # Called by NewInstance to set and parse the arguments

    proc installArgs {slave arguments} {
	# Save raw arguments:

	ISet $slave browserRawArgs $arguments

	# Default value
	ISet $slave Tk 1

	# Html tags are case insensitive, so make sure the names for
	# the tags are all in lower case:

	foreach {tag value} $arguments {
	    set ntag [string tolower $tag]
	    set narg($ntag) $value
	    # The "script=" tag is special, it eventually replaces
	    # the src= tag
	    switch -exact -- $ntag {
		"script" {
		    ISet $slave Script $value
		    # Nb: as we will use this script, we must thus set the
		    # "origin" of this tclet to the page and not to
		    # whatever the stream origin would be for instance.
		    # This is done at the end of NewInstance.
		}
		"tk" {
		    ::pluglog::log $slave "tk specified ($value)" DEBUG
		    ISet $slave Tk [string is true -strict $value]
		}
		"hidden" {
		    ::pluglog::log $slave "hidden specified ($value)" DEBUG
		    ISet $slave Tk 0
		}
	    }
	    # Special handling for height and width for backward compatibility
	    # (used in ResizeWindow)   - removed until proved necessary.
#	    foreach v {height width} {
#		if {[string equal $ntag $v]} {
#		    ISet $slave ${v}Set $value
#		    break
#		}
#	    }
	}

	set narglst [array get narg]

	# Save the processed args:

	ISet $slave browserArgs $narglst

	# The Tclet should really use "getattr browserArgs" to get the
	# arguments but for backward compatibility we install them in the array
	# embed_args. This name is kept even though it is not style guide
	# compliant, for backwards compatibility:

	interp eval $slave [list array set embed_args $narglst]

    }


    # Get the user agent (represents the embedding browser version etc.)
    # and decide, based on that, whether to disable some of the
    # commands.

    proc ConfigureCommands {slave} {
	global plugin
	variable userAgent
	variable apiVersion

	set userAgent [pnExecute UserAgent $slave {}]
	set vl [pnExecute ApiVersion $slave {}]

	# We only use the first two elements of the list, which are the
	# version numbers of the Netscape->plugin side. The other two are
	# the version numbers of the plugin->Netscape side of the API.

	set apiVersion [lindex $vl 0].[lindex $vl 1]

	::pluglog::log $slave "set [namespace current]::userAgent=($userAgent)"

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
	    ::pluglog::log {} "Disabling command $cmd for $ua"
	    proc $cmd {slave args} [list error "$cmd is disabled in $ua"]
	}
    }


    ######## 'Tasks' management utility functions ########

    # Background wrapper for logging and to avoid spurious
    # bgerror when evaluating in slave:

    # if direct is 1 : we directly execute code
    #           is 0 : we execute tclet code wrapped around bgerror checking

    proc BgEval {slave direct cmd} {
	::pluglog::log $slave "BgEval START tclet $slave: $cmd"
	if {$direct} {
	    set expr $cmd
	} else {
	    # First remove what we've eventually put at "NewWindow" time
	    if {[iget $slave hasLogo]} {
		ISet $slave hasLogo 0
		if {[catch {interp eval $slave {destroy .logo}} msg]} {
		    ::pluglog::log $slave \
			"removing splash screen failure (tk destroyed): $msg" \
			ERROR
		}
	    }
	    # Try to use our installed bgerror.
	    set expr [subst {
		set plugin(ret) \[catch {uplevel \#0 [list $cmd]} plugin(res)\]
		# only launch the error console if there is really an
		# "error" (=1) return code
		if {\$plugin(ret)==1} { bgerror \$plugin(res) }
		return -code \$plugin(ret) \
		    -errorinfo \$::errorInfo \$plugin(res)
	    }]
	    # still, we return what we got.
	}
	set ret [catch {interp eval $slave $expr} res]
	if {$ret} {
	    ::pluglog::log $slave \
		"Slave $slave eval ($direct) return code $ret ($cmd): $res" \
		ERROR
	} else {
	    ::pluglog::log $slave "BgEval DONE tclet $slave ($cmd): $res"
	}
    }

    # Will evaluate "cmd" in the slave when idle:

    proc BgSpawn {slave direct cmd} {
	::pluglog::log $slave "Call on IDLE: \"$cmd\""
	after idle [list [namespace current]::BgEval $slave $direct $cmd]
    }

    # If the waiting counter is 0 or less, actually launch the code:

    proc EventuallyLaunch {slave} {
	if {[iget $slave waiting] <=0} {
	    # Reset the counter to 0 so we don't go too far in negative
	    # if called again later:
	    ISet $slave waiting 0
	    if {[iexists $slave ToLaunch]} {
		# What we have to do :
		set script [iget $slave ToLaunch]
		# This part is for recording the total script for
		# later authentification/signature purposes for instance
		# and so we know if we need to install the logo/please wait
		if {[iexists $slave script]} {
		    IAppend $slave script "\n$script"
		} else {
		    ISet $slave script $script
		}
		# Remove 'ToLaunch' content so we don't evaluate things twice
		IUnset $slave ToLaunch
		# Prepare for launch (when idle)
		::pluglog::log $slave \
		    "Convert CR/CRLF to LF and schedule script for eval"
		# The script we receive requires LF conversion still.
		# Order in the map is important.  This may affect binary
		# data stored in a script.
		set script [string map [list "\r\n" "\n" "\r" "\n"] $script]
		BgSpawn $slave 0 $script
	    } else {
		::pluglog::log $slave \
		    "would launch the tclet, but nothing to launch now!"
	    }
	} else {
	    ::pluglog::log $slave \
		"not yet ready to go ([iget $slave waiting] to go)"
	}
    }

    # Decrement the ref counting of tasks we are still waiting
    # completion, if it reaches 0 then actually launch the tclet:

    proc DecrWaiting {slave} {
	::pluglog::log $slave \
	    "decrementing the waiting counter ([iget $slave waiting])"
	IIncr $slave waiting -1
	EventuallyLaunch $slave
    }

    # Add to the code to launch whenever possible
    # and record everything which has been evaluated in the tclet :

    proc AddToScript {slave script} {
	# Record what we have to do when ready
	IAppend $slave ToLaunch "$script\n"
    }

    # Start a tclet coming from a stream:

    proc EvalInTclet {slave stream reason data} {
	if {[string equal $reason "EOF"]} {
	    if {[string length $data] == 0} {
		NotifyError $slave "document [iget $slave originURL]\
			contains no data"
		return
	    }
	    AddToScript $slave $data
	    EventuallyLaunch $slave
	} else {
	    ::pluglog::log $slave \
		"Tclet code's stream $stream ended with reason $reason" ERROR
	}
    }

    #### Url fetching/posting (for the url feature) utility/helper functions:

    # This procedure does the actual work of fetching the URL:

    proc GetURL {slave url notusedData notusedFromFile \
		 newCallBack writeCallBack endCallBack} {
	if {[iexists $slave stream,handler:$url]} {
	    error "not supported: multiple pending requests for same URL\
			($url)"
	}

	ISet $slave stream,handler:$url \
		[list $newCallBack $writeCallBack $endCallBack]

	pnExecute GetURL $slave [list $url]
    }

    # This procedure does the actual work of posting to a URL:
    proc PostURL {slave url data fromFile \
		  newCallBack writeCallBack endCallBack} {
	if {[iexists $slave stream,handler:$url]} {
	    error "not supported: multiple pending requests for same URL\
			($url)"
	}

	ISet $slave stream,handler:$url \
		[list $newCallBack $writeCallBack $endCallBack]

	pnExecute PostURL $slave [list $url {} $data $fromFile]
    }

    # Temporary file for posts
    proc TempFile {slave data} {
	set fname [file join $::cfg::Tmp $slave]
	::pluglog::log $slave "creating temp file $fname"
	set fd [open $fname w]
	puts $fd $data
	close $fd
	return $fname
    }

    # This should all be rewritten to leverage the http package.
    # This function encodes the given data if "raw" isn't requested.
    # As it seems that data transmitted directly does not work
    # properly in most cases, we always use an intermediate file
    # (The drawback is that we don't know when the file can be removed
    #  and we might write on a file which is in use by a previous request)

    proc EncodeIt {slave data raw} {
	if {!$raw} {
	    set data [eval [list ::http::formatQuery] $data]
	    set data [join [list \
		    "Content-type: application/x-www-form-urlencoded" \
		    "Content-length: [string length $data]" "" $data] "\n"]
	}
	# Always use the file option
	set data [TempFile $slave $data]
	set fromFile 1
	return [list $data $fromFile]
    }

    # Helper procedure that computes wrapped callbacks, potentially blocks
    # and calls the worker function to actually fetch the data:

    proc CommonFetcher {op slave url data fromFile newCB writeCB endCB
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

	$op $slave $url $data $fromFile $newCallBackHandler \
		$writeCallBackHandler $endCallBackHandler

	# If we wanted to block, block now, else return the end callback:

	if {$blocking} {
	    # Block until end of stream:
	    set resCode [catch {::wait::hold $token $slave\
		    "commonFetcher:$op" $aTimeout} res]
	    if {$resCode && ([lindex $::errorCode 0] == "TIMEOUT")} {
		# We need to cleanup the stream
		::pluglog::log $slave \
		    "timeout, cleaning up for \"$url\"" WARNING
		DestroyStreamFromUrl $slave $url TIMEOUT
		error "timeout"
	    }
	    return -code $resCode -errorcode $::errorCode $res
	} else {
	    return $endCB
	}
    }

    # Cleans up a waited for stream by its url.

    proc DestroyStreamFromUrl {slave url reason} {
	if {[iexists $slave stream,handler:$url]} {
	    ::pluglog::log $slave \
		"DestroyStreamFromUrl ($reason): we did not even have\
		the new stream for $url" WARNING
	    IUnset $slave stream,handler:$url
	} elseif {[iexists $slave openUrl:$url]} {
	    set stream [iget $slave openUrl:$url]
	    ::pluglog::log $slave \
		"DestroyStreamFromUrl ($reason): will close $stream"
	    DestroyStream $slave $stream $reason
	} else {
	    ::pluglog::log $slave \
		"DestroyStreamFromUrl ($reason): can not find \"$url\"" ERROR
	}
    }

    # This callback is called when the user registered a callback to be
    # called when some stream events occurs:

    proc streamCallBackHandler {callback slave stream args} {
	BgEval $slave 0 [concat $callback $args]
    }

    # This callback releases a blocking geturl or posturl call:

    proc genericEndHandler {token slave stream reason data} {
	::pluglog::log $slave \
	    "calling endGenericHandler $slave $stream $reason"
	if {[string equal $reason "EOF"]} {
	    ::wait::release $token $slave "endGenericHandler" ok $data
	} else {
	    ::wait::release $token $slave "endGenericHandler" error \
		    "abnormal end of stream: $reason"
	}
    }

    #### Stream (for the stream feature) utility/helper functions:

    # This helper routine records the stream as belonging to this Tclet
    # and sets up ForgetStream as an end-of-stream handler.

    proc RecordStream {slave stream} {
	ISet $slave streamsToBrowser,$stream $stream
	ISet $slave stream,$stream,endHandler ForgetStream
    }

    # This routine checks if a given stream is associated with this Tclet.

    proc OwnsStream {slave stream} {
	iexists $slave streamsToBrowser,$stream
    }

    # This routine removes the association between a stream and a Tclet.

    proc ForgetStream {slave stream reason dataPlaceHolder} {
	::pluglog::log $slave "forgetting stream $stream : $reason"
	IUnset $slave streamsToBrowser,$stream
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

    proc getURL {slave url {Timeout {}} {newCB {}} {writeCB {}} {endCB {}}} {
	CommonFetcher GetURL $slave $url {} 0 $newCB $writeCB $endCB $Timeout
    }

    # This function is called by the feature for a slave to send mail:
    # (it is just a shortcut for displayForm to empty target of a
    #  mailto: url)

    proc sendMail {slave where data} {
	displayForm $slave "mailto:$where" {} $data 1
    }

    # This function is called by the feature for a slave to post a form:

    proc getForm {slave url data {raw 0} {Timeout {}} {newCB {}} {writeCB {}}\
	    {endCB {}} } {
	foreach {data fromFile} [EncodeIt $slave $data $raw] {}
	CommonFetcher PostURL $slave $url $data $fromFile $newCB \
		      $writeCB $endCB $Timeout
    }

    # This procedure is called by the feature for a slave to display a form:

    proc displayForm {slave url target data {raw 0}} {
	foreach {data fromFile} [EncodeIt $slave $data $raw] {}
	pnExecute PostURL $slave [list $url $target $data $fromFile]
    }

    # This procedure implements the displayURL feature:

    proc displayURL {slave url frame} {
	pnExecute GetURL $slave [list $url $frame]
    }

    # Short cut for javascript get urls

    proc javascript {slave script {callback ""}} {
	::pluglog::log $slave "called javascript:$script, callback $callback"
	getURL $slave javascript:$script 1000 {} {} $callback
    }

    # This routine displays a status message:

    proc status {slave message} {
	::pluglog::log $slave "status \"$message\"" NOTICE
	pnExecute Status $slave [list $message]
    }

    # This routine opens a stream to a target frame.

    proc openStream {slave target {type "text/html"}} {
	set stream [pnExecute OpenStream $slave [list $type $target]]
	if {[OwnsStream $slave $stream]} {
	    ::pluglog::log $slave \
		"duplicate stream $stream for target $target" WARNING
	} else {
	    ::pluglog::log $slave "openStream \"$target\" --> \"$stream\""
	    RecordStream $slave $stream
	}
	return $stream
    }

    # This routine writes to a stream opened by openStream.

    proc writeToStream {slave stream contents} {
	if {![OwnsStream $slave $stream]} {
	    error "permission denied" \
		  "slave $slave tried to write to unknown stream $stream"
	}
	::pluglog::log $slave "writeToStream \"$stream\" \"$contents\"" NOTICE
	pnExecute WriteToStream $slave [list $stream $contents]
    }

    # This routine closes a stream opened by openStream.

    proc closeStream {slave stream} {
	if {![OwnsStream $slave $stream]} {
	    error "permission denied" \
		  "slave $slave tried to close unknown stream $stream"
	}
	::pluglog::log $slave "closeStream \"$stream\"" NOTICE
	pnExecute CloseStream $slave [list $stream]
    }

}
