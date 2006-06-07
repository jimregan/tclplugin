/* 
 * npwinplatform.c --
 *
 *	Routines that are called from the generic part and that are
 *	reimplemented differently for each platform.
 *
 * CONTACT:		tclplugin-core@lists.activestate.com
 *
 * ORIGINAL AUTHORS:	Jacob Levy			Laurent Demailly
 *
 * Copyright (c) 1995-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 * Copyright (c) 2002 ActiveState Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS:  @(#) $Id$
 */

#include <io.h>
#include <stdio.h>
#include <stdlib.h>
#include "np.h"

/*
 * The following messages are use to communicate between a Tk toplevel
 * and its container window.  Stolen from tk/win/tkWin.h.
 */

#define TK_CLAIMFOCUS	(WM_USER)
#define TK_GEOMETRYREQ	(WM_USER+1)
#define TK_ATTACHWINDOW	(WM_USER+2)
#define TK_DETACHWINDOW	(WM_USER+3)

TCL_DECLARE_MUTEX(windowMutex);

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

static LRESULT CALLBACK	ContainerProc _ANSI_ARGS_((HWND hwnd,
        		    UINT message, WPARAM wParam, LPARAM lParam));

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
NpPlatformMsg(CONST char *msg, char *title)
{
    NpLog("MSG [%s]: %s\n", title, msg);
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
    /*
     * We don't require special initialization.  The generic
     * package require plugin should work for us.
     */
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
    ContainerInfo *cPtr;
    HWND hwnd = (HWND) window->window;
    WNDPROC curProc;

    /*
     * Subclass the window only if it was not yet subclassed by us.
     */

    curProc = (WNDPROC) GetWindowLongPtr(hwnd, GWLP_WNDPROC);
    if (curProc == (WNDPROC) ContainerProc) {
        return;
    }

    for (cPtr = firstContainerPtr; cPtr != NULL; cPtr = cPtr->nextPtr) {
        if (cPtr->instance == instance) {
            break;
        }
    }

    if (cPtr == (ContainerInfo *) NULL) {
        cPtr = (ContainerInfo *) ckalloc(sizeof(ContainerInfo));
        cPtr->hwnd = hwnd;
        cPtr->instance = instance;
        cPtr->nextPtr = firstContainerPtr;
        cPtr->child = NULL;
        cPtr->oldProc = curProc;

        firstContainerPtr = cPtr;
    }

#if 1
    /*
     * NPP_SetWindow calls this - is this necessary?
     */
    Tcl_ServiceAll();
#endif
    (void) SetWindowLongPtr(hwnd, GWLP_WNDPROC, (LONG_PTR) ContainerProc);
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
    ContainerInfo *cPtr, *prevPtr;
    HWND hwnd;
    WNDPROC curProc;

    /*
     * Find the container.
     */

    for (prevPtr = (ContainerInfo *) NULL, cPtr = firstContainerPtr;
         cPtr != (ContainerInfo *) NULL;
         cPtr = cPtr->nextPtr) {
        if (cPtr->instance == instance) {
            break;
        }
        prevPtr = cPtr;
    }

    /*
     * If not found, do nothing.
     */

    if (cPtr == (ContainerInfo *) NULL) {
	NpLog("NpPlatformDestroy instance %p no hwnd found\n", instance);
        return;
    }

    /*
     * Remove the container info from the list.
     */

    if (prevPtr == (ContainerInfo *) NULL) {
        firstContainerPtr = cPtr->nextPtr;
    } else {
        prevPtr->nextPtr = cPtr->nextPtr;
    }

    /*
     * Unsubclass only if the current window proc is what we installed.
     */

    hwnd = cPtr->hwnd;
    curProc = (WNDPROC) GetWindowLongPtr(hwnd, GWLP_WNDPROC);
    if (curProc == (WNDPROC) ContainerProc) {
	(void) SetWindowLongPtr(hwnd, GWLP_WNDPROC, (LONG_PTR) cPtr->oldProc);
    } else {
	NpLog("NpPlatformDestroy: "
		"SetWindowLong(%p, WNDPROC, %p) not called (%p != %p)\n",
		hwnd, cPtr->oldProc, curProc, ContainerProc);
    }

    NpLog("NpPlatformDestroy instance %p hwnd %p\n", instance, hwnd);

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

    NpLog("CONTAINERPROC message 0x%x wParam 0x%x hwnd %p\n",
	    message, wParam, hwnd);

    for (ptr = firstContainerPtr; ptr != NULL; ptr = ptr->nextPtr) {
	if (ptr->hwnd == hwnd) {
	    break;
	}
	prevPtr = ptr;
    }

    if (!ptr) {
	/*
	 * This used to be a panic condition, but it was changed to call
	 * DefWindowProc.  The panics occured after moving to AT 8.4.11.2
	 * (threaded), so this may need further examination (possible
	 * threading bug, possibly always OK to pass to DefWindowProc).
	 */
        NpLog("ContainerProc: hwnd %p not recognized - pass to DefWindowProc",
		hwnd);

	return DefWindowProc(hwnd, message, wParam, lParam);
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

	case WM_PAINT: {
	    /*
	     * Mozilla/Firefox doesn't propagate the WM_PAINT requests to us,
	     * so catch them and trigger the ERASEBKGND.
	     * This isn't needed for IE, but doesn't bother it either.
	     */
	    PAINTSTRUCT ps;
	    BeginPaint(hwnd, &ps);
	    EndPaint(hwnd, &ps);
	    break;
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
	    SetWindowLongPtr(hwnd, GWLP_WNDPROC, (LONG_PTR) oldProc);
	    ckfree((char*) ptr);
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
NpPlatformNew(NPP instance)
{
    instance->pdata = (void *) GetCurrentThreadId();
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
