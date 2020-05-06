--[[
    This file is part of darktable,
    copyright (c) 2020 Benoit Waerzeggers

    darktable is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
    darktable is distributed in the hope that it will be useful,
     but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
    You should have received a copy of the GNU General Public License
    along with dt.  If not, see <http://www.gnu.org/licenses/>.
]]

--[[
FtpExport.lua - add new target storage "ftp export", allowing to export image to any ftp server

USAGE
    * require this script from main lua file
	
	By default, this script user "curl" as external ftp command.
	You can set another external command in "preferences/lua options"
	I use external program because the lua internal implemantation of ftp is quite (too!) poor...
  
  -- setup --
  global parameters could be set in "preferences/lua options"
	- "using curl", if checked, export use "curl" as external command. It generates its parameters automatically 
	- "command path", external command to use, if curl is not on the user path for example, or another external command 
	  if "using curl" is not set
	- "create remote directory param", the full "create remote directory parameters", only used if "using curl" is not set
	  if create remote directory parameter is set (in the export section, see below), variable FTP_CREATEDIR_OPT is expanded to
	- "do not create remote directory parameter": same as above but if create remote directory parameter is not set
	- "global keywords", tags added to image on succesfull export, default is "darktable|exported|ftp"
	  multiple keywords can be specified, seperate them with a ",". The first one is used as the root part of hierarchic system tags
	  of the export
	
	other specific user tags can be specified in the export GUI
	
	-- use --
	* in the export dialog, choose "ftp export" and fill the required field:
	- ftp host : ftp server, do not specify "ftp://" prefix
	- ftp port : ftp port (default is 21)
	- ftp user : ftp user
	- ftp password: ftp password
	- ftp remote path: full remote pathname to upload to. If last char is "/", it is intended to be a directory. 
	                   image sent to it, with its local name
	- ftp create dir: check this box to create full subdirectories tree
	- additional tags: user specific tags to add to exported images
	                   several may be input, seperated by "," hierachic one with "|"
					   
	Click on "Edit parameter" button to edit this fields, then "Save parameters" saves it preferences, "Cancel" button restore it 
	to last preference.
	
	Remote dir supports all variable expension used by 'copy' module
	
	When curl is not used, these variables are added to the set of pre-defined variables:
	FTP_HOST
	FTP_PORT
	FTP_USER
	FTP_PASSWORD
	FTP_REMOTEDIR: remote dir is pre-analyse and all variables are expanded previously to the command
	FTP_CREATEDIR_OPT
	FTP_CREATEDIR: 1 or 0, depending on the check button state
	
	If export is succesfull, Global keywords as user keywords are added to the image
	Otherwise, tags darktable|exported|ftp|error|__return code__ is added to image, where __return_code__ is the command return code
	
]]

local dt = require "darktable"
require "darktable.debug"

--[[
	Register preferences so they appear in the pref "option lua" tab of darktable
--]]

-- use curl or external command. Default is to use curl and all its parameters
dt.preferences.register("ftp export","using_curl",
  "bool","using curl",
  "is set (default), generate curl commmand directly",true)
  
-- full command path, if "curl" is not in the user execution path, or if another external command is used
dt.preferences.register("ftp export","command_path",
  "string","cmd path",
  "Complete path to command export. default: curl","curl")
  
-- if curl is not used, specify the value of the "create dir parameter" when this option is checked in the main export UI
dt.preferences.register("ftp export","createdir_param",
  "string","create remote directory param",
  "syntax of create remote directory parameter (not used with curl)","")
  
-- if curl is not used, specify the value of the "create dir parameter" when this option is not checked in the main export UI
dt.preferences.register("ftp export","not_createdir_param",
  "string","do not create remote directory param",
  "syntax to not create remote directory parameter (not used with curl)","")
  
-- global keywords to add to image on successfull export. First one is used as the root part of keyword for system specific keywords
-- (error number)
dt.preferences.register("ftp export","global_keywords",
  "string","global keywords",
  "global ftp export keywords (all ftp profile use them) with ',' as separator\ndefault: darktable|exported|ftp","darktable|exported|ftp")


