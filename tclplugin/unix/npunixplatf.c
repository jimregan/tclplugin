/* 
 * npunixplatform.c --
 *
 *	Platform specific routines: Unix version.
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
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npunixplatf.c 1.39 98/01/06 13:23:11
 */

#include	"np.h"
#include	"npxt.h"

/*
 * Constant for buffer size:
 */

#define BUFMAXLEN 512

/*
 * Static functions used in this file:
 */

static void	DestroyEventHandler _ANSI_ARGS_((Widget widget,
	            XtPointer clientData, XEvent *event,
	            Boolean *continueDispatchPtr));
static void	EnterEventHandler _ANSI_ARGS_((Widget widget,
	            XtPointer clientData, XEvent *event,
	            Boolean *continueDispatchPtr));
static Window	GetChild _ANSI_ARGS_((XEnterWindowEvent *enterEventPtr));

static void StartNotifier _ANSI_ARGS_((NPP instance));


/*
 *----------------------------------------------------------------------
 *
 * NpPlatformMsg --
 *
 *	Display a message to the user of the plugin.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Displays a message.
 *
 *----------------------------------------------------------------------
 */

void
NpPlatformMsg(char *msg, char *title)
{
    NpLog("%s: %s\n", (int) title, (int) msg, 0);
    fprintf(stderr, "%s: %s\n", title, msg);
}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformInit --
 *
 *	Initialize the plugin script running inside the plugin Tcl
 *	interpreter.
 *
 * Results:
 *	A standard Tcl result.
 *
 * Side effects:
 *	Whatever the script does.
 *
 *----------------------------------------------------------------------
 */

int
NpPlatformInit(interp, inBrowser)
    Tcl_Interp *interp;
    int inBrowser;
{
    static char initScript[]=
"if {[info exists plugin(library)]} return\n\
proc PlugChkDir {dir} {\n\
    global plugin\n\
    set d [file join $dir tclplug $plugin(version) plugin]\n\
#   puts \"trying \\\"$d\\\" [info level 1]\"\n\
    if {[file isdirectory $d]} {\n\
      set plugin(library) $d\n\
      return 1\n\
    } else {\n\
      return 0\n\
    }\n\
}\n\
# candidates\n\
# TCL_PLUGIN_DIR is special, it ought to work...\n\
if {[info exists env(TCL_PLUGIN_DIR)]} {\n\
    if {[string compare tclplug [file tail $env(TCL_PLUGIN_DIR)]] != 0} {\n\
       puts stderr \"Warning: TCL_PLUGIN_DIR=\\\"$env(TCL_PLUGIN_DIR)\\\"\\\n\
		should end with \\\"tclplug\\\"\"\n\
    }\n\
    if {[PlugChkDir [file dirname $env(TCL_PLUGIN_DIR)]]} {\n\
       rename PlugChkDir {}\n\
       return\n\
    } else {\n\
       puts stderr \"Warning: TCL_PLUGIN_DIR=\\\"$env(TCL_PLUGIN_DIR)\\\"\\\n\
		is invalid, value ignored\"\n\
    }\n\
}\n\
if {[info exists env(NPX_PLUGIN_PATH)]} {\n\
  foreach dir [split $env(NPX_PLUGIN_PATH) :] {\n\
    lappend dirlist [file dirname $dir]\n\
  }\n\
}\n\
lappend dirlist ~/.netscape\n\
if {[info exists env(MOZILLA_HOME)]} {\n\
    lappend dirlist $env(MOZILLA_HOME)\n\
}\n\
lappend dirlist /usr/local/lib/netscape\n\
lappend dirlist /usr/local/netscape\n\
lappend dirlist /opt/netscape\n\
#lappend dirlist [file dirname [file dirname [info nameofexecutable]]]\n\
#lappend dirlist [pwd]\n\
# actual checking\n\
foreach dir $dirlist {\n\
    if {[PlugChkDir $dir]} {\n\
        unset dir dirlist\n\
        rename PlugChkDir {}\n\
        return\n\
    }\n\
}\n\
unset dir\n\
return -code error \"Could not find tclplug/$plugin(version)/plugin\\\n\
      directory in TCL_PLUGIN_DIR nor any of those candidates : $dirlist\"\n\
";

    if (inBrowser) {
	/*
	 * Start the notifier, Netscape is nice enough to return the
	 * correct appContext even when we pass NULL as the instance.
	 * (Which is what we need as we don't yet have an instance but we
	 *  still need to enter our event processing)
	 */
    
	StartNotifier(NULL);
    }
 
    return Tcl_Eval(interp, initScript);

}

