/*
 * SCCS: @(#) acconfig.h 1.1 97/07/02 16:41:47
 * RCS:  @(#) $Id$
 */

/* Define if you want debugging compiled in
 * (not recommended)
 */
#undef DEBUG

/*
 * Define PLUGIN_TRACE to have the wrapper functions print
 * messages to stderr whenever they are called.
 */
#undef PLUGIN_TRACE

/*
 * Use the native notifier (recommended)
 */
#define NATIVE_NOTIFIER


/*
 * Use the Xt notifier (don't)
 */
#undef XT_NOTIFIER
