local w=workspace.NightShiftWorld
local out={Mode=game:GetService("RunService"):IsRunning() and "Play" or "Edit",Parts=0,Lights=0,Units={},Baseplate=workspace:FindFirstChild("Baseplate")~=nil,OriginalSpawn=workspace:FindFirstChild("SpawnLocation")~=nil}
for _,v in ipairs(w:GetDescendants()) do
 if v:IsA("BasePart") then out.Parts+=1 elseif v:IsA("Light") then out.Lights+=1 end
end
for _,model in ipairs(w.Advertising:GetChildren()) do
 local face=model.AdSurface; local ad=face.ImageAd
 local row={Name=model.Name,Size=tostring(face.Size),Face=tostring(ad.Face),Video=ad.EnableVideoAds,Status=tostring(ad.Status),Fallback=ad.FallbackImage,Children=#face:GetChildren(),Collidable=face.CanCollide}
 assert(ad.Face==Enum.NormalId.Back and not ad.EnableVideoAds and #face:GetChildren()==1)
 assert(not face.CanCollide and face:IsA("Part"))
 local normal=face.CFrame:VectorToWorldSpace(Vector3.new(0,0,1))
 local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Exclude
 local ignore={w.Advertising,w.CommerceRuntime};for _,p in ipairs(game.Players:GetPlayers()) do if p.Character then table.insert(ignore,p.Character) end end
 ray.FilterDescendantsInstances=ignore;ray.RespectCanCollide=true
 local hit=workspace:Raycast(face.Position+normal*10,-normal*9.9,ray)
 row.FrontRayObstacle=hit and hit.Instance:GetFullName() or false
 table.insert(out.Units,row)
end
assert(#out.Units==10)
table.sort(out.Units,function(a,b) return a.Name<b.Name end)
if not game:GetService("RunService"):IsRunning() then
 local b=require(game.ServerStorage.NightShift.BuildBillboards)
 local reused=b.build(w); assert(reused.Ok and reused.Reused and reused.AddedParts==0)
 out.Reinstall={Reused=reused.Reused,AddedParts=reused.AddedParts}
end
return game.HttpService:JSONEncode(out)
