# persist.tcl --
#
#	Installs the File Persistence features set
#       when requested by policies.
#	This file implements local persistent storage for Tclets. This
#	facility is accessible via individual policies such as
#	the network policy.
#
# AUTHORS:      Jacob Levy              Laurent Demailly
#
# Copyright (c) 1996-1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# RCS:  @(#) $Id$


# We provide the "persist" features set
package provide safefeature::persist 1.0

# All the dependencies and the creation of our parent namespace
# is done (once) by the "feature" mother package:
package require safefeature 1.0

# Note: We use the implentation ISet's here which is probably 
# a bad thing (ie we should maintain our per tclet state ourselves)

namespace eval ::safefeature::persist {

    # Our parent will set us up (import and variable lists)
    [namespace parent]::setup [namespace current]

    # Public entry point:
    namespace export install computeKey

    # By default, all local persistent file directories live
    # underneath this directory. One of the two env(TEMP) or
    # ::cfg::Tmp must exist for this to work:

    if {[info exists ::cfg::Tmp]} {
	variable StorageRoot [file join $::cfg::Tmp persist]
    } else {
	variable StorageRoot [file join $::env(TEMP) persist]
    }

    # How many channels can be open in a Tclet at any one time? The default
    # value is four, which means that a Tclet can have up to four channels
    # to persistent local files open at once.

    variable OpenFilesLimit 4

    # How many files can be stored in a local persistent file directory?
    # The default is fout, which means that a persistent file directory can
    # contain at most four files at once.

    variable StoredFilesLimit 4

    # What is the maximum size for a local persistent file? The default is
    # one megabyte.

    variable FileSizeLimit [expr {1024 * 1000}]

    proc install {slave policy arglist} {
	global errorInfo

	set originURL [iget $slave originURL]
	set originPath [iget $slave originPath]
	if {([catch {interp eval $slave {set ::embed_args(prefix)}} prefix])
	     || ([catch {computeKey $originURL $prefix} key])} {

	    # If the variable "key" is set, we got an error in the second
	    # catch, above, and this means that the given prefix was bad.

	    if {[info exists key]} {
		safelog $slave "bad prefix \"$prefix\": $key" WARNING
	    }

	    # Switch to using the original URL, and set the prefix in
	    # the Tclet to the full path component of that URL:

	    set key $originURL
	    set prefix $originPath
	    safelog $slave "bad or empty prefix, using \"$prefix\": \"$key\""
	    if {[catch {interp eval $slave \
		    [list set ::embed_args(prefix) $prefix]} msg]} {
		safelog $slave "could not update embed_args(prefix): $msg" WARNING
	    }
	} else {
	    safelog $slave "prefix \"$prefix\": \"$key\""
	}


	# Compute the directory to be used by this Tclet for its persistent
	# local storage files: 

	# We don't catch the GetDir which can fail, it it fails
	# the error will be caught by the policy mechanism and
	# reported to the user and the tclet will be killed

	set dir [GetDir $slave $policy $key]

	ISet $slave PersistentFileDir $dir

	# Set up aliases for the local persistent storage facility:

	set nsc [namespace current]

	# All the commands below are expected to having been hidden
	# before any unsafe code could have run, otherwise we
	# have a quite big security problem.

	foreach alias {
	    open
	    file
	    puts
	    close
	    seek
	    tell
	    glob
	} {
	    if {[lsearch [interp hidden $slave] $alias] < 0} {
		error "unsafe setup, command \"$alias\" is not hidden"
	    }

	    # Provide the alias if it is allowed by the requested policy:

	    if {[allowed $slave $policy aliases $alias]} {
		interpAlias $slave $alias ${nsc}::${alias}Alias $policy
	    } else {
		safelog $slave "denied alias \"$alias\" for $policy"
	    }
	}

	# Set up counters for open channels and existing files for the Tclet:

	ISet $slave openChannelCounter 0
    }

    # Utility function to create a key used to select a directory to use
    # for this Tclet:

    proc computeKey {originURL prefix} {

	# Compute the key. Using a prefix of the URL from which the Tclet
	# was loaded allows sharing of local persistent files between
	# Tclets. If the Tclet asked to use a prefix, we check it
	# and if it's OK then we use it, otherwise we error out. If the
	# Tclet didn't ask to use a prefix, we use the complete original
	# URL to compute the key.

	foreach var {Proto Host Port Path Key} val [::url::parse $originURL] {
	    set $var $val
	}

	# We want to prevent un-agreed upon sharing between Tclets
	# from the same host. Therefore we construct a match pattern
	# that includes the host, port and protocol from the original
	# URL, and effectively match only the prefix given against the
	# path portion and the key portion of the original URL.

	set key [::url::format $Proto $Host $Port $prefix {}]
	if {![string match ${key}* $originURL]} {
	    error "key \"$key\" did not match \"$originURL\""
	}
	return $key
    }

    # This procedure maintains a map from Tclet names and policies to
    # directories used to store the Tclet's local persistent files:

    proc GetDir {slave policy key} {
	global env

	variable StorageRoot
	variable OpenFilesLimit
	variable StoredFilesLimit
	variable FileSizeLimit

	# Compute the root to use for the storage for this policy:

	if {[catch {cfg::getConstant $slave $policy persist storage} where]} {
	    set where $policy
	}
	set storage [file join $StorageRoot $where]


	# Refresh the map from the disk file:

	set fname [file join $storage persist.map]

	if {[catch {source $fname} msg]} {
	    safelog $slave "source \"$fname\" failed: $msg" WARNING
	}

	# Set the dirty bit which indicates that we need to save the
	# state. Initially it is not set.

	set dirty 0

	# If the counter for directories does not exist yet, initialize
	# it now:

	if {![info exists KeyCounter]} {
	    set KeyCounter 0
	    set dirty 1
	}

	# Compute the directory used to store the persistent files for this
	# Tclet.

	if {[info exists Map($key)]} {
	    set dir $Map($key)
	} else {
	    set dir [file join $storage dir${KeyCounter}]
	    incr KeyCounter
	    set Map($key) $dir
	    set dirty 1
	}

	# If we have changed any state bits, save the state now:

	if {$dirty} {
	    file mkdir $storage
	    if {[catch {set fd [open $fname w]} msg]} {
		error "permission denied" \
		      "cannot open persistent map file \"$fname\" for writing"
	    }
	    puts $fd [list set KeyCounter $KeyCounter]

	    # Dump the map of keys to directories:

	    puts $fd [list array set Map [array get Map]]
	    close $fd
	}

	safelog $slave "using \"$key\", \"$policy\" for file directory \"$dir\""

	return $dir
    }

    # This procedure services the open alias:

    proc openAlias {slave policy fileName {mode r}} {
	variable StoredFilesLimit
	variable FileSizeLimit
	variable OpenFilesLimit

	# If opening another file would exceed the channel limit, error out:

	if {[catch {cfg::getConstant $slave $policy persist openFilesLimit}\
		openFilesLimit]} {
	    set openFilesLimit $OpenFilesLimit
	}

	if {[iget $slave openChannelCounter] == $openFilesLimit} {
	    error "permission denied: channel count limit" \
		  "slave $slave cannot open \"$fileName\": channel count limit"
	}

	# Ensure that the local persistent file directory exists and that
	# it is a directory:

	set dir [iget $slave PersistentFileDir]
	if {![file exists $dir]} {
	    # Try to create the directory:
	    file mkdir $dir
	    if {![file exists $dir]} {
		safelog $slave "could not create $dir"
		error "permission denied: could not open $fileName" \
		      "can't create local directory $dir for $slave"
	    }
	} elseif {![file isdirectory $dir]} {
	    error "permission denied: could not open $fileName" \
		  "local directory $dir for $slave is a file"
	}

	# Ignore any leading pathname components in the requested file
	# name, so we won't be fooled into opening a file outside of
	# the prescribed directory:

	set real [file join $dir [file tail $fileName]]

	# Check if the file exists. If it doesn't, check whether creating
	# it would push us over the limit on the number of local persistent
	# files in the directory. Note that we must do this by globbing so
	# that the file count limit *per directory* is respected even when
	# directories are shared among Tclets:

	if {![file exists $real]} {
	    set exists 0
	    set globPat [file join $dir *]
	    set existingCounter [llength [glob -nocomplain $globPat]]
	    ISet $slave persistentFileCounter $existingCounter
	    if {[catch {cfg::getConstant $slave $policy persist\
		    storedFilesLimit} storedFilesLimit]} {
		set storedFilesLimit $StoredFilesLimit
	    }
	    if {$existingCounter >= $storedFilesLimit} {
		error "permission denied: file count limit" \
			"local file count limit $storedFilesLimit for $slave: \
			have $existingCounter files in $globPat"
	    }
	} else {
	    set exists 1
	}

	# Try to open the file. Use the hidden open command to actually
	# do the opening. This is more efficient than opening it in the
	# master and then transferring the channel to the slave:

	if {[catch {set fd [interp invokehidden $slave open $real $mode]} \
		   msg]} {
	    error "permission denied: can not open $fileName" \
		  "slave $slave can not open \"$real\" in mode $mode: $msg"
	}

	# Check the current size of the file. If it is bigger than the
	# file size limit, allow the Tclet to write into all areas of the
	# file but not to make the file bigger.

	set size [file size $real]
	if {[catch {cfg::getConstant $slave $policy persist fileSizeLimit}\
		fileSizeLimit]} {
	    set fileSizeLimit $FileSizeLimit
	}
	if {$size > $fileSizeLimit} {
	    set fileSizeLimit $size
	    safelog $slave \
		"file size \"$real\" is $size, bigger than $fileSizeLimit"
	}
	ISet $slave FileSizeLimit${fd} $fileSizeLimit

	# Remember the count of open channels for this Tclet, and record
	# that this channel belongs to the persistent file facility:

	ISet $slave openChannelCounter \
		[expr {1 + [iget $slave openChannelCounter]}]
	ISet $slave PersistentFile${fd} $real

	safelog $slave "opened local persistent file \"$real\" in mode $mode"

	return $fd
    }

    # This procedure services the close alias:

