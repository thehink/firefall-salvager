--================================================================
-- Salvager
-- by Thehink
--================================================================

require "math";
require "unicode";
require "lib/lib_InterfaceOptions";
require "lib/lib_Slash";
require "lib/lib_NestedList";
require "lib/lib_WebCache";
require "lib/lib_Callback2";
require "lib/lib_Slash";
require "lib/lib_Items";
require "lib/lib_Tooltip";
require "lib/lib_Button";
require "lib/lib_DropDownList";
require "lib/lib_CheckBox";
require "lib/lib_Callback2";
require "lib/lib_Colors";

require "./lib/lib_Framework";
require "./lib/lib_ListScroller";
require "./localization/EN";
require "./localization/FR";
require "./localization/DE";

FW.Init({
	Name = "Salvager",
	Version = "0.95",
	Author = "Thehink",
	InterfaceOptions = false,
});

--================================================================
-- Variables
--================================================================

local INPUT_STATE = 0;
local CLAIM_STATE = 1;

local SALVAGE_SALVAGING_STATE = 1;
local SALVAGE_SUCCESS_STATE = 2;
local SALVAGE_NONE_STATE = 0;

local FRAME = Component.GetFrame("Main");
local FOSTER = FRAME:GetChild("foster");
local WD_CATEGORIES = Component.GetWidget("InventoryCategories");
local W_FILTERS = Component.GetWidget("InventoryFilters");
local W_FILTERS_BG = Component.GetWidget("InventoryFiltersBG");
local W_INVENTORY = Component.GetWidget("ItemList");
local W_QUEUE = Component.GetWidget("QueuedItems");
local W_CLOSE_BUTTON = Component.GetWidget("closeButton");
local W_START_SALVAGE = Component.GetWidget("StartSalvage");
local W_CLEAR_QUEUE = Component.GetWidget("ClearQueue");
local W_ADD_ALL_ITEMS = Component.GetWidget("AddAllToQueue");
local W_SortChoice = Component.GetWidget("SortChoice");
local W_SearchInput = Component.GetWidget("SearchInput");
local W_REWARDS_ROW = Component.GetWidget("RewardItems");

local w_REWARDS = {};

local DD_SORT;
local SORT_METHOD = {};
local SortMethod;
local SearchFilter = "";
local cb_Search;

local TOOLTIP_POPUP;
local TOOLTIP_FRAME;

local INVENTORY_SCROLLER;
local QUEUE_SCROLLER;

local SLASH = {};
local SALVAGE_QUEUE = {};
local INVENTORY = {};
local SALVAGE_BTN;

local SalvagingProcessEnabled = false;
local CurrentItemSalvaging;
local SalvageState = INPUT_STATE;
local InZone = false;

local RarityValues = {
	legendary = 5,
	epic = 4,
	rare = 3,
	uncommon = 2,
	common = 1,
	salvage = 0,
};

local FILTERS = {};
local SelectedCategory;
local ActiveFilters = {};
local CATEGORIES = {
	{name = "ALL", filters = {}},
	{name = "OTHER", filters = {"OTHER"}},
	{name = "GEAR", filters = {'GEAR'}, children = {
		{name = "WEAPONS", filters = {'WEAPON'}},
		{name = "ABILITIES", filters = {'ABILITY'}},
		{name = "MODULES", filters = {'MODULE'}},
	}},
};

local FILTER_LIST = {
	{name = "NEW", filter = "NEW"},
	{name = "LOOTED", filter = "LOOTED", group = "GearType"},
	{name = "CRAFTED", filter = "CRAFTED", group = "GearType"},
	{name = "BROKEN", filter = "BROKEN"},
	{name = "PRESTIGE", filter = "PRESTIGE"},
	{name = "POST_MILESTONE", filter = "POST_MILESTONE"},
	{name = "PRE_MILESTONE", filter = "PRE_MILESTONE"},
	{name = "COMMON", filter = "COMMON"},
	{name = "UNCOMMON", filter = "UNCOMMON"},
	{name = "RARE", filter = "RARE"},
	{name = "EPIC", filter = "EPIC"},
	{name = "LEGENDARY", filter = "LEGENDARY"},
};

local Items, Resources;
local InventoryIsDirty = true;

local cb_SalvageError;

--================================================================
-- UI Events
--================================================================

