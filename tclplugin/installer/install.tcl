# install.tcl --
#
#     Installer for the Tcl plugin.
#
# CONTACT:      sunscript-plugin@sunscript.sun.com
#
# AUTHORS:      Jacob Levy              Laurent Demailly
#               jyl@eng.sun.com         demailly@eng.sun.com
#               jyl@tcl-tk.com          dl@mail.org , L@demailly.com
#
# Please contact us directly for questions, comments and enhancements.
#
# Copyright (c) 1995-1997 Sun Microsystems, Inc.
#
# SCCS: @(#) install.tcl 1.41 98/01/16 10:12:38

set supportEmail "plugin@scriptics.com"
set supportUrl   "http://www.scriptics.com/plugin/"


# Check if this is running with the plugin environment
if {![info exists plugin(patchLevel)]} {
    puts stderr "Can not install - distribution problem:\n\
    \tno plugin(patchLevel) ! (you must use ./install.sh)\n"
    exit 1
}

set PRODUCT "Tcl Plugin $plugin(patchLevel)"

set user ""
catch {set user $env(LOGNAME)}
catch {set user $env(USER)}
set email "$user@[info hostname]"

set DETAILS "(P $plugin(patchLevel)/$plugin(pkgVersion), D [lindex $argv 0], T [info patchlevel], U $user, H [info hostname], S $tcl_platform(platform)/$tcl_platform(machine)/$tcl_platform(os)/$tcl_platform(osVersion))"

set netscape "netscape ${supportUrl}applets.html#V2"

# Start logging

if {[catch {package require log 1.0} msg]} {
   puts stderr "Can not install - distribution problem:\n\
    \tpackage require log failed: $msg\n\
    \t$DETAILS"
    exit 1
}


# (We need the backslah because of SCCS !)
set uniq "[clock format [clock seconds] -format "%m\%d\%H\%M\%S"]"
set logFileName inst$uniq.log
#set logFileName stderr

::log::setup $logFileName

puts "Installation log file is : $logFileName"

proc log {msg {type {}}} {
    ::log::log {} $msg $type
}

log "Installing $PRODUCT $DETAILS"

set plugin(topdir) [file dirname $plugin(library)]
log "plugin(topdir) = $plugin(topdir) - PluginVersion $plugin(patchLevel)"

# We need to unset the TCL_PLUGIN_DIR otherwise when we "test" the
# install we will not use the installed version...
catch {unset env(TCL_PLUGIN_DIR)}

if {[catch {package require Tk 8.0} msg]} {
    set m "Can not initialize Tk : $msg"
    log $m ERROR;
    puts stderr \n$m\n
    set GUI 0
} else {
#    auto_reset
#    puts "tk_library=$tk_library; auto_path=$auto_path";
    set GUI 1
}

proc abort {msg} {
    log $msg FATALERROR
    if {$::GUI} {
	grab release .msg
	tk_messageBox -icon error -title "Fatal Error" -message $msg
	tkwait window [troubleReport $msg]
    } else {
	puts stderr $msg
    }
    log "...aborting..." ERROR
    exit 1
}

# copy a file into a dir
proc copyOne {file dir} {
    set target [file join $dir [file tail $file]]
    log "copying \"$file\" as \"$target\""
    if {[catch {file copy -force -- $file $target} msg]} {
	abort "can't copy \"$file\" as \"$target\": $msg"
    }
    return $target
}

proc chMod {mode file} {
    log "changing mode for \"$file\" to $mode";
    if {[catch {file attributes $file -permissions $mode} msg]} {
	abort "failed chmod for \"$file\" to $mode : $msg"
    }
}

proc Delete {file} {
    log "deleting \"$file\"";
    if {[catch {file delete -force $file} msg]} {
	abort "failed file delete for \"$file\" : $msg"
    }
}

proc Glob {pattern {flags --}} {
    if {[catch {glob $flags $pattern} flist]} {
	abort "can't get file list for pattern \"$pattern\": $flist"
    }
    return $flist
}

proc Mkdir {destdir} {
    log "Making directory $destdir"
    if {[catch {file mkdir $destdir} msg]} {
	abort "can't make directory \"$destdir\": $msg"
    }
}

