/* 
 * npwinplatform.c --
 *
 *	Routines that are called from the generic part and that are
 *	reimplemented differently for each platform.
 *
 * CONTACT:		sunscript-plugin@sunscript.sun.com
 *
 * AUTHORS:		Jacob Levy			Laurent Demailly
 *			jyl@eng.sun.com			demailly@eng.sun.com
 *			jyl@tcl-tk.com			L@demailly.com
 *
 * Please contact us directly for questions, comments and enhancements.
 *
 * Copyright (c) 1995-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npWinPlatform.c 1.24 96/12/31 15:22:21
 * RCS:  @(#) $Id$
 */

#include	<stdio.h>
#include	<stdlib.h>
#include	<tkWin.h>
#include	"np.h"

/*
 * Constant for buffer size:
 */

#define BUFMAXLEN 512

typedef struct ContainerInfo {
    NPP instance;
    WNDPROC oldProc;
    HWND hwnd;
    HWND child;
    struct ContainerInfo *nextPtr;
} ContainerInfo;

static ContainerInfo *firstContainerPtr = NULL;

/*
 * Static functions in this file:
 */

static LRESULT CALLBACK		ContainerProc _ANSI_ARGS_((HWND hwnd,
        			    UINT message, WPARAM wParam,
        			    LPARAM lParam));

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformMsg --
 *
 *	Display a message to the user.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

void
NpPlatformMsg(char *msg, char *title)
{
    MessageBox(NULL, msg, title, MB_OK);
}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformInit --
 *
 *	Performs platform specific initialization. Looks up the
 *	directory for the plugin library in the registry, and computes
 *	values for the Tcl variables tcl_library and tk_library based
 *	on the registry key value.
 *
 * Results:
 *	A standard Tcl result.
 *
 * Side effects:
 *	Sets Tcl variables in the interpreter passed as an argument.
 *
 *----------------------------------------------------------------------
 */