FW:AddHandler("OnReady", function()
	Component.GetWidget("Title"):SetText(ADDON.Name .. " " .. ADDON.Version);
	Component.GetWidget("InventoryTitle"):SetText(FW.GetString("INVENTORY"));
	Component.GetWidget("QueueTitle"):SetText(FW.GetString("SALVAGE_QUEUE"));

	LIB_SLASH.BindCallback({slash_list = "salvage salvager", description = "", func = SLASH.ToggleSalvager});
	
	TOOLTIP_FRAME = Component.CreateFrame("PanelFrame")
	TOOLTIP_FRAME:SetDims("right:75%; top:25%; width:200; height:400;")
	TOOLTIP_FRAME:SetDepth(-5)
	TOOLTIP_FRAME:Hide()
	
	local group = Component.CreateWidget([[<Group dimensions="dock:fill" style="visible:false"/>]], TOOLTIP_FRAME)
	TOOLTIP_POPUP = LIB_ITEMS.CreateToolTip(group)

	InitInventory();
	InitQueue();
	InitCategories();
	InitFilters();
	InitButtons();
	InitSort();
end);

FW:AddHandler("UI_EVENT:ON_SALVAGE_RESPONSE", function(args)

	for k,v in ipairs(args) do
		AddReward(v);
	end

	if SalvageState == INPUT_STATE and CurrentItemSalvaging then
		if cb_SalvageError then
			cancel_callback(cb_SalvageError);
			cb_SalvageError = nil;
		end
	
		local rewards = #args;

		if rewards > 0 then
			CurrentItemSalvaging.SetSalvagingStatus(SALVAGE_SUCCESS_STATE);
			SalvageState = CLAIM_STATE;
			local success = false;
			if CurrentItemSalvaging.item_id then
				Player.ClaimSalvageItemRewards(CurrentItemSalvaging.item_id)
			else
				Player.ClaimSalvageResourceRewards(CurrentItemSalvaging.item_sdb_id, CurrentItemSalvaging.quantity, CurrentItemSalvaging.resource_type or 0)
			end
		else
			--No rewards == salvage error
			--try again
			SalvageState = INPUT_STATE;
			CurrentItemSalvaging.SetSalvagingStatus(SALVAGE_NONE_STATE);
			Callback2.FireAndForget(SalvageNextItem, nil, 1.0);
		end
	elseif SalvageState == CLAIM_STATE and CurrentItemSalvaging then
		SalvageState = INPUT_STATE;
		CurrentItemSalvaging.OnSalvaged();
		CurrentItemSalvaging = nil;
		Callback2.FireAndForget(SalvageNextItem, nil, 0.8);
	else
		
	end
end);

FW:AddHandler("UI_EVENT:ON_EXIT_ZONE", function(args)
	InZone = false;
end);

FW:AddHandler("UI_EVENT:ON_PLAYER_READY", function(args)
	InZone = true;
	SalvageNextItem();
end);

function OnInventoryUpdate()
	InventoryIsDirty = true;
end

FW:AddHandler("UI_EVENT:ON_RESOURCES_CHANGED", OnInventoryUpdate);
FW:AddHandler("UI_EVENT:ON_RESOURCE_ITEM_CHANGED", OnInventoryUpdate);
FW:AddHandler("UI_EVENT:ON_INVENTORY_ITEM_CHANGED", OnInventoryUpdate);

function OnEscape()
	Hide();
end

function OnClose()
	Component.SetInputMode(nil);
end

function OnOpen()
	if InventoryIsDirty then
		callback(UpdateInventoryDisplay, nil, .1);
	end
	Component.SetInputMode("cursor");
end


--================================================================
-- 
--================================================================

function UpdateInventory()
	Items, Resources = Player.GetInventory();
	
	InventoryIsDirty = false;
	
	for i,item in ipairs(Items) do
		if item.repair_pool then
			table.insert(item.attributes,
			{
				["inverse"] =false, 
				["format"] ="%d", 
				["value"] =item.repair_pool, 
				["stat_id"] =-1, 
				["display_name"] = FW.GetString("REPAIR_POOL"), 
				["name"] ="repair_pool"
			});
		end
	
		if item.prestige then
		
			item.name = item.prestige.prestige_title .. " " .. item.name;
		
			table.insert(item.attributes,
			{
				["inverse"] = false, 
				["format"] = "%d", 
				["value"] = item.prestige.next_prestige, 
				["stat_id"] = -1, 
				["display_name"] = FW.GetString("NEXT_PRESTIGE"), 
				["name"] = "next_prestige"
			});
			--[[
			table.insert(item.attributes,
			{
				["inverse"] =false, 
				["format"] ="%q", 
				["value"] =item.prestige.prestige_title, 
				["stat_id"] =-1, 
				["display_name"] ="Title", 
				["name"] ="prestige_title"
			});]]
			table.insert(item.attributes,
			{
				["inverse"] =false, 
				["format"] ="%d", 
				["value"] =item.prestige.current_prestige, 
				["stat_id"] =-1, 
				["display_name"] = FW.GetString("PRESTIGE"), 
				["name"] ="current_prestige"
			});
			table.insert(item.attributes,
			{
				["inverse"] =false, 
				["format"] ="%d", 
				["value"] =item.prestige.prestige_level, 
				["stat_id"] =-1, 
				["display_name"] = FW.GetString("PRESTIGE_LEVEL"), 
				["name"] ="prestige_level"
			});
		end
	end
	
