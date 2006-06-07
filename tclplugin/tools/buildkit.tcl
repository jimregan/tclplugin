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
set windir  [file dirname [info script]]/../win
set toollib [file dirname [info script]]
set pluglib [file dirname [info script]]/../library
set ext     [info sharedlibext]

proc usage {{fid stderr}} {
    puts $fid "$::argv0 ?options?"
    puts $fid "\t-basedll dllkit basekit dll to base plugkit dll on"
    puts $fid "\t-baseexe kit    basekit exe to add into plugin (required on unix)"
    puts $fid "\t-modules list   add the listed Tcl modules"
    puts $fid "\t-excludes list  glob pattern of file to exclude in modules"
    puts $fid "\t-mini bool      install minimal components (default: fat)"
    puts $fid "\t-wish prog      default external wish to use"
    puts $fid "\t-xpi  file      create xpi named <file>"
    puts $fid "\t-help           print out this message"
    exit [string equal stderr $fid]
}

set prefix  "tclplugin"
set srcdll  ""
set npdll   ""
set baseexe "" ; # only required on unix
set mini    0 ; # use minimal components
set dir     [pwd]
set modules  ""
set excludes ""
set xpi      ""
set wrap     ""
set zip      ""
set version  "3.0"
set wish     [auto_execok wish]
set install_js $toollib/install.js.in

