/* 
 * npmaccmds.c --
 *
 *	Wrappers for the NPN commands used in npcmds.c
 *
 * AUTHOR: Jim Ingham			jingham@eng.sun.com
 *
 * Please contact me directly for questions, comments and enhancements.
 *
 * Copyright (c) 1995 Sun Microsystems, Inc.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npmaccmds.c 1.1 97/12/16 18:06:37
 */

#include "npmac.h"
#include <tclMacInt.h>
#include <tkMacInt.h>
#include <Threads.h>

/*
 * The following is necessary to pass control back to the Main thread 
 * when we want to call NPN functions, since it is not safe to call 
 * the NPN functions from any other thread...
 * If you add any other of the NPN functions to the plugin, you must add wrappers
 * here as well.
 */
 
typedef void (Main_NPN_Proc)(void);

static void Main_NPN_GetURL(void);
static void Main_NPN_PostURL(void);
static void Main_NPN_Status(void);
static void Main_NPN_NewStream(void);
static void Main_NPN_Write(void);
static void Main_NPN_DestroyStream(void);
static void Main_NPN_UserAgent(void);
static void Main_NPN_Version(void); 

void CallNPNInMain(Main_NPN_Proc theProc, int nArgs, ...);

static Main_NPN_Proc *gNPN_Proc = NULL;
static void *gNPN_Argv[6];
static void *gNPN_Return;


/*
 ******************************************************************************
 *   This note explains how the NPN Tcl wrappers are run on the Mac:
 *  
 *	The NPN commands are wrapped in Tcl commands, so they will be called 
 *      on the Tcl thread side.  But the functions themselves can only be called
 *      from the main thread side (this is a Netscape restriction).  So we break
 *      each function into a pair of functions.  One (the Np_ one) is called from
 *      the Tcl command.  It stores away the args & a pointer to it companion function,
 *      and wakes up the main thread.  The main thread checks for this global pointer,
 *      and if it is set, runs the companion function, which takes the arguments,
 *      casts them appropriately, and runs the real NPN function.
 *******************************************************************************
 */

/*
 *----------------------------------------------------------------------
 *
 * NpMacDoACompleteEval --
 *
 *	This wakes up the Tcl thread to process its queue, and keeps doing 
 *      so until it is no longer interrupted by an NPN callback into the main
 *      thread.
 *
 * Results:
 *	None
 *
 * Side effects:
 *	Whatever the tcl thread does.
 *
 *----------------------------------------------------------------------
 */
void 
NpMacDoACompleteEval(int serviceMode)
{
    Main_NPN_Proc *curProc;

    /*
     * We get passed in a service mode, which we use when we
     * start waking up the Tcl thread, but if we get called back, 
     * then we are in the middle of an NPN proc, in which case it is
     * probably NOT safe to service any new events...
     */
         
    NpMacWakeUpTclThread(serviceMode);


    while (1) {
        
        if (gNPN_Proc != NULL) {
            curProc = gNPN_Proc;
            gNPN_Proc = NULL;
            curProc();
        } else {
           break;
        }
        
        NpMacWakeUpTclThread(TCL_SERVICE_NONE);               
    }
} 

/*
 *----------------------------------------------------------------------
 *
 * CallNPNInMain --
 *
 *	This is called by the Tcl thread side of the NPN wrappers.  It 
 *      stashes away the arguments and the proc to be called, and then
 *      yields to the Main thread.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Whatever theProc does.
 *
 *----------------------------------------------------------------------
 */
void
CallNPNInMain(Main_NPN_Proc *theProc,
              int nArgs,
              ...)
{
    va_list argList;
    int i;
        
    if (gNPN_Proc != NULL) {
        NpPanic("CallNPNInMain called with non-NULL proc.");
    }
    
    gNPN_Proc = theProc;
    
    va_start(argList, nArgs);
    
    for (i = 0; i < nArgs; i++) {
        gNPN_Argv[i] = va_arg(argList, void *);
    }
    
    va_end(argList);
    
    /*
     * Be careful, the NPN proc might call back into the Tcl thread
     * through a call to Np_Eval.  If it does, we have to eval the script,
     * and then return control to the main thread so it can complete the
     * execution of the NPN function before we can exit.
     */
     
    while (1) {
        
        YieldToThread(gMainThread);
        
        if (!NpMacServiceNpScript()) {            
            break;            
        }        
    }
        
}

NPError
Np_NPN_GetURL(NPP instance, 
               const char* url,
	       const char* target)
{

    CallNPNInMain(Main_NPN_GetURL, 3, 
            (void *) instance,
            (void *) url,
            (void *) target);
    
    return (NPError) gNPN_Return;
}