int
NpPlatformInit(Tcl_Interp *interp, int inBrowser)
{
    char tmpBuf[BUFMAXLEN];
    char *ptr;
    OSVERSIONINFO osInfo;
    DWORD result;
    HKEY regKey;
    int isWin32s;		/* True if we are running under Win32s. */
    Tcl_DString ds;
    long size = MAX_PATH;

    Tcl_DStringInit(&ds);
    
    /*
     * First look in the environment for the TCL_PLUGIN_DIR entry.
     */

    ptr = getenv(TCL_PLUGIN_DIR);    
    if (ptr != NULL) {
        sprintf(tmpBuf, "%*.s\\%s\\plugin", BUFMAXLEN, ptr, NPTCL_VERSION);
        if (access(ptr, 0) != 0) {
            ptr = (char *) NULL;
        } else {
            ptr = (char *) ckalloc(strlen(tmpBuf) + 1);
            strcpy(ptr, tmpBuf);
        }
    }

    /*
     * If not found, look in the registry for where to find the
     * plugin library files.
     */
    
    if (ptr == NULL) {

	/*
         * Find out what kind of system we are running on.
         */

        osInfo.dwOSVersionInfoSize = sizeof(OSVERSIONINFO);
        GetVersionEx(&osInfo);

        isWin32s = (osInfo.dwPlatformId == VER_PLATFORM_WIN32s);

	/*
	 * Open the registry and look for the TCL_PLUGIN_DIR_KEY key. Note that
	 * Windows 3.1 only supports HKEY_CLASSES_ROOT and single valued
	 * keys.
	 */

	if (isWin32s) {
	    result =
                RegOpenKey(HKEY_CLASSES_ROOT, TCL_PLUGIN_DIR_KEY, &regKey);
            if (result != ERROR_SUCCESS) {
                Tcl_AppendResult(interp, "The Tcl Plugin appears to not be",
                        " installed properly. Please check your registry.",
                        " It should have a key HKEY_CURRENT_USER\\",
                        TCL_PLUGIN_DIR_KEY,
                        " but I didn't find such a key.",
                        (char *) NULL);
                return TCL_ERROR;
            }
	    Tcl_DStringSetLength(&ds, MAX_PATH);
	    result = RegQueryValue(regKey, "Directory", Tcl_DStringValue(&ds),
                    &size);
	} else {
	    result = RegOpenKeyEx(HKEY_LOCAL_MACHINE, TCL_PLUGIN_DIR_KEY, 0,
		KEY_READ, &regKey);
            if (result != ERROR_SUCCESS) {
                Tcl_AppendResult(interp, "The Tcl Plugin appears to not be",
                        " installed properly. Please check your registry.",
                        " It should have a key HKEY_LOCAL_MACHINE\\",
                        TCL_PLUGIN_DIR_KEY,
                        " but I didn't find such a key.",
                        (char *) NULL);
                return TCL_ERROR;
            }
	    Tcl_DStringSetLength(&ds, MAX_PATH);
	    result = RegQueryValueEx(regKey, "Directory", NULL, NULL,
		Tcl_DStringValue(&ds), (DWORD*)&size);
	}

	if (result == ERROR_SUCCESS) {
	    RegCloseKey(regKey);
	    Tcl_DStringSetLength(&ds, size);
            ptr = Tcl_DStringValue(&ds);

            /*
             * See if the registered value that we found actually points
             * at an existing directory. If not, ignore the value.
             */
            
            if (access(ptr, 0) != 0) {
                ptr = (char *) NULL;
            }
	} else {
	    Tcl_DStringSetLength(&ds, 0);
            ptr = (char *) NULL;
	}
    }
              
    /*
     * If still not found, complain and abort the plugin initialization.
     */
    
    if (ptr == NULL) {
        Tcl_DStringFree(&ds);
        Tcl_AppendResult(interp,
                "could not find Tcl plugin library; please check that the",
                " plugin is properly installed",
                (char *) NULL);
        return TCL_ERROR;
    }

    /*
     * Copy the value into a temporary buffer because it may be pointing
     * at the DString buffer which we will free next.
     */

    sprintf(tmpBuf, "%s\\%s\\plugin", ptr, NPTCL_VERSION);
    Tcl_DStringFree(&ds);

    /*
     * Now store the value we found.
     */
    
    if (Tcl_SetVar2(interp, "plugin", "library", tmpBuf,
	    TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG)
            == NULL) {
	return TCL_ERROR;
    }
    return TCL_OK;
}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformSetWindow --
 *
 *	This function subclasses the netscape container window and
 *	stores a pointer to the instance data in the window. 
 *
 * Results:
 *	1 if success, 0 otherwise.
 *
 * Side effects:
 *	Subclasses the netscape window.
 *
 *----------------------------------------------------------------------
 */

void
NpPlatformSetWindow(NPP instance, NPWindow *window)
{
    ContainerInfo *cptr;
    HWND hwnd = (HWND) window->window;
    WNDPROC curProc;
    
    /*
     * Subclass the window only if it was not yet subclassed by us.
     */
    
    curProc = (WNDPROC) GetWindowLong(hwnd, GWL_WNDPROC);
    if (curProc == (WNDPROC) ContainerProc) {
        return;
    }

    for (cptr = firstContainerPtr; cptr != NULL; cptr = cptr->nextPtr) {
        if (cptr->instance == instance) {
            break;
        }
    }

    if (cptr == (ContainerInfo *) NULL) {
        cptr = (ContainerInfo *) ckalloc(sizeof(ContainerInfo));
        cptr->hwnd = hwnd;
        cptr->instance = instance;
        cptr->nextPtr = firstContainerPtr;
        cptr->child = NULL;
        cptr->oldProc = curProc;
        
        firstContainerPtr = cptr;
    }

    (void) SetWindowLong(hwnd, GWL_WNDPROC, (DWORD) ContainerProc);
}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformDestroy --
 *
 *	This function removes the subclassing of the Netscape container
 *	window.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Removes the subclassing from the Netscape window.
 *
 *----------------------------------------------------------------------
 */