end

--================================================================
-- Search
--================================================================

function OnSearchInput()
	SearchFilter = W_SearchInput:GetText();
	
	if cb_Search then
		cancel_callback(cb_Search);
		cb_Search = nil;
	end
	
	cb_Search = callback(function()
		UpdateInventoryDisplay();
	end, nil, 0.7);
end

function OnSearchSubmit()
	if cb_Search then
		cancel_callback(cb_Search);
		cb_Search = nil;
	end
	UpdateInventoryDisplay();
end

--================================================================
-- Sort
--================================================================

function InitSort()
	DD_SORT = DropDownList.Create(W_SortChoice, "Demi_10");
	DD_SORT:SetListMaxSize(10);
	DD_SORT:BindOnSelect(OnSelect)
	local sortmethods = {"SORT", "QUALITY", "PRESTIGE", "DURABILITY"};
	for i,v in ipairs(sortmethods) do
		DD_SORT:AddItem(FW.GetString(v), v);
	end
	SortMethod = "SORT";
end

function OnSelect(args)
	SortMethod = DD_SORT:GetSelected();
	UpdateInventoryDisplay();
end


--================================================================
-- Sort Methods
--================================================================
--[[
SORT_METHOD["Stage & Quality"] = function(a, b)
	local aItemInfo = Game.GetItemInfoByType(a.item_sdb_id);
	local bItemInfo = Game.GetItemInfoByType(b.item_sdb_id);
	
	if(a.name < b.name) then
		return true;
	elseif(aItemInfo.tier and bItemInfo.tier and aItemInfo.tier.level < bItemInfo.tier.level and a.name == b.name) then
		return true;
	elseif(a.name == b.name) then
		return (a.quality or 0) < (b.quality or 0);
	end
end]]

SORT_METHOD["QUALITY"] = function(a, b)
	if(a.quality and b.quality and a.quality > b.quality or RarityValues[a.rarity] > RarityValues[b.rarity]) then
		return true;
	elseif(a.quality and b.quality and a.quality == b.quality or not (a.quality and b.quality) and a.rarity == b.rarity) then
		return a.name < b.name;
	end
end

SORT_METHOD["PRESTIGE"] = function(a, b)
	local aPres, bPres = a.prestige and a.prestige.current_prestige or 0, b.prestige and b.prestige.current_prestige or 0;
	return aPres > bPres;
end

SORT_METHOD["SORT"] = function(a, b)
	return a.name < b.name;
end

SORT_METHOD["DURABILITY"] = function(a, b)
	if a.durability and b.durability and a.durability.current < b.durability.current then
		return true;
	elseif(a.durability and b.durability and a.durability.current == b.durability.current and a.repair_pool < b.repair_pool) then
		return true;
	elseif not (a.durability and b.durability) then
		return a.name < b.name;
	end
end

--================================================================
-- Filters
--================================================================

function FILTERS.OTHER(item, itemInfo)
	return not FILTERS.ABILITY(item, itemInfo) and
		   not FILTERS.WEAPON(item, itemInfo) and
		   not FILTERS.MODULE(item, itemInfo);
end

function FILTERS.GEAR(item, itemInfo)
	return FILTERS.ABILITY(item, itemInfo) or
		   FILTERS.WEAPON(item, itemInfo) or
		   FILTERS.MODULE(item, itemInfo);
end

function FILTERS.NEW(item, itemInfo)
	return item.flags.is_new;
end

function FILTERS.PRE_MILESTONE(item, itemInfo)
	local excluded = {
		["86398"] = true,   -- half digested
		["30408"] = true,	-- broken bandit
		["86404"] = true,	-- chosen tech
		["52206"] = true,	-- recovered chosen tech
		["77418"] = true,	-- Damaged Cycle Plating
		["77419"] = true,	-- Damaged Drive Circuit Board
		["77420"] = true,	-- Damaged Ignition Drive System
	}

	return tonumber(item.item_sdb_id) < 85579 and not excluded[tostring(item.item_sdb_id)];
end

function FILTERS.POST_MILESTONE(item, itemInfo)
	return tonumber(item.item_sdb_id) > 85579;
end

function FILTERS.BROKEN(item, itemInfo)
	return item.flags.is_broken;
end

function FILTERS.ABILITY(item, itemInfo)
	return itemInfo.type == "ability_module";
end

