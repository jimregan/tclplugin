# rpi.tcl --
#
# Copyright (c) 1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# General Remote Procedure Invocation package (Class).
#
#         Developped for the Tcl Plugin, based on previous work
#         done during Laurent Demailly's PhD on multi-agents control system.
#
# Key Features :
#    + Completly symetric after the connection is established.
#    + From the caller point of view : the entry points 
#      will not return before remote invaction is done (seems 'blocking')
#    + It can services remote request and other events (Tk,...) 
#      while waiting so:
#    + A can send a request to B which, in order to answer will send
#      a request back to A and which will process it ok, return to B
#      the answer which will finally return to A, and everything works
#      ok and in the  right order!
#    + All the Tcl exceptions and special return codes are passed
#      transparently (it is really like and remote eval).
#    + Supports multi-clients per server and any combinations of any
#      number of servers and clients per process/interp
# Missing features:
#    + Strong security : has to be provided by the caller or used in safe
#      interps.
#    + Write queue management
#
# ORIGINAL AUTHORS:      Jacob Levy              Laurent Demailly
#
# RCS:  @(#) $Id$

# We provide the remote procedure invocation:

package provide rpi 1.1

# Package the we need:

package require pluglog 1.0
package require wait 1.0

# This is OO design and we emulate a class using the nice namespace
# features.

# As usual, public APIs and externally settable variables start lowercase
# We use [namespace current] everywhere we need the namespace name so
# the code can be moved to any workspace by just renaming the first line.

namespace eval ::rpi {

    namespace export newServer newClient invoke iset iget iexists\
	    shutdown delete serverWaitConnect spawn

    # Default class wide list of allowed server connection
    variable accessList [list "127.0.0.1:*"]

    # Current protocol version (major minor)
    variable ProtoVersion {1 0} 

    # default class wide timeout
    variable timeout 5000

    # Private current uniq reference (msg number)
    variable MsgNum 0

    # Private current number of instances
    variable InstNum 0

    # Each 'instance' token is in fact the absolute name of a local
    # array In where n is the instance number.

    variable PublicGetAttributes {
	timeout Sock Port accessList newConnHdler PeerList
    }
    variable PublicSetAttributes {
	timeout accessList newConnHdler
    }


    # Public API which, given an instance token and an attribute name,
    # returns it's value
    # Empty or not given attribute will return the a-list of public attributes
    proc iget {this {attribute ""}} {
	if {[string equal $attribute ""]} {
	    variable PublicGetAttributes
	    set res {}
	    foreach attribute $PublicGetAttributes {
		if {[IExists $attribute]} {
		    lappend res $attribute [IGet $attribute]
		}
	    }
	    return $res
	} else {
	    IGet $attribute
	}
    }

    # Public API to set public settable values
    proc iset {this attribute value} {
	variable PublicSetAttributes
	if {[lsearch -exact $PublicSetAttributes $attribute] >= 0} {
	    ISet $attribute $value
	} else {
	    error "unknown or private attribute $attribute"
	}
    }

    # Public API to check existance of an attribute

    # NB: both the instance name and the attributes
    #     can contain any funky character except ()

    proc iexists {this attribute} {
	IExists $attribute
    }

    # Private API to set a value
    # All those accessing APIs assumes the caller has a variable
    # named "this" containing the instance name: ('class' emulation)

    proc ISet {attribute value} {
	upvar 1 this this
#	puts stderr \
#		"Set this=($this), attribute=($attribute), value=($value)"
	set ${this}($attribute) $value
    }

    # Private API to get a value
    proc IGet {attribute} {
	upvar 1 this this
#	puts stderr \
#		"IGet ([info level -1]) this=($this), attribute=($attribute)"
	set ${this}($attribute)
    }

    # Private API to check existance of an attribute
    proc IExists {attribute} {
	upvar 1 this this
	info exists ${this}($attribute)
    }