local ftpexport = {}
local fe = ftpexport

-- state of the interface. true after user clicks on "Edit parameters" button. False in other case
fe.edit_state=false

-- ftp server entry
local ftp_host = dt.new_widget("entry"){
  tooltip ="ftp server to upload to",
  editable=false,
  text = dt.preferences.read("ftp export","ftp_host", "string"),
}

-- ftp port entry
local ftp_port = dt.new_widget("entry"){
  tooltip ="server port (default 21)",
  editable=false,
  text = dt.preferences.read("ftp export","ftp_port", "string"),
}

-- ftp user entry
local ftp_user = dt.new_widget("entry"){
  tooltip ="ftp user",
  editable=false,
  text = dt.preferences.read("ftp export","ftp_user", "string"),
}

-- ftp password entry 
-- TO DO: try to find why is_password does not work (allways show the entry...)
local ftp_password = dt.new_widget("entry"){
  tooltip ="ftp password",
  editable=false,
  is_password=false,
  text = dt.preferences.read("ftp export","ftp_password", "string"),
}

-- ftp remote path entry.
local ftp_rmtdir = dt.new_widget("entry"){
  tooltip ="remote full pathname of the exported file (option var is allowed).\nif the path is a directory (filename omitted), if must ended with a '/'",
  editable=false,
  text = dt.preferences.read("ftp export","ftp_remotedir", "string"),
}

-- user specific tags added to image on successfull export
local ftp_tags = dt.new_widget("entry"){
  tooltip ="additional tags (',' as separator)",
  editable=false,
  text = dt.preferences.read("ftp export","ftp_tags", "string"),
}

-- force remote subdirectories of remote path to be created
local ftp_createdir = dt.new_widget("check_button"){
  tooltip ="force creation of remote directory",
  value=dt.preferences.read( "ftp export", "ftp_createdir", "bool"),
--[[  clicked_callback = function(self)
	if not fe.edit_state then
		self.value = dt.preferences.read( "ftp export", "ftp_createdir", "bool")
	end
  end
--]]
}

-- Edit/Save parameter button depending on the interface state
local ftp_editparam = dt.new_widget("button") {
	label = "Edit Param",
	tooltip="Edit Ftp Parameters",
	clicked_callback = function(self)
		if fe.edit_state then
			-- Edit mode is true, button is then "Save Parameters" so we save parameters
			dt.preferences.write( "ftp export", "ftp_host", "string", ftp_host.text )
			dt.preferences.write( "ftp export", "ftp_port", "string", ftp_port.text )
			dt.preferences.write( "ftp export", "ftp_user", "string", ftp_user.text )
			dt.preferences.write( "ftp export", "ftp_password", "string", ftp_password.text )
			dt.preferences.write( "ftp export", "ftp_remotedir", "string", ftp_rmtdir.text )
			dt.preferences.write( "ftp export", "ftp_tags", "string", ftp_tags.text )
			dt.preferences.write( "ftp export", "ftp_createdir", "bool", ftp_createdir.value )
			
			-- return to viewing mode, then the button is to be changed "Edit parameter"
			fe.edit_state = false
			self.label = "Edit Parameters"
			ftp_host.editable=false
			ftp_user.editable=false
			ftp_password.editable=false
			ftp_port.editable=false
			ftp_rmtdir.editable=false
			ftp_tags.editable=false
			ftp_createdir.sensitive=false
		else
			-- Viewing mode -> changing to "dit mode", button becomes "Save Parameters"
			fe.edit_state = true
			self.label = "Save Parameters"
			ftp_host.editable=true
			ftp_host.editable=true
			ftp_user.editable=true
			ftp_password.editable=true
			ftp_port.editable=true
			ftp_rmtdir.editable=true
			ftp_tags.editable=true
			ftp_createdir.sensitive=true
		end
	end
}

