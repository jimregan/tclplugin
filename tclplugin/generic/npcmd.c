/* 
 * npcmd.c --
 *
 *	This file contains implementations of commands that can be
 *	called from the plugin stub to perform specialized operations
 *	on the hosting browser. 
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
 * SCCS: @(#) npcmd.c 1.31 97/10/06 20:12:37
 */

#include	"np.h"

/*
 * Command functions:
 */

static int		PnCloseStreamCmd _ANSI_ARGS_((
			    ClientData clientData, Tcl_Interp *interp,
                            int argc, char **argv));
static int		PnDisplayStatusCmd _ANSI_ARGS_((
			    ClientData clientData, Tcl_Interp *interp,
                            int argc, char **argv));
static int		PnWriteToStreamObjCmd _ANSI_ARGS_((
                            ClientData dummy, Tcl_Interp *interp,
			    int objc, Tcl_Obj *CONST objv[]));
static int		PnGetURLCmd _ANSI_ARGS_((
			    ClientData clientData, Tcl_Interp *interp,
                            int argc, char **argv));
static int		PnOpenStreamCmd _ANSI_ARGS_((
			    ClientData clientData, Tcl_Interp *interp,
                            int argc, char **argv));
static int		PnPostURLObjCmd _ANSI_ARGS_((
			    ClientData dummy, Tcl_Interp *interp,
                            int objc, Tcl_Obj *CONST objv[]));
static int		PnUserAgentCmd _ANSI_ARGS_((
			    ClientData clientData, Tcl_Interp *interp,
                            int argc, char **argv));
