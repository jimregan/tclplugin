/* 
 * npwindll.c --
 *
 *	Dynamic link entry points for the Tcl plugin on Win32.
 *
 * CONTACT:		tclplugin-core@lists.sourceforge.net
 *
 * ORIGINAL AUTHORS:	Jacob Levy			Laurent Demailly
 *
 * Copyright (c) 1995-1997 Sun Microsystems, Inc.
 * Copyright (c) 2000 by Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * SCCS: @(#) npwindll.c 1.2 97/09/26 07:33:28
 * RCS:  @(#) $Id$
 */

#include "np.h"

/*
 * DLL entry points:
 */

#ifdef WIN32

BOOL WINAPI
DllMain(HINSTANCE hDLL, DWORD dwReason, LPVOID lpReserved)
{
    return 1;
}

#else

int CALLBACK
LibMain(HINSTANCE hinst, WORD wDataSeg, WORD cbHeap, LPSTR lpszCmdLine)
{
    return 1;
}

#endif
