# feature.tcl --
#
#	Common parts and tools needed by all the installable
#       features.
#
# CONTACT:      sunscript-plugin@sunscript.sun.com
#
# AUTHORS:      Jacob Levy                      Laurent Demailly
#               jyl@eng.sun.com                 demailly@eng.sun.com
#               jyl@tcl-tk.com                  L@demailly.com
#
# Please contact us directly for questions, comments and enhancements.
#
# Copyright (c) 1997 Sun Microsystems, Inc.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# SCCS: @(#) feature.tcl 1.8 97/11/11 21:11:04


# We provide the "safefeature" package
# WARNING: Only the policy package is ever supposed to require
#          this package. package loading here is used as a
#          convenience by the policy mechanism.

# Nb: the version number for the policy package itself and
# the package require safefeature line from policy.tcl need
# to be changed whenever this version here is changed
# because safefeature can not be required directly but only
# through policy and it's init (path problem)

package provide safefeature 1.1

if {[llength [info command ::safe::policy]] == 0} {
    error "the safefeature package should be loaded only by policy"
}

# We rely on the api set provided by policy 1.x (safe base + policy extensions,
# who called us in fact)  {ie mediated error, log, aliasing and invoking}
# we don't do the package require because it must have been installed
# by our loader (policy)
#
# package require policy 1.2

# Likewise, though we need the config parsing functions, we will
# not require it here.
# Nb: the cfg package must have been initialized before features are called
# otherwise cfg::implNs and cfg::slaveNs will certainly not be defined
#
# package require cfg 1.0

# Same for logging
# package require log 1.0

namespace eval ::safefeature {

    # Public entry point:
    namespace export setup importAndCheck checkArgs

    # List of the namespaces from which we need import functions
    # into our child namespaces
    # (empty namespace mean the function is defined in this namespace)

    set importList {
	cfg  {allowed getConstant}
	safe {error interpAlias invokeAndLog}
	log  {log}
	{}   {checkArgs}
    }


    # List of procs in the application specific code that our sub-features
    # might use:

    variable implCmdList {iget iexists ISet IUnset}

    # What is the implNs (will be filled at init time (when policy's
    # initialize this package)

    variable implNs

    # Utility function that import and check that the import actually
    # worked from a source to a destination namespace a given command

    proc importAndCheck {destNs srcNs cmd} {
	namespace eval $destNs [list namespace import ${srcNs}::${cmd}]
	if {[llength [info commands ${destNs}::${cmd}]] == 0} {
	    error "failed import \"$cmd\" from \"${srcNs}::\"\
		    to \"${destNs}::\""
	}
    }


    # Utility function to check if some configure like arguments are
    # in allowed set

    proc checkArgs {allowedList usage flag {withDash 1}} {
	log {} "flag=\"$flag\", withDash=$withDash,\
		allowedList=\"$allowedList\""
	if {$withDash} {
	    if {![string match "-*" $flag]} {
		error "bad option \"$flag\": $usage"
	    }
	    set testFlag [string range $flag 1 end]
	} else {
	    set testFlag $flag
	}
	if {[lsearch -exact $allowedList $testFlag] >= 0} {
	    return $flag
	} else {
	    error "disallowed option \"$flag\": $usage"
	}
    }

    # Init 

    proc init {} {

	# Where the actual implementation (application specific) is
	# The application has to provide this namespace and the "iget"
	# function in it (used in urlIsOk) and the actual implementation
	# for some application specific aliases (like the url features set)

	variable implNs $::cfg::implNs

	# If the iget proc does not yet exist in the slave
	# we get it from the "implNs" 
		
	if {[llength [info commands ::cfg::iget]] == 0} {
	    log {} "Installing iget in ::cfg"
	    importAndCheck ::cfg $implNs iget
	}

	# Now setup ourselves (we want access to common utilities
	# (log, error...) too)
	setup [namespace current]
	
	return $implNs
    }

    # Setup common parts:

    proc setup {namespace} {
	log {} "setting up namespace $namespace"

	variable importList
	variable implCmdList
	variable implNs

	# Where we will install the alias in the slave
	# (for the aliases which implements new functionality and 
	#  hence are added  in a namespace in the target (url features set))

	set slaveNs $::cfg::slaveNs

	foreach {ns cmdList} $importList {
	    if {[string compare $ns ""] == 0} {
		set ns [namespace current]
	    }
	    if {[string compare $ns $namespace] == 0} {
		log {} "setting up $namespace, skipping $cmdList self imports"
		continue
	    }
	    foreach cmd $cmdList {
		importAndCheck $namespace ::$ns $cmd
	    }
	}

	# Transfer a copy of needed variables
	foreach var {implNs slaveNs} {
	    namespace eval $namespace [list variable $var [set $var]]
	}

	# Add the application specific call backs
	foreach cmd $implCmdList {
	    importAndCheck $namespace $implNs $cmd
	}

	# Most functions use "nsc" as a short cut for [namespace current]
	namespace eval $namespace [list variable nsc $namespace]


    }

}