foreach {key val} $argv {
    switch -glob -- $key {
	"-based*" {
	    set srcdll $val
	}
	"-basee*" {
	    set baseexe $val
	}
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
	"-npdll" {
	    set npdll $val
	}
	"-xpi*" {
	    set xpi $val
	}
	"-version" {
	    set version $val
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

if {$srcdll eq ""} {
    set srcdll [glob -nocomplain -directory $noedir base-tcl*[info shared]]
    if {[llength $srcdll] != 1} {
	puts stderr "Found multiple basedlls:\n\t[join $srcdll \n\t]"
	puts stderr "Choose one with -basedll option"
	exit 1
    }
    if {![file exists $srcdll]} {
	puts stderr "Couldn't find base dll kit:\
		ActiveTcl 8.4.9+ is required for operation"
	exit 1
    }
} else {
    if {![file exists $srcdll]} {
	puts stderr "Couldn't find '$srcdll'"
	exit 1
    }
}

set basekit ""
if {$::tcl_platform(platform) eq "unix" && ![file exists $baseexe]} {
    set baseexe [glob -nocomplain -directory $noedir base-tk*]
    if {[llength $baseexe] != 1} {
	puts stderr "Found multiple baseexes:\n\t[join $baseexe \n\t]"
	puts stderr "Choose one with -baseexe option"
	exit 1
    }
}
if {[file exists $baseexe]} {
    set basekit $dir/[file tail $baseexe]
    puts "Basekit source:  $baseexe\nBasekit target: $basekit"
    if {[file exists $basekit]} {
	puts "\t$basekit exists - deleting"
	file delete -force $basekit
    }
    file copy $baseexe $basekit
    puts "Mounting - [file tail $basekit]: [file size $basekit] bytes"
    vfs::mk4::Mount $basekit $basekit
} elseif {$::tcl_platform(platform) eq "unix"} {
    puts stderr "The basekit exe is required on unix."
    puts stderr "Specify with -baseexe <exekit>."
    exit 1
}

set basedll $dir/$prefix$::ext
puts "Basedll source:  $srcdll\nBasedll target: $basedll"
if {[file exists $basedll]} {
    puts "\t$basedll exists - deleting"
    file delete -force $basedll
}
file copy $srcdll $basedll

puts "Mounting - [file tail $basedll]: [file size $basedll] bytes"
vfs::mk4::Mount $basedll $basedll

#
# Add in components
#

proc add_tk {kit} {
    puts "Copying in Tk $::tcl_version to [file tail $kit] ..."
    if {[file exists $kit/lib/tk$::tcl_version]} {
	puts "\tTk found already in the kit"
    } else {
	if {$::tcl_platform(platform) eq "windows"} {
	    file copy $::noedir/tk[string map {. {}} $::tcl_version]$::ext \
		$kit/bin/
	} else {
	    file copy $::libdir/libtk$::tcl_version$::ext $kit/lib/
	}
	file copy $::libdir/tk$::tcl_version $kit/lib
    }
    file delete -force $kit/lib/tk$::tcl_version/demos
    file delete -force $kit/lib/tk$::tcl_version/tkAppInit.c
}

proc nptcl_indll {kit} {
    # nptcl doesn't belong in the dll anymore because we need it on
    # disk to allow for runtime modification of the configuration and
    # sharing with any external binaries that may be used
    return
    puts "Copying in nptcl runtime to [file tail $kit] ..."
    set nptcldir $kit/lib/nptcl
    catch {file delete -force [glob $nptcldir*]}
    foreach sdir [list . config safetcl utils] {
	set target [file join $nptcldir $sdir]
	file mkdir $target
	set files [glob -type f [file join $::pluglib $sdir *.*]]
	eval [list file copy] $files [list $target]
    }

    puts "Modifying installed.cfg"
    set fid [open $nptcldir/installed.cfg a]
    seek $fid 0 end
    puts $fid ""
    set wish $::wish
    if {[file exists $::basekit]} {
	# Need to modify to allow for self-referencing exe
	set wish "\$::plugin(library)/../../../[file tail $::basekit]"
	puts $fid "set ::plugin(executable) \[file normalize \"$wish\"\]"
    } else {
	puts $fid [list set ::plugin(executable) $wish]
    }
    puts "   External wish: $wish"
    close $fid
}

proc nptcl_inxpi {} {
    # nptcl doesn't belong in the dll anymore because we need it on
    # disk to allow for runtime modification of the configuration and
    # sharing with any external binaries that may be used
    puts "Creating nptcl runtime dir for xpi ($::dir/nptcl) ..."
    set nptcldir $::dir/nptcl
    catch {file delete -force $nptcldir}
    foreach sdir [list . config safetcl utils] {
	set target [file join $nptcldir plugin$::version $sdir]
	file mkdir $target
	set files [glob -type f [file join $::pluglib $sdir *.*]]
	eval [list file copy] $files [list $target]
    }

    puts "Modifying installed.cfg"
    set fid [open $nptcldir/plugin$::version/installed.cfg a]
    seek $fid 0 end
    puts $fid ""
    set wish $::wish
    if {[file exists $::basekit]} {
	# Need to modify to allow for self-referencing exe
	set wish "\$::plugin(library)/../[file tail $::basekit]"
	puts $fid "set ::plugin(executable) \[file normalize \"$wish\"\]"
    } else {
	puts $fid [list set ::plugin(executable) $wish]
    }
    puts "   External wish: $wish"
    close $fid
}

proc add_modules {kit modules} {
    foreach mod $modules {
	puts "Copying in $mod to [file tail $kit] ..."
	set dirs [concat [list $::libdir] $::auto_path]
	foreach sdir $dirs {
	    set real [glob -nocomplain $sdir/$mod*]
	    if {[llength $real]} { break }
	}
	if {[llength $real] != 1} {
	    puts stderr "\nDid not find exactly one version of '$mod':\n\t$real"
	    exit 1
	}
	puts "\t([file tail $real])"
	# We copy things into the tcl8.x dir to allow them to be recognized
	# as safe packages
	set kitdir $kit/lib/tcl$::tcl_version
	catch {file delete -force [glob $kitdir/$mod*]}
	file copy $real $kitdir
    }
}

proc exclude_files {kit excludes} {
    foreach exc $excludes {
	catch {eval [list file delete -force] [glob $kit/lib/$exc]}
    }
}

# If we have a basekit, add all the extra stuff to it, as it will be
# used for tclets.  However, both the dll and the basekit would need
# the nptcl plugin packages and Tk.
add_tk $basedll
nptcl_indll $basedll
if {[file exists $basekit]} {
    add_tk $basekit
    nptcl_indll $basekit
    add_modules $basekit $modules
    exclude_files $basekit $excludes
} else {
    add_modules $basedll $modules
    exclude_files $basedll $excludes
}

::vfs::unmount $basedll
puts "Done - $basedll: [file size $basedll] bytes"
if {[file exists $basekit]} {
    ::vfs::unmount $basekit
    puts "Done - $basekit: [file size $basekit] bytes"
}

proc dirsize {dir size} {
    foreach fd [glob -directory $dir *] {
	if {[file isdirectory $fd]} {
	    incr size [dirsize $fd 0]
	} else {
	    incr size [file size $fd]
	}
    }
    return $size
}

proc xpi {xpi} {
    if {$xpi eq ""} { return }
    if {$xpi eq 1} {
	set xpi "$::prefix[string map {. {}} $::version]-"
	if {$::tcl_platform(platform) eq "windows"} {
	    append xpi "win32"
	} else {
	    # Unix currently needs a basekit exe as well
	    append xpi "$::tcl_platform(os)"
	}
	append xpi ".xpi"
    }

    puts "Creating XPI '$xpi'"
    file delete -force $xpi

    if {$::zip eq ""} {
	set ::zip [auto_execok zip]
    }
    if {$::zip eq ""} {
	puts stderr "Unable to find zip executable - cannot create xpi"
	exit 1
    }

    puts "    Generating correct install.js ..."
    set fid [open $::install_js]
    set data [read $fid]
    close $fid

    nptcl_inxpi ; # will create ./nptcl/ subdir
    file rename $::basedll $::dir/nptcl/
    if {[file exists $::basekit]} {
	file rename $::basekit $::dir/nptcl/
    }

    set plughostdll ""
    if {$::tcl_platform(platform) eq "windows"} {
	puts "    Obtaining plughostctrl.dll ..."
	file copy -force $::windir/pluginhostctrl.dll ./
	set plughostdll pluginhostctrl.dll
	lappend ::wrap $plughostdll
    }

    set size [file size $::npdll]
    incr size [dirsize $::dir/nptcl $size]
    foreach file $::wrap {
	incr size [file size $::wrap]
    }
    set map [list @NPAPIDLL@ [file tail $::npdll] \
		 @NPTCL_SIZE@ $size \
		 @VERSION@ $::version \
		 @PLUGHOSTDLL@ $plughostdll \
		]

    set js "install.js"
    set fid [open $js w]
    puts -nonewline $fid [string map $map $data]
    close $fid

    puts "    Install required size: [expr {$size/1024}]K"
    puts "    Zip'ing [list $js $::npdll nptcl] $::wrap"
    # -j would store just by names, no dir prefixes
    eval [list exec $::zip -9 -r $xpi $js $::npdll nptcl] $::wrap
}
xpi $xpi
