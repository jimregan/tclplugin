# unsafe.tcl --
#
#	Installs the "Unsafe" features set when requested by policies.
#
# AUTHORS:      Jacob Levy                      Laurent Demailly
#
# Copyright (c) 1996-1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
# Copyright (c) 2004 ActiveState Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# RCS:  @(#) $Id$

# We provide the "unsafe" features set:
package provide safefeature::unsafe 1.2

# Common feature tools (and dependencies):
package require safefeature 1.0

# We require the configuration package:
namespace eval ::safefeature::unsafe {
    # Our parent will set us up:
    [namespace parent]::setup [namespace current]

    # Public entry point:
    namespace export install
}

# This procedure restores the unsafe features that were hidden in
# a Tclet in the Safe Base and by other policies, as allowed by
# the configuration for the policy using this feature:

proc ::safefeature::unsafe::install {slave policy arglist} {
    variable nsc

    safelog $slave "starting installation of the UNSAFE features" SECURITY

    # If the policy allows this, mark the interpreter as trusted, to
    # disable the hard-wired checks for safety in Tcl and Tk core. The
    # default is to disallow it if the policy didn't allow it itself:

    if {![catch {set markTrusted [::cfg::getConstant $slave $policy \
				      markTrusted markTrusted]}]} {
	if {$markTrusted} {
	    interp marktrusted $slave
	}
    }

    # Restore all the commands that we hid previously, removing any
    # commands with the same name in the process, as allowed by the
    # policy:

    foreach cmd [interp hidden $slave] {
	# If we are not allowed to restore this command by this policy
	# then just skip it:

	if {![cfg::allowed $slave $policy restoreCommands $cmd]} {
	    continue
	}
	catch {interp eval $slave [list rename $cmd {}]}
	interp expose $slave $cmd
    }

    # Restore important scalar variables in the slave as allowed by
    # the policy. We use a default list if the application didn't
    # set a list of variables that it wants us to restore:

    set varlist {
	auto_path tcl_library tk_library tcl_pkgPath argc argv argv0
    }
    catch {set varlist $::cfg::RestoreVariables}
    foreach var $varlist {
	if {[info exists ::$var]
	    && [::cfg::allowed $slave $policy restoreVariables $var]} {
	    interp eval $slave [list set ::$var [set ::$var]]
	}
    }

    # Restore important array variables in the slave as allowed by
    # the policy. We use a default list if the application didn't
    # set a list of variables that it wants us to restore:

    set varlist {env auto_index tcl_platform}
    catch {set varlist $::cfg::RestoreArrayVariables}
    foreach var $varlist {
	if {[info exists ::$var]
	    && [::cfg::allowed $slave $policy restoreArrayVariables $var]} {
	    if {[catch {interp eval $slave [list unset ::$var]} msg]} {
		safelog $slave "unset ::$var: $msg" WARNING
	    }
	    interp eval $slave \
		[list array set ::$var [array get ::$var]]
	}
    }

    # Reset the unknown mechanism to notice that auto_path may have
    # changed:

    if {[catch {interp eval $slave ::tcl::autoReset} msg]} {
	safelog $slave "failed to auto_reset: $msg" WARNING
    }

    # Add master alias
    foreach alias {
	master
    } {
	if {[allowed $slave $policy aliases $alias]} {
	    interpAlias $slave $alias ${nsc}::${alias}Alias $policy
	} else {
	    safelog $slave "denied alias \"$alias\" for $policy"
	}
    }

    # Do extra logging because of the potential danger of this feature:
    safelog $slave "successfully installed UNSAFE features" SECURITY
}

proc ::safefeature::unsafe::masterAlias {slave policy args} {
    safelog $slave "requested master eval of $args"
    if {[catch {uplevel #0 $args} msg]} {
	error $msg "giving full error"
    } else {
	return $msg
    }
}