    proc closeAlias {slave policy fd} {
	# First attempt to close the channel. Use the hidden close command
	# to actually close the channel without transferring it to the
	# master interpreter:

	if {[catch {interp invokehidden $slave close $fd} msg]} {
	    error "permission denied" \
		  "slave $slave failed to close $fd: $msg"
	}

	# If this is a channel for a local persistent file, decrement
	# the count of open channels for the Tclet:

	if {[iexists $slave PersistentFile${fd}]} {
	    IUnset $slave FileSizeLimit${fd}
	    IUnset $slave PersistentFile${fd}
	    ISet $slave openChannelCounter \
		    [expr {[iget $slave openChannelCounter] - 1}]
	}
	return
    }

    # This procedure services the file alias:

    proc fileAlias {slave policy args} {
	# Insist on having at least an operation specified:

	if {[llength $args] == 0} {
	    error "permission denied" \
		  "must specify an operation for \"file\" command"
	}
	set operation [lindex $args 0]

	# Interpose on the "delete" operation

	if {[string equal "delete" $operation]} {
	    set fname [file join [iget $slave PersistentFileDir] \
			   [file tail [lindex $args 1]]]
	    file delete $fname

	    safelog $slave "deleted local persistent file \"$fname\""

	    return
	}

	# Forward other operations to the implementation of
	# the default file alias:

	eval ::safe::Subset \
		[list $slave file \
			 "^(dir.*|join|root.*|ext.*|tail|path.*|split)\$"] \
		$args
    }

    # This procedure services the puts alias:

    proc putsAlias {slave policy args} {
	if {[llength $args] > 3} {
	    error "invalid arguments" \
		  "slave $slave called puts with arguments: \"$args\""
	}

	set newline "\n"
	if {[string match "-nonewline" [lindex $args 0]]} {
	    set newline ""
	    set args [lreplace $args 0 0]
	}
	if {[llength $args] == 1} {
	    set fd stdout
	    set tell 0
	    set string [lindex $args 0]$newline
	} else {
	    set fd [lindex $args 0]
	    set tell [interp invokehidden $slave tell $fd]
	    set string [lindex $args 1]$newline
	}

	# Check if this is one of the channels for a local persistent file.
	# If it is, compute the size of the string and error out if
	# producing it on the file would exceed the file size limit:

	if {[iexists $slave PersistentFile${fd}]} {
	    set size [expr {$tell + [string length $string]}]
	    set limit [iget $slave FileSizeLimit${fd}]
	    if {$size > $limit} {
		error "permission denied" \
		      "slave $slave tried to exceed file size limit\
		      ($size (=$tell+strlen) > $limit)"
	    }
	    safelog $slave "new file size for $fd: $size"
	}
	interp invokehidden $slave puts -nonewline $fd $string
    }

    # This procedure services the tell alias. We need this alias because
    # we hid the original tell command; we do that because we need to be
    # able to call a trustworthy tell in the context of the slave. This
    # alias just redirects to that hidden command, so the slave can also
    # use tell in the Tclet:

    proc tellAlias {slave policy fd} {
	interp invokehidden $slave tell $fd
    }

    # This procedure services the seek alias. We need this alias because
    # the slave should not be allowed to seek on local persistent files
    # in order to increase the size of the file at will.

    proc seekAlias {slave policy fd offset {origin current}} {
	# If the channel is for a local persistent file, determine if
	# the seek would push the file size beyond the file size limit.
	if {![string is integer -strict $offset]} {
	    return -code error "invalid offset \"$offset\", must be an integer"
	}

	if {[iexists $slave PersistentFile${fd}]} {
	    set fileSizeLimit [iget $slave FileSizeLimit${fd}]
	    set current [interp invokehidden $slave tell $fd]
	    switch -- $origin {
		"current" {
		    set location [expr {$current + $offset}]
		    if {$location > $fileSizeLimit} {
			error "permission denied" \
			      "slave $slave tried to seek too far on $fd"
		    }
		}
		"end" {
		    interp invokehidden $slave seek $fd 0 end
		    set location [expr {[interp invokehidden tell $fd] \
			    + $offset}]
		    if {$location > $fileSizeLimit} {
			interp invokehidden $slave seek $fd $current start
			error "permission denied" \
			      "slave $slave tried to seek too far on $fd"
		    }
		}
		"start" {
		    if {$offset > $fileSizeLimit} {
			error "permission denied" \
			      "slave $slave tried to seek too far on $fd"
		    }
		}
	    }
	}

	# If we got here, it's OK to actually do the seek:

	interp invokehidden $slave seek $fd $offset $origin
    }


    # This procedure services the glob alias:

    proc globAlias {slave policy args} {

	if {[llength $args] == 0} {
	    error "wrong # args: should be \"glob pattern ?pattern ...?\""
	}

	set dir  [iget $slave PersistentFileDir]
	set list {}

	foreach f [glob -nocomplain -tails -directory $dir -- *] {
	    lappend list $f
	}

	set res {}

	foreach f $list {
	    foreach pattern $args {
		if {[string match $pattern $f]} {
		    lappend res $f
		    break
		}
	    }
	}
	return [lsort -unique $res]

    }
}
