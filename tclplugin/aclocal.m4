#
# Include the TEA standard macro set
#

builtin(include,tclconfig/tcl.m4)

#
# Add here whatever m4 macros you want to define for your package
#

AC_DEFUN(TCLPLUGIN_TRACE, [
    AC_MSG_CHECKING([whether to enable plugin tracing])
    AC_ARG_ENABLE(plugin-trace,
    	[  --enable-plugin-trace   Enable Plugin Trace (debug output)],
    	[], [enableval="no"])

    if test "$enableval" = "yes"; then
	AC_DEFINE(PLUGIN_TRACE)
	AC_MSG_RESULT([yes])
    else
	AC_MSG_RESULT([no (default)])
    fi
])

AC_DEFUN(TCLPLUGIN_LOG, [
    AC_MSG_CHECKING([whether to enable plugin logging])
    AC_ARG_ENABLE(plugin-log,
    	[  --enable-plugin-log     Enable Plugin Logging],
    	[log_ok=$enableval], [log_ok=no])

    if test "$log_ok" = "no"; then
	AC_MSG_RESULT([no (default)])
    else
	if test "$log_ok" = "yes"; then
	    if test "${TEA_PLATFORM}" = "unix"; then
		NP_LOG=\"/tmp/nptcl.log\"
	    else
		NP_LOG=\"C:/temp/nptcl.log\"
	    fi
	else
	    NP_LOG=\"$log_ok\"
	fi
	AC_DEFINE_UNQUOTED(NP_LOG, ${NP_LOG})
	AC_MSG_RESULT([yes (${NP_LOG})])
    fi
])

AC_DEFUN(TCLPLUGIN_MOZILLA_DIR, [
    AC_MSG_CHECKING([for Mozilla home directory])
    # Check for Mozilla home (install directory of netscape (plugins))
    AC_ARG_WITH(mozilla,
    	[  --with-mozilla=DIR      Will install in DIR/plugins],
	[MOZILLA_DIR=$withval], [MOZILLA_DIR="$MOZILLA_HOME"])

    if test -z "$MOZILLA_DIR"; then
	if test "${TEA_PLATFORM}" = "unix"; then
	    MOZILLA_DIR=/usr/local/lib/netscape
	    for i in \
		    `ls -d /usr/local/lib/mozilla 2>/dev/null` \
		    `ls -d /usr/local/lib/netscape 2>/dev/null` \
		    `ls -d /usr/local/mozilla/lib 2>/dev/null` \
		    `ls -d /usr/local/netscape/lib 2>/dev/null` \
		    `ls -d /usr/lib/mozilla 2>/dev/null` \
		    `ls -d /usr/lib/netscape 2>/dev/null` \
		    `ls -d /opt/mozilla 2>/dev/null` \
		    `ls -d /usr/netscape/lib 2>/dev/null` \
		    `ls -d ~/.mozilla 2>/dev/null` \
		    `ls -d ~/.netscape 2>/dev/null` \
		; do
		if test -d "$i" ; then
		    MOZILLA_DIR=`(cd $i; pwd)`
		    break
		fi
	    done
	else
	    MOZILLA_DIR=C:/Progra~1/Mozilla
	    for i in `ls -d C:/Progra~1/mozilla.org/Mozilla 2>/dev/null` \
		    `ls -d C:/Progra~1/Mozilla 2>/dev/null` \
		    ; do
		if test -d "$i" ; then
		    MOZILLA_DIR=`(cd $i; pwd)`
		    break
		fi
	    done
	fi
    fi

    if test ! -d "$MOZILLA_DIR"; then
	AC_MSG_WARN([Could not find Mozilla directory: use configure --with-mozilla=MOZILLA_HOME - ie. --with-mozilla=$HOME/.netscape for a personal install])
    fi
    AC_MSG_RESULT([found ($MOZILLA_DIR)])

    AC_SUBST(MOZILLA_DIR)
])