    # Private API to check unset an attribute
    proc IUnset {attribute} {
	upvar 1 this this
	unset ${this}($attribute)
    }

    # Private API to append to a (list) attribute
    proc ILappend {attribute value} {
	upvar 1 this this
	lappend ${this}($attribute) $value
    }

    # Private API to lreplace in a (list) attribute
    proc ILvreplace {attribute args} {
	upvar 1 this this
	set ${this}($attribute)\
	    [eval [list lreplace [set ${this}($attribute)]] $args]
    }

    # Private API to log a message
    proc ILog {args} {
	upvar 1 this this
	eval [list ::pluglog::log $this] $args
    }

    # Private API to create new instance
    
    proc New {type} {
	variable InstNum
	variable timeout

	incr InstNum
	set this [namespace current]::I$InstNum$type

	# instance's timeout inherit from class' one.

	ISet timeout $timeout

	return $this
    }

    # Public APIs for Server Side (network wise)

    # Nb: one of the two peers have to be a network server, the other
    #     a network client, and both have to agree on a port, but once
    #     the link is established, the communication is fully symetrical)

    proc newServer {{port 0} {myaddr {}}} {
	variable accessList

	set this [New srv]

	# Set the instance accessList initial value to be the class wide one
	ISet accessList $accessList

	# Create a socket for accepting wishd connections:
	# (make sure we listen only on localhost loopback wherever possible)

	# Lets use the myaddr argument only if provided.
	if {[string compare {} $myaddr] == 0} {
	    set socket [socket -server\
		    [list [namespace current]::Accept $this] $port]
	} else {
	    set socket [socket -myaddr $myaddr\
		               -server\
	            [list [namespace current]::Accept $this] $port]
	}

	ISet Sock $socket

	set fl [fconfigure $socket -sockname]

	ISet Host [lindex $fl 0]
	ISet Port [lindex $fl 2]

	ILog "Created server socket [IGet Sock] for [IGet Host]:[IGet Port]"

	return $this
    }

    # Deletes the instance and stops any on going communication
    # as well as shutting down the link.

    proc delete {this} {
	ILog "Deleting..."
	# If we have an open socket, shut it down
	if {[IExists Sock]} {
	    shutdown $this
	}
	# If we have peers remove us from their list
	if {[IExists PeerList]} {
	    foreach peer [IGet PeerList] {
		RemovePeer $peer $this
	    }
	}
	unset $this
    }

    # Private helper to keep PeerList in sync
    proc RemovePeer {this peer} {
	ILog "Removing $peer from this' peers list"
	if {[IExists PeerList]} {
	    set where [lsearch -exact [IGet PeerList] $peer]
	    if {$where >= 0} {
		ILvreplace PeerList $where $where
	    }
	}
    }

    # Public API for both side to end the communication.

    proc shutdown {this} {
	ILog "Closing [IGet Sock]"
	close [IGet Sock]
	IUnset Sock
    }

    # Public API for getting a connection

    proc serverWaitConnect {this {varName {}}} {

	set timeout [IGet timeout]

	# If we are given a varname we'll use it as the token
	# and Accept will store the peer in that varname just
	# before releasing.

	if {[string equal $varName {}]} {
	    # use a token not starting we :: so Accept will not
	    # try to store any result in it
	    set token WT_${this}
	} else {
	    if {![string match "::*" $varName]} {
		error "invalid varname \"$varName\":\
			must start with \"::\" (absolute)"
	    }
	    set token $varName
	}

	ILog "will wait for connect using token \"$token\""

	ISet SrvWaitToken $token

	# Will return 'released' or timeout
	::wait::hold $token $this "serverWaitConnect" $timeout

    }

    # Public API for client (network wise) side.

