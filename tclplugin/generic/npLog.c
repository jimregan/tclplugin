/* 
 * nplog.c --
 *
 *	File based logging for the Tcl plugin.
 *
 * ORIGINAL AUTHORS:	Jacob Levy			Laurent Demailly
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

#include "np.h"

#ifdef	NP_LOG

#ifndef MAC_TCL
#include <time.h>
#endif

/*
 * Static variables in this file:
 */

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
NpLog(CONST char *format, int a1, int a2, int a3)
{
    /*
     * Prevent crash if we stopped logging or could not open the file.
     */
    
    if (logFile != NULL) {
#ifdef MAC_TCL
	unsigned long TclpGetClicks _ANSI_ARGS_((void));
	fprintf(logFile, "[%lu] ",  TclpGetClicks());
#else
	fprintf(logFile, "[%lu] ", (unsigned long) time((time_t *) NULL));
#endif
        fprintf(logFile, format, a1, a2, a3);
        fflush(logFile);
    }
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
        NpLog("\n ###### LOG STARTED ###### [NEW]\n\n", 0, 0, 0);
    } else {
        NpLog("\n ###### LOG STARTED ###### [EXISTING LOGFILE]\n\n", 0, 0, 0);
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
        NpLog("====== LOG STOPPED ======\n\n", 0, 0, 0);
        fclose(logFile);
        logFile = NULL;
    }
}

#endif	/* NP_LOG */    