function FILTERS.WEAPON(item, itemInfo)
	return itemInfo.type == "weapon";
end

function FILTERS.MODULE(item, itemInfo)
	return itemInfo.type == "frame_module";
end

function FILTERS.PRESTIGE(item, itemInfo)
	return item.prestige and item.prestige.prestige_level > 0;
end

function FILTERS.CRAFTED(item, itemInfo)
	log(tostring(item));
	return item.repair_pool and item.repair_pool > 0;
end

function FILTERS.LOOTED(item, itemInfo)
	return not item.repair_pool or item.repair_pool and item.durability and item.repair_pool == 0;
end

function FILTERS.COMMON(item, itemInfo)
	return item.quality and item.quality > 0 and item.quality < 401 or not item.quality and item.rarity == "common";
end

function FILTERS.UNCOMMON(item, itemInfo)
	return item.quality and item.quality > 400 and item.quality < 701 or not item.quality and item.rarity == "uncommon";
end

function FILTERS.RARE(item, itemInfo)
	return item.quality and item.quality > 700 and item.quality < 901 or not item.quality and item.rarity == "rare";
end

function FILTERS.EPIC(item, itemInfo)
	return item.quality and item.quality > 900 and item.quality < 1000 or not item.quality and item.rarity == "epic";
end

function FILTERS.LEGENDARY(item, itemInfo)
	return item.quality and item.quality > 999 or not item.quality and item.rarity == "legendary";
end


function FilterItem(item)
	local passes = 0;
	local itemInfo = Game.GetItemInfoByType(item.item_sdb_id);
	for _,v in pairs(ActiveFilters) do
		if FILTERS[v] and FILTERS[v](item, itemInfo) then
			passes = passes + 1;
		else
			break;
		end
	end
	
	if passes == #ActiveFilters then
		return true;
	end
	return false;
end
--================================================================
-- Salvage
--================================================================

function Show()
	FRAME:Show(true);
end

function Hide()
	FRAME:Hide(true);
end

function ToggleSalvage()
	if SalvagingProcessEnabled then
		SalvagingProcessEnabled = false;

		SALVAGE_BTN:SetText(FW.GetString("SALVAGE"));
		SALVAGE_BTN:TintPlate("00FF00");
	elseif #SALVAGE_QUEUE > 0 then
		ClearRewards();
		SALVAGE_BTN:SetText(FW.GetString("ABORT_SALVAGE"));
		SALVAGE_BTN:TintPlate("FF0000");
		
		SalvagingProcessEnabled = true;
		SalvageNextItem();
	end
end

function SalvageNextItem()
	if SalvagingProcessEnabled and #SALVAGE_QUEUE > 0 then
		if InZone then
			CurrentItemSalvaging = SALVAGE_QUEUE[1];
			CurrentItemSalvaging.SetSalvagingStatus(SALVAGE_SALVAGING_STATE);
			if CurrentItemSalvaging.item_id then
				Player.RequestSalvageItem(CurrentItemSalvaging.item_id);
			else
				Player.RequestSalvageResource(CurrentItemSalvaging.item_sdb_id, CurrentItemSalvaging.quantity, CurrentItemSalvaging.resource_type or 0);
			end
			
			cb_SalvageError = callback(function()
				SalvageState = INPUT_STATE;
				SalvageNextItem();
			end, nil, 1.2);
			
		end
	elseif SalvagingProcessEnabled then
		if not FRAME:IsVisible() then
			Notify({
				text = FW.GetString("SALVAGE_DONE");
			});
		end
		ToggleSalvage(false);
	elseif not SalvagingProcessEnabled then
		for i=1, #SALVAGE_QUEUE do
			SALVAGE_QUEUE[i].SetSalvagingStatus(SALVAGE_NONE_STATE);
		end
	end
end
--================================================================
-- Rewards
--================================================================

