##
## Copyright 1996-8 Jeffrey Hobbs, jeff.hobbs@acm.org
##
## Based off previous work for TkCon
##

namespace eval ::Utility {;

## Protos
namespace export -clear *

# get_opts --
#
#   Processes -* named options, with or w/o possible associated value
#   and returns remaining args
#
# Arguments:
#   var		variable into which option values should be stored
#   arglist	argument list to parse
#   optlist	list of valid options with default value
#   typelist	optional list of option types that can be used to
#		validate incoming options
#   nocomplain	whether to complain about unknown -switches (0 - default)
#		or not (1)
# Results:
#   Returns unprocessed arguments.
#
;proc get_opts {var arglist optlist {typelist {}} {nocomplain 0}} {
    upvar 1 $var data

    if {![llength $optlist] || ![llength $arglist]} { return $arglist }
    array set opts $optlist
    array set types $typelist
    set i 0
    while {[llength $arglist]} {
	set key [lindex $arglist $i]
	if {[string match -- $key]} {
	    set arglist [lreplace $arglist $i $i]
	    break
	} elseif {![string match -* $key]} {
	    break
	} elseif {[string match {} [set akey [array names opts $key]]]} {
	    set akey [array names opts ${key}*]
	}
	switch [llength $akey] {
	    0		{ ## oops, no keys matched
		if {$nocomplain} {
		    incr i
		} else {
		    return -code error "unknown switch '$key', must be:\
			    [join [array names opts] {, }]"
		}
	    }
	    1		{ ## Perfect, found just the right key
		if {$opts($akey)} {
		    set val [lrange $arglist [expr {$i+1}] \
			    [expr {$i+$opts($akey)}]]
		    set arglist [lreplace $arglist $i [expr {$i+$opts($akey)}]]
		    if {[info exists types($akey)] && \
			    ([string compare none $types($akey)] && \
			    ![validate $types($akey) $val])} {
			return -code error "the value for \"$akey\" is not in\
				proper $types($akey) format"
		    }
		    set data($akey) $val
		} else {
		    set arglist [lreplace $arglist $i [expr {$i+$opts($akey)}]]
		    set data($akey) 1
		}
	    }
	    default	{ ## Oops, matches too many possible keys
		return -code error "ambiguous option \"$key\",\
			must be one of: [join $akey {, }]"
	    }
	}
    }
    return $arglist
}

# get_opts2 --
#
#   Process options into an array.  -- short-circuits the processing
#
# Arguments:
#   var		variable into which option values should be stored
#   arglist	argument list to parse
#   optlist	list of valid options with default value
#   typelist	optional list of option types that can be used to
#		validate incoming options
# Results:
#   Returns unprocessed arguments.
#
;proc get_opts2 {var arglist optlist {typelist {}}} {
    upvar 1 $var data

    if {![llength $optlist] || ![llength $arglist]} { return $arglist }
    array set data $optlist
    array set types $typelist
    foreach {key val} $arglist {
	if {[string match -- $key]} {
	    set arglist [lreplace $arglist 0 0]
	    break
	}
	if {[string match {} [set akey [array names data $key]]]} {
	    set akey [array names data ${key}*]
	}
	switch [llength $akey] {
	    0		{ ## oops, no keys matched
		return -code error "unknown switch '$key', must be:\
			[join [array names data] {, }]"
	    }
	    1		{ ## Perfect, found just the right key
		if {[info exists types($akey)] && \
			![validate $types($akey) $val]} {
		    return -code error "the value for \"$akey\" is not in\
			    proper $types($akey) format"
		}
		set data($akey) $val
	    }
	    default	{ ## Oops, matches too many possible keys
		return -code error "ambiguous option \"$key\",\
			must be one of: [join $akey {, }]"
	    }
	}
	set arglist [lreplace $arglist 0 1]
    }
    return $arglist
}

# lremove --
#   remove items from a list
# Arguments:
#   ?-all?	remove all instances of said item
#   list	list to remove items from
#   args	items to remove
# Returns:
#   The list with items removed
#
;proc lremove {args} {
    set all 0
    if {[string match \-a* [lindex $args 0]]} {
	set all 1
	set args [lreplace $args 0 0]
    }
    set l [lindex $args 0]
    foreach i [join [lreplace $args 0 0]] {
	if {[set ix [lsearch -exact $l $i]] == -1} continue
	set l [lreplace $l $ix $ix]
	if {$all} {
	    while {[set ix [lsearch -exact $l $i]] != -1} {
		set l [lreplace $l $ix $ix]
	    }
	}
    }
    return $l
}

# best_match --
#   finds the best unique match in a list of names
#   The extra $e in this argument allows us to limit the innermost loop a
#   little further.
# Arguments:
#   l		list to find best unique match in
#   e		currently best known unique match
# Returns:
#   longest unique match in the list
#
;proc best_match {l {e {}}} {
    set ec [lindex $l 0]
    if {[llength $l]>1} {
	set e  [string length $e]; incr e -1
	set ei [string length $ec]; incr ei -1
	foreach l $l {
	    while {$ei>=$e && [string first $ec $l]} {
		set ec [string range $ec 0 [incr ei -1]]
	    }
	}
    }
    return $ec
}

# alias --
#   akin to the csh alias command
# Arguments:
#   newcmd	(optional) command to bind alias to
#   args	command and args being aliased
# Returns:
#   If called with no args, then it dumps out all current aliases
#   If called with one arg, returns the alias of that arg (or {} if none)
#
;proc alias {{newcmd {}} args} {
    if {[string match {} $newcmd]} {
	set res {}
	foreach a [interp aliases] {
	    lappend res [list $a -> [interp alias {} $a]]
	}
	return [join $res \n]
    } elseif {[string match {} $args]} {
	interp alias {} $newcmd
    } else {
	eval interp alias [list {} $newcmd {}] $args
    }
}

## unalias - unaliases an alias'ed command
# ARGS:	cmd	- command to unbind as an alias
## 
proc unalias {cmd} {
    interp alias {} $cmd {}
}

# echo --
#   Relaxes the one string restriction of 'puts'
# Arguments:
#   args	any number of strings to output to stdout
# Returns:
#   Outputs all input to stdout
#
;proc echo args { puts [concat $args] }

## which - tells you where a command is found
# ARGS:	cmd	- command name
# Returns:	where command is found (internal / external / unknown)
## 
proc which cmd {
    ## This tries to auto-load a command if not recognized
    set types [uplevel 1 [list what $cmd 1]]
    if {[llength $types]} {
	set out {}
	
	foreach type $types {
	    switch -- $type {
		alias		{ set res "$cmd: aliased to [alias $cmd]" }
		procedure	{ set res "$cmd: procedure" }
		command		{ set res "$cmd: internal command" }
		executable	{ lappend out [auto_execok $cmd] }
		variable	{ lappend out "$cmd: $type" }
	    }
	    if {[info exists res]} {
		global auto_index
		if {[info exists auto_index($cmd)]} {
		    ## This tells you where the command MIGHT have come from -
		    ## not true if the command was redefined interactively or
		    ## existed before it had to be auto_loaded.  This is just
		    ## provided as a hint at where it MAY have come from
		    append res " ($auto_index($cmd))"
		}
		lappend out $res
		unset res
	    }
	}
	return [join $out \n]
    } else {
	return -code error "$cmd: command not found"
    }
}

## what - tells you what a string is recognized as
# ARGS:	str	- string to id
# Returns:	id types of command as list
## 
proc what {str {autoload 0}} {
    set types {}
    if {[llength [info commands $str]] || ($autoload && \
	    [auto_load $str] && [llength [info commands $str]])} {
	if {[lsearch -exact [interp aliases] $str] > -1} {
	    lappend types "alias"
	} elseif {
	    [llength [info procs $str]] ||
	    ([string match *::* $str] &&
	    [llength [namespace eval [namespace qualifier $str] \
		    info procs [namespace tail $str]]])
	} {
	    lappend types "procedure"
	} else {
	    lappend types "command"
	}
    }
    if {[llength [uplevel 1 info vars $str]]} {
	upvar 1 $str var
	if {[array exists var]} {
	    lappend types array variable
	} else {
	    lappend types scalar variable
	}
    }
    if {[file isdirectory $str]} {
	lappend types "directory"
    }
    if {[file isfile $str]} {
	lappend types "file"
    }
    if {[llength [info commands winfo]] && [winfo exists $str]} {
	lappend types "widget"
    }
    if {[string compare {} [auto_execok $str]]} {
	lappend types "executable"
    }
    return $types
}

# ls --
#   mini-ls equivalent (directory lister)
# Arguments:
#   ?-all?	list hidden files as well (Unix dot files)
#   ?-long?	list in full format "permissions size date filename"
#   ?-full?	displays / after directories and link paths for links
#   args	names/glob patterns of directories to list
# Returns:
#   a directory listing
#
interp alias {} ::Utility::ls {} namespace inscope ::Utility dir -full
;proc dir {args} {
    array set s {
	-all 0 -full 0 -long 0
	0 --- 1 --x 2 -w- 3 -wx 4 r-- 5 r-x 6 rw- 7 rwx
    }
    set args [get_opts s $args [array get s -*]]
    set sep [string trim [file join . .] .]
    if {[string match {} $args]} { set args . }
    foreach arg $args {
	if {[file isdir $arg]} {
	    set arg [string trimr $arg $sep]$sep
	    if {$s(-all)} {
		lappend out [list $arg [lsort [glob -nocomplain -- $arg.* $arg*]]]
	    } else {
		lappend out [list $arg [lsort [glob -nocomplain -- $arg*]]]
	    }
	} else {
	    lappend out [list [file dirname $arg]$sep \
		    [lsort [glob -nocomplain -- $arg]]]
	}
    }
    if {$s(-long)} {
	global tcl_platform
	set old [clock scan {1 year ago}]
	switch -exact -- $tcl_platform(os) {
	    windows	{ set fmt "%-5s %8d %s %s\n" }
	    default	{ set fmt "%s %-8s %-8s %8d %s %s\n" }
	}
	foreach o $out {
	    set d [lindex $o 0]
	    if {[llength $out]>1} { append res $d:\n }
	    foreach f [lindex $o 1] {
		file lstat $f st
		array set st [file attrib $f]
		set f [file tail $f]
		if {$s(-full)} {
		    switch -glob $st(type) {
			dir* { append f $sep }
			link { append f " -> [file readlink $d$sep$f]" }
			fifo { append f | }
			default { if {[file exec $d$sep$f]} { append f * } }
		    }
		}
		switch -exact -- $st(type) {
		    file	{ set mode - }
		    fifo	{ set mode p }
		    default	{ set mode [string index $st(type) 0] }
		}
		set cfmt [expr {$st(mtime)>$old?{%b %d %H:%M}:{%b %d  %Y}}]
		switch -exact -- $tcl_platform(os) {
		    windows	{
			# RHSA
			append mode $st(-readonly) $st(-hidden) \
				$st(-system) $st(-archive)
			append res [format $fmt $mode $st(size) \
				[clock format $st(mtime) -format $cfmt] $f]
		    }
		    macintosh	{
			append mode $st(-readonly) $st(-hidden)
			append res [format $fmt $mode $st(-creator) \
				$st(-type) $st(size) \
				[clock format $st(mtime) -format $cfmt] $f]
		    }
		    default	{ ## Unix is our default platform type
			foreach j [split [format %o \
				[expr {$st(mode)&0777}]] {}] {
			    append mode $s($j)
			}
			append res [format $fmt $mode $st(-owner) $st(-group) \
				$st(size) \
				[clock format $st(mtime) -format $cfmt] $f]
		    }
		}
	    }
	    append res \n
	}
    } else {
	foreach o $out {
	    set d [lindex $o 0]
	    if {[llength $out]>1} { append res $d:\n }
	    set i 0
	    foreach f [lindex $o 1] {
		if {[string len [file tail $f]] > $i} {
		    set i [string len [file tail $f]]
		}
	    }
	    set i [expr {$i+2+$s(-full)}]
	    ## Assume we have at least 70 char cols
	    set j [expr {70/$i}]
	    set k 0
	    foreach f [lindex $o 1] {
		set f [file tail $f]
		if {$s(-full)} {
		    switch -glob [file type $d$sep$f] {
			d* { append f $sep }
			l* { append f @ }
			default { if {[file exec $d$sep$f]} { append f * } }
		    }
		}
		append res [format "%-${i}s" $f]
		if {[incr k]%$j == 0} {set res [string trimr $res]\n}
	    }
	    append res \n\n
	}
    }
    return [string trimr $res]
}

# validate --
# This procedure validates particular types of numbers/formats
#
# Arguments:
# type		- The type of validation (alphabetic, alphanumeric, date,
#		hex, integer, numeric, real).  Date is always strict.
# val		- The value to be validated
#
# Returns:	0 or 1 (whether or not it resembles the type)
#
# Switches:
# -incomplete	enable less precise (strict) pattern matching on number
#		useful for when the number might be half-entered
#
# Example use:	validate real 55e-5
#		validate -incomplete integer -505
#

;proc validate {args} {
    if {[string match [lindex $args 0]* "-incomplete"]} {
	set strict 0
	set opt *
	set args [lreplace $args 0 0]
    } else {
	set strict 1
	set opt +
    }

    if {[llength $args] != 2} {
	return -code error "wrong \# args: should be\
		\"[lindex [info level 0] 0] ?-incomplete? type value\""
    } else {
	set type [lindex $args 0]
	set val  [lindex $args 1]
    }

    ## This is a big switch for speed reasons
    switch -glob -- $type {
	alphab*	{ # alphabetic
	    return [regexp -nocase "^\[a-z\]$opt\$" $val]
	}
	alphan* { # alphanumeric
	    return [regexp -nocase "^\[a-z0-9\]$opt\$" $val]
	}
	b*	{ # boolean - would be nice if it were more than 0/1
	    return [regexp "^\[01\]$opt\$" $val]
	}
	d*	{ # date - always strict
	    return [expr {![catch {clock scan $val}]}]
	}
	h*	{ # hexadecimal
	    return [regexp -nocase "^(0x)?\[0-9a-f\]$opt\$" $val]
	}
	i*	{ # integer
	    return [regexp "^\[-+\]?\[0-9\]$opt\$" $val]
	}
	n*	{ # numeric
	    return [regexp "^\[0-9\]$opt\$" $val]
	}
	rea*	{ # real
	    return [regexp -nocase [expr {$strict
	    ?{^[-+]?([0-9]+\.?[0-9]*|[0-9]*\.?[0-9]+)(e[-+]?[0-9]+)?$}
	    :{^[-+]?[0-9]*\.?[0-9]*([0-9]\.?e[-+]?[0-9]*)?$}}] $val]
	}
	reg*	{ # regexp
	    return [expr {![catch {regexp $val {}}]}]
	}
	val*	{ # value, any valid number type
	    return [expr {![catch {expr {0+$val}}]}]
	}
	l*	{ # list
	    return [expr {![catch {llength $val}]}]
	}
	w*	{ # widget
	    return [winfo exists $val]
	}
	default {
	    return -code error "bad [lindex [info level 0] 0] type \"$type\":\
		    \nmust be [join [lsort {alphabetic alphanumeric date \
		    hexadecimal integer numeric real value \
		    list boolean}] {, }]"
	}
    }
    return
}

}; # end namespace ::Utility