-- cancel button, cancel parameters edit
local ftp_canceledit = dt.new_widget("button")
{
	label = "Cancel",
	tooltip = "Cancel Parameter",
	clicked_callback = function(self)
		if fe.edit_state then
			-- Cancel only applies in edition mode
			-- return to viewing mode
			fe.edit_state = false
			ftp_editparam.label = "Edit Parameters"
			ftp_host.editable=false
			ftp_user.editable=false
			ftp_password.editable=false
			ftp_port.editable=false
			ftp_rmtdir.editable=false
			ftp_tags.editable=false
			
			-- reload last pref values
			ftp_host.text=dt.preferences.read( "ftp export", "ftp_host", "string" )
			ftp_port.text=dt.preferences.read( "ftp export", "ftp_port", "string" )
			ftp_user.text=dt.preferences.read( "ftp export", "ftp_user", "string" )
			ftp_password.text=dt.preferences.read( "ftp export", "ftp_password", "string" )
			ftp_rmtdir.text=dt.preferences.read( "ftp export", "ftp_remotedir", "string" )
			ftp_tags.text=dt.preferences.read( "ftp export", "ftp_tags", "string" )
			ftp_createdir.value=dt.preferences.read( "ftp export", "ftp_createdir", "bool")
			ftp_createdir.sensitive=false
		end
	end
}