function AddReward(args)
	--[[
		args = {
			item_sdb_id = 10,
			quantity = 123,
			quality = 0,
		}
	]]

	local itemInfo = Game.GetItemInfoByType(args.item_sdb_id);
	local GROUP = {};
	local key = tostring(args.item_sdb_id) .. " - " ..tostring(args.quality);
	
	if w_REWARDS[key] then
		GROUP = w_REWARDS[key];
	else
		GROUP = {
			item_sdb_id = args.item_sdb_id,
			quantity = 0,
			quality = args.quality,
			WIDGET = Component.CreateWidget("RewardBox", W_REWARDS_ROW);
		}
		
		local count = W_REWARDS_ROW:GetChildCount()-1;
		GROUP.WIDGET:SetDims("height:80; width:80; center-y:50%; left:" .. count * 90 + 25);
		
		local color = "#000000";
		
		if args.quality > 0 then
			color = LIB_ITEMS.GetResourceQualityColor(args.quality);
		else
			color = LIB_ITEMS.GetItemColor(itemInfo);
		end
		
		local BTN = GROUP.WIDGET:GetChild("ItemBox");
		
		BTN:BindEvent("OnMouseEnter", function() 
			TOOLTIP_POPUP:DisplayInfo(itemInfo);
			local args = TOOLTIP_POPUP:GetBounds();
			Tooltip.Show(TOOLTIP_POPUP.GROUP, args);
			GROUP.WIDGET:GetChild("ItemBox.icon"):ParamTo("exposure", 0.5, .15);
		end);
		BTN:BindEvent("OnMouseLeave", function()
			Tooltip.Show(nil);
			GROUP.WIDGET:GetChild("ItemBox.icon"):ParamTo("exposure", 0.0, .15);
		end);
		
		GROUP.WIDGET:GetChild("ItemBox.bg"):SetParam("tint", color);
		--GROUP.WIDGET:GetChild("ItemBox.bg"):SetParam("glow", color);
		GROUP.WIDGET:GetChild("ItemBox.icon"):SetUrl(itemInfo.web_icon);
		w_REWARDS[key] = GROUP;
	end
	
	GROUP.WIDGET:GetChild("ItemBox.icon"):ParamTo("exposure", 1.0, .2);
	GROUP.WIDGET:GetChild("ItemBox.icon"):QueueParam("exposure", 0.0, .5);
	
	GROUP.WIDGET:GetChild("ItemBox.quantity"):ParamTo("exposure", 1.0, .5);
	GROUP.WIDGET:GetChild("ItemBox.quantity"):QueueParam("exposure", 0.0, .5);
	
	GROUP.quantity = GROUP.quantity + args.quantity;
	GROUP.WIDGET:GetChild("ItemBox.quantity"):SetText(tostring(GROUP.quantity));
end

function ClearRewards()
	for k,v in pairs(w_REWARDS) do
		Component.RemoveWidget(v.WIDGET);
		w_REWARDS[k] = nil;
	end
end

--================================================================
-- Buttons
--================================================================

function InitButtons()
	SALVAGE_BTN = Button.Create(W_START_SALVAGE);
	SALVAGE_BTN:SetText(FW.GetString("SALVAGE"));
	SALVAGE_BTN:TintPlate("00FF00");
	SALVAGE_BTN:SetFont("Demi_11")
	SALVAGE_BTN:Bind(ToggleSalvage)
	
	local BTN2 = Button.Create(W_CLEAR_QUEUE);
	BTN2:SetText(FW.GetString("CLEAR"));
	BTN2:TintPlate("FF1100");
	BTN2:SetFont("Demi_11")
	BTN2:Bind(ClearQueue)
	
	local BTN3 = Button.Create(W_ADD_ALL_ITEMS);
	BTN3:SetText(FW.GetString("ADD_ALL_TO_QUEUE"));
	BTN3:TintPlate("FF9707");
	BTN3:SetFont("Demi_11")
	BTN3:Bind(AddAllCurrentItemsToQueue)
	
	W_CLOSE_BUTTON:BindEvent("OnMouseDown", function()
		Hide();
	end);
	local X = W_CLOSE_BUTTON:GetChild("X");
	W_CLOSE_BUTTON:BindEvent("OnMouseEnter", function() X:ParamTo("exposure", 1, 0.15); end);
	W_CLOSE_BUTTON:BindEvent("OnMouseLeave", function() X:ParamTo("exposure", 0, 0.15); end);
end

--================================================================
-- UI
--================================================================
local WIDGETS = {};
function GetRowWidget(item, FOSTER)
	if WIDGETS[item.item_sdb_id .. tostring(item.item_id)] then
		local WIDGET = WIDGETS[item.item_sdb_id .. tostring(item.item_id)];
		WIDGET:GetChild("row.bg"):SetParam("alpha", 0.0);
		return WIDGET;
	end
	local WIDGET = Component.CreateWidget("InventoryRow", FOSTER);
	
	local TITLE = WIDGET:GetChild("row.title");
	local TF = LIB_ITEMS.GetNameTextFormat(item, {quality=item.quality});
	TF:ApplyTo(TITLE);
	
	WIDGET:SetDims("width:100%; height:22;");
	
	--TITLE:SetText(item.name);
	
	WIDGET:GetChild("row.quantity"):SetText("x"..item.quantity);
	if item.durability then
		WIDGET:GetChild("row.quantity"):SetTextColor(Colors.MakeGradient("condition", item.durability / 1000));
	end
	
	if item.prestige then
		WIDGET:GetChild("row.prestige"):SetText(item.prestige.prestige_level);
		WIDGET:GetChild("row.prestige_progress"):SetDims("height:100%; width:".. 100 * item.prestige.current_prestige / item.prestige.next_prestige .. "%; left:0");
		WIDGET:GetChild("row.prestige_progress"):Show(true);
	end
	WIDGETS[item.item_sdb_id .. tostring(item.item_id)] = WIDGET;
	return WIDGET;
