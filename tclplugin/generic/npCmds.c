/* 
 * npcmd.c --
 *
 *	This file contains implementations of commands that can be
 *	called from the plugin stub to perform specialized operations
 *	on the hosting browser. 
 *
 * CONTACT:		tclplugin-core@lists.sourceforge.net
 *
 * ORIGINAL AUTHORS:	Jacob Levy			Laurent Demailly
 *
 * Please contact us directly for questions, comments and enhancements.
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

#include	"np.h"

/*
 * Command functions:
 */

static int		PnCloseStreamCmd _ANSI_ARGS_((
                            ClientData dummy, Tcl_Interp *interp,
			    int objc, Tcl_Obj *CONST objv[]));
static int		PnDisplayStatusCmd _ANSI_ARGS_((
                            ClientData dummy, Tcl_Interp *interp,
			    int objc, Tcl_Obj *CONST objv[]));
static int		PnWriteToStreamObjCmd _ANSI_ARGS_((
                            ClientData dummy, Tcl_Interp *interp,
			    int objc, Tcl_Obj *CONST objv[]));
static int		PnGetURLCmd _ANSI_ARGS_((
                            ClientData dummy, Tcl_Interp *interp,
			    int objc, Tcl_Obj *CONST objv[]));
static int		PnOpenStreamCmd _ANSI_ARGS_((
                            ClientData dummy, Tcl_Interp *interp,
			    int objc, Tcl_Obj *CONST objv[]));
static int		PnPostURLObjCmd _ANSI_ARGS_((
			    ClientData dummy, Tcl_Interp *interp,
                            int objc, Tcl_Obj *CONST objv[]));
static int		PnUserAgentCmd _ANSI_ARGS_((
			    ClientData clientData, Tcl_Interp *interp,
			    int objc, Tcl_Obj *CONST objv[]));
static int		PnVersionCmd _ANSI_ARGS_((
			    ClientData clientData, Tcl_Interp *interp,
			    int objc, Tcl_Obj *CONST objv[]));

/*
 *----------------------------------------------------------------------
 *
 * PnDisplayStatusCmd --
 *
 *	Display a message in the status line.
 *
 * Results:
 *	A standard Tcl result.
 *
 * Side effects:
 *	Displays a message in the status line.
 *
 *----------------------------------------------------------------------
 */

static int
PnDisplayStatusCmd(
    ClientData dummy,		/* Not used. */
    Tcl_Interp *interp,		/* Current interpreter. */
    int objc,			/* Number of arguments. */
    Tcl_Obj *CONST objv[]	/* The argument objects. */
    )
{
    NPP instance;

    NpLog("ENTERING PnDisplayStatus\n");

    if (objc != 3) {
	Tcl_WrongNumArgs(interp, 1, objv, "instance message");
        NpLog("LEAVING PnDisplayStatus with num args error\n");
        return TCL_ERROR;
    }

    if (NpGetAndCheckToken(interp, objv[1], NPTCL_INSTANCE,
            (ClientData *) &instance) != TCL_OK) {
        NpLog("LEAVING PnDisplayStatus with instance error\n");
        return TCL_ERROR;
    }

    NPN_Status(instance, (const char *) Tcl_GetString(objv[2]));

    NpLog("LEAVING Status: %s\n", Tcl_GetString(objv[2]));

    return TCL_OK;
}

/*
 *----------------------------------------------------------------------
 *
 * PnOpenStreamCmd --
 *
 *	Opens a new stream (to an existing or new frame).
 *
 * Results:
 *	A standard Tcl result. The interpreter result contains the
 *	token name of the new stream.
 *
 * Side effects:
 *	May create a new frame.
 *
 *----------------------------------------------------------------------
 */

