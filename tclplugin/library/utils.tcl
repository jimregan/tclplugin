# utils.tcl --
#
#	Some general utilities which does not fit anywhere else
#       (used by the Tcl plugin but could be useful anywhere).
#
# Copyright (c) 1997 Sun Microsystems, Inc.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# SCCS: @(#) utils.tcl 1.3 97/12/02 14:41:42

# Nb: if the version below is changed to reflect changes in APIs
#     the version number of plugtcl should be changed too because
#     plugtcl 'includes' this package.

package provide tcl::utils 1.0

package require log 1.0

# Part of this package is defined in C side cmds:
catch {load {} tcl::utils-C}
if {[catch {package require tcl::utils-C 1.0} msg]} {
    log {} "Can't get C side utils, probable wrong Tcl version/shell ($msg)"\
	    WARNING
    # Dummy replacements for C utilities:
    namespace eval ::tcl {
	proc quote str {return str}
    }
}

namespace eval ::tcl {

    namespace export autoReset cequal byte randomBytes \
	    isBoolean isInteger isFloat isList \
	    getBoolean getInterger getFloat \
	    isAlphaWord \
	    quote \
	    ;

    # A clean (does not delete some of the defined procs) and
    # complete (remove the unloaded packages infos) version of auto_reset

    proc autoReset {} {
	global auto_execs auto_index auto_oldpath
	catch {unset auto_execs}
	catch {unset auto_index}
	catch {unset auto_oldpath}
	# Remove package information for un-required packages
	foreach pkg [package names] {
	    if {[package provide $pkg]=={}} {
		package forget $pkg
	    }
	}
    }

    # return 1 if 2 strings are equal
    
    proc cequal {s1 s2} {
	expr {[string compare $s1 $s2]==0}
    }

    proc byte {char} {
	if {[string length $char]!=1} {
	    error "\"$char\" is not a single char"
	}
	binary scan $char c v
	expr {($v+0x100)%0x100}
    }


    # Generate a (pseudo) random bytes sequence

    proc randomBytes {count} {
	# We try getting res to be the empty byte array
	# (and not the empty string, should be different in 8.1 ?)
	set res [binary format a0 ""]
	for {} {$count > 0} {incr count -1} {
	    append res [binary format c [expr {int(256*rand())}]]
	}
	return $res
    }

    # The function below safely determines if a value
    # is of the requested type and returns the corresponding values.
    # Please be very carfull if you think you have to change a definition.

    # This function prepares strings for expression testing
    # it removes (trim) spaces and tabs around the string
    # and then call quote to make sure special chars (like \0)
    # will get noticed and will generate an error in the isXXX
    # proc which use expr. (was determined to be needed
    # by the test suite)

    proc Munge {value} {
	# only trim spaces, \r, \n ... might be 'dangerous'
	quote [string trim $value " \t"]
    }

    proc isBoolean {value} {
	expr {![catch {expr {([Munge $value])?1:0}}]}
    }

    proc getBoolean {value {errorValue 1}} {
	if {[catch {expr {([Munge $value])?1:0}} res]} {
	    return $errorValue
	} else {
	    return $res
	}
    }

    proc isInteger {value} {
	expr {![catch {expr {~[Munge $value]}}]}
    }

    proc getInteger {value {errorValue 0}} {
	if {[catch {expr {~[Munge $value]}} res]} {
	    return $errorValue
	} else {
	    return [expr {int($value)}]
	}
    }

    proc isFloat {value} {
	expr {![catch {expr {double($value)}}]}
    }

    proc getFloat {value {errorValue 0.0}} {
	if {[catch {expr {double($value)}} res]} {
	    return $errorValue
	} else {
	    return $res
	}
    }

    proc isList {value} {
	expr {![catch {llength $value}]}
    }

    proc isAlphaWord {value} {
	if {[string first \0 $value] >= 0} {
	    return 0
	}
	regexp -nocase -- {^[a-z0-9]+$} $value
    }

    proc getAlphaWord {value {errorValue {}}} {
	if {[isAlphaWord]} {
	    return $value
	} else {
	    return $errorValue
	}
    }


} ; # end of namespace eval ...

