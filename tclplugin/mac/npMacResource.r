/* 
 * npMacResource.r --
 *
 * Resources definitions for the netscape plugin/
 *
 * Copyright (c) 1996 Sun Microsystems, Inc.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npMacResource.r 1.6 98/01/15 18:56:12
 */

/*
 * We define SystemSevenOrLater so that our dialogs may use the 
 * auto center feature.
 */
#define SystemSevenOrLater 1

#include <Types.r>
#include <SysTypes.r>

#define RESOURCE_INCLUDED
#include "tcl.h"
#include "tk.h"
#include "npconfig.h"

#if (NPTCL_RELEASE_LEVEL == 0)
#   define RELEASE_LEVEL alpha
#elif (NPTCL_RELEASE_LEVEL == 1)
#   define RELEASE_LEVEL beta
#elif (NPTCL_RELEASE_LEVEL == 2)
#   define RELEASE_LEVEL final
#endif

#if (NPTCL_RELEASE_LEVEL == 2)
#   define MINOR_VERSION (NPTCL_MINOR_VERSION * 16) + NPTCL_RELEASE_SERIAL
#else
#   define MINOR_VERSION NPTCL_MINOR_VERSION * 16
#endif

resource 'vers' (1) {
	NPTCL_MAJOR_VERSION, MINOR_VERSION,
	RELEASE_LEVEL, 0x00, verUS,
	NPTCL_PATCH_LEVEL,
	NPTCL_PATCH_LEVEL ", by Jim Ingham © Sun Microsystems"
};

resource 'vers' (2) {
	NPTCL_MAJOR_VERSION, MINOR_VERSION,
	RELEASE_LEVEL, 0x00, verUS,
	NPTCL_PATCH_LEVEL,
	"Tcl Plugin " NPTCL_INTERNAL_VERSION " © 1997-8"
};

/*
 * The following resource tells what MIME type and file extension
 * to associate with this plugin.  This allows Netscape to understand
 * what the plugin supports without first having to load the plugin
 * into Netscape.
 */

resource 'STR#' (126, "Plugin Information") {
	{	"Tcl Plugin " NPTCL_PATCH_LEVEL " (" NPTCL_INTERNAL_VERSION ").  Executes tclets found in Web pages.  See the <a href=http://sunscript.sun.com/plugin/>Tcl Plugin</a> for more details.",
	    "Tcl Plugin 2.0"
	};
};

resource 'STR#' (128, "Mime Types") {
	{	"application/x-tcl",
		"tcl"
	};
};

resource 'STR#' (127, "Mime Type descriptions") {
	{	"Tcl Scripts"
	};
};

/*
 * Uncomment this to get logging in the plugin
 */
 
/*
resource 'STR#' (130, "Tcl Environment Variables") {
	{	"TCL_PLUGIN_LOGFILE={Tcl Plugin Tcl-code Log}",
                "TCL_PLUGIN_CONSOLE=0",
                "TCL_PLUGIN_LOGWINDOW=0"
	};
};
*/

/* 
 * The mechanisim below loads Tcl source into the resource fork of the
 * application.  The example below creates a TEXT resource named
 * "Init" from the file "init.tcl".  This allows applications to use
 * Tcl to define the behavior of the application without having to
 * require some predetermined file structure - all needed Tcl "files"
 * are located within the application.  To source a file for the
 * resource fork the source command has been modified to support
 * sourcing from resources.  In the below case "source -rsrc {Init}"
 * will load the TEXT resource named "Init".
 */

read 'TEXT' (0, "Init", purgeable, preload) 
	":::tcl" TCL_VERSION ":library:init.tcl";
read 'TEXT' (1, "History", purgeable, preload) 
	":::tcl" TCL_VERSION ":library:history.tcl";
read 'TEXT' (2, "Word", purgeable,preload) 
	":::tcl" TCL_VERSION ":library:word.tcl";
read 'TEXT' (3, "safe", purgeable, preload)
    ":::tcl" TCL_VERSION ":library:safe.tcl";
read 'TEXT' (4, "optparse.tcl", purgeable, preload)
    ":::tcl" TCL_VERSION ":library:opt0.1:optparse.tcl";