static int
PnOpenStreamCmd(
    ClientData dummy,		/* Not used. */
    Tcl_Interp *interp,		/* Current interpreter. */
    int objc,			/* Number of arguments. */
    Tcl_Obj *CONST objv[]	/* The argument objects. */
    )
{
    NPP instance;
    char *mtype, *frame;
    NPStream *streamPtr;
    int status;

    NpLog("ENTERING PnOpenStream\n");
    
    if (objc != 4) {
	Tcl_WrongNumArgs(interp, 1, objv, "instance mimeType frameName");
        NpLog("Leaving PnOpenStream with num args error\n");
        return TCL_ERROR;
    }
    
    if (NpGetAndCheckToken(interp, objv[1], NPTCL_INSTANCE,
            (ClientData *) &instance) != TCL_OK) {
        NpLog("LEAVING PnOpenStream with instance error\n");
        return TCL_ERROR;
    }

    /*
     * We assume that the Tcl code already checked that a stream to the
     * requested frame does not yet exist. It should not have called us
     * if this is the case.
     */

    mtype = (char *) Tcl_GetString(objv[2]);
    frame = (char *) Tcl_GetString(objv[3]);
    status = NPN_NewStream(instance, mtype, frame, &streamPtr);
    if (status != NPERR_NO_ERROR) {
        Tcl_AppendResult(interp, "could not open stream of type \"",
                mtype, "\" to \"", frame, "\"", (char *) NULL);
        NpLog("LEAVING PnOpenStream with new stream error\n");
        return TCL_ERROR;
    }

    /*
     * The operation succeeded, so we return the address of the new
     * stream in the interpreter result. We register the token in the
     * stream table.
     */

    NpRegisterToken((ClientData) streamPtr, interp, NPTCL_STREAM);

    /*
     * Increment the count of open streams so that NPP_DestroyStream
     * calls can be matched up.
     */

    NpTclStreams(1);

    /*
     * Return the token name to the Tcl code:
     */

    Tcl_SetObjResult(interp, Tcl_NewLongObj((long) streamPtr));

    NpLog("LEAVING OpenStream type %s target %s --> 0x%x\n",
	    mtype, frame, streamPtr);

    return TCL_OK;    
}

/*
 *----------------------------------------------------------------------
 *
 * PnWriteToStreamObjCmd --
 *
 *	Writes data to a named stream in the hosting browser.
 *
 * Results:
 *	A standard Tcl result.
 *
 * Side effects:
 *	Causes the hosting browser to display the data in a frame.
 *
 *----------------------------------------------------------------------
 */

static int
PnWriteToStreamObjCmd(
    ClientData dummy,		/* Not used. */
    Tcl_Interp *interp,		/* Current interpreter. */
    int objc,			/* Number of arguments. */
    Tcl_Obj *CONST objv[]	/* The argument objects. */
    )
{
    NPStream *streamPtr;
    NPP instance;
    int len;
    char *dataPtr;

    NpLog("Entering PnWriteToStream\n");
    
    if (objc != 4) {
	Tcl_WrongNumArgs(interp, 1, objv,
		"instance stream contents");
        NpLog("Leaving PnWriteToStream with num args error\n");
        return TCL_ERROR;
    }

    if (NpGetAndCheckToken(interp, objv[1], NPTCL_INSTANCE,
		(ClientData *) &instance) != TCL_OK) {
        NpLog("Leaving PnWriteToStream with instance token error\n");
        return TCL_ERROR;
    }

    /*
     * Get the stream from its token:
     */

    if (NpGetAndCheckToken(interp, objv[2], NPTCL_STREAM,
		(ClientData *) &streamPtr) != TCL_OK) {
        NpLog("Leaving PnWriteToStream with stream token error\n");
        return TCL_ERROR;
    }

    
    dataPtr = Tcl_GetStringFromObj(objv[3], &len);

    (void) NPN_Write(instance, streamPtr, len, dataPtr);

    NpLog("Leaving PnWriteToStream (%d) with success\n", len);
    
    return TCL_OK;
}

/*
 *----------------------------------------------------------------------
 *
 * PnCloseStreamCmd --
 *
 *	Closes a stream (to a frame).
 *
 * Results:
 *	A standard Tcl result.
 *
 * Side effects:
 *	May make output actually appear (flushes in the frame).
 *
 *----------------------------------------------------------------------
 */

