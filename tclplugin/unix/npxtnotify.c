/* 
 * npxtnotify.c --
 *
 *	This file contains the notifier driver implementation for the
 *	Xt intrinsics.
 *
 * Copyright (c) 1997 by Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npxtnotify.c 1.25 98/01/06 13:23:32
 * RCS:  @(#) $Id$
 */

#include <tclInt.h>
#include "np.h"
#include "npxt.h"

static int count = 0 ;

/*
 * This structure is used to keep track of the notifier info for a 
 * a registered file.
 */

typedef struct FileHandler {
    int fd;
    int mask;			/* Mask of desired events: TCL_READABLE, etc. */
    int readyMask;		/* Events that have been seen since the
				   last time FileHandlerEventProc was called
				   for this file. */
    XtInputId read;		/* Xt read callback handle. */
    XtInputId write;		/* Xt write callback handle. */
    XtInputId except;		/* Xt exception callback handle. */
    Tcl_FileProc *proc;		/* Procedure to call, in the style of
				 * Tcl_CreateFileHandler. */
    ClientData clientData;	/* Argument to pass to proc. */
    struct FileHandler *nextPtr;/* Next in list of all files we care about. */
} FileHandler;

/*
 * The following structure is what is added to the Tcl event queue when
 * file handlers are ready to fire.
 */

typedef struct FileHandlerEvent {
    Tcl_Event header;		/* Information that is standard for
				 * all events. */
    int fd;			/* File descriptor that is ready.  Used
				 * to find the FileHandler structure for
				 * the file (can't point directly to the
				 * FileHandler structure because it could
				 * go away while the event is queued). */
} FileHandlerEvent;

/*
 * The following static structure contains the state information for the
 * Xt based implementation of the Tcl notifier.
 */

static struct NotifierState {
    XtAppContext appContext;		/* The context used by the Xt
                                         * notifier. Can be set with
                                         * NpSetAppContext. */
    int appContextCreated;		/* Was it created by us? */
    XtIntervalId currentTimeout;	/* Handle of current timer. */
    FileHandler *firstFileHandlerPtr;	/* Pointer to head of file handler
					 * list. */
    XtInputMask inputMask;              /* Input mask to use */
} notifier;

/*
 * The following static indicates whether this module has been initialized.
 */

static int initialized = 0;

/*
 * Static routines defined in this file.
 */

static int		FileHandlerEventProc _ANSI_ARGS_((Tcl_Event *evPtr,
			    int flags));
static void		FileProc _ANSI_ARGS_((XtPointer clientData,
			    int *source, XtInputId *id));
static void		InitNotifier _ANSI_ARGS_((void));
static void		TimerProc _ANSI_ARGS_((XtPointer clientData,
			    XtIntervalId *id));
static void		SetTimer _ANSI_ARGS_((Tcl_Time *timePtr));
static void		CreateFileHandler _ANSI_ARGS_((int fd,
			    int mask, Tcl_FileProc *proc, ClientData clientData));
static void		DeleteFileHandler _ANSI_ARGS_((int fd));
static int		WaitForEvent _ANSI_ARGS_((Tcl_Time *timePtr));

static Tcl_NotifierProcs procs = {
    SetTimer,
    WaitForEvent,
    CreateFileHandler,
    DeleteFileHandler
};


/*
 *----------------------------------------------------------------------
 *
 * NpPlatformSetAppContext --
 *
 *	Set the notifier application context and set the inputMask.
 *      If inputMask is set to 0, will keep the default one (XtIMAll).
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Sets the application context used by the notifier. Panics if
 *	one try to change an existing context. May initialize the notifier
 *	on demand.
 *
 *----------------------------------------------------------------------
 */

