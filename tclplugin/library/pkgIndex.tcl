package ifneeded plugin 3.0 [list source [file join $dir plugmain.tcl]]
package ifneeded browser 1.0 [list source [file join $dir browser.tcl]]
package ifneeded setup 1.0 [list source [file join $dir common.tcl]]
