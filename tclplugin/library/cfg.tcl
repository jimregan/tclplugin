# cfg.tcl --
#
#	Parses standard configuration files and determines whether
#	a matching entry for a request exists in a configuration file.
#
#	Configuration files consist of text and comments. Comment lines
#	are introduced by '#' in the first column. Comments appear only
#	for the benefit of a human reader and are ignored by the parser.
#	Empty lines are ignored by the parsed. Any other line is a data
#	line and is used by the parser. 
#
#	Configuration files consist of sections, introduced by section
#	name lines, lines ending with a ":" character. The name of the
#	section is whatever appears before the ":", and the section lasts
#	until the next section name line or end of file.
#
#	Each section contains any number of lines starting with one of the
#	words "allow" or "disallow". The rest of the line consists of words
#	or lists of words enclosed in "{", "}" pairs. A word containing
#	spaces or other special characters must be enclosed in '"' marks.
#
#	A policy asks safe::allowed to determine if a request is allowed
#	according to the configuration information. A policy and section
#	name are supplied, as well as any number of additional arguments
#	needed to determine whether to allow or not. The decision is made
#	as follows:
#
#	1. if no section by that name exists in the configuration
#	   information for that policy, disallow.
#
#	2. if a matching "allow" and no matching "disallow" lines are found
#	   in the section, allow.
#
#	3. otherwise, disallow.
#
#	Line matches are determined as follows:
#
#	For each line in a section, the arguments supplied in the call to
#	::cfg::allowed are matched by position with items in the line
#	after the first word ("allow" or "disallow").
#
#	An item matches an argument if neither the item nor the argument
#	are the empty strings, and:
#
#	1. if the item is equal to the argument,
#	2. if the item is a string pattern and it matches the argument
#	   using "string match",
#	3. if the item is a range of the form n1-n2 and the range contains
#	   the numeric value of the argument,
#	4. if the item is a range of the form >n and the range contains the
#	   numeric value of the argument,
#	5. if the item is a range of the form <n and the range contains the
#	   numeric value of the argument,
#	6. or if the item is a list and at least one element in the list
#	   matches the argument according to 1-5 above.
#
#      NEEDS UPDATE ABOUT EXPR EVAL AT THE END OF ARGS LIST (ifallowed)...
#
#
# CONTACT:		sunscript-plugin@sunscript.sun.com
#
# AUTHORS:		Jacob Levy			Laurent Demailly
#			jyl@eng.sun.com			demailly@eng.sun.com
#			jyl@tcl-tk.com			L@demailly.com
#
# Please contact us directly for questions, comments and enhancements.
#
# Copyright (c) 1995-1997 Sun Microsystems, Inc.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# SCCS: @(#) cfg.tcl 1.31 97/12/02 19:23:34

# This file provides the "cfg" package:

package provide cfg 1.0

# We use the 'fancy' logging:

package require log 1.0

namespace eval ::cfg {
    namespace export init allowed getConstant clear

    # We use the fancy logger:

    namespace import ::log::log

### DEBUG
#   set ::log::strTruncLen 500

    # In which directory will we find configuration files? We set it to
    # a reasonable default: the "config" directory sister of $tcl_library

    variable configDir [file join [file dirname $tcl_library] "config"]

    # Are we Sourcing a file already ?
    variable _InSource 0

    # What section are we in now?

    variable _CurrentSection

    # What configuration are we parsing?

    variable _CurrentSrcConfig

    # For which token are we checking now? We need to do this because
    # when we source a configuration file, subst invoked from allow and
    # disallow might need to refer to the token.

    variable _CurrentToken


    # Initialize the cfg mechanism

    proc init {baseName {masterConfigFile ""} {aConfigDir ""}} {
	variable configDir
	variable name

	set name $baseName

	if {[string compare $aConfigDir ""] != 0} {
	    # arg given:
	    log $name "setting config dir to $aConfigDir"
	    set configDir $aConfigDir
	}

	if {[string compare $masterConfigFile ""] ==0 } {
	    # arg not given:
	    set masterConfigFile [file join $configDir $name.cfg]
	    if {[file exists $masterConfigFile]} {
		log $name "will use $name.cfg in $configDir\
			as the master config"
	    } else {
		# As a fall back, try to find the config file
		# where the executable was
		set dir [file dirname [info nameofexecutable]]
		set masterConfigFile [file join $dir $name.cfg]
		if {[file exists $masterConfigFile]} {
		    log $name "wil use $name in $dir as the master config"
		} else {
		    return -code error "could not find $name.cfg (in "
		}
	    }
	} else {
	    set masterConfigFile [file join $configDir $masterConfigFile]
	}
	
	# Make sure we really source it

	clear $name

	#       3 args            :  logName configName fileName

	EventuallySourceConfigFile   $name   $name      $masterConfigFile
    }