end

--================================================================
-- Queue
--================================================================

function InitQueue()
	--QUEUE_SCROLLER = RowScroller.Create(W_QUEUE);
	--QUEUE_SCROLLER:SetSlider(RowScroller.SLIDER_DEFAULT);
	--QUEUE_SCROLLER:SetSpacing(2);

	QUEUE_SCROLLER = ListScroller.Create(W_QUEUE);
	--[[
	callback(function()
		Msg("Start");
		callback(function()
			for i = 1, 2000 do
				local WIDGET = Component.CreateWidget("InventoryRow", QUEUE_SCROLLER.HIDDEN);
				WIDGET:SetDims("width: 100%; height:20;");
				
				
				local TITLE = WIDGET:GetChild("row.title");
				local TF = LIB_ITEMS.GetNameTextFormat(Game.GetItemInfoByType(10), {quality=nil});
				TF:ApplyTo(TITLE);
				
				QUEUE_SCROLLER:AddRow(WIDGET);
			end
		end, nil, 0.1);
		Msg("Stop");
	end, nil, 2);]]
end

function InsertItemToQueue(item)
	local WIDGET = GetRowWidget(item, QUEUE_SCROLLER.HIDDEN);
	local ROW = QUEUE_SCROLLER:AddRow(WIDGET);
	
	if type(item.durability) == "number" then
		item.durability = {current=item.durability};
	end
	
	if not item.certifications then
		item.certifications = {};
	end
	
	item.SetSalvagingStatus = function(state)
		if state == SALVAGE_SALVAGING_STATE then
			item.salvaging = true;
			WIDGET:GetChild("row.bg"):ParamTo("alpha", 0.7, 0.15);
			WIDGET:GetChild("row.bg"):ParamTo("tint", "#FF8316", 0.15);
		elseif state == SALVAGE_SUCCESS_STATE then
			item.salvaging = true;
			WIDGET:GetChild("row.bg"):ParamTo("alpha", 0.7, 0.15);
			WIDGET:GetChild("row.bg"):ParamTo("tint", "#0FAD1A", 0.15);
		else
			item.salvaging = false;
			WIDGET:GetChild("row.bg"):ParamTo("alpha", 0.0, 0.15);
			WIDGET:GetChild("row.bg"):ParamTo("tint", "#112233", 0.15);
		end
	end
	
	item.ReturnToInventory = function()
		if not item.salvaging then
			ROW:Remove();
			for i,v in ipairs(SALVAGE_QUEUE) do
				if v == item then
					table.remove(SALVAGE_QUEUE, i);
				end
			end
			if FilterItem(item) then
				AddInventoryItem(item, true);
			end
		end
	end
	
	item.OnSalvaged = function()
		ROW:Remove();
		for i,v in ipairs(SALVAGE_QUEUE) do
			if v == item then
				table.remove(SALVAGE_QUEUE, i);
			end
		end
	end
	
	
	ROW:AddHandler("OnMouseEnter", function()
		TOOLTIP_POPUP:DisplayInfo(item)
		local args = TOOLTIP_POPUP:GetBounds()
		Tooltip.Show(TOOLTIP_POPUP.GROUP, args)
		WIDGET:GetChild("row.bg"):ParamTo("alpha", 0.7, 0.15);
	end);
	ROW:AddHandler("OnMouseLeave", function()
		Tooltip.Show(nil);
		if not item.salvaging then
			WIDGET:GetChild("row.bg"):ParamTo("alpha", 0.0, 0.15);
		end
	end);

	ROW:AddHandler("OnMouseUp", item.ReturnToInventory);
	
	--WIDGET:GetChild("row.bg"):SetParam("alpha", "1.0");
	--WIDGET:GetChild("row.bg"):ParamTo("alpha", "0.0", 0.5);

	table.insert(SALVAGE_QUEUE, item);
end

function ClearQueue()
	for i=#SALVAGE_QUEUE, 1, -1 do
		if not SALVAGE_QUEUE[i].salvaging then
			SALVAGE_QUEUE[i].ReturnToInventory();
		end
	end
end

function ItemIsInQueue(v)
	for i=#SALVAGE_QUEUE, 1, -1 do
		if v.item_sdb_id == SALVAGE_QUEUE[i].item_sdb_id and v.item_id == SALVAGE_QUEUE[i].item_id then
			return true;
		end
	end
