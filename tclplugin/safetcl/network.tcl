# network.tcl --
#
#	Installs the "Network" features security control set
#       when requested by policies.
#
# CONTACT:	sunscript-plugin@sunscript.sun.com
#
# AUTHORS:	Jacob Levy			Laurent Demailly
#		jyl@eng.sun.com			demailly@eng.sun.com
#		jyl@tcl-tk.com			L@demailly.com
#
# Please contact us directly for questions, comments and enhancements.
#
# Copyright (c) 1996-1997 Sun Microsystems, Inc.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# SCCS: @(#) network.tcl 1.8 97/10/16 14:33:34


# We provide the "network" features set
package provide safefeature::network 1.0

# All the dependencies and the creation of our parent namespace
# is done (once) by the "feature" mother package:
package require safefeature 1.1

namespace eval ::safefeature::network {

    # Our parent will set us up
    [namespace parent]::setup [namespace current]

    # Public entry point:
    namespace export install hostAndPortAreOk


    # This procedure installs the features related to URL manipulation:

    proc install {slave policy arglist} {
	variable nsc

	# The Aliases which provides mediated access to commmands usually
	# enabled in Tcl will thus go to toplevel in the slave:

	foreach alias {
	    socket
	    fconfigure
	} {
	    if {[allowed $slave $policy aliases $alias]} {
		interpAlias $slave $alias ${nsc}::${alias}Alias $policy
	    } else {
		log $slave "denied alias \"$alias\" for $policy"
	    }
	}
    }

    # This procedure intermediates on socket requests to ensure that the
    # request falls within the policy allowed by the policy currently in
    # use by the requesting Tclet.

    proc socketAlias {slave policy host port} {
	if {[string compare $host ""] == 0} {
	    set host [iget $slave originSocketHost]
	}
	# Check access
	hostAndPortAreOk $slave $policy $host $port
	# Proceed
	return [invokeAndLog $slave socket $host $port]
    }

    # This procedure handles the "fconfigure" alias from the slave:

    proc fconfigureAlias {slave policy sock args} {
	set allowedList {blocking buffering buffersize
             eofchar translation peername}
	
	set usage "should be one of -[join $allowedList ", -"]."

	if {[llength $args] == 0} {
	    set res {}
	    foreach {a v} [invokeAndLog $slave fconfigure $sock] {
		if {[lsearch $allowedList [string range $a 1 end]] >= 0} {
		    lappend res $a $v
		}
	    }
	    return $res
	} elseif {[llength $args] == 1} {
	    
	    return [invokeAndLog $slave fconfigure $sock\
		    [checkArgs $allowedList $usage [lindex $args 0]]]

	} else {

	    if {[llength $args] % 2} {
		error "wrong # args: should be \"fconfigure channelId\
			?optionName? ?value? ?optionName value?...\""
	    }
	    foreach {a v} $args {
		checkArgs $allowedList $usage $a
	    }
	    eval invokeAndLog [list $slave fconfigure $sock] $args
	}
    }
    
    # Security clearance functions

    # This procedure decides whether the host and port are allowed for the
    # policy currently in use by the requesting Tclet.

    proc hostAndPortAreOk {slave policy host port} {
	if {![regexp {^[0-9]+$} $port]} {
	    error "permission denied: non numeric port $port"
	}
	if {![allowed $slave $policy {hosts ports} $host $port]} {
	    error "permission denied for host $host port $port"
	}
    }


}
