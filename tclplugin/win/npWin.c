/* 
 * npWin.c --
 *
 * CONTACT:		tclplugin-core@lists.sourceforge.net
 *
 * Copyright (c) 2003 ActiveState Corporation.
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

/*
 * Default directory in which to look for Tcl/Tk libraries.  The
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

EXTERN int
NpLoadLibrary(HMODULE *tclHandle, HMODULE *tkHandle)
{
    char path[MAX_PATH], vers[MAX_PATH], libname[MAX_PATH];
    DWORD result, size = MAX_PATH;
    HKEY regKey;
    HMODULE hinst;
#define TCL_REG_DIR_KEY "Software\\ActiveState\\ActiveTcl"

    result = RegOpenKeyEx(HKEY_LOCAL_MACHINE, TCL_REG_DIR_KEY, 0,
	    KEY_READ, &regKey);
    if (result != ERROR_SUCCESS) {
	NpLog("Could not access registry \"%s\"\n",
		(int) TCL_REG_DIR_KEY, 0, 0);
	return TCL_ERROR;
    }

    result = RegQueryValueEx(regKey, "CurrentVersion", NULL, NULL,
	    vers, &size);
    RegCloseKey(regKey);
    if (result != ERROR_SUCCESS) {
	NpLog("Could not access registry \"%s\" CurrentVersion\n",
		(int) TCL_REG_DIR_KEY, 0, 0);
	return TCL_ERROR;
    }

    sprintf(path, "%s\\%s", TCL_REG_DIR_KEY, vers);

    result = RegOpenKeyEx(HKEY_LOCAL_MACHINE, path, 0, KEY_READ, &regKey);
    if (result != ERROR_SUCCESS) {
	NpLog("Could not access registry \"%s\"\n", (int) path, 0, 0);
	return TCL_ERROR;
    }

    size = MAX_PATH;
    result = RegQueryValueEx(regKey, NULL, NULL, NULL, path, &size);
    RegCloseKey(regKey);
    if (result != ERROR_SUCCESS) {
	NpLog("Could not access registry \"%s\" Default\n",
		(int) TCL_REG_DIR_KEY, 0, 0);
	return TCL_ERROR;
    }

    NpLog("Found current Tcl installation at \"%s\"\n", (int) path, 0, 0);

    sprintf(libname, "%s\\bin\\%s", path, TCL_LIB_FILE);
    hinst = LoadLibrary(libname);
    if (!hinst) {
	NpLog("NpLoadLibrary: could not find dll '%s'\n", (int) libname, 0, 0);
	return TCL_ERROR;
    }
    *tclHandle = hinst;

    sprintf(libname, "%s\\bin\\tk%s", path, TCL_LIB_FILE+3 /* skip 'tcl' */);
    hinst = LoadLibrary(libname);
    if (!hinst) {
	FreeLibrary(*tclHandle);
	*tclHandle = NULL;
	NpLog("NpLoadLibrary: could not find dll '%s'\n", (int) libname, 0, 0);
	return TCL_ERROR;
    }
    *tkHandle = hinst;

    return TCL_OK;
}