--[[
	format_var( v, f ): v value to format, f format to use, according to export specifications
	
	see: https://darktable.gitlab.io/doc/fr/export_selected.html for more information
--]]
local function format_var( v, f)
	local vret 
	
	if v then
		vret = v
	else
		vret  = ""
	end
	
	if ( f == "^^" ) then
		if v then
			vret = string.upper(v)
		end
	elseif ( f == "^" ) then
		if v then
			vret = string.gsub( v, "^(.)(.*)", function( f, r )  return string.upper(f)..r end)
		end
	elseif ( f == ",," ) then
		if v then
			vret = string.lower(v)
		end
	elseif ( f == "," ) then
		if v then
			vret = string.gsub( v, "^(.)(.*)", function( f, r )  return string.lower(f)..r end)
		end
	end

	defvalue = string.match(f, "^-(.*)")
	
	if defvalue then
		if not v then
			vret=defvalue
		end
	end
	
	altvalue = string.match(f, "^+(.*)")
	if altvalue then
		if v then
			vret=altvalue
		end
	end
	
	_,_,offb,offe = string.find(f, "^:(%-?%d+):?(%-?%d+)$")
	
	if offb and v then
		vret = string.sub( vret, tonumber(offb) )
		
		if offe then
			if tonumber(offe) > 0 then
				vret = string.sub( vret, 1, tonumber(offe) )
			else
				if tonumber(offe) < #vret then
					vret = string.sub( vret, 1, #vret + tonumber(offe) )
				end
			end
		end
	end
	
	pattern = string.match(f, "^#(.+)")
	
	if pattern then		
		vret = string.gsub( vret, "^"..pattern, "" )
	end

	pattern = string.match(f, "^%%(.+)")
	
	if pattern then
		vret = string.gsub( vret, pattern.."$", "" )
	end
	
	_,_,pattern, repl = string.find( f, "^//([^/%c]+)/(.*)$")
	
	if pattern then
		if not repl then
			repl = ""
		end
		
		vret = string.gsub( vret, pattern, repl )
	end
	
	_,_,pattern, repl = string.find( f, "^/([^/%c]+)/(.*)$")
	
	if pattern then
		if not repl then
			repl = ""
		end
		
		vret = string.gsub( vret, pattern, repl, 1 )
	end
	
	_,_,pattern, repl = string.find( f, "^/#([^/%c][^/%c]-)/(.*)$")
	
	
	if pattern then
		if not repl then
			repl = ""
		end
		
		vret = string.gsub( vret, "^"..pattern, repl )
	end

	_,_,pattern, repl = string.find( f, "^/%%([^/%c]+)/(.*)$")
	
	if pattern then
		if not repl then
			repl = ""
		end
		
		vret = string.gsub( vret, pattern.."$", repl )
	end
	
	if not vret then
		vret = ""
	end
	
	return vret
end

-- extract each field of exif datetime tag (find this funct on the web... don't remember where!)
local function SeperateTime(str)
    local cleaned = string.gsub(str, '[^%d]',':')
    cleaned = string.gsub(cleaned, '::*',':')  
    local year = string.sub(cleaned,1,4)
    local month = string.sub(cleaned,6,7)
    local day = string.sub(cleaned,9,10)
    local hour = string.sub(cleaned,12,13)
    local min = string.sub(cleaned,15,16)
    local sec = string.sub(cleaned,18,19)
    return {year = year, month = month, day = day, hour = hour, min = min, sec = sec}
end

--[[
	generate and return key/value table of expandable variable of remote path annd command path
	
	Hope that corresponds to export specification, some of them are not very relevant...
--]]
local function ftp_generate_img_keys_values( storage, image,filename, number, total, high_quality, extra_data)
	local kv = {}
	
	kv["ROLL_NAME"]=image.film[1].path
	
	-- file directory of temp exported image file
	kv["FILE_FOLDER"]=string.gsub(filename, "^(.*)([/\\])(.*)$","%1")
	
	-- base name of temp exported image file
	kv["FILE_BASE"]=string.gsub(filename, "^(.*)([/\\])(.*)$","%3")
	
	-- full exported filename
	kv["FILE_NAME"]=filename
	
	-- extension of exported iamge filename
	kv["FILE_EXTENSION"]=string.gsub(kv["FILE_BASE"], "^(.*)([%.])(.*)$","%3")
	
	-- image ID in darktable database
	kv["ID"]=tostring(image.id)
	
	-- image index (clone) of source image
	if image.duplicate_index then
		kv["VERSION"]=tostring(image.duplicate_index)
	else
		kv["VERSION"]="0"
	end
	
	-- image sequence number of export process
	kv["SEQUENCE"]=tostring(number)
	
	-- max width of exported image
	kv["MAX_WIDTH"]=tostring(storage.recommended_width)
	-- max height of exported image
	kv["MAX_HEIGHT"]=tostring(storage.recommended_height)

	curdatetime=os.date("*t")

	-- current date
	kv["YEAR"]=tostring(curdatetime.year)
	kv["MONTH"]=string.format("%02d", curdatetime.month)
	kv["DAY"]=string.format("%02d", curdatetime.day)
	kv["HOUR"]=string.format("%02d", curdatetime.hour)
	kv["MINUTE"]=string.format("%02d", curdatetime.min)
	kv["SECOND"]=string.format("%02d", curdatetime.sec)

	
	-- exif time of image 
	exiftime=SeperateTime(image.exif_datetime_taken)

	kv["EXIF_YEAR"]=exiftime.year
	kv["EXIF_MONTH"]=exiftime.month
	kv["EXIF_DAY"]=exiftime.day
	kv["EXIF_HOUR"]=exiftime.hour
	kv["EXIF_MINUTE"]=exiftime.min
	kv["EXIF_SECOND"]=exiftime.sec
	
	-- exposure, try to format it as 1_nnnn if less than 0, 1_100 for an exposure of 1/100
	if image.exif_exposure then
		if image.exif_exposure > 0 then
			kv["EXIF_EXPOSURE"]=tostring(math.ceil(image.exif_exposure*100)/100)
		else
			kv["EXIF_EXPOSURE"]="1_"..tostring(math.ceil(1/image.exif_exposure))
		end
	end

	-- rounded aperture field
	if image.exif_aperture then	
		kv["EXIF_APERTURE"]=tostring(math.ceil(image.exif_aperture*10)/10)
	end
	
	-- other exif informations
	kv["EXIF_ISO"]=tostring(image.exif_iso)
	kv["EXIF_FOCAL_LENGTH"]=string.format("%d",image.exif_focal_length)
	kv["EXIF_FOCUS_DISTANCE"]=string.format("%.2f",image.exif_focus_distance)
	kv["LONGITUDE"]=tostring(image.longitude)
	kv["LATITUDE"]=tostring(image.latitude)
	kv["ELEVATION"]=tostring(image.elevation)
	kv["STARS"]=tostring(image.rating)
	
	-- color labels, curious field
	kv["LABELS"]=(image.red and "red," or "" )..(image.yellow and "yellow," or "")..(image.green and "green," or "")..(image.blue and "blue," or "")..(image.purple and "purple" or "" )

	kv["LABELS"]=string.gsub(kv["LABELS"],",$","")
	
	
	-- other exif and image informations
	kv["MAKER"]=image.exif_maker
	kv["MODEL"]=image.exif_model
	kv["TITLE"]=image.title
	kv["DESCRIPTION"]=image.description
	kv["CREATOR"]=image.creator
	kv["PUBLISHER"]=image.publisher
	kv["RIGHTS"]=image.rights

	-- user and os specific informations
	if dt.configuration.running_os == "windows" then
		kv["USERNAME"]=os.getenv("USERNAME")
		kv["PICTURES_FOLDER"]= os.getenv("USER_DIRECTORY_PICTURES") and os.getenv("USER_DIRECTORY_PICTURES") or os.getenv("USERPROFILE").."/Pictures"
		kv["HOME"]=os.getenv("USERPROFILE")
		kv["DESKTOP"]=os.getenv("USERPROFILE").."/Desktop"
	else
		kv["USERNAME"]=os.getenv("USER")
		kv["PICTURES_FOLDER"]= os.getenv("USER_DIRECTORY_PICTURES") and os.getenv("USER_DIRECTORY_PICTURES") or os.getenv("HOME")"/Pictures"
		kv["HOME"]=os.getenv("HOME")
		kv["DESKTOP"]=os.getenv("HOME").."/Desktop"
	end
	
	local image_tags_tmp = {}
	image_tags_tmp = dt.tags.get_tags(image)
	
	-- list of comma (",") separated tags of the image, all "darktable" tags are removed
	kv["TAGS"]=""

	for _,t in pairs(image_tags_tmp) do
		if not string.find(t.name, "^darktable|") then
			kv["TAGS"]=kv["TAGS"]..t.name..","
		end
	end

	kv["TAGS"]=string.gsub(kv["TAGS"], ",$", "" )
	

	return kv
end


-- format input string such a remotedir and command path according to expansion var and formats
local function ftp_format_dir( rmtdir, kw )
	local formated_dir=rmtdir
	
	for var in string.gmatch(rmtdir, "$%b()") do
		_, _, v, f = string.find( var, "(%u+[_%u]*)(.*)%)")
		local new_var=format_var(kw[v],f)
		b,e = string.find(formated_dir,var,1, true)
		
		if b and e then
			formated_dir=string.sub(formated_dir, 1, b - 1)..new_var..string.sub( formated_dir, e + 1)
		end
	end
	
	return formated_dir
end

-- Generate full external command path
local function ftp_format_cmd( storage, image,filename, number, total, high_quality, extra_data)

	-- Get de pref command path
	local fullcmd = dt.preferences.read( "ftp export", "command_path", "string" )
	
	-- Generation of keys/values table
	local tb_img_keys = ftp_generate_img_keys_values(  storage, image,filename, number, total, high_quality, extra_data )
	
	-- Adding extra specific ones	
	tb_img_keys["FTP_HOST"]=ftp_host.text
	tb_img_keys["FTP_PORT"]=ftp_port.text
	tb_img_keys["FTP_USER"]=ftp_user.text
	tb_img_keys["FTP_PASSWORD"]=ftp_password.text
	tb_img_keys["FTP_CREATEDIR"]=ftp_createdir.value and "1" or "0"
	tb_img_keys["FTP_CREATEDIR_OPT"]=ftp_createdir.value and dt.preferences.read("ftp_export", "createdir_param", "string" ) or dt.preferences.read("ftp_export", "not_createdir_param", "string" )
	
	-- adding formatted remotedir key/value
	tb_img_keys["FTP_REMOTEDIR"]=ftp_format_dir( ftp_rmtdir.text, tb_img_keys )
	
	
	-- default behavior,using curl syntax	
	if dt.preferences.read("ftp export", "using_curl", "bool") then
		fullcmd=fullcmd.." --silent --fail --user \""..ftp_user.text..":"..ftp_password.text.."\""
		fullcmd=fullcmd.." --upload-file \""..filename.."\""
		
		if ftp_createdir.value then
			fullcmd=fullcmd.." --ftp-create-dirs "
		end
		
		if string.match(ftp_host.text,"^ftp://") == nil then
			fullcmd=fullcmd.." \"ftp://"..ftp_host.text..":"..ftp_port.text
		else
			fullcmd=fullcmd.." \""..ftp_host.text..":"..ftp_port.text
		end
		
		fullcmd=fullcmd.."/"..tb_img_keys["FTP_REMOTEDIR"].."\""
	else
		fullcmd=ftp_format_dir( fullcmd, tb_img_keys )
	end
	
	return fullcmd
end

-- adding tags to image (on successfull)
local function ftp_tag_image( image, tags )

	-- reading and attaching global keywords
	local ltags=dt.preferences.read("ftp export", "global_keywords", "string" )
	local dttag
	
	for ltag in string.gmatch( ltags, "[^,]+") do
			dttag = dt.tags.create(ltag)
			dt.tags.attach(image, dttag )
	end
	
	-- attaching user keywords
	for ltag in string.gmatch( tags, "[^,]+") do
		dttag = dt.tags.create(ltag)
		dt.tags.attach(image, dttag )
	end
end

-- suppress error tags before export
local function ftp_delete_errtags( image )
	local image_tags_tmp = {}
	image_tags_tmp = dt.tags.get_tags(image)
	
	for _,t in pairs(image_tags_tmp) do
		if string.find(t.name, "^darktable|exported|ftp|error") then
			dt.tags.detach( t, image )
		end
		if #t == 0 then
			dt.tags.delete( t )
		end
	end
end


-- adding this storage 
dt.register_storage("ftp_export","ftp export",
	function( storage, image, format, filename, number, total, high_quality, extra_data)
		-- generate full command
		local cmdtorun=ftp_format_cmd(storage, image,filename, number, total, high_quality, extra_data)
		
		-- supperss error tag
		ftp_delete_errtags(image)
		
		-- execute command
		local cretcmd = dt.control.execute(cmdtorun)
		
		if cretcmd == 0 then
			-- success !!!
			--dt.print_error("Command "..cmdtorun.." successfull.")
			ftp_tag_image(image, ftp_tags.text )
		else
			-- error, attaching error number to image
			dt.print_error("Command "..cmdtorun.." FAILED. Exit code:"..tostring(cretcmd))
			
			local gltags = string.gsub(dt.preferences.read("ftp export", "global_keywords", "string"),"(^.*),", "%1")
			
			if #gltags == 0 then
				gltags="darktable|exported|ftp|error|"
			else
				gltags="darktable|exported|ftp".."|error|"
			end
			
			local errtags = dt.tags.create(gltags..tostring(cretcmd))
			
			dt.tags.attach(image, errtags )
		end

	end,
    nil, --finalize
    nil, --supported
    nil, --initialize
    dt.new_widget("box") 
	{
		orientation = "vertical",
		dt.new_widget("box") 
		{
			orientation ="horizontal",
			dt.new_widget("label")
			{
				label = "ftp server "
			},
			ftp_host,
		},
		dt.new_widget("box") 
		{
			orientation ="horizontal",
			dt.new_widget("label")
			{
				label = "ftp port "
			},
			ftp_port,
		},
		dt.new_widget("box") 
		{
			orientation ="horizontal",
			dt.new_widget("label")
			{
				label = "ftp user "
			},
			ftp_user,
		},
		dt.new_widget("box") 
		{
			orientation ="horizontal",
			dt.new_widget("label")
			{
				label = "ftp password "
			},
			ftp_password,
		},
		dt.new_widget("box") 
		{
			orientation ="horizontal",
			dt.new_widget("label")
			{
				label = "remote pathname "
			},
			ftp_rmtdir,
		},
		dt.new_widget("box") 
		{
			orientation ="horizontal",
			dt.new_widget("label")
			{
				label = "force remote directory creation "
			},
			ftp_createdir,
		},
		dt.new_widget("box") 
		{
			orientation ="horizontal",
			dt.new_widget("label")
			{
				label = "additional tags "
			},
			ftp_tags,
		},
		dt.new_widget("box") 
		{
			orientation ="horizontal",
			ftp_editparam,
			ftp_canceledit
		}
	}
)