proc MoveToDir {file dir} {
    log "moving \"$file\" to \"$dir\""
    if {![file isdirectory $dir]} {
	Mkdir $dir
    }
    if {[catch {file rename -force -- $file $dir} msg]} {
	abort "can't move  \"$file\" to \"$dir\": $msg"
    }
}

proc installAny {pattern destdir mode} {
    log "installing \"$pattern\" -> \"$destdir\""
    Mkdir $destdir
    foreach file [Glob $pattern] {
	chMod $mode [copyOne $file $destdir]
    }
}

proc installExec {pattern destdir} {
    installAny $pattern $destdir 0555
}

proc installData {pattern destdir} {
    installAny $pattern $destdir 0444
}

proc installHier {srcdir destdir} {
    log "tree copy \"$srcdir\" into \"$destdir\""
    set ddest [file join $destdir [file tail $srcdir]]
    foreach s [Glob [file join $srcdir *]] {
	update
	if {[file isdirectory $s]} {
	    installHier $s $ddest
	} else {
	    installData $s $ddest
	}
    }
}


proc MoveAwayOldVersions {in what dest} {
    global plugin
    set found 0
    log "Cheking old versions of \"$what\" in \"$in\""
    foreach item [Glob [file join $in $what] -nocomplain] {
	incr found
	MoveToDir $item $dest
    }
    return $found
}
   

proc Install {targetdir} {

    global logFileName plugin exitcode uniq backup

    log "Called install ([info level 1])"
    tellUser "Installing... Please Wait..." 0

    # Where the .so goes
    set sodir [file join $targetdir plugins]
    # Where everything else goes
    set pldir [file join $targetdir tclplug]

    set backup 0
    # Unique(!) id for old version, if needed
    set olddir [file join $pldir "old$uniq"]
    log "Old (backup) directory will be \"$olddir\""

    # Backup/move away .so's
    if {[MoveAwayOldVersions $sodir "libtclp{\[0-9\],lugin}*" $olddir]} {
	set backup 1
    }
    # Backup/move away additional files
    if {[MoveAwayOldVersions $pldir "$plugin(version)" $olddir]} {
	incr backup
    }

    if {$backup} {
	puts stderr "your old tcl plugin files have been moved to:"
	puts stderr "\t\"$olddir\""
    }

    installExec [file join plugins *] $sodir

    set srcexec [info nameofexecutable]
    installExec $srcexec $pldir

    set executable [file tail $srcexec]

    installExec [file join plugins *] $sodir

    installHier [file join tclplug $plugin(version)] $pldir 


    set fname [file join $pldir $plugin(version) plugin installed.cfg]

    log "Adding site specific paths to \"$fname\" ($sodir,$pldir,$executable)"
    chMod 0644 $fname
    if {[catch {open $fname a+} f]} {
	abort "can't open \"$fname\" for append: $f";
    }
    puts $f [list set ::plugin(executable) [file join $pldir $executable]]
    puts $f [list set ::plugin(sharedLibraryDir) $sodir]
    puts $f "# EOF (generated by the installer $::DETAILS)"
    close $f


    set exitcode 0

    log "Installation completed !"
	
    tellUser "Done!

    Comments, bug reports and questions --> email to :

    	$::supportEmail

    Please include log file: $logFileName

    Visit the demos at :

    	${::supportUrl}applets.html


    or test the plugin now by hitting the \"Test It!\" button." 1

    if {$backup && $::GUI} {
	noticeUser "Your old Tcl plugin files have been moved to\n$olddir"
    }

}

proc tellUser {msg end} {
    if {$::GUI} {
	.msg config -text $msg
	if {$end} {
	    destroy .finst
	    . configure -cursor  {}
	    grab release .msg
	    pack forget .ok .back .custom
	    pack .trouble .testb .log -in .buttons -side right
	} else {
	    . configure -cursor watch
	    grab .msg
	    update
	}
    } else {
	puts $msg
    }
}

