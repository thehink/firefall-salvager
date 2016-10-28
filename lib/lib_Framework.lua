if FW then
	return false;
end

require "unicode";
require "table";
require "math";
require "unicode";
require "lib/lib_InterfaceOptions"
require "lib/lib_EventDispatcher";
require "lib/lib_ChatLib";

FW = {};
local DISPATCHER = EventDispatcher.Create();
local OPTIONS = {};
local TEMP = {};
local DATA = {};

local LOCALSTRINGS = {EN = {}};
		
local QUEUEDRequests = {};
local HFRAME;

OPERATOR = {};

ADDON = {
	Name = "",
	Version = "0.0.0",
	Author = "",
	Ready = false;
	UpdateCheckURL = nil,
}

DISPATCHER:Delegate(FW);

function FW.Init(options)
	ADDON.Name = options.Name or "";
	ADDON.Version = options.Version or "0.0.0";
	ADDON.Author = options.Author or "";
	ADDON.UpdateCheckURL = options.UpdateCheckURL;

	if(options.InterfaceOptions) then
		InterfaceOptions.SaveVersion(1.0)
		InterfaceOptions.NotifyOnDefaults(true);
		InterfaceOptions.SetCallbackFunc(FW.OnOptionChange, ADDON.Name);
	end
	
	FW:AddHandler("UI_EVENT:ON_EXIT_GAME", FW.SaveAllData);
	FW:AddHandler("UI_EVENT:ON_PRE_RELOADUI", FW.SaveAllData);
	FW:AddHandler("UI_EVENT:ON_COMPONENT_LOAD", FW.ReadyCheck);
	FW:AddHandler("UI_EVENT:ON_PLAYER_READY", FW.ReadyCheck);
	FW:AddHandler("UI_EVENT:ON_STREAM_PROGRESS", FW.ReadyCheck);
	
	FW:AddHandler("UI_EVENT:ON_STREAM_PROGRESS", FW.LoadingCheck);
	FW:AddHandler("UI_EVENT:ON_COMPONENT_LOAD", FW.LoadingCheck);
end

function FW.LoadingCheck()
	if Game.GetLoadingProgress() == 1 then
		FW:DispatchEvent("OnZoneLoaded");
	end
end

function FW.ReadyCheck()
	OPERATOR.INGAME_HOST = System.GetOperatorSetting("ingame_host");
	OPERATOR.API_HOST = System.GetOperatorSetting("clientapi_host");
	
	FW.SetLocale(unicode.upper(System.GetLocale()));

	if not ADDON.Ready and Game.GetLoadingProgress() == 1 and Player.IsReady() then
		FW:RemoveHandler("UI_EVENT:ON_COMPONENT_LOAD", FW.ReadyCheck);
		--FW:RemoveHandler("UI_EVENT:ON_PLAYER_READY", FW.ReadyCheck);
		--FW:RemoveHandler("UI_EVENT:ON_STREAM_PROGRESS", FW.ReadyCheck);
		ADDON.Ready = true;
		callback(function()
			FW:DispatchEvent("OnReady");
		end, nil, .5);
	end
	return ADDON.Ready;
end

---------------------------
--	OnUIEvent
---------------------------

function OnUIEvent(args)
	FW:DispatchEvent("UI_EVENT:" .. args.event:upper(), args);
end

---------------------------
--	HTTP Request
---------------------------

function FW.HTTPRequest(args)
	if not HTTP.IsRequestPending(args.url) then
		HTTP.IssueRequest(args.url, args.method or "GET", args.data, function(resp, err)
			if not err and type(args.OnSuccess) == "function" then
				args.OnSuccess(resp, args);
			elseif err and type(args.OnError) == "function" then
				args.OnError(err, args);
			end
			
			if QUEUEDRequests[args.url] and #QUEUEDRequests[args.url] > 0 then
				FW.HTTPRequest(QUEUEDRequests[args.url][1]);
				table.remove(QUEUEDRequests[args.url], 1);
			end
			
		end);
	else
		--Request to this url already active, queue this until the request is done.
		if not QUEUEDRequests[args.url] then
			QUEUEDRequests[args.url] = {};
		end
		table.insert(QUEUEDRequests[args.url], args);
	end
end

---------------------------
--	Update Checker
---------------------------

function FW.CheckForUpdate()
	if(ADDON.UpdateCheckURL) then
		FW.HTTPRequest({
			url = ADDON.UpdateCheckURL,
			method = "GET",
			OnSuccess = function(resp)
				if(resp and resp.version ~= ADDON.Version) then
					FW.Msg("New version available " .. ADDON.Version .. " => " .. resp.version);
				end
			end
		});
	end
end

---------------------------
--	Data
---------------------------
function FW.SetData(key, value)
	DATA[key] = value;
end

