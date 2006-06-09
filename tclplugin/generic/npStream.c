/* 
 * npstream.c --
 *
 *	Implements the functions used to get URLs loaded from Navigator
 *	into the plugin, and functions that implement commands to request
 *	that Navigator initiate loading of new URLs. 
 *
 * CONTACT:		tclplugin-core at lists.sourceforge.net
 *
 * ORIGINAL AUTHORS:	Jacob Levy, Laurent Demailly
 *
 * Please contact us directly for questions, comments and enhancements.
 *
 * Copyright (c) 1996-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 * Copyright (c) 2002-2006 ActiveState Software Inc.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS:  @(#) $Id$
 */

#include "np.h"

/*
 * This could be thread-specific, but global is OK as well, and simplifies
 * acess to allow pre-Tcl-init and post-Tcl-shutdown.
 */
static int nptcl_streams = 0;

/*
 *----------------------------------------------------------------------
 *
 * NpTclStreams --
 *
 *	Accessor to static nptcl_streams.
 *
 * Results:
 *	Value of nptcl_streams.
 *
 * Side effects:
 *	modifies nptcl_streams.
 *
 *----------------------------------------------------------------------
 */

int
NpTclStreams(int incrVal)
{
    nptcl_streams += incrVal;
    return nptcl_streams;
}

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