static int
PnCloseStreamCmd(
    ClientData dummy,		/* Not used. */
    Tcl_Interp *interp,		/* Current interpreter. */
    int objc,			/* Number of arguments. */
    Tcl_Obj *CONST objv[]	/* The argument objects. */
    )
{
    NPP instance;
    NPStream *streamPtr;
    int status;

    NpLog("ENTERING PnCloseStream\n");

    if (objc != 3) {
	Tcl_WrongNumArgs(interp, 1, objv, "instance stream");
        NpLog("LEAVING PnCloseStream with num args error\n");
        return TCL_ERROR;
    }
    
    if (NpGetAndCheckToken(interp, objv[1], NPTCL_INSTANCE,
            (ClientData *) &instance) != TCL_OK) {
        NpLog("LEAVING PnCloseStream with instance error\n");
        return TCL_ERROR;
    }

    /*
     * Get the stream from its token:
     */

    if (NpGetAndCheckToken(interp, objv[2], NPTCL_STREAM,
            (ClientData *) &streamPtr) != TCL_OK) {
        NpLog("LEAVING PnCloseStream with stream error\n");
        return TCL_ERROR;
    }

    status = NPN_DestroyStream(instance, streamPtr, NPRES_DONE);
    if (status != NPERR_NO_ERROR) {
	Tcl_AppendResult(interp, "could not destroy stream \"",
		Tcl_GetString(objv[2]), "\"", (char *) NULL);
        NpLog("LEAVING PnCloseStream with destroy stream error\n");
	return TCL_ERROR;
    }

    /*
     * We should not call NpUnregisterToken here because it was called
     * already from NPP_DestroyStream which was called immediately in
     * response to our call to NPN_DestroyStream. We ensure that this
     * indeed happened by checking for the token here and panicking if
     * it is still found:
     *
     * NOTE: We also do not have to decrement the stream counter because
     * that is also done in NPP_DestroyStream.
     */

    if (NpGetAndCheckToken(interp, objv[2], NPTCL_STREAM,
            (ClientData *) &streamPtr) == TCL_OK) {
        NpLog("Token for stream %s persists after call to NPN_DestroyStream\n",
                Tcl_GetString(objv[2]));
    } else {
        /*
         * NpGetAndCheckToken sets the interpreter result to an error
         * message if it does not find the token, which is what we are
         * checking for; this means that we do not want the error message.
         */
        
        Tcl_ResetResult(interp);
    }

    NpLog("LEAVING PnDestroyStream with success\n");
    
    return TCL_OK;
}

/*
 *----------------------------------------------------------------------
 *
 * PnGetURLCmd --
 *
 *	Requests a new stream from a URL from Navigator.
 *
 * Results:
 *	A standard Tcl result.
 *
 * Side effects:
 *	The new stream is (eventually) sent to the plugin.
 *
 *----------------------------------------------------------------------
 */

static int
PnGetURLCmd(
    ClientData dummy,		/* Not used. */
    Tcl_Interp *interp,		/* Current interpreter. */
    int objc,			/* Number of arguments. */
    Tcl_Obj *CONST objv[]	/* The argument objects. */
    )
{
    NPP instance;
    CONST84 char *url, *frame = NULL;

    NpLog("ENTERING PnGetUrl\n");

    if ((objc != 3) && (objc != 4)) {
	Tcl_WrongNumArgs(interp, 1, objv, "instance url ?target?");
	NpLog("LEAVING PnGetUrl with num args error\n");
	return TCL_ERROR;
    }

    if (NpGetAndCheckToken(interp, objv[1], NPTCL_INSTANCE,
	    (ClientData *) &instance) != TCL_OK) {
	NpLog("LEAVING PnGetUrl with instance error\n");
	return TCL_ERROR;
    }

    url = Tcl_GetString(objv[2]);
    if (objc == 4) {
	frame = Tcl_GetString(objv[3]);
    }
    
    if (NPN_GetURL(instance, (const char *) url, (const char *) frame)
	    != NPERR_NO_ERROR) {
	Tcl_AppendResult(interp, "could not get URL \"", url, "\"",
		(char *) NULL);
	NpLog("LEAVING PnGetUrl with get url error\n");
	return TCL_ERROR;
    }

    NpLog("LEAVING PnGetUrl with success\n");

    return TCL_OK;
}

