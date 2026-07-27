# log.tcl --
#
#	A general logging package
#       (used by the Tcl plugin).
#
# ORIGINAL AUTHORS:	Jacob Levy			Laurent Demailly
#
# Copyright (c) 1996-1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# SCCS: @(#) log.tcl 1.24 97/12/02 19:23:07
# RCS:  @(#) $Id$

package provide log 1.1

namespace eval ::log:: {
    
    namespace export log setup refreshAttributes truncateStr

    # Set the behavior of different severity tags:

    variable attributes {
	DEBUG    {}
	NOTICE   {}
	ERROR    {-background orange -foreground black}
	WARNING  {-background yellow -foreground black}
	SECURITY {-background red -foreground blue}
	all {-lmargin2 24p -tabs {[expr {[winfo width $Dest.f.msg]-10}] right}}
    }


    # Filter proc. User redefinable:
    # (for instace use proc filter {name msg type} {expr {$type=="DEBUG"}}
    #  to remove debuging informations)
    proc filter {name msg type} {
	# never filter anything out by default:
	return 0
    }

    # Time stamping proc. Users can redefine it at will:

    proc TS {} {
	clock format [clock seconds] -format "%h %d %T";
    }

    variable DoLog 0

    variable IsChannel
    variable Dest

    proc setup {destname {title "Log"}} {
	variable DoLog
	variable IsChannel
	variable Dest
	if {![catch {fconfigure $destname}]} {
	    # We have a channel !
	    set IsChannel 1
	    set DoLog 1
	    set Dest $destname
	    log {} "Pid [pid], Log Started ($Dest)"
	    return 
	}
	switch -glob -- $destname {
	    "suspend" {
		log {} "Logging suspended"
		set DoLog 0
		return 
	    }
	    "stop" {		
		if {$DoLog} {
		    set DoLog 0
		    if {$IsChannel} {
			log {} "Logging stopped" NOTICE
			close $Dest
		    } else {
			if {[winfo exist $Dest]} {
			    destroy $Dest;
			}
		    }
		    unset Dest
		}
	    }
	    "resume" {
		if {[info exists Dest]} {
		    set DoLog 1
		    log {} "Logging resumed"
		    return
		} else {
		    error "No logging destination to resume"
		}
	    }
	    "clear" {
		if {($DoLog)} {
		    if {!$IsChannel} {
			WindowClear
			log {} "Log cleared" NOTICE
		    }
		}
	    }
	    ".*" {
		set Dest $destname
		WindowSetup
	    }
	    "window" {
		set Dest .log
		catch {destroy $Dest} 
		toplevel $Dest -class Log
		wm title $Dest $title
		wm iconify $Dest
		# wm geometry $Dest +10+20

		WindowSetup
	    }
	    default {
		# We have a filename -> channel!
		set IsChannel 1
		set DoLog 1
		set Dest [open $destname a+]
	    	fconfigure $Dest -buffering line
		log {} "Pid [pid], Log Started ($destname,$Dest)"
		return 
	    }
	}
    }

    proc WindowSetup {} {
	variable Dest
	variable DoLog
	variable IsChannel

	set DoLog 1
	set IsChannel 0

	menubutton $Dest.mb -direction below -menu $Dest.mb.m\
		-text "Log" -relief raised -indicator 1
	menu $Dest.mb.m
	$Dest.mb.m add command -label "Suspend" \
		-command [list [namespace current]::setup suspend]
	$Dest.mb.m add command -label "Resume" \
		-command [list [namespace current]::setup resume]
	$Dest.mb.m add command -label "Save..." \
		-command [list [namespace current]::Save]
	$Dest.mb.m add separator
	$Dest.mb.m add command -label "Clear" \
		-command [list [namespace current]::setup clear]
	$Dest.mb.m add separator
	$Dest.mb.m add command -label "Close" \
		-command [list [namespace current]::setup stop]

	pack $Dest.mb -side top

	MkTxtWin $Dest.f
	pack $Dest.f -fill both -expand 1 -side bottom
	bind $Dest.f.msg <Configure> [namespace current]::refreshAttributes
	bind $Dest.f.msg <Destroy>   [list [namespace current]::setup stop]

	log {} "Pid [pid], Log Started (GUI)"
    }

