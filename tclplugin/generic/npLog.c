/* 
 * nplog.c --
 *
 *	File based logging for the Tcl plugin.
 *
 * Copyright (c) 2002-2003 ActiveState Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS:  @(#) $Id$
 */

#include "np.h"

#ifdef	NP_LOG

#include <time.h>

/*
 * Static variables in this file:
 */
static void	NpLogVA (CONST char *format, va_list argList);

static FILE *logFile = NULL;


/*
 *----------------------------------------------------------------------
 *
 * NpLog --
 *
 *	Logs a message to a file.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Logs a message to a file, opens the file in append mode if it
 *	is not open yet.
 *
 *----------------------------------------------------------------------
 */

	/* VARARGS ARGSUSED */
EXTERN void
NpLog TCL_VARARGS_DEF(CONST char *,arg1)
{
    va_list argList;
    CONST char *format;

    format = TCL_VARARGS_START(CONST char *,arg1,argList);
    NpLogVA(format, argList);
    va_end (argList);
}

/*
 *----------------------------------------------------------------------
 *
 * NpLogVA --
 *
 *	Print an error message and kill the process.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	The process dies, entering the debugger if possible.
 *
 *----------------------------------------------------------------------
 */

static void
NpLogVA (format, argList)
    CONST char *format;		/* Format string, suitable for passing to
				 * fprintf. */
    va_list argList;		/* Variable argument list. */
{
    char *arg1, *arg2, *arg3, *arg4;	/* Additional arguments (variable in
					 * number) to pass to fprintf. */
    char *arg5, *arg6, *arg7, *arg8;

    arg1 = va_arg(argList, char *);
    arg2 = va_arg(argList, char *);
    arg3 = va_arg(argList, char *);
    arg4 = va_arg(argList, char *);
    arg5 = va_arg(argList, char *);
    arg6 = va_arg(argList, char *);
    arg7 = va_arg(argList, char *);
    arg8 = va_arg(argList, char *);

    if (logFile == NULL) {
	return;
    }

    (void) fprintf(logFile, "[%lu] ", (unsigned long) time(NULL));
    (void) fprintf(logFile, format, arg1, arg2, arg3, arg4, arg5, arg6,
	    arg7, arg8);
    /* (void) fprintf(logFile, "\n"); */
    (void) fflush(logFile);
}

/*
 *----------------------------------------------------------------------
 *
 * NpStartLog --
 *
 *	Initializes logging. Called from NPP_Initialize to be able to
 *	log as soon as possible.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Opens a file in append mode and potentially creates the file.
 *
 *----------------------------------------------------------------------
 */

EXTERN void
NpStartLog(CONST char *filename)
{
    if (logFile == NULL) {
        logFile = fopen(filename, "a");
        NpLog("\n ###### LOG STARTED ###### [NEW]\n\n");
    } else {
        NpLog("\n ###### LOG STARTED ###### [EXISTING LOGFILE]\n\n");
    }
}

/*
 *----------------------------------------------------------------------
 *
 * NpStopLog --
 *
 *	Stops logging, and closes the file.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Closes the file.
 *
 *----------------------------------------------------------------------
 */

EXTERN void
NpStopLog()
{
    if (logFile != NULL) {
        NpLog("====== LOG STOPPED ======\n\n");
        fclose(logFile);
        logFile = NULL;
    }
}

#endif	/* NP_LOG */    