    proc newClient {host port {myaddr {}}} {
	set this [New cli]
	
	# Lets use the myaddr argument only if provided.
	if {[string equal {} $myaddr]} {
	    set socket [socket $host $port]
	} else {
	    set socket [socket -myaddr $myaddr $host $port]
	}

	ISet Sock $socket

	fconfigure $socket -buffering line -translation binary

	ILog "Sucessfully connected on $host:$port ($socket)"

	SetupHandler $this

	CheckVersion $this

	return $this

    }

    # 'The' API : remote invocation

    proc invoke {this script {aReference {}} {aTimeout {}}} {
	variable MsgNum

	if {![IExists Sock]} {
	    return -code error "$this is not connected!"
	}

	set Sock    [IGet Sock]
	set timeout [IGet timeout]
	
	# Internally, someone might request a single special messages
	# (like CheckVersion does)
	if {[IExists Special]} {
	    set type [IGet Special]
	    # Avoid possible loops or interferences
	    IUnset Special
	} else {
	    set type "E"
	}
	    
	incr MsgNum

	# If no reference argument was given (or empty), lets generate one
	if {[string equal $aReference {}]} {
	    set aReference $MsgNum
	}

	SendMsg $Sock [list $type $aReference $script]

	# Set the timeout handler

	# If no timeout argument was given, lets use the current
	# 'class' timeout:
	if {[string equal $aTimeout {}]} {
	    set aTimeout $timeout
	}

	set token [token $aReference]

	# Will return the 'released' value or timeout
	::wait::hold $token $this "invoke" $aTimeout
    }

    # another API : remote spawn (asynch and no returned value)

    proc spawn {this script {aReference {}}} {
	variable MsgNum

	set Sock [IGet Sock]

	incr MsgNum

	# If no reference argument was given (or empty), lets generate one
	if {[string equal $aReference {}]} {
	    set aReference $MsgNum
	}

	SendMsg $Sock [list S $aReference $script]
    }


    # End of public APIs

    proc CheckVersion {this} {
	variable ProtoVersion

	# Set the 'Special' tags that will enable this one shot special
	# message in invoke.

	ISet Special "V"

	set RemoteProtoVersion [invoke $this $ProtoVersion]
	ISet $RemoteProtoVersion $RemoteProtoVersion
	foreach {mMajor mMinor} $ProtoVersion {}
	foreach {pMajor pMinor} $RemoteProtoVersion {}
	if {$mMajor != $pMajor} {
	    error "protocol error: local major version $mMajor, peer $pMajor"
	}
	# Don't do anything yet with minor as we are the first release
	# later we will need to disable some functions or tune up
	# depending on the minor (adapt to the peer)
    }

    # AccessControl : can be replaced at will if needed by the application
    # if the "accessList" mecanism is not enough

    proc AccessControl {this socket host port} {
	# Host must match with one of the patterns from the accessList:
	foreach allowPat [IGet accessList] {
	    if {[string match $allowPat $host:$port]} {
		ILog "Accepted connection from $host:$port:\
		    matches \"$allowPat\"" SECURITY
		# <Insert here some real security check, with a real challenge>
		return 1
	    }
	}
	ILog "Refusing connection from $host:$port:\
		no match in accessList" SECURITY
	close $socket
	return 0
    }

