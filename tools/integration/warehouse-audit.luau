-- Engine geometry/content census. Read-only except a detached temporary truck.
local w=workspace.NightShiftWorld
local result={Mode=game:GetService("RunService"):IsRunning() and "Play" or "Edit",Stores={},Ground={},Ads=0,Managed=0,DuplicateFaces={},LCD={},Trucks={}}
local faces={}
for _,v in ipairs(w:GetDescendants()) do
 if v:IsA("AdGui") or v:IsA("SurfaceGui") or v:IsA("Decal") or v:IsA("Texture") then
  local p=(v:IsA("AdGui") or v:IsA("SurfaceGui")) and (v.Adornee or v.Parent) or v.Parent
  local key=p:GetFullName()..":"..tostring(v.Face)
  -- DirectNotice siblings have the same name; use Instance keys, not paths.
  faces[p]=faces[p] or {}
  if faces[p][v.Face] then table.insert(result.DuplicateFaces,key) end
  faces[p][v.Face]=true
  if v:IsA("AdGui") then result.Ads+=1; assert(not v.EnableVideoAds) end
  if v:GetAttribute("NightShiftDirectContentOwned") then result.Managed+=1 end
 end
end
local names={MainRoad=true,Plaza=true,Sidewalk=true,ServiceLane=true,HubWalk=true,Floor=true,Forecourt=true,SideWalk=true,RearWalk=true,LoadingPad=true,WarehousePad=true}
local ground={}
for _,p in ipairs(w:GetDescendants()) do if p:IsA("BasePart") and names[p.Name] then
 table.insert(ground,p)
 table.insert(result.Ground,{Path=p:GetFullName(),Top=p.Position.Y+p.Size.Y/2})
 assert(p.Position.Y+p.Size.Y/2>workspace.Baseplate.Position.Y+workspace.Baseplate.Size.Y/2+0.07)
end end
result.CoplanarGround={}
for i,a in ipairs(ground) do for j=1,i-1 do local b=ground[j]
 if math.abs(a.Position.X-b.Position.X)<(a.Size.X+b.Size.X)/2-0.001 and math.abs(a.Position.Z-b.Position.Z)<(a.Size.Z+b.Size.Z)/2-0.001 then
  if math.abs(a.Position.Y+a.Size.Y/2-b.Position.Y-b.Size.Y/2)<0.04 then table.insert(result.CoplanarGround,{a:GetFullName(),b:GetFullName()}) end
 end
end end
for _,s in ipairs(w.Stores:GetChildren()) do
 local a=s.Architecture; local racks={}
 for _,p in ipairs(a:GetChildren()) do if string.sub(p.Name,1,4)=="Rack" then
  local pos=s:GetPivot():PointToObjectSpace(p.Position)
  assert(p.Size.X<=8 and pos.Z-p.Size.Z/2>=-10.001,"Rack protected rear path")
  assert(pos.X-p.Size.X/2>=-20.001,"Rack left path")
  assert(pos.X+p.Size.X/2<=4.001 or pos.X-p.Size.X/2>=11.999,"Rack central path")
  table.insert(racks,{Name=p.Name,LocalPosition=tostring(pos),Size=tostring(p.Size)})
 end end
 table.insert(result.Stores,{StoreId=s.Name,Racks=racks,Anchors=#s.WarehouseSlots:GetChildren()})
 table.insert(result.LCD,{StoreId=s.Name,Status=a.InformationLCD:GetAttribute("OperatorBindingStatus") or "Edit unbound",SlotId=a.InformationLCD:GetAttribute("SlotId")})
end
if result.Mode=="Play" then
 for _,t in ipairs(w.CommerceRuntime.Trucks:GetChildren()) do
  local notices={}
  for _,p in ipairs(t:GetChildren()) do if p.Name=="DirectNotice" then table.insert(notices,{SlotId=p:GetAttribute("SlotId"),Status=p:GetAttribute("OperatorBindingStatus")}) end end
  local route=w.Stores[t:GetAttribute("StoreId")].TruckRoute
  local forward=t.Cab.CFrame.LookVector
  table.insert(result.Trucks,{OrderId=t.Name,Presentation=t:GetAttribute("PresentationKind"),Phase=t:GetAttribute("DeliveryPhase"),CargoCount=t:GetAttribute("CargoCount"),Notices=notices,ForwardTravelDot=forward:Dot((route.Exit.Position-route.Approach.Position).Unit)})
 end
 local settings=require(game.ServerScriptService.NightShift.Modules.OperatorContent).Settings
 result.Content={Sponsorship=settings.SponsorshipEnabled,Video=settings.VideoEnabled,AllowedAssetIds=#settings.AllowedAssetIds,Creatives=#settings.Creatives}
end
result.Baseplate={Position=tostring(workspace.Baseplate.Position),Size=tostring(workspace.Baseplate.Size)}
result.OriginalSpawn={Position=tostring(workspace.SpawnLocation.Position),Size=tostring(workspace.SpawnLocation.Size)}
assert(#result.Stores==8 and result.Ads==10 and #result.DuplicateFaces==0 and #result.CoplanarGround==0)
return game.HttpService:JSONEncode(result)
