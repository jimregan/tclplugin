# policy.tcl --
#
#	A security policy mechanism.
#
# CONTACT:		sunscript-plugin@sunscript.sun.com
#
# AUTHORS:		Jacob Levy			Laurent Demailly
#			jyl@eng.sun.com			demailly@eng.sun.com
#			jyl@tcl-tk.com			L@demailly.com
#
# Please contact us directly for questions, comments and enhancements.
#
# Copyright (c) 1996-1997 Sun Microsystems, Inc.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# SCCS: @(#) policy.tcl 1.42 98/01/15 15:05:32

# This file provides the policy package:

package provide policy 1.3

# We need the Safe Base in Tcl core 8.0:

package require Tcl 8.0

# First ensure that the ::safe namespace exists along with
# the needed procs by making the safe:: base eventually load 
# if not yet there:

::safe::setLogCmd

# We use the external improved logging mechanism

package require log 1.0

# We require the configuration mechanism
# (supposedly already initialized at this point
#  or at least before calling any of the API exported here)

package require cfg 1.0

# New procs definition

namespace eval ::safe {

    # Procs we export:

    namespace export policy installPolicy initPolicies\
	    error interpAlias invokeAndLog getattr

    # What we import:
    
    namespace import ::cfg::allowed ::log::log


    # Place to set information about an error that shall not
    # go to the slave. Used by "safe::error"

    variable errorMessage

    # Where do we find the security features sets ? 
    # By auto loading. We expect the user of that package
    # to have setup the auto_path in order to find the safetcl
    # features. Usually there is nothing to do as the safetcl/
    # are installed as a sibling of the tcl_library directory
    # whose parent dir is already in the auto_path.

    # This procedure initializes the policy mechanism
    # mainly by installing the dependent safetcl/features.
    # It must be called before using policies

    proc initPolicies {} {
	log {} "policies initialization" NOTICE

	# We need to have the common safetcl/features
	# loaded and init'ed (they will for instance define
	# iget in the cfg:: namespace so "getattr" works)

	# Nb: the version number for policy need to be changed
	# whenever the required version here is changed, and
	# this required version needs to be changed when the
	# provided version in safefeature changes because
	# safefeature can not be required directly but only
	# through policy and it's init (path problem)

	package require safefeature 1.1
	::safefeature::init

    }

    # This returns the token for the slave's policy
    # it uses and extend the mecanism of tcl8.0/library/safe.tcl

    proc PolicyName {slave} {
	return "[InterpStateName $slave](policy)"
    }

    # Install the policy mechanism for the given slave
    # and 'save' important commands that features might later
    # need as hidden (original) commands and install simple
    # aliases instead

    proc installPolicy {slave} {

	# this install a "logged/mediated" alias

	interpAlias $slave policy [namespace current]::policy

	# Hide the following important commands a default generic
	# alias for now (take the list from cfg's):
	foreach alias $::cfg::toHideCmdsList {
	    interp hide $slave $alias
	    interpAlias $slave $alias {}
	}

	# return the slave name (usefull for piping commands)

	return $slave
    }

    # This is the entry point called from the "policy" alias in the safe
    # interpreter, to install the policy into the requesting interpreter.

    proc policy {slave args} {

	set policy [lindex $args 0]

	# If no policy name is provided, the slave wants to know what
	# policy is loaded, if any. Tell them:

	set pname [PolicyName $slave]

        if {[string compare {} $policy] == 0} {
	    if {[Exists $pname]} {
		return [Set $pname]
	    }
	    return
	}

	# If a policy is already loaded:

	if {[Exists $pname]} {
	    set current [Set $pname]
	    if {[string compare $args $current] == 0} {
		# same arguments, nothing to do
		return $current
	    } else {
		# different, no changes allowed, error out:
		error "security policy \"$current\" already loaded"
	    }
	}

	# Check whether the policy is allowed

	if {[catch {allowed $slave $::cfg::userConfig "policies" $args} res]} {
	    error   "permission denied"\
		    "error assessing trust for policy \"$args\": $res"
	}
	if {!$res} {
	    error "permission denied" "trust.cfg said no to policy \"$args\""
	}

	# We passed the trust check, from now, either the
	# policy will load ok or the slave will be killed

	# Remember the (about to be) loaded policy, just in case
	# somehow policy is called again, in the policy init procedure.

	Set $pname $args

	# Call the installer to install all requested features into the
	# Tclet as specified by the policy specification. If we get an
	# error this is fatal for the slave, because it can be in an
	# undefined or unsafe state because it was only partially
	# initialized.

	if {[catch {InstallFeatures $slave $policy $args} num]} {
	    log $slave \
		"InstallFeatures $policy $args failed : $num ($::errorInfo),\
		killing slave" SECURITY
	    SaveErrorInfo
	    interpDelete $slave
	    # A critical error occured, sign of probably mis-configuration
	    # if the application has a function to NotifyError we will use it
	    if {[catch {NotifyError "Features Install"\
		    "Failed for policy \"$args\": $num\
		    \nCheck your installation and configuration\
		    ($::cfg::configDir)\n"} msg]} {
		log $slave "could not NotifyError: $msg" WARNING
	    }
	    error "failed to install features for policy $policy" "dead interp"
	}

	if {$num == 0} {
	    # No features have been installed, let the slave know
	    # (so they have a chance to try something else)
	    Unset $pname
	    error "no features installed"
	}

	# At this point the policy is loaded in the slave.

	log $slave "policy \"$args\" loaded" SECURITY

	return [Set $pname]
    }


