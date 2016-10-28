if ListScroller then return; end;

require "lib/lib_Slider"
require "lib/lib_EventDispatcher";

ListScroller = {};

local ScrollApi = {};
local RowApi = {};

local BP_LISTSCROLLER = [[
<Group dimensions="dock:fill" style="clip-children:true">
	<FocusBox name="focus" dimensions="dock:fill" style="tabbable:false">
		<Group name="rows" dimensions="left:0; right:100%-20; height:100%"/>
		<Group name="slider" dimensions="right:100%; width:20; height:100%" style="visible:false"/>
	</FocusBox>
</Group>
]];

local BP_DEFAULT_SLIDER = [[<Group dimensions="right:100%; width:21; height:100%">
		<StillArt name="back" dimensions="dock:fill" style="texture:Slider; region:back_v; ywrap:21"/>
		<Slider name="slider" dimensions="center-x:50%; width:66%; height:100%" style="tabbable:false"/>
	</Group>]];
	
local BP_ROW = [[<FocusBox dimensions="dock:fill" style="clip-children:true; tabbable:false; visible:true;"/>]];

local SCROLLER_METATABLE = {
	__index = function(t,key) return ScrollApi[key]; end,
	__newindex = function(t,k,v) error("cannot write to value '"..k.."' in SCROLLER"); end
};

local ROW_METATABLE = {
	__index = function(t,key) return RowApi[key]; end
};

local RowPool = {};


