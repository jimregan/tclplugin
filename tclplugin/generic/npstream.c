/* 
 * npstream.c --
 *
 *	Implements the functions used to get URLs loaded from Navigator
 *	into the plugin, and functions that implement commands to request
 *	that Navigator initiate loading of new URLs. 
 *
 * CONTACT:		sunscript-plugin@sunscript.sun.com
 *
 * AUTHORS:		Jacob Levy			Laurent Demailly
 *			jyl@eng.sun.com			demailly@eng.sun.com
 *			jyl@tcl-tk.com			L@demailly.com
 *
 * Please contact us directly for questions, comments and enhancements.
 *
 * Copyright (c) 1996-1997 Sun Microsystems, Inc.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npstream.c 1.39 97/12/03 14:53:15
 */

#include	"np.h"

/*
 *----------------------------------------------------------------------
 *
 * NPP_NewStream --
 *
 *	Notifies the plugin that Netscape is about to start sending a
 *	new stream to the plugin. The plugin is allowed to specify how
 *	it wants to receive the data: either as a file (NP_ASFILE) or
 *	streaming (NP_NORMAL). Currently the plugin always asks for the
 *	data in streaming mode (NP_NORMAL) because there are security
 *	issues with caching the tclet.
 *
 * Results:
 *	A standard Netscape error code.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

NPError NP_LOADDS
NPP_NewStream(NPP This, NPMIMEType type, NPStream *stream, NPBool seekable,
              uint16 *stype)
{
    Tcl_DString ds;
    Tcl_Interp *interp;
    char buf[64];
    int oldServiceMode = NpEnter("NPP_NewStream");

    streams++;

    interp = NpGetMainInterp();

    /*
     * Register the stream token so that we can later check for invalid
     * stream tokens from the browser.
     */
    
    NpRegisterToken((ClientData) stream, interp, NPTCL_STREAM);

    *stype = NP_NORMAL;
    Tcl_DStringInit(&ds);

    Tcl_DStringAppendElement(&ds, "npNewStream");

    Tcl_DStringAppendElement(&ds, NpGetTokenName((ClientData) This,
	    interp, NPTCL_INSTANCE));

    Tcl_DStringAppendElement(&ds, NpGetTokenName((ClientData) stream,
	    interp, NPTCL_STREAM));

    Tcl_DStringAppendElement(&ds, (char *) stream->url);

    Tcl_DStringAppendElement(&ds, (char *) type);

    sprintf(buf, "%d", (int) stream->lastmodified);
    Tcl_DStringAppendElement(&ds, buf);

    sprintf(buf, "%d", (int) stream->end);
    Tcl_DStringAppendElement(&ds, buf);
    
    if (Np_Eval(interp, Tcl_DStringValue(&ds)) != TCL_OK) {
        NpPlatformMsg(Tcl_GetStringResult(interp), "npNewStream");
        Tcl_DStringFree(&ds);
        NpLeave("NPP_NewStream err", oldServiceMode);

        return NPERR_GENERIC_ERROR;
    }
    
    Tcl_DStringFree(&ds);
    NpLeave("NPP_NewStream ok", oldServiceMode);

    return NPERR_NO_ERROR;
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_WriteReady --
 *
 *	Called by Netscape to ask the plugin instance how much input it
 *	is willing to accept now. We always return MAXINPUTSIZE, which
 *	tells Netscape that we will accept whatever amount of input is
 *	available.
 *
 * Results:
 *	Always MAXINPUTSIZE.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

	/* ARGSUSED */
