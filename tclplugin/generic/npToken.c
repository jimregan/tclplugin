/* 
 * nptoken.c --
 *
 *	Manage token tables for instances and streams in the Tcl plugin.
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

#include	"np.h"
#include	<stdio.h>

/*
 * Buffer used to print out panic messages:
 */

#define PANIC_BUFSIZ 512
static char panicBuf[PANIC_BUFSIZ];

/*
 *----------------------------------------------------------------------
 *
 * NpInitTokenTables --
 *
 *	Add the token tables to the interpreter passed as argument.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Creates the assocData structures and the tables.
 *
 *----------------------------------------------------------------------
 */

void
NpInitTokenTables(Tcl_Interp *interp)
{
    Tcl_HashTable *hTblPtr;

    hTblPtr = (Tcl_HashTable *) ckalloc(sizeof(Tcl_HashTable));
    if (hTblPtr == (Tcl_HashTable *) NULL) {
	snprintf(panicBuf, PANIC_BUFSIZ,
		"memory allocation failed in NpInitTokenTables for %s",
		NPTCL_INSTANCE);
	NpPanic(panicBuf);
    }

    Tcl_InitHashTable(hTblPtr, TCL_ONE_WORD_KEYS);
    Tcl_SetAssocData(interp, NPTCL_INSTANCE,
	    (Tcl_InterpDeleteProc *) NULL, (ClientData) hTblPtr);

    /*
     * Install a hash table for stream tokens.
     */

    hTblPtr = (Tcl_HashTable *) ckalloc(sizeof(Tcl_HashTable)); 
    if (hTblPtr == (Tcl_HashTable *) NULL) {
	snprintf(panicBuf, PANIC_BUFSIZ,
		"memory allocation failed in NpInitTokenTables for %s",
		NPTCL_STREAM);
	NpPanic(panicBuf);
    }

    Tcl_InitHashTable(hTblPtr, TCL_ONE_WORD_KEYS);
    Tcl_SetAssocData(interp, NPTCL_STREAM,
	    (Tcl_InterpDeleteProc *) NULL, (ClientData) hTblPtr);
}

/*
 *----------------------------------------------------------------------
 *
 * NpRegisterToken --
 *
 *	Registers a token in one of the token tables.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Adds a token to one of the token tables.
 *
 *----------------------------------------------------------------------
 */

void
NpRegisterToken(ClientData clientData, Tcl_Interp *interp, char *tableName)
{
    Tcl_HashTable *hTblPtr;
    Tcl_HashEntry *hPtr;
    int isnew;

    hTblPtr = (Tcl_HashTable *) Tcl_GetAssocData(interp, tableName, NULL);
    if (hTblPtr == (Tcl_HashTable *) NULL) {
        snprintf(panicBuf, PANIC_BUFSIZ,
		"could not find token table \"%s\" in RegisterToken",
                tableName);
        NpPanic(panicBuf);
    }
    hPtr = Tcl_CreateHashEntry(hTblPtr, (CONST char *) clientData, &isnew);
    if (!isnew) {
        snprintf(panicBuf, PANIC_BUFSIZ,
		"duplicate token key %ld in token table %s",
                (long) clientData, tableName);
        NpPanic(panicBuf);
    }
    Tcl_SetHashValue(hPtr, clientData);
}

/*
 *----------------------------------------------------------------------
 *
 * NpUnregisterToken --
 *
 *	Remove a token from a token table.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Removes the token and its associated value from the table.
 *
 *----------------------------------------------------------------------
 */

void
NpUnregisterToken(Tcl_Interp *interp, void *token, char *tableName)
{
    Tcl_HashTable *hTblPtr;
    Tcl_HashEntry *hPtr;
    
    hTblPtr = (Tcl_HashTable *) Tcl_GetAssocData(interp, tableName, NULL);
    if (hTblPtr == (Tcl_HashTable *) NULL) {
        snprintf(panicBuf, PANIC_BUFSIZ,
		"could not find token table %s in NpUnregisterToken",
                tableName);
        NpPanic(panicBuf);
    }
    hPtr = Tcl_FindHashEntry(hTblPtr, token);
    if (hPtr == NULL) {
        snprintf(panicBuf, PANIC_BUFSIZ,
		"missing token %p in table %s in NpUnregisterToken",
                token, tableName);
        NpPanic(panicBuf);
    }
    Tcl_DeleteHashEntry(hPtr);
}

/*
 *----------------------------------------------------------------------
 *
 * NpGetAndCheckToken --
 *
 *	Get the value of a token associated with a passed token in one
 *	of the token tables in the passed interpreter.
 *
 * Results:
 *	The value associated with the token.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

int
NpGetAndCheckToken(Tcl_Interp *interp, Tcl_Obj *objPtr, char *tableName,
	ClientData *clientDataPtr)
{
    Tcl_HashEntry *hPtr;
    Tcl_HashTable *hTblPtr;
    long longVal;

    hTblPtr = (Tcl_HashTable *) Tcl_GetAssocData(interp, tableName, NULL);
    if (hTblPtr == (Tcl_HashTable *) NULL) {
        Tcl_AppendResult(interp,
                "could not find token table", tableName, (char *) NULL);
        return TCL_ERROR;
    }
    if (Tcl_GetLongFromObj(interp, objPtr, &longVal) != TCL_OK) {
	return TCL_ERROR;
    }
    hPtr = Tcl_FindHashEntry(hTblPtr, (CONST char *) longVal);
    if (hPtr == (Tcl_HashEntry *) NULL) {
	char buf[256];
	snprintf(buf, 256, "invalid instance token \"%ld\" in table \"%s\"",
		longVal, tableName);
	Tcl_SetResult(interp, buf, TCL_VOLATILE);
        return TCL_ERROR;
    }
    *clientDataPtr = (ClientData) Tcl_GetHashValue(hPtr);
    return TCL_OK;
}

/*
 *----------------------------------------------------------------------
 *
 * NpDeleteTokenTables --
 *
 *	Deletes the token tables on shutdown.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Deletes the tables.
 *
 *----------------------------------------------------------------------
 */

void
NpDeleteTokenTables(Tcl_Interp *interp)
{
    Tcl_HashTable *hTblPtr;

    /*
     * Don't panic if these are already gone.
     */

    hTblPtr = (Tcl_HashTable *) Tcl_GetAssocData(interp, NPTCL_INSTANCE, NULL);
    if (hTblPtr != NULL) {
	Tcl_DeleteHashTable(hTblPtr);
	Tcl_DeleteAssocData(interp, NPTCL_INSTANCE);
    }

    hTblPtr = (Tcl_HashTable *) Tcl_GetAssocData(interp, NPTCL_STREAM, NULL);
    if (hTblPtr != NULL) {
	Tcl_DeleteHashTable(hTblPtr);
	Tcl_DeleteAssocData(interp, NPTCL_STREAM);
    }
}