XtAppContext
NpPlatformSetAppContext(appContext, inputMask)
    XtAppContext	appContext;
    XtInputMask         inputMask;
{
    /*
     * Initialize the notifier if needed:
     */
    
    if (!initialized) {
        InitNotifier();
    }

    /*
     * Remember the desired inputMask
     */

    if (inputMask) {
	notifier.inputMask = inputMask;
    }

    /*
     * If we already have a context we check whether we were asked to set a
     * different new context. If so, we panic because we try to prevent
     * switching contexts by mistake. Otherwise, we return the one we have.
     */

    if (notifier.appContext != NULL) {
        if ((appContext != NULL) && (appContext != notifier.appContext)) {

	    /*
             * We already have a context. We do not allow switching to a
	     * different new context after initialization, so we panic.
             */
        
            NpPanic("NpPlatformSetAppContext: multiple application contexts.");
        }
    } else {

        /*
         * If we get here we have not yet gotten a context, so either create
         * one or use the one supplied by our caller.
         */

        if (appContext == NULL) {

            /*
             * If we are in exit handling and trying to recreate an
             * appContext, we have been de-initialized and do not want
             * to be re-initialized, so we panic here:
             */

            if (TclInExit()) {
                NpPanic("NpPlatformSetAppContext: reinit appContext in exit.");
            }
            
	    /*
             * We must create a new context and tell our caller what it is, so
             * she can use it too.
             */
    
            notifier.appContext = XtCreateApplicationContext();
            notifier.appContextCreated = 1;
	    NpLog("%d: NpPlatformSetAppContext CREATED new app context %p\n",
                  getpid(), appContext);
        } else {

	    /*
             * Otherwise we remember the context that our caller gave us
             * and use it.
             */
    
            notifier.appContextCreated = 0;
            notifier.appContext = appContext;

	    NpLog("%d: NpPlatformSetAppContext SET app context to %p\n",
                  getpid(), appContext);
        }
    }
    
    return notifier.appContext;
}

/*
 *----------------------------------------------------------------------
 *
 * InitNotifier --
 *
 *	Initializes the notifier state.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Creates a new exit handler.
 *
 *----------------------------------------------------------------------
 */

static void
InitNotifier(void)
{
    /*
     * Only reinitialize if we are not in exit handling. The notifier
     * can get reinitialized after its own exit handler has run, because
     * of exit handlers for the I/O and timer sub-systems (order dependency).
     */
    NpLog("Called InitNotifier\n");

    if (TclInExit()) {
	NpLog("In Exit so no init\n");
	return;
    }
    if (count !=0) {
	NpLog("Warning: Invalid stack count %d\n", count);
	count =0 ;
    }

    /*
     * DO NOT create the application context yet; doing so would prevent
     * external applications from setting it for us to their own ones.
     */
    
    initialized = 1;

    Tcl_SetNotifier(&procs);

    memset(&notifier, 0, sizeof(notifier));

    /*
     * Default value for input mask : process all events.
     */

    notifier.inputMask = XtIMAll;
}

/*
 *----------------------------------------------------------------------
 *
 * NpXtStopNotifier --
 *
 *	This function is called to cleanup the notifier state before
 *	Tcl is unloaded.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Shuts down the Xt notifier, removes timers and filehandlers.
 *
 *----------------------------------------------------------------------
 */

void
NpXtStopNotifier()
{
    NpLog("entering NpXtStopNotifier\n");
    if (count !=0) {
	NpLog("ERROR: Invalid notifier stack count %d\n", count);
    }
    if (notifier.currentTimeout != 0) {
        XtRemoveTimeOut(notifier.currentTimeout);
    }
    for (; notifier.firstFileHandlerPtr != NULL; ) {
        DeleteFileHandler(notifier.firstFileHandlerPtr->fd);
    }
    if (notifier.appContextCreated) {
        XtDestroyApplicationContext(notifier.appContext);
    }
    notifier.appContextCreated = 0;
    notifier.appContext = NULL;
    initialized = 0;

    NpLog("leaving NpXtStopNotifier\n");
}

/*
 *----------------------------------------------------------------------
 *
 * SetTimer --
 *
 *	This procedure sets the current notifier timeout value. When
 *	called with a NULL timeout, the procedure cancels any pending
 *	timeout and does not schedule a new one.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Replaces any previous timer.
 *
 *----------------------------------------------------------------------
 */

