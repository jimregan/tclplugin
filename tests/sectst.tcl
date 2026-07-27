#
# Brute force security checker for Tcl
#
# by Laurent Demailly
#
# RCS:  @(#) $Id$

lappend auto_path ..

catch {no_such_command}
catch {package require no_such_package}

foreach pkg [package names] {
    if {[catch {package require $pkg} msg]} {
	puts "warning, could not require package $pkg: $msg"
    }
}


catch {no_such_command}
catch {package require no_such_package}

foreach pkg [package names] {package require $pkg}


foreach cmd [array names auto_index] {catch {$cmd}}
set targets [info procs]
proc addtolist {namespace list} {
    foreach cmd $list {
	lappend ::targets ${namespace}::$cmd
    }
}
proc addchild {} {
    foreach child [uplevel namespace children] {
	namespace eval $child {::addtolist [namespace current] [info procs]}
	namespace eval $child ::addchild
    }
}
addchild
puts "targets: $targets"

# nasty strings to try :
variable tryList {
    {; BUG}
    {[BUG]}
    {\x5bBUG\x5b}
    {\\x5bBUG\\x5b}
}

lappend tryList "0\nBUG\n"

proc mklist {length pos what default} {
    set res {}
    for {set i 0} {$i<$length} {incr i} {
	if {$pos==$i} {
	    lappend res $what
	} else {
	    lappend res $default
	}
    }
    return $res
}

proc try {cmd list} {
    for {set i 1} {$i<5} {incr i} {
	for {set j 0} {$j<$i} {incr j} {
	    foreach try $list {
		set what "$cmd [mklist $i $j $try 0]"
		set ::_LAST_TRY $what
		catch {eval $what}
	    }
	}
    }
}

proc BUG {args} {
eate set f [open /tmp/BUGS a]
    puts stderr "POTENTIAL BUG!!! $::_LAST_TRY"
}

# If log is not there:

#if {[info commands log]==""} {
#    proc log {str} {puts $str}
#}

#proc buggy {a b c d} {
#  if $c {
#     puts cool
#  } else {
#     puts eleet
#  }
#}

foreach cmd $targets {
    try $cmd $tryList
}

puts stderr "NO MORE BUGS FOUND!"