    # This procedure installs the features requested by a policy into
    # the Tclet.

    proc InstallFeatures {slave policy arglist} {
	
	set num 0
	# The overall features list is saved in the cfg:: namespace
	# (set from config/<application>.cfg)

	foreach feature $::cfg::featuresList {
	    if {[allowed $slave $policy "features" $feature]} {
		log $slave "installing feature $feature for policy $policy"
		
		# If an error occur, this is a bad sign, for security
		# reason we'd rather kill the slave, so we don't catch
		# the package require here: (and thus 'policy' will
		# kill the slave for us)
		package require safefeature::${feature}

		# The feature is allowed by the policy and is supposed
		# to exist (passed the require stage), if it fails now
		# the slave will also be killed (too bad)

		::safefeature::${feature}::install $slave $policy $arglist

		incr num

	    } else {
		log $slave "disallowing feature $feature for policy $policy"
	    }
	}
	return $num
    }




    # Shortcut for alias setup in a slave + common error
    # interception , logging using InterpInvokeAlias.

    proc interpAlias {slave nameInSlave nameInMaster args} {
	log $slave "new alias: \"$nameInSlave\" -> (invoke) \"$nameInMaster $args\""
	set previous [interp alias $slave $nameInSlave]
	if {[string compare $previous ""]} {
	    log $slave "replacing previous alias: \"$previous\""
	}
	interp alias $slave $nameInSlave\
		{} [namespace current]::InterpInvokeAlias\
		$slave $nameInSlave $nameInMaster $args
    }

    # Return a cleaned up error message to the slave, so that it does
    # not get detailed error information from the master:

    proc ReturnError {msg} {
	SaveErrorInfo

	# Discard the error information and overwrite it:

	return -code error -errorinfo $msg $msg
    }

    # save the errorInfo, unless there is one already

    proc SaveErrorInfo {} {
	if {[string compare [set [namespace current]::errorInfo] ""] == 0} {
	    global errorInfo
	    set [namespace current]::errorInfo $errorInfo
	}
    }

    proc ResetErrors {} {
	variable errorMessage
	variable errorInfo

	set errorMessage ""
	set errorInfo ""
    }

    # Mediate all the aliases through a common interface to prevent
    # errorInfo from being transmitted to the slave and to do some logging.

    proc InterpInvokeAlias {slave alias command argsList args} {
	ResetErrors
	# Check if we want the generic alias (which just invokes
	# the hidden command of the same name in the slave)
	if {[string compare $command {}] == 0} {
	    if {[catch {eval interp invokehidden [list $slave]\
		    $alias $argsList $args} res]} {
		log $slave "error in slave while executing \"$alias $args\":\
			$res" ERROR
		ReturnError $res
	    }
	} else {
	    if {[catch {uplevel #0 $command [list $slave] $argsList $args} res]} {
		variable errorMessage
		if {[string compare $errorMessage ""] == 0} {
		    # no special error message was set,
		    # the current message is maybe unsafe
		    # We check if its a direct argument mismatch tough:
		    if {([regexp {^no value given for parameter "[^"]+"} $res\
			    safem]) || ([regexp {too many arguments$} $res\
			    safem])} {
			log $slave "probable slave's syntax error: $res\
				-> $safem ($command $argsList $args)" ERROR
			set res $safem
		    } else {
			log $slave "unexpected in\
				\"$command $argsList $args\" ($alias): $res"\
				ERROR
			set res "error"
		    }
		} else {
		    log $slave "$errorMessage ($command $argsList $args\
			    ($alias): $res)" ERROR
		}
		ReturnError $res
	    }
	}
	log $slave "$command $argsList $args ($alias) -> $res" NOTICE
	return $res
    }

    # Generate an error that will be caught by InterpAlias
    # and save additional message/info so it can be logged.

    proc error {msg {more_msg ""}} {
	variable errorMessage;
	if {[string compare $more_msg ""] == 0} {
	    set more_msg "in \"[info level -1]\"";
	}
	set errorMessage $more_msg
	return -code error $msg
    }

    proc invokeAndLog {slave command args} {
	if {[catch {uplevel ::interp invokehidden $slave $command $args} \
		   res]} {
	    error $res "invoking $command $args"
	}
	log $slave "$command $args -> $res" NORMAL
	return $res
    }

    # Redefine the Logging from the safe base:
    # we ignore the previous mechanism for the 
    # more powerfull ::log::

    rename Log LogOld
    proc Log {slave msg {type ERROR}} {log $slave $msg $type}

}