# below that point a lot would also need more in deep rewriting
# (using a single function instead of copy/paste to view
#  each document, etc... etc...)  .... when time will permit ....

if {$GUI} {
    wm title . "Install $PRODUCT";
    option add *Entry.relief sunken
    option add *Radiobutton.highlightThickness 0
    frame .top -bd 5
    message .top.title -aspect 2000 -justify center \
	    -text "Install $PRODUCT"

    package require tclplogo 1.0

    image create photo tclimage -data $::TclpLogoData

    label .top.left -image tclimage
    label .top.right -image tclimage

    
    message .msg -aspect 2000
    frame .buttons -bd 5
    label .buttons.l -text "Choose one of:"
    frame .buttonsDocs -bd 5
    label .buttonsDocs.l -text "or View:"
    button .ok -text "Individual Install" -command EasyInstall
    button .custom -text "Site-wide/Custom Install" -command Custom
    #button .site -text "Site-wide Install" -command Site -state disabled
    button .readmeb -text "Read Me" -command Readme
    button .licenseb -text "License" -command ViewLicense
    #button .helpb -text "Help" -command Help
    button .faqb -text FAQ -command FAQ
    button .new -text "What's New?" -command NEW
    button .quit -text "Quit" -command {
	catch {::log::setup stop}
	set ::exit $exitcode
    }
    button .back -text "Back" -command {
	destroy .finst
	pack forget .back
	.ok configure -text "Individual Install" -command EasyInstall
	FirstScreen
    }
    foreach b {.ok .custom .quit} {
	bind $b <Return> "$b flash ; $b invoke"
    }
    button .log -text "View Log" -command viewLog
    button .trouble -text "Submit Trouble Report" -command "troubleReport {}"
    button .testb -text "Test It!" -command testIt
    set custom 0
    set exitcode 1

    proc FirstScreen {} {
	global logFileName

	catch {
	    pack forget .top
	    pack forget .msg
	    pack forget .buttons
	    pack forget .buttonsDocs .buttonsDocs.l
	    pack forget .ok .custom
	    pack forget .quit .readmeb .licenseb .faqb ; # .helpb
	}
	.msg configure -aspect 2000 -text "
	The tcl plugin installed files need to be installed
	in sub directories of browser specific 'home' directory.
	If you select Individual Install, the plugin will be immediately
	installed in ~/.netscape/plugins and ~/.netscape/tclplug

	Log file for install is \"$logFileName\"
	please include it in trouble reports.

	Note: Please close all Netscape windows before installing!
	"

	pack .top.left .top.title .top.right -side left

	pack .top
	pack .msg -fill x
	pack .buttonsDocs.l -side top
	pack .buttonsDocs -side bottom -fill x -expand 1
	pack .buttons -side bottom -fill x -ipadx 5
	pack .buttons.l -side top
	pack .ok .custom -in .buttons -side left -padx 2
	pack .quit -in .buttons -side right -fill x -expand 1 -ipadx 10 -padx 10 ; # .helpb
	pack .readmeb .licenseb .faqb .new \
		-in .buttonsDocs -side left -padx 2 -fill x -expand 1
	focus .ok
    }

    proc EasyInstall {} {
	global env
	Install $env(HOME)/.netscape
    }

    proc Custom {} {
	global env
	global logFileName

	pack forget .custom
	pack .back -in .buttons
	.msg config -aspect 2000 -text "
	Netscape recommends MOZILLA_HOME/plugins as the place to install
	plugins site-wide. The default value of MOZILLA_HOME is 
	/usr/local/lib/netscape. If you accept MOZILLA_HOME, as your top
	destination directory you will not have to set any (additional)
	environment variables.

	If you install the plugin shared library in another directory, your
	users will have to set the environment variable NPX_PLUGIN_PATH to
	where you installed the shared library (for netscape to find the
	shared library) and TCL_PLUGIN_DIR to where you installed the
	.tcl scripts of the plugin (for the plugin to find its 
	plugin(library)). You may wish to provide a site wide wrapper 
	shell script that sets these variables to the correct location
	before invoking Netscape Navigator (though using the simple 
	MOZILLA_HOME for the latest Communicator versions is much simpler).

	Log file for install: $logFileName, please include it in
	trouble reports.
	"
	if {[info exists env(MOZILLA_HOME)]} {
	    set ::targetTopDir $env(MOZILLA_HOME)
	} else {
	    set ::targetTopDir /usr/local/lib/netscape
	}
	frame .finst
	pack .finst -fill both -expand 1

	set f .finst.finput
	frame $f
	label $f.l -text "Installation Top Dir "
	entry $f.e -textvariable targetTopDir -width 0
	bind $f.e <Return> {Install $targetTopDir}
	pack $f.l -side left
	pack $f.e -side right -fill x -expand 1
	pack $f -fill x -padx 10

	set f .finst.fpreview1
	frame $f
	label $f.l1 -text "Shared lib will thus go to " -bd 0 -padx 0
	label $f.l2 -textvariable targetTopDir -bd 0 -padx 0
	label $f.l3 -text "/plugins" -bd 0 -padx 0
	pack $f.l1 $f.l2 $f.l3 -side left -padx 0 -ipadx 0
	pack $f

	set f .finst.fpreview2
	frame $f
	label $f.l1 -text "Support files (.tcl...) to " -bd 0 -padx 0
	label $f.l2 -textvariable targetTopDir -bd 0 -padx 0
	label $f.l3 -text "/tclplug ($::plugin(version)/*)" -bd 0 -padx 0
	pack $f.l1 $f.l2 $f.l3 -side left -padx 0 -ipadx 0
	pack $f


	.ok config -text "Install It!" -command {Install $targetTopDir}
    }


    proc Help {} {
	catch {destroy .help}
	toplevel .help
	wm title .help "Help for Tcl Plugin Install"
	text .help.t -height 16
	.help.t insert insert \
		"

	Help needs updating

	"
	pack .help.t

	button .help.quit -text Dismiss -command {destroy .help}
	pack .help.quit
    }

    proc Readme {} {
	global plugin

	catch {destroy .readme}
	toplevel .readme
	frame .readme.top
	wm title .readme "Unix Installation information for the Tcl Plugin"
	text .readme.t -yscrollcommand {.readme.s set}
	scrollbar .readme.s -command {.readme.t yview} -orient vertical
	pack .readme.s -side right -fill y -in .readme.top
	pack .readme.t -side left -fill both -expand true -in .readme.top
	pack .readme.top
	if [catch {open [file join $plugin(topdir) doc INSTALL.unix]} in] {
	    .readme.t insert insert $in
	} else {
	    .readme.t insert insert [read $in]
	    close $in
	}
	button .readme.quit -text Dismiss -command {destroy .readme}
	pack .readme.quit
    }
    proc ViewLicense {} {
	global plugin

	catch {destroy .license}
	toplevel .license
	frame .license.top
	wm title .license "License for Tcl Plugin"
	text .license.t -yscrollcommand {.license.s set}
	scrollbar .license.s -command {.license.t yview} -orient vertical
	pack .license.s -side right -fill y -in .license.top
	pack .license.t -side left -fill both -expand true -in .license.top
	pack .license.top
	if [catch {open [file join $plugin(topdir) doc license.terms]} in] {
	    .license.t insert insert $in
	} else {
	    .license.t insert insert [read $in]
	    close $in
	}
	button .license.quit -text Dismiss -command {destroy .license}
	pack .license.quit
    }
    proc FAQ {} {
	global plugin
	
	catch {destroy .faqview}
	toplevel .faqview
	frame .faqview.top
	wm title .faqview "Frequently Asked Questions for Tcl Plugin"
	text .faqview.t -yscrollcommand {.faqview.s set}
	scrollbar .faqview.s -command {.faqview.t yview} -orient vertical
	pack .faqview.s -side right -fill y -in .faqview.top
	pack .faqview.t -side left -fill both -expand true -in .faqview.top
	pack .faqview.top
	if [catch {open [file join $plugin(topdir) doc FAQ]} in] {
	    .faqview.t insert insert $in
	} else {
	    .faqview.t insert insert [read $in]
	    close $in
	}
	button .faqview.quit -text Dismiss -command {destroy .faqview}
	pack .faqview.quit
    }
    proc NEW {} {
	global plugin

	catch {destroy .newview}
	toplevel .newview
	frame .newview.top
	wm title .newview "What's New In This Release?"
	text .newview.t -yscrollcommand {.newview.s set}
	scrollbar .newview.s -command {.newview.t yview} -orient vertical
	pack .newview.s -side right -fill y -in .newview.top
	pack .newview.t -side left -fill both -expand true -in .newview.top
	pack .newview.top
	if [catch {open [file join $plugin(topdir) doc new]} in] {
	    .newview.t insert insert $in
	} else {
	    .newview.t insert insert [read $in]
	    close $in
	}
	button .newview.quit -text Dismiss -command {destroy .newview}
	pack .newview.quit
    }

    proc viewLog {} {
	global logFileName logfile
	catch {close $logfile}
	catch {destroy .logview}
	toplevel .logview
	frame .logview.top
	wm title .logview "Log of Installation"
	text .logview.t -yscrollcommand {.logview.s set}
	scrollbar .logview.s -command {.logview.t yview} -orient vertical
	pack .logview.s -side right -fill y -in .logview.top
	pack .logview.t -side left -fill both -expand true -in .logview.top
	pack .logview.top
	if [catch {open $logFileName} in] {
	    .logview.t insert insert $in
	} else {
	    .logview.t insert insert [read $in]
	    close $in
	}
	button .logview.quit -text Dismiss -command {destroy .logview}
	pack .logview.quit
    }

    proc troubleReport {{err {}}} {
	global logFileName logfile trouble
	catch {::log::setup stop}
	catch {destroy .troubleview}

	set w .troublechoice
	catch {destroy $w}
	toplevel $w
	wm title $w "Trouble report"
	message $w.m -aspect 1000 \
		-text "Please select what kind of problem you have
(you will be able to give more details after this choice)"
        pack $w.m 
        set i 0 
        foreach {msg type} {
	    "Installation gave an error message" install
	    "It does not show up in Help/About Plug-ins..." nsnotfound
	    "It does show up but marked disabled (even when I retry)" nsdisabled
	    "It crashes! (I will explain where/when/how)" crash
	    "Something else I will explain..." misc
	    "Nothing is wrong..." nothing
	} {
	    radiobutton $w.r$i -anchor w\
		    -variable trouble -value $type -text $msg
	    pack $w.r$i -fill x -expand 1
	    incr i
	}
        frame $w.fb
        button $w.fb.n -text "Next..." -command "destroy $w"
        button $w.fb.c -text "Cancel" -command "set trouble nothing;destroy $w"
        pack $w.fb.n  $w.fb.c -side left -fill x -expand 1
        set trouble nothing
        pack $w.fb -fill x -expand 1
        tkwait window $w

        if {$trouble == "nothing"} {
	    noticeUser "No problem ? Good ! Thanks."
	    return
	}

	toplevel .troubleview
	wm title .troubleview "Submit a trouble report"
	message .troubleview.m -aspect 2000 -text "
	The window below contains the log of your attempt to install the Tcl 
	Plugin. Please type detailed additional information explaining
	what is wrong with the plugin and what you tried:
	(Before submitting, try again to launch netscape from another
        window and check the 'Help/About Plug-ins' menu, see if the Tcl plugin
        is here and enabled, if yes everything should work !)

	When you hit the \"Send Report\" button, the report will be sent by
	email to $::supportEmail"
	pack .troubleview.m -fill x
	frame .troubleview.top
	text .troubleview.t -yscrollcommand {.troubleview.s set}
	scrollbar .troubleview.s -command {.troubleview.t yview} -orient vertical
	pack .troubleview.s -side right -fill y -in .troubleview.top
	pack .troubleview.t -side left -fill both -expand true -in .troubleview.top
	pack .troubleview.top
	.troubleview.t insert insert "Problem type: $trouble - Details:\n"
	.troubleview.t insert insert "Type your comments here: \n\n"
	if [catch {open $logFileName} in] {
	    .troubleview.t insert insert $in
	} else {
	    .troubleview.t insert insert [read $in]
	    close $in
	}
	if {"$err" != ""} {
	    .troubleview.t insert insert "\n\n$err"
	}
	.troubleview.t mark set insert 2.end
	.troubleview.t tag add sel 2.0 2.end
	focus .troubleview.t
	bind .troubleview.t <KeyRelease>\
		"+.troubleview.submit configure -state normal"
	frame .troubleview.buttons -bd 10
	button .troubleview.quit -text Dismiss -command {destroy .troubleview}
	button .troubleview.submit -state disabled \
		-text "Send Report" -command {
	    sendTroubleReport
	    destroy .troubleview
	}
	frame .troubleview.email
	label .troubleview.email.l -text "Your email address (for replies):"
	entry .troubleview.email.e -textvariable email
	pack .troubleview.email.l .troubleview.email.e -side left
	pack .troubleview.buttons -side bottom
	pack .troubleview.email -side bottom
	pack .troubleview.quit .troubleview.submit -in .troubleview.buttons \
		-side left
	return .troubleview
    }

    proc sendTroubleReport {} {
	global email PRODUCT DETAILS

	set text [.troubleview.t get 1.0 end]
	set msg "To: $::supportEmail
From: $email
Subject: Tcl plugin trouble report

Trouble report $PRODUCT $DETAILS:

$text"
	exec /usr/lib/sendmail $::supportEmail << $msg
    }

    proc testIt {} {
	global netscape

	catch {destroy .test}
	toplevel .test
	message .test.m -aspect 2000 -text "
	Please type in the command to invoke Netscape Navigator. I've initialized
	the entry box below to a command that will visit our page of example tclets.
	When you press \"Launch\", I will execute the command in the entry box. It
	might take several seconds for Netscape Navigator to start. 
	Note that sometimes it does not work the very first time you start
	Netscape. You should check that there is only ONE Tcl plugin listed
        in the Help/About Plug-ins menu and that it is enabled. If it is
        not the case,  exit the installer, eventually remove older versions,
        and try launching netscape directly (eventually twice to 'enable' the
        plugin). It should then work (always check the about:plugins before
        reporting a bug or problem).
	"
	pack .test.m -side top
	frame .test.top
	label .test.l -text "Command: "
	entry .test.e -textvariable netscape -width 60
	pack .test.l .test.e -side left -in .test.top
	pack .test.top -side top
	frame .test.buttons
	button .test.launch -text "Launch" -command invokeIt
	button .test.dismiss -text "Dismiss" -command {destroy .test}
	pack .test.launch .test.dismiss -side left -in .test.buttons
	pack .test.buttons -side bottom
	bind .test.e <Return> invokeIt
	focus .test.e
    }

    proc noticeUser {msg} {
	log "noticing user about \"$msg\""
	tk_messageBox -type ok -icon info\
		-message "$msg"
    }

    proc invokeIt {} {
	global netscape
	log "about to invoke \"exec $netscape &\""
	if {[catch {eval exec $netscape &} msg]} {
	    log "failed exec: $msg"
	    tk_messageBox -type ok -icon error\
		    -message "Can't start netscape: $msg"
	} else {
	    log "sucessfully execed"
	    catch {destroy .test}
	}
    }


    FirstScreen

    vwait exit

    if {$exit == 0} {
	puts "
	All done, thanks for installing the Tcl Plugin!

	Please exit any copies of Navigator that are running now, and restart
	Navigator. View the Help->About plug-ins menu item and verify that
	the Tcl plugin is found by Netscape Navigator. If it appears in the
	Installed plug-ins page, you can view the demos at the URL:

	   $::supportUrl

	You may also want to check out the plugin tutorial site at:

	   ${::supportUrl}tutorial

	Comments, bug reports, questions --> email to :

	   $::supportEmail

	Please include the following log file in bug reports

	$logFileName

	Thanks for installing the Tcl plugin $plugin(patchLevel) !"
    }

    exit $exit

} else {
    log "pure tcl installation not implemented yet. you need X11.\
	    installation aborted" ERROR;
    exit 1;
}