/*
 *----------------------------------------------------------------------
 *
 * DestroyEventHandler --
 *
 *	Callback invoked by the Xt Toolkit library when a child is
 *	destroyed.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Removes all registered handlers for this widget.
 *
 *----------------------------------------------------------------------
 */

static void
DestroyEventHandler(Widget widget, XtPointer clientData, XEvent *e,
        Boolean *continueDispatchPtr)
{
    XDestroyWindowEvent *devPtr;
    
    if (continueDispatchPtr != (Boolean *) NULL) {
        *continueDispatchPtr = FALSE;
    }
    if (e->type == DestroyNotify) {
        devPtr = (XDestroyWindowEvent *) e;
        XtRemoveEventHandler(widget, EnterWindowMask | LeaveWindowMask,
                FALSE, (XtEventHandler) EnterEventHandler,
                (XtPointer) devPtr->window);
        XtRemoveEventHandler(widget, SubstructureNotifyMask, FALSE,
                (XtEventHandler) DestroyEventHandler, (XtPointer) NULL);
    }
}

/*
 *----------------------------------------------------------------------
 *
 * GetChild --
 *
 *      Search for the appropriate child to give focus to.
 *      This should not be necessary as the emmbeded window should
 *      get the focus when we set it to the emmbeding window, but
 *      this is not yet working and thus this work around.
 *      (Which would fail if there were 2 children)
 *
 * Results:
 *	X Window or NULL when not found.
 *
 * Side effects:
 *      None.
 *
 *----------------------------------------------------------------------
 */

static Window
GetChild(enterEventPtr) 
    XEnterWindowEvent *enterEventPtr;
{
    Window subwindow = (Window) NULL;

    if (enterEventPtr->subwindow != (Window) NULL) {
	subwindow = enterEventPtr->subwindow;
    } else {
	Window parent;
	Window root;
	Window *children;
	unsigned int nchildren;

	if (XQueryTree(enterEventPtr->display,
		enterEventPtr->window, &root, &parent,
		&children, &nchildren) != 0) {
	    if (nchildren > 0) {
		subwindow = children[0];
		XFree((void *) children);
	    }
	}
    }

    return subwindow;
}

/*
 *----------------------------------------------------------------------
 *
 * EnterEventHandler --
 *
 *	Callback invoked by the X Toolkit library when the mouse pointer
 *	enters the Navigator window. If the focus detail is 1, set the
 *	focus on the '.' window of the Tk application in the interpreter
 *	that is passed as the second argument.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Sends the event to the Tk application in the interpreter passed
 *	as the second argument.
 *
 *----------------------------------------------------------------------
 */

	/* ARGSUSED */
