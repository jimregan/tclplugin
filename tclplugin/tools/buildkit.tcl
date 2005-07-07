#!/bin/sh
# The next line is executed by /bin/sh, but not tcl \
exec tclsh "$0" ${1+"$@"}


# Copyright (c) 2005 ActiveState Corporation.
#
# This will build us a tkkit if we have TDK.

# The script is actually x-platform, but unless we had access to
# all the installed bits from a single platform, it's easier to
# run this on each platform.

# require minimum version we want to use
set ver [package require ActiveTcl 8.4.9]
package require vfs

set noedir  [file dirname [info nameofexecutable]]
set libdir  [file dirname $tcl_library]
set toollib [file dirname [info script]]
set pluglib [file dirname [info script]]/../library
set ext    [info sharedlibext]

proc usage {{fid stderr}} {
    puts $fid "$::argv0 ?options?"
    puts $fid "\t-modules list   add the listed Tcl modules"
    puts $fid "\t-excludes list  glob pattern of file to exclude in modules"
    puts $fid "\t-mini bool      install minimal components (default: fat)"
    puts $fid "\t-wish prog      default external wish to use"
    puts $fid "\t-xpi  file      create xpi named <file>"
    puts $fid "\t-help           print out this message"
    exit [string equal stderr $fid]
}

set prefix  "tclplugin"
set basekit ""
set mini    0 ; # use minimal components
set dir     [pwd]
set modules  ""
set excludes ""
set xpi      ""
set wrap     ""
set zip      ""
set wish     [auto_execok wish]
foreach {key val} $argv {
    switch -glob -- $key {
	"-min*" {
	    set mini [string is true -strict $val]
	}
	"-module*" {
	    eval [list lappend modules] $val
	}
	"-exc*" {
	    eval [list lappend excludes] $val
	}
	"-wi*" {
	    set wish $val
	}
	"-wrap*" {
	    lappend wrap $val
	}
	"-xpi*" {
	    set xpi $val
	}
	"-zip" {
	    set zip $val
	}
	"\?" - "help" - "-help" - "usage" {
	    usage stdout
	}
	default {
	    puts stderr "unknown option '$key'"
	    usage stderr
	}
    }
}

puts "Build with ActiveTcl $ver"

if {$basekit eq ""} {
    set basekit $dir/$prefix$::ext
    set srckit [glob -nocomplain -directory $noedir base-tcl-*[info shared]]
    if {![file exists $srckit]} {
	puts stderr "Couldn't find base dll kit:\
		ActiveTcl 8.4.9+ is required for operation"
	exit 1
    }
    puts "Using $srckit as source for $basekit"
    if {[file exists $basekit]} {
	puts "$basekit exists - deleting"
	file delete -force $basekit
    }
    file copy $srckit $basekit
} else {
    if {![file exists $basekit]} {
	puts stderr "Couldn't find '$basekit'"
	exit 1
    }
    puts "Updating $basekit - non-binary components only"
}

puts "Mounting - [file tail $basekit]: [file size $basekit] bytes"
vfs::mk4::Mount $basekit $basekit

#
# Binary components
#

puts "Copying in Tk ..."
if {$tcl_platform(platform) eq "windows"} {
    file copy $noedir/tk84$::ext $basekit/bin/
} else {
    file copy $libdir/libtk8.4$::ext $basekit/lib/
}
file copy $libdir/tk8.4 $basekit/lib
file delete -force $basekit/lib/tk8.4/demos
file delete -force $basekit/lib/tk8.4/tkAppInit.c

#
# Script-only components
#
proc nptcl {} {
    puts "Copying in nptcl runtime ..."
    set nptcldir $::basekit/lib/nptcl
    catch {file delete -force [glob $nptcldir*]}
    foreach dir [list . config safetcl utils] {
	set target [file join $nptcldir $dir]
	file mkdir $target
	set files [glob -type f [file join $::pluglib $dir *.*]]
	eval [list file copy] $files [list $target]
    }

    puts "Modifying installed.cfg"
    puts "   External wish: $::wish"
    set fid [open $nptcldir/installed.cfg a]
    seek $fid 0 end
    puts $fid ""
    puts $fid [list set ::plugin(executable) $::wish]
    close $fid
}
nptcl

proc add_modules {modules} {
    foreach mod $modules {
	puts "Copying in $mod ..."
	set real [glob $::libdir/$mod*]
	if {[llength $real] != 1} {
	    puts stderr "Did not find exactly one version of '$mod':\n\t$real"
	    exit 1
	}
	catch {file delete -force [glob $::basekit/lib/$mod*]}
	file copy $real $::basekit/lib
    }
}
add_modules $modules

proc exclude_files {excludes} {
    foreach exc $excludes {
	catch {eval [list file delete -force] [glob $::basekit/lib/$exc]}
    }
}
exclude_files $excludes

::vfs::unmount $basekit
puts "Done - $basekit: [file size $basekit] bytes"

proc xpi {xpi} {
    if {$xpi ne ""} {

	puts "Creating xpi '$xpi'"
	file delete -force $xpi

	if {$::zip eq ""} {
	    set ::zip [auto_execok zip]
	}
	if {$::zip eq ""} {
	    puts stderr "Unable to find zip executable - cannot create xpi"
	    exit
	}

	puts "    Zip'ing $::basekit $::wrap"
	# -j - store just by names, no dir prefixes
	eval [list exec $::zip -9 -j $xpi $::basekit] $::wrap
    }
}
xpi $xpi
