# stream.tcl --
#
#	Installs the "stream" feature security checks when requested by
#	a policy.
#
# AUTHORS:      Jacob Levy                      Laurent Demailly
#
# Copyright (c) 1995-1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
# Copyright (c) 2004 ActiveState Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# RCS:  @(#) $Id$

# We provide the "stream" feature set and security checks:
package provide safefeature::stream 1.0

# All the dependencies are done by the "feature" mother package:
package require safefeature 1.0

# We also require security checking functions from the URL feature:
package require safefeature::url 1.0

namespace eval ::safefeature::stream {
    # Our parent will set us up (import and variable lists)
    [namespace parent]::setup [namespace current]

    # Import the security checking features from URL. Report an error if
    # the required features are not defined yet:
    ::safefeature::importAndCheck [namespace current] ::safefeature::url \
	targetIsOk

    # Public entry point:
    namespace export install mimeTypeIsOk
}

proc ::safefeature::stream::install {slave policy arglist} {
    variable nsc
    variable implNs
    variable slaveNs

    foreach {alias directFlag} {
	openStream	0
	closeStream	1
	writeToStream	1
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
	    safelog $slave "denied alias \"$alias\" for \"$policy\""
	}
    }
}

# Aliases that need to check the target (frame)
proc ::safefeature::stream::openStreamAlias \
    {slave policy impl target {mimeType "text/html"}} {
    # Security/Access checks (will return and log an error if needed)
    targetIsOk $slave $policy $target

    # Security/Access checks (will return and log an error if needed)
    mimeTypeIsOk $slave $policy $mimeType

    # cleared, proceed to real implementation :
    $impl $slave $target $mimeType
}

# Mime type checking
proc ::safefeature::stream::mimeTypeIsOk {slave policy mimeType} {
    variable implNs

    if {[allowed $slave $policy "mimeTypes" $mimeType]} {
	return $mimeType
    }
    error "permission denied" "$policy said \"$mimeType\" is not allowed"
}