function FW.GetData(key)
	return DATA[key];
end

function FW.SaveAllData()
	Component.SaveSetting("DATA", DATA);
end

function FW.GetAllData()
	DATA = Component.GetSetting("DATA") or {};
end

---------------------------
--	Interface Options
---------------------------

function FW.StartGroup(args)
	InterfaceOptions.StartGroup({id = args.id, label = args.label})
end

function FW.StopGroup()
	InterfaceOptions.StopGroup();
end

function FW.AddInterfaceOption(type, args)
	FW.SetOption(args.id, args.default);
	InterfaceOptions[type](args);
end

function FW.AddCheckBox(args)
	FW.AddInterfaceOption("AddCheckBox", args);
end

function FW.AddChoiceMenu(args)
	FW.AddInterfaceOption("AddChoiceMenu", args);
	if(args.options) then
		for i,v in ipairs(args.options) do
			InterfaceOptions.AddChoiceEntry({menuId = args.id, val = v.value, label = v.label, subtab = args.subtab})
		end
	end
end

function FW.AddColorPicker(args)
	FW.AddInterfaceOption("AddColorPicker", args);
end

function FW.AddTextInput(args)
	FW.AddInterfaceOption("AddTextInput", args);
end

function FW.AddSlider(args)
	FW.AddInterfaceOption("AddSlider", args);
end

function FW.OnOptionChange(key, value)
	FW.SetOption(key, value);
	FW:DispatchEvent("OnOptionChange", {key=key, value=value});
	FW:DispatchEvent("OnOptionChange:"..key, {key=key, value=value});
end

function FW.GetOption(key)
	return TEMP[key] or OPTIONS[key];
end

function FW.SetOption(key, value)
	OPTIONS[key] = value;
end

function FW.SetTempOption(key, value)
	TEMP[key] = value;
end

---------------------------
--	Widgets
---------------------------

function FW.GetHiddenFrame()
	if not HFRAME then
		HFRAME = Component.CreateFrame("HudFrame");
		HFRAME:Hide(true);
	end
	
	return HFRAME;
end

function FW.CreateWidget(widget)
	return Component.CreateWidget(widget, GetHiddenFrame());
end

---------------------------
--	Localization
---------------------------

function FW.AddLocalization(lang, words)
	LOCALSTRINGS[lang] = {};
	for k,word in pairs(words) do
		LOCALSTRINGS[lang][k] = word;
	end
end

function FW.GetSupportedLanguages()
	local list = {};
	for k,_ in pairs(LOCALSTRINGS) do
		table.insert(list, k);
	end
	return list;
end

function FW.SetLocale(lang)
	FW.SetOption('LANG', lang);
	if(LOCALSTRINGS[lang]) then
		CurrentLocale = lang;
	end
end

function FW.GetString(k)
	local CurrentLocale = FW.GetOption('LANG') or "EN";
	if(LOCALSTRINGS[CurrentLocale][k]) then
		return LOCALSTRINGS[CurrentLocale][k];
	elseif(Component.LookupText(k) ~= '') then
		return Component.LookupText(k);
	else
		return k;
	end
end

---------------------------
--	Utils
---------------------------
function Round(num, idp)
	if(type(num) == "number") then
		local mult = 10^(idp or 0)
		return math.floor(num * mult + 0.5) / mult
	else
		return 0
	end
end

function Msg(message, channel)
	--Component.GenerateEvent("MY_CHAT_MESSAGE", {channel=channel or "system", text="[".. ADDON.Name .."]: "..tostring(message)})
	Component.GenerateEvent("MY_SYSTEM_MESSAGE", {json=tostring({channel=channel or "system", text="[".. ADDON.Name .."]: "..tostring(message)})})
end

function Notify(args)
	Component.GenerateEvent("MY_NOTIFY", {text=args.text, color=args.color or "#0099DD", dur=args.dur or 5});
end

function FW.PlayerTag(name)
	-- return tag, name;
	return name:match("%[(.*)%] (.*)$");
end

function InArray(array, value)
	for i=1, #array do
		if  array[i] == value then
			return i;
		end
	end
	return false;
end

function ConcatenateArray(arr1, arr2)
	for i=1, #arr2 do
		table.insert(arr1, arr2[i]);
	end
end

function escape(x)
  return (x:gsub('%%', '%%%%')
           :gsub('%^', '%%%^')
           :gsub('%$', '%%%$')
           :gsub('%(', '%%%(')
           :gsub('%)', '%%%)')
           :gsub('%.', '%%%.')
           :gsub('%[', '%%%[')
           :gsub('%]', '%%%]')
           :gsub('%*', '%%%*')
           :gsub('%+', '%%%+')
           :gsub('%-', '%%%-')
           :gsub('%?', '%%%?'))
end

function FW.Log(data)
	log(tostring(data));
end