    proc WindowClear {} {
	variable Dest
	set w $Dest.f.msg
	$w configure -state normal
	$w delete 1.0 end
	$w configure -state disabled
    }

    proc Save {} {
	variable Dest

	set w $Dest
	$w configure -cursor watch
	set defn [clock format [clock seconds] -format "%d%m%Y"]
	set fname [tk_getSaveFile \
		-initialfile "$defn.log" \
		-defaultextension ".log" \
		-filetypes { {"Log files" {.log}} {"Text" {.txt}}\
		             {"All files" {*}} } \
		-title "Save Log..." \
		-parent $w]
	$w configure -cursor {}
	if {[string length $fname]==0} return
	
	set f [open $fname w]
	log {} "Saved in $fname..."
	puts -nonewline $f [$Dest.f.msg get 1.0 end-1c]
	close $f
    }

    proc refreshAttributes {} {
	variable attributes
	variable Dest
	foreach {tag value} $attributes {
	    RegTag $Dest.f.msg $tag [subst $value]
	}
    }

    # Make a scrollable text widget (adapted from NetPlug by Laurent Demailly)

    proc MkTxtWin {w} {
	frame $w
	text $w.msg -yscrollcommand "$w.scroll set" \
		-setgrid true -height 24 -width 80 -wrap word
	scrollbar $w.scroll -command "$w.msg yview" -width 12
	pack $w.scroll -side right -fill y
	pack $w.msg -side left -fill both -expand yes
	$w.msg configure -state disabled
	return $w.msg
    }

    # (Re)register a tag :

    proc RegTag {w tagname attribs} {
	# save current tag positions
	set rg [$w tag ranges $tagname]
	# delete tag (so we start from default)
	$w tag delete  $tagname
	# configure tag
	eval "$w tag configure $tagname $attribs"
	# restore tag positions
	if {[string compare "" $rg]} {eval "$w tag add $tagname $rg"}
    }
    
    # Default max log

    variable max 500

    proc addTxt {txt taglist} {
	variable Dest
	variable max 
	
	set w $Dest.f.msg

	# Allow changes.

	$w configure -state normal

	lappend taglist all

	$w insert end $txt $taglist

	# Keep only last N lines.

	$w delete 1.0 end-${max}l

	# Adjust view position.
	$w yview -pickplace end-2c

	# Prevent editing.
	$w configure -state disabled

    }

    variable strTruncLen 256
    
    proc LogStr {name msg type} {
	variable strTruncLen
	# Limit the line length.
	format {[%s] %s : %s %s} \
		[TS] \
		$name \
		[truncateStr $msg $strTruncLen]\
		"\t$type\n"
    }

    # Log a message for slave 'name' with severity 'severity'.

    proc log {name msg {type NOTICE}} {
	variable DoLog
	variable IsChannel
	variable Dest

	# Do not do anything if we are not logging.

	if {!$DoLog} {
	    return
	}

	# Do nothing if the filter proc wants us to skip this entry

	if {[filter $name $msg $type]} {
	    return
	}

	set what [LogStr $name $msg $type]

	if {$IsChannel} {
	    catch {puts -nonewline $Dest $what}
	} else {
	    catch {addTxt $what $type}
	}
    }

    # Utility function to produce nice not too long strings :
    proc truncateStr {str {max 79}} {
	# NULs would be lost with regsub, replace them with '\'+'0'
	set str [join [split $str \0] {\0}]
	# 'compress' the stuff a bit
	regsub -all "\[\n\t \]+" $str { } str;
	regsub -all " \}" $str "\}" str;
	regsub -all "\{ " $str "\{" str;
	set lg [string length $str];
	if {$lg<=$max} {
	    return $str;
	} else {
	    return "[string range $str 0 [expr {3*($max/4)-3}]]...[string range $str [expr {$lg-$max/4}] end]"
	}
    }

}
