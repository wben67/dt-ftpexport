Author: Benoit Waerzeggers - bw@bewill.eu
License: GNU General Public License Version 3

Purpose
-------
This script add an "ftp export" target to "darktable" so that you can export images 
to any ftp server

Installation
------------
- copy `FtpExport.lua` to your darktable config directory under lua folder (by default `~/.config/darktable/lua`) 

- edit your `luarc` (by default `~/.config/darktable/luarc`)
- put `require 'FtpExport'`
- save file, open Darktable (on close and open it)

Setup
-----

This script use an external command to access ftp server.
By default, it uses "curl".
Make sure, "curl" is in your user execution path.
If not, you can specify its full path in darktable preferences (see below)
You can choose to use another external command (script file ou exe file) (see below)

---- darktable preferences ----
global parameters can be set in darktable->preferences->lua options

- "using curl", if checked, script is intended to use "curl" as external command,
that is, it generate external with curl options. This is the default behavior.

- "command path", full command path of the external command to use for ftp access.
  default is "curl", if curl is not içn your path, specify the full path name of it,
  example: /home/myuser/utilities/curl
  if previous parameter is set to false, specify full path of the external command
  
- "create remote directory param"
- "do not create remote directory parameter": as the "create remote directory parameter"
  has boolean value (converted to 0 and 1 during command generation process), these two 
  parameters tell the script to convert true value of the parameter to the value of the 
  first of them and to the second one for false.
  By default, "create remote dir param" is set to "--ftp-create-dirs" as it is 
  the "curl" options. Default value for "do not create remote directory parameter" is 
  empty string as this the default option for curl.
  These two parameters are not used if "using curl" is set to true.
  
- "global keywords": a comma "," separated list of keywords added to image on 
  successfull export. The first one is used as a root of hierachic tags for
  system tags (extern command return code on error)
  
usage
-----

* in the export dialog, choose "ftp export" and fill the required field:
	- ftp host : ftp server, do not specify "ftp://" prefix
	- ftp port : ftp port (default is 21)
	- ftp user : ftp user
	- ftp password: ftp password
	- ftp remote path: full remote pathname to upload to. If last char is "/", it is intended 
	  to be a directory. local image base name is then used as remote filename
	- ftp create dir: check this box to create full subdirectories tree
	- additional tags: user specific tags to add to exported images
	                   several may be input, seperated by "," hierachic one with "|"
					   
	Click on "Edit parameter" button to edit this fields, then "Save parameters" saves it 
	in "darktable/preferences", "Cancel" button restore last stored preferences.
	
	Remote dir supports all variable expansion used by export module
	
	When curl is not used, these variables are added to the set of pre-defined variables:
	FTP_HOST
	FTP_PORT
	FTP_USER
	FTP_PASSWORD
	FTP_REMOTEDIR: remote dir is pre-analyse and all variables are expanded previously to the command
	FTP_CREATEDIR_OPT
	FTP_CREATEDIR: 1 or 0, depending on the check button state
	
	If export is succesfull, Global keywords and user keywords are added to the image
	Otherwise, the first "global keywords" (default, "darktalbe|exported|ftp") is used 
	to store error code (default darktable|exported|ftp|error|__returncode__ , 
	where __return_code__ is the command return code
	
	Error code is deleted on successfull export.
