# url.tcl --
#
#	Installs the "Url" features security control set
#       when requested by policies.
#
# AUTHORS:      Jacob Levy                      Laurent Demailly
#
# Copyright (c) 1996-1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# SCCS: @(#) url.tcl 1.11 97/11/13 16:54:37
# RCS:  @(#) $Id$

# We provide the "url" features set:

package provide safefeature::url 1.1

# All the dependencies and the creation of our parent namespace
# is done (once) by the "feature" mother package:

package require safefeature 1.0

namespace eval ::safefeature::url {
    # Our parent will set us up (import and variable lists)

    [namespace parent]::setup [namespace current]

    # Initialize the frame list/array counting mechanism

    variable frames
    # We store the total number of frames in frames(_blank)
    # _self _top _parent and _current comes for free
    array set frames {_blank 0 _top 0 _parent 0 _self 0 _current 0}


    # Public entry point:

    namespace export install urlIsOk targetIsOk

    # This procedure installs the features related to URL manipulation:

    proc install {slave policy arglist} {
	variable nsc
	variable implNs
	variable slaveNs

	foreach {alias 		directFlag} {

		 getURL 	0
		 displayURL 	0
		 getForm	0
		 displayForm	0

		 status		1
		 javascript	1
	         sendMail       1
	} {
	    set nameInSlave "${slaveNs}::${alias}"

	    # Provide the alias if it is allowed for the requested policy:

	    if {[allowed $slave $policy aliases $nameInSlave]} {
		# If there is no security checks to perform (directFlag = 1)
		# We will call directly the implementation, otherwise
		# we go through here
			
		if {$directFlag} {
		    interpAlias $slave $nameInSlave ${implNs}::${alias}
		} else {
		    interpAlias $slave $nameInSlave ${nsc}::${alias}Alias \
			    $policy ${implNs}::${alias}
		}
		# Allow it to be imported:

		interp eval $slave [list namespace eval $slaveNs \
		    [list namespace export $alias]]
	    } else {
		log $slave "denied alias \"$alias\" for \"$policy\""
	    }
	}
    }

    # Aliases that need to check the URL:

    foreach cmd {getURL getForm} {
	proc ${cmd}Alias {slave policy impl url args} {
	    # security clearance
	    set url [urlIsOk $slave $policy $url]
	    # actual implementation (application specific)
	    eval $impl $slave [list $url] $args
	}
    }

    # Aliases that need to check both the target (frame) and an url:

    foreach cmd {displayURL displayForm} {
	proc ${cmd}Alias {slave policy impl url frame args} {
	    # Security/Access checks (will return and log an error if needed).
	    targetIsOk $slave $policy $frame
	    # check and translate url:
	    set url [urlIsOk $slave $policy $url]
	    eval $impl $slave [list $url $frame] $args
	}
    }

    # Security clearance functions:

    proc targetIsOk {slave policy frame} {
	variable frames
	log $slave "called for $policy to display in \"$frame\""
	if {![allowed $slave $policy "frames" $frame]} {
	    error "permission denied: policy $policy does not allow\
		    display in frame \"$frame\""
	}
	# Check the total number of frames
	# (single overall total for all tclets)

	# Blank is special, it always "adds up"
	if {[string equal $frame "_blank"]} {
	    targetCheckTotalCount $slave $frame
	} elseif {![info exists frames($frame)]} {
	    targetCheckTotalCount $slave $frame
	    set frames($frame) 1
	} else {
	    incr frames($frame)
	}
    }

    proc targetCheckTotalCount {name frame} {
	variable frames
	# The total number is stored in _blank
	if {$frames(_blank)+1 > $::cfg::maxFrames} {
	    error "too many frames" "frame \"$frame\",\
		    maxFrames $::cfg::maxFrames ($frames(_blank)+1)"
	}
	log $name "new frame \"$frame\""
	incr frames(_blank) ; # not $frame
    }

    # This procedure policyifies the URL: it decides whether a URL is
    # allowed according to the policy in use by a Tclet.

    proc urlIsOk {slave policy url} {
	variable implNs

	# Relative ---> canonical url:
	set cUrl [::url::join [iget $slave originURL] $url]
	log $slave "url $url -> $cUrl" NOTICE

	if {[allowed $slave $policy "urls" $cUrl]} {
	    return $cUrl
	}
	error "permission denied" "$policy said \"$cUrl\" is not allowed"
    }
}