static void
EnterEventHandler(Widget widget, XtPointer clientData, XEvent *e,
                  Boolean *continueDispatchPtr)
{
    XEnterWindowEvent *enterEventPtr;
    XLeaveWindowEvent *leaveEventPtr;
    
    /*
     * Let our caller know that we handled the event and it should not
     * dispatch it to other handlers.
     */
    
    if (continueDispatchPtr != (Boolean *) NULL) {
        *continueDispatchPtr = FALSE;
    }

    /*
     * Now dispatch on the event:
     */
        

    if (e->type == EnterNotify) {
        enterEventPtr = (XEnterWindowEvent *) e;
        switch (enterEventPtr->detail) {
            case NotifyAncestor:
                /*
                 * We are entering an empty part of the container window.
                 */
                
                break;
            case NotifyVirtual:
            case NotifyNonlinearVirtual:
                /*
                 * We are crossing from outside the container into our
                 * child window. We set the focus on the child window.
                 */
                XSetInputFocus(enterEventPtr->display,
			GetChild((XEnterWindowEvent *) e),
                        RevertToParent, CurrentTime);
                break;
            case NotifyInferior:
                /*
                 * We left the child to enter an empty part of the container.
                 * We return the focus back to the container application.
                 */

                XSetInputFocus(enterEventPtr->display, enterEventPtr->root,
                        RevertToParent, CurrentTime);
                break;
            case NotifyNonlinear:
                /*
                 * We do not do anything in this case.
                 */
                
                break;
            default:
                NpPanic("Unknown detail in enter event");
        }
    } else if (e->type == LeaveNotify) {
        leaveEventPtr = (XLeaveWindowEvent *) e; 
        switch (leaveEventPtr->detail) {
            case NotifyAncestor:
                /*
                 * We are leaving from an empty part of the container to
                 * the container. We have nothing to do here.
                 */

                break;
            case NotifyVirtual:
            case NotifyNonlinearVirtual:
                /*
                 * We are crossing from a child to outside the container.
                 * We return the focus back to the container application.
                 */

                XSetInputFocus(leaveEventPtr->display, leaveEventPtr->root,
                        RevertToParent, CurrentTime);
                break;
            case NotifyInferior:
                /*
                 * We are leaving an empty area of the container to the
                 * child window. We set the focus into the child.
                 */

                XSetInputFocus(leaveEventPtr->display,
                        GetChild((XEnterWindowEvent *) e),
			RevertToParent, CurrentTime);
                break;
            case NotifyNonlinear:
                /*
                 * We do nothing in this case.
                 */

                break;
          default:
                NpPanic("Unknown detail in leave event");
        }
    } else {
        NpPanic("Unknown event type in EnterEventHandler");
    }
}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformSetWindow --
 *
 *	Make sure that the embeding will work by registering handlers for
 *      the given window.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Set up handlers to propagate the focus into a Tk application,
 *      from outside.
 *
 *----------------------------------------------------------------------
 */

void
NpPlatformSetWindow(NPP This, NPWindow *npwindow)
{
    Window window;		/* The X11 window. */
    Display *display;		/* The X11 display. */
    Widget widget;		/* The Netscape Xt widget. */

    window = (Window) npwindow->window;
    display = ((NPSetWindowCallbackStruct *)npwindow->ws_info)->display;

    /*
     * Make sure that the window will exist when we'll try to load Tk
     * into it.
     */
    XFlush(display);

    widget = XtWindowToWidget(display, window);

    /*
     * Store the display for the XSynch at Destroy time
     */
    This->pdata = (void *) display;
    
    /*
     * We should check that we have not already registered those callbacks
     */

    if (widget != (Widget) NULL) {
        XtAddEventHandler(widget, EnterWindowMask | LeaveWindowMask, FALSE,
                (XtEventHandler) EnterEventHandler, (XtPointer) window);
        XtAddEventHandler(widget, SubstructureNotifyMask, FALSE,
                (XtEventHandler) DestroyEventHandler, (XtPointer) NULL);
    }
}

/*
 *----------------------------------------------------------------------
 *
 * NpDestroy --
 *
 *	Forgets the association between this instance pointer and
 *	a container window.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Syncs the X display so that the window is guaranteed to be
 *	destroyed before the call returns. (?)
 *
 *----------------------------------------------------------------------
 */

	/* ARGSUSED */
void
NpPlatformDestroy(This)
    NPP This;
{
    if (This->pdata == NULL) {
        NpLog("NpPlatformForgetContainer: no display to XSync on\n", 0, 0, 0);
        return;
    }
    XSync((Display *) This->pdata, FALSE);
}

/*
 *----------------------------------------------------------------------
 *
 * StartNotifier --
 *
 *	Links Tk with the external event loop of the containing
 *	application.
 *
 * Results:
 *	A standard Tcl result.
 *
 * Side effects:
 *	Tells Tk about the container application context.
 *
 *----------------------------------------------------------------------
 */

void
StartNotifier(instance)
    NPP instance;
{
    int i=0;
    XtAppContext appContext = NULL;

    /*
     * We can be called with a NULL instance, hopefully we do get
     * the appContext from Netscape even when passing NULL.
     */

    i = NPN_GetValue(instance , NPNVxtAppContext, &appContext);

    NpLog("StartNotifier %p : appContext %d : %p\n", (int) instance, i ,
	    (int) appContext);

    /*
     * We should always see the same context, otherwise we will panic
     */

     NpPlatformSetAppContext(appContext, 0);

}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformNew --
 *
 *	Unix specific code to do for each instance: attach the notifier
 *      to This context
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
    StartNotifier(This);
}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformShutdown --
 *
 *	Unlinks the Tk notifier from the external event loop.
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
    NpXtStopNotifier();
}