end

--================================================================
-- Inventory
--================================================================

function InitInventory()
	INVENTORY_SCROLLER = ListScroller.Create(W_INVENTORY);
	--INVENTORY_SCROLLER:SetSlider(RowScroller.SLIDER_DEFAULT);
	--INVENTORY_SCROLLER:SetSpacing(2);
end

function UpdateInventoryDisplay()
	if not FRAME:IsVisible() then
		InventoryIsDirty = true;
		return false;
	end

	INVENTORY_SCROLLER:Reset();
	INVENTORY = {};
	
	if InventoryIsDirty then
		UpdateInventory();
	end
	
	if TOOLTIP_POPUP then
		--TOOLTIP_POPUP:Destroy();
	end
	
	local FilteredItems = {};
	
	for k,v in ipairs(Items) do
		if  v.flags.is_salvageable
			and not v.flags.is_equipped
			and (v.item_id or Game.GetItemInfoByType(v.item_sdb_id).flags.resource)
			and v.quantity > 0
			and (SearchFilter == "" or unicode.find(unicode.lower(v.name), unicode.lower(escape(SearchFilter))))
			and not ItemIsInQueue(v)
			and FilterItem(v) then
				table.insert(FilteredItems, v);
		end
	end

	if SortMethod then
		table.sort(FilteredItems, SORT_METHOD[SortMethod]);
	end

	local i = 1;
	local done = 0;
	
	for k,v in ipairs(FilteredItems) do
		v.index = i;
		i = i + 1;
		--Adding inventory rows async doesnt freeze the clients with large inventories.
		AddInventoryItem(v, nil);
		--[[Callback2.FireAndForget(function()
			AddInventoryItem(v, nil);
			done = done + 1;
			if done == #FilteredItems then
				--fix item sorting which got messed up
				UpdateInventorySort();
			end
		end, nil, 1.0);]]
	end
end

function UpdateInventorySort()
	--local count = INVENTORY_SCROLLER:GetRowCount();
	--for i=1, #INVENTORY do
	--	local item = INVENTORY[i];
		--item.ROW:MoveTo(math.min(item.index, count));
	--end
	
	--this fixes the empty rows
	--INVENTORY_SCROLLER:ScrollToPercent(0);
end
local IN_QUEUE = {};
local CALLBACKS = {};
local CallbackLimit = 25;
local ActiveCallbacks = 0;
local FunctionsPerCallback = 2;
local cb_InvQueue;