    # Remove a config data from memory (ensuring reloading)

    proc clear {config} {
	set arrayName [ConfigArrayName $config]
	variable $arrayName
	if {[info exists $arrayName]} {
	    unset $arrayName
	    log {} "cleared config \"$config\""
	} else {
	    log {} "nothing to clear for config \"$config\""
	}
    }

    #
    # Functions callable from regular Tcl (like safetcl features set checks)
    # (cfg:: APIs)

    # This procedure determines whether a request has a match in the
    # given section in the configuration file for that policy. A match
    # is found if a matching "allow" entry is found in the section and
    # no matching "disallow" entries are found.

    proc allowed {logToken config section args} {
	# Save state because of possible recursion
	set state [SaveState]

	variable _CurrentToken $logToken
	variable _CurrentChkConfig $config

	# Check if we must first read the configuration file (one time init).

	EventuallySourceConfigFile $logToken $config

	# If the requested section does not exist, we decide that this is
	# not allowed.
	set allowSectionVarName [VarName $config $section allow]

	if {![info exists $allowSectionVarName]} {
	    log $logToken "no match: \"$section\", \"$args\" in $config"
	    RestoreState $state
	    return 0
	}

	# Search the requested section for a matching allow:

	set match 0
	foreach allow [set $allowSectionVarName] {
	    if {[MatchItems $logToken $allow $args]} {
		set match 1
		break
	    }
	}

	# No match found so we disallow:

	if {!$match} {
	    RestoreState $state
	    return 0
	}
	
	# If there are no disallows in this section, we found a match,
	# so allow this request:

	set disallowSectionVarName [VarName $config $section disallow]
	if {![info exists $disallowSectionVarName]} {
	    RestoreState $state
	    return 1
	}

	# Search the requested section for a matching disallow:

	foreach disallow [set $disallowSectionVarName] {
	    if {[MatchItems $logToken $disallow $args]} {
		RestoreState $state
		return 0
	    }
	}

	# Did not find a matching disallow so we allow:
	RestoreState $state
	return 1
    }

    # This procedure gets the value of a resource in a given section:

    proc getConstant {logToken config section name} {
	variable _CurrentToken $logToken
	variable _CurrentChkConfig $config

	# Check if we must first read the configuration file (one time init).

	EventuallySourceConfigFile $logToken $config

	# If the constant in the section does not exist, return empty handed:

	set constantVarName [VarName $config $section constant${name}]

	if {![info exists $constantVarName]} {
	    log $logToken "constant \"$name\" not found in $section, $config"
	    error "no such constant: $name"
	}

	return [set $constantVarName]
    }


    #
    # Functions available when sourcing
    #

    # Set the current section.

    proc section {args} {
	variable _CurrentSection $args
	variable _CurrentSectionNumArgs [llength $args]
    }

    # Remembers an allow line from the config file.

    proc allow {args} {
	Store "allow" 1 0 $args
    }

    # Remembers a disallow line

    proc disallow {args} {
	Store "disallow" 1 0 $args
    }

    # Records a constant (token) definition.

    proc constant {name value} {
	Store "constant$name" 0 1 $value
	# also make it available as a local variable
	uplevel [list set $name $value]
    }

    # Overloading variable so it does not error when smashing a local copy

    proc variable {name args} {
	if {[llength [uplevel [list info locals $name]]]} {
	    uplevel [list unset $name]
	}
	uplevel ::variable [list $name] $args
    }

    # Include directive : a source in the current config dir (!= pwd)

    proc include {filename} {
	variable _CurrentSrcDir
	variable _CurrentToken
	set fname [file join $_CurrentSrcDir $filename]
	log $_CurrentToken "including \"$fname\" ($filename)"
	uplevel [list source [file join $_CurrentSrcDir $fname]]
    }

    #
    # Functions available when substituting/evaling
    # (runtime "allowed" checks)
    #

    # Get attributes of the current slave:

    proc getattr {attr} {
	variable _CurrentToken

	# NOTE: it is the responsability of the "user" of this package
	#       to provide an "iget" that finds the requested attribute
	#	of the supplied token.

	iget $_CurrentToken $attr
    }


