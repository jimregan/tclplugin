/* 
 * npinit.c --
 *
 *	Implements Windows plugin initialization.
 *
 * CONTACT:		tclplugin-core@lists.sourceforge.net
 *
 * Copyright (c) 2002 ActiveState Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS:  @(#) $Id$
 */

/*
 * Netscape Plugin APIs
 */
#include "np.h"
#include "npupp.h"


/*
 * Netscape Plugin Navigator-side (browser) functions
 */
static NPNetscapeFuncs NPNFuncs;

static NPError fillPluginFunctionTable(NPPluginFuncs* aNPPFuncs)
{
    if(aNPPFuncs == NULL) {
	NpLog("fillPluginFunctionTable aNPPFuncs NULL ERROR\n", 0, 0, 0);
	return NPERR_INVALID_FUNCTABLE_ERROR;
    }

    // Set up the plugin function table that Netscape will use to
    // call us. Netscape needs to know about our version and size   
    // and have a UniversalProcPointer for every function we implement.

    aNPPFuncs->version       = (NP_VERSION_MAJOR << 8) | NP_VERSION_MINOR;
    aNPPFuncs->newp          = NPP_New;
    aNPPFuncs->destroy       = NPP_Destroy;
    aNPPFuncs->setwindow     = NPP_SetWindow;
    aNPPFuncs->newstream     = NPP_NewStream;
    aNPPFuncs->destroystream = NPP_DestroyStream;
    aNPPFuncs->asfile        = NPP_StreamAsFile;
    aNPPFuncs->writeready    = NPP_WriteReady;
    aNPPFuncs->write         = NPP_Write;
    aNPPFuncs->print         = NPP_Print;
    aNPPFuncs->event         = NPP_HandleEvent;
    aNPPFuncs->urlnotify     = NPP_URLNotify;
    aNPPFuncs->getvalue      = NPP_GetValue;
    aNPPFuncs->setvalue      = NPP_SetValue;
    aNPPFuncs->javaClass     = NULL; //Private_GetJavaClass();

    return NPERR_NO_ERROR;
}

static NPError fillNetscapeFunctionTable(NPNetscapeFuncs* aNPNFuncs)
{
    int v9plugin = 0;

    if (aNPNFuncs == NULL) {
	return NPERR_INVALID_FUNCTABLE_ERROR;
    }

    if (HIBYTE(aNPNFuncs->version) > NP_VERSION_MAJOR) {
	return NPERR_INCOMPATIBLE_VERSION_ERROR;
    }

    if (aNPNFuncs->size < sizeof(NPNetscapeFuncs)) {
	if (aNPNFuncs->size < sizeof(NPNetscapeFuncsOld)) {
	    return NPERR_INVALID_FUNCTABLE_ERROR;
	}
	v9plugin = 1;
    }

    NPNFuncs.size             = aNPNFuncs->size;
    NPNFuncs.version          = aNPNFuncs->version;
    NPNFuncs.geturlnotify     = aNPNFuncs->geturlnotify;
    NPNFuncs.geturl           = aNPNFuncs->geturl;
    NPNFuncs.posturlnotify    = aNPNFuncs->posturlnotify;
    NPNFuncs.posturl          = aNPNFuncs->posturl;
    NPNFuncs.requestread      = aNPNFuncs->requestread;
    NPNFuncs.newstream        = aNPNFuncs->newstream;
    NPNFuncs.write            = aNPNFuncs->write;
    NPNFuncs.destroystream    = aNPNFuncs->destroystream;
    NPNFuncs.status           = aNPNFuncs->status;
    NPNFuncs.uagent           = aNPNFuncs->uagent;
    NPNFuncs.memalloc         = aNPNFuncs->memalloc;
    NPNFuncs.memfree          = aNPNFuncs->memfree;
    NPNFuncs.memflush         = aNPNFuncs->memflush;
    NPNFuncs.reloadplugins    = aNPNFuncs->reloadplugins;
    NPNFuncs.getJavaEnv       = aNPNFuncs->getJavaEnv;
    NPNFuncs.getJavaPeer      = aNPNFuncs->getJavaPeer;
    if (v9plugin) {
	NPNFuncs.getvalue         = NULL;
	NPNFuncs.setvalue         = NULL;
	NPNFuncs.invalidaterect   = NULL;
	NPNFuncs.invalidateregion = NULL;
	NPNFuncs.forceredraw      = NULL;
    } else {
	NPNFuncs.getvalue         = aNPNFuncs->getvalue;
	NPNFuncs.setvalue         = aNPNFuncs->setvalue;
	NPNFuncs.invalidaterect   = aNPNFuncs->invalidaterect;
	NPNFuncs.invalidateregion = aNPNFuncs->invalidateregion;
	NPNFuncs.forceredraw      = aNPNFuncs->forceredraw;
    }

    return NPERR_NO_ERROR;
}