function NextItemAdd()
	if not cb_InvQueue and #IN_QUEUE > 0 and ActiveCallbacks < CallbackLimit then
		for i=ActiveCallbacks, CallbackLimit do
			if #IN_QUEUE > 0 then
				ActiveCallbacks = ActiveCallbacks + 1;
				local funcs = {};
				
				for j = 1, math.min(#IN_QUEUE, FunctionsPerCallback) do
					table.insert(funcs, IN_QUEUE[1]);
					table.remove(IN_QUEUE, 1);
				end
				
				callback(function()
					for k = 1, #funcs do
						funcs[k][1](funcs[k][2]);
					end
					ActiveCallbacks = ActiveCallbacks - 1;
					Component.GetWidget("Title"):SetText(ADDON.Name .. " " .. ADDON.Version .. ", " .. #IN_QUEUE);
					NextItemAdd();
				end, nil, 0.001);
			end
		end
	end
end

function AddItemAsync(item, highlight)
	local func = function()
		AddInventoryItem(item, highlight);
	end

	IN_QUEUE[#IN_QUEUE + 1] = {func, nil};
	if not cb_InvQueue then
		NextItemAdd();
	end
end

function RemoveItemRow(item, highlight)
	local func = function()
		AddInventoryItem(item, highlight);
	end

	IN_QUEUE[#IN_QUEUE + 1] = {func, nil};
	if not cb_InvQueue then
		NextItemAdd();
	end
end

function AddInventoryItem(item, highlight)
	--[[if item.idx then
		local count = INVENTORY_SCROLLER:GetRowCount();
		if item.idx > count then
			item.idx = nil;
		end
	end]]

	
	local WIDGET = GetRowWidget(item, INVENTORY_SCROLLER.HIDDEN);
	local ROW = INVENTORY_SCROLLER:AddRow(WIDGET, item.idx);

	if type(item.durability) == "number" then
		item.durability = {current=item.durability};
	end
	
	if not item.certifications then
		item.certifications = {};
	end
	
	ROW:AddHandler("OnMouseEnter", function()
		TOOLTIP_POPUP:DisplayInfo(item)
		local args = TOOLTIP_POPUP:GetBounds()
		Tooltip.Show(TOOLTIP_POPUP.GROUP, args)
		WIDGET:GetChild("row.bg"):ParamTo("alpha", 0.7, 0.15);
	end);
	ROW:AddHandler("OnMouseLeave", function()
		Tooltip.Show(nil);
		WIDGET:GetChild("row.bg"):ParamTo("alpha", 0.0, 0.15);
	end);
	
	item.ROW = ROW;
	item.idx = item.index or ROW.idx;

	ROW:AddHandler("OnMouseUp", function()
		table.remove(INVENTORY, ROW.idx);
		ROW:Remove();
		InsertItemToQueue(item);
	end);
	
	if highlight then
		--WIDGET:GetChild("row.bg"):SetParam("alpha", "1.0");
		--WIDGET:GetChild("row.bg"):ParamTo("alpha", "0.0", 0.5);
	end
	
	--ROW:SetWidget(WIDGET)
	--ROW:UpdateSize({height=25})
	
	table.insert(INVENTORY, item);
	return item;
end

function AddAllCurrentItemsToQueue()
	INVENTORY_SCROLLER:Reset();
	for i,item in ipairs(INVENTORY) do
		InsertItemToQueue(item);
	end
	INVENTORY = {};
end

--================================================================
-- Filters
--================================================================

function InitFilters()
	local height = 24;
	for i,v in ipairs(FILTER_LIST) do
		local W = Component.CreateWidget("Filter", W_FILTERS);
		W:GetChild("label"):SetText(FW.GetString(v.name));
		
		local CHECKBOX = CheckBox.Create(W:GetChild("checkbox"));
		W:SetDims("height:" .. height .. "; width:100%");
		CHECKBOX:AddHandler("OnStateChanged", function(args)
			if args.checked then
				AddFilter(v.filter);
			else
				RemoveFilter(v.filter);
			end
			UpdateInventoryDisplay();
		end);
	end
	
	W_FILTERS_BG:SetDims("left:0; top:230; width:170; height:" .. #FILTER_LIST * (height+2) + 5);
end

function AddFilter(filter)
	if not InArray(ActiveFilters, filter) then
		table.insert(ActiveFilters, filter);
	end
end

function RemoveFilter(filter)
	local index = InArray(ActiveFilters, filter);
	if index then
		table.remove(ActiveFilters, index);
	end
end

--================================================================
-- Categories
--================================================================

function InitCategories()
	for i,v in ipairs(CATEGORIES) do
		AddCategory(v, 1, i == 1);
	end
end

function AddCategory(category, i, selected)
	local WIDGET = Component.CreateWidget("InventoryCategory", WD_CATEGORIES);
	local BUTTON = WIDGET:GetChild("categoryBtn");
	
	local height = 30;
	if i > 1 then
		height = 25;
	end

	WIDGET:SetDims("width:100%; height:" .. height .. ";");
	BUTTON:SetDims("width:100%-" .. 30 * (i-1) .. "; height:" .. height .. "; right:100%;");
	
	BUTTON:GetChild("title"):SetText(FW.GetString(category.name));
	
	category.GROUP = WIDGET;
	
	BUTTON:BindEvent("OnMouseDown", function()
		SelectCategory(category);
	end);
	local CBTN2 = BUTTON:GetChild("bg");
	
	BUTTON:BindEvent("OnMouseEnter", function() CBTN2:ParamTo("tint", "#11AAFF", 0.15); end);
	BUTTON:BindEvent("OnMouseLeave", function() if(SelectedCategory ~= category) then CBTN2:ParamTo("tint", "#111111", 0.15); end; end);
		
	if selected then
		SelectedCategory = category;
		SelectedCategory.GROUP:GetChild("categoryBtn.bg"):ParamTo("tint", "#11AAFF", 0.15);
	end
		
	if category.children then
		for _,v in ipairs(category.children) do
			AddCategory(v, i+1);
		end
	end
end

function SelectCategory(category)
	if SelectedCategory == category then return; end;
	if SelectedCategory and SelectedCategory.GROUP then
		SelectedCategory.GROUP:GetChild("categoryBtn.bg"):ParamTo("tint", "#111111", 0.15);
	end
	
	if SelectedCategory and SelectedCategory.filters then
		for i,filter in ipairs(SelectedCategory.filters) do
			RemoveFilter(filter);
		end
	end
	
	if category and category.filters then
		for i,filter in ipairs(category.filters) do
			AddFilter(filter);
		end
	end
	
	SelectedCategory = category;
	UpdateInventoryDisplay();
end

--================================================================
-- SLASH
--================================================================

function SLASH.ToggleSalvager()
	if FRAME:IsVisible() then
		Hide();
	else
		Show();
	end
end