    # Helper function equivalent to expr to make the rules matching
    # more 'english'

    proc when {expression} {
	variable _CurrentToken
#	log $_CurrentToken "Doing when \"$expression\""
	# (it's not just "expr" because we need to canonalize booleans
	#  and others so it works in if {![when ...]}...)
	# *and* because we evaluate in the caller (namespace) frame
	if {[expr $expression]} {
	    return 1
	} else {
	    return 0
	}
    }

    # Helper function to negate an expression (makes rules more 'english')
    
    proc unless {expression} {
	variable _CurrentToken
#	log $_CurrentToken "Doing unless \"$expression\""
	if {[expr $expression]} {
	    return 0
	} else {
	    return 1
	}
    }

    # ifallowed determines whether a request has a match in the
    # current configuration and a given section. used only from inside
    # a config (.cfg) file to conditionalize a match in "allow" or "disallow".
    
    proc ifallowed {section args} {
	variable _CurrentToken
	variable _CurrentChkConfig

	# See if the section is relative to the current one
	# or absolute
	if {![regexp {^(.*)/(.*)$} $section all config section]} {
	    set config $_CurrentChkConfig
	}
	log {} "ifallowed: config=\"$config\" section=\"$section\"" DEBUG
	# We need to subst our last args because they haven't been
	# subst'ed yet
	eval allowed [list $_CurrentToken $config $section]\
		[subst $args]
    }


    ###### End of public and special APIs #######

    # Returns the name of the namespace array variable holding the
    # current config

    proc ConfigArrayName {config} {
	return _config.$config
    }

    proc VarName {config section what} {
	set arrayName [ConfigArrayName $config]
	uplevel [list variable $arrayName]
	return ${arrayName}($section.$what)
    }


    # This procedure sources the configuration file for a policy:

    proc EventuallySourceConfigFile {logToken config {configFile ""}} {
	variable configDir

	set ConfigArrayName [ConfigArrayName $config]
	variable $ConfigArrayName
	
	if {![info exists $ConfigArrayName]} {
	    variable _InSource
	    variable _CurrentSrcConfig

	    if {$_InSource} {
		set state [SaveState]
		log {} "saved cfg state before source recursion\
			$_InSource ($_CurrentSrcConfig)"
	    }
	    incr _InSource 1

	    set _CurrentSrcConfig $config

	    if {[string compare $configFile ""] == 0} {
		set configFile [file join $configDir $config.cfg]
	    }

	    log $logToken "sourcing \"$configFile\" for config \"$config\""

	    # remember the current SrcDir (for include)
	    variable _CurrentSrcDir [file dirname $configFile]

	    # Remember the filename (and then we also always have something
	    # to unset in case of sourcing error below)

	    set ${ConfigArrayName}(filename) $configFile;

	    # The caller must be prepared to deal with errors in sourcing
	    # the config file.

	    # We source things in the current context so 'local' variables
	    # used in the .cfg scripts are cleaned away at the end and
	    # only explicitly declared "variable"s are saved

	    set res [catch {DoSource $configFile} msg]
	    if {$res} {
		log $logToken "sourcing \"$configFile\": $msg" ERROR
		# Cleanup potentially partially initialized state
		unset $ConfigArrayName
	    }
	    incr _InSource -1
	    if {$_InSource} {
		RestoreState $state
		log {} "restored cfg state after source recursion\
			$_InSource ($_CurrentSrcConfig)"
	    }
	    return -code $res $msg
	}
    }

    # Save/restore the state (Current*)

    proc SaveState {} {
	log {} "saving cfg state   [info level] [info level -1]" DEBUG
	set savedState {}
	foreach v [info vars [namespace current]::_Current*] {
	    if {[info exists $v]} {
		lappend savedState $v [set $v]
	    }
	}
	return $savedState
    }

    proc RestoreState {state} {
	foreach {v value} $state {
	    set $v $value
	}
	log {} "restored cfg state [info level] [info level -1]" DEBUG

    }


    # Source the config file and makes source time context available

    proc DoSource {configFile} {
	# Make a copy of all namespace variables accessible in this frame
	foreach var [info vars [namespace current]::*] {
	    set localname [namespace tail $var]
	    # make a local copy if the name is not private (_..)
	    if {![string match {_*} $localname]} {
		set $localname [set $var]
	    }
	}
	# If the configFile want to *change* or *create* a new variable
	# it has to use "variable foo", otherwise any config can access
	# any previously defined var but changes will just be discarded
	# when we exit current scope.
	::source $configFile
    }