static int		PnVersionCmd _ANSI_ARGS_((
			    ClientData clientData, Tcl_Interp *interp,
                            int argc, char **argv));

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
    ClientData	clientData,
    Tcl_Interp	*interp,
    int argc,
    char **argv)
{
    NPP instance;

    NpLog("Entering PnDisplayStatus\n", 0, 0, 0);
    
    if (argc != 3) {
        Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
                " instanceToken message\"", (char *) NULL);
        NpLog("Leaving PnDisplayStatus with num args error\n", 0, 0, 0);
        return TCL_ERROR;
    }

    if (NpGetAndCheckToken(interp, argv[1], NPTCL_INSTANCE,
            (ClientData *) &instance) != TCL_OK) {
        NpLog("Leaving PnDisplayStatus with instance error\n", 0, 0, 0);
        return TCL_ERROR;
    }

    NPN_Status(instance, (const char *) argv[2]);

    NpLog("Leaving Status: %s\n", (int) argv[2], 0, 0);
    
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
    ClientData	clientData,
    Tcl_Interp	*interp,
    int argc,
    char **argv)
{
    NPP instance;
    NPStream *streamPtr;
    int status;

    NpLog("Entering PnOpenStream\n", 0, 0, 0);
    
    if (argc != 4) {
        Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
                " instanceToken mimeType frameName\"", (char *) NULL);
        NpLog("Leaving PnOpenStream with num args error\n", 0, 0, 0);
        return TCL_ERROR;
    }
    
    if (NpGetAndCheckToken(interp, argv[1], NPTCL_INSTANCE,
            (ClientData *) &instance) != TCL_OK) {
        NpLog("Leaving PnOpenStream with instance error\n", 0, 0, 0);
        return TCL_ERROR;
    }

    /*
     * We assume that the Tcl code already checked that a stream to the
     * requested frame does not yet exist. It should not have called us
     * if this is the case.
     */

    status = NPN_NewStream(instance, argv[2], argv[3], &streamPtr);
    if (status != NPERR_NO_ERROR) {
        Tcl_AppendResult(interp, "could not open stream of type \"",
                argv[2], "\" to \"", argv[3], "\"", (char *) NULL);
        NpLog("Leaving PnOpenStream with new stream error\n", 0, 0, 0);
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

    streams++;

    /*
     * Return the token name to the Tcl code:
     */

    Tcl_AppendResult(interp,
            NpGetTokenName((ClientData) streamPtr, interp, NPTCL_STREAM),
            (char *) NULL);
    
    NpLog("Leaving OpenStream type %s target %s --> 0x%x\n",
          (int) argv[2], (int) argv[3], (int) streamPtr);
    
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
PnWriteToStreamObjCmd(dummy, interp, objc, objv)
    ClientData dummy;		/* Not used. */
    Tcl_Interp *interp;		/* Current interpreter. */
    int objc;			/* Number of arguments. */
    Tcl_Obj *CONST objv[];	/* The argument objects. */
{
    NPStream *streamPtr;
    NPP instance;
    int len;
    char *dataPtr;
    
    NpLog("Entering PnWriteToStream\n", 0, 0, 0);
    
    if (objc != 4) {
	Tcl_WrongNumArgs(interp, 1, objv, 
		"instanceToken streamToken contents");
        NpLog("Leaving PnWriteToStream with num args error\n", 0, 0, 0);
        return TCL_ERROR;
    }
    
    if (NpGetAndCheckToken(interp, Tcl_GetStringFromObj(objv[1], NULL),
	    NPTCL_INSTANCE, (ClientData *) &instance) != TCL_OK) {
        NpLog("Leaving PnWriteToStream with instance token error\n", 0, 0, 0);
        return TCL_ERROR;
    }

    /*
     * Get the stream from its token:
     */

    if (NpGetAndCheckToken(interp, Tcl_GetStringFromObj(objv[2], NULL), 
	    NPTCL_STREAM, (ClientData *) &streamPtr) != TCL_OK) {
        NpLog("Leaving PnWriteToStream with stream token error\n", 0, 0, 0);
        return TCL_ERROR;
    }

    
    dataPtr = Tcl_GetStringFromObj(objv[3], &len);

    (void) NPN_Write(instance, streamPtr, len, dataPtr);

    NpLog("Leaving PnWriteToStream (%d) with success\n", len, 0, 0);
    
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
    ClientData	clientData,
    Tcl_Interp	*interp,
    int argc,
    char **argv)
{
    NPP instance;
    NPStream *streamPtr;
    int status;

    NpLog("Entering PnCloseStream\n", 0, 0, 0);

    if (argc != 3) {
        Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
                " instanceToken streamToken\"", (char *) NULL);
        NpLog("Leaving PnCloseStream with num args error\n", 0, 0, 0);
        return TCL_ERROR;
    }
    
    if (NpGetAndCheckToken(interp, argv[1], NPTCL_INSTANCE,
            (ClientData *) &instance) != TCL_OK) {
        NpLog("Leaving PnCloseStream with instance error\n", 0, 0, 0);
        return TCL_ERROR;
    }

    /*
     * Get the stream from its token:
     */

    if (NpGetAndCheckToken(interp, argv[2], NPTCL_STREAM,
            (ClientData *) &streamPtr) != TCL_OK) {
        NpLog("Leaving PnCloseStream with stream error\n", 0, 0, 0);
        return TCL_ERROR;
    }

    status = NPN_DestroyStream(instance, streamPtr, NPRES_DONE);
    if (status != NPERR_NO_ERROR) {
	Tcl_AppendResult(interp, "could not destroy stream \"",
		argv[2], "\"", (char *) NULL);
        NpLog("Leaving PnCloseStream with destroy stream error\n", 0, 0, 0);
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

    if (NpGetAndCheckToken(interp, argv[2], NPTCL_STREAM,
            (ClientData *) &streamPtr) == TCL_OK) {
        NpLog("Token for stream %s persists after call to NPN_DestroyStream",
                (int) argv[2], 0, 0);
    } else {

        /*
         * NpGetAndCheckToken sets the interpreter result to an error
         * message if it does not find the token, which is what we are
         * checking for; this means that we do not want the error message.
         */
        
        Tcl_ResetResult(interp);
    }

    NpLog("Leaving PnDestroyStream with success\n", 0, 0, 0);
    
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
    ClientData	clientData,
    Tcl_Interp	*interp,
    int argc,
    char **argv)
{
    NPP instance;
    char *targetName = NULL;
    
    NpLog("Entering PnGetUrl\n", 0, 0, 0);

    if ((argc != 3) && (argc != 4)) {
        Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
                " instanceToken URL ?target?\"", (char *) NULL);
        NpLog("Leaving PnGetUrl with num args error\n", 0, 0, 0);
        return TCL_ERROR;
    }

    if (NpGetAndCheckToken(interp, argv[1], NPTCL_INSTANCE,
            (ClientData *) &instance) != TCL_OK) {
        NpLog("Leaving PnGetUrl with instance error\n", 0, 0, 0);
        return TCL_ERROR;
    }
    
    if (argc == 4) {
        if (strlen(argv[3]) > 0) {
            targetName = argv[3];
        }
    }
    
    if (NPN_GetURL(instance, (const char *) argv[2], (const char *) targetName)
            != NPERR_NO_ERROR) {
        Tcl_AppendResult(interp, "could not get URL \"", argv[2],
                "\"", (char *) NULL);
        NpLog("Leaving PnGetUrl with get url error\n", 0, 0, 0);
        return TCL_ERROR;
    }
    
    NpLog("Leaving PnGetUrl with success\n", 0, 0, 0);

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
PnPostURLObjCmd(dummy, interp, objc, objv)
    ClientData dummy;		/* Not used. */
    Tcl_Interp *interp;		/* Current interpreter. */
    int objc;			/* Number of arguments. */
    Tcl_Obj *CONST objv[];	/* The argument objects. */
{
    NPP instance;
    int dataLen, len;
    int fromFile = FALSE;
    char *targetName, *url, *dataPtr;
    NPError status = NPERR_NO_ERROR;
    
    NpLog("Entering PnPostUrl\n", 0, 0, 0);

    if ((objc != 5) && (objc != 6)) {
        Tcl_WrongNumArgs(interp, 1, objv,
                "instanceToken URL target data ?fromFile?");
        NpLog("Leaving PnPostUrl with num args error\n", 0, 0, 0);
        return TCL_ERROR;
    }

    if (NpGetAndCheckToken(interp, Tcl_GetStringFromObj(objv[1], NULL),
	    NPTCL_INSTANCE, (ClientData *) &instance) != TCL_OK) {
        NpLog("Leaving PnPostUrl with instance error\n", 0, 0, 0);
        return TCL_ERROR;
    }

    dataPtr = Tcl_GetStringFromObj(objv[4], &dataLen);
    
    if ((objc == 6) &&
            (Tcl_GetBooleanFromObj(interp, objv[5], &fromFile) != TCL_OK)) {
        NpLog("Leaving PnPostUrl with boolean error\n", 0, 0, 0);
        return TCL_ERROR;
    }

    targetName = Tcl_GetStringFromObj(objv[3], &len);
    if (len == 0) {
        targetName = NULL;
    }
    url= Tcl_GetStringFromObj(objv[2], NULL);
    status= NPN_PostURL(instance, url, targetName, dataLen, dataPtr, fromFile);
    if (status != NPERR_NO_ERROR) {
        Tcl_AppendResult(interp, "could not post to URL \"", url,
                "\"", (char *) NULL);
        NpLog("Leaving PnPostUrl with url (%s) error (%d)\n", (int) url, 
		status, 0);
        return TCL_ERROR;
    }
    
    NpLog("Leaving PnPostUrl with success\n", 0, 0, 0);

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
    ClientData	clientData,
    Tcl_Interp	*interp,
    int argc,
    char **argv)
{
    NPP instance;
    char *userAgentPtr;

    NpLog("Entering PnUserAgent\n", 0, 0, 0);
    
    if (argc != 2) {
        Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
                " instanceToken\"", (char *) NULL);
        NpLog("Leaving PnUserAgent with num args error\n", 0, 0, 0);
        return TCL_ERROR;
    }

    if (NpGetAndCheckToken(interp, argv[1], NPTCL_INSTANCE,
            (ClientData *) &instance) != TCL_OK) {
        NpLog("Leaving PnUserAgent with instance error\n", 0, 0, 0);
        return TCL_ERROR;
    }
    
    userAgentPtr = (char *) NPN_UserAgent(instance);
    if (userAgentPtr == NULL) {
        if (interp != NULL) {
            Tcl_AppendResult(interp, "\"", argv[0], "\" failed",
                    (char *) NULL);
        }
        NpLog("Leaving PnUserAgent with user agent error\n", 0, 0, 0);
        return TCL_ERROR;
    }

    Tcl_AppendResult(interp, userAgentPtr, (char *) NULL);

    NpLog("Leaving PnUserAgent with success\n", 0, 0, 0);

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
    ClientData	clientData,
    Tcl_Interp	*interp,
    int argc,
    char **argv)
{
    int pMaj, pMin, bMaj, bMin;
    char buf[32];

    NpLog("Entering PnVersion\n", 0, 0, 0);
    
    NPN_Version(&pMaj, &pMin, &bMaj, &bMin);
    sprintf(buf, "%d", pMaj);
    Tcl_AppendElement(interp, buf);
    sprintf(buf, "%d", pMin);
    Tcl_AppendElement(interp, buf);
    sprintf(buf, "%d", bMaj);
    Tcl_AppendElement(interp, buf);
    sprintf(buf, "%d", bMin);
    Tcl_AppendElement(interp, buf);

    NpLog("Leaving PnVersion with success\n", 0, 0, 0);
    
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
    (void) Tcl_CreateCommand(interp, "pniStatus",
            PnDisplayStatusCmd, (ClientData) NULL, NULL);
    (void) Tcl_CreateCommand(interp, "pniOpenStream",
            PnOpenStreamCmd, (ClientData) NULL, NULL);
    (void) Tcl_CreateObjCommand(interp, "pniWriteToStream",
	    PnWriteToStreamObjCmd, (ClientData) 0, (Tcl_CmdDeleteProc *) NULL);
    (void) Tcl_CreateCommand(interp, "pniCloseStream",
            PnCloseStreamCmd, (ClientData) NULL, NULL);
    (void) Tcl_CreateCommand(interp, "pniGetURL",
            PnGetURLCmd, (ClientData) NULL, NULL);
    (void) Tcl_CreateObjCommand(interp, "pniPostURL",
	    PnPostURLObjCmd, (ClientData) 0, (Tcl_CmdDeleteProc *) NULL);
    (void) Tcl_CreateCommand(interp, "pniUserAgent",
            PnUserAgentCmd, (ClientData) NULL, NULL);
    (void) Tcl_CreateCommand(interp, "pniApiVersion",
            PnVersionCmd, (ClientData) NULL, NULL);
    
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
PnSafeInit(interp)
    Tcl_Interp *interp;
{
    Tcl_AppendResult(interp,
            "The pni package can not be loaded into a safe interpreter",
            (char *) NULL);
    
    return TCL_ERROR;
}
