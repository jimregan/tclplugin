/*
 * np.h --
 *
 *	Declarations of functions and entry points for the Tcl Netscape
 *	plugin.
 *
 * CONTACT:		tclplugin-core@lists.sourceforge.net
 *
 * Copyright (c) 1996-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 * Copyright (c) 2002 ActiveState Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS:  @(#) $Id$
 */

#ifndef _NP
#define _NP

#include <tk.h>

#ifdef WIN32

#  include <windows.h>

#  define HAVE_UNISTD_H 1

#  ifndef	F_OK
#    define	F_OK	0
#  endif

EXTERN void *NpWinLoadDll(char *libname);

#elif defined(MAC_TCL)

#  include <stdio.h>

#  define HIBYTE(i) (i >> 8)
#  define LOBYTE(i) (i & 0xff)

#  define HAVE_UNISTD_H 1
#  if HAVE_UNISTD_H
#	include <types.h>
#	include <unistd.h>
#  endif

#  include <tkInt.h>
#  include <tkMacInt.h>
#  include <Quickdraw.h>

#  include <Threads.h>

#  define TCL_THREAD_STACK_SIZE (256*1024)

int	NpMacServiceNpScript(void);
void	NpMacWakeUpTclThread(int serviceMode);
void 	NpMacDoACompleteEval(int serviceMode);

EXTERN ThreadID gTclThread;     /* The ThreadID of the Tcl thread */
EXTERN ThreadID gMainThread;    /* The ThreadID of the thread we started in */

#else /* UNIX */

#  include <stdio.h>

#  define HIBYTE(i) (i >> 8)
#  define LOBYTE(i) (i & 0xff)

#  if HAVE_UNISTD_H
#	include <sys/types.h>
#	include <unistd.h>
#  endif

/*
 * Shared functions:
 */

EXTERN void		NpXtStopNotifier _ANSI_ARGS_((void));

#endif /* PLATFORM DEFS */

/*
 * Tcl Plugin version identifiers
 * (the 3 strings are computed from the 4 internal numbers)
 */
#define NPTCL_VERSION		"3.0"
#define NPTCL_PATCH_LEVEL	"3.0a1"
#define NPTCL_INTERNAL_VERSION	"3.0.0.1"

#define NPTCL_MAJOR_VERSION	3
#define NPTCL_MINOR_VERSION	0
#define NPTCL_RELEASE_LEVEL	0
#define NPTCL_RELEASE_SERIAL	1

#ifdef BUILD_nptcl
#undef TCL_STORAGE_CLASS
#define TCL_STORAGE_CLASS DLLEXPORT
#endif /* BUILD_nptcl */

/*
 * Tcl/Tk 8.4 introduced better CONST-ness in the APIs, but we use CONST84 in
 * some cases for compatibility with earlier Tcl headers to prevent warnings.
 */
#ifndef CONST84
#  define CONST84
#endif

/*
 * Netscape APIs (needs system specific headers)
 */

#include "npapi.h"

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
#ifndef NP_LOG_FILENAME
#   define NP_LOG_FILENAME "nplog.txt"
#endif
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
#   define Np_Eval 		Tcl_Eval
#   define Np_EvalObj 		Tcl_EvalObj
#   define Np_NPN_Status 	NPN_Status
#   define Np_NPN_NewStream 	NPN_NewStream
#   define Np_NPN_Write 	NPN_Write
#   define Np_NPN_DestroyStream NPN_DestroyStream
#   define Np_NPN_GetURL 	NPN_GetURL
#   define Np_NPN_PostURL 	NPN_PostURL
#   define Np_NPN_UserAgent 	NPN_UserAgent
#   define Np_NPN_Version 	NPN_Version
#endif


/*
 * Procedures shared between various modules in the plugin:
 */

/*
 * nptcl.c
 */
extern int		NpInit _ANSI_ARGS_((Tcl_Interp *interp));
extern void		NpShutdown _ANSI_ARGS_((Tcl_Interp *interp));

/*
 * npinterp.c
 */
extern void		NpDestroyMainInterp _ANSI_ARGS_((void));
extern Tcl_Interp	*NpGetMainInterp _ANSI_ARGS_((void));
extern Tcl_Interp	*NpCreateMainInterp _ANSI_ARGS_((void));

/*
 * npstream.c
 */
extern int		NpTclStreams _ANSI_ARGS_((int incrVal));
extern int		NpEnter _ANSI_ARGS_((CONST char *msg));
extern void		NpLeave _ANSI_ARGS_((CONST char *msg,
			    int oldMode));
EXTERN void		NpPanic _ANSI_ARGS_((char *msg));

/*
 * np***plat.c
 */
extern int		NpPlatformInit _ANSI_ARGS_((Tcl_Interp *interp,
			    int externalFlag));
extern void		NpPlatformDestroy _ANSI_ARGS_((NPP This));
extern void		NpPlatformMsg _ANSI_ARGS_((CONST84 char *msg,
			    char *title));
extern void		NpPlatformNew _ANSI_ARGS_((NPP instance));
extern void		NpPlatformSetWindow _ANSI_ARGS_((NPP This,
			    NPWindow *window));
extern void		NpPlatformShutdown _ANSI_ARGS_((void));

/*
 * nptoken.c
 */
extern void		NpInitTokenTables _ANSI_ARGS_((Tcl_Interp *interp));
extern void		NpDeleteTokenTables _ANSI_ARGS_((Tcl_Interp *interp));
extern void		NpRegisterToken _ANSI_ARGS_((ClientData clientData,
			    Tcl_Interp *interp, char *tokenTableID));
extern void		NpUnregisterToken _ANSI_ARGS_((Tcl_Interp *interp,
			    void *token, char *tokenTableID));
extern char		*NpGetTokenName _ANSI_ARGS_((ClientData clientData,
			    Tcl_Interp *interp, char *tableName));
extern int		NpGetAndCheckToken _ANSI_ARGS_((Tcl_Interp *interp,
			    Tcl_Obj *token, char *tableName,
			    ClientData *clientDataPtr));

/*
 * npcmd.c
 */
extern int		PnInit _ANSI_ARGS_((Tcl_Interp *interp));
extern int		PnSafeInit _ANSI_ARGS_((Tcl_Interp *interp));

#if 0
# undef TCL_STORAGE_CLASS
# define TCL_STORAGE_CLASS DLLIMPORT
#endif

#endif /* _NP */
