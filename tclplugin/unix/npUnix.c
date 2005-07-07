/*
 * npUnix.c --
 *
 * Netscape Client Plugin API
 * - Wrapper function to interface with the Netscape Navigator
 *
 * Copyright (c) 2002-2005 ActiveState Corporation.
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
#ifndef TCL_KIT_DLL
#  define TCL_KIT_DLL "tclplugin.so"
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
NpLoadLibrary(HMODULE *tclHandle, char *dllName, int dllNameSize)
{
    char *envdll, libname[MAX_PATH];
    HMODULE handle = (HMODULE) NULL;

    *tclHandle = NULL;

    /*
     * Try a user-supplied Tcl dll to start with.
     */
    envdll = getenv("TCL_PLUGIN_DLL");
    if (envdll != NULL) {
	NpLog("Attempt to load Tcl dll (TCL_PLUGIN_DLL) '%s'\n", envdll);
	handle = dlopen(envdll, RTLD_NOW | RTLD_GLOBAL);
	if (handle) {
	    memcpy(libname, envdll, MAX_PATH);
	}
    }

#ifdef HAVE_DLADDR
    if (!handle) {
	/*
	 * Try based on current path by using dladdr.
	 * Grab any symbol - we just need one for reverse mapping
	 */
	char (* npgetmime)(void) =
	    (char (*)(void)) dlsym(handle, "NP_GetMIMEDescription");
	Dl_info info;

	if (npgetmime && dladdr(npgetmime, &info)) {
	    snprintf(libname, MAX_PATH, "%s/%s", info.dli_fname, TCL_KIT_DLL);
	    NpLog("Attempt to load Tcl dll (plugkit) '%s'\n", libname);
	    handle = dlopen(libname, RTLD_NOW | RTLD_GLOBAL);
	}
    }
#endif

    if (!handle) {
	/*
	 * Try based on full path.
	 */
	snprintf(libname, MAX_PATH, "%s/%s", defaultLibraryDir, TCL_LIB_FILE);
	NpLog("Attempt to load Tcl dll (default) '%s'\n", libname);
	handle = dlopen(libname, RTLD_NOW | RTLD_GLOBAL);
    }

    if (!handle) {
	/*
	 * Try based on anywhere in the path.
	 */
	strncpy(libname, TCL_LIB_FILE, MAX_PATH);
	NpLog("Attempt to load Tcl dll (libpath) '%s'\n", libname);
	handle = dlopen(libname, RTLD_NOW | RTLD_GLOBAL);
    }

    if (!handle) {
	/*
	 * Try different versions anywhere in the path.
	 */
	char *pos;

	pos = strstr(libname, "tcl")+4;
	if (*pos == '.') {
	    pos++;
	}
	*pos = '9'; /* count down from '8' to '4'*/
	while (!handle && (--*pos > '3')) {
	    NpLog("Attempt to load Tcl dll (default_ver) '%s'\n", libname);
	    handle = dlopen(libname, RTLD_NOW | RTLD_GLOBAL);
	}
    }

    if (!handle) {
	NpPlatformMsg("Failed to load Tcl dll!", "NpCreateMainInterp");
	return TCL_ERROR;
    }

    *tclHandle = handle;
    if (dllNameSize > 0) {
#ifdef HAVE_DLADDR
	/*
	 * Use dladdr if possible to get the real libname we are loading.
	 * Grab any symbol - we just need one for reverse mapping
	 */
	int (* tcl_Init)(Tcl_Interp *) =
	    (int (*)(Tcl_Interp *)) dlsym(handle, "Tcl_Init");
	Dl_info info;

	if (tcl_Init && dladdr(tcl_Init, &info)) {
	    NpLog("using dladdr '%s' => '%s'\n", libname, info.dli_fname);
	    snprintf(dllName, dllNameSize, info.dli_fname);
	} else
#endif
	    snprintf(dllName, dllNameSize, libname);
    }
    return TCL_OK;
}