    # Helper procedure: match each item.

    proc MatchItems {logToken items arguments} {
	set il [llength $items]
	set al [llength $arguments]
	if {$al > $il} {
	    log $logToken  "can't match \"$items\"\
		    with \"$arguments\": args # mismatch"
	    return 0
	} elseif {$il > $al} {
	    set moreItems [lrange $items $al end]
#	    log $logToken "extra arguments ($moreItems):\
#		    will conditionally eval if begining match"
	    set items [lrange $items 0 [expr {$al-1}]]
	} else {
	    set moreItems {}
	}
	foreach i $items a $arguments {
	    if {![MatchItem $logToken $i $a]} {
		log $logToken "didn't match $i with $a" DEBUG
		return 0
	    }
	}
	log $logToken "matched \"$items\" against \"$arguments\""
	if {[llength $moreItems]} {
	    # Tricky stuff :

	    # remove one level of bracing
	    # (moreItems is a list, so we need concat)
	    set script [concat $moreItems]
	    
	    log $logToken "matched so far, extra args to eval: \"$script\""
	    # We don't eval in the namespace context because the variable
	    # have only the indirect value there (and are thus pretty
	    # useless
	    if {[catch {eval $script} res]} {
		log $logToken "error processing extra args ($script): $res"\
			ERROR
		log $logToken "errorInfo=($::errorInfo)" ERROR
		return 0
	    }
	    # We might want to check that res is a boolean/number...
	    log $logToken "match res=$res"
	    return $res
	} else {
	    return 1
	}
    }

    # Helper procedure: match an individual item according to the rules
    # described above.

    proc MatchItem {logToken rawItem arg} {
	# Substitute rawItem to get the Tcl evaluation of embedded expressions
	# to happen now:

	# subst might fail when we treat an argument as a list for instance
	# when it was really a two word command (like {[getattr foo]})
	# in this case we will use the raw item instead.

	if {[catch {namespace eval [namespace current]\
		[list subst $rawItem]} item]} {
	    log $logToken "error (probably ok) in subst \"$rawItem\" : $item"
	    set item $rawItem
	}
	
	# "rawItem" comes from the config file, and can be a list.
	# "item" is the substituted value of "rawItem".
	# "arg" is what has been requested by the slave.

	# Match rule #1:

	if {[string compare $item $arg] == 0} {
	    return 1
	}

	# Match rule #2:
	
	if {[string match $item $arg]} {
	    return 1
	}

	set isInt [regexp {^[\-]*[0-9]+$} $arg]

	if {$isInt} {
	    
	    # Match rule #3:

	    if {[regexp {^([\-]*[0-9]+)-([\-]*[0-9]+)$} $item dummy n1 n2]} {
		return [expr {($n1 <= $arg) && ($arg <= $n2)}]
	    }

	    # Match rule #4:

	    if {[regexp {^>([\-]*[0-9]+)$} $item dummy n1]} {
		return [expr {$n1 < $arg}]
	    }

	    # Match rule #5:

	    if {[regexp {^<([\-]*[0-9]+)$} $item dummy n1]} {
		return [expr {$n1 > $arg}]
	    }
	}

	# Match rule #6 if the item is a list:

	# NB: todo : we should not recurse if the inner is a full []
	#     (but we have to if its {{[x foo]} {[y bar]}} for instance)

	# We disable recursion into list for security reasons for now on.

#	if {[llength $rawItem] < 2} {
#	    return 0
#	}

#	foreach listItem $rawItem {
#	    if {[MatchItem $logToken $listItem $arg]} {
#		return 1
#	    }
#	}

	# No match found, sorry:

	return 0
    }


    #
    # Store data in the scope of the current section
    #

    proc Store {name checkLen overWrite value} {

	# We need access to the global array named by the current config
	# array name -- this is because we are doing double indirection.

	variable _CurrentSrcConfig
	variable _CurrentSection
	
	if {$checkLen} {
	    variable _CurrentSectionNumArgs

	    set len [llength $value]

	    if {$len < $_CurrentSectionNumArgs} {
		error "syntax error, not enough arguments in\
			\"$name $value\" for section \"$_CurrentSection\""
	    }
	}
	set vname [VarName $_CurrentSrcConfig $_CurrentSection $name]
	if {$overWrite} {
	    set $vname $value
	} else {
	    lappend $vname $value
	}
    }



}
