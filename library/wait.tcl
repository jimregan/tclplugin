# wait.tcl --
#
#	General hold/release (vwait encapsulation) helper package.
#
#	Based on Laurent Demailly's Ph.D. thesis work on multi-agent
#	systems.
#
# ORIGINAL AUTHORS:      Jacob Levy              Laurent Demailly
#
# Copyright (c) 1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# SCCS: @(#) wait.tcl 1.9 97/12/02 19:25:51
# RCS:  @(#) $Id$

# We provide waiting:

package provide wait 1.1

# Package the we need:

package require log 1.0

# As usual, public APIs and externally settable variables start lowercase
# We use [namespace current] everywhere we need the namespace name so
# the code can be moved to any workspace by just renaming the first line.

namespace eval ::wait {

    namespace export token register hold release wait

    namespace import ::log::log

    # number of stacked waits
    variable InWait 0

    # number of stacked release
    variable Rcount 0

    # default class wide timeout
    variable timeout 5000

    variable WaitCount 0

    variable WaitStack {}

    # Public Api for a logging and counting vwait, by defaults also registers it

    proc token {{register 1}} {
	variable WaitCount
	incr WaitCount
	set token $WaitCount
	if {$register} {
	    register $token
	} else {
	    return $token
	}
    }

    # Public Api for registering a token (so release can happen before hold)

    proc register {token} {
	set vname [Vname $token]
	if {[info exists $vname]} {
	    set status [lindex [set $vname] 0]
	    switch -exact -- $status {
		"waiting" {
		    error "register token \"$token\" already on hold"
		}
		"registered" {
		    # Nothing to do (it's ok to register twice or more)
		    return $token
		}
		default {
		    error "register token \"$token\" already released ([set $vname])"
		}
	    }
	} else {
	    set $vname [list "registered" {}]
	    return $token
	}
    }

    proc Vname {token} {
	# Allow token to contain any char and still be usuable as
	# local variable in this namespace
	regsub -all {::} $token {__} token
	return [namespace current]::WT$token
    }

    proc EnQueue {vname} {
	variable WaitStack
	lappend WaitStack $vname
    }
    proc DeQueue {} {
	variable WaitStack
	set l [llength $WaitStack]
	if {$l == 0} {
	    error "dequeue on empty wait queue"
	}
	set WaitStack [lrange $WaitStack 0 [expr {$l-2}]]
    }
    proc IsLast {vname} {
	variable WaitStack
	expr {[string compare $vname [lindex $WaitStack end]]==0}
    }

    # Wait for all the ongoing tasks to complete before returning
    # (C stack will still need to be unwinded when it returns non zero)
    # and optionally execute a script when this condition is true

    proc wait {logname msg {script {}}} {
	#
	variable InWait
	variable Rcount
	variable WaitStack

	set scriptGiven [string compare $script {}]

	set l [llength $WaitStack]

	if {$l == 0} {
	    if {$scriptGiven} {
		log $logname "WALL stack empty for $msg, executing script now"
		if {[catch {uplevel #0 $script} err]} {
		    log $logname "$msg: $err" ERROR
		}
		return 
	    } else {
		log $logname "WALL stack empty for $msg"
		return 0
	    }
	}

	set i 0

	log $logname "WALL for $msg : $l / $InWait / $Rcount"

	# Find the deepest un released var
	while {$i<$l} {
	    set vname [lindex $WaitStack $i]
	    set vstat [lindex [set $vname] 0]
	    if {[string compare $vstat "waiting"]==0} {
		# Found !
		log $logname "WALL $i -> $vname for $msg : $InWait"
		vwait $vname
		log $logname "WALL $i <- $vname for $msg : $InWait"
		break
	    }
	    incr i
	}


	if {$scriptGiven} {
	    log $logname "WALL DONE for $msg: $InWait / $Rcount - re-queing"
	    # Next time we get called we (should) have unwind all the above
	    after idle [list [namespace current]::wait $logname "${msg}+" $script]
	} else {
	    log $logname "WALL DONE for $msg: $InWait / $Rcount"
	    return $InWait
	}
    }


    proc hold {token logname msg timeout} {
	variable InWait
	variable Rcount

	# get the real variable name

	set vname [Vname $token]

	# We will hold only if the token has not yet been released :

	if {[info exists $vname]} {
	    set status [lindex [set $vname] 0]
	    switch -exact -- $status {
		"waiting" {
		    error "trying to hold on token $token which is already on hold"
		}
		"registered" {
		    set resultIsHere 0
		}
		default {
		    # all other cases are result codes:
		    set resultIsHere 1
		}
	    }
	} else {
	    set resultIsHere 0
	}
	
	if {$resultIsHere} {
	    # The variable already holds a result, nothing to do

	    set common "hold $token : already exist (immediate return)"
	    
	} else {
	    # 'Normal' case, we have to wait/hold for release:

	    incr InWait

	    # Setup timeout handler

	    set id [after $timeout\
		    [list [namespace current]::release $token $logname\
		          {}\
		          error\
			  "timeout after $timeout ($msg|$vname|$InWait)"\
			  [list TIMEOUT $token $timeout]]]

	    set common "hold $token $msg ($vname) timeout $timeout"
	    log $logname "Entering  $common - $InWait to go."
	    set $vname [list "waiting" $id]
	    EnQueue $vname
	    vwait $vname
	    DeQueue
	    incr InWait -1
	    incr Rcount -1
	}

	set resList [set $vname]
	log $logname "Exiting   $common - res($resList),\
		$InWait wait to go - $Rcount releases pending"
	unset $vname

	set retCode [lindex $resList 0]
	set res     [lindex $resList 1]
	set errCode [lindex $resList 2]

	return -code $retCode -errorcode $errCode $res
    }

    proc release {token logname msg code result {errCode NONE}} {
	variable Rcount

	set vname [Vname $token]
	if {![info exists $vname]} {
	    set msg "invalid (expired? not registered?)\
		    release token \"$token\" ($msg) ($vname)"
	    log $logname $msg ERROR
	    return -code error $msg
	}
	set vstat [lindex [set $vname] 0]
	set id [lindex [set $vname] 1]

	set common [list $code $result $errCode]
	set commonMsg "Releasing hold $token ($msg) ($common)"
	switch -exact -- $vstat {
	    "waiting" {
		incr Rcount
		if {[IsLast $vname]} {
		    log $logname $commonMsg
		} else {
		    log $logname "$commonMsg Not Last! (wrong order)" WARNING
		}
		set $vname $common
		after cancel $id
	    }
	    "registered" {
		log $logname "$commonMsg BEFORE hold"
		set $vname $common
	    }
	    default {
		# all other cases are result already here and thus errors:
		set msg "multiple release attempt for token \"$token\"\
			($msg) ($vname,{$vstat $id} ignoring {$common})"
		log $logname $msg ERROR
		return -code error $msg
	    }
	}
    }
}