static void
SetTimer(timePtr)
    Tcl_Time *timePtr;		/* Timeout value, may be NULL. */
{
    long timeout;

    NpPlatformSetAppContext(NULL, 0);
    if (notifier.currentTimeout != 0) {
#ifdef	NP_DEBUG
        NpLog("Removing timeout id 0x%x\n", (int)notifier.currentTimeout);
#endif
	XtRemoveTimeOut(notifier.currentTimeout);
    }
    if (timePtr) {
        /*
         * A timeout was requested: schedule an Xt event after the requested
         * delay.
         */
        
	timeout = timePtr->sec * 1000 + timePtr->usec / 1000;
#ifdef	NP_DEBUG
        NpLog("before timer of %d msecs\n", timeout);
#endif
        notifier.currentTimeout =
            XtAppAddTimeOut(notifier.appContext, (unsigned long) timeout,
                    (XtTimerCallbackProc) TimerProc, NULL);
#ifdef	NP_DEBUG
        NpLog("after timer of %d msecs id 0x%x\n", timeout,
                (int) notifier.currentTimeout);
#endif
    } else {
        /*
         * No timeout was requested: schedule an Xt timer to make sure that
         * Tcl_ServiceAll will get called at the earliest possible time even
         * if no events have occurred.
         */
        
        notifier.currentTimeout = 0;
#ifdef	NP_DEBUG
        NpLog("called SetTimer with NULL timeout\n");
#endif
    }
}

/*
 *----------------------------------------------------------------------
 *
 * TimerProc --
 *
 *	This procedure is the XtTimerCallbackProc used to handle
 *	timeouts.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *      Processes all queued events.
 *
 *----------------------------------------------------------------------
 */

static void
TimerProc(data, id)
    XtPointer data;		/* Not used. */
    XtIntervalId *id;
{
#ifdef	NP_DEBUG
    NpLog("TimerProc called with %d 0x%x vs. 0x%x\n", data, *id,
            notifier.currentTimeout);
#endif
    if (*id != notifier.currentTimeout) {
	return;
    }
    notifier.currentTimeout = 0;

    Tcl_ServiceAll();
}

/*
 *----------------------------------------------------------------------
 *
 * CreateFileHandler --
 *
 *	This procedure registers a file handler with the Xt notifier.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Creates a new file handler structure and registers one or more
 *	input procedures with Xt.
 *
 *----------------------------------------------------------------------
 */

static void
CreateFileHandler(fd, mask, proc, clientData)
    int fd;			/* Handle of stream to watch. */
    int mask;			/* OR'ed combination of TCL_READABLE,
				 * TCL_WRITABLE, and TCL_EXCEPTION:
				 * indicates conditions under which
				 * proc should be called. */
    Tcl_FileProc *proc;		/* Procedure to call for each
				 * selected event. */
    ClientData clientData;	/* Arbitrary data to pass to proc. */
{
    FileHandler *filePtr;
#ifdef NP_DEBUG
    NpLog("CreateFileHandler %d\n", fd);
#endif

    NpPlatformSetAppContext(NULL, 0);

    for (filePtr = notifier.firstFileHandlerPtr; filePtr != NULL;
	    filePtr = filePtr->nextPtr) {
	if (filePtr->fd == fd) {
	    break;
	}
    }
    if (filePtr == NULL) {
	filePtr = (FileHandler*) ckalloc(sizeof(FileHandler));
	filePtr->fd = fd;
	filePtr->read = 0;
	filePtr->write = 0;
	filePtr->except = 0;
	filePtr->readyMask = 0;
	filePtr->mask = 0;
	filePtr->nextPtr = notifier.firstFileHandlerPtr;
	notifier.firstFileHandlerPtr = filePtr;
    }
    filePtr->proc = proc;
    filePtr->clientData = clientData;

    /*
     * Register the file with the Xt notifier, if it hasn't been done yet.
     */

    if (mask & TCL_READABLE) {
	if (!(filePtr->mask & TCL_READABLE)) {
	    filePtr->read =
                XtAppAddInput(notifier.appContext, fd,
                        (XtPointer) XtInputReadMask,
                        (XtInputCallbackProc) FileProc,
                        (XtPointer) filePtr);
	}
    } else {
	if (filePtr->mask & TCL_READABLE) {
	    XtRemoveInput(filePtr->read);
	}
    }
    if (mask & TCL_WRITABLE) {
	if (!(filePtr->mask & TCL_WRITABLE)) {
	    filePtr->write =
                XtAppAddInput(notifier.appContext, fd,
                        (XtPointer) XtInputWriteMask,
                        (XtInputCallbackProc) FileProc,
                        (XtPointer) filePtr);
	}
    } else {
	if (filePtr->mask & TCL_WRITABLE) {
	    XtRemoveInput(filePtr->write);
	}
    }
    if (mask & TCL_EXCEPTION) {
	if (!(filePtr->mask & TCL_EXCEPTION)) {
	    filePtr->except =
                XtAppAddInput(notifier.appContext, fd,
                        (XtPointer) XtInputExceptMask,
                        (XtInputCallbackProc) FileProc,
                        (XtPointer) filePtr);
	}
    } else {
	if (filePtr->mask & TCL_EXCEPTION) {
	    XtRemoveInput(filePtr->except);
	}
    }
    filePtr->mask = mask;
}