/*
 *----------------------------------------------------------------------
 *
 * NP_GetEntryPoints --
 *
 *	fills in the func table used by Navigator to call entry points in
 *	plugin DLL.
 *
 *----------------------------------------------------------------------
 */

#ifdef XP_WIN
NPError OSCALL
NP_GetEntryPoints(NPPluginFuncs* aNPPFuncs)
{
  return fillPluginFunctionTable(aNPPFuncs);
}
#endif

/*
 *----------------------------------------------------------------------
 *
 * NP_Initialize --
 *
 *	called immediately after the plugin DLL is loaded
 *
 *----------------------------------------------------------------------
 */

#ifdef XP_WIN
NPError OSCALL
NP_Initialize(NPNetscapeFuncs* aNPNFuncs)
{
    NPError rv = fillNetscapeFunctionTable(aNPNFuncs);

    if (rv != NPERR_NO_ERROR) {
	return rv;
    }

    // NPP_Initialize is a standard (cross-platform) initialize function.
    return NPP_Initialize();
}
#elif defined(XP_UNIX)
NPError NP_Initialize(NPNetscapeFuncs* aNPNFuncs, NPPluginFuncs* aNPPFuncs)
{
  NPError rv = fillNetscapeFunctionTable(aNPNFuncs);
  if (rv != NPERR_NO_ERROR)
    return rv;

  rv = fillPluginFunctionTable(aNPPFuncs);
  if (rv != NPERR_NO_ERROR)
    return rv;

  return NPP_Initialize();
}
#endif

/*
 *----------------------------------------------------------------------
 *
 * NP_Shutdown --
 *
 *	called immediately before the plugin DLL is unloaded.  This function
 *	should check for some ref count on the dll to see if it is unloadable
 *	or it needs to stay in memory.
 *----------------------------------------------------------------------
 */
NPError OSCALL
NP_Shutdown()
{
    NPP_Shutdown();
    return NPERR_NO_ERROR;
}
/************** END - PLUGIN DLL entry points *************************/

/************** NAVIGATOR Entry points **************************/

/* These entry points expect to be called from within the plugin.  The
 * noteworthy assumption is that DS has already been set to point to the
 * plugin's DLL data segment.
 */

/* 
 * returns the major/minor version numbers of the Plugin API for the plugin
 * and the Navigator
 */
void NPN_Version(int* plugin_major, int* plugin_minor,
		 int* netscape_major, int* netscape_minor)
{
    *plugin_major   = NP_VERSION_MAJOR;
    *plugin_minor   = NP_VERSION_MINOR;
    *netscape_major = HIBYTE(NPNFuncs.version);
    *netscape_minor = LOBYTE(NPNFuncs.version);
}

/* causes the specified URL to be fetched and streamed in
 */
NPError NPN_GetURLNotify(NPP instance, const char *url,
			 const char *target, void* notifyData)

{
    int navMinorVers = NPNFuncs.version & 0xFF;
    NPError err;

    if (navMinorVers >= NPVERS_HAS_NOTIFICATION) {
	err = CallNPN_GetURLNotifyProc(NPNFuncs.geturlnotify,
		instance, url, target, notifyData);
    } else {
	err = NPERR_INCOMPATIBLE_VERSION_ERROR;
    }
    return err;
}


NPError NPN_GetURL(NPP instance, const char *url, const char *target)
{
    return CallNPN_GetURLProc(NPNFuncs.geturl, instance, url, target);
}

NPError NPN_PostURLNotify(NPP instance, const char* url, const char* window,
			  uint32 len, const char* buf, NPBool file,
			  void* notifyData)
{
    int navMinorVers = NPNFuncs.version & 0xFF;
    NPError err;

    if (navMinorVers >= NPVERS_HAS_NOTIFICATION) {
	err = CallNPN_PostURLNotifyProc(NPNFuncs.posturlnotify,
		instance, url, window, len, buf, file, notifyData);
    } else {
	err = NPERR_INCOMPATIBLE_VERSION_ERROR;
    }
    return err;
}


NPError NPN_PostURL(NPP instance, const char* url, const char* window,
		    uint32 len, const char* buf, NPBool file)
{
    return CallNPN_PostURLProc(NPNFuncs.posturl,
	    instance, url, window, len, buf, file);
}

/* Requests that a number of bytes be provided on a stream.  Typically
   this would be used if a stream was in "pull" mode.  An optional
   position can be provided for streams which are seekable.
*/
NPError NPN_RequestRead(NPStream* stream, NPByteRange* rangeList)
{
    return CallNPN_RequestReadProc(NPNFuncs.requestread, stream, rangeList);
}

