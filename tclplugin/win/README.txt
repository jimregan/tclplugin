Tcl/Tk Browser Plugin - Windows
===============================

This document describes how to use the browser plugin on Windows.

ActiveX control for hosting the Tcl plugin in IE
================================================

This folder contains an ActiveX control that allows you to host NPAPI
compatible plugins within Internet Explorer.  It was obtained here:
	http://plugindoc.mozdev.org/windows.html

regsvr32 pluginhostctrl.dll

You must have administrator privileges to install a new control on
operating systems such as Windows NT, 2000 & XP.


Usage: Embedding Tclets in Web Pages
====================================

Insert some HTML like this into your content:
  <OBJECT
	ID="PluginHostCtrl"
	CLASSID="CLSID:DBB2DE32-61F1-4F7F-BEB8-A37F5BC24EE2"
	WIDTH="475"
	HEIGHT="575"
  >
    <PARAM name="pluginspage" value="http://www.tcl.tk/software/plugin/"/>
    <PARAM name="type" value="application/x-tcl"/>
    <PARAM name="src" value="http://www.tcl.tk/software/plugin/tktetris.tcl"/>

    <EMBED
	  TYPE="application/x-tcl"
	  PLUGINSPAGE="http://www.tcl.tk/software/plugin/"
	  FRAMEBORDER="NO"
	  WIDTH="475"
	  HEIGHT="575"
	  SRC="http://www.tcl.tk/software/plugin/tktetris.tcl"
    >
    </EMBED>
  </OBJECT>

** THE CLSID FOR THE TCL PLUGIN MAY CHANGE IN THE FUTURE **
The CLSID attribute tells IE to create an instance of the plugin hosting
control, the width and height specify the dimensions in pixels.

The following <EMBED> attributes have <PARAM> tag equivalents:

* <PARAM name="type" ...> is equivalent to TYPE
  Specifies the MIME type of the plugin. The control uses this value to
  determine which plugin it should create to handle the content.

* <PARAM name="src" ...> is equivalent to SRC
  Specifies an URL for the initial stream of data to feed the plugin.
  If you havent't specified a "type" PARAM, the control will attempt to use
  the MIME type of this stream to create the correct plugin.  At this time,
  you must use a fully qualified URL as the Mozilla ActiveX plugin host
  control doesn't correctly fully qualify URLs.

* <PARAM name="pluginspage" ...> is equivalent to PLUGINSPAGE
  Specifies a URL where the plugin may be installed from. The default
  plugin will redirect you to this page when you do not have the correct
  plugin installed.

You may also supply any custom plugin parameters as additional <PARAM>
elements.

The IE ActiveX plugin host controller will act on the <OBJECT> tag, and
NPAPI compatible clients will act on the <EMBED> tag.
