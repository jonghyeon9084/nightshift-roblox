
local nativeTypeof = typeof
local mockFailAd = false
local mockFailSurface = false
local mockRejectParent = nil
local created = 0
local propsByObject = {}
local methods = {}
local vectorMeta = {}
local function vec(x,y,z) return setmetatable({X=x,Y=y,Z=z},vectorMeta) end
vectorMeta.__add = function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vectorMeta.__sub = function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMeta.__index = function(v,k)
 if k=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
 if k=="Dot" then return function(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
end
local Vector3 = {new=vec}
local function rotate(v,y) return vec(math.cos(y)*v.X+math.sin(y)*v.Z,v.Y,-math.sin(y)*v.X+math.cos(y)*v.Z) end
local frameMeta = {}
local function frame(p,y) return setmetatable({Position=p,Yaw=y},frameMeta) end
frameMeta.__add = function(a,b) return frame(a.Position+b,a.Yaw) end
frameMeta.__mul = function(a,b)
 local p=rotate(b.Position,a.Yaw)
 return frame(vec(a.Position.X+p.X,a.Position.Y+p.Y,a.Position.Z+p.Z),a.Yaw+b.Yaw)
end
frameMeta.__index = function(v,k)
 if k=="LookVector" then return rotate(vec(0,0,-1),v.Yaw) end
 if k=="UpVector" then return vec(0,1,0) end
end
local CFrame = {
 new=function(x,y,z) return frame(if type(x)=="table" then x else vec(x or 0,y or 0,z or 0),0) end,
 Angles=function(x,y,z) assert(x==0 and z==0) return frame(vec(0,0,0),y) end,
}
local Vector2 = {new=function(x,y) return {x,y} end}
local UDim2 = {fromScale=function(x,y) return {x,y} end}
local Color3 = {fromRGB=function(r,g,b) return {r,g,b} end}
local Enum = {PartType={Block="Block"},NormalId={Back="Back"},AdShape={HorizontalRectangle="HorizontalRectangle"},Material={SmoothPlastic="SmoothPlastic"},SurfaceType={Smooth="Smooth"}}
Enum.NormalId.Right="Right"; Enum.NormalId.Left="Left"; Enum.Material.Neon="Neon"; Enum.Material.Glass="Glass"; Enum.SurfaceGuiSizingMode={FixedSize="FixedSize"}; Enum.Font={GothamMedium="GothamMedium"}
local function typeof(v) return if propsByObject[v] then "Instance" else nativeTypeof(v) end
local Instance = {}
function Instance.new(class)
 if class=="SurfaceGui" and mockFailSurface then error("MOCK_SURFACE_FAILURE") end
 if class=="AdGui" and mockFailAd then error("MOCK_AD_API_UNAVAILABLE") end
 created+=1
 local props={ClassName=class,Name=class,Attributes={},Children={},FallbackWrites=0}
 if class=="AdGui" then props.FallbackImage="ROBLOX_DEFAULT_SENTINEL" props.Enabled=true end
 local obj=setmetatable({}, {
  __index=function(_,k)
   if methods[k] then return methods[k] end
   if k=="Position" then return props.CFrame.Position end
   return props[k]
  end,
  __newindex=function(self,k,v)
   if k=="Parent" then
    if v and v==mockRejectParent then error("MOCK_PARENT_FAILURE") end
    if props.Parent then
     local siblings=propsByObject[props.Parent].Children
     for i,c in ipairs(siblings) do if c==self then table.remove(siblings,i) break end end
    end
    if v then table.insert(propsByObject[v].Children,self) end
   end
   if k=="FallbackImage" or k=="FallbackImageContent" then props.FallbackWrites+=1 end
   props[k]=v
  end,
 })
 propsByObject[obj]=props
 return obj
end
function methods:IsA(class) return self.ClassName==class or ((self.ClassName=="Part" or self.ClassName=="SpawnLocation") and class=="BasePart") or (self.ClassName=="PointLight" and class=="Light") or (self.ClassName=="TextLabel" and class=="GuiObject") end
function methods:SetAttribute(name,value) self.Attributes[name]=value end
function methods:GetAttribute(name) return self.Attributes[name] end
function methods:GetChildren() return table.clone(self.Children) end
function methods:GetDescendants()
 local out={}
 for _,child in ipairs(self:GetChildren()) do
  table.insert(out,child)
  for _,desc in ipairs(child:GetDescendants()) do table.insert(out,desc) end
 end
 return out
end
function methods:Destroy()
 for _,child in ipairs(self:GetChildren()) do child:Destroy() end
 self.Parent=nil self.Destroyed=true
end
function methods:GetPivot() return self.WorldPivot or CFrame.new() end
function methods:FindFirstChild(name)
 for _,child in ipairs(self:GetChildren()) do if child.Name==name then return child end end
 return nil
end

function methods:IsDescendantOf(parent) local p=self.Parent while p do if p==parent then return true end p=p.Parent end return false end


