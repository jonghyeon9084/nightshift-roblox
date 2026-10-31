local world=Instance.new("Model"); world.Name="NightShiftWorld"
world:SetAttribute("NightShiftOwned",true); world:SetAttribute("CommerceLayoutVersion",2)
local stores=Instance.new("Folder"); stores.Name="Stores"; stores.Parent=world
local legacy=Instance.new("Folder"); legacy.Name="Advertising"; legacy.Parent=world
for i=1,10 do local x=Instance.new("Part"); x.Name="Legacy"..i; x.Parent=legacy end
local ids={"Store01","Store03","Store06","Store08"}
local models={}
for i,id in ipairs(ids) do
 local m=Instance.new("Model"); m.Name=id; m:SetAttribute("StoreId",id); m.pivot=F.new(i*80,0,i<3 and -52 or 52) * F.Angles(0,i<3 and 0 or math.pi,0); m.Parent=stores
 local roof=Instance.new("Part"); roof.Name="Roof"; roof.Size=V.new(58,1,50); roof.CFrame=m.pivot * F.new(0,18.5,0); roof.Parent=m
 models[i]=m
end
local function check(r) assert(r.Ok, r.Reason or r.Code); return r end
local r=check(module.build(world)); assert(r.PartCount==28 and r.AdUnits==4 and not r.Reused); local first=r.Folder
assert(#legacy:GetChildren()==10 and legacy.Parent==world); print("PASS first build: four boards, 28 parts, legacy 10 preserved")
r=check(module.build(world)); assert(r.Reused and r.Folder==first and r.AddedParts==0); print("PASS repeated build reuses folder")
models[1].pivot=models[1].pivot * F.new(1,0,0); models[1]._children[1].CFrame=models[1].pivot * F.new(0,15,0)
r=check(module.build(world)); assert(not r.Reused and r.Folder~=first); first=r.Folder; print("PASS pivot movement rebuild")
models[1]._children[1].CFrame=models[1].pivot * F.new(0,16,0)
r=check(module.build(world)); assert(not r.Reused and r.Folder~=first); first=r.Folder; print("PASS roof height change rebuild")
first:FindFirstChild("Store01"):FindFirstChild("AdSurface").CFrame=F.new(0,0,0)
r=check(module.build(world)); assert(not r.Reused and r.Folder~=first); first=r.Folder; print("PASS board movement rebuild")
first:FindFirstChild("Store01"):FindFirstChild("FrameTop").Size=V.new(1,1,1)
r=check(module.build(world)); assert(not r.Reused and r.Folder~=first); first=r.Folder; print("PASS frame size change rebuild")
local board=first:FindFirstChild("Store01")
local support=board:FindFirstChild("Support"); support.Size=V.new(0.6,2,0.5)
r=check(module.build(world)); assert(not r.Reused and r.Folder~=first); first=r.Folder; print("PASS support size change rebuild")
board=first:FindFirstChild("Store01"); local supports={}
for _, item in ipairs(board:GetChildren()) do if item.Name=="Support" then table.insert(supports,item) end end
supports[2].CFrame=supports[1].CFrame
r=check(module.build(world)); assert(not r.Reused and r.Folder~=first); first=r.Folder; print("PASS duplicate support position rebuild")
r=check(module.build(world,"notice")); assert(r.AdUnits==0 and r.Folder~=first); first=r.Folder
r=check(module.build(world,"ad")); assert(r.AdUnits==4 and r.Folder~=first); first=r.Folder; print("PASS mode switching notice and ad")
failNew=4; r=module.rebuild(world); assert(not r.Ok and first.Parent==world and world:FindFirstChild("RooftopAdvertising")==first); print("PASS mid-creation failure retains old folder")
corruptCommit=true; r=module.rebuild(world); assert(not r.Ok and first.Parent==world and world:FindFirstChild("RooftopAdvertising")==first); print("PASS failed candidate validation restores old folder")
local roof=models[1]._children[1]; roof.Shape=Enum.PartType.Ball; r=module.rebuild(world); assert(not r.Ok and first.Parent==world); roof.Shape=Enum.PartType.Block; print("PASS non-block roof rejected, old folder retained")
local obstruction=Instance.new("Part"); obstruction.Name="VisibleNoncolliding"; obstruction.Size=V.new(2,2,2); obstruction.CFrame=models[1].pivot * F.new(-12,20,24.65); obstruction.CanCollide=false; obstruction.Parent=models[1]
r=module.rebuild(world); assert(not r.Ok and first.Parent==world); obstruction:Destroy(); print("PASS visible noncolliding obstruction rejected")
assert(#legacy:GetChildren()==10 and legacy.Parent==world); print("PASS legacy advertising unchanged throughout")
for _, value in ipairs({false,"missing"}) do
 if value=="missing" then world:SetAttribute("NightShiftOwned",nil) else world:SetAttribute("NightShiftOwned",value) end
 r=module.build(world); assert(not r.Ok and first.Parent==world)
end
world:SetAttribute("NightShiftOwned",true); world:SetAttribute("CommerceLayoutVersion",3)
r=module.build(world); assert(not r.Ok and first.Parent==world)
world:SetAttribute("CommerceLayoutVersion",2)
print("PASS foreign/missing ownership and unsupported layout rejected without mutation")
local duplicate=Instance.new("Folder"); duplicate.Name="RooftopAdvertising"; duplicate.Parent=world
r=module.build(world); assert(not r.Ok and duplicate.Parent==world and first.Parent==world)
duplicate:Destroy(); print("PASS unowned duplicate folder retained and rejected")
local function surface(folder) return folder:FindFirstChild("Store01"):FindFirstChild("AdSurface") end
r=check(module.build(world,"notice")); local previous=r.Folder
surface(previous):GetChildren()[1]:GetChildren()[1]:Destroy()
r=check(module.build(world,"notice")); assert(not r.Reused and r.Folder~=previous)
local label=surface(r.Folder):GetChildren()[1]:GetChildren()[1]; label.Text=""
r=check(module.build(world,"notice")); assert(not r.Reused)
label=surface(r.Folder):GetChildren()[1]:GetChildren()[1]; label.Visible=false
r=check(module.build(world,"notice")); assert(not r.Reused)
print("PASS deleted, blank and hidden notice repaired")
label=surface(r.Folder):GetChildren()[1]:GetChildren()[1]; label.Size=UDim2.fromScale(0,0)
r=check(module.build(world,"notice")); assert(not r.Reused)
label=surface(r.Folder):GetChildren()[1]:GetChildren()[1]; label.TextColor3=label.BackgroundColor3
r=check(module.build(world,"notice")); assert(not r.Reused)
label=surface(r.Folder):GetChildren()[1]:GetChildren()[1]; label.Position=UDim2.fromScale(2,2)
r=check(module.build(world,"notice")); assert(not r.Reused)
print("PASS zero-size, invisible contrast and off-surface notice repaired")
surface(r.Folder):GetChildren()[1].Enabled=false
r=check(module.build(world,"notice")); assert(not r.Reused)
surface(r.Folder):GetChildren()[1].AlwaysOnTop=true
r=check(module.build(world,"notice")); assert(not r.Reused)
print("PASS disabled and through-wall notice repaired")
r=check(module.build(world,"ad")); surface(r.Folder):GetChildren()[1].Enabled=false
r=check(module.build(world,"ad")); assert(not r.Reused)
surface(r.Folder):GetChildren()[1].FallbackImage="NOT_AN_ASSET"
r=check(module.build(world,"ad")); assert(not r.Reused)
surface(r.Folder):GetChildren()[1].FallbackImageContent="NOT_CONTENT"
r=check(module.build(world,"ad")); assert(not r.Reused)
surface(r.Folder):GetChildren()[1].AdShape="UNSUPPORTED"
r=check(module.build(world,"ad")); assert(not r.Reused)
print("PASS disabled ad, custom fallback and wrong shape repaired with engine defaults")
for i,m in ipairs(models) do
 local part=r.Folder:FindFirstChild(ids[i]):FindFirstChild("AdSurface")
 local localPosition=m.pivot:PointToObjectSpace(part.CFrame.Position)
 assert(math.abs(localPosition.Z-24.65)<0.001)
 assert(part.CFrame.LookVector.Z*(i<3 and 1 or -1)>0.999)
 -- The lowest image point clears the front roof edge at representative walking viewpoints.
 local roofTop=m:GetChildren()[1].CFrame.Position.Y+0.5
 local frontZ=localPosition.Z+0.2
 for _, cameraZ in ipairs({30,40,52,64,72}) do
  local edgeY=roofTop+2+(5-(roofTop+2))*(25-frontZ)/(cameraZ-frontZ)
  assert(edgeY>roofTop)
 end
end
print("PASS all four front faces at roof edge and geometric sightlines clear roof (not rendering proof)")
local roof=models[2]:GetChildren()[1]; roof.Size=V.new(58,1,40)
r=check(module.build(world)); local position=models[2].pivot:PointToObjectSpace(r.Folder:FindFirstChild(ids[2]):FindFirstChild("AdSurface").CFrame.Position)
assert(math.abs(position.Z-19.65)<0.001)
print("PASS roof depth change derives board and footprint from current roof")
print("MOCK ONLY: yaw-only CFrame, simplified Instance; not Roblox or Studio")
