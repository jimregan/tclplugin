# url.tcl --
#
#      Routines for URL parsing, joining and canonalizing.
#
# ORIGINAL AUTHORS:      Jacob Levy              Laurent Demailly
#
#       Initially based on earlier work by Brent Welch bwelch@eng.sun.com
#       Current implementation based on earlier work by Laurent Demailly.
#
# Copyright (c) 1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
#
# SCCS: @(#) url.tcl 1.21 97/12/02 19:26:34
# RCS:  @(#) $Id$

# We provide URL parsing functionality:

package provide url 1.1

namespace eval ::url {
    namespace export parse format join canonic

    # Valid protocols and their default ports
    variable tabProtos

    array set tabProtos {
	http		80
	https		443
	ftp		21
	mailto		25
	javascript	{}
	file		21
    }

    # This procedure parses a URL into its components:

    proc parse {url} {
	variable tabProtos

	if {[regexp {\s} $url]} {
	    return -code error "invalid url: contains whitespaces"
	}

	# 'local' file urls (ie w/o host (non ftp)) are unfortunately specials:
	# (don't touch unless you know what you're doing
	#  AND it still passes the all the tests after your changes)
	if {[regexp -nocase {^file:/(//+)?([^/][^#]*)?(#.*)?$} \
		$url all slashes what key]} {
	    regsub ^/+ $what / what
	    set proto file
	    set port {}
	    set host {}
	} else {
	    # The big regexp from space - don't touch it unles you really
	    # known what you're doing AND it still passes the all the 
	    # tests after your changes.
	    if {![regexp\
		    {^([^:/]+):(//([^/:]+)(:([^/]*))?/?)?([^/#][^#]*)?(#.*)?$}\
		    $url all proto h host p port what key]} {
		return -code error "invalid url \"$url\": badly formed"
	    }
	    set host [string tolower $host]
	    set proto [string tolower $proto]
	    if {![info exists tabProtos($proto)]} {
		return -code error \
		    "invalid url \"$url\": unknown protocol $proto"
	    }
	    if {$port eq ""} {
		set port $tabProtos($proto)
	    } elseif {[catch {set port [expr {int($port)}]}]} {
		if {[file exists $host:$port]} {
		    ## OK, IE gives us a different file: type URL
		    ## Handle that here
		    set what $host:$port
		    regsub ^/+ $what / what
		    ## Get it into the way that Tcl likes to see it
		    eval file join [file split $what]
		    set proto file
		    set port {}
		    set host {}
		} else {
		    return -code error \
			"invalid url \"$url\": non numeric port $port"
		}
	    }
	}
	list $proto $host $port $what $key
    }

    # The inverse of "parse": build a URL from components:

    proc format {proto host port path key} {
	if {$host eq ""} {
	    if {$proto eq "file"} {
		return "$proto:/$path$key"
	    } else {
		return "$proto:$path$key"
	    }
	} else {
	    if {$port eq ""} {
		return "$proto://$host/$path$key"
	    } else {
		return "$proto://$host:$port/$path$key"
	    }
	}
    }

    # Canonicalize

    proc canonic {url} {
	eval format [parse $url]
    }

    # Join an absolute and a relative URL to form a new absolute URL:

    proc join {url1 url2} {
	# if the second url parses, it's absolute:
	if {![catch {parse $url2} res]} {
	    return [eval format $res]
	} else {
	    # Parse the first one (if it fails, nothing can be done).
	    foreach {proto host port path key} [parse $url1] break

	    # test the special case where we join with "#key"
	    if {[string match "#*" $url2]} {
		return [format $proto $host $port $path $url2]
	    }

	    # Drop one level
	    set pathL [lrange [split $path /] 0 end-1]

	    # if url2 is empty we have to return origin path less one level
	    # with trailing /
	    if {$url2 eq ""} {
		if {[llength $pathL] == 0} {
		    return [format $proto $host $port {} {}]
		} else {
		    return [format $proto $host $port "[::join $pathL /]/" {}]
		}
	    }

	    # trailing ".." implies directory at the end (ie xxx/..
	    # really means xxx/../ for the processing below)
	    if {[string match "*.." $url2]} {
		set trailingS 1
	    } else {
		# Remove and remember single trailing /
		# (trailing / is not like middle or begining / : 
		#  xxx//yyy where it would imply /yyy)
		set trailingS [regsub {([^/])/$} $url2 {\1} url2]
	    }

	    foreach newP [split $url2 /] {
		if {$newP eq ""} {
		    # Leading / or two consecutive // -- start from top.
		    set pathL {}
		} elseif {$newP eq "."} {
		    # "./" -- Means nothing, skip.
		    continue
		} elseif {$newP eq ".."} {
		    # ".." -- Go up one dir.
		    set pathL [lrange $pathL 0 [expr {[llength $pathL]-2}]]
		} else {
		    # Regular item -- add to URL being built.
		    lappend pathL $newP
		}
	    }

	    # Putback trailing /
	    if {$trailingS} {
		lappend pathL {}
	    }

	    # Be carefull not to call ourselves
	    set path [::join $pathL /]
	    # Be over cautious and make sure what we get can be parsed:
	    return [canonic [format $proto $host $port $path {}]]
	}
    }
}
