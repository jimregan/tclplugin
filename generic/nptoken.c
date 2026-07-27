/* 
 * nptoken.c --
 *
 *	Manage token tables for instances and streams in the Tcl plugin.
 *
 * ORIGINAL AUTHORS:	Jacob Levy			Laurent Demailly
 *
 * Copyright (c) 1995-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) nptoken.c 1.6 97/09/26 07:28:48
 * RCS:  @(#) $Id$
 */

#include	"np.h"
#include	<stdio.h>

/*
 * Buffer used to print out panic messages:
 */

static char panicBuf[512];

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
NpInitTokenTables(interp)
    Tcl_Interp *interp;
{
    Tcl_HashTable *hTblPtr;

    hTblPtr = (Tcl_HashTable *) ckalloc(sizeof(Tcl_HashTable));
    if (hTblPtr == (Tcl_HashTable *) NULL) {
        sprintf(panicBuf,
                "memory allocation failed in NpInitTokenTables for %s",
                NPTCL_INSTANCE);
        NpPanic(panicBuf);
    }
    
    Tcl_InitHashTable(hTblPtr, TCL_STRING_KEYS);
    Tcl_SetAssocData(interp, NPTCL_INSTANCE,
            (Tcl_InterpDeleteProc *) NULL, (ClientData) hTblPtr);

    /*
     * Install a hash table for stream tokens.
     */

    hTblPtr = (Tcl_HashTable *) ckalloc(sizeof(Tcl_HashTable)); 
    if (hTblPtr == (Tcl_HashTable *) NULL) {
        sprintf(panicBuf,
                "memory allocation failed in NpInitTokenTables for %s",
                NPTCL_STREAM);
        NpPanic(panicBuf);
    }
    
    Tcl_InitHashTable(hTblPtr, TCL_STRING_KEYS);
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
NpRegisterToken(clientData, interp, tableName)
    ClientData clientData;
    Tcl_Interp *interp;
    char *tableName;
{
    Tcl_HashTable *hTblPtr;
    Tcl_HashEntry *hPtr;
    char *tokenName;
    int isnew;

    hTblPtr = (Tcl_HashTable *) Tcl_GetAssocData(interp, tableName, NULL);
    if (hTblPtr == (Tcl_HashTable *) NULL) {
        sprintf(panicBuf, "could not find token table \"%s\" in RegisterToken",
                tableName);
        NpPanic(panicBuf);
    }
    tokenName = NpGetTokenName(clientData, interp, tableName);
    hPtr = Tcl_CreateHashEntry(hTblPtr,
            NpGetTokenName(clientData, interp, tableName),
            &isnew);
    if (!isnew) {
        sprintf(panicBuf, "duplicate token key %s in token table %s",
                tokenName, tableName);
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
NpUnregisterToken(interp, token, tableName)
    Tcl_Interp *interp;
    char *token;
    char *tableName;
{
    Tcl_HashTable *hTblPtr;
    Tcl_HashEntry *hPtr;
    
    hTblPtr =
        (Tcl_HashTable *) Tcl_GetAssocData(interp, tableName, NULL);
    if (hTblPtr == (Tcl_HashTable *) NULL) {
        sprintf(panicBuf, "could not find token table %s in NpUnregisterToken",
                tableName);
        NpPanic(panicBuf);
    }
    hPtr = Tcl_FindHashEntry(hTblPtr, token);
    if (hPtr == NULL) {
        sprintf(panicBuf, "missing token %s in table %s in NpUnregisterToken",
                token, tableName);
        NpPanic(panicBuf);
    }
    Tcl_DeleteHashEntry(hPtr);
}

/*
 *----------------------------------------------------------------------
 *
 * NpGetTokenName --
 *
 *	Gets a name for a token.
 *
 * Results:
 *	A string (static storage) containing the name.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

char *
NpGetTokenName(clientData, interp, tableName)
    ClientData clientData;
    Tcl_Interp *interp;
    char *tableName;
{
    static char tmpBuf[128];
    
    sprintf(tmpBuf, "%s-%p", tableName, (void *) clientData);
    return tmpBuf;
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
NpGetAndCheckToken(interp, token, tableName, clientDataPtr)
    Tcl_Interp *interp;
    char *token;
    char *tableName;
    ClientData *clientDataPtr;
{
    Tcl_HashEntry *hPtr;
    Tcl_HashTable *hTblPtr;

    hTblPtr = (Tcl_HashTable *) Tcl_GetAssocData(interp, tableName,
            NULL);
    if (hTblPtr == (Tcl_HashTable *) NULL) {
        Tcl_AppendResult(interp,
                "could not find token table", tableName, (char *) NULL);
        return TCL_ERROR;
    }
    hPtr = Tcl_FindHashEntry(hTblPtr, token);
    if (hPtr == (Tcl_HashEntry *) NULL) {
        Tcl_AppendResult(interp, "invalid instance token: ", token,
                " in table: ", tableName, (char *) NULL);
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
NpDeleteTokenTables(interp)
    Tcl_Interp *interp;
{
    Tcl_HashTable *hTblPtr;

    hTblPtr = (Tcl_HashTable *) Tcl_GetAssocData(interp, NPTCL_INSTANCE,
            NULL);
    if (hTblPtr == (Tcl_HashTable *) NULL) {
        sprintf(panicBuf,
                "could not find token table %s in NpDeleteTokenTables",
                NPTCL_INSTANCE);
        NpPanic(panicBuf);
    }
    
    Tcl_DeleteHashTable(hTblPtr);
    Tcl_DeleteAssocData(interp, NPTCL_INSTANCE);

    hTblPtr = (Tcl_HashTable *) Tcl_GetAssocData(interp, NPTCL_STREAM,
            NULL);
    if (hTblPtr == (Tcl_HashTable *) NULL) {
        sprintf(panicBuf,
                "could not find token table %s in NpDeleteTokenTables",
                NPTCL_STREAM);
        NpPanic(panicBuf);
    }
    
    Tcl_DeleteHashTable(hTblPtr);
    Tcl_DeleteAssocData(interp, NPTCL_STREAM);
}
