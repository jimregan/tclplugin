# plugtk.tcl --
#
#	Tool kit utilities for tclets.
#       This is intended to be sourced in each Safe Tk interp of the Plugin
#
# ORIGINAL AUTHORS:      Jacob Levy              Laurent Demailly
#
# Copyright (c) 1996-1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# RCS:  @(#) $Id$

package provide plugtk 1.0

#
# Enhanced error management for Tclets (no new toplevel):
#
package require pluglog 1.0

# A micro (light!) console (could be used outside bgerror)

proc bgerrorConsole {top {borderColor blue}} {
    set w $top.f
    if {![winfo exists $top]} {
	frame $top -bd 3 -relief ridge
	bind $top <1> [list raise $top]
	bind $top <Double-1> [list lower $top]
	frame $w
	text $w.msg -yscrollcommand [list $w.scroll set] -bg white
	scrollbar $w.scroll -command [list $w.msg yview] -width 10
	pack $w.scroll -side right -fill y
	pack $w.msg -side left -fill both -expand yes
	$w.msg tag configure error -foreground red -background white
	$w.msg tag configure syst -foreground green3 -background white
	$w.msg tag configure rest -foreground black -background white
	$w.msg tag configure ok -foreground blue2 -background white
	set wb $top.fb
	frame $wb
	entry $wb.e
	# have an variable with the same name for the history
	global $wb.e
	if {![info exists $wb.e]} {
	    set $wb.e {}
	}
	bind $wb.e <Return> [list bgerrorEval $wb.e $w.msg]
	bind $wb.e <Up> [list bgerrorUp $wb.e]
	bind $wb.e <Down> [list bgerrorUp $wb.e]
	bind $wb.e <Control-p> [list bgerrorUp $wb.e]
	bind $wb.e <Control-n> [list bgerrorUp $wb.e]
	button $wb.b -text "Dismiss" \
		-bd 2 -padx 10 -pady 0 -highlightthickness 0 \
		-command [list place forget $top]

	pack $wb.b -side right
	pack $wb.e -side left -expand 1 -fill x
	pack $wb -fill both -side bottom
	pack $w -expand 1 -fill both -side top
    }
    $top configure -bg $borderColor
    place $top -relx 0 -rely 0 -relwidth 1 -relheight 1
    raise $top
    return $w.msg
}

proc bgerrorEval {e m} {
    global $e
    set what [$e get]
    if {[string length $what] == 0} {
	$m insert end "\n" syst
    } else {
	set $e $what
	$e delete 0 end
	$m insert end "\nEval: " syst
	$m insert end $what rest
	$m insert end " -> " syst
	if {[catch {uplevel #0 $what} res]} {
	    $m insert end $res error
	} else {
	    $m insert end $res ok
	}
    }
    $m see "end-1l linestart"
}

proc bgerrorUp {e} {
    global $e
    set what [$e get]
    $e delete 0 end
    $e insert end [set $e]
    $e xview end
    set $e $what
}


# Actually process bg errors

proc bgerror {errmsg} {
    global errorInfo
    # Log (if log is enabled in the master)
    set errinf [string trim $errorInfo]
    ::pluglog::log "bgerror: $errmsg ($errinf)"
    # Set UI
    set top .bgerror
    set msg [bgerrorConsole $top red]

    # See if we need to skip new lines:

    # We need end-2c to be in front of the last character inserted
    # in the text widget (there is always an 'external' \n at the end...)
    set where [$msg index end-2c]
    if {![string equal $where "1.0"] \
	    && ![string equal [$msg get $where] "\n"]} {
	$msg insert end "\n\n" syst
    }
    # Remember what we want to show the user (error message starting at top)
    set where [$msg index end-1c] ; # don't ask why it's -1c here.

    $msg insert end "An " syst
    $msg insert end "error" error
    $msg insert end " occured during execution of this Tclet:\n" syst
    $msg insert end $errmsg\n ok
    if {[string length $errinf]} {
	$msg insert end "Stack trace:\n" syst
	$msg insert end $errinf rest
    } else {
	$msg insert end "(Empty stack trace)" syst
    }
    $msg yview $where
}

# Set up a hot key

bind all <Control-Shift-C> {
    bgerrorConsole .bgerror
    break
}