/*
 *----------------------------------------------------------------------
 *
 * DeleteFileHandler --
 *
 *	Cancel a previously-arranged callback arrangement for
 *	a file.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	If a callback was previously registered on file, remove it.
 *
 *----------------------------------------------------------------------
 */

static void
DeleteFileHandler(fd)
    int fd;			/* Stream id for which to remove
				 * callback procedure. */
{
    FileHandler *filePtr, *prevPtr;
#ifdef NP_DEBUG
    NpLog("DeleteFileHandler %d\n", fd);
#endif

    NpPlatformSetAppContext(NULL, 0);

    /*
     * Find the entry for the given file (and return if there
     * isn't one).
     */

    for (prevPtr = NULL, filePtr = notifier.firstFileHandlerPtr; ;
	    prevPtr = filePtr, filePtr = filePtr->nextPtr) {
#ifdef NP_DEBUG
	NpLog(".");
#endif
	if (filePtr == NULL) {
#ifdef NP_DEBUG
	    NpLog("-> not found\n");
#endif
	    return;
	}
	if (filePtr->fd == fd) {
	    break;
	}
    }
#ifdef NP_DEBUG
    NpLog("-> found\n");
#endif

    /*
     * Clean up information in the callback record.
     */

    if (prevPtr == NULL) {
	notifier.firstFileHandlerPtr = filePtr->nextPtr;
    } else {
	prevPtr->nextPtr = filePtr->nextPtr;
    }
    if (filePtr->mask & TCL_READABLE) {
	XtRemoveInput(filePtr->read);
    }
    if (filePtr->mask & TCL_WRITABLE) {
	XtRemoveInput(filePtr->write);
    }
    if (filePtr->mask & TCL_EXCEPTION) {
	XtRemoveInput(filePtr->except);
    }
    ckfree((char *) filePtr);
}

/*
 *----------------------------------------------------------------------
 *
 * FileProc --
 *
 *	These procedures are called by Xt when a file becomes readable,
 *	writable, or has an exception.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Makes an entry on the Tcl event queue if the event is
 *	interesting.
 *
 *----------------------------------------------------------------------
 */

static void
FileProc(clientData, fd, id)
    XtPointer clientData;
    int *fd;
    XtInputId *id;
{
    FileHandler *filePtr = (FileHandler *)clientData;
    FileHandlerEvent *fileEvPtr;
    int mask = 0;

#ifdef NP_DEBUG
    NpLog("Notifier: FileProc %d %d\n", filePtr->fd, *fd);
#endif

    /*
     * Determine which event happened.
     */

    if (*id == filePtr->read) {
	mask = TCL_READABLE;
    } else if (*id == filePtr->write) {
	mask = TCL_WRITABLE;
    } else if (*id == filePtr->except) {
	mask = TCL_EXCEPTION;
    }

    /*
     * Ignore unwanted or duplicate events.
     */

    if (!(filePtr->mask & mask) || (filePtr->readyMask & mask)) {
	return;
    }
    
    /*
     * This is an interesting event, so put it onto the event queue.
     */

    filePtr->readyMask |= mask;
    fileEvPtr = (FileHandlerEvent *) ckalloc(sizeof(FileHandlerEvent));
    fileEvPtr->header.proc = FileHandlerEventProc;
    fileEvPtr->fd = filePtr->fd;
    Tcl_QueueEvent((Tcl_Event *) fileEvPtr, TCL_QUEUE_TAIL);

    /*
     * Process events on the Tcl event queue before returning to Xt.
     */

    Tcl_ServiceAll();
}

