# url.tcl --
#
#      Routines for URL parsing, joining and canonalizing.
#
# CONTACT:      sunscript-plugin@sunscript.sun.com
#
# AUTHORS:      Jacob Levy              Laurent Demailly
#               jyl@eng.sun.com         demailly@eng.sun.com
#               jyl@tcl-tk.com          L@demailly.com
#
#       Initially based on earlier work by Brent Welch bwelch@eng.sun.com
#       Current implementation based on earlier work by Laurent Demailly.
#
# Please contact us directly for questions, comments and enhancements.
#
# Copyright (c) 1997 Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
#
# SCCS: @(#) url.tcl 1.21 97/12/02 19:26:34
# RCS:  @(#) $Id$

# We provide URL parsing functionality:

package provide url 1.1

# We use Lassign, so we need the opt package:

package require opt 0.1 

namespace eval ::url {
    namespace export parse format join canonic

    # Valid protocols and their default ports
    variable tabProtos

    array set tabProtos {
	http 80
	https 443
	ftp  21
	mailto 25
	javascript {}
	file 21
    }

    # This procedure parses a URL into its components:

    proc parse {url} {
	variable tabProtos

	if {[regexp " \n\t\r" $url]} {
	    error "invalid url: contains whitespaces"
	}

	# 'local' file urls (ie w/o host (non ftp)) are unfortunately specials:
	# (don't touch unless you know what you're doing
	#  AND it still passes the all the tests after your changes)
	if {[regexp -nocase {^file:/(//+)?([^/][^#]*)?(#.*)?$}\
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
		error "invalid url \"$url\": badly formed"
	    }
	    set host [string tolower $host]
	    set proto [string tolower $proto]
	    if {![info exists tabProtos($proto)]} {
		error "invalid url \"$url\": unknown protocol $proto"
	    }
	    if {[string compare $port ""] == 0} {
		set port $tabProtos($proto)
	    } else {
		if {[catch {set port [expr {int($port)}]}]} {
		    error "invalid url \"$url\": non numeric port $port"
		}
	    }
	}
	list $proto $host $port $what $key
    }

    # The inverse of "parse": build a URL from components:

    proc format {proto host port path key} {
	if {[string compare $host ""] == 0} {
	    if {[string compare $proto file] == 0} {
		return "$proto:/$path$key"
	    } else {
		return "$proto:$path$key"
	    }
	} else {
	    if {[string compare $port ""] == 0} {
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
	    ::tcl::Lassign [parse $url1] proto host port path key

	    # test the special case where we join with "#key"
	    if {[regexp {^#.*$} $url2]} {
		return [format $proto $host $port $path $url2]
	    }

	    # Initial path:
	    set pathL [split $path /]

	    # Drop one level
	    set pathL [lrange $pathL 0 [expr {[llength $pathL]-2}]]

	    # if url2 is empty we have to return origin path less one level
	    # with trailing /
	    if {[string compare "" $url2] == 0} {
		if {[llength $pathL] == 0} {
		    return [format $proto $host $port {} {}];
		} else {
		    return [format $proto $host $port "[::join $pathL /]/" {}]
		}
	    }

	    # trailing ".." implies directory at the end (ie xxx/..
	    # really means xxx/../ for the processing below)
	    if {[regexp {\.\.$} $url2]} {
		set trailingS 1;
	    } else {
		# Remove and remember single trailing /
		# (trailing / is not like middle or begining / : 
		#  xxx//yyy where it would imply /yyy)
		set trailingS [regsub {([^/])/$} $url2 {\1} url2];
	    }

	    foreach newP [split $url2 /] {
		if {[string compare $newP ""]==0} {
		    # Leading / or two consecutive // -- start from top.
		    set pathL {}
		    continue
		} elseif {[string compare $newP "."]==0} {
		    # "./" -- Means nothing, skip.
		    continue
		} elseif {[string compare $newP ".."]==0} {
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