namespace import -force ::Utility::*

## Barebones requirements for creating and querying megawidgets
##
## Copyright 1997-9 Jeffrey Hobbs, jeff.hobbs@acm.org
##
## Initiated: 5 June 1997
## Last Update: 1999

## FIX: config flag, option for setting all child widgets by default

package require Tk 8
#package require ::Utility
package provide Widget 2.0

##------------------------------------------------------------------------
## PROCEDURE
##	widget
##
## DESCRIPTION
##	Implements and modifies megawidgets
##
## ARGUMENTS
##	widget <subcommand> ?<args>?
##
## <classname> specifies a global array which is the name of a class and
## contains options database information.
##
## add classname option ?args?
##	adds ...
##
## create classname
##	creates the widget class $classname based on the specifications
##	in the global array of the same name
##
## classes ?pattern?
##	returns the classes created with this command.
##
## delete classname option ?args?
##	deletes ...
##
## value classname key
##	returns the value of a key from the special class variable.
##
## OPTIONS
##	none
##
## RETURNS
##	the namespace for the widget class (::Widget::$CLASS)
##
## NAMESPACE & STATE
##	The namespace Widget is used, with public procedure "widget".
##
##------------------------------------------------------------------------
##
## For a well-commented example for creating a megawidget using this method,
## see the ScrolledText example at the end of the file.
##
## SHORT LIST OF IMPORTANT THINGS TO KNOW:
##
## Specify the "type", "base", & "components" keys of the $CLASS global array
##
## In the $w global array that is created for each instance of a megawidget,
## the following keys are set by the "widget create $CLASS" procedure:
##   "base", "basecmd", "container", "class", any option specified in the
##   $CLASS array, each component will have a named key
##
## The following public methods are created for you in the namespace:
##   cget	::Widget::$CLASS::_cget
##   configure	::Widget::$CLASS::_configure
##   destruct	::Widget::$CLASS::_destruct
##   subwidget	::Widget::$CLASS::_subwidget
## The following additional submethods are required (you write them):
##   construct	::Widget::$CLASS::construct
##   configure	::Widget::$CLASS::configure
## You may want the following that will be called when appropriate:
##   init	::Widget::$CLASS::init
##	(after initial configuration)
##   destruct	::Widget::$CLASS::destruct
##	(called first thing when widget is being destroyed)
##
## All ::Widget::$CLASS::_* commands are considered public methods.  The
## megawidget routine will match your options and methods on a unique
## substring basis.
##
## END OF SHORT LIST


## Dummy call for indexers
proc widget args {}

