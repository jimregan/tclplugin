/* 
 * npWin.c --
 *
 * CONTACT:		tclplugin-core@lists.sourceforge.net
 *
 * Copyright (c) 2003-2004 ActiveState Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS:  @(#) $Id$
 */

#include "np.h"

#ifndef TCL_LIB_FILE
#   define TCL_LIB_FILE "tcl84.dll"
#endif
#define snprintf _snprintf

/*
 * Default directory in which to look for Tcl libraries.  The
 * symbol is defined by Makefile.
 */

static char defaultLibraryDir[sizeof(LIB_RUNTIME_DIR)+200] = LIB_RUNTIME_DIR;


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

extern int
NpLoadLibrary(HMODULE *tclHandle, char *dllName, int dllNameSize)
{
    char *envdll, libname[MAX_PATH];
    HMODULE handle = (HMODULE) NULL;

    /*
     * Try a user-supplied Tcl dll to start with.
     */
    envdll = getenv("TCL_PLUGIN_DLL");
    if (envdll != NULL) {
	NpLog("Attempt to load Tcl dll (TCL_PLUGIN_DLL) '%s'\n", envdll);
	handle = LoadLibrary(envdll);
	if (handle) {
	    memcpy(libname, envdll, MAX_PATH);
	}
    }

    if (!handle) {
	/*
	 * Try based on full path.
	 */
	snprintf(libname, MAX_PATH, "%s/%s", defaultLibraryDir, TCL_LIB_FILE);
	NpLog("Attempt to load Tcl dll (default) '%s'\n", libname);
	handle = LoadLibrary(libname);
    }

    if (!handle) {
	/*
	 * Try based on anywhere in the path.
	 */
	strncpy(libname, TCL_LIB_FILE, MAX_PATH);
	NpLog("Attempt to load Tcl dll (libpath) '%s'\n", libname);
	handle = LoadLibrary(libname);
    }

    if (!handle) {
	/*
	 * Try based on ActiveTcl registry entry
	 */
	char path[MAX_PATH], vers[MAX_PATH];
	DWORD result, size = MAX_PATH;
	HKEY regKey;
#define TCL_REG_DIR_KEY "Software\\ActiveState\\ActiveTcl"
	result = RegOpenKeyEx(HKEY_LOCAL_MACHINE, TCL_REG_DIR_KEY, 0,
		KEY_READ, &regKey);
	if (result != ERROR_SUCCESS) {
	    NpLog("Could not access registry \"HKLM\\%s\"\n", TCL_REG_DIR_KEY);

	    result = RegOpenKeyEx(HKEY_CURRENT_USER, TCL_REG_DIR_KEY, 0,
		    KEY_READ, &regKey);
	    if (result != ERROR_SUCCESS) {
		NpLog("Could not access registry \"HKCU\\%s\"\n", TCL_REG_DIR_KEY);
		return TCL_ERROR;
	    }
	}

	result = RegQueryValueEx(regKey, "CurrentVersion", NULL, NULL,
		vers, &size);
	RegCloseKey(regKey);
	if (result != ERROR_SUCCESS) {
	    NpLog("Could not access registry \"%s\" CurrentVersion\n",
		    TCL_REG_DIR_KEY);
	    return TCL_ERROR;
	}

	snprintf(path, MAX_PATH, "%s\\%s", TCL_REG_DIR_KEY, vers);

	result = RegOpenKeyEx(HKEY_LOCAL_MACHINE, path, 0, KEY_READ, &regKey);
	if (result != ERROR_SUCCESS) {
	    NpLog("Could not access registry \"%s\"\n", path);
	    return TCL_ERROR;
	}

	size = MAX_PATH;
	result = RegQueryValueEx(regKey, NULL, NULL, NULL, path, &size);
	RegCloseKey(regKey);
	if (result != ERROR_SUCCESS) {
	    NpLog("Could not access registry \"%s\" Default\n", TCL_REG_DIR_KEY);
	    return TCL_ERROR;
	}

	NpLog("Found current Tcl installation at \"%s\"\n", path);

	snprintf(libname, MAX_PATH, "%s\\bin\\%s", path, TCL_LIB_FILE);
	NpLog("Attempt to load Tcl dll (registry) '%s'\n", libname);
	handle = LoadLibrary(libname);
    }

    if (!handle) {
	NpLog("NpLoadLibrary: could not find dll '%s'\n", libname);
	return TCL_ERROR;
    }

    *tclHandle = handle;
    if (dllNameSize > 0) {
	/*
	 * Use GetModuleFileName to ensure that we have a fully-qualified
	 * path, no matter which route above succeeded.
	 */
	GetModuleFileNameA((HINSTANCE) tclHandle, dllName, dllNameSize);
    }
    return TCL_OK;
}
