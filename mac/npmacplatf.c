/* 
 * npmacplatform.c --
 *
 *	Platform specific routines: Mac version.
 *
 * AUTHOR: Jim Ingham			jingham@eng.sun.com
 *
 * Please contact me directly for questions, comments and enhancements.
 *
 * Copyright (c) 1995 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npmacplatf.c 1.3 97/12/17 13:19:52
 * RCS:  @(#) $Id$
 */

#include "npmac.h"
#include <tclMacInt.h>
#include <tkMacInt.h>

#undef Status
#include <Dialogs.h>
#include <Fonts.h>
#include <Icons.h>
#include <Resources.h>
#include <QDOffscreen.h>
#include <Sound.h>
#include <Threads.h>

extern void FreeAllMemory();

/*
 * constants for panic dialog
 */
#define PANICHEIGHT 150				/* Height of dialog */
#define PANICWIDTH 350				/* Width of dialog */
#define PANIC_BUTTON_RECT {125, 260, 145, 335}	/* Rect for button. */
#define PANIC_ICON_RECT   {10, 20, 42, 52}	/* Rect for icon. */
#define PANIC_TEXT_RECT   {10, 65, 120, 330}	/* Rect for text. */
#define	ENTERCODE  (0x03)
#define	RETURNCODE (0x0D)

/*
 * This structure stores the information about each plugin.  We
 * store this in the pdata field of the NPP structure.
 */
 
typedef struct PluginInstance {
    NPP plugin;
    NPRect oldClip;
    NPWindow *npWin;
    Tk_Window tkWin;
} PluginInstance;
 
/*
 * Use a linked list that relates NPP pointers, their NPWindow structures &
 * the TkWindow pointer for that window.
 */

typedef struct PluginList {
    PluginInstance *data;
    struct PluginList *nextPlugin;
} PluginList;

/*
 * As each port is set up for drawing, it searches this list to see
 * if it has been registered, and if not, the drawing state is stored
 * here.  Then we restore all the windows on this list before we go 
 * back to Netscape.
 */

typedef struct SavedPort {
    CGrafPtr portPtr;             /* This is a pointer to the real Port we are saving */
    CGrafPort savedPort;          /* This is a fake port we use to store away info */
    int isSaved;                  /* If the port has been touched between calls to 
                                     SetUpPort, this will be 1 */
    struct SavedPort *nextSaved;  /* A pointer to the next saved port. */
} SavedPort;


/*
 * Globals
 */
 
/*
 * The following two variables are defined in the Netscape glue.
 */
 
extern QDGlobalsPtr	gQDPtr;	
extern short		gResFile; /* The ID of the plugin library's resource file */

/*
 * The following variables keep track of the currently loaded plugins.
 */

static SavedPort *gSavedPortList = NULL; /* This is a list with information about the  
                                            original state of the ports we have touched 
                                            between calls to npStartDraw & npEndDraw */

static PluginList *gPluginList = NULL;   /* This is the list of plugins */

/*
 * These are for managing the Tcl thread 
 */
 
static int initialized = 0;	/* Set when we have initialized the Tcl thread */
static int gDone = 0;		/* Set to 1 to tell the Tcl Thread to exit */
ThreadID gTclThread;            /* The ThreadID of the Tcl thread */
ThreadID gMainThread;            /* The ThreadID of the thread we started in */
static int gGotAnEvent = 0;         /* This is how the NPP_HandleEvent can tell 
                                   Tcl_WaitNextEvent an event has been found */
/*
 * These are used in Np_Eval to pass data between the main thread and the Tcl thread.
 */
 
static Tcl_Interp *gTclInterp;     /* This is the interp to eval in... */
static char *gTclScript = NULL;    /* This points to a script.  If it is not NULL, then
                                      the Tcl thread will Tcl_Eval this next time it
                                      is woken up */
static Tcl_Obj *gTclObjPtr = NULL; /* This has the same function for Tcl_EvalObj. */
static int  gTclResult;            /* This is used to pass the result between the Tcl 
                                      thread and the main thread. */
                                 
/*
 * Static functions used in this file:
 */

static pascal void	*NpMacRunThread(void *data);
static void 	InitTclThreadIfNeeded();
static void	NpMacRestoreDrawingEnv();
static void	NpMacSetupForDrawing(NPWindow *npWin);
static void	NPToMacRect(NPRect *npRect,Rect *macRect);

static void 	myPostDialog(char *message);

static void 	NpMacUpdateWindows(); 

/*
 * These are the functions handed off the the embedding code
 */
 
static GWorldPtr NpMacSetupPort(Tk_Window window);
static void NpMacGetClip(Tk_Window tkWin, RgnHandle clipRgn); 
static void NpMacGetPluginOffset(Tk_Window tkWin, Point *theOffset);
static int  NpMacRegisterWindow (int windowRef, Tk_Window tkWin);