    proc Accept {this socket host port} {

 	ILog "Received a connection on $socket, from $host:$port"

	if {[AccessControl $this $socket $host $port]} {
	    # We are clear !
	    
	    set peer [NewPeer $this $socket $host $port]

	    ILog "Accepted connection ! -> $peer"
	    
	    ILappend PeerList $peer

	    if {[catch {CheckVersion $peer} msg]} {
		ILog "Peer version problem: $msg" ERROR
		set retCode error
		set resVal  "$peer : $msg"
	    } else {
		set retCode ok
		set resVal  $peer
	    }

	    # Are we 'expecting' this connection ?
	    if {[IExists SrvWaitToken]} {
		
		# Releasing the wait and tell our new children name
		set token [IGet SrvWaitToken]

		# If the token is a global variable name (starting with ::)
		# we save the result in that variable (so ppl can
		# have traces, callbacks, or just start using the result
		# before the vwait unwinds)
	    
		ILog "checking token \"$token\""

		if {[string match "::*" $token]} {
		    set $token $peer
		}

		wait::release [IGet SrvWaitToken] $this Accept $retCode $resVal
	    } elseif {[IExists newConnHdler]} {
		# This server have a new connection handler registered,
		# let's call it :
		[IGet newConnHdler] $this $retCode $resVal
	    } else {
		# Unexpected connection, hmmm
		linkError $this UNEXPECTED_CONNECT $retCode $resVal
	    }
	}
	
    }
    proc NewPeer {peer socket host port} {

	set this [New cli]

	ISet Sock $socket
	ISet Host $host
	ISet Port $port

	ISet PeerList [list $peer]

	# Make the socket line buffered:
	fconfigure $socket -buffering line -translation binary

	# Setup listener
	SetupHandler $this

	return $this
    }


    proc Read {this} {
	set socket [IGet Sock]
	# Our messages are always newline terminated
	set msg [GetMsg $socket]
	if {[llength $msg]==0} {
	    if {[eof $socket]} {
		ILog "EOF on $socket, closing" WARNING
		shutdown $this
		linkDown $this
	    } else {
		# This is strange.
		ILog "Empty read on $socket"
	    }
	} else {
	    # Decode the message structure {type reference script}
	    set type [lindex $msg 0]
	    set ref  [lindex $msg 1]
	    set what [lindex $msg 2]
	    switch -exact -- $type {
		"E" {
		    # This is an eval query (we want a reply), execute it:
		
		    LocalEval $this $ref $what
		}
		"S" {
		    # This is an spawn query (we don't want a reply),
		    # execute it:
		
		    LocalSpawn $this $ref $what
		}
		"V" {
		    # This a protocol version request

		    variable ProtoVersion
		    Reply $this ok $ref $ProtoVersion
		}
		default {
		    # It's a reply, release someone
		
		    if {[catch {::wait::release\
			    [token $ref] $this Read $type $what} msg]} {
			# Unexpected reply !! (probably expired)
			# Tell that we have an error

			linkError $this UNEXPECTED_MSG $ref $type $what $msg
		    }
		}
	    }
	}
    }

    proc linkDown {this} {
	ILog "called default linkDown" WARNING
	delete $this
    }

    proc linkError {this errorType args} {
	ILog "called default linkError $errorType $args" WARNING
    }
    
    proc token {ref} {
	return [namespace current]Rep${ref}
    }

    proc SetupHandler {this} {
	fileevent [IGet Sock] readable [list [namespace current]::Read $this]
    }
    
    # Encode so the transmitted message does not contain a newline
    proc Encode {message} {
	split $message \n
    }
    # Decode message to restore eventual newlines.
    proc Decode {message} {
	join $message \n
    }

    proc SendMsg {socket message} {
	set what [Encode $message]
	puts $socket $what
	::pluglog::log {} "Sent $socket \"$what\"" DEBUG
    }

    proc GetMsg {socket} {
	# Our messages are always newline terminated
	set what [gets $socket]
	::pluglog::log {} "Read $socket \"$what\"" DEBUG
	return [Decode $what]
    }

    proc LocalEval {this reference script} {
	ILog "Local eval \"$script\""
	set ret [catch {uplevel #0 $script} res]
	if {$ret!=0} {
	    ILog "Propagating error \"$res\" ($::errorInfo)" ERROR
	}
	Reply $this $ret $reference $res
    }

    proc LocalSpawn {this reference script} {
	ILog "Local spawn \"$script\""
	if {[catch {uplevel #0 $script} res]} {
	    ILog "Error ($this,$reference)\
		    while executing \"$script\" error: \"$res\"" ERROR
	}
    }

    proc Reply {this code reference answer} {
	SendMsg [IGet Sock] [list $code $reference $answer]
    }


}