function ListScroller.Create(PARENT)
	local SCROLLER = {};
	
	SCROLLER.StartRow = 1;
	
	SCROLLER.ROW_HEIGHT = 22;
	
	local bounds = PARENT:GetBounds();
	
	SCROLLER.height = bounds.height;
	SCROLLER.width = bounds.width;
	SCROLLER.percent = 0;
	SCROLLER.visible_rows = 0;
	
	SCROLLER.RowPool = {};
	
	SCROLLER.GROUP = Component.CreateWidget(BP_LISTSCROLLER, PARENT);
	SCROLLER.FOCUS = SCROLLER.GROUP:GetChild("focus");
	SCROLLER.ROWS = SCROLLER.GROUP:GetChild("focus.rows");
	
	SCROLLER.hidden = true;
	
	SCROLLER.HIDDEN = Component.CreateWidget('<Group dimensions="dock:fill" style="visible:false"/>', SCROLLER.GROUP);
	
	SCROLLER.SLIDER = Slider.Create(SCROLLER.GROUP, "vertical")
	SCROLLER.SLIDER:SetDims("right:100%-1; width:_")
	SCROLLER.SLIDER:SetParam("thumbsize", 1);
	SCROLLER.SLIDER:BindEvent("OnStateChanged", function() ScrollApi.Slider_OnStateChange(SCROLLER) end)
	SCROLLER.SLIDER:Hide(true);
	
	SCROLLER.ROWS_LIST = {};
	
	SCROLLER.FOCUS:BindEvent("OnScroll", function(args)
		if #SCROLLER.ROWS_LIST > 0 then
			local new_pct = SCROLLER.percent + args.amount * (SCROLLER.SLIDER:GetScrollSteps())/(#SCROLLER.ROWS_LIST * SCROLLER.ROW_HEIGHT - SCROLLER.height);
			new_pct = math.max(0, math.min(1, new_pct));
			SCROLLER.SLIDER:SetPercent(new_pct);
			SCROLLER:RenderRows();
		end
	end);
	
	setmetatable(SCROLLER, SCROLLER_METATABLE);
	
	return SCROLLER;
end


function ScrollApi.GetRowFromPool(SCROLLER)
	if #SCROLLER.RowPool > 0 then
		local row = SCROLLER.RowPool[#SCROLLER.RowPool];
		SCROLLER.RowPool[#SCROLLER.RowPool] = nil;
		return row;
	else
		local row = Component.CreateWidget(BP_ROW, SCROLLER.ROWS);
		return row;
	end
end

function ScrollApi.AddRowToPool(SCROLLER, ROW)
	ROW:Hide(true);
	SCROLLER.RowPool[#SCROLLER.RowPool + 1] = ROW;
end

function ScrollApi.Slider_OnStateChange(SCROLLER)
	SCROLLER:RenderRows();
end

function ScrollApi.UpdateSlider(SCROLLER)
	SCROLLER.SLIDER:SetScrollSteps(#SCROLLER.ROWS_LIST * SCROLLER.ROW_HEIGHT / #SCROLLER.ROWS_LIST);
	SCROLLER.SLIDER:SetJumpSteps(SCROLLER.height);
	
	local RowsCount = #SCROLLER.ROWS_LIST;
	if RowsCount == 0 then
		RowsCount = 1;
	end
	
	if SCROLLER.hidden and RowsCount * SCROLLER.ROW_HEIGHT > SCROLLER.height then
		SCROLLER.hidden = false;
		SCROLLER.SLIDER:Show(true);
		SCROLLER.ROWS:SetDims("left:0; right:100%-20; height:100%");
	elseif not SCROLLER.hidden and RowsCount * SCROLLER.ROW_HEIGHT <= SCROLLER.height then
		SCROLLER.hidden = true;
		SCROLLER.SLIDER:Hide(true);
		SCROLLER.ROWS:SetDims("left:0; right:100%; height:100%");
	end
	
	SCROLLER.SLIDER:SetParam("thumbsize", math.max(.2, SCROLLER.height / (RowsCount * SCROLLER.ROW_HEIGHT)));
end

function ScrollApi.RenderRows(SCROLLER, idx)
	local precent = SCROLLER.SLIDER:GetPercent();
	
	local Force = false;

	if idx or SCROLLER.percent ~= precent then
		SCROLLER.percent = precent;

		local RowsVisibleCount = math.ceil(SCROLLER.height/SCROLLER.ROW_HEIGHT);
		local StartRow = math.floor(math.max(#SCROLLER.ROWS_LIST-RowsVisibleCount + 1, 0) * precent) + 1;
		local EndRow = math.min(#SCROLLER.ROWS_LIST, StartRow + RowsVisibleCount);
		local percDiff = StartRow - (math.max(#SCROLLER.ROWS_LIST-RowsVisibleCount + 1, 0)) * precent - 1;
		
		if type(idx) == "number" and (idx < StartRow or idx > EndRow) then
			return;
		end
		
		if SCROLLER.StartRow then
			for i=SCROLLER.StartRow, math.min(#SCROLLER.ROWS_LIST, SCROLLER.StartRow + RowsVisibleCount) do
				local ROW = SCROLLER.ROWS_LIST[i];
				ROW.GROUP:SetDims("width:100%; height:" .. SCROLLER.ROW_HEIGHT .. "; top:-9999");
			end
		end

		local k = 0;
		for i=StartRow, EndRow do
			local ROW = SCROLLER.ROWS_LIST[i];
			ROW.GROUP:SetDims("width:100%; height:" .. SCROLLER.ROW_HEIGHT .. "; top:" .. (k * (SCROLLER.ROW_HEIGHT) + percDiff * SCROLLER.ROW_HEIGHT));
			k = k + 1;
		end
		
		SCROLLER.StartRow = StartRow;
	end
end

function ScrollApi.AddRow(SCROLLER, WIDGET, idx)
	local ROW = {};
	
	ROW.GROUP = SCROLLER:GetRowFromPool();
	ROW.GROUP:SetDims("width:100%; height:" .. SCROLLER.ROW_HEIGHT .. "; top:-9999");
	
	ROW.WIDGET = WIDGET;
	
	if Component.IsWidget(WIDGET) then
		Component.FosterWidget(ROW.WIDGET, ROW.GROUP);
	end
	ROW.SCROLLER = SCROLLER;
	ROW.idx = #SCROLLER.ROWS_LIST + 1;
	
	ROW.DISPATCHER = EventDispatcher.Create(ROW);
	ROW.DISPATCHER:Delegate(ROW);
	
	local FOCUS = ROW.GROUP;
	FOCUS:BindEvent("OnMouseEnter", function()
		ROW.DISPATCHER:DispatchEvent("OnMouseEnter");
	end);
	FOCUS:BindEvent("OnMouseLeave", function()
		ROW.DISPATCHER:DispatchEvent("OnMouseLeave");
	end);
	FOCUS:BindEvent("OnMouseDown", function()
		ROW.DISPATCHER:DispatchEvent("OnMouseDown");
	end);
	FOCUS:BindEvent("OnMouseUp", function()
		ROW.DISPATCHER:DispatchEvent("OnMouseUp");
	end);
	
	setmetatable(ROW, ROW_METATABLE);
	
	SCROLLER.visible_rows = SCROLLER.visible_rows + 1;
	
	ROW.GROUP:Show(true);
	
	SCROLLER.ROWS_LIST[ROW.idx] = ROW;
	SCROLLER:RenderRows(ROW.idx);
	SCROLLER:UpdateSlider();
	return ROW;
end

function ScrollApi.UpdateIndexes(SCROLLER, start)
	for i=start or 1, #SCROLLER.ROWS_LIST do
		SCROLLER.ROWS_LIST[i].idx = i;
	end
end

function ScrollApi.RemoveRow(SCROLLER, ROW)
	local idx = ROW.idx;
	SCROLLER:RemoveRowFunc(ROW);
	SCROLLER:UpdateIndexes(ROW.idx);
	SCROLLER:UpdateSlider();
	SCROLLER:RenderRows(true);
	ROW = nil;
end

function ScrollApi.RemoveRowFunc(SCROLLER, ROW)
	local idx = ROW.idx;
	
	local FOCUS = ROW.GROUP;
	FOCUS:BindEvent("OnMouseEnter", nil);
	FOCUS:BindEvent("OnMouseLeave", nil);
	FOCUS:BindEvent("OnMouseDown", nil);
	FOCUS:BindEvent("OnMouseUp", nil);
	
	table.remove(SCROLLER.ROWS_LIST, idx);
	Component.FosterWidget(ROW.WIDGET, nil);
	SCROLLER:AddRowToPool(ROW.GROUP);
	ROW.DISPATCHER:Destroy();
	SCROLLER.visible_rows = SCROLLER.visible_rows - 1;
end

function ScrollApi.HideRow(SCROLLER, ROW)
	local idx = ROW.idx;
	SCROLLER.visible_rows = SCROLLER.visible_rows - 1;
	ROW.hidden = true;
	SCROLLER:UpdateSlider();
	SCROLLER:RenderRows(ROW.idx);
end

function ScrollApi.ShowRow(SCROLLER, ROW)
	local idx = ROW.idx;
	SCROLLER.visible_rows = SCROLLER.visible_rows + 1;
	ROW.hidden = false;
	SCROLLER:UpdateSlider();
	SCROLLER:RenderRows(ROW.idx);
end

function ScrollApi.MoveRow(SCROLLER, ROW, idx)
	table.remove(SCROLLER.ROWS_LIST, ROW.idx);
	table.insert(SCROLLER.ROWS_LIST, idx, ROW);
	SCROLLER:UpdateIndexes(math.min(idx, ROW.idx));
	SCROLLER:RenderRows(math.min(idx, ROW.idx));
end

function ScrollApi.Reset(SCROLLER)
	for i=#SCROLLER.ROWS_LIST, 1, -1 do
		SCROLLER:RemoveRowFunc(SCROLLER.ROWS_LIST[i]);
	end
	SCROLLER.visible_rows = 0;
	SCROLLER.SLIDER:SetPercent(0);
	SCROLLER:UpdateIndexes();
	SCROLLER:UpdateSlider();
	SCROLLER:RenderRows();
end


function RowApi.Remove(ROW)
	ROW.DISPATCHER:DispatchEvent("OnMouseLeave");
	ROW.SCROLLER:RemoveRow(ROW);
end

function RowApi.Hide(ROW)
	ROW.DISPATCHER:DispatchEvent("OnMouseLeave");
	ROW.SCROLLER:HideRow(ROW);
end

function RowApi.Show(ROW)
	ROW.SCROLLER:ShowRow(ROW);
end

function RowApi.Move(ROW, idx)
	ROW.SCROLLER:MoveRow(ROW, idx);
end