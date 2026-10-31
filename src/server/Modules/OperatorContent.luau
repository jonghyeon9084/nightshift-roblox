--!nonstrict
-- Server-only operator settings. No Remote, asset loading, tracking or ad delivery.
local Content = {}
Content.Settings = {
	SponsorshipEnabled = false, VideoEnabled = false,
	AllowedAssetIds = {}, Creatives = {},
	Notices = { LCD = "매장 안내 · 입고한 상품을 직접 진열하세요", Truck = "배송 안내 · 도착 후 직접 하역하세요" },
}

function Content.slot(medium, storeId, orderId, side)
	if type(storeId)~="string" or not string.match(storeId,"^Store0[1-8]$") then return nil end
	if medium=="LCD" then return "lcd."..storeId..".main" end
	if medium=="Truck" and type(orderId)=="string" and #orderId>0 and #orderId<=96 and (side=="left" or side=="right") then
		return "truck."..storeId.."."..orderId.."."..side
	end
	return nil
end

function Content.resolve(medium, storeId, orderId, side, creativeId)
	local slotId=Content.slot(medium,storeId,orderId,side)
	if not slotId then return {Ok=false,Code="BAD_REQUEST"} end
	-- Deliberately no sponsored renderer yet. Even an operator allowlist entry
	-- cannot bypass the separate future platform approval/eligibility integration.
	if creativeId~=nil and creativeId~=false then return {Ok=false,Code="FEATURE_DISABLED"} end
	return {Ok=true,Code="OK",Value={SlotId=slotId,Mode="house_notice",Text=Content.Settings.Notices[medium],AssetId=false}}
end

function Content.bind(world, part, face, notice)
	if type(notice)~="table" or not notice.Ok or type(notice.Value)~="table" or type(notice.Value.Text)~="string" or not part or not part:IsA("BasePart") or not part:IsDescendantOf(world)
		or notice.Value.Mode~="house_notice" or notice.Value.AssetId~=false then return {Ok=false,Code="BAD_REQUEST"} end
	local own
	-- Include Adornee references outside the part, not just direct children.
	for _,node in ipairs(world:GetDescendants()) do
		local isGui=node:IsA("SurfaceGui") or node:IsA("AdGui")
		local isDecal=node:IsA("Decal") or node:IsA("Texture")
		local target=isGui and (node.Adornee or node.Parent) or (isDecal and node.Parent)
		if target==part and node.Face==face then
			if node:IsA("SurfaceGui") and node:GetAttribute("NightShiftDirectContentOwned")==true
				and node:GetAttribute("ContentSlotId")==notice.Value.SlotId and not own then own=node
			elseif node:IsA("SurfaceGui") and node.Parent==part and node.Name=="WorldText" and part.Name=="InformationLCD"
				and part:GetAttribute("ContentMode")=="HouseInformation" and not own then own=node
			else return {Ok=false,Code="FACE_OCCUPIED"} end
		end
	end
	local gui
	local built=pcall(function()
	gui=Instance.new("SurfaceGui"); gui.Enabled=false; gui.Name="OperatorNotice"; gui.Face=face
	gui.CanvasSize=Vector2.new(768,256); gui.AlwaysOnTop=false; gui.LightInfluence=0; gui.MaxDistance=100
	gui:SetAttribute("NightShiftDirectContentOwned",true); gui:SetAttribute("ContentSlotId",notice.Value.SlotId)
	gui:SetAttribute("ContentMode","house_notice")
	local label=Instance.new("TextLabel"); label.Size=UDim2.fromScale(1,1); label.BackgroundTransparency=0.1
	label.BackgroundColor3=Color3.fromRGB(28,35,49)
	label.Text=notice.Value.Text; label.TextWrapped=true; label.TextScaled=true; label.RichText=false
	label.TextColor3=Color3.fromRGB(240,245,250); label.Parent=gui
	assert(gui.Parent==nil and label.Parent==gui and label.Text==notice.Value.Text,"candidate validation")
	end)
	if not built then if gui then gui:Destroy() end; return {Ok=false,Code="RENDER_FAILED"} end
	-- Publish disabled; preserve the old renderer through every construction/parenting failure.
	local wasEnabled=own and own.Enabled
	local committed=pcall(function()
		gui.Parent=part
		if own then own.Enabled=false end
		gui.Enabled=true
	end)
	if not committed then
		gui:Destroy(); if own then own.Enabled=wasEnabled end
		return {Ok=false,Code="RENDER_FAILED"}
	end
	if own then own:Destroy() end
	return {Ok=true,Code="OK"}
end
return Content
