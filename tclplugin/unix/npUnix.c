/*
 * npUnix.c --
 *
 * Netscape Client Plugin API
 * - Wrapper function to interface with the Netscape Navigator
 *
 * Copyright (c) 2002 ActiveState Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS:  @(#) $Id$
 */

#define XP_UNIX 1

#include "np.h"
#include <string.h>

#include <dlfcn.h>
#ifndef TCL_LIB_FILE
#  define TCL_LIB_FILE "libtcl8.4.so"
#endif

/*
 * In some systems, like SunOS 4.1.3, the RTLD_NOW flag isn't defined
 * and this argument to dlopen must always be 1.  The RTLD_GLOBAL
 * flag is needed on some systems (e.g. SCO and UnixWare) but doesn't
 * exist on others;  if it doesn't exist, set it to 0 so it has no effect.
 */

#ifndef RTLD_NOW
#   define RTLD_NOW 1
#endif

#ifndef RTLD_GLOBAL
#   define RTLD_GLOBAL 0
#endif

/*
 * Default directory in which to look for Tcl/Tk libraries.  The
 * symbol is defined by Makefile.
 */

static char defaultLibraryDir[sizeof(LIB_RUNTIME_DIR)+200] = LIB_RUNTIME_DIR;


/*
 *----------------------------------------------------------------------
 *
 * NPP_GetMIMEDescription --
 *
 *	Called by the Navigator to get a string that describes the MIME
 *	types implemented by the plugin.
 *
 * Results:
 *	A string describing the application/x-tcl MIME type.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

char *
NPP_GetMIMEDescription()
{
    return "application/x-tcl:.tcl:Tcl Web Applets";
}

/*
 * NP_GetMIMEDescription
 *	- Netscape needs to know about this symbol
 *	- Netscape uses the return value to identify when an object instance
 *	  of this plugin should be created.
 */
char *
NP_GetMIMEDescription(void)
{
    return NPP_GetMIMEDescription();
}

/*
 * NP_GetValue [optional]
 *	- Netscape needs to know about this symbol.
 *	- Interfaces with plugin to get values for predefined variables
 *	  that the navigator needs.
 */
NPError
NP_GetValue(void *future, NPPVariable variable, void *value)
{
    return NPP_GetValue(future, variable, value);
}

/*
 *----------------------------------------------------------------------
 *
 * NpLoadLibrary --
 *
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

EXTERN int
NpLoadLibrary(void **tclHandle, void **tkHandle)
{
    char *pos, libname[512];
    char *loadfile = NULL;
    void *handle = NULL;

    *tclHandle = NULL;
    *tkHandle  = NULL;

    /*
     * Try a user-supplied Tcl dll to start with.
     */
    loadfile = getenv("TCL_PLUGIN_DLL");
    if (loadfile != NULL) {
	NpLog("Attempt to load Tcl dll '%s'\n", loadfile);
	handle = dlopen(loadfile, RTLD_NOW | RTLD_GLOBAL);
    }

    if (!handle) {
	if (strlen(TCL_LIB_FILE) < 3) {
	    NpPlatformMsg("Invalid base Tcl library filename provided!",
		    "NpCreateMainInterp");
	    return TCL_ERROR;
	}

	/* Try based on full path. */
	snprintf(libname, 511, "%s/%s", defaultLibraryDir, TCL_LIB_FILE);
	NpLog("Attempt to load Tcl dll '%s'\n", libname);
	handle = dlopen(libname, RTLD_NOW | RTLD_GLOBAL);
	if (!handle) {
	    /* Try based on anywhere in the path. */
	    strcpy(libname, TCL_LIB_FILE);
	    NpLog("Attempt to load Tcl dll '%s'\n", libname);
	    handle = dlopen(libname, RTLD_NOW | RTLD_GLOBAL);
	}
	if (!handle) {
	    /* Try different versions anywhere in the path. */
	    pos = strstr(libname, "tcl")+4;
	    if (*pos == '.') {
		pos++;
	    }
	    *pos = '9'; /* count down from '8' to '4'*/
	    while (!handle && (--*pos > '3')) {
		NpLog("Attempt to load Tcl dll '%s'\n", libname);
		handle = dlopen(libname, RTLD_NOW | RTLD_GLOBAL);
	    }
	}
    }
    if (!handle) {
	NpPlatformMsg("Failed to load Tcl dll!", "NpCreateMainInterp");
	return TCL_ERROR;
    }
    *tclHandle = handle;

    /*
     * Derive the name of Tk's library from Tcl's.
     * Should work on all platforms (we hope ...).
     */
    pos = libname + strlen(libname) - strlen(TCL_LIB_FILE);
    pos = strstr(pos, "tcl")+1;
    if (pos) {
	*pos++ = 'k';
	while (*pos) {
	    *pos++ = pos[1];
	}
    }
    NpLog("Attempt to load Tk dll '%s'\n", libname);
    handle = dlopen(libname, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
	dlclose(tclHandle);
	*tclHandle = NULL;
	NpPlatformMsg("Failed to load Tk dll!", "NpCreateMainInterp");
	return TCL_ERROR;
    }
    *tkHandle = handle;

    return TCL_OK;
}