void
NpPlatformDestroy(NPP instance)
{
    ContainerInfo *cPtr, *backPtr;
    HWND hwnd;
    WNDPROC curProc;

    /*
     * Find the container.
     */

    for (backPtr = (ContainerInfo *) NULL, cPtr = firstContainerPtr;
         cPtr != (ContainerInfo *) NULL;
         cPtr = cPtr->nextPtr) {
        if (cPtr->instance == instance) {
            break;
        }
        backPtr = cPtr;
    }

    /*
     * If not found, do nothing.
     */

    if (cPtr == (ContainerInfo *) NULL) {
        return;
    }
        
    /*
     * Remove the container info from the list.
     */

    if (backPtr == (ContainerInfo *) NULL) {
        firstContainerPtr = cPtr->nextPtr;
    } else {
        backPtr->nextPtr = cPtr->nextPtr;
    }

    /*
     * Unsubclass only if the current window proc is what we installed.
     */
    
    hwnd = cPtr->hwnd;
    curProc = (WNDPROC) GetWindowLong(hwnd, GWL_WNDPROC);
    if (curProc != (WNDPROC) ContainerProc) {
        ckfree((char *) cPtr);
        return;
    }
    
    (void) SetWindowLong(hwnd, GWL_WNDPROC, (DWORD) cPtr->oldProc);
    ckfree((char *) cPtr);
}

/*
 *----------------------------------------------------------------------
 *
 * ContainerProc --
 *
 *	This is the window procedure for the netscape container window.
 *	It watches for focus messages from netscape and container
 *	protocol messages from the embedded Tk window.
 *
 * Results:
 *	Standard WNDPROC return value.
 *
 * Side effects:
 *	May cause the embedded window to get/lose focus or change size.
 *
 *----------------------------------------------------------------------
 */

static LRESULT CALLBACK
ContainerProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    ContainerInfo *ptr, *prevPtr = NULL;
    WNDPROC oldProc;

    for (ptr = firstContainerPtr; ptr != NULL; ptr = ptr->nextPtr) {
	if (ptr->hwnd == hwnd) {
	    break;
	}
	prevPtr = ptr;
    }

    if (!ptr) {
        NpPanic("Container not found in ContainerProc");

        /* NOTREACHED */
        exit(99);
    }
    
    oldProc = ptr->oldProc;

    switch (message) {
	case TK_ATTACHWINDOW: {
	    RECT rect;
	    ptr->child = (HWND)wParam;
	    GetClientRect(hwnd, &rect);
	    MoveWindow(ptr->child, 0, 0, rect.right - rect.left,
		    rect.bottom - rect.top, TRUE);
	    return 0;
	}

	case TK_CLAIMFOCUS:
	    if (wParam || (GetFocus() != NULL)) {
		SetFocus(ptr->child);
	    }
	    return 0;

	case TK_GEOMETRYREQ: {
	    RECT rect;
	    GetClientRect(hwnd, &rect);
	    MoveWindow(ptr->child, 0, 0, rect.right - rect.left,
		    rect.bottom - rect.top, TRUE);
	    return 0;
	}

	case WM_PARENTNOTIFY: {
	    switch (LOWORD(wParam)) {
		case WM_LBUTTONDOWN:
		case WM_MBUTTONDOWN:
		case WM_RBUTTONDOWN:
		    SetFocus(ptr->child);
		    break;
	    }
	    return 0;
	}
	case WM_DESTROY:
	    if (prevPtr != NULL) {
		prevPtr->nextPtr = ptr->nextPtr;
	    } else {
		firstContainerPtr = ptr->nextPtr;
	    }
	    ckfree((char*)ptr);
	    SetWindowLong(hwnd, GWL_WNDPROC, (DWORD) oldProc);
	    break;
    }
    return CallWindowProc(oldProc, hwnd, message, wParam, lParam);
}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformNew --
 *
 *	Performs platform specific instance initialization:
 *      None on Windows
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

void
NpPlatformNew(This)
  NPP This;
{
}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformShutdown --
 *
 *	Performs platform specific shutdown (notifier stopping,...):
 *      None on Windows
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

void
NpPlatformShutdown()
{
}