namespace eval ::Widget {;

namespace export -clear widget
variable CLASSES
variable CONTAINERS {frame toplevel}
#namespace import -force ::Utility::get_opts*

;proc widget {cmd args} {
    ## Establish the prefix of public commands
    set prefix [namespace current]::_
    if {[string match {} [set arg [info commands $prefix$cmd]]]} {
	set arg [info commands $prefix$cmd*]
    }
    switch [llength $arg] {
	1 { return [uplevel $arg $args] }
	0 {
	    set arg [info commands $prefix*]
	    regsub -all $prefix $arg {} arg
	    return -code error "unknown [lindex [info level 0] 0] method\
		    \"$cmd\", must be one of: [join [lsort $arg] {, }]"
	}
	default {
	    regsub -all $prefix $arg {} arg
	    return -code error "ambiguous method \"$cmd\",\
		    could be one of: [join [lsort $arg] {, }]"
	}
    }
}

;proc verify_class {CLASS} {
    variable CLASSES
    if {![info exists CLASSES($CLASS)]} {
	return -code error "no known class \"$CLASS\""
    }
    return
}

;proc _add {CLASS what args} {
    variable CLASSES
    verify_class $CLASS
    if {[string match ${what}* options]} {
	add_options $CLASSES($CLASS) $CLASS $args
    } else {
	return -code error "unknown type for add, must be one of:\
		options, components"
    }
}

;proc _find_class {CLASS {root .}} {
    if {[string match $CLASS [winfo class $root]]} {
	return $root
    } else {
	foreach w [winfo children $root] {
	    set w [_find_class $CLASS $w]
	    if {[string compare {} $w]} {
		return $w
	    }
	}
    }
}

;proc _delete {CLASS what args} {
    variable CLASSES
    verify_class $CLASS
}

;proc _classes {{pattern "*"}} {
    variable CLASSES
    return [array names CLASSES $pattern]
}

;proc _value {CLASS key} {
    variable CLASSES
    verify_class $CLASS
    upvar \#0 $CLASSES($CLASS)::class class
    if {[info exists class($key)]} {
	return $class($key)
    } else {
	return -code error "unknown key \"$key\" in class \"$CLASS\""
    }
}

## handle
## Handles the method calls for a widget.  This is the command to which
## all megawidget dummy commands are redirected for interpretation.
##
;proc handle {namesp w subcmd args} {
    upvar \#0 ${namesp}::$w data
    if {[string match {} [set arg [info commands ${namesp}::_$subcmd]]]} {
	set arg [info commands ${namesp}::_$subcmd*]
    }
    set num [llength $arg]
    if {$num==1} {
	return [uplevel $arg [list $w] $args]
    } elseif {$num} {
	regsub -all "${namesp}::_" $arg {} arg
	return -code error "ambiguous method \"$subcmd\",\
		could be one of: [join $arg {, }]"
    } elseif {[catch {uplevel [list $data(basecmd) $subcmd] $args} err]} {
	return -code error $err
    } else {
	return $err
    }
}

## construct
## Constructs the megawidget instance instantiation proc based on the
## current knowledge of the megawidget. 
##
;proc construct {namesp CLASS} {
    upvar \#0 ${namesp}::class class \
	    ${namesp}::components components

    lappend dataArrayVals [list class $CLASS]
    if {[string compare $class(type) $class(base)]} {
	## If -type and -base don't match, we need a special setup
	lappend dataArrayVals "base \$w.[list [lindex $components(base) 1]]" \
		"basecmd ${namesp}::\$w.[list [lindex $components(base) 1]]" \
		"container ${namesp}::.\$w"
	## If the base widget is not the container, then we want to rename
	## its widget commands and add the CLASS and container bind tables
	## to its bindtags in case certain bindings are made
	## Interp alias is the optimal solution, but exposes
	## a bug in Tcl7/8 when renaming aliases
	#interp alias {} \$base {} ::Widget::handle $namesp \$w
	set renamingCmd "rename \$base \$data(basecmd)
	;proc ::\$base args \"uplevel ::Widget::handle $namesp \[list \$w\] \\\$args\"
	bindtags \$base \[linsert \[bindtags \$base\] 1\
		[expr {[string match toplevel $class(type)]?{}:{$w}}] $CLASS\]"
    } else {
	## -type and -base are the same, we only create for one
	lappend dataArrayVals "base \$w" \
		"basecmd ${namesp}::\$w" \
		"container ${namesp}::\$w"
	if {[string compare {} [lindex $components(base) 3]]} {
	    lappend dataArrayVals "[lindex $components(base) 3] \$w"
	}
	## When the base widget and container are the same, we have a
	## straightforward renaming of commands
	set renamingCmd {}
    }
    set baseConstruction {}
    foreach name [array names components] {	
	if {[string match base $name]} {
	    continue
	}
	foreach {type wid opts} $components($name) break
	lappend dataArrayVals "[list $name] \$w.[list $wid]"
	lappend baseConstruction "$type \$w.[list $wid] $opts"
	if {[string match toplevel $type]} {
	    lappend baseConstruction "wm withdraw \$data($name)"
	}
    }
    set dataArrayVals [join $dataArrayVals " \\\n\t"]
    ## the lsort ensure that parents are created before children
    set baseConstruction [join [lsort -index 1 $baseConstruction] "\n    "]

    ## More of this proc could be configured ahead of time for increased
    ## construction speed.  It's delicate, so handle with extreme care.
    ;proc ${namesp}::$CLASS {w args} [subst {
	variable options
	upvar \#0 ${namesp}::\$w data
	$class(type) \$w -class $CLASS
	[expr [string match toplevel $class(type)]?{wm withdraw \$w\n}:{}]
	## Populate data array with user definable options
	foreach o \[array names options\] {
	    if {\[string match -* \$options(\$o)\]} continue
	    set data(\$o) \[option get \$w \[lindex \$options(\$o) 0\] $CLASS\]
	}

	## Populate the data array
	array set data \[list $dataArrayVals\]
	## Create all the base and component widgets
	$baseConstruction

	## Allow for an initialization proc to be eval'ed
	## The user must create one
	if {\[catch {construct \$w} err\]} {
	    catch {_destruct \$w}
	    return -code error \"megawidget construction error: \$err\"
	}

	set base \$data(base)
	rename \$w \$data(container)
	$renamingCmd
	#;proc ::\$w args \"uplevel ::Widget::handle $namesp \[list \$w\] \\\$args\"
	interp alias {} \$w {} ::Widget::handle $namesp \$w

	## Do the configuring here and eval the post initialization procedure
	if {(\[llength \$args\] && \
		\[catch {uplevel 1 ${namesp}::_configure \$w \$args} err\]) || \
		\[catch {${namesp}::init \$w} err\]} {
	    catch { ${namesp}::_destruct \$w }
	    return -code error \"megawidget initialization error: \$err\"
	}

	return \$w
    }
    ]
}

;proc add_options {namesp CLASS optlist} {
    upvar \#0 ${namesp}::class class \
	    ${namesp}::options options \
	    ${namesp}::widgets widgets
    ## Go through the option definition, substituting for ALIAS where
    ## necessary and setting up the options database for this $CLASS
    ## There are several possible formats:
    ## 1. -optname -optnamealias
    ## 2. -optname dbname dbcname value
    ## 3. -optname ALIAS componenttype option
    ## 4. -optname ALIAS componenttype option dbname dbcname
    foreach optdef $optlist {
	foreach {optname alias type opt dbname dbcname} $optdef break
	set len [llength $optdef]
	switch -glob -- $alias {
	    -*	{
		if {$len != 2} {
		    return -code error "wrong \# args for option alias,\
			    must be: {-aliasoptioname -realoptionname}"
		}
		set options($optname) $alias
		continue
	    }
	    ALIAS - alias {
		if {$len != 4 && $len != 6} {
		    return -code error "wrong \# args for ALIAS, must be:\
			    {-optionname ALIAS componenttype option\
			    ?databasename databaseclass?}"
		}
		if {![info exists widgets($type)]} {
		    return -code error "cannot create alias \"$optname\" to\
			    $CLASS component type \"$type\" option \"$opt\":\
			    component type does not exist"
		} elseif {![info exists config($type)]} {
		    if {[string compare toplevel $type]} {
			set w .__widget__$type
			catch {destroy $w}
			## Make sure the component widget type exists,
			## returns the widget name,
			## and accepts configure as a subcommand
			if {[catch {$type $w} result] || \
				[string compare $result $w] || \
				[catch {$w configure} config($type)]} {
			    ## Make sure we destroy it if it was a bad widget
			    catch {destroy $w}
			    ## Or rename it if it was a non-widget command
			    catch {rename $w {}}
			    return -code error "invalid widget type \"$type\""
			}
			catch {destroy $w}
		    } else {
			set config($type) [. configure]
		    }
		}
		set i [lsearch -glob $config($type) "$opt\[ \t\]*"]
		if {$i == -1} {
		    return -code error "cannot create alias \"$o\" to $CLASS\
			    component type \"$type\" option \"$opt\":\
			    option does not exist"
		}
		if {$len==4} {
		    foreach {opt dbname dbcname def} \
			    [lindex $config($type) $i] break
		} elseif {$len==6} {
		    set def [lindex [lindex $config($type) $i] 3]
		}
	    }
	    default {
		if {$len != 4} {
		    return -code error "wrong \# args for option \"$optdef\",\
			    must be:\
			    {-optioname databasename databaseclass defaultval}"
		}
		foreach {optname dbname dbcname def} $optdef break
	    }
	}
	set options($optname) [list $dbname $dbcname $def]
	option add *$CLASS.$dbname $def widgetDefault
    }
}

;proc _create {CLASS args} {
    if {![string match {[A-Z]*} $CLASS] || [string match { } $CLASS]} {
	return -code error "invalid class name \"$CLASS\": it must begin\
		with a capital letter and contain no spaces"
    }

    variable CONTAINERS
    variable CLASSES
    set namesp [namespace current]::$CLASS
    namespace eval $namesp {
	variable class
	variable options
	variable components
	variable widgets
	catch {unset class}
	catch {unset options}
	catch {unset components}
	catch {unset widgets}
    }
    upvar \#0 ${namesp}::class class \
	    ${namesp}::options options \
	    ${namesp}::components components \
	    ${namesp}::widgets widgets

    get_opts2 classopts $args {
	-type		frame
	-base		frame
	-components	{}
	-options	{}
    } {
	-type		list
	-base		list
	-components	list
	-options	list
    }

    ## First check to see that their container type is valid
    ## I'd like to include canvas and text, but they don't accept the
    ## -class option yet, which would thus require some voodoo on the
    ## part of the constructor to make it think it was the proper class
    if {![regexp ^([join $CONTAINERS |])\$ $classopts(-type)]} {
	return -code error "invalid class container type\
		\"$classopts(-type)\", must be one of:\
		[join $CONTAINERS {, }]"
    }

    ## Then check to see that their base widget type is valid
    ## We will create a default widget of the appropriate type just in
    ## case they use the DEFAULT keyword as a default value in their
    ## megawidget class definition
    if {[info exists classopts(-base)]} {
	## We check to see that we can create the base, that it returns
	## the same widget value we put in, and that it accepts cget.
	if {[string match toplevel $classopts(-base)] && \
		[string compare toplevel $classopts(-type)]} {
	    return -code error "\"toplevel\" is not allowed as the base\
		    widget of a megawidget (perhaps you intended it to\
		    be the class type)"
	}
    } else {
	## The container is the default base widget
	set classopts(-base) $classopts(-type)
    }

    ## Ensure that the class is set correctly
    array set class [list class $CLASS \
	    base $classopts(-base) \
	    type $classopts(-type)]

    set widgets($class(type)) 0

    if {![info exists classopts(-components)]} {
	set classopts(-components) {}
    }
    foreach compdef $classopts(-components) {
	set opts {}
	switch [llength $compdef] {
	    0 continue
	    1 { set name [set type [set wid $compdef]] }
	    2 {
		set type [lindex $compdef 0]
		set name [set wid [lindex $compdef 1]]
	    }
	    default {
		foreach {type name wid opts} $compdef break
		set opts [string trim $opts]
	    }
	}
	if {[info exists components($name)]} {
	    return -code error "component name \"$name\" occurs twice\
		    in $CLASS class"
	}
	if {[info exists widnames($wid)]} {
	    return -code error "widget name \"$wid\" occurs twice\
		    in $CLASS class"
	}
	if {[regexp {(^[\.A-Z]| |\.$)} $wid]} {
	    return -code error "invalid $CLASS class component widget\
		    name \"$wid\": it cannot begin with a capital letter,\
		    contain spaces or start or end with a \".\""
	}
	if {[string match *.* $wid] && \
		![info exists widnames([file root $wid])]} {
	    ## If the widget name contains a '.', then make sure we will
	    ## have created all the parents first.  [file root $wid] is
	    ## a cheap trick to remove the last .child string from $wid
	    return -code error "no specified parent for $CLASS class\
		    component widget name \"$wid\""
	}
	if {[string match base $type]} {
	    set type $class(base)
	    set components(base) [list $type $wid $opts $name]
	    if {[string match $type $class(type)]} continue
	}
	set components($name) [list $type $wid $opts]
	set widnames($wid) 0
	set widgets($type) 0
    }
    if {![info exists components(base)]} {
	set components(base) [list $class(base) $class(base) {}]
	# What should we really do here?
	#set components($class(base)) $components(base)
	set widgets($class(base)) 0
	if {![regexp ^([join $CONTAINERS |])\$ $class(base)] && \
		![info exists components($class(base))]} {
	    set components($class(base)) $components(base)
	}
    }

    ## Process options
    add_options $namesp $CLASS $classopts(-options)

    namespace eval $namesp {
	set CLASS [namespace tail [namespace current]]
	## The _destruct must occur to remove excess state elements.
	## The [winfo class %W] will work in this Destroy, which is necessary
	## to determine if we are destroying the actual megawidget container.
	bind $CLASS <Destroy> [namespace code {
	    if {[string compare {} [::widget classes [::winfo class %W]]]} {
		if [catch {_destruct %W} err] { puts $err }
	    }
	}]
    }
    ## This creates the basic constructor procedure for the class
    ## as ${namesp}::$CLASS
    construct $namesp $CLASS

    ## Both $CLASS and [string tolower $CLASS] commands will be created
    ## in the global namespace
    namespace eval $namesp [list namespace export -clear $CLASS]
    namespace eval :: [list namespace import -force ${namesp}::$CLASS]
    interp alias {} ::[string tolower $CLASS] {} ::$CLASS

    ## These are provided so that errors due to lack of the command
    ## existing don't arise.  Since they are stubbed out here, the
    ## user can't depend on 'unknown' or 'auto_load' to get this proc.
    if {[string match {} [info commands ${namesp}::construct]]} {
	;proc ${namesp}::construct {w} {
	    # the user should rewrite this
	    # without the following error, a simple megawidget that was just
	    # a frame would be created by default
	    return -code error "user must write their own\
		    [lindex [info level 0] 0] function"
	}
    }
    if {[string match {} [info commands ${namesp}::init]]} {
	;proc ${namesp}::init {w} {
	    # the user should rewrite this
	}
    }

    ## The user is not supposed to change this proc
    set comps [lsort [array names components]]
    ;proc ${namesp}::_subwidget {w {widget return} args} [subst {
	variable \$w
	upvar 0 \$w data
	switch -- \$widget {
	    return	{
		return [list $comps]
	    }
	    all {
		if {\[llength \$args\]} {
		    foreach sub [list $comps] {
			catch {uplevel 1 \[list \$data(\$sub)\] \$args}
		    }
		} else {
		    return [list $comps]
		}
	    }
	    [join $comps { - }] {
		if {\[llength \$args\]} {
		    return \[uplevel 1 \[list \$data(\$widget)\] \$args\]
		} else {
		    return \$data(\$widget)
		}
	    }
	    default {
		return -code error \"No \$data(class) subwidget \\\"\$widget\\\",\
			must be one of: [join $comps {, }]\"
	    }
	}
    }]

    ## The user is not supposed to change this proc
    ## Instead they create a ::Widget::$CLASS::destruct proc
    ## Some of this may be redundant, but at least it does the job
    ;proc ${namesp}::_destruct {w} "
    upvar \#0 ${namesp}::\$w data
    catch {${namesp}::destruct \$w}
    catch {::destroy \$data(base)}
    catch {::destroy \$w}
    catch {rename \$data(basecmd) {}}
    catch {rename ::\$data(base) {}}
    catch {rename ::\$w {}}
    catch {unset data}
    return\n"
    
    if {[string match {} [info commands ${namesp}::destruct]]} {
	## The user can optionally provide a special destroy handler
	;proc ${namesp}::destruct {w args} {
	    # empty
	}
    }

    ## The user is not supposed to change this proc
    ;proc ${namesp}::_cget {w args} {
	if {[llength $args] != 1} {
	    return -code error "wrong \# args: should be \"$w cget option\""
	}
	set namesp [namespace current]
	upvar \#0 ${namesp}::$w data ${namesp}::options options
	if {[info exists options($args)]&&[string match -* $options($args)]} {
	    set args $options($args)
	}
	if {[string match {} [set arg [array names data $args]]]} {
	    set arg [array names data ${args}*]
	}
	set num [llength $arg]
	if {$num==1} {
	    return $data($arg)
	} elseif {$num} {
	    return -code error "ambiguous option \"$args\",\
		    must be one of: [join $arg {, }]"
	} elseif {[catch {$data(basecmd) cget $args} err]} {
	    return -code error $err
	} else {
	    return $err
	}
    }

    ## The user is not supposed to change this proc
    ## Instead they create a $CLASS:configure proc
    ;proc ${namesp}::_configure {w args} {
	set namesp [namespace current]
	upvar \#0 ${namesp}::$w data ${namesp}::options options \
		${namesp}::components components

	set num [llength $args]
	if {$num==1} {
	    ## Request for one config option
	    if {[info exists options($args)] && \
		    [string match -* $options($args)]} {
		set args $options($args)
	    }
	    if {[string match {} [set arg [array names data $args]]]} {
		set arg [array names data ${args}*]
	    }
	    set num [llength $arg]
	    if {$num==1} {
		## FIX one-elem config
		return "[list $arg] $options($arg) [list $data($arg)]"
	    } elseif {$num} {
		return -code error "ambiguous option \"$args\",\
			must be one of: [join $arg {, }]"
	    } elseif {[catch {$data(basecmd) configure $args} err]} {
		return -code error $err
	    } else {
		return $err
	    }
	} elseif {$num} {
	    ## Request for several config options to be set
	    ## Group the {key val} pairs to be distributed
	    if {$num&1} {
		set last [lindex $args end]
		set args [lrange $args 0 [incr num -2]]
	    }
	    set widargs {}
	    set cmdargs {}
	    foreach {key val} $args {
		if {[info exists options($key)] && \
			[string match -* $options($key)]} {
		    set key $options($key)
		}
		if {[string match {} [set arg [array names data $key]]]} {
		    set arg [array names data $key*]
		}
		set len [llength $arg]
		if {$len==1} {
		    lappend widargs $arg $val
		} elseif {$len} {
		    set ambarg [list $key $arg]
		    break
		} else {
		    lappend cmdargs $key $val
		}
	    }
	    if {[llength $widargs]} {
		uplevel ${namesp}::configure [list $w] $widargs
	    }
#	    if {[llength $cmdargs]} {
#		;proc _configure {w args} {
#		    catch {uplevel [list $w] configure $args}
#		    set n [namespace current]
#		    foreach c [winfo children $w] {
#			uplevel ${n}::_configure [list $c] $args
#		    }
#		}
#		uplevel widget configure [list $w] $cmdargs
#	    }
	    if {[llength $cmdargs] && [catch \
		    {uplevel [list $data(basecmd)] configure $cmdargs} err]} {
		return -code error $err
	    }
	    if {[info exists ambarg]} {
		return -code error "ambiguous option \"[lindex $ambarg 0]\",\
			must be one of: [join [lindex $ambarg 1] {, }]"
	    }
	    if {[info exists last]} {
		return -code error "value for \"$last\" missing"
	    }
	} else {
	    ## Request for all config options to be printed out
	    foreach opt [$data(basecmd) configure] {
		set opts([lindex $opt 0]) [lrange $opt 1 end]
	    }
	    foreach opt [array names options] {
		if {[string match -* $options($opt)]} {
		    set opts($opt) [string range $options($opt) 1 end]
		} else {
		    set opts($opt) "$options($opt) [list $data($opt)]"
		}
	    }
	    foreach opt [lsort [array names opts]] {
		lappend config "$opt $opts($opt)"
	    }
	    return $config
	}
    }

    if {[string match {} [info commands ${namesp}::configure]]} {
	## The user is intended to rewrite this one
	;proc ${namesp}::configure {w args}  {
	    foreach {key val} $args {
		puts "$w: configure $key to [list $value]"
	    }
	}
    }

    set CLASSES($CLASS) $namesp
    return $namesp
}

# Redefine private Tk function tkFocusOK to recognize our widgets
#
;proc _tkFocusOK w {
    if {[llength [info commands widget]] && \
	    [llength [widget classes [winfo class $w]]]} {
	return 0
    }
    set code [catch {$w cget -takefocus} value]
    if {($code == 0) && ($value != "")} {
	if {$value == 0} {
	    return 0
	} elseif {$value == 1} {
	    return [winfo viewable $w]
	} else {
	    set value [uplevel #0 $value $w]
	    if {$value != ""} {
		return $value
	    }
	}
    }
    if {![winfo viewable $w]} {
	return 0
    }
    set code [catch {$w cget -state} value]
    if {($code == 0) && ($value == "disabled")} {
	return 0
    }
    regexp Key|Focus "[bind $w] [bind [winfo class $w]]"
}

}; #end namespace ::Widget

namespace eval :: {
    namespace import -force ::Widget::widget
    if {$::tcl_version > 8.3} {
	catch {::tk::FocusOK .}; # we want this auto-loaded
	interp alias {} ::tk::FocusOK {} widget tkFocusOK
    } else {
	catch {tkFocusOK .}; # we want this auto-loaded
	interp alias {} tkFocusOK {} widget tkFocusOK
    }
}

package require Widget 2.0

package provide Console 2.0

##------------------------------------------------------------------------
## PROCEDURE
##	console
##
## DESCRIPTION
##	Implements a console mega-widget
##
## ARGUMENTS
##	console <window pathname> <options>
##
## OPTIONS
##	(Any frame widget option may be used in addition to these)
##
##  -blinkcolor color			DEFAULT: #FFFF00 (yellow)
##	Specifies the background blink color for brace highlighting.
##	This doubles as the highlight color for the find box.
##
##  -blinkrange TCL_BOOLEAN		DEFAULT: 1
##	When doing electric brace matching, specifies whether to blink
##	the entire range or just the matching braces.
##
##  -blinktime delay			DEFAULT: 500
##	For electric brace matching, specifies the amount of time to
##	blink the background for.
##
##  -grabputs TCL_BOOLEAN		DEFAULT: 1
##	Whether this console should grab the "puts" default output
##
##  -lightbrace TCL_BOOLEAN		DEFAULT: 1
##	Specifies whether to activate electric brace matching.
##
##  -lightcmd TCL_BOOLEAN		DEFAULT: 1
##	Specifies whether to highlight recognized commands.
##
##  -proccolor color			DEFAULT: #008800 (darkgreen)
##	Specifies the color to highlight recognized procs.
##
##  -prompt string	DEFAULT: {([file tail [pwd]]) [history nextid] % }
##	The equivalent of the tcl_prompt1 variable.
##
##  -promptcolor color			DEFAULT: #8F4433 (brown)
##	Specifies the prompt color.
##
##  -stdincolor color			DEFAULT: #000000 (black)
##	Specifies the color for "stdin".
##	This doubles as the console foreground color.
##
##  -stdoutcolor color			DEFAULT: #0000FF (blue)
##	Specifies the color for "stdout".
##
##  -stderrcolor color			DEFAULT: #FF0000 (red)
##	Specifies the color for "stderr".
##
##  -showmultiple TCL_BOOLEAN		DEFAULT: 1
##	For file/proc/var completion, specifies whether to display
##	completions when multiple choices are possible.
##
##  -showmenu TCL_BOOLEAN		DEFAULT: 1
##	Specifies whether to show the menubar.
##
##  -subhistory TCL_BOOLEAN		DEFAULT: 1
##	Specifies whether to allow substitution in the history.
##
##  -varcolor color			DEFAULT: #FFC0D0 (pink)
##	Specifies the color for "stderr".
##
## RETURNS: the window pathname
##
## BINDINGS (these are the bindings for Console, used in the text widget)
##
## <<Console_ExpandFile>>	<Key-Tab>
## <<Console_ExpandProc>>	<Control-Shift-Key-P>
## <<Console_ExpandVar>>	<Control-Shift-Key-V>
## <<Console_Tab>>		<Control-Key-i>
## <<Console_Eval>>		<Key-Return> <Key-KP_Enter>
##
## <<Console_Clear>>		<Control-Key-l>
## <<Console_KillLine>>		<Control-Key-k>
## <<Console_Transpose>>	<Control-Key-t>
## <<Console_ClearLine>>	<Control-Key-u>
## <<Console_SaveCommand>>	<Control-Key-z>
##
## <<Console_Prev>>		<Key-Up>
## <<Console_Next>>		<Key-Down>
## <<Console_NextImmediate>>	<Control-Key-n>
## <<Console_PrevImmediate>>	<Control-Key-p>
## <<Console_PrevSearch>>	<Control-Key-r>
## <<Console_NextSearch>>	<Control-Key-s>
##
## <<Console_Exit>>		<Control-Key-q>
## <<Console_New>>		<Control-Key-N>
## <<Console_Close>>		<Control-Key-w>
## <<Console_About>>		<Control-Key-A>
## <<Console_Help>>		<Control-Key-H>
## <<Console_Find>>		<Control-Key-F>
##
## METHODS
##	These are the methods that the console megawidget recognizes.
##
## configure ?option? ?value option value ...?
## cget option
##	Standard tk widget routines.
##
## load ?filename?
##	Loads the named file into the current interpreter.
##	If no file is specified, it pops up the file requester.
##
## save ?filename?
##	Saves the console buffer to the named file.
##	If no file is specified, it pops up the file requester.
##
## clear ?percentage?
##	Clears a percentage of the console buffer (1-100).  If no
##	percentage is specified, the entire buffer is cleared.
##
## error
##	Displays the last error in the interpreter in a dialog box.
##
## hide
##	Withdraws the console from the screen
##
## history ?-newline?
##	Prints out the history without numbers (basically providing a
##	list of the commands you've used).
##
## show
##	Deiconifies and raises the console
##
## subwidget widget
##	Returns the true widget path of the specified widget.  Valid
##	widgets are console, yscrollbar, menubar.
##
## NAMESPACE & STATE
##	The megawidget creates a global array with the classname, and a
## global array which is the name of each megawidget is created.  The latter
## array is deleted when the megawidget is destroyed.
##	Public procs of $CLASSNAME and [string tolower $CLASSNAME] are used.
## Other procs that begin with $CLASSNAME are private.  For each widget,
## commands named .$widgetname and $CLASSNAME$widgetname are created.
##
## EXAMPLE USAGE:
##
## console .con -height 20 -showmenu false
## pack .con -fill both -expand 1
##------------------------------------------------------------------------

foreach pkg [info loaded {}] {
    set file [lindex $pkg 0]
    set name [lindex $pkg 1]
    if {![catch {set version [package require $name]}]} {
	if {[string match {} [package ifneeded $name $version]]} {
	    package ifneeded $name $version "load [list $file $name]"
	}
    }
}
catch {unset file name version}

# Create this to make sure there are registered in auto_mkindex
# these must come before the [widget create ...]
proc Console args {}
proc console args {}
widget create Console -type frame -base text -components {
    {base console console {-wrap char -setgrid 1 \
	    -yscrollcommand [list $data(yscrollbar) set] \
	    -foreground $data(-stdincolor)}}
    {frame menubar menubar {-relief raised -bd 1}}
    {scrollbar yscrollbar sy {-takefocus 0 -bd 1 \
	    -command [list $data(console) yview]}}
} -options {
    {-blinkcolor	blinkColor	BlinkColor	\#FFFF00}
    {-proccolor		procColor	ProcColor	\#008800}
    {-promptcolor	promptColor	PromptColor	\#8F4433}
    {-stdincolor	stdinColor	StdinColor	\#000000}
    {-stdoutcolor	stdoutColor	StdoutColor	\#0000FF}
    {-stderrcolor	stderrColor	StderrColor	\#FF0000}
    {-varcolor		varColor	VarColor	\#FFC0D0}

    {-blinkrange	blinkRange	BlinkRange	1}
    {-blinktime		blinkTime	BlinkTime	500}
    {-grabputs		grabPuts	GrabPuts	1}
    {-lightbrace	lightBrace	LightBrace	1}
    {-lightcmd		lightCmd	LightCmd	1}
    {-showmultiple	showMultiple	ShowMultiple	1}
    {-showmenu		showMenu	ShowMenu	1}
    {-subhistory	subhistory	SubHistory	1}

    {-abouttext		aboutText	AboutText	{}}
}

if {[info exists ::embed_args] || [info exists ::browser_args]} {
    widget add Console option {-prompt prompt Prompt {[history nextid] % }}
} else {
    widget add Console option {-prompt prompt Prompt \
	    {([file tail [pwd]]) [history nextid] % }}
}

widget add Console option [list -abouttitle aboutTitle AboutTitle \
	"About Console v[package provide Console]"]

##
## BEGIN CONSOLE DIALOG
##

# Create this to make sure there are registered in auto_mkindex
# these must come before the [widget create ...]
proc ConsoleDialog args {}
proc consoledialog args {}
widget create ConsoleDialog -type toplevel -base console -options {
    {-title	title	Title	"Console Dialog"}
}

namespace eval ::Widget::ConsoleDialog {;

variable class
array set class [list version [package provide Console]]

;proc construct {w} {
    set namesp [namespace current]
    upvar \#0 ${namesp}::$w data
    variable class

    wm title $w $data(-title)

    grid $data(console) -in $w -sticky news
    grid columnconfig $w 0 -weight 1
    grid rowconfig $w 0 -weight 1
}

;proc configure {w args} {
    upvar \#0 [namespace current]::$w data
    #variable class

    #set truth {^(1|yes|true|on)$}
    foreach {key val} $args {
	switch -- $key {
	    -title	{ wm title $w $val }
	}
	set data($key) $val
    }
}

;proc _hide w { if {[winfo exists $w]} { wm withdraw $w } }

;proc _show w { if {[winfo exists $w]} { wm deiconify $w; raise $w } }

}; # end namespace ::Widget::ConsoleDialog

##
## END CONSOLE DIALOG
##

##
## CONSOLE MEGAWIDGET
##

namespace eval ::Widget::Console {;

variable class
array set class {
    release	{December 1998}
    contact	"jeff.hobbs@acm.org"
    docs	"http://tkcon.sourceforge.net/"
    slavealias	{ console }
    slaveprocs	{ alias dir dump lremove puts echo unknown tcl_unknown which }
}
if {![info exists class(active)]} { set class(active) {} }
set class(version) [package provide Console]
set class(WWW) [expr {[info exists ::embed_args] \
	|| [info exists ::browser_args]}]

#catch {highlight}
#if {[string compare {} [info commands ::Utility::lremove]]} {
#    namespace import -force ::Utility::*
#}

## console -
# ARGS:	w	- widget pathname of the Console console
# Calls:	InitUI
# Outputs:	errors found in Console resource file
##
;proc construct {w} {
    upvar \#0 [namespace current]::$w data

    global auto_path tcl_pkgPath tcl_interactive
    set tcl_interactive 0

    ## Private variables
    array set data {
	app {} appname {} apptype {} namesp {} deadapp 0
	cmdbuf {} cmdsave {} errorInfo {}
	event 1 histid 0 find {} find,case 0 find,reg 0
    }

    if {![info exists tcl_pkgPath]} {
	set dir [file join [file dirname [info nameofexec]] lib]
	if {[string compare {} [info commands @scope]]} {
	    set dir [file join $dir itcl]
	}
	catch {namespace eval :: [list source [file join $dir pkgIndex.tcl]]}
    }
    catch {tclPkgUnknown dummy-name dummy-version}

    InitMenus $w

    grid $data(menubar) - -sticky ew
    grid $data(console) $data(yscrollbar) -sticky news
    grid columnconfig $w 0 -weight 1
    grid rowconfig $w 1 -weight 1

    prompt $w "console display active\n"

    set c $data(console)
    foreach col {prompt stdout stderr stdin proc} {
	$c tag configure $col -foreground $data(-${col}color)
    }
    $c tag configure var -background $data(-varcolor)
    $c tag configure blink -background $data(-blinkcolor)
}

;proc init {w} {
    upvar \#0 [namespace current]::$w data
    variable class
    bind $w <Destroy> [bind $class(class) <Destroy>]
    bindtags $w [list $w [winfo toplevel $w] all]
    set c $data(console)
    bindtags $c [list $c Console PostConsole $w all]
    if {$data(-grabputs) && [lsearch $class(active) $c] == -1} {
	set class(active) [linsert $class(active) 0 $c]
    }
}

;proc destruct w {
    variable class
    upvar \#0 [namespace current]::$w data
    set class(active) [lremove $class(active) $data(console)]
}

;proc configure { w args } {
    set namesp [namespace current]
    upvar \#0 ${namesp}::$w data
    variable class

    set truth {^(1|yes|true|on)$}
    set c $data(console)
    foreach {key val} $args {
	switch -- $key {
	    -blinkcolor	{
		$c tag config blink -background $val
		$c tag config __highlight -background $val
	    }
	    -proccolor   { $c tag config proc   -foreground $val }
	    -promptcolor { $c tag config prompt -foreground $val }
	    -stdincolor  {
		$c tag config stdin -foreground $val
		$c config -foreground $val
	    }
	    -stdoutcolor { $c tag config stdout -foreground $val }
	    -stderrcolor { $c tag config stderr -foreground $val }

	    -blinktime		{
		if {![regexp {[0-9]+} $val]} {
		    return -code error "$key option requires an integer value"
		} elseif {$val < 100} {
		    return -code error "$key option must be greater than 100"
		}
	    }
	    -grabputs	{
		if {[set val [regexp -nocase $truth $val]]} {
		    set class(active) [linsert $class(active) 0 $c]
		} else {
		    set class(active) [lremove -all $class(active) $c]
		}
	    }
	    -prompt		{
		if {[catch {namespace eval :: [list subst $val]} err]} {
		    return -code error "\"$val\" threw an error:\n$err"
		}
	    }
	    -showmenu	{
		if {[set val [regexp -nocase $truth $val]]} {
		    grid $data(menubar)
		} else {
		    grid remove $data(menubar)
		}
	    }
	    -lightbrace	-
	    -lightcmd	-
	    -showmultiple -
	    -subhistory	{ set val [regexp -nocase $truth $val] }
	}
	set data($key) $val
    }
}

;proc Exit {w args} {
    exit
}

## Eval - evaluates commands input into console window
## This is the first stage of the evaluating commands in the console.
## They need to be broken up into consituent commands (by CmdSep) in
## case a multiple commands were pasted in, then each is eval'ed (by
## EvalCmd) in turn.  Any uncompleted command will not be eval'ed.
# ARGS:	w	- console text widget
# Calls:	CmdGet, CmdSep, EvalCmd
## 
;proc Eval {w} {
    set incomplete [CmdSep [CmdGet $w] cmds last]
    $w mark set insert end-1c
    $w insert end \n
    if {[llength $cmds]} {
	foreach c $cmds {EvalCmd $w $c}
	$w insert insert $last {}
    } elseif {!$incomplete} {
	EvalCmd $w $last
    }
    $w see insert
}

## EvalCmd - evaluates a single command, adding it to history
# ARGS:	w	- console text widget
# 	cmd	- the command to evaluate
# Calls:	prompt
# Outputs:	result of command to stdout (or stderr if error occured)
# Returns:	next event number
## 
;proc EvalCmd {w cmd} {
    ## HACK to get $W as we need it
    set W [winfo parent $w]
    upvar \#0 [namespace current]::$W data

    $w mark set output end
    if {[string compare {} $cmd]} {
	set code 0
	if {$data(-subhistory)} {
	    set ev [EvalSlave history nextid]
	    incr ev -1
	    if {[string match !! $cmd]} {
		set code [catch {EvalSlave history event $ev} cmd]
		if {!$code} {$w insert output $cmd\n stdin}
	    } elseif {[regexp {^!(.+)$} $cmd dummy evnt]} {
		## Check last event because history event is broken
		set code [catch {EvalSlave history event $ev} cmd]
		if {!$code && ![string match ${evnt}* $cmd]} {
		    set code [catch {EvalSlave history event $evnt} cmd]
		}
		if {!$code} {$w insert output $cmd\n stdin}
	    } elseif {[regexp {^\^([^^]*)\^([^^]*)\^?$} $cmd dummy old new]} {
		set code [catch {EvalSlave history event $ev} cmd]
		if {!$code} {
		    regsub -all -- $old $cmd $new cmd
		    $w insert output $cmd\n stdin
		}
	    }
	}
	if {$code} {
	    $w insert output $cmd\n stderr
	} else {
	    ## We are about to evaluate the command, so move the promptEnd
	    ## mark to ensure that further <Return>s don't cause double
	    ## evaluation of this command - for cases like the command
	    ## has a vwait or something in it
	    $w mark set promptEnd end
	    EvalSlave history add $cmd
	    if {[catch {EvalAttached $cmd} res]} {
		if {[catch {EvalAttached {set errorInfo}} err]} {
		    set data(errorInfo) "Error getting errorInfo:\n$err"
		} else {
		    set data(errorInfo) $err
		}
		$w insert output $res\n stderr
	    } elseif {[string compare {} $res]} {
		$w insert output $res\n stdout
	    }
	}
    }
    prompt $W
    set data(event) [EvalSlave history nextid]
}

## EvalSlave - evaluates the args in the associated slave
## args should be passed to this procedure like they would be at
## the command line (not like to 'eval').
# ARGS:	args	- the command and args to evaluate
##
;proc EvalSlave {args} {
    uplevel \#0 $args
}

## EvalAttached
##
;proc EvalAttached {args} {
    uplevel \#0 eval $args
}

## CmdGet - gets the current command from the console widget
# ARGS:	w	- console text widget
# Returns:	text which compromises current command line
## 
;proc CmdGet w {
    if {[string match {} [$w tag nextrange prompt promptEnd end]]} {
	$w tag add stdin promptEnd end-1c
	return [$w get promptEnd end-1c]
    }
}

## CmdSep - separates multiple commands into a list and remainder
# ARGS:	cmd	- (possible) multiple command to separate
# 	list	- varname for the list of commands that were separated.
#	rmd	- varname of any remainder (like an incomplete final command).
#		If there is only one command, it's placed in this var.
# Returns:	constituent command info in varnames specified by list & rmd.
## 
;proc CmdSep {cmd list last} {
    upvar 1 $list cmds $last inc
    set inc {}
    set cmds {}
    foreach c [split [string trimleft $cmd] \n] {
	if {[string compare $inc {}]} {
	    append inc \n$c
	} else {
	    append inc [string trimleft $c]
	}
	if {[info complete $inc] && ![regexp {[^\\]\\$} $inc]} {
	    ## FIX: is this necessary?
	    if {[regexp "^\[^#\]" $inc]} {lappend cmds $inc}
	    set inc {}
	}
    }
    set i [string compare $inc {}]
    if {!$i && [string compare $cmds {}] && ![string match *\n $cmd]} {
	set inc [lindex $cmds end]
	set cmds [lreplace $cmds end end]
    }
    return $i
}

## prompt - displays the prompt in the console widget
# ARGS:	w	- console text widget
# Outputs:	prompt (specified in data(-prompt)) to console
## 
;proc prompt {W {pre {}} {post {}} {prompt {}}} {
    upvar \#0 [namespace current]::$W data

    set w $data(console)
    if {[string compare {} $pre]} { $w insert end $pre stdout }
    set i [$w index end-1c]
    if {[string compare {} $data(appname)]} {
	$w insert end ">$data(appname)< " prompt
    }
    if {[string compare {} $prompt]} {
	$w insert end $prompt prompt
    } else {
	$w insert end [EvalSlave subst $data(-prompt)] prompt
    }
    $w mark set output $i
    $w mark set insert end
    $w mark set promptEnd insert
    $w mark gravity promptEnd left
    if {[string compare {} $post]} { $w insert end $post stdin }
    $w see end
}

## About - gives about info for Console
##
;proc About W {
    variable class
    upvar \#0 [namespace current]::$W data

    set w $W.about
    if {[winfo exists $w]} {
	wm deiconify $w
    } else {
	global tk_patchLevel tcl_patchLevel tcl_platform
	toplevel $w
	wm title $w $data(-abouttitle)
	button $w.b -text Dismiss -command [list wm withdraw $w]
	text $w.text -height 9 -bd 1 -width 62
	pack $w.b -fill x -side bottom
	pack $w.text -fill both -side left -expand 1
	$w.text tag config center -justify center
	$w.text tag config title -justify center -font {Courier 18 bold}
	$w.text insert 1.0 $data(-abouttitle) title \
		"$data(-abouttext)\n\nConsole Copyright 1995-1998\
		Jeffrey Hobbs, $class(contact)\
		\nRelease Date: v$class(version), $class(release)\
		\nDocumentation available at:\n$class(docs)\
		\nUsing: Tcl v$tcl_patchLevel / Tk v$tk_patchLevel" center
    }
}

## InitMenus - inits the menubar and popup for the console
# ARGS:	W	- console megawidget
## 
;proc InitMenus W {
    set V [namespace current]::$W
    upvar \#0 $V data

    set w    $data(menubar)
    set text $data(console)

    if {[catch {menu $w.pop -tearoff 0}]} {
	label $w.label -text "Menus not available in plugin mode"
	pack $w.label
	return
    }
    #bind [winfo toplevel $w] <Button-3> "tk_popup $w.pop %X %Y"
    bind $text <Button-3> "tk_popup $w.pop %X %Y"

    ## Console Menu
    ## FIX - get the attachment stuff working
    set n cons
    set l "Console"
    pack [menubutton $w.$n  -text $l -underline 0 -menu $w.$n.m] -side left
    $w.pop add cascade -label $l -underline 0 -menu $w.pop.$n
    foreach m [list [menu $w.$n.m -disabledforeground $data(-promptcolor)] \
	    [menu $w.pop.$n -disabledforeground $data(-promptcolor)]] {
	$m add command -label "Console $W" -state disabled
	$m add command -label "Clear Console " -underline 1 \
		-accelerator [event info <<Console_Clear>>] \
		-command [namespace code [list _clear $W]]
	$m add command -label "Load File" -underline 0 \
		-command [namespace code [list _load $W]]
	$m add cascade -label "Save ..." -underline 0 -menu $m.save
	$m add separator
	$m add cascade -label "Attach Console" -underline 7 -menu $m.apps \
		-state disabled
	$m add cascade -label "Attach Namespace" -underline 7 -menu $m.name \
		-state disabled
	$m add separator
	$m add command -label "Exit" -underline 1 \
		-accelerator [event info <<Console_Exit>>] \
		-command [namespace code [list Exit $W]]

	## Save Menu
	##
	set s $m.save
	menu $s -disabledforeground $data(-promptcolor) -tearoff 0
	$s add command -label "All"	-underline 0 \
		-command [namespace code [list _save $W all]]
	$s add command -label "History"	-underline 0 \
		-command [namespace code [list _save $W history]]
	$s add command -label "Stdin"	-underline 3 \
		-command [namespace code [list _save $W stdin]]
	$s add command -label "Stdout"	-underline 3 \
		-command [namespace code [list _save $W stdout]]
	$s add command -label "Stderr"	-underline 3 \
		-command [namespace code [list _save $W stderr]]

	## Attach Console Menu
	##
	menu $m.apps -disabledforeground $data(-promptcolor) \
		-postcommand [namespace code [list AttachMenu $W $m.apps]]

	## Attach Interpreter Menu
	##
	menu $m.int -disabledforeground $data(-promptcolor) -tearoff 0 \
		-postcommand [namespace code [list AttachMenu $W $m.int interp]]

	## Attach Namespace Menu
	##
	menu $m.name -disabledforeground $data(-promptcolor) -tearoff 0 \
		-postcommand [namespace code [list AttachMenu $W $m.name namespace]]
    }

    ## Edit Menu
    ##
    set n edit
    set l "Edit"
    pack [menubutton $w.$n -text $l -underline 0 -menu $w.$n.m] -side left
    $w.pop add cascade -label $l -underline 0 -menu $w.pop.$n
    foreach m [list [menu $w.$n.m] [menu $w.pop.$n]] {
	$m add command -label "Cut"   -underline 1 \
		-accelerator [lindex [event info <<Cut>>] 0] \
		-command [namespace code [list Cut $text]]
	$m add command -label "Copy"  -underline 1 \
		-accelerator [lindex [event info <<Copy>>] 0] \
		-command [namespace code [list Copy $text]]
	$m add command -label "Paste" -underline 0 \
		-accelerator [lindex [event info <<Paste>>] 0] \
		-command [namespace code [list Paste $text]]
	$m add separator
	$m add command -label "Find"  -underline 0 \
		-accelerator [lindex [event info <<Console_Find>>] 0] \
		-command [namespace code [list FindBox $W]]
	$m add separator
	$m add command -label "Last Error" -underline 0 \
		-command [list $W error]
    }

    ## Prefs Menu
    ##
    set n pref
    set l "Prefs"
    pack [menubutton $w.$n -text $l -underline 0 -menu $w.$n.m] -side left
    $w.pop add cascade -label $l -underline 0 -menu $w.pop.$n
    foreach m [list [menu $w.$n.m] [menu $w.pop.$n]] {
	$m add checkbutton -label "Brace Highlighting" \
		-variable $V\(-lightbrace\)
	$m add checkbutton -label "Command Highlighting" \
		-variable $V\(-lightcmd\)
	$m add checkbutton -label "Grab Puts Output" \
		-variable $V\(-grabputs\) \
		-command [namespace code "configure [list $W] \
		-grabputs \[set ${V}(-grabputs)\]"]
	$m add checkbutton -label "History Substitution" \
		-variable $V\(-subhistory\)
	$m add checkbutton -label "Show Multiple Matches" \
		-variable $V\(-showmultiple\)
	$m add checkbutton -label "Show Menubar" \
		-variable $V\(-showmenu\) \
		-command [namespace code "configure [list $W] \
		-showmenu \[set ${V}(-showmenu)\]"]
    }

    ## History Menu
    ##
    set n hist
    set l "History"
    pack [menubutton $w.$n -text $l -underline 0 -menu $w.$n.m] -side left
    $w.pop add cascade -label $l -underline 0 -menu $w.pop.$n
    foreach m [list $w.$n.m $w.pop.$n] {
	menu $m -disabledforeground $data(-promptcolor) \
		-postcommand [namespace code [list HistoryMenu $W $m]]
    }

    ## Help Menu
    ##
    set n help
    set l "Help"
    pack [menubutton $w.$n -text $l -underline 0 -menu $w.$n.m] -side right
    $w.pop add cascade -label $l -underline 0 -menu $w.pop.$n
    foreach m [list [menu $w.$n.m] [menu $w.pop.$n]] {
	$m config -disabledfore $data(-promptcolor)
	$m add command -label "About " -underline 0 \
		-accelerator [event info <<Console_About>>] \
		-command [namespace code [list About $W]]
    }

    bind $W <<Console_Exit>>	[namespace code [list Exit $W]]
    bind $W <<Console_About>>	[namespace code [list About $W]]
    bind $W <<Console_Help>>	[namespace code [list Help $W]]
    bind $W <<Console_Find>>	[namespace code [list FindBox $W]]

    ## Menu items need null PostConsole bindings to avoid the TagProc
    ##
    foreach ev [bind $W] {
	bind PostConsole $ev {
	    # empty
	}
    }
}

# AttachMenu --
#
#   ADD COMMENTS HERE
#
# Arguments:
#   args	comments
# Results:
#   Returns ...
#
;proc AttachMenu {W m {type default}} {
    upvar \#0 [namespace current]::$W data
}

## HistoryMenu - dynamically build the menu for attached interpreters
##
# ARGS:	w	- menu widget
##
;proc HistoryMenu {W w} {
    upvar \#0 [namespace current]::$W data

    if {![winfo exists $w]} return
    set id [EvalSlave history nextid]
    if {$data(histid)==$id} return
    set data(histid) $id
    $w delete 0 end
    set con $data(console)
    while {$id>0 && ($id>$data(histid)-10) && \
	    ![catch {EvalSlave history event [incr id -1]} tmp]} {
	set lbl [lindex [split $tmp "\n"] 0]
	if {[string len $lbl]>32} { set lbl [string range $tmp 0 29]... }
	$w add command -label "$id: $lbl" -command [namespace code "
	$con delete promptEnd end
	$con insert promptEnd [list $tmp]
	$con see end
	Eval $con\n"]
    }
}

## FindBox - creates minimal dialog interface to Find
# ARGS:	w	- text widget
#	str	- optional seed string for data(find)
##
;proc FindBox {W {str {}}} {
    set V [namespace current]::$W
    upvar \#0 $V data

    highlight_dialog $data(console)
    return

    set t $data(console)
    set base $W.find
    if {![winfo exists $base]} {
	toplevel $base
	wm withdraw $base
	wm title $base "Console Find"

	pack [frame $base.f] -fill x -expand 1
	label $base.f.l -text "Find:"
	entry $base.f.e -textvar ${V}(find)
	pack [frame $base.opt] -fill x
	checkbutton $base.opt.c -text "Case Sensitive" -var ${V}(find,case)
	checkbutton $base.opt.r -text "Use Regexp" -var ${V}(find,reg)
	pack $base.f.l -side left
	pack $base.f.e $base.opt.c $base.opt.r -side left -fill both -expand 1
	pack [frame $base.sep -bd 2 -relief sunken -height 4] -fill x
	pack [frame $base.btn] -fill both
	button $base.btn.fnd -text "Find" -width 6
	button $base.btn.clr -text "Clear" -width 6
	button $base.btn.dis -text "Dismiss" -width 6
	eval pack [winfo children $base.btn] -padx 4 -pady 2 \
		-side left -fill both

	focus $base.f.e

	bind $base.f.e <Return> [list $base.btn.fnd invoke]
	bind $base.f.e <Escape> [list $base.btn.dis invoke]
    }
    $base.btn.fnd config -command [namespace code \
	    "highlight [list $data(console)] \[set ${V}(find)\] \
	    \[expr {\[set ${V}(find,case)\]?{}:{-nocase}}] \
	    \[expr {\[set ${V}(find,reg)\]?{-regexp}:{}}] \
	    -tag __highlight -color [list $data(-blinkcolor)]"]
    $base.btn.clr config -command "
    $t tag remove __highlight 1.0 end
    set ${V}(find) {}
    "
    $base.btn.dis config -command "
    $t tag remove __highlight 1.0 end
    wm withdraw $base
    "
    if {[string compare {} $str]} {
	set data(find) $str
	$base.btn.fnd invoke
    }

    if {[string compare normal [wm state $base]]} {
	wm deiconify $base
    } else { raise $base }
    $base.f.e select range 0 end
}

## savecommand - saves a command in a buffer for later retrieval
#
##
;proc savecommand {w} {
    upvar \#0 [namespace current]::[winfo parent $w] data

    set tmp $data(cmdsave)
    set data(cmdsave) [CmdGet $w]
    if {[string match {} $data(cmdsave)]} {
	set data(cmdsave) $tmp
    } else {
	$w delete promptEnd end-1c
    }
    $w insert promptEnd $tmp
    $w see end
}

## _load - sources a file into the console
# ARGS:	fn	- (optional) filename to source in
# Returns:	selected filename ({} if nothing was selected)
## 
;proc _load {W {fn ""}} {
    set types {
	{{Tcl Files}	{.tcl .tk}}
	{{Text Files}	{.txt}}
	{{All Files}	*}
    }
    if {
	[string match {} $fn] &&
	([catch {tk_getOpenFile -filetypes $types \
	    -title "Source File into Attached Interpreter"} fn]
	|| [string match {} $fn])
    } { return }
    EvalAttached [list source $fn]
}

## _save - saves the console buffer to a file
## This does not eval in a slave because it's not necessary
# ARGS:	w	- console text widget
# 	fn	- (optional) filename to save to
## 
;proc _save {W {type ""} {fn ""}} {
    upvar \#0 [namespace current]::$W data

    set c $data(console)
    if {![regexp -nocase {^(all|history|stdin|stdout|stderr)$} $type]} {
	array set s { 0 All 1 History 2 Stdin 3 Stdout 4 Stderr 5 Cancel }
	## Allow user to specify what kind of stuff to save
	set type [tk_dialog $W.savetype "Save Type" \
		"What part of the console text do you want to save?" \
		questhead 0 $s(0) $s(1) $s(2) $s(3) $s(4) $s(5)]
	if {$type == 5 || $type == -1} return
	set type $s($type)
    }
    if {[string match {} $fn]} {
	set types {
	    {{Text Files}	{.txt}}
	    {{Tcl Files}	{.tcl .tk}}
	    {{All Files}	*}
	}
	if {[catch {tk_getSaveFile -filetypes $types -title "Save $type"} fn] \
		|| [string match {} $fn]} return
    }
    set type [string tolower $type]
    set output {}
    switch $type {
	stdin -	stdout - stderr {
	    foreach {first last} [$c tag ranges $type] {
		lappend output [$c get $first $last]
	    }
	    set output [join $data \n]
	}
	history		{ set output [_history $W] }
	all - default	{ set output [$c get 1.0 end-1c] }
    }
    if {[catch {open $fn w} fid]} {
	return -code error "Save Error: Unable to open '$fn' for writing\n$fid"
    }
    puts $fid $output
    close $fid
}

## clear - clears the buffer of the console (not the history though)
## 
;proc _clear {W {pcnt 100}} {
    upvar \#0 [namespace current]::$W data

    set data(tmp) [CmdGet $data(console)]
    if {![regexp {^[0-9]*$} $pcnt] || $pcnt < 1 || $pcnt > 100} {
	return -code error \
		"invalid percentage to clear: must be 1-100 (100 default)"
    } elseif {$pcnt == 100} {
	$data(console) delete 1.0 end
    } else {
	set tmp [expr {$pcnt/100.0*[$data(console) index end]}]
	$data(console) delete 1.0 "$tmp linestart"
    }
    prompt $W {} $data(tmp)
}

;proc _error {W} {
    ## Outputs stack caused by last error.
    upvar \#0 [namespace current]::$W data
    set info $data(errorInfo)
    if {[string match {} $info]} { set info {errorInfo empty} }
    catch {destroy $W.error}
    set w [toplevel $W.error]
    wm title $w "Console Last Error"
    button $w.close -text Dismiss -command [list destroy $w]
    scrollbar $w.sy -takefocus 0 -bd 1 -command [list $w.text yview]
    text $w.text -yscrollcommand [list $w.sy set]
    pack $w.close -side bottom -fill x
    pack $w.sy -side right -fill y
    pack $w.text -fill both -expand 1
    $w.text insert 1.0 $info
    $w.text config -state disabled
}

## _event - searches for history based on a string
## Search forward (next) if $int>0, otherwise search back (prev)
# ARGS:	W	- console widget
##
;proc _event {W int {str {}}} {
    upvar \#0 [namespace current]::$W data

    if {!$int} return
    set w $data(console)

    set nextid [EvalSlave history nextid]
    if {[string compare {} $str]} {
	## String is not empty, do an event search
	set event $data(event)
	if {$int < 0 && $event == $nextid} { set data(cmdbuf) $str }
	set len [string len $data(cmdbuf)]
	incr len -1
	if {$int > 0} {
	    ## Search history forward
	    while {$event < $nextid} {
		if {[incr event] == $nextid} {
		    $w delete promptEnd end
		    $w insert promptEnd $data(cmdbuf)
		    break
		} elseif {![catch {EvalSlave history event $event} res] \
			&& ![string compare $data(cmdbuf) \
			[string range $res 0 $len]]} {
		    $w delete promptEnd end
		    $w insert promptEnd $res
		    break
		}
	    }
	    set data(event) $event
	} else {
	    ## Search history reverse
	    while {![catch {EvalSlave history event [incr event -1]} res]} {
		if {![string compare $data(cmdbuf) \
			[string range $res 0 $len]]} {
		    $w delete promptEnd end
		    $w insert promptEnd $res
		    set data(event) $event
		    break
		}
	    }
	} 
    } else {
	## String is empty, just get next/prev event
	if {$int > 0} {
	    ## Goto next command in history
	    if {$data(event) < $nextid} {
		$w delete promptEnd end
		if {[incr data(event)] == $nextid} {
		    $w insert promptEnd $data(cmdbuf)
		} else {
		    $w insert promptEnd [EvalSlave history event $data(event)]
		}
	    }
	} else {
	    ## Goto previous command in history
	    if {$data(event) == $nextid} {set data(cmdbuf) [CmdGet $w]}
	    if {[catch {EvalSlave history event [incr data(event) -1]} res]} {
		incr data(event)
	    } else {
		$w delete promptEnd end
		$w insert promptEnd $res
	    }
	}
    }
    $w mark set insert end
    $w see end
}

;proc _history {W args} {
    set sub {\2}
    if {[string match -n* $args]} { append sub "\n" }
    set h [EvalSlave history]
    regsub -all "( *\[0-9\]+  |\t)(\[^\n\]*\n?)" $h $sub h
    return $h
}

##
## Some procedures to make up for lack of built-in shell commands
##

## puts
## This allows me to capture all stdout/stderr to the console window
# ARGS:	same as usual	
# Outputs:	the string with a color-coded text tag
## 
if {![catch {rename ::puts ::console_tcl_puts}]} {
    ;proc ::puts args {
	if {![catch {widget value Console active} active] && \
		[winfo exists [lindex $active 0]]} {
	    set w [lindex $active 0]
	    set len [llength $args]
	    if {$len==1} {
		eval $w insert output $args stdout {\n} stdout
		$w see output
	    } elseif {$len==2 && [regexp {(stdout|stderr|-nonewline)} \
		    [lindex $args 0] junk tmp]} {
		if {[string compare $tmp -nonewline]} {
		    eval $w insert output [lreplace $args 0 0] $tmp {\n} $tmp
		} else {
		    eval $w insert output [lreplace $args 0 0] stdout
		}
		$w see output
	    } elseif {$len==3 && \
		    [regexp {(stdout|stderr)} [lreplace $args 2 2] junk tmp]} {
		if {[string compare [lreplace $args 1 2] -nonewline]} {
		    eval $w insert output [lrange $args 1 1] $tmp
		} else {
		    eval $w insert output [lreplace $args 0 1] $tmp
		}
		$w see output
	    } else {
		global errorCode errorInfo
		if {[catch "::console_tcl_puts $args" msg]} {
		    regsub console_tcl_puts $msg puts msg
		    regsub -all console_tcl_puts \
			    $errorInfo puts errorInfo
		    error $msg
		}
		return $msg
	    }
	    if {$len} update
	} else {
	    global errorCode errorInfo
	    if {[catch "::console_tcl_puts $args" msg]} {
		regsub console_tcl_puts $msg puts msg
		regsub -all console_tcl_puts $errorInfo puts errorInfo
		error $msg
	    }
	    return $msg
	}
    }
}

if {!$class(WWW)} {;
## We exclude the reworking of unknown for the plugin

## Unknown changed to get output into Console window
# unknown:
# Invoked automatically whenever an unknown command is encountered.
# Works through a list of "unknown handlers" that have been registered
# to deal with unknown commands.  Extensions can integrate their own
# handlers into the "unknown" facility via "unknown_handle".
#
# If a handler exists that recognizes the command, then it will
# take care of the command action and return a valid result or a
# Tcl error.  Otherwise, it should return "-code continue" (=2)
# and responsibility for the command is passed to the next handler.
#
# Arguments:
# args -	A list whose elements are the words of the original
#		command, including the command name.

proc ::unknown args {
    global unknown_handler_order unknown_handlers errorInfo errorCode

    #
    # Be careful to save error info now, and restore it later
    # for each handler.  Some handlers generate their own errors
    # and disrupt handling.
    #
    set savedErrorCode $errorCode
    set savedErrorInfo $errorInfo

    if {![info exists unknown_handler_order] || \
	    ![info exists unknown_handlers]} {
	set unknown_handlers(tcl) tcl_unknown
	set unknown_handler_order tcl
    }

    foreach handler $unknown_handler_order {
        set status [catch {uplevel $unknown_handlers($handler) $args} result]

        if {$status == 1} {
            #
            # Strip the last five lines off the error stack (they're
            # from the "uplevel" command).
            #
            set new [split $errorInfo \n]
            set new [join [lrange $new 0 [expr {[llength $new] - 6}]] \n]
            return -code $status -errorcode $errorCode \
		    -errorinfo $new $result

        } elseif {$status != 4} {
            return -code $status $result
        }

        set errorCode $savedErrorCode
        set errorInfo $savedErrorInfo
    }

    set name [lindex $args 0]
    return -code error "invalid command name \"$name\""
}

# tcl_unknown:
# Invoked when a Tcl command is invoked that doesn't exist in the
# interpreter:
#
#	1. See if the autoload facility can locate the command in a
#	   Tcl script file.  If so, load it and execute it.
#	2. If the command was invoked interactively at top-level:
#	    (a) see if the command exists as an executable UNIX program.
#		If so, "exec" the command.
#	    (b) see if the command requests csh-like history substitution
#		in one of the common forms !!, !<number>, or ^old^new.  If
#		so, emulate csh's history substitution.
#	    (c) see if the command is a unique abbreviation for another
#		command.  If so, invoke the command.
#
# Arguments:
# args -	A list whose elements are the words of the original
#		command, including the command name.

proc ::tcl_unknown args {
    global auto_noexec auto_noload env unknown_pending tcl_interactive
    global errorCode errorInfo

    # Save the values of errorCode and errorInfo variables, since they
    # may get modified if caught errors occur below.  The variables will
    # be restored just before re-executing the missing command.

    set savedErrorCode $errorCode
    set savedErrorInfo $errorInfo
    set name [lindex $args 0]
    if {![info exists auto_noload]} {
	#
	# Make sure we're not trying to load the same proc twice.
	#
	if {[info exists unknown_pending($name)]} {
	    return -code error "self-referential recursion in \"unknown\" for command \"$name\"";
	}
	set unknown_pending($name) pending;
	set ret [catch {auto_load $name} msg]
	unset unknown_pending($name);
	if {$ret != 0} {
	    return -code $ret -errorcode $errorCode \
		    "error while autoloading \"$name\": $msg"
	}
	if {![array size unknown_pending]} {
	    unset unknown_pending
	}
	if {$msg} {
	    set errorCode $savedErrorCode
	    set errorInfo $savedErrorInfo
	    set code [catch {uplevel 1 $args} msg]
	    if {$code ==  1} {
		#
		# Strip the last five lines off the error stack (they're
		# from the "uplevel" command).
		#

		set new [split $errorInfo \n]
		set new [join [lrange $new 0 [expr {[llength $new] - 6}]] \n]
		return -code error -errorcode $errorCode \
			-errorinfo $new $msg
	    } else {
		return -code $code $msg
	    }
	}
    }
    if {[info level] == 1 && [string match {} [info script]] \
	    && [info exists tcl_interactive] && $tcl_interactive} {
	if {![info exists auto_noexec]} {
	    set new [auto_execok $name]
	    if {[string compare $new ""]} {
		set errorCode $savedErrorCode
		set errorInfo $savedErrorInfo
                set redir ""
                if {[info commands console] == ""} {
                    set redir ">&@stdout <@stdin"
                }
                return [uplevel exec $redir $new [lrange $args 1 end]]
	    }
	}
	set errorCode $savedErrorCode
	set errorInfo $savedErrorInfo
	##
	## History substitution moved into EvalCmd
	##
	set ret [catch {set cmds [info commands $name*]} msg]
	if {![string compare $name "::"]} {
	    set name ""
	}
	if {$ret != 0} {
	    return -code $ret -errorcode $errorCode \
		"error in unknown while checking if \"$name\" is a unique command abbreviation: $msg"
	}
	if {[llength $cmds] == 1} {
	    return [uplevel [lreplace $args 0 0 $cmds]]
	}
	if {[llength $cmds]} {
	    if {$name == ""} {
		return -code error "empty command name \"\""
	    } else {
		return -code error \
			"ambiguous command name \"$name\": [lsort $cmds]"
	    }
	}
    }
    return -code continue
}

}; # end switch on proc unknown

switch -glob $tcl_platform(platform) {
    win* { set META Alt }
    mac* { set META Command }
    default { set META Meta }
}

# ClipboardKeysyms --
# This procedure is invoked to identify the keys that correspond to
# the "copy", "cut", and "paste" functions for the clipboard.
#
# Arguments:
# copy -	Name of the key (keysym name plus modifiers, if any,
#		such as "Meta-y") used for the copy operation.
# cut -		Name of the key used for the cut operation.
# paste -	Name of the key used for the paste operation.

;proc ClipboardKeysyms {copy cut paste} {
    bind Console <$copy>	[namespace code {Copy %W}]
    bind Console <$cut>		[namespace code {Cut %W}]
    bind Console <$paste>	[namespace code {Paste %W}]
}

;proc Cut w {
    if {[string match $w [selection own -displayof $w]]} {
	clipboard clear -displayof $w
	catch {
	    clipboard append -displayof $w [selection get -displayof $w]
	    if {[$w compare sel.first >= promptEnd]} {$w delete sel.first sel.last}
	}
    }
}
;proc Copy w {
    if {[string match $w [selection own -displayof $w]]} {
	clipboard clear -displayof $w
	catch {clipboard append -displayof $w [selection get -displayof $w]}
    }
}

;proc Paste w {
    if {
	![catch {selection get -displayof $w} tmp] ||
	![catch {selection get -displayof $w -type TEXT} tmp] ||
	![catch {selection get -displayof $w -selection CLIPBOARD} tmp]
    } {
	if {[$w compare insert < promptEnd]} {$w mark set insert end}
	$w insert insert $tmp
	$w see insert
	if {[string match *\n* $tmp]} {Eval $w}
    }
}

## Get all Text bindings into Console
foreach ev [bind Text] { bind Console $ev [namespace code [bind Text $ev]] }
## We don't want newline insertion
bind Console <Control-Key-o> {}

foreach {ev key} {
    <<Console_Prev>>		<Key-Up>
    <<Console_Next>>		<Key-Down>
    <<Console_NextImmediate>>	<Control-Key-n>
    <<Console_PrevImmediate>>	<Control-Key-p>
    <<Console_PrevSearch>>	<Control-Key-r>
    <<Console_NextSearch>>	<Control-Key-s>

    <<Console_Expand>>		<Key-Tab>
    <<Console_ExpandFile>>	<Key-Escape>
    <<Console_ExpandProc>>	<Control-Shift-Key-P>
    <<Console_ExpandVar>>	<Control-Shift-Key-V>
    <<Console_Tab>>		<Control-Key-i>
    <<Console_Tab>>		<Meta-Key-i>
    <<Console_Eval>>		<Key-Return>
    <<Console_Eval>>		<Key-KP_Enter>

    <<Console_Clear>>		<Control-Key-l>
    <<Console_KillLine>>	<Control-Key-k>
    <<Console_Transpose>>	<Control-Key-t>
    <<Console_ClearLine>>	<Control-Key-u>
    <<Console_SaveCommand>>	<Control-Key-z>

    <<Console_Exit>>		<Control-Key-q>
    <<Console_New>>		<Control-Key-N>
    <<Console_Close>>		<Control-Key-w>
    <<Console_About>>		<Control-Key-A>
    <<Console_Help>>		<Control-Key-H>
    <<Console_Find>>		<Control-Key-F>
} {
    event add $ev $key
    bind Console $key {}
}
catch {unset ev key}

## Redefine for Console what we need
##
event delete <<Paste>> <Control-V>
ClipboardKeysyms <Copy> <Cut> <Paste>

bind Console <Insert> {catch {Insert %W [selection get -displayof %W]}}

bind Console <Triple-1> {+
catch {
    eval %W tag remove sel [%W tag nextrange prompt sel.first sel.last]
    eval %W tag remove sel sel.last-1c
    %W mark set insert sel.first
}
}

bind Console <<Console_Expand>> [namespace code {
    if {[%W compare insert > promptEnd]} {Expand %W}
    break
}]
bind Console <<Console_ExpandFile>> [namespace code {
    if {[%W compare insert > promptEnd]} {Expand %W path}
    break
}]
bind Console <<Console_ExpandProc>> [namespace code {
    if {[%W compare insert > promptEnd]} {Expand %W proc}
    break
}]
bind Console <<Console_ExpandVar>> [namespace code {
    if {[%W compare insert > promptEnd]} {Expand %W var}
    break
}]
bind Console <<Console_Tab>> [namespace code {
    if {[%W compare insert >= promptEnd]} {	Insert %W \t }
}]
bind Console <<Console_Eval>> [namespace code { Eval %W }]
bind Console <Delete> {
    if {[string compare {} [%W tag nextrange sel 1.0 end]] \
	    && [%W compare sel.first >= promptEnd]} {
	%W delete sel.first sel.last
    } elseif {[%W compare insert >= promptEnd]} {
	%W delete insert
	%W see insert
    }
}
bind Console <BackSpace> {
    if {[string compare {} [%W tag nextrange sel 1.0 end]] \
	    && [%W compare sel.first >= promptEnd]} {
	%W delete sel.first sel.last
    } elseif {[%W compare insert != 1.0] && [%W compare insert > promptEnd]} {
	%W delete insert-1c
	%W see insert
    }
}
bind Console <Control-h> [bind Console <BackSpace>]

bind Console <KeyPress> [namespace code { Insert %W %A }]

bind Console <Control-a> {
    if {[%W compare {promptEnd linestart} == {insert linestart}]} {
	tkTextSetCursor %W promptEnd
    } else {
	tkTextSetCursor %W {insert linestart}
    }
}
bind Console <Control-d> {
    if {[%W compare insert < promptEnd]} break
    %W delete insert
}
bind Console <<Console_KillLine>> {
    if {[%W compare insert < promptEnd]} break
    if {[%W compare insert == {insert lineend}]} {
	%W delete insert
    } else {
	%W delete insert {insert lineend}
    }
}
bind Console <<Console_Clear>> [namespace code { _clear [winfo parent %W] }]
bind Console <<Console_Prev>> [namespace code {
    if {[%W compare {insert linestart} != {promptEnd linestart}]} {
	tkTextSetCursor %W [tkTextUpDownLine %W -1]
    } else {
	_event [winfo parent %W] -1
    }
}]
bind Console <<Console_Next>> [namespace code {
    if {[%W compare {insert linestart} != {end-1c linestart}]} {
	tkTextSetCursor %W [tkTextUpDownLine %W 1]
    } else {
	_event [winfo parent %W] 1
    }
}]
bind Console <<Console_NextImmediate>> [namespace code {
    _event [winfo parent %W] 1
}]
bind Console <<Console_PrevImmediate>> [namespace code {
    _event [winfo parent %W] -1
}]
bind Console <<Console_PrevSearch>> [namespace code {
    _event [winfo parent %W] -1 [CmdGet %W]
}]
bind Console <<Console_NextSearch>> [namespace code {
    _event [winfo parent %W] 1 [CmdGet %W]
}]
bind Console <<Console_Transpose>> {
    ## Transpose current and previous chars
    if {[%W compare insert > promptEnd]} { tkTextTranspose %W }
}
bind Console <<Console_ClearLine>> {
    ## Clear command line (Unix shell staple)
    %W delete promptEnd end
}
bind Console <<Console_SaveCommand>> [namespace code {
    ## Save command buffer (swaps with current command)
    savecommand %W
}]
catch {bind Console <Key-Page_Up>   { tkTextScrollPages %W -1 }}
catch {bind Console <Key-Prior>     { tkTextScrollPages %W -1 }}
catch {bind Console <Key-Page_Down> { tkTextScrollPages %W 1 }}
catch {bind Console <Key-Next>      { tkTextScrollPages %W 1 }}
bind Console <$META-d> {
    if {[%W compare insert >= promptEnd]} {
	%W delete insert {insert wordend}
    }
}
bind Console <$META-BackSpace> {
    if {[%W compare {insert -1c wordstart} >= promptEnd]} {
	%W delete {insert -1c wordstart} insert
    }
}
bind Console <$META-Delete> {
    if {[%W compare insert >= promptEnd]} {
	%W delete insert {insert wordend}
    }
}
bind Console <ButtonRelease-2> {
    ## Try and get the default selection, then try and get the selection
    ## type TEXT, then try and get the clipboard if nothing else is available
    if {
	(!$tkPriv(mouseMoved) || $tk_strictMotif) &&
	(![catch {selection get -displayof %W} tkPriv(junk)] ||
	![catch {selection get -displayof %W -type TEXT} tkPriv(junk)] ||
	![catch {selection get -displayof %W \
		-selection CLIPBOARD} tkPriv(junk)])
    } {
	if {[%W compare @%x,%y < promptEnd]} {
	    %W insert end $tkPriv(junk)
	} else {
	    %W insert @%x,%y $tkPriv(junk)
	}
	if {[string match *\n* $tkPriv(junk)]} {
	    namespace inscope ::Widget::Console { Eval %W }
	}
    }
}

##
## End Console bindings
##

##
## Bindings for doing special things based on certain keys
##
bind PostConsole <Key-parenright> [namespace code {
    if {[string compare \\ [%W get insert-2c]]} {MatchPair %W \( \) promptEnd}
}]
bind PostConsole <Key-bracketright> [namespace code {
    if {[string compare \\ [%W get insert-2c]]} {MatchPair %W \[ \] promptEnd}
}]
bind PostConsole <Key-braceright> [namespace code {
    if {[string compare \\ [%W get insert-2c]]} {MatchPair %W \{ \} promptEnd}
}]
bind PostConsole <Key-quotedbl> [namespace code {
    if {[string compare \\ [%W get insert-2c]]} {MatchQuote %W promptEnd}
}]

bind PostConsole <KeyPress> [namespace code {
    if {[string compare {} %A]} {TagProc %W}
}]


## TagProc - tags a procedure in the console if it's recognized
## This procedure is not perfect.  However, making it perfect wastes
## too much CPU time...  Also it should check the existence of a command
## in whatever is the connected slave, not the master interpreter.
##
;proc TagProc w {
    upvar \#0 [namespace current]::[winfo parent $w] data
    if {!$data(-lightcmd)} return
    set exp "\[^\\\\\]\[\[ \t\n\r\;{}\"\$\]"
    set i [$w search -backwards -regexp $exp insert-1c promptEnd-1c]
    if {[string compare {} $i]} {append i +2c} {set i promptEnd}
    regsub -all "\[\[\\\\\\?\\*\]" [$w get $i "insert-1c wordend"] {\\\0} c
    if {[string compare {} [EvalAttached info commands [list $c]]]} {
	$w tag add proc $i "insert-1c wordend"
    } else {
	$w tag remove proc $i "insert-1c wordend"
    }
    if {[string compare {} [EvalAttached info vars [list $c]]]} {
	$w tag add var $i "insert-1c wordend"
    } else {
	$w tag remove var $i "insert-1c wordend"
    }
}

## MatchPair - blinks a matching pair of characters
## c2 is assumed to be at the text index 'insert'.
## This proc is really loopy and took me an hour to figure out given
## all possible combinations with escaping except for escaped \'s.
## It doesn't take into account possible commenting... Oh well.  If
## anyone has something better, I'd like to see/use it.  This is really
## only efficient for small contexts.
# ARGS:	w	- console text widget
# 	c1	- first char of pair
# 	c2	- second char of pair
# Calls:	blink
## 
;proc MatchPair {w c1 c2 {lim 1.0}} {
    upvar \#0 [namespace current]::[winfo parent $w] data
    if {!$data(-lightbrace) || $data(-blinktime)<100} return
    if {[string compare [set ix [$w search -back $c1 insert $lim]] {}]} {
	while {[string match {\\} [$w get $ix-1c]] && \
		[string compare [set ix [$w search -back $c1 $ix-1c $lim]] {}]} {}
	set i1 insert-1c
	while {[string compare $ix {}]} {
	    set i0 $ix
	    set j 0
	    while {[string compare [set i0 [$w search $c2 $i0 $i1]] {}]} {
		append i0 +1c
		if {[string match {\\} [$w get $i0-2c]]} continue
		incr j
	    }
	    if {!$j} break
	    set i1 $ix
	    while {$j && [string compare \
		    [set ix [$w search -back $c1 $ix $lim]] {}]} {
		if {[string match {\\} [$w get $ix-1c]]} continue
		incr j -1
	    }
	}
	if {[string match {} $ix]} { set ix [$w index $lim] }
    } else {
	set ix [$w index $lim]
    }
    if {$data(-blinkrange)} {
	blink $w $data(-blinktime) $ix [$w index insert]
    } else {
	blink $w $data(-blinktime) $ix $ix+1c \
		[$w index insert-1c] [$w index insert]
    }
}

## MatchQuote - blinks between matching quotes.
## Blinks just the quote if it's unmatched, otherwise blinks quoted string
## The quote to match is assumed to be at the text index 'insert'.
# ARGS:	w	- console text widget
# Calls:	blink
## 
;proc MatchQuote {w {lim 1.0}} {
    upvar \#0 [namespace current]::[winfo parent $w] data
    if {!$data(-lightbrace) || $data(-blinktime)<100} return
    set i insert-1c
    set j 0
    while {[string compare {} [set i [$w search -back \" $i $lim]]]} {
	if {[string match {\\} [$w get $i-1c]]} continue
	if {!$j} {set i0 $i}
	incr j
    }
    if {$j & 1} {
	if {$data(-blinkrange)} {
	    blink $w $data(-blinktime) $i0 [$w index insert]
	} else {
	    blink $w $data(-blinktime) $i0 $i0+1c \
		    [$w index insert-1c] [$w index insert]
	}
    } else {
	blink $w $data(-blinktime) [$w index insert-1c] \
		[$w index insert]
    }
}

## blink - blinks between 2 indices for a specified duration.
# ARGS:	w	- console text widget
#	delay	- millisecs to blink for
# 	args	- indices of regions to blink
# Outputs:	blinks selected characters in $w
## 
;proc blink {w delay args} {
    eval $w tag add blink $args
    after $delay eval $w tag remove blink $args
    return
}


## Insert
## Insert a string into a text console at the point of the insertion cursor.
## If there is a selection in the text, and it covers the point of the
## insertion cursor, then delete the selection before inserting.
# ARGS:	w	- text window in which to insert the string
# 	s	- string to insert (usually just a single char)
# Outputs:	$s to text widget
## 
;proc Insert {w s} {
    if {[string match {} $s] || [string match disabled [$w cget -state]]} {
	return
    }
    if {[$w comp insert < promptEnd]} {
	$w mark set insert end
    }
    catch {
	if {[$w comp sel.first <= insert] && [$w comp sel.last >= insert]} {
	    $w delete sel.first sel.last
	}
    }
    $w insert insert $s
    $w see insert
}

## Expand - 
# ARGS:	w	- text widget in which to expand str
# 	type	- type of expansion (path / proc / variable)
# Calls:	Expand(Pathname|Procname|Variable)
# Outputs:	The string to match is expanded to the longest possible match.
#		If data(-showmultiple) is non-zero and the user longest match
#		equaled the string to expand, then all possible matches are
#		output to stdout.  Triggers bell if no matches are found.
# Returns:	number of matches found
## 
## FIX: make namespace aware
;proc Expand {w {type ""}} {
    set exp "\[^\\\\\]\[\[ \t\n\r\\\{\"\\\\\$\]"
    set tmp [$w search -backwards -regexp $exp insert-1c promptEnd-1c]
    if {[string compare {} $tmp]} {append tmp +2c} else {set tmp promptEnd}
    if {[$w compare $tmp >= insert]} return
    set str [$w get $tmp insert]
    switch -glob $type {
	pa* { set res [ExpandPathname $str] }
	pr* { set res [ExpandProcname $str] }
	v*  { set res [ExpandVariable $str] }
	default {
	    set res {}
	    foreach t {Pathname Procname Variable} {
		if {[string compare {} [set res [Expand$t $str]]]} break
	    }
	}
    }
    set len [llength $res]
    if {$len} {
	$w delete $tmp insert
	$w insert $tmp [lindex $res 0]
	if {$len > 1} {
	    upvar \#0 [namespace current]::[winfo parent $w] data
	    if {$data(-showmultiple) && \
		    ![string compare [lindex $res 0] $str]} {
		puts stdout [lsort [lreplace $res 0 0]]
	    }
	}
    } else { bell }
    return [incr len -1]
}

## ExpandPathname - expand a file pathname based on $str
## This is based on UNIX file name conventions
# ARGS:	str	- partial file pathname to expand
# Calls:	ExpandBestMatch
# Returns:	list containing longest unique match followed by all the
#		possible further matches
## 
;proc ExpandPathname str {
    set pwd [EvalAttached pwd]
    if {[catch {EvalAttached [list cd [file dirname $str]]} err]} {
	return -code error $err
    }
    if {[catch {lsort -dict [EvalAttached [list glob [file tail $str]*]]} m]} {
	set match {}
    } else {
	if {[llength $m] > 1} {
	    global tcl_platform
	    if {[string match windows $tcl_platform(platform)]} {
		## Windows is screwy because it's can be case insensitive
		set tmp [best_match [string tolower $m] \
			[string tolower [file tail $str]]]
	    } else {
		set tmp [best_match $m [file tail $str]]
	    }
	    if {[string match ?*/* $str]} {
		set tmp [file dirname $str]/$tmp
	    } elseif {[string match /* $str]} {
		set tmp /$tmp
	    }
	    regsub -all { } $tmp {\\ } tmp
	    set match [linsert $m 0 $tmp]
	} else {
	    ## This may look goofy, but it handles spaces in path names
	    eval append match $m
	    if {[file isdir $match]} {append match /}
	    if {[string match ?*/* $str]} {
		set match [file dirname $str]/$match
	    } elseif {[string match /* $str]} {
		set match /$match
	    }
	    regsub -all { } $match {\\ } match
	    ## Why is this one needed and the ones below aren't!!
	    set match [list $match]
	}
    }
    EvalAttached [list cd $pwd]
    return $match
}

## ExpandProcname - expand a tcl proc name based on $str
# ARGS:	str	- partial proc name to expand
# Calls:	best_match
# Returns:	list containing longest unique match followed by all the
#		possible further matches
## 
;proc ExpandProcname str {
    set match [EvalAttached [list info commands $str*]]
    if {[llength $match] > 1} {
	regsub -all { } [best_match $match $str] {\\ } str
	set match [linsert $match 0 $str]
    } else {
	regsub -all { } $match {\\ } match
    }
    return $match
}

## ExpandVariable - expand a tcl variable name based on $str
# ARGS:	str	- partial tcl var name to expand
# Calls:	best_match
# Returns:	list containing longest unique match followed by all the
#		possible further matches
## 
;proc ExpandVariable str {
    if {[regexp {([^\(]*)\((.*)} $str junk ary str]} {
	## Looks like they're trying to expand an array.
	set match [EvalAttached [list array names $ary $str*]]
	if {[llength $match] > 1} {
	    set vars $ary\([best_match $match $str]
	    foreach var $match {lappend vars $ary\($var\)}
	    return $vars
	} else {set match $ary\($match\)}
	## Space transformation avoided for array names.
    } else {
	set match [EvalAttached [list info vars $str*]]
	if {[llength $match] > 1} {
	    regsub -all { } [best_match $match $str] {\\ } str
	    set match [linsert $match 0 $str]
	} else {
	    regsub -all { } $match {\\ } match
	}
    }
    return $match
}

## resource - re'source's this script into current console
## Meant primarily for my development of this program.  It follows
## links until the ultimate source is found.
##
set class(SCRIPT) [info script]
if {!$class(WWW)} {
    while {[string match link [file type $class(SCRIPT)]]} {
	set link [file readlink $class(SCRIPT)]
	if {[string match relative [file pathtype $link]]} {
	    set class(SCRIPT) [file join \
		    [file dirname $class(SCRIPT)] $link]
	} else {
	    set class(SCRIPT) $link
	}
    }
    catch {unset link}
    if {[string match relative [file pathtype $class(SCRIPT)]]} {
	set class(SCRIPT) [file join [pwd] $class(SCRIPT)]
    }
}

;proc resource {} {
    upvar \#0 [namespace current] class
    uplevel \#0 [list source $class(SCRIPT)]
}

}; # end namespace ::Widget::Console

## dump - outputs variables/procedure/widget info in source'able form.
## Accepts glob style pattern matching for the names
#
# ARGS:	type	- type of thing to dump: must be variable, procedure, widget
#
# OPTS: -nocomplain
#		don't complain if no items of the specified type are found
#	-filter pattern
#		specifies a glob filter pattern to be used by the variable
#		method as an array filter pattern (it filters down for
#		nested elements) and in the widget method as a config
#		option filter pattern
#	--	forcibly ends options recognition
#
# Returns:	the values of the requested items in a 'source'able form
## 
proc dump {type args} {
    set whine 1
    set code  ok
    if {![llength $args]} {
	## If no args, assume they gave us something to dump and
	## we'll try anything
	set args $type
	set type any
    }
    while {[string match -* [lindex $args 0]]} {
	switch -glob -- [lindex $args 0] {
	    -n* { set whine 0; set args [lreplace $args 0 0] }
	    -f* { set fltr [lindex $args 1]; set args [lreplace $args 0 1] }
	    --  { set args [lreplace $args 0 0]; break }
	    default {return -code error "unknown option \"[lindex $args 0]\""}
	}
    }
    if {$whine && ![llength $args]} {
	return -code error "wrong \# args: [lindex [info level 0] 0] type\
		?-nocomplain? ?-filter pattern? ?--? pattern ?pattern ...?"
    }
    set res {}
    switch -glob -- $type {
	c* {
	    # command
	    # outputs commands by figuring out, as well as possible, what it is
	    # this does not attempt to auto-load anything
	    foreach arg $args {
		if {[llength [set cmds [info commands $arg]]]} {
		    foreach cmd [lsort $cmds] {
			if {[lsearch -exact [interp aliases] $cmd] > -1} {
			    append res "\#\# ALIAS:   $cmd =>\
				    [interp alias {} $cmd]\n"
			} elseif {
			    [llength [info procs $cmd]] ||
			    ([string match *::* $cmd] &&
			    [llength [namespace eval [namespace qual $cmd] \
				    info procs [namespace tail $cmd]]])
			} {
			    if {[catch {dump p -- $cmd} msg] && $whine} {
				set code error
			    }
			    append res $msg\n
			} else {
			    append res "\#\# COMMAND: $cmd\n"
			}
		    }
		} elseif {$whine} {
		    append res "\#\# No known command $arg\n"
		    set code error
		}
	    }
	}
	v* {
	    # variable
	    # outputs variables value(s), whether array or simple.
	    if {![info exists fltr]} { set fltr * }
	    foreach arg $args {
		if {![llength [set vars [uplevel 1 info vars [list $arg]]]]} {
		    if {[uplevel 1 info exists $arg]} {
			set vars $arg
		    } elseif {$whine} {
			append res "\#\# No known variable $arg\n"
			set code error
			continue
		    } else { continue }
		}
		foreach var [lsort $vars] {
		    if {[uplevel 1 [list info locals $var]] == ""} {
			# use the proper scope of the var, but namespace which
			# won't id locals or some upvar'ed vars correctly
			set new [uplevel 1 \
				[list namespace which -variable $var]]
			if {$new != ""} {
			    set var $new
			}
		    }
		    upvar 1 $var v
		    if {[array exists v] || [catch {string length $v}]} {
			set nst {}
			append res "array set [list $var] \{\n"
			if {[array size v]} {
			    foreach i \
				    [lsort -dictionary [array names v $fltr]] {
				upvar 0 v\($i\) __a
				if {[array exists __a]} {
				    append nst "\#\# NESTED ARRAY ELEM: $i\n"
				    append nst "upvar 0 [list $var\($i\)] __a;\
					    [dump v -filter $fltr __a]\n"
				} else {
				    append res "    [list $i]\t[list $v($i)]\n"
				}
			    }
			} else {
			    ## empty array
			    append res "    empty array\n"
			    if {$var == ""} {
				append nst "unset (empty)\n"
			    } else {
				append nst "unset [list $var](empty)\n"
			    }
			}
			append res "\}\n$nst"
		    } else {
			append res [list set $var $v]\n
		    }
		}
	    }
	}
	p* {
	    # procedure
	    foreach arg $args {
		if {
		    ![llength [set procs [info proc $arg]]] &&
		    ([string match *::* $arg] &&
		    [llength [set ps [namespace eval \
			    [namespace qualifier $arg] \
			    info procs [namespace tail $arg]]]])
		} {
		    set procs {}
		    set namesp [namespace qualifier $arg]
		    foreach p $ps {
			lappend procs ${namesp}::$p
		    }
		}
		if {[llength $procs]} {
		    foreach p [lsort $procs] {
			set as {}
			foreach a [info args $p] {
			    if {[info default $p $a tmp]} {
				lappend as [list $a $tmp]
			    } else {
				lappend as $a
			    }
			}
			append res [list proc $p $as [info body $p]]\n
		    }
		} elseif {$whine} {
		    append res "\#\# No known proc $arg\n"
		    set code error
		}
	    }
	}
	w* {
	    # widget
	    ## The user should have Tk loaded
	    if {![llength [info command winfo]]} {
		return -code error "winfo not present, cannot dump widgets"
	    }
	    if {![info exists fltr]} { set fltr .* }
	    foreach arg $args {
		if {[llength [set ws [info command $arg]]]} {
		    foreach w [lsort $ws] {
			if {[winfo exists $w]} {
			    if {[catch {$w configure} cfg]} {
				append res "\#\# Widget $w\
					does not support configure method"
				set code error
			    } else {
				append res "\#\# [winfo class $w]\
					$w\n$w configure"
				foreach c $cfg {
				    if {[llength $c] != 5} continue
				    ## Check to see that the option does
				    ## not match the default, then check
				    ## the item against the user filter
				    if {[string compare [lindex $c 3] \
					    [lindex $c 4]] && \
					    [regexp -nocase -- $fltr $c]} {
					append res " \\\n\t[list [lindex $c 0]\
						[lindex $c 4]]"
				    }
				}
				append res \n
			    }
			}
		    }
		} elseif {$whine} {
		    append res "\#\# No known widget $arg\n"
		    set code error
		}
	    }
	}
	a* {
	    ## see if we recognize it, other complain
	    if {[regexp {(var|com|proc|widget)} \
		    [set types [uplevel 1 what $args]]]} {
		foreach type $types {
		    if {[regexp {(var|com|proc|widget)} $type]} {
			append res "[uplevel 1 dump $type $args]\n"
		    }
		}
	    } else {
		set res "dump was unable to resolve type for \"$args\""
		set code error
	    }
	}
	default {
	    return -code error "bad [lindex [info level 0] 0] option\
		    \"$type\": must be variable, command, procedure,\
		    or widget"
	}
    }
    return -code $code [string trimright $res \n]
}

# highlight --
#    searches in text widget for $str and highlights it
#    If $str is empty, it just deletes any highlighting
#    This really belongs in ::Utility::tk
# Arguments:
#   w			text widget
#   str			string to search for
#   -nocase		specifies to be case insensitive
#   -regexp		specifies that $str is a pattern
#   -tag   tagId	name of tag in text widget
#   -color color	color of tag in text widget
# Results:
#   Returns ...
#
;proc highlight {w str args} {
    $w tag remove __highlight 1.0 end
    array set opts {
	-nocase	0
	-regexp	0
	-tag	__highlight
	-color	yellow
    }
    set args [get_opts opts $args {-nocase 0 -regexp 0 -tag 1 -color 1}]
    if {[string match {} $str]} return
    set pass {}
    if {$opts(-nocase)} { append pass "-nocase " }
    if {$opts(-regexp)} { append pass "-regexp " }
    $w tag configure $opts(-tag) -background $opts(-color)
    $w mark set $opts(-tag) 1.0
    while {[string compare {} [set ix [eval $w search $pass -count numc -- \
	    [list $str] $opts(-tag) end]]]} {
	$w tag add $opts(-tag) $ix ${ix}+${numc}c
	$w mark set $opts(-tag) ${ix}+1c
    }
    catch {$w see $opts(-tag).first}
    return [expr {[llength [$w tag ranges $opts(-tag)]]/2}]
}

# highlight_dialog --
#
#   creates minimal dialog interface to highlight
#
# Arguments:
#   w	text widget
#   str	optional seed string for HIGHLIGHT(string)
# Results:
#   Returns null.
#
proc highlight_dialog {w {str {}}} {
    variable HIGHLIGHT

    set namesp [namespace current]
    set var ${namesp}::HIGHLIGHT
    set base $w.__highlight
    if {![winfo exists $base]} {
	toplevel $base
	wm withdraw $base
	wm title $base "Find String"

	pack [frame $base.f] -fill x -expand 1
	label $base.f.l -text "Find:"
	entry $base.f.e -textvariable ${var}($w,string)
	pack [frame $base.opt] -fill x
	checkbutton $base.opt.c -text "Case Sensitive" \
		-variable ${var}($w,nocase)
	checkbutton $base.opt.r -text "Use Regexp" -variable ${var}($w,regexp)
	pack $base.f.l -side left
	pack $base.f.e $base.opt.c $base.opt.r -side left -fill both -expand 1
	pack [frame $base.sep -bd 2 -relief sunken -height 4] -fill x
	pack [frame $base.btn] -fill both
	button $base.btn.fnd -text "Find" -width 6
	button $base.btn.clr -text "Clear" -width 6
	button $base.btn.dis -text "Dismiss" -width 6
	eval pack [winfo children $base.btn] -padx 4 -pady 2 \
		-side left -fill both

	focus $base.f.e

	bind $base.f.e <Return> [list $base.btn.fnd invoke]
	bind $base.f.e <Escape> [list $base.btn.dis invoke]
    }
    ## FIX namespace
    $base.btn.fnd config -command [namespace code \
	    "highlight [list $w] \[set ${var}($w,string)\] \
	    \[expr {\[set ${var}($w,nocase)\]?{}:{-nocase}}] \
	    \[expr {\[set ${var}($w,regexp)\]?{-regexp}:{}}] \
	    -tag __highlight -color [list yellow]"]
    $base.btn.clr config -command \
	    "[list $w] tag remove __highlight 1.0 end;\
	    set [list ${var}($w,string)] {}"
    $base.btn.dis config -command \
	    "[list $w] tag remove __highlight 1.0 end;\
	    wm withdraw [list $base]"
    if {[string compare {} $str]} {
	set ${var}($w,string) $str
	$base.btn.fnd invoke
    }

    if {[string compare normal [wm state $base]]} {
	wm deiconify $base
    } else {
	raise $base
    }
    $base.f.e select range 0 end
}


####################################################################
####################################################################

## This automatically starts a console
##
catch {destroy .c}
pack [console .c] -fill both -expand 1
if {[info exists ::Name]} {
    wm title . "Console: $::Name"
    wm iconify .
    #wm geometry . +10+10
}
if {[info exists ::Widget::Console::class]
    && $::Widget::Console::class(WWW)} {
    . configure -width [getattr width] -height [getattr height]
}
