local V = {}; V.__index = function(t,k)
 if k == "Magnitude" then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z) end
 return V[k]
end
function V.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},V) end
function V.__add(a,b) return V.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
function V.__sub(a,b) return V.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
function V.__mul(a,b) return V.new(a.X*b,a.Y*b,a.Z*b) end
function V.__eq(a,b) return a.X==b.X and a.Y==b.Y and a.Z==b.Z end
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
Vector3=V
local F={}
F.__index=function(t,k)
 if k=="Position" then return t.p end
 if k=="RightVector" then return V.new(math.cos(t.y),0,-math.sin(t.y)) end
 if k=="UpVector" then return V.new(0,1,0) end
 if k=="LookVector" then return V.new(-math.sin(t.y),0,-math.cos(t.y)) end
 return F[k]
end
function F.new(x,y,z) return setmetatable({p=V.new(x or 0,y or 0,z or 0),y=0},F) end
function F.Angles(_,y,_) return setmetatable({p=V.new(0,0,0),y=y},F) end
function F:PointToWorldSpace(v) local c,s=math.cos(self.y),math.sin(self.y); return self.p+V.new(c*v.X+s*v.Z,v.Y,-s*v.X+c*v.Z) end
function F:PointToObjectSpace(v) local q=v-self.p; local c,s=math.cos(self.y),math.sin(self.y); return V.new(c*q.X-s*q.Z,q.Y,s*q.X+c*q.Z) end
function F:ToObjectSpace(other) return setmetatable({p=self:PointToObjectSpace(other.p),y=other.y-self.y},F) end
function F.__mul(a,b) return setmetatable({p=a:PointToWorldSpace(b.p),y=a.y+b.y},F) end
function F.__sub(a,b) return setmetatable({p=a.p-b,y=a.y},F) end
CFrame=F
local valueMT={__eq=function(a,b) if #a~=#b then return false end; for i,v in ipairs(a) do if v~=b[i] then return false end end; return true end}
Color3={fromRGB=function(...) return setmetatable({...},valueMT) end}
UDim2={fromScale=function(...) return setmetatable({...},valueMT) end}
Enum={NormalId={Front="Front"},PartType={Block="Block", Ball="Ball"},AdShape={HorizontalRectangle="HorizontalRectangle"}}
local methods={}; local MT={}
local failNew, corruptCommit = 0, false
MT.__index=function(t,k) if k=="Parent" then return rawget(t,"_parent") end; return methods[k] or rawget(t,k) end
MT.__newindex=function(t,k,v)
 if k=="Parent" then
  local old=rawget(t,"_parent")
  if old then for i,c in ipairs(old._children) do if c==t then table.remove(old._children,i); break end end end
  rawset(t,"_parent",v)
  if v then table.insert(v._children,t) end
  if corruptCommit and t.Name=="RooftopAdvertising" and v and v.Name=="NightShiftWorld" then
   corruptCommit=false; t._children[1]._children[1].Size=V.new(1,1,1)
  end
 else rawset(t,k,v) end
end
Instance={}
function Instance.new(kind)
 if failNew > 0 then failNew -= 1; if failNew == 0 then error("injected creation failure") end end
 local x=setmetatable({_class=kind,_children={},_attrs={},Name=kind},MT)
 if kind=="Part" then x.Size=V.new(1,1,1); x.CFrame=F.new(); x.Transparency=0; x.CanCollide=true; x.CanTouch=true; x.CanQuery=true; x.CastShadow=true; x.Anchored=false; x.Shape=Enum.PartType.Block end
 if kind=="AdGui" then x.FallbackImage="ENGINE_DEFAULT"; x.FallbackImageContent="ENGINE_CONTENT_DEFAULT" end
 return x
end
function methods:IsA(kind) return self._class==kind or (kind=="BasePart" and (self._class=="Part" or self._class=="MeshPart")) end
function methods:SetAttribute(k,v) self._attrs[k]=v end
function methods:GetAttribute(k) return self._attrs[k] end
function methods:GetChildren() return table.clone(self._children) end
function methods:GetDescendants()
 local out={}; local function walk(x) for _,c in ipairs(x._children) do table.insert(out,c); walk(c) end end; walk(self); return out
end
function methods:FindFirstChild(name) for _,x in ipairs(self._children) do if x.Name==name then return x end end end
function methods:GetPivot() return self.pivot end
function methods:Destroy() self.Parent=nil; for _,c in ipairs(self:GetChildren()) do c:Destroy() end; self.destroyed=true end