/*
 * This section implements the platform specific portion of the lifecycle
 * of the plugin.
 *
 */

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
NpPlatformInit(Tcl_Interp *interp, 
        int externalFlag   /* Ignored on the Mac */
        )
{
    static char initScript[] =
"if {[info exists plugin(library)]} return\n\
if {[lsearch [resource list TEXT] plugmain.tcl] != -1} {\n\
    #set plugin(library) resource\n\
    # ssource -rsrc pkgIndex.tcl\n\
}\n\
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
if {[info exists env(MOZILLA_HOME)]} {\n\
    lappend dirlist $env(MOZILLA_HOME)\n\
}\n\
lappend dirlist [file join $env(EXT_FOLDER) \"Tool Command Language\"]\n\
lappend dirlist [file dirname [file dirname [info nameofexecutable]]]\n\
lappend dirlist [pwd]\n\
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

    /* 
     * Pass Tk the QuickDraw global Netscape gave us.
     */
     
    tcl_macQdPtr = gQDPtr;

    /* 
     * Set up the embedding callbacks, store away the current thread ID,
     * create the Tcl thread, and then eval the atartup script.
     */
         
    Tk_MacSetEmbedHandler(NpMacRegisterWindow, NpMacSetupPort, 
            NULL, NpMacGetClip, NpMacGetPluginOffset);

    GetCurrentThread(&gMainThread);
    
    InitTclThreadIfNeeded();
    
    Tcl_SetPanicProc(NpPanic);
    
    return Np_Eval(interp, initScript);

}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformNew --
 *
 *	For the Mac, this starts the Tcl thread spinning.
 *
 * Results:
 *	None
 *
 * Side effects:
 *	None
 *
 *----------------------------------------------------------------------
 */

void
NpPlatformNew(instance)
    NPP instance;
{
    InitTclThreadIfNeeded();	
}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformSetWindow --
 *
 *	Remember the association between this instance pointer and a
 *	container window (platform specific data type).
 *	On the Mac, the NPWindow is not enough, since it is just a 
 *	single Netscape window + offsets.  I would also like to store
 *	away the interpreter & the new toplevel.  For this I RELY on 
 *	the mapping between the Token Name for the Instance and the child
 *	interpreter's name...
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Stores the new window structure in the plugin instance data.
 *
 *----------------------------------------------------------------------
 */

	/* ARGSUSED */
void
NpPlatformSetWindow (NPP This, NPWindow *npWin)
{
    PluginInstance *newInstance;
    PluginList *pluginData;
    SavedPort *savedPort;
    CGrafPtr thisPortPtr = ((NP_Port *) npWin->window)->port;
    
    if (This->pdata == NULL) {
    /*
     * If pdata is NULL, we have not remembered this container before.
     * Set up the PluginInstance structure, and put it in the plugin list
     */
    
    	newInstance = (PluginInstance *) ckalloc(sizeof(PluginInstance));
	This->pdata = newInstance;
        newInstance->tkWin = NULL;
        newInstance->plugin = This;
        newInstance->npWin = npWin;
        
        newInstance->oldClip = npWin->clipRect;
    
       /*
        * Now set up the element in the linked list of all plugins.
        */
        
        pluginData = (PluginList *) ckalloc(sizeof(PluginList));
        pluginData->data = newInstance;
        pluginData->nextPlugin = gPluginList;
        gPluginList = pluginData;
        
        /*
         * If this is the first plugin in this GrafPort, then add the
         * Port to the list of saved Ports
         */
          
        for (savedPort = gSavedPortList; savedPort != NULL; 
                savedPort = savedPort->nextSaved) {
            if (savedPort->portPtr == thisPortPtr) {
                break;
            }
        }
             
        if (savedPort == NULL) {
                savedPort = (SavedPort *) ckalloc(sizeof(SavedPort));
                savedPort->portPtr = thisPortPtr;
                savedPort->savedPort.clipRgn = NewRgn();
                savedPort->isSaved = 0;
	        savedPort->nextSaved = gSavedPortList;
	        gSavedPortList = savedPort;
        }
        
        /*
         * Tk has just been loaded for this plugin, so we will turn off
         * the menus to make sure the plugin cannot damage the browser's
         * menubar
         */
         
        Tk_MacTurnOffMenus();
                 
            
    } else if (((PluginInstance *) This->pdata)->tkWin != NULL) {
        int flags = 0, height, width;
        
        /*
         * We get here if the npwindow for this plugin has changed.
         * Actually, we DO NOT get called here if the window scrolls,
         * but we do get called if it resizes.  We need to generate 
         * a configure event, since the window may have changed size.
         * This happens for full page Tclets only.
         */
         
	newInstance = (PluginInstance *) This->pdata;
        newInstance->npWin = npWin;
        
        if (npWin->clipRect.left != newInstance->oldClip.left
                || npWin->clipRect.top != newInstance->oldClip.top) {
            flags &= TK_LOCATION_CHANGED;
        }
        
        height = npWin->clipRect.bottom - npWin->clipRect.top;
        width = npWin->clipRect.right - npWin->clipRect.left;
        
        if (height != newInstance->oldClip.bottom - 
                newInstance->oldClip.top
                || width != newInstance->oldClip.right - 
                newInstance->oldClip.left) {
            flags &= TK_SIZE_CHANGED;
        }
        
        if (flags) {
            TkGenWMConfigureEvent(newInstance->tkWin,
                    npWin->clipRect.left, npWin->clipRect.top,
                    width, height, flags);
        }
        
        TkMacInvalClipRgns((TkWindow *) newInstance->tkWin);
        newInstance->oldClip = npWin->clipRect;

    }
    
}

/*
 *----------------------------------------------------------------------
 *
 * NpMacRegisterWindow --
 *
 *	This is the callback handed to the tkMacEmbed code.  It is called
 *	when a toplevel is made in tk which has -use set, but is not 
 *	embedded in another Tk window.
 *	It has the responsibility to fill in the port of the macWin structure
 *
 * Results:
 *	Standard Tcl Result.
 *
 * Side effects:
 *	Relates the tkWin to the NPWindow structure representing it.
 *
 *----------------------------------------------------------------------
 */
int 
NpMacRegisterWindow (int windowRef, Tk_Window tkWin)
{
    NP_Port *port = (NP_Port *) windowRef;
    TkWindow *winPtr = (TkWindow *) tkWin;
    PluginList *pluginDataPtr;
    MacDrawable *macWin = winPtr->privatePtr;
    
    /*
     * First find our NPWindow in the plugin list:
     */
    
    for (pluginDataPtr = gPluginList; pluginDataPtr != NULL; 
	    pluginDataPtr = pluginDataPtr->nextPlugin) {
        if ((int) pluginDataPtr->data->npWin->window == windowRef) {
	     break;
	}
    }
    
    if (pluginDataPtr == NULL) {
    	NpPanic("Can't find the PluginData for this windowRef");
    	return TCL_ERROR;
    }
    
    pluginDataPtr->data->tkWin = tkWin;
    
    NpLog("Registering npWin %p for plugin %p and port %p\n", 
            (int) pluginDataPtr->data->npWin,
            (int) pluginDataPtr->data->plugin,
            (int) port->port);
    /*
     * Now fill in the rest of the data for the tkWin.
     */
    
    macWin->portPtr = (GWorldPtr) port->port;
    
    
    winPtr->changes.width = pluginDataPtr->data->npWin->width;
    winPtr->changes.height = pluginDataPtr->data->npWin->height;
    winPtr->changes.x = 0;
    winPtr->changes.y = 0;
    
    macWin->xOff = 0;
    macWin->yOff = 0;
    
    return TCL_OK;
	
}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformDestroy --
 *
 *	Forgets the association between this instance pointer and
 *	a container window.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	This pluginInstance structure is removed from the list of plugins,
 *	and the grafPort is removed from the list of stored ports if it
 *      is the last plugin on this grafPort.
 *
 *----------------------------------------------------------------------
 */

	/* ARGSUSED */
void
NpPlatformDestroy(This)
    NPP This;
{
    PluginList *pluginDataPtr, *prevPtr;
    CGrafPort *thisPort;
    CGrafPort *eachPort;
    
    if (This->pdata == NULL) {
        return;
    }

    /*
     * First find our NPWindow in the plugin list:
     */
    
    prevPtr = NULL;
    
    for (pluginDataPtr = gPluginList; pluginDataPtr != NULL; 
	    prevPtr = pluginDataPtr, pluginDataPtr = pluginDataPtr->nextPlugin) {
        if (pluginDataPtr->data->plugin == This) {
	     break;
	}
    }
    
    if (pluginDataPtr == NULL) {
        NpPanic("Error finding container in NpPlatformForgetContainer");
        return;
    }
    if (pluginDataPtr->data != This->pdata) {
        NpPanic("pdata & plugin list data is inconsistent!");
        return;
    }
            
    if (prevPtr == NULL) {
        gPluginList = pluginDataPtr->nextPlugin;
    } else {
        prevPtr->nextPlugin = pluginDataPtr->nextPlugin;
    }
    
    /*
     * Remember the port, because we want to know if this is the last
     * plugin on this port, then free the memory for this plugin instance.
     */
     
    thisPort = ((NP_Port *) ((PluginInstance *) This->pdata)->npWin->window)->port; 
    
    ckfree((char *) This->pdata);
    This->pdata = NULL;
    ckfree((char *) pluginDataPtr);
    
    /* 
     * If this was the last plugin on this GrafPort, then remove the port from the 
     * list of saved ports
     */
     
    for (pluginDataPtr = gPluginList; pluginDataPtr != NULL; 
	    pluginDataPtr = pluginDataPtr->nextPlugin) {
	eachPort = ((NP_Port *) pluginDataPtr->data->npWin->window)->port;
        if (eachPort == thisPort) {
	     break;
	}
    }
    
    if (pluginDataPtr == NULL) {
        SavedPort *thisSaved, *prevSaved = NULL; 
        
        for (thisSaved = gSavedPortList; 
                thisSaved != NULL;
                prevSaved = thisSaved, thisSaved = thisSaved->nextSaved) {
            if (thisSaved->portPtr == thisPort) {
                break;
            }
        }
        
        if (thisSaved == NULL) {
            panic("Could not find port for a container I am forgetting");
        } else if (prevSaved == NULL) {
            gSavedPortList = thisSaved->nextSaved;
        } else {
            prevSaved->nextSaved = thisSaved->nextSaved;
        }
        DisposeRgn(thisSaved->savedPort.clipRgn);
        ckfree((char *) thisSaved);
            
    }
}

/*
 *----------------------------------------------------------------------
 *
 * NpPlatformShutdown --
 *
 *	Gives the Tcl Thread a chance to shut down, and then frees all
 *      memory the Tcl allocator has allocated.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	It is unsafe to do ANY ckallocs after this function has been 
 *      called.
 *
 *----------------------------------------------------------------------
 */

void
NpPlatformShutdown()
{
    /*
     * Kill the Tcl thread here.
     */
      
    DisposeThread( gTclThread,  NULL, false);

    /*
     * Set these values back in case (as happens on UNIX) we get restarted
     * without getting unloaded & reloaded.
     */
     
    gDone = 0;
    initialized = 0;
    
    /*
     * We now have to clean up all the malloc'ed memory in Tk.
     */
    
    FreeAllMemory(); 
     
}

/*
 ***************************************************************************** 
 * This section implements the communication between the Tcl thread and the 
 * Main thread.  All Tcl_Eval calls are done from the Tcl thread, since this
 * is the only thread whose resources I can control (most importantly the 
 * stack size).  However, all events are funneled in through NPP_HandleEvent
 * in the Main thread, and all NPN_ functions must be run from the Main thread.  
 *****************************************************************************
 */


/*
 *----------------------------------------------------------------------
 *
 * NPP_HandleEvent --
 *
 *	This is how events get from the browser to the plugin on the Mac
 *	The event that we were passed is converted into its Tk events, and
 *	then the Tcl thread is restarted.  The Tcl thread will service all 
 *	the outstanding Tcl events, and then yield back to this thread.
 *
 * Results:
 *	A Netscape error code.
 *
 * Side effects:
 *	An event is placed on the Tcl event queue, and one pass is mace
 *      through Tcl_DoOneEvent.
 *
 *----------------------------------------------------------------------
 */
int16
NPP_HandleEvent(NPP This, void *event)
{
    PluginInstance *pluginInstance = (PluginInstance *) This->pdata;
    NPBool eventHandled = FALSE;
    EventRecord *theEvent = (EventRecord *) event;
    static short curResFile;
    static CGrafPort *oldPortPtr;      /* This stores Netscape's active port */
    
    InitTclThreadIfNeeded();
    
    if (pluginInstance != NULL) {
	
	/* Someone else (like another plugin) might have
	 * opened their resource fork after us, and we don't
	 * want their resources to shadow ours.
	 */
	 
        curResFile = CurResFile();
        UseResFile(gResFile);
        
 	
        /*
         * Test to see if any of our plugins have been scrolled,
         * and if so, invalidate their clip regions.
         */
	                
	NpMacUpdateWindows();

        /*
         * Convert the event, and pass it to the Tcl event queue.  Also set the
         * got an event flag so that if we wake up the Tcl Thread in the middle
         * of a Tcl_WaitForEvent, it knows that a new event has indeed been 
         * processed.  
         * N.B. we have to call SetUpForDrawing first, so this event's coordinates  
         * are correctly interpreted in the frame of the plugin to which the event 
         * was delivered.
         */
         
        GetPort(&((GrafPtr) oldPortPtr));
     
        NpMacSetupForDrawing(pluginInstance->npWin);

	if (TkMacConvertTkEvent(theEvent, 
	        (Window) ((TkWindow *) pluginInstance->tkWin)->privatePtr)) {
	    gGotAnEvent = 1;
            eventHandled = TRUE;
	} else {
	    gGotAnEvent = 0;
	}

        
        /*
         * Now yield to the Tcl thread.  We don't want to return to 
         * Netscape while there is an NPN call still pending, or the
         * calls would get out of order, so we use NpMacDoACompleteEval.
         */
         
	NpMacDoACompleteEval(TCL_SERVICE_ALL);
	        
        NpMacRestoreDrawingEnv();
        SetPort((GrafPtr) oldPortPtr);
	
	UseResFile(curResFile);
	
    }
    
    return eventHandled;

}

/* 
 * -------------------------------------------------------------------------
 * 
 * Tcl_WaitForEvent --
 * 
 *         This version of Tcl_WaitForEvent is only for the plugin.  It
 *         yields control to the Main Thread so that we can get called back
 *         with another event in NPP_HandleEvent.
 * 
 * Results:
 *         A Standard Tcl result
 * 
 * Side effects:
 *         Events on the Tcl event queue are serviced
 * -------------------------------------------------------------------------
 */

int
Tcl_WaitForEvent(
    Tcl_Time *timePtr)		/* Maximum block time. */
{
    
    /*
     * If we are stacked in vwaits, then the Tcl Thread is spinning
     * in Tcl_DoOneEvent, which means that if there is a global script 
     * around that needs to be processed, we must do it here.
     */
     
    if (NpMacServiceNpScript()) {
        NpLog("Tcl_WaitForEvent: Did a global script\n", 0, 0, 0);
    }
    
    /*
     * Set gGotAnEvent to zero, then NPP_HandleEvent will set it
     * to 0 or 1 to indicate whether a new event has been processed.
     */
             
    gGotAnEvent = 0;
    YieldToThread(gMainThread);
    return gGotAnEvent;
}

/* 
 * -------------------------------------------------------------------------
 * 
 * NpMacRunThread --
 * 
 *	This is the Main Loop of the Tcl thread in the Mac Netscape
 *	plugin.  It runs in a thread under the main execution thread of
 *	the plugin.  It processes one Tcl event at a time, returning control  
 *	to the main thread after the event has been processed.  Also, all 
 *      Tcl_Eval calls must be done in the context of this thread. 
 * 
 * Results:
 * 	Repeatedly Processes one event from the Tcl event Queue, and returns
 * 	control to the main plugin thread.
 * 
 * Side effects:
 * 	None
 * -------------------------------------------------------------------------
 */
pascal void *
NpMacRunThread(void *data)
{

    /*
     * Look for an Np_Eval script to handle, and if there is one
     * do it, otherwise service the outstanding events, and then yield
     * back to the Main thread.
     *
     * The gDone variable could be used to get the thread to exit nicely,
     * unwinding the stack, etc.  In practice, however, we just kill it
     * by hand by calling DisposeThread in npPlatformShutdown.
     */
     
    while (!gDone) {
        if (!NpMacServiceNpScript()) {            
            Tcl_ServiceAll();
        } else {
            NpLog("NpMacRunThread: Did a global script\n", 0, 0, 0);
        }
        
        YieldToThread(gMainThread);
    }
    
    return NULL;
    
}

/*
 *----------------------------------------------------------------------
 *
 * InitTclThreadIfNeeded --
 *
 *	This checks that we have a thread for the plugin
 *      Execution, and starts one if not.
 *
 * Results:
 *	None
 *
 * Side effects:
 *	A New Macintosh thread is started, if one does not already exist.
 *
 *----------------------------------------------------------------------
 */

void
InitTclThreadIfNeeded(void)
{
    OSErr err;
    
    if (initialized) {
    	return;
    }
    
    initialized = 1;
    err = NewThread(kCooperativeThread, NpMacRunThread, NULL,
	    TCL_THREAD_STACK_SIZE, kNewSuspend + kCreateIfNeeded, 
	    NULL, &gTclThread);
    if (err != noErr) {
	NpPanic("Failed to create the thread for Tcl");
    }
    	
}

/*
 *----------------------------------------------------------------------
 *
 * NpMacWakeUpTclThread --
 *
 *	This wakes up the tcl thread, and then when it yields control 
 *      back to us, puts it to sleep again.
 *
 * Results:
 *	None
 *
 * Side effects:
 *	The Tcl thread is given a chance to run.
 *
 *----------------------------------------------------------------------
 */

void
NpMacWakeUpTclThread(
        int serviceMode)
{
    int oldServiceMode;
    
    oldServiceMode = Tcl_SetServiceMode(serviceMode);
    
    SetThreadState(gTclThread, kReadyThreadState, kNoThreadID);
    YieldToThread(gTclThread);
    SetThreadState(gTclThread, kStoppedThreadState, gMainThread);
    
    Tcl_SetServiceMode(oldServiceMode);    	
}

/* 
 * -------------------------------------------------------------------------
 * 
 * NpMacServiceNpScript --
 * 
 *	Looks for a Np_Eval script or script objPtr, and eval's it if present.
 * 
 * Results:
 * 	1 if a script was found, 0 otherwise.
 * 
 * Side effects:
 * 	Whatever the script does.
 * -------------------------------------------------------------------------
 */
int 
NpMacServiceNpScript(void)
{
    char *curScript;
    Tcl_Obj *curObjCmd;
    Tcl_Interp *curInterp;

    if (gTclScript != NULL) {
        if (gTclInterp != NULL) {
            curScript = gTclScript;
            curInterp = gTclInterp;
            gTclScript = NULL;
            gTclInterp = NULL;
                
            gTclResult = Tcl_Eval(curInterp, curScript);
        } else {
            NpPanic("Np_Eval called me with a null interp");
            gTclResult = TCL_ERROR;
        }
        return 1;
    } else if (gTclObjPtr != NULL) {
        if (gTclInterp != NULL) {
            curObjCmd = gTclObjPtr;
            curInterp = gTclInterp;
            gTclObjPtr = NULL;
            gTclInterp = NULL;
                
            gTclResult = Tcl_EvalObj(curInterp, curObjCmd);
        } else {
            NpPanic("Np_Eval called me with a null interp");
            gTclResult = TCL_ERROR;
        }
        return 1;
    }
    return 0;
    
}

/*
 *----------------------------------------------------------------------
 *
 * Np_Eval --
 *
 *	This Tcl_Evals the script in the string variable but makes sure 
 *      that it happens in the stack frame of the Tcl Thread.
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
Np_Eval(Tcl_Interp *interp,
        char *string)
{
    
    if ((gTclScript != NULL) || (gTclObjPtr != NULL)) {
        NpPanic("Np_Eval run when there was already a script in the queue");
        return TCL_ERROR;
    }

    InitTclThreadIfNeeded();

    gTclScript = string;
    gTclInterp = interp;

    NpMacDoACompleteEval(TCL_SERVICE_NONE);

    return gTclResult;

}

/*
 *----------------------------------------------------------------------
 *
 * Np_EvalObj --
 *
 *	This Tcl_EvalObj's the script in the objPtr variable but makes sure 
 *      that it happens in the stack frame of the Tcl Thread.
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
Np_EvalObj(Tcl_Interp *interp,
        Tcl_Obj *objPtr)
{

    if ((gTclScript != NULL) || (gTclObjPtr != NULL)) {
        NpPanic("Np_Eval run when there was already a script in the queue");
        return TCL_ERROR;
    }

    InitTclThreadIfNeeded();


    gTclObjPtr = objPtr;
    gTclInterp = interp;

    NpMacDoACompleteEval(TCL_SERVICE_NONE);
    
    return gTclResult;

}

/*
 ****************************************************************************
 * The next section is the lowest level of drawing code for the plugin.
 * It handles setting up the drawing environment for each plugin before
 * the standard Tk routines try to draw
 ****************************************************************************
 */
 
/* 
 * -------------------------------------------------------------------------
 * 
 * NpMacUpdateWindows --
 * 
 *         This function scans through the list of plugins for all the
 *         windows whose clip regions have been changed - because they have
 *         been scrolled, sets their clip region to invalid and generates  
 *         updates for them.
 *         
 * Results:
 *         None
 * 
 * Side effects:
 *         Tk configure events may be generated.
 * -------------------------------------------------------------------------
 */
void 
NpMacUpdateWindows() 
{
    PluginList *pluginDataPtr;
    NPWindow *npWin;
    NPRect *oldClipPtr;
    TkWindow *winPtr;
    
    for (pluginDataPtr = gPluginList; pluginDataPtr != NULL; 
	    pluginDataPtr = pluginDataPtr->nextPlugin) {
	    
	npWin = pluginDataPtr->data->npWin;
	oldClipPtr = &(pluginDataPtr->data->oldClip);
	if ( oldClipPtr->top != npWin->clipRect.top
	        || oldClipPtr->left != npWin->clipRect.left
	        || oldClipPtr->bottom != npWin->clipRect.bottom
	        || oldClipPtr->right != npWin->clipRect.right) {	    
            /*
             * Force the invalidation of the clip region for this
             * window and its children, so it will get updated.
             */
             
 	    winPtr = (TkWindow *) pluginDataPtr->data->tkWin;
            TkMacInvalClipRgns(winPtr);
                                                 
            pluginDataPtr->data->oldClip = npWin->clipRect;

        }    
    }
}


/* 
 * -------------------------------------------------------------------------
 * 
 * NpMacSetupPort --
 * 
 *         This is the function passed to the Tk Embed Handler
 *         facility in Tk.  Its job is to get the GrafPort the Tk Window 
 *         "window", and set it up for drawing on the Mac.
 *         The window must be in the pluginData list.
 *         It sets to origin of the GrafPort to the ULH corner of the tkWin
 * 
 * Results:
 *         A Macintosh GrafPort
 * 
 * Side effects:
 *         The GrafPort's origin is shifted.
 * -------------------------------------------------------------------------
 */
GWorldPtr 
NpMacSetupPort(Tk_Window window) 
{
    TkWindow *winPtr = (TkWindow *) window;
    TkWindow *toplevel = winPtr->privatePtr->toplevel->winPtr;
    PluginList *pluginDataPtr;
    NPWindow *npWin;
    
    for (pluginDataPtr = gPluginList; pluginDataPtr != NULL; 
	 pluginDataPtr = pluginDataPtr->nextPlugin) {
	 	if (pluginDataPtr->data->tkWin == (Tk_Window) toplevel) {
	 		break;
	 	}
    }
    
    if (pluginDataPtr == NULL) {
        char buffer[256];
        sprintf(buffer,"NpMacSetupPort can't find the PluginData for tkWindow %s",
                winPtr->pathName);
    	NpPanic(buffer);
    	return NULL;
    }
    
    npWin = pluginDataPtr->data->npWin;

    NpMacSetupForDrawing(npWin);
        
    return (GWorldPtr) ((NP_Port *) npWin->window)->port;
    
}


/* 
 * -------------------------------------------------------------------------
 * 
 * NpMacSetupForDrawing --
 * 
 *         This Sets up the port for drawing into the port specified by the
 *         NPWindow structure given by npWin.  It stores the previous drawing
 *         environment if this is the first time this GrafPort is touched.
 *         It sets to origin of the GrafPort to the ULH corner of the tkWin
 * 
 * Results:
 *         None
 * 
 * Side effects:
 *         The GrafPort's origin is shifted
 * -------------------------------------------------------------------------
 */
void
NpMacSetupForDrawing(NPWindow *npWin) 
{
    SavedPort *savedPort;
    NP_Port *port = (NP_Port *) npWin->window;
    Rect clipRect;
    
    if (npWin->clipRect.left < npWin->clipRect.right) {
	for (savedPort = gSavedPortList; savedPort != NULL; 
	        savedPort = savedPort->nextSaved) {
            if (savedPort->portPtr == port->port) {
            	break;
            }
	}
	
	if (savedPort == NULL) {
	    panic("SetUpForDrawing passed an NPWindow that is not on my port list");
	    return;
	}
	
	if (port->port == NULL) {
	    panic("Passed a Null port in SetUpForDrawing");
	    return;
	}
	
        SetPort((GrafPtr) port->port);
	
	/*
	 * If this is the first time that we are setting up the environment
	 * for this npWin, then we store the information for it away.
	 *
	 * Note we do not store the old port away here, as the Netscape sample code
	 * does, because the current port may be one set by Tk, so we don't want to 
	 * restore it.
	 */

	if (!savedPort->isSaved) {
	    savedPort->savedPort.portRect = port->port->portRect;
	    savedPort->savedPort.txFont = port->port->txFont;
	    savedPort->savedPort.txFace = port->port->txFace;
	    savedPort->savedPort.txMode = port->port->txMode;
	    savedPort->savedPort.rgbFgColor = port->port->rgbFgColor;
	    savedPort->savedPort.rgbBkColor = port->port->rgbBkColor;
	    GetClip(savedPort->savedPort.clipRgn);
	    savedPort->isSaved = 1;
	    	    
	}
	
	/* 
	 * Now set up the new drawing environment...
	 */
	
	clipRect.top = npWin->clipRect.top + port->porty;
	clipRect.left = npWin->clipRect.left + port->portx;
	clipRect.right = npWin->clipRect.right + port->portx;
	clipRect.bottom = npWin->clipRect.bottom + port->porty;
	
	SetOrigin(port->portx, port->porty);
	ClipRect(&clipRect);
    }
     
 }

/* 
 * -------------------------------------------------------------------------
 * 
 * NpMacRestoreDrawingEnv --
 * 
 *         This restores the drawing environment for all the ports that
 *         were touched by NpMacSetupForDrawing.  Call this before returning
 *         to Netscape.  
 *         It does not restore the GrafPort to the first value, however.
 * 
 * Results:
 *         None
 * 
 * Side effects:
 *         The GrafPorts that were touched with NpMacSetupDrawingEnvironment
 *         are restored to their original values.
 * -------------------------------------------------------------------------
 */
 void
 NpMacRestoreDrawingEnv() 
{
    SavedPort *savedPort;
    
    for (savedPort = gSavedPortList; savedPort != NULL; 
            savedPort = savedPort->nextSaved) {
        if (savedPort->isSaved) {
            if (savedPort->portPtr == NULL) {
                panic("RestoreDrawingEnv hit a null portPtr");
            }
                        
            SetPort((GrafPtr) savedPort->portPtr);
            SetOrigin(savedPort->savedPort.portRect.left, savedPort->savedPort.portRect.top);
            SetClip(savedPort->savedPort.clipRgn);
            savedPort->portPtr->txFont = savedPort->savedPort.txFont;
            savedPort->portPtr->txFace = savedPort->savedPort.txFace;
            savedPort->portPtr->txMode = savedPort->savedPort.txMode;
            RGBForeColor(&(savedPort->savedPort.rgbFgColor));
            RGBBackColor(&(savedPort->savedPort.rgbBkColor));
            
            savedPort->isSaved = 0;
    	}	
    }    
}

/* 
 * -------------------------------------------------------------------------
 * 
 * NpMacGetPluginOffset --
 * 
 *         This is another of the embedding handlers for the Netscape embedding.
 *         This returns the offset of the Tk window, which is assumed to be a 
 *         toplevel that is -used by a NON-Tk toplevel, in its containing Mac
 *         toplevel.
 *
 * 
 * Results:
 *         Sets theOffset to the correct offset
 * 
 * Side effects:
 *         None
 * -------------------------------------------------------------------------
 */
void 
NpMacGetPluginOffset(Tk_Window tkWin, Point *theOffset)
{
    TkWindow *winPtr = (TkWindow *) tkWin;
    PluginList *pluginDataPtr;
    NPWindow *npWin;
    NP_Port *port;
    
    for (pluginDataPtr = gPluginList; pluginDataPtr != NULL; 
	 pluginDataPtr = pluginDataPtr->nextPlugin) {
	 if (pluginDataPtr->data->tkWin == tkWin) {
	     break;
	 }
    }
    
    if (pluginDataPtr == NULL) {
    	NpPanic("Can't find the PluginData for this tkWindow");
    	return;
    }
    
    npWin = pluginDataPtr->data->npWin;
    port = (NP_Port *) npWin->window;
    theOffset->h = 0;
    theOffset->v = 0;
    LocalToGlobal(theOffset);
        
} 

/* 
 * -------------------------------------------------------------------------
 * 
 * NpMacGetClip --
 * 
 *         This is another of the embedding handlers for the Netscape embedding.
 *         This returns the clip region for the current npWindow corresponding
 *         to the input Tk_Window.  This must be an embedded toplevel, that is
 *         not controlled by Tk.
 *
 *         This assumes that the window has already been set up for drawing,
 *         so the origin shift has been done.  The clip region is returned in
 *         the shifted coordinates.
 * 
 * Results:
 *         None
 * 
 * Side effects:
 *         None
 * -------------------------------------------------------------------------
 */
void 
NpMacGetClip(Tk_Window tkWin, RgnHandle clipRgn)
{
    TkWindow *winPtr = (TkWindow *) tkWin;
    PluginList *pluginDataPtr;
    NPWindow *npWin;
    NP_Port *port;
    
    for (pluginDataPtr = gPluginList; pluginDataPtr != NULL; 
	 pluginDataPtr = pluginDataPtr->nextPlugin) {
	 if (pluginDataPtr->data->tkWin == tkWin) {
	     break;
	 }
    }
    
    if (pluginDataPtr == NULL) {
    	NpPanic("Can't find the PluginData for this tkWindow");
    	return;
    }
    
    npWin = pluginDataPtr->data->npWin;
    port = (NP_Port *) npWin->window;
    SetRectRgn(clipRgn,
	npWin->clipRect.left + port->portx,
	npWin->clipRect.top + port->porty,
	npWin->clipRect.right + port->portx,
	npWin->clipRect.bottom + port->porty);
}

/*
 ************************************************************************ 
 * The following three functions implement the panic and warning message
 * posting facilities for the plugin.
 ************************************************************************
 */
 

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
    myPostDialog(msg);
#ifdef TCL_DEBUG
    Debugger();
#endif
}