read 'TEXT' (10, "tk", purgeable, preload) ":::tk" TK_VERSION ":library:tk.tcl";
read 'TEXT' (11, "button", purgeable, preload) ":::tk" TK_VERSION ":library:button.tcl";
read 'TEXT' (12, "dialog", purgeable, preload) ":::tk" TK_VERSION ":library:dialog.tcl";
read 'TEXT' (13, "entry", purgeable, preload) ":::tk" TK_VERSION ":library:entry.tcl";
read 'TEXT' (14, "focus", purgeable, preload) ":::tk" TK_VERSION ":library:focus.tcl";
read 'TEXT' (15, "listbox", purgeable, preload) ":::tk" TK_VERSION ":library:listbox.tcl";
read 'TEXT' (16, "menu", purgeable, preload) ":::tk" TK_VERSION ":library:menu.tcl";
read 'TEXT' (17, "optionMenu", purgeable, preload) ":::tk" TK_VERSION ":library:optMenu.tcl";
read 'TEXT' (18, "palette", purgeable, preload) ":::tk" TK_VERSION ":library:palette.tcl";
read 'TEXT' (19, "scale", purgeable, preload) ":::tk" TK_VERSION ":library:scale.tcl";
read 'TEXT' (20, "scrollbar", purgeable, preload) ":::tk" TK_VERSION ":library:scrlbar.tcl";
read 'TEXT' (21, "tearoff", purgeable, preload) ":::tk" TK_VERSION ":library:tearoff.tcl";
read 'TEXT' (22, "text", purgeable, preload) ":::tk" TK_VERSION ":library:text.tcl";
read 'TEXT' (23, "tkerror", purgeable, preload) ":::tk" TK_VERSION ":library:bgerror.tcl";
read 'TEXT' (24, "Console", purgeable, preload) ":::tk" TK_VERSION ":library:console.tcl";
read 'TEXT' (25, "msgbox", purgeable, preload) ":::tk" TK_VERSION ":library:msgbox.tcl";
read 'TEXT' (26, "comdlg", purgeable, preload) ":::tk" TK_VERSION ":library:comdlg.tcl";
read 'TEXT' (27, "prolog", purgeable, preload) ":::tk" TK_VERSION ":library:prolog.ps";

read 'TEXT' (30, "plugmain.tcl", purgeable, preload) "::plugin:plugmain.tcl";
read 'TEXT' (31, "console.tcl", purgeable, preload) "::plugin:console.tcl";
read 'TEXT' (32, "browser.tcl", purgeable, preload) "::plugin:browser.tcl";
read 'TEXT' (33, "common.tcl", purgeable, preload) "::plugin:common.tcl";

read 'TEXT' (41, "cfg.tcl", purgeable, preload) "::library:cfg.tcl";
read 'TEXT' (42, "log.tcl", purgeable, preload) "::library:log.tcl";
read 'TEXT' (43, "logo.tcl", purgeable, preload) "::library:logo.tcl";
read 'TEXT' (44, "policy.tcl", purgeable, preload) "::library:policy.tcl";
read 'TEXT' (45, "rpi.tcl", purgeable, preload) "::library:rpi.tcl";
read 'TEXT' (46, "trustexpr.tcl", purgeable, preload) "::library:trustexpr.tcl";
read 'TEXT' (47, "url.tcl", purgeable, preload) "::library:url.tcl";
read 'TEXT' (48, "wait.tcl", purgeable, preload) "::library:wait.tcl";

/*
 *  Here is the dialog that we use for error notification
 */
 
resource 'DLOG' (128, purgeable) {
    {0, 0, 195, 344}, dBoxProc, visible, noGoAway, 0,
     128, "Tclet Warning", alertPositionParentWindowScreen
};

resource 'DITL' (128, "Warning Box", purgeable) {
    {
	{16,16, 179, 328}, StaticText   {disabled, "^0"}
    }
};
/*
 * Here is the custom file open dialog. This dialog is used instead of
 * the default file dialog if the -filetypes flag is specified.
 */

resource 'DLOG' (130, purgeable) {
    {0, 0, 195, 344}, dBoxProc, invisible, noGoAway, 0,
     130, "", noAutoCenter
};

resource 'DITL' (130, "File Open Box", purgeable) {
    {
	{135, 252, 155, 332}, Button   {enabled, "Open"},
	{104, 252, 124, 332}, Button   {enabled, "Cancel"},	    
        {  0,   0,   0,   0}, HelpItem {disabled, HMScanhdlg {130}},
        {  8, 235,  24, 337}, UserItem {enabled},
        { 32, 252,  52, 332}, Button   {enabled, "Eject"},
        { 60, 252,  80, 332}, Button   {enabled, "Desktop"},    
        { 29,  12, 159, 230}, UserItem {enabled},
        {  6,  12,  25, 230}, UserItem {enabled},
        { 91, 251,  92, 333}, Picture  {disabled, 11},
        {168,  20, 187, 300}, Control  {enabled, 131} 
    }
};

resource 'CNTL' (131, "File Types menu", purgeable) {
    {168, 20, 187, 300},
    popupTitleLeftJust,
    visible,
    80,
    132,
    popupMenuCDEFProc,
    0,
    "File Type:"
};


resource 'MENU' (132, preload) {
    132,
    textMenuProc,
    0xFFFF, enabled, "", {}
};