/*
 *----------------------------------------------------------------------
 *
 * PnPostURLObjCmd --
 *
 *	Posts a file or given chunk of data to a given URL using
 *	Navigator as the HTTP client.
 *
 * Results:
 *	A standard Tcl result.
 *
 * Side effects:
 *	The file or data is sent to an HTTP server.
 *
 * NOTE: Due to bugs in Navigator, we will probably always be posting from
 *	 a file. We rely on the caller to delete the file when we return,
 *	 if they desire. Netscape is supposed to delete the file itself.
 *
 *----------------------------------------------------------------------
 */

static int
PnPostURLObjCmd(
    ClientData dummy,		/* Not used. */
    Tcl_Interp *interp,		/* Current interpreter. */
    int objc,			/* Number of arguments. */
    Tcl_Obj *CONST objv[]	/* The argument objects. */
    )
{
    NPP instance;
    int dataLen, len;
    int fromFile = FALSE;
    char *frame, *url, *dataPtr;
    NPError status = NPERR_NO_ERROR;
    
    NpLog("Entering PnPostUrl\n");

    if ((objc != 5) && (objc != 6)) {
	Tcl_WrongNumArgs(interp, 1, objv,
		"instance URL target data ?fromFile?");
	NpLog("Leaving PnPostUrl with num args error\n");
	return TCL_ERROR;
    }

    if (NpGetAndCheckToken(interp, objv[1], NPTCL_INSTANCE,
		(ClientData *) &instance) != TCL_OK) {
	NpLog("Leaving PnPostUrl with instance error\n");
	return TCL_ERROR;
    }

    dataPtr = Tcl_GetStringFromObj(objv[4], &dataLen);
    
    if ((objc == 6) &&
	    (Tcl_GetBooleanFromObj(interp, objv[5], &fromFile) != TCL_OK)) {
	NpLog("Leaving PnPostUrl with boolean error\n");
	return TCL_ERROR;
    }

    frame = Tcl_GetStringFromObj(objv[3], &len);
    if (len == 0) {
	frame = NULL;
    }
    url = Tcl_GetStringFromObj(objv[2], NULL);
    status = NPN_PostURL(instance, (const char *) url, (const char *) frame,
	    dataLen, (const char *) dataPtr, (NPBool) fromFile);
    if (status != NPERR_NO_ERROR) {
	Tcl_AppendResult(interp, "could not post to URL \"", url, "\"",
		(char *) NULL);
	NpLog("Leaving PnPostUrl with url (%s) error (%d)\n", url, status);
	return TCL_ERROR;
    }
    
    NpLog("Leaving PnPostUrl with success\n");

    return TCL_OK;
}

/*
 *----------------------------------------------------------------------
 *
 * PnUserAgentCmd --
 *
 *	Gets a string containing the browser "user agent" field.
 *	This identifies the hosting browser and is sent as part of
 *	all HTTP requests.
 *
 * Results:
 *	A standard Tcl result. Also returns the string in interp->result.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

static int
PnUserAgentCmd(
    ClientData dummy,		/* Not used. */
    Tcl_Interp *interp,		/* Current interpreter. */
    int objc,			/* Number of arguments. */
    Tcl_Obj *CONST objv[]	/* The argument objects. */
    )
{
    NPP instance;
    char *userAgentPtr;

    NpLog("ENTERING PnUserAgent\n");
    
    if (objc != 2) {
	Tcl_WrongNumArgs(interp, 1, objv, "instance");
	NpLog("LEAVING PnUserAgent with num args error\n");
	return TCL_ERROR;
    }

    if (NpGetAndCheckToken(interp, objv[1], NPTCL_INSTANCE,
	    (ClientData *) &instance) != TCL_OK) {
	NpLog("LEAVING PnUserAgent with instance error\n");
	return TCL_ERROR;
    }

    userAgentPtr = (char *) NPN_UserAgent(instance);
    if (userAgentPtr == NULL) {
#if 0
	Tcl_AppendResult(interp, "failed to retrieve useragent",
		(char *) NULL);
	NpLog("LEAVING PnUserAgent with user agent error\n");
	return TCL_ERROR;
#else
	userAgentPtr = "unknown";
#endif
    }

    Tcl_AppendResult(interp, userAgentPtr, (char *) NULL);
    NpLog("LEAVING PnUserAgent OK '%s'\n", userAgentPtr);
    return TCL_OK;
}

