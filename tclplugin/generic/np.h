/*
 * np.h --
 *
 *	Declarations of functions and entry points for the Tcl Netscape
 *	plugin.
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
 * Copyright (c) 2000 by Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) np.h 1.49 97/12/16 18:18:54
 * RCS:  @(#) $Id$
 */

#ifndef _NP
#define _NP

#include	"npconfig.h"

/*
 * Include the Tcl headers first, as we use the Tcl macros, functions and
 * types
 */

#include <tcl.h>

/*
 * Include the Tk headers for when we want to do in-process Tk:
 */

#include	<tk.h>

/*
 * System specific includes:
 */

#ifdef	XP_UNIX
#include	"../unix/npunix.h"
#endif

#ifdef	_WINDOWS
#include	"../win/npwin.h"
#endif

#ifdef	MAC_TCL
#include	"npmac.h"
#endif

/*
 * Netscape APIs (needs system specific headers)
 */

#include	"npapi.h"

/*
 * The following constant is used to tell Netscape that the plugin will
 * accept whatever amount of input is available on a stream.
 */

#define MAXINPUTSIZE		0X0FFFFFFF

/*
 * Define the name of the environment variable that will contain the
 * path to the Tcl plugin library.
 */

#define TCL_PLUGIN_DIR		"TCL_PLUGIN_DIR"

/*
 * Define the names of token tables used in the plugin:
 */

#define	NPTCL_INSTANCE		"npInstance"
#define NPTCL_STREAM		"npStream"

#ifdef NP_LOG
EXTERN void		NpLog _ANSI_ARGS_((CONST char *format, int arg1,
			    int arg2, int arg3));
EXTERN void		NpStartLog _ANSI_ARGS_((CONST char *filename));
EXTERN void		NpStopLog _ANSI_ARGS_((void));
#else
#define NpLog(f, a1, a2, a3)
#define NpStartLog(f)
#define NpStopLog()
#endif

/*
 * For the Mac, we need to make sure the Tcl_Evals are all
 * done in the plugin thread, so we wrap Tcl_Eval in Np_Eval.
 *
 * However, we cannot call the NPN_ functions from the Tcl
 * thread, so we have to wrap the calls in the pn Tcl commands,
 * to run them in the main thread...
 *
 * For Unix & Windows this is irrelevant...
 */

#ifdef MAC_TCL
    EXTERN int 		Np_Eval _ANSI_ARGS_((Tcl_Interp *interp, char *string));
    EXTERN int 		Np_EvalObj _ANSI_ARGS_((Tcl_Interp *interp, Tcl_Obj *objPtr));
    

    EXTERN void        	Np_NPN_Status(NPP instance, const char* message);
    EXTERN NPError     	Np_NPN_NewStream(NPP instance, NPMIMEType type,
				const char* target, NPStream** stream);
    EXTERN int32        Np_NPN_Write(NPP instance, NPStream* stream, int32 len,
				void* buffer);
    EXTERN NPError    	Np_NPN_DestroyStream(NPP instance, NPStream* stream,
				NPReason reason);
    EXTERN NPError     	Np_NPN_GetURL(NPP instance, const char* url,
				const char* target);

    EXTERN NPError     	Np_NPN_PostURL(NPP instance, const char* url,
				const char* target, uint32 len,
				const char* buf, NPBool file);

    EXTERN void        	Np_NPN_Version(int* plugin_major, int* plugin_minor,
			        int* netscape_major, int* netscape_minor);
    EXTERN const char* 	Np_NPN_UserAgent(NPP instance);

#else 
    #define Np_Eval 		Tcl_Eval
    #define Np_EvalObj 		Tcl_EvalObj
    #define Np_NPN_Status 	NPN_Status
    #define Np_NPN_NewStream 	NPN_NewStream
    #define Np_NPN_Write 	NPN_Write
    #define Np_NPN_DestroyStream NPN_DestroyStream
    #define Np_NPN_GetURL 	NPN_GetURL
    #define Np_NPN_PostURL 	NPN_PostURL
    #define Np_NPN_UserAgent 	NPN_UserAgent
    #define Np_NPN_Version 	NPN_Version
#endif


/*
 * Procedures shared between various modules in the plugin:
 */

EXTERN void		NpDeleteTokenTables _ANSI_ARGS_((Tcl_Interp *interp));
EXTERN void		NpDestroyMainInterp _ANSI_ARGS_((void));
EXTERN int		NpEnter _ANSI_ARGS_((CONST char *msg));
EXTERN char     	*NpGetTokenName _ANSI_ARGS_((ClientData clientData,
			    Tcl_Interp *interp, char *tableName));
EXTERN int		NpGetAndCheckToken _ANSI_ARGS_((Tcl_Interp *interp,
			    char *token, char *tableName,
			    ClientData *clientDataPtr));
EXTERN Tcl_Interp	*NpGetMainInterp _ANSI_ARGS_((void));
EXTERN Tcl_Interp 	*NpCreateMainInterp _ANSI_ARGS_((void));
EXTERN int		NpInit _ANSI_ARGS_((Tcl_Interp *interp));
EXTERN void		NpInitTokenTables _ANSI_ARGS_((Tcl_Interp *interp));
EXTERN void		NpLeave _ANSI_ARGS_((CONST char *msg,
	                    int oldMode));
EXTERN void		NpPanic _ANSI_ARGS_((char *msg));
EXTERN int		NpPlatformInit _ANSI_ARGS_((Tcl_Interp *interp,
			    int externalFlag));
EXTERN void		NpPlatformDestroy _ANSI_ARGS_((NPP This));
EXTERN char *		NpPlatformFindTcl _ANSI_ARGS_((char *minVer, int exact,
			    int dbgOnly));
EXTERN void		NpPlatformMsg _ANSI_ARGS_((char *msg, char *title));
EXTERN void		NpPlatformNew _ANSI_ARGS_((NPP instance));
EXTERN void		NpPlatformSetWindow _ANSI_ARGS_((NPP This,
        		    NPWindow *window));
EXTERN void		NpPlatformShutdown _ANSI_ARGS_((void));
EXTERN void		NpRegisterToken _ANSI_ARGS_((ClientData clientData,
			    Tcl_Interp *interp, char *tokenTableID));
EXTERN void		NpShutdown _ANSI_ARGS_((Tcl_Interp *interp));
EXTERN void		NpUnregisterToken _ANSI_ARGS_((Tcl_Interp *interp,
			    char *token, char *tokenTableID));

EXTERN int		Plug_Init _ANSI_ARGS_((Tcl_Interp *interp,
	                    int inBrowserFlag));
EXTERN int		PnInit _ANSI_ARGS_((Tcl_Interp *interp));
EXTERN int		PnSafeInit _ANSI_ARGS_((Tcl_Interp *interp));
EXTERN int		PnTkInit _ANSI_ARGS_((Tcl_Interp *interp));
EXTERN int		PnTkSafeInit _ANSI_ARGS_((Tcl_Interp *interp));


EXTERN int streams;

#endif /* _NP */