NPError
NPP_NewStream(NPP instance, NPMIMEType type, NPStream *stream, NPBool seekable,
              uint16 *stype)
{
    int oldServiceMode;
    NPError rv = NPERR_NO_ERROR;
    Tcl_Interp *interp;
    Tcl_Obj *objPtr;

    if (instance == NULL) {
	NpLog(">>> NPP_NewStream NULL instance\n");
	return NPERR_INVALID_INSTANCE_ERROR;
    }

    oldServiceMode = NpEnter("NPP_NewStream");
    nptcl_streams++;

    interp = (Tcl_Interp *) instance->pdata;

    NpLog("NPP_NewStream(0x%x, %s, %s)\n", stream, stream->url, type);

    /*
     * Register the stream token so that we can later check for invalid
     * stream tokens from the browser.
     */
    
    NpRegisterToken((ClientData) stream, interp, NPTCL_STREAM);

    *stype = NP_NORMAL;

    objPtr = Tcl_NewObj();
    Tcl_ListObjAppendElement(NULL, objPtr,
	    Tcl_NewStringObj("npNewStream", -1));
    Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewLongObj((long) instance));
    Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewLongObj((long) stream));
    Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewStringObj(stream->url, -1));
    Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewStringObj(type, -1));
    Tcl_ListObjAppendElement(NULL, objPtr,
	    Tcl_NewIntObj((int) stream->lastmodified));
    Tcl_ListObjAppendElement(NULL, objPtr,
	    Tcl_NewIntObj((int) stream->end));
    
    Tcl_IncrRefCount(objPtr);
    if (Tcl_EvalObjEx(interp, objPtr, TCL_EVAL_GLOBAL|TCL_EVAL_DIRECT)
	    != TCL_OK) {
        NpPlatformMsg(Tcl_GetStringResult(interp), "npNewStream");
        rv = NPERR_GENERIC_ERROR;
    }

    Tcl_DecrRefCount(objPtr);
    NpLeave("NPP_NewStream", oldServiceMode);
    return rv;
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
int32
NPP_WriteReady(NPP instance, NPStream *stream)
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
int32
NPP_Write(NPP instance, NPStream *stream, int32 offset, int32 len, void *buffer)
{
    int oldServiceMode;
    ClientData dummy;
    Tcl_Interp *interp;
    Tcl_Obj *objPtr = NULL;

    if (instance == NULL) {
	NpLog(">>> NPP_Write NULL instance\n");
	return len;
    }

    oldServiceMode = NpEnter("NPP_Write");
    interp = (Tcl_Interp *) instance->pdata;

    Tcl_ResetResult(interp);

    /*
     * Check that we got a legal stream from the browser:
     */

    objPtr = Tcl_NewLongObj((long) stream);
    Tcl_IncrRefCount(objPtr);
    if (NpGetAndCheckToken(interp, objPtr, NPTCL_STREAM, &dummy) != TCL_OK) {
        NpPlatformMsg(Tcl_GetStringResult(interp), "NPP_Write");
        len = -1;
        goto end;
    }
    Tcl_DecrRefCount(objPtr);

    objPtr = Tcl_NewObj();
    Tcl_ListObjAppendElement(NULL, objPtr,
	    Tcl_NewStringObj("npWriteStream", -1));
    Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewLongObj((long) instance));
    Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewLongObj((long) stream));
    Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewIntObj((int) len));
    Tcl_ListObjAppendElement(NULL, objPtr,
	    Tcl_NewByteArrayObj((const unsigned char *) buffer, len));

    Tcl_IncrRefCount(objPtr);
    if (Tcl_EvalObjEx(interp, objPtr, TCL_EVAL_GLOBAL|TCL_EVAL_DIRECT)
	    != TCL_OK) {
        NpPlatformMsg(Tcl_GetStringResult(interp), "npWriteStream");
        len = -1;
    }

    end:
    if (objPtr) {
	Tcl_DecrRefCount(objPtr);
    }
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
NPError
NPP_DestroyStream(NPP instance, NPStream *stream, NPError reason)
{
    int oldServiceMode;
    NPError rv = NPERR_NO_ERROR;
    ClientData dummy;
    Tcl_Interp *interp;
    Tcl_Obj *objPtr = NULL;

    if (instance == NULL) {
	NpLog(">>> NPP_DestroyStream NULL instance\n");
	return NPERR_INVALID_INSTANCE_ERROR;
    }

    oldServiceMode = NpEnter("NPP_DestroyStream");
    interp = (Tcl_Interp *) instance->pdata;
    Tcl_ResetResult(interp);

    /*
     * Check that we got a legal stream from the browser:
     */
    
    objPtr = Tcl_NewLongObj((long) stream);
    Tcl_IncrRefCount(objPtr);
    if (NpGetAndCheckToken(interp, objPtr, NPTCL_STREAM, &dummy) != TCL_OK) {
	NpPlatformMsg(Tcl_GetStringResult(interp), "NPP_DestroyStream");
	rv = NPERR_GENERIC_ERROR;
	goto error;
    }
    Tcl_DecrRefCount(objPtr);

    /*
     * Remove the stream from the token table.
     */

    NpLog("DESTROYING stream %p\n", stream);

    NpUnregisterToken(interp, (void *) stream, NPTCL_STREAM);

    /*
     * Prepare the stream close command for evaluation.
     */

    objPtr = Tcl_NewObj();
    Tcl_ListObjAppendElement(NULL, objPtr,
	    Tcl_NewStringObj("npDestroyStream", -1));
    Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewLongObj((long) instance));
    Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewLongObj((long) stream));
    switch (reason) {
	case NPRES_DONE:
	    Tcl_ListObjAppendElement(NULL, objPtr,
		    Tcl_NewStringObj("EOF", -1));
	    break;
	case NPRES_NETWORK_ERR:
	    Tcl_ListObjAppendElement(NULL, objPtr,
		    Tcl_NewStringObj("NETWORK_ERROR", -1));
	    break;
	case NPRES_USER_BREAK:
	    Tcl_ListObjAppendElement(NULL, objPtr,
		    Tcl_NewStringObj("USER_BREAK", -1));
	    break;
	default:
	    Tcl_ListObjAppendElement(NULL, objPtr,
		    Tcl_NewStringObj("UNKOWN", -1));
	    break;
    }

    Tcl_IncrRefCount(objPtr);
    if (Tcl_EvalObjEx(interp, objPtr, TCL_EVAL_GLOBAL|TCL_EVAL_DIRECT)
	    != TCL_OK) {
	NpPlatformMsg(Tcl_GetStringResult(interp), "npDestroyStream");
	rv = NPERR_GENERIC_ERROR;
    }

error:
    if (objPtr) {
	Tcl_DecrRefCount(objPtr);
    }
    nptcl_streams--;
    NpLeave("NPP_DestroyStream", oldServiceMode);
    return rv;
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
void
NPP_StreamAsFile(NPP instance, NPStream *stream, const char *fname)
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