/*
 *----------------------------------------------------------------------
 *
 * PnVersionCmd --
 *
 *	Gets version information about the plugin API in use (what the
 *	plugin was compiled with) and the browser API in use (what the
 *	hosting browser supplies). Computes a list of four elements:
 *	- the first two elements are the plugin major and minor API numbers.
 *	- the second two elements are the browser major and minor API numbers.
 *
 * Results:
 *	A standard Tcl result. The interp->result field will contain a list
 *	of the above four elements, if the operation was successful.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

static int
PnVersionCmd(
    ClientData dummy,		/* Not used. */
    Tcl_Interp *interp,		/* Current interpreter. */
    int objc,			/* Number of arguments. */
    Tcl_Obj *CONST objv[]	/* The argument objects. */
    )
{
    int pMaj, pMin, bMaj, bMin;
    Tcl_Obj *objPtr;

    NpLog("ENTERING PnVersion\n");

    /*
     * Ignore arguments
     */
    NPN_Version(&pMaj, &pMin, &bMaj, &bMin);

    objPtr = Tcl_NewObj();
    Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewIntObj(pMaj));
    Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewIntObj(pMin));
    Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewIntObj(bMaj));
    Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewIntObj(bMin));
    Tcl_SetObjResult(interp, objPtr);

    NpLog("LEAVING PnVersion with success\n");
    return TCL_OK;
}

/*
 *----------------------------------------------------------------------
 *
 * PnInit --
 *
 *	Adds commands implemented in this file to an interpreter.
 *
 * Results:
 *	A standard Tcl result.
 *
 * Side effects:
 *	Adds commands to an interpreter.
 *
 *----------------------------------------------------------------------
 */

int
PnInit(Tcl_Interp *interp)
{
    (void) Tcl_CreateObjCommand(interp, "pniStatus",
            PnDisplayStatusCmd, (ClientData) NULL, NULL);
    (void) Tcl_CreateObjCommand(interp, "pniOpenStream",
            PnOpenStreamCmd, (ClientData) NULL, NULL);
    (void) Tcl_CreateObjCommand(interp, "pniWriteToStream",
	    PnWriteToStreamObjCmd, (ClientData) 0, NULL);
    (void) Tcl_CreateObjCommand(interp, "pniCloseStream",
            PnCloseStreamCmd, (ClientData) NULL, NULL);
    (void) Tcl_CreateObjCommand(interp, "pniGetURL",
            PnGetURLCmd, (ClientData) NULL, NULL);
    (void) Tcl_CreateObjCommand(interp, "pniPostURL",
	    PnPostURLObjCmd, (ClientData) NULL, NULL);
    (void) Tcl_CreateObjCommand(interp, "pniUserAgent",
            PnUserAgentCmd, (ClientData) NULL, NULL);
    (void) Tcl_CreateObjCommand(interp, "pniApiVersion",
            PnVersionCmd, (ClientData) NULL, NULL);
    
    Tcl_StaticPackage(interp, "pni", PnInit, PnSafeInit);

    return TCL_OK;
}

/*
 *----------------------------------------------------------------------
 *
 * PnSafeInit --
 *
 *	Safe entry point for pni static package.
 *
 * Results:
 *	Always TCL_ERROR, because the Pni package can not be loaded into
 *	a safe interpreter. Also leaves an error message in the result
 *	of interp.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

int
PnSafeInit(Tcl_Interp *interp)
{
    Tcl_AppendResult(interp,
            "The pni package cannot be loaded into a safe interpreter",
            (char *) NULL);
    
    return TCL_ERROR;
}