int32 NP_LOADDS
NPP_WriteReady(NPP This, NPStream *stream)
{
    return MAXINPUTSIZE;
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_Write --
 *
 *	Called by Netscape to provide a buffer of input of a specified
 *	size to the plugin. The plugin indicates, through the return
 *	value, how much of the input has been consumed by it.
 *
 * Results:
 *	The number of bytes consumed by the plugin.
 *
 * Side effects:
 *	The input is consumed by the plugin.
 *
 *----------------------------------------------------------------------
 */

	/* ARGSUSED */
int32 NP_LOADDS
NPP_Write(NPP This, NPStream *stream, int32 offset, int32 len, void *buffer)
{
    ClientData dummy;
    Tcl_Interp *interp;
    Tcl_DString ds;
    Tcl_Obj *cmdPtr;
    char buf[128];
    int curSize, flags, result;
    int oldServiceMode = NpEnter("NPP_Write");

    interp = NpGetMainInterp();

    /*
     * Check that we got a legal stream from the browser:
     */

    Tcl_ResetResult(interp);

    if (NpGetAndCheckToken(interp,
            NpGetTokenName((ClientData) stream, interp, NPTCL_STREAM),
            NPTCL_STREAM,
            &dummy)
            != TCL_OK) {
        NpPlatformMsg(Tcl_GetStringResult(interp), "NPP_Write");
        len = -1;
        goto end;
    }
    
    Tcl_DStringInit(&ds);
    Tcl_DStringAppendElement(&ds, "npWriteStream");
    Tcl_DStringAppendElement(&ds,
            NpGetTokenName((ClientData) This, interp, NPTCL_INSTANCE));
    Tcl_DStringAppendElement(&ds,
            NpGetTokenName((ClientData) stream, interp, NPTCL_STREAM));
    sprintf(buf, "%d", (int) len);
    Tcl_DStringAppendElement(&ds, buf);

    /* 
     * Tcl_DStringAppendElement is not safe wrt \0 so we do it inline.
     */
    Tcl_DStringAppend(&ds, " ", 1);
    curSize=Tcl_DStringLength(&ds); 
    Tcl_DStringSetLength(&ds, curSize
	    + Tcl_ScanCountedElement(buffer,len,&flags) );
    Tcl_DStringSetLength(&ds,curSize 
	    + Tcl_ConvertCountedElement(buffer,len,
		    Tcl_DStringValue(&ds)+curSize,flags));

    cmdPtr = Tcl_NewStringObj(Tcl_DStringValue(&ds), Tcl_DStringLength(&ds));
    Tcl_DStringFree(&ds);
    Tcl_IncrRefCount(cmdPtr);

    result = Np_EvalObj(interp, cmdPtr);
    if (result != TCL_OK) {
        NpPlatformMsg(
            Tcl_GetStringFromObj(Tcl_GetObjResult(interp), (int *) NULL),
            "npWriteStream");
        len = -1;
    }

    Tcl_DecrRefCount(cmdPtr);	

end:
    NpLeave("NPP_Write", oldServiceMode);
    return len;
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_DestroyStream --
 *
 *	Netscape calls this function to inform the plugin that a
 *	stream was destroyed, either by user action or because the
 *	navigator was unable to get the contents.
 *
 * Results:
 *	A standard Netscape error code.
 *
 * Side effects:
 *	Cleans up memory.
 *
 *----------------------------------------------------------------------
 */

	/* ARGSUSED */
NPError NP_LOADDS
NPP_DestroyStream(NPP This, NPStream *stream, NPError reason)
{
    ClientData dummy;
    Tcl_DString ds;
    Tcl_Interp *interp;
    int oldServiceMode = NpEnter("NPP_DestroyStream");

    interp = NpGetMainInterp();

    /*
     * Check that we got a legal stream from the browser:
     */
    
    Tcl_ResetResult(interp);

    if (NpGetAndCheckToken(interp,
            NpGetTokenName((ClientData) stream, interp, NPTCL_STREAM),
            NPTCL_STREAM,
            &dummy)
            != TCL_OK) {

        NpPlatformMsg(Tcl_GetStringResult(interp), "NPP_DestroyStream");
        goto error;
    }

    /*
     * Remove the stream from the token table.
     */

    NpLog("Forgetting stream 0x%x token %s\n", (int) stream,
          (int) NpGetTokenName((ClientData) stream, interp, NPTCL_STREAM),
          0);
    
    NpUnregisterToken(interp,
            NpGetTokenName((ClientData) stream, interp, NPTCL_STREAM),
            NPTCL_STREAM);

    /*
     * Prepare the stream close command for evaluation.
     */
    
    Tcl_DStringInit(&ds);
    Tcl_DStringAppendElement(&ds, "npDestroyStream");
    Tcl_DStringAppendElement(&ds,
            NpGetTokenName((ClientData) This, interp, NPTCL_INSTANCE));
    Tcl_DStringAppendElement(&ds,
            NpGetTokenName((ClientData) stream, interp, NPTCL_STREAM));
    switch (reason) {
        case NPRES_DONE:
            Tcl_DStringAppendElement(&ds, "EOF");
            break;
        case NPRES_NETWORK_ERR:
            Tcl_DStringAppendElement(&ds, "NETWORK_ERROR");
            break;
        case NPRES_USER_BREAK:
            Tcl_DStringAppendElement(&ds, "USER_BREAK");
            break;
        default:
            Tcl_DStringAppendElement(&ds, "UNKNOWN");
            break;
    }

    if (Np_Eval(interp, Tcl_DStringValue(&ds)) != TCL_OK) {
        NpPlatformMsg(Tcl_GetStringResult(interp), "npDestroyStream");
        Tcl_DStringFree(&ds);
        goto error;
    }

    Tcl_DStringFree(&ds);
    streams--;
    NpLeave("NPP_DestroyStream ok", oldServiceMode);
    return NPERR_NO_ERROR;

error:
    streams--;
    NpLeave("NPP_DestroyStream err", oldServiceMode);
    return NPERR_GENERIC_ERROR;    
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_StreamAsFile --
 *
 *	Netscape calls this function in the plugin to tell it that the
 *	requested stream is stored in a cache file and has been completely
 *	received. The plugin sources the stream into the interpreter for
 *	this instance, if the stream mode is NPTK_FILE. Otherwise, the
 *	function does nothing.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	May load the file as Tcl code into the interpreter associated
 *	with the plugin instance.
 *
 *----------------------------------------------------------------------
 */

	/* ARGSUSED */
void NP_LOADDS
NPP_StreamAsFile(NPP This, NPStream *stream, const char *fname)
{
    /*
     * Nothing to do here.
     */
}

/*
 *----------------------------------------------------------------------
 *
 * NPP_URLNotify --
 *
 *	Called by Navigator when a URL is finished fetching when the
 *	request was initiated through a call to NPN_GetURLNotify or
 *	NPN_PostURLNotify.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

	/* ARGSUSED */
void
NPP_URLNotify(NPP Instance, const char *url, NPReason reason,
              void *notifyData)
{
    /*
     * NOT IMPLEMENTED YET.
     */
}