/* Creates a new stream of data from the plug-in to be interpreted
   by Netscape in the current window.
*/
NPError NPN_NewStream(NPP instance, NPMIMEType type, 
		      const char* target, NPStream** stream)
{
    int navMinorVersion = NPNFuncs.version & 0xFF;
    NPError err;

    if (navMinorVersion >= NPVERS_HAS_STREAMOUTPUT) {
	err = CallNPN_NewStreamProc(NPNFuncs.newstream,
		instance, type, target, stream);
    } else {
	err = NPERR_INCOMPATIBLE_VERSION_ERROR;
    }
    return err;
}

/* Provides len bytes of data.
 */
int32 NPN_Write(NPP instance, NPStream *stream,
                int32 len, void *buffer)
{
    int navMinorVersion = NPNFuncs.version & 0xFF;
    int32 result;

    if (navMinorVersion >= NPVERS_HAS_STREAMOUTPUT) {
	result = CallNPN_WriteProc(NPNFuncs.write,
		instance, stream, len, buffer);
    } else {
	result = -1;
    }
    return result;
}

/* Closes a stream object.  
   reason indicates why the stream was closed.
*/
NPError NPN_DestroyStream(NPP instance, NPStream* stream, NPError reason)
{
    int navMinorVersion = NPNFuncs.version & 0xFF;
    NPError err;

    if (navMinorVersion >= NPVERS_HAS_STREAMOUTPUT) {
	err = CallNPN_DestroyStreamProc(NPNFuncs.destroystream,
		instance, stream, reason);
    } else {
	err = NPERR_INCOMPATIBLE_VERSION_ERROR;
    }
    return err;
}

/* Provides a text status message in the Netscape client user interface
 */
void NPN_Status(NPP instance, const char *message)
{
    CallNPN_StatusProc(NPNFuncs.status, instance, message);
}

/* returns the user agent string of Navigator, which contains version info
 */
const char* NPN_UserAgent(NPP instance)
{
    return CallNPN_UserAgentProc(NPNFuncs.uagent, instance);
}

/* allocates memory from the Navigator's memory space.  Necessary so that
   saved instance data may be freed by Navigator when exiting.
*/


void* NPN_MemAlloc(uint32 size)
{
    return CallNPN_MemAllocProc(NPNFuncs.memalloc, size);
}

/* reciprocal of MemAlloc() above
 */
void NPN_MemFree(void* ptr)
{
    CallNPN_MemFreeProc(NPNFuncs.memfree, ptr);
}

uint32 NPN_MemFlush(uint32 size)
{
    return CallNPN_MemFlushProc(NPNFuncs.memflush, size);
}

/* private function to Netscape.  do not use!
 */
void NPN_ReloadPlugins(NPBool reloadPages)
{
    CallNPN_ReloadPluginsProc(NPNFuncs.reloadplugins, reloadPages);
}

JRIEnv* NPN_GetJavaEnv(void)
{
    return CallNPN_GetJavaEnvProc(NPNFuncs.getJavaEnv);
}

jref NPN_GetJavaPeer(NPP instance)
{
    return CallNPN_GetJavaPeerProc(NPNFuncs.getJavaPeer, instance);
}

NPError NPN_GetValue(NPP instance, NPNVariable variable, void *value)
{
    return CallNPN_GetValueProc(NPNFuncs.getvalue, instance, variable, value);
}

NPError NPN_SetValue(NPP instance, NPPVariable variable, void *value)
{
    return CallNPN_SetValueProc(NPNFuncs.setvalue, instance, variable, value);
}

void NPN_InvalidateRect(NPP instance, NPRect *invalidRect)
{
    CallNPN_InvalidateRectProc(NPNFuncs.invalidaterect, instance, invalidRect);
}

void NPN_InvalidateRegion(NPP instance, NPRegion invalidRegion)
{
    CallNPN_InvalidateRegionProc(NPNFuncs.invalidateregion,
	    instance, invalidRegion);
}

void NPN_ForceRedraw(NPP instance)
{
    CallNPN_ForceRedrawProc(NPNFuncs.forceredraw, instance);
}

#if USE_JAVA
JRIGlobalRef Private_GetJavaClass(void);

// Private_GetJavaClass (global function)
//
//	Given a Java class reference (thru NPP_GetJavaClass) inform JRT
//	of this class existence
//
JRIGlobalRef
Private_GetJavaClass(void)
{
    jref clazz = NPP_GetJavaClass();
    if (clazz) {
	JRIEnv* env = NPN_GetJavaEnv();
	return JRI_NewGlobalRef(env, clazz);
    }
    return NULL;
}
#endif