/*
 *----------------------------------------------------------------------
 *
 * FileHandlerEventProc --
 *
 *	This procedure is called by Tcl_ServiceEvent when a file event
 *	reaches the front of the event queue.  This procedure is
 *	responsible for actually handling the event by invoking the
 *	callback for the file handler.
 *
 * Results:
 *	Returns 1 if the event was handled, meaning it should be removed
 *	from the queue.  Returns 0 if the event was not handled, meaning
 *	it should stay on the queue.  The only time the event isn't
 *	handled is if the TCL_FILE_EVENTS flag bit isn't set.
 *
 * Side effects:
 *	Whatever the file handler's callback procedure does.
 *
 *----------------------------------------------------------------------
 */

static int
FileHandlerEventProc(evPtr, flags)
    Tcl_Event *evPtr;		/* Event to service. */
    int flags;			/* Flags that indicate what events to
				 * handle, such as TCL_FILE_EVENTS. */
{
    FileHandler *filePtr;
    FileHandlerEvent *fileEvPtr = (FileHandlerEvent *) evPtr;
    int mask;

#ifdef NP_DEBUG
    NpLog("FileHandlerEventProc %d\n", fileEvPtr->fd);
#endif

    if (!(flags & TCL_FILE_EVENTS)) {
	return 0;
    }

    /*
     * Search through the file handlers to find the one whose handle matches
     * the event.  We do this rather than keeping a pointer to the file
     * handler directly in the event, so that the handler can be deleted
     * while the event is queued without leaving a dangling pointer.
     */

    for (filePtr = notifier.firstFileHandlerPtr; filePtr != NULL;
	    filePtr = filePtr->nextPtr) {
	if (filePtr->fd != fileEvPtr->fd) {
	    continue;
	}

	/*
	 * The code is tricky for two reasons:
	 * 1. The file handler's desired events could have changed
	 *    since the time when the event was queued, so AND the
	 *    ready mask with the desired mask.
	 * 2. The file could have been closed and re-opened since
	 *    the time when the event was queued.  This is why the
	 *    ready mask is stored in the file handler rather than
	 *    the queued event:  it will be zeroed when a new
	 *    file handler is created for the newly opened file.
	 */

	mask = filePtr->readyMask & filePtr->mask;
	filePtr->readyMask = 0;
	if (mask != 0) {
	    (*filePtr->proc)(filePtr->clientData, mask);
	}
	break;
    }
    return 1;
}

/*
 *----------------------------------------------------------------------
 *
 * WaitForEvent --
 *
 *	This function is called by Tcl_DoOneEvent to wait for new
 *	events on the message queue.  If the block time is 0, then
 *	Tcl_WaitForEvent just polls without blocking.
 *
 * Results:
 *	Returns 1 if an event was found, else 0.  This ensures that
 *	Tcl_DoOneEvent will return 1, even if the event is handled
 *	by non-Tcl code.
 *
 * Side effects:
 *	Queues file events that are detected by the select.
 *
 *----------------------------------------------------------------------
 */

static int
WaitForEvent(
    Tcl_Time *timePtr)		/* Maximum block time, or NULL. */
{
    int timeout;
    
#ifdef NP_DEBUG
    NpLog("entering WaitForEvent\n");
#endif

    NpPlatformSetAppContext(NULL, 0);

    if (timePtr) {
        timeout = timePtr->sec * 1000 + timePtr->usec / 1000;
        if (timeout == 0) {
            SetTimer(NULL);
            if (XtAppPending(notifier.appContext)) {
                goto process;
            } else {
                return 0;
            }
        } else {
            SetTimer(timePtr);
        }
    }
process:
    count ++;
#ifdef NP_DEBUG
    NpLog("entering XtAppProcessEvent %p %d (%d)\n",
	    notifier.appContext, notifier.inputMask, count);
#endif
    XtAppProcessEvent(notifier.appContext, notifier.inputMask);
#ifdef NP_DEBUG
    NpLog("exiting  XtAppProcessEvent %p %d (%d)\n",
	    notifier.appContext, notifier.inputMask, count);
#endif
    count --;

    return 1;
}