/*
 *----------------------------------------------------------------------
 *
 * NpPanic --
 *
 *	Displays panic info..
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Cleans up plugin state.
 *
 *----------------------------------------------------------------------
 */

static void
NpPanic(
    char *msg)
{
    myPostDialog(msg);  
#ifdef TCL_DEBUG
    Debugger();
#endif
    /*
     * This should do the same thing as NPP_Shutdown when
     * it's the last instance.
     */
    /* NpPlatformShutdown(); */
}



/*
 *----------------------------------------------------------------------
 *
 * myPostDialog --
 *
 *	This does the actual work of posting either a panic or a
 *      message dialog, without using resources.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	None
 *
 *----------------------------------------------------------------------
 */

static void myPostDialog(
    char *msg)
{
    WindowRef macWinPtr, foundWinPtr;
    Rect macRect;
    Rect buttonRect = PANIC_BUTTON_RECT;
    Rect iconRect = PANIC_ICON_RECT;
    Rect textRect = PANIC_TEXT_RECT;
    ControlHandle okButtonHandle;
    EventRecord event;
    Handle stopIconHandle;
    int	part;
    Boolean done = false;
            

    /*
     * Put up an alert without using the Resource Manager (there may 
     * be no resources to load). Use the Window and Control Managers instead.
     */
 
    macRect.top = 40;
    macRect.left = 40;
    macRect.bottom = PANICHEIGHT;
    macRect.right = PANICWIDTH;
    
    macWinPtr = NewWindow(NULL, &macRect, "\p", true, dBoxProc, (WindowRef) -1,
            false, 0);
    if (macWinPtr == NULL) {
	goto exitNow;
    }
    
    okButtonHandle = NewControl(macWinPtr, &buttonRect, "\pOK", true,
	    0, 0, 1, pushButProc, 0);
    if (okButtonHandle == NULL) {
	CloseWindow(macWinPtr);
	SysBeep(1);
	goto exitNow;
    }
    
    SelectWindow(macWinPtr);
    /* SetCursor(&qd.arrow); */
    stopIconHandle = GetIcon(kStopIcon);
            
    while (!done) {
	if (WaitNextEvent(mDownMask | keyDownMask | updateMask,
		&event, 0, NULL)) {
	    switch(event.what) {
		case mouseDown:
		    part = FindWindow(event.where, &foundWinPtr);
    
		    if ((foundWinPtr != macWinPtr) || (part != inContent)) {
		    	SysBeep(1);
		    } else {
		    	SetPortWindowPort(macWinPtr);
		    	GlobalToLocal(&event.where);
		    	part = FindControl(event.where, macWinPtr,
				&okButtonHandle);
    	
			if ((inButton == part) && 
				(TrackControl(okButtonHandle,
					event.where, NULL))) {
			    done = true;
			}
		    }
		    break;
		case keyDown:
		    switch (event.message & charCodeMask) {
			case ENTERCODE:
			case RETURNCODE:
			    HiliteControl(okButtonHandle, 1);
			    HiliteControl(okButtonHandle, 0);
			    done = true;
		    }
		    break;
		case updateEvt:   
		    SetPortWindowPort(macWinPtr);
		    TextFont(systemFont);
		    
		    BeginUpdate(macWinPtr);
		    if (stopIconHandle != NULL) {
			PlotIcon(&iconRect, stopIconHandle);
		    }
		    TextBox(msg, strlen(msg), &textRect, teFlushDefault);
		    DrawControls(macWinPtr);
		    EndUpdate(macWinPtr);
	    }
	}
    }

    CloseWindow(macWinPtr);

    exitNow:
    
    return;
    
}
