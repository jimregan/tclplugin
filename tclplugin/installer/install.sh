#!/bin/sh
#
# Wrapper to launch the Tcl/Tk installer for the Tcl Plugin.
#
# CONTACT:      sunscript-plugin@sunscript.sun.com
#
# AUTHORS:      Jacob Levy              Laurent Demailly
#               jyl@eng.sun.com         demailly@eng.sun.com
#               jyl@tcl-tk.com          dl@mail.org , L@demailly.com
#
# Please contact us directly for questions, comments and enhancements.
#
# Copyright (c) 1997 Sun Microsystems, Inc.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# SCCS: @(#) install.sh 1.25 98/01/21 10:18:50

TOPDIR=`pwd`

# Get versions and file paths
VERSION=`cat $TOPDIR/tclplug/plug-version`
PATCHLEVEL=`cat $TOPDIR/tclplug/plug-patchlevel`
DISTRIB=`cat $TOPDIR/tclplug/plug-distrib`
TCLVERSION=`cat $TOPDIR/tclplug/tcl-version`
TCLSHP=`cat $TOPDIR/tclplug/tclshp-name`

# Starting the Tcl/Tk based installer
echo "Tcl Plugin $PATCHLEVEL (based on Tcl $TCLVERSION):"
echo "Starting the Tcl/Tk installer for $DISTRIB..."
LD_LIBRARY_PATH=$TOPDIR/plugins:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH
# We don't need to set TCL_LIBRARY or TK_LIBRARY anymore as tclshp
# only uses TCL_PLUGIN_DIR and find everything fine from there
TCL_PLUGIN_DIR=$TOPDIR/tclplug
export TCL_PLUGIN_DIR
$TOPDIR/tclplug/$TCLSHP installer/install.tcl $DISTRIB

if [ $? -eq 0 ]; then
    echo "Thank you for using the Tcl/Tk installer!"
    exit 0
else
    echo "The Tcl/Tk installer generated an unexpected error..."
    echo "Please send any log to sunscript-plugin@sunscript.sun.com"
    echo "Can not proceed. Installation aborted."
    exit 1
fi
