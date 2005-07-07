///////////////////////////////////////////////////////////////////
// Started with the install script from the mozilla activex plugin
// http://www.iol.ie/~locka/mozilla/plugin.htm

var SOFTWARE_NAME  = "Tcl/Tk Plugin";
var VERSION        = "3.0";
var PLID_BASE      = "@mozilla.org/TclPlugin";
var PLID           = PLID_BASE + ",version=" + VERSION;

var FLDR_PLUGINS   = getFolder("Plugins");

// TODO: check platform and use .so extension instead
// TODO: find actual sizes of the dll's
var PLUGIN         = new FileToInstall("nptcl30.dll", 60, FLDR_PLUGINS);
var TCLKIT         = new FileToInstall("tclplugin.dll", 1500, FLDR_PLUGINS);

var filesToAdd     = new Array(PLUGIN, TCLKIT);


///////////////////////////////////////////////////////////////////


// Invoke initInstall to start the installation
err = initInstall(SOFTWARE_NAME, PLID, VERSION);
if (err == BAD_PACKAGE_NAME)
{
    // HACK: Mozilla 1.1 has a busted PLID parser which doesn't like
    // the equals sign
    PLID = PLID_BASE;
    err = initInstall(SOFTWARE_NAME, PLID, VERSION);
}

if (err == SUCCESS)
{
    // Install plugin files
    err = verifyDiskSpace(FLDR_PLUGINS, calcSpaceRequired(filesToAdd));
    if (err == SUCCESS)
    {
        for (i = 0; i < filesToAdd.length; i++)
        {
            err = addFile(PLID, VERSION, filesToAdd[i].name,
			  filesToAdd[i].path, null);
            if (err != SUCCESS)
            {
                alert("Installation of " + filesToAdd[i].name +
		      " failed. Error code " + err);
                logComment("adding file " + filesToAdd[i].name +
			   " failed. Errror code: " + err);
                break;
            }
        }
    }
    else
    {
        logComment("Cancelling current browser install due to lack of space...");
    }
}
else
{
    logComment("Install failed at initInstall level with " + err);
}


if (err == SUCCESS)
{
    err = performInstall();
    if (err == SUCCESS)
    {
        alert("Installation performed successfully, you must restart the browser for the changes to take effect");
    }
}
else
{
    cancelInstall();
}

/**
 * Function for preinstallation of plugin (FirstInstall).
 * You should not stop the install process because the function failed,
 * you still have a chance to install the plugin for the already
 * installed gecko browsers.
 *
 * @param dirPath	directory path from getFolder
 * @param spaceRequired	required space in kilobytes
 * 
 **/
function verifyDiskSpace(dirPath, spaceRequired)
{
    var spaceAvailable;

    // Get the available disk space on the given path
    spaceAvailable = fileGetDiskSpaceAvailable(dirPath);
 
    // Convert the available disk space into kilobytes
    spaceAvailable = parseInt(spaceAvailable / 1024);

    // do the verification
    if(spaceAvailable < spaceRequired)
    {
        logComment("Insufficient disk space: " + dirPath);
        logComment("  required : " + spaceRequired + " K");
        logComment("  available: " + spaceAvailable + " K");
        return INSUFFICIENT_DISK_SPACE;
    }

    return SUCCESS;
}

function calcSpaceRequired(fileArray)
{
    var spaceRqd = 0;
    for (i = 0; i < fileArray.length; i++)
    {
        spaceRqd += fileArray[i].size;
    }
    return spaceRqd;
}

function FileToInstall(fileName, fileSize, dirPath)
{
    this.name = fileName;
    this.size = fileSize;
    this.path = dirPath;
}