void Main_NPN_GetURL(void) {
    
    gNPN_Return = (void *) NPN_GetURL((NPP) gNPN_Argv[0],
                                      (const char *) gNPN_Argv[1],
                                      (const char *) gNPN_Argv[2]);
}
 
NPError
Np_NPN_PostURL(NPP instance, 
		    const char* url,
		    const char* target, 
		    uint32 len,
		    const char* buf, 
		    NPBool file)
{

    CallNPNInMain(Main_NPN_PostURL, 6,
            (void *) instance,
            (void *) url,
            (void *) target,
            (void *) len,
            (void *) buf,
            (void *) file);
   
    return (NPError) gNPN_Return;

}

void Main_NPN_PostURL(void) {
    
    gNPN_Return = (void *) NPN_PostURL((NPP) gNPN_Argv[0],
                                      (const char *) gNPN_Argv[1],
                                      (const char *) gNPN_Argv[2],
                                      (uint32) gNPN_Argv[3],
                                      (const char *) gNPN_Argv[4],
                                      (NPBool) gNPN_Argv[5]);
}

void        	
Np_NPN_Status(NPP instance, 
	         const char* message)
{
    CallNPNInMain(Main_NPN_Status, 2,
            (void *) instance,
            (void *) message);   
    
}

void 
Main_NPN_Status(void)
{

    NPN_Status((NPP) gNPN_Argv[0], (const char *) gNPN_Argv[1]);
        
}


NPError     	
Np_NPN_NewStream(NPP instance, NPMIMEType type,
				const char* target, NPStream** stream)
{

    CallNPNInMain(Main_NPN_NewStream, 4,
            (void *) instance,
            (void *) type,
            (void *) target,
            (void *) stream);   
    return (NPError) gNPN_Return;
}

void
Main_NPN_NewStream(void)
{

    gNPN_Return = (void *) NPN_NewStream((NPP) gNPN_Argv[0],
                                         (NPMIMEType) gNPN_Argv[1],
                                         (const char *) gNPN_Argv[2],
                                         (NPStream **) gNPN_Argv[3]);
                                          
}

int32        
Np_NPN_Write(NPP instance, NPStream* stream, int32 len,
				void* buffer)
{
    CallNPNInMain(Main_NPN_Write, 4,
            (void *) instance,
            (void *) stream,
            (void *) len,
            (void *) buffer);
            
    return (int32) gNPN_Return;
}

void
Main_NPN_Write(void)
{

    gNPN_Return = (void *) NPN_Write((NPP) gNPN_Argv[0],
                                         (NPStream *) gNPN_Argv[1],
                                         (int32) gNPN_Argv[2],
                                         (void *) gNPN_Argv[3]);
                                          
}

NPError    	
Np_NPN_DestroyStream(NPP instance, NPStream* stream,
				NPReason reason)
{
    NpLog("Np_NPN_DestroyStream: About to call CallNPNInMain\n", 0, 0, 0);                 
    CallNPNInMain(Main_NPN_DestroyStream, 3,
            (void *) instance,
            (void *) stream,
            (void *) reason);
    NpLog("Np_NPN_DestroyStream: Got back from CallNPNInMain with retval: %d\n", (int) gNPN_Return, 0, 0);                 
    return (NPError) gNPN_Return;
}

void
Main_NPN_DestroyStream(void)
{
    NpLog("Main_NPN_DestroyStream: About to call NPN_DestroyStream\n", 0, 0, 0);                 
    gNPN_Return = (void *) NPN_DestroyStream((NPP) gNPN_Argv[0],
            (NPStream *) gNPN_Argv[1],
            (NPReason) gNPN_Argv[2]);
    NpLog("Main_NPN_DestroyStream: done calling NPN_DestroyStream\n", 0, 0, 0);                 
            
}

const char* 	
Np_NPN_UserAgent(NPP instance)
{
    
    CallNPNInMain(Main_NPN_UserAgent, 1,
            (void *) instance);
                
    return (const char *) gNPN_Return;    
}

void
Main_NPN_UserAgent(void)
{
    gNPN_Return = (char *) NPN_UserAgent((NPP) gNPN_Argv[0]);
}

void        	
Np_NPN_Version(int* plugin_major, 
		int* plugin_minor,
		int* netscape_major, 
		int* netscape_minor)
{
    CallNPNInMain(Main_NPN_Version, 4,
            (void *) plugin_major, 
	    (void *) plugin_minor,
	    (void *) netscape_major, 
	    (void *) netscape_minor);
}

void 
Main_NPN_Version(void) 
{
    NPN_Version((int *) gNPN_Argv[0], 
		(int *) gNPN_Argv[1],
		(int *) gNPN_Argv[2], 
		(int *) gNPN_Argv[3]);
}

