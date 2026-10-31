'use strict';
// Offline compiler, geometry checks and mocked Luau execution. This is NOT Studio validation.
// Usage: tools/Invoke-Node.ps1 tools/world/verify-billboards.cjs [official-luau-bin-directory]
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const project = path.resolve(__dirname, '../..');
const bin = path.resolve(process.argv[2] || path.join(__dirname, '.validation/luau-0.745'));
const file = path.join(__dirname, 'BuildBillboards.luau');
const source = fs.readFileSync(file, 'utf8');
function run(exe, args) {
  return cp.execFileSync(path.join(bin, exe), args, {cwd: project, encoding: 'utf8', maxBuffer: 8e6});
}
run('luau-compile.exe', ['--null', path.relative(project, file)]);
function ast(filePath) { return JSON.parse(run('luau-ast.exe', [path.relative(project, filePath)])).root; }
function value(n) {
  if (!n) return undefined;
  if (['AstExprConstantNumber', 'AstExprConstantString', 'AstExprConstantBool'].includes(n.type)) return n.value;
  if (n.type === 'AstExprUnary' && n.op === 'Minus') return -value(n.expr);
  if (n.type === 'AstExprTable') return n.items.every(x => x.kind === 'item')
    ? n.items.map(x => value(x.value)) : Object.fromEntries(n.items.map(x => [value(x.key), value(x.value)]));
}
function localValue(tree, name) {
  const statement = tree.body.find(n => n.type === 'AstStatLocal' && n.vars[0].name === name);
  assert(statement, `Missing source constant ${name}`);
  return value(statement.values[0]);
}
const tree = ast(file);
const streets = localValue(tree, 'STREET_PLACEMENTS');
const streetParts = localValue(tree, 'STREET_COMPONENTS');
const poster = localValue(tree, 'POSTER');
const posterParts = localValue(tree, 'POSTER_COMPONENTS');
const legacy = localValue(ast(path.join(project, 'src/shared/Config.luau')), 'Config');
const commerce = localValue(ast(path.join(project, 'src/shared/CommerceConfig.luau')), 'CommerceConfig');
assert.equal(commerce.World.LayoutVersion, 2);
assert.equal(commerce.World.StoreIds.length, 8, 'Update the eight-store integration expectation if the contract changes');
assert.equal(streets.length, 2);
assert.equal(streetParts.length, 6);
assert.equal(posterParts.length, 2);
for (const parts of [streetParts, posterParts]) {
  const surface = parts.find(p => p.Name === 'AdSurface');
  assert(surface);
  assert.equal(surface.Size[0] / surface.Size[1], 16 / 9);
  assert(surface.Size[0] >= 8 && surface.Size[0] <= 32);
  assert(surface.Size[1] >= 4.5 && surface.Size[1] <= 18);
  assert.equal(new Set(parts.map(p => p.Name)).size, parts.length);
}
function transform(position, yaw, offset) {
  const r = yaw * Math.PI / 180, c = Math.cos(r), s = Math.sin(r);
  return [position[0] + c * offset[0] + s * offset[2], position[1] + offset[1], position[2] - s * offset[0] + c * offset[2]];
}
function box(part, position, yaw) {
  const r = yaw * Math.PI / 180, c = Math.abs(Math.cos(r)), s = Math.abs(Math.sin(r));
  return {name: part.Name, pos: transform(position, yaw, part.Offset), size: [c * part.Size[0] + s * part.Size[2], part.Size[1], s * part.Size[0] + c * part.Size[2]]};
}
function overlap(a, b) { return a.pos.every((v, i) => Math.abs(v - b.pos[i]) < (a.size[i] + b.size[i]) / 2 - 0.001); }
const reserved = [
  {name: 'MainRoad', pos: [0, 10, 0], size: [commerce.World.RoadLength, 20, commerce.World.RoadWidth]},
  {name: 'Hub', pos: [commerce.World.HubPosition[0], 12, commerce.World.HubPosition[2]], size: [commerce.World.HubSize[0], 24, commerce.World.HubSize[2]]},
];
for (const side of [-1, 1]) {
  reserved.push({name: 'Sidewalk', pos: [0, 10, side * 17], size: [commerce.World.RoadLength, 20, commerce.World.SidewalkWidth]});
  reserved.push({name: 'DeliveryLane', pos: [0, 10, side * 91], size: [commerce.World.RoadLength, 20, 12]});
}
for (const id of commerce.World.StoreIds) {
  const store = commerce.World.Stores[id];
  reserved.push({name: `${id}Walks`, pos: transform(store.Position, store.YawDegrees, [0, 10, 1]), size: [74, 20, 70]});
}
const outside = streets.flatMap(p => streetParts.map(c => box(c, p.Position, p.YawDegrees)));
for (const part of outside) for (const zone of reserved) assert(!overlap(part, zone), `${part.name} intrudes into ${zone.name}`);
for (const placement of streets) {
  const normal = transform([0, 0, 0], placement.YawDegrees, [0, 0, 1]);
  assert(normal[2] * placement.Position[2] < 0, 'Street ad must face the road');
}
const insideLocal = posterParts.map(p => box(p, poster.Position, poster.YawDegrees));
for (const part of insideLocal) {
  assert(part.pos[0] + part.size[0] / 2 <= 28, 'Poster embedded in right wall');
  assert(part.pos[0] - part.size[0] / 2 >= 27.5, 'Poster projects too far into the store');
  assert(part.pos[1] - part.size[1] / 2 >= 7.5, 'Poster must stay above normal task sightlines');
  assert(part.pos[1] + part.size[1] / 2 < 18, 'Poster intersects the roof');
  for (const [name, spec] of Object.entries({...legacy.World.Markers, ...commerce.World.Markers})) {
    assert(!overlap(part, {pos: spec.Position, size: spec.Size}), `Poster intersects task marker ${name}`);
  }
  for (const slot of commerce.World.ShelfSlotPositions) assert(!overlap(part, {pos: slot, size: commerce.World.ShelfSlotSize}), 'Poster intersects stock');
}
assert(transform([0, 0, 0], poster.YawDegrees, [0, 0, 1])[0] < -0.99, 'Poster must face into the store');
for (const token of ['WaitForChild', 'task.wait', 'ClearAllChildren', 'GetService(', 'HttpService', 'MarketplaceService', 'TeleportService', 'PolicyService', 'AdService', 'SoundId', 'rbxassetid://', 'ProximityPrompt', 'ClickDetector', 'RemoteEvent', 'RemoteFunction']) {
  assert(!source.includes(token), `Unexpected dependency/interaction ${token}`);
}
assert(!/\.FallbackImage(?:Content)?\s*=/.test(source), 'Preserve the platform fallback');
assert(source.includes('store:GetPivot()'), 'Interior positions must derive from actual store instances');

// A deliberately small Roblox stand-in validates builder control flow, not Roblox rendering/API behavior.
const mock = String.raw`
local nativeTypeof = typeof
local mockFailAd = false
local mockRejectParent = nil
local created = 0
local propsByObject = {}
local methods = {}
local vectorMeta = {}
local function vec(x,y,z) return setmetatable({X=x,Y=y,Z=z},vectorMeta) end
vectorMeta.__sub = function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMeta.__index = function(v,k)
 if k=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
 if k=="Dot" then return function(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
end
local Vector3 = {new=vec}
local function rotate(v,y) return vec(math.cos(y)*v.X+math.sin(y)*v.Z,v.Y,-math.sin(y)*v.X+math.cos(y)*v.Z) end
local frameMeta = {}
local function frame(p,y) return setmetatable({Position=p,Yaw=y},frameMeta) end
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
local Color3 = {fromRGB=function(r,g,b) return {r,g,b} end}
local Enum = {PartType={Block="Block"},NormalId={Back="Back"},AdShape={HorizontalRectangle="HorizontalRectangle"},Material={SmoothPlastic="SmoothPlastic"},SurfaceType={Smooth="Smooth"}}
local function typeof(v) return if propsByObject[v] then "Instance" else nativeTypeof(v) end
local Instance = {}
function Instance.new(class)
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
function methods:IsA(class) return self.ClassName==class or (self.ClassName=="Part" and class=="BasePart") end
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
local beforeRequire=created
local Builder=(function()
__SOURCE__
end)()
assert(created==beforeRequire,"require has side effects")
local function rootWithStores(count)
 local root=Instance.new("Model") root.Name="NightShiftWorld"
 root:SetAttribute("NightShiftOwned",true) root:SetAttribute("CommerceLayoutVersion",2)
 local stores=Instance.new("Folder") stores.Name="Stores" stores.Parent=root
 for i=1,count do
  local store=Instance.new("Model") store.Name=string.format("Store%02d",i) store:SetAttribute("StoreId",store.Name)
  local x=({-120,-40,40,120})[(i-1)%4+1]
  store.WorldPivot=CFrame.new(x,0,if i<=4 then -52 else 52)*CFrame.Angles(0,if i<=4 then 0 else math.pi,0)
  store.Parent=stores
 end
 local sibling=Instance.new("Part") sibling.Name="UnrelatedMarker" sibling.Parent=root
 return root,stores,sibling
end
local root,stores,sibling=rootWithStores(8)
local result=Builder.build(root)
assert(result.Ok,result.Reason)
assert(result.AdUnits==10 and result.PartCount==28 and result.AddedParts==28 and not result.Reused)
assert(result.Folder.Parent==root and #root:GetChildren()==3)
local initialFolder=result.Folder
for _,obj in ipairs(initialFolder:GetDescendants()) do
 if obj:IsA("AdGui") then
  assert(obj.EnableVideoAds==false and obj.Face==Enum.NormalId.Back)
  assert(obj.FallbackWrites==0 and obj.FallbackImage=="ROBLOX_DEFAULT_SENTINEL")
 end
end
local repeatResult=Builder.build(root)
assert(repeatResult.Ok and repeatResult.Reused and repeatResult.AddedParts==0 and repeatResult.Folder==initialFolder)
assert(Builder.validate(root).Ok)
mockFailAd=true
local failure=Builder.rebuild(root)
mockFailAd=false
assert(not failure.Ok and failure.Code=="BILLBOARDS_UNAVAILABLE")
assert(root:FindFirstChild("Advertising")==initialFolder and not initialFolder.Destroyed)
mockRejectParent=root
local parentFailure=Builder.rebuild(root)
mockRejectParent=nil
assert(not parentFailure.Ok and root:FindFirstChild("Advertising")==initialFolder)
local rebuilt=Builder.rebuild(root)
assert(rebuilt.Ok and rebuilt.AddedParts==0 and rebuilt.Folder~=initialFolder and initialFolder.Destroyed)
assert(not sibling.Destroyed and sibling.Parent==root and stores.Parent==root and #stores:GetChildren()==8)
local ad=rebuilt.Folder:GetChildren()[1]:FindFirstChild("AdSurface"):FindFirstChild("ImageAd")
ad.EnableVideoAds=true
assert(not Builder.validate(root).Ok and not Builder.build(root).Ok)
assert(Builder.rebuild(root).Ok)
local surface=root:FindFirstChild("Advertising"):GetChildren()[1]:FindFirstChild("AdSurface")
local extra=Instance.new("SurfaceGui") extra.Parent=surface
assert(not Builder.validate(root).Ok)
extra:Destroy()
assert(Builder.validate(root).Ok)
local foreign=rootWithStores(8)
local userFolder=Instance.new("Folder") userFolder.Name="Advertising" userFolder.Parent=foreign
assert(not Builder.build(foreign).Ok and not Builder.rebuild(foreign).Ok and not userFolder.Destroyed)
local duplicate=Instance.new("Folder") duplicate.Name="Advertising" duplicate.Parent=root
assert(not Builder.rebuild(root).Ok and not duplicate.Destroyed)
duplicate:Destroy()
local wrong=rootWithStores(8) wrong:SetAttribute("NightShiftOwned",false)
assert(not Builder.build(wrong).Ok and #wrong:GetChildren()==2)
assert(not Builder.build(nil).Ok)
local failingRoot=rootWithStores(8)
mockFailAd=true
assert(not Builder.build(failingRoot).Ok)
mockFailAd=false
assert(not failingRoot:FindFirstChild("Advertising"))
local smallRoot,smallStores=rootWithStores(2)
local small=Builder.build(smallRoot)
assert(small.Ok and small.AdUnits==4 and small.PartCount==16,"store count was hard-coded")
local moved=smallStores:GetChildren()[1] moved.WorldPivot=CFrame.new(10,0,20)
assert(not Builder.validate(smallRoot).Ok,"stale poster transform was accepted")
assert(Builder.rebuild(smallRoot).Ok)
for obj,props in pairs(propsByObject) do
 if props.Name=="Advertising" and not props.Parent then assert(props.Destroyed,"orphaned staged folder") end
end
print("MOCK_PASS: 10 ad units / 28 parts; idempotence, rebuild, ownership, API/parent failures, fallback, image-only, store-derived transforms")
`;
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'nightshift-billboards-'));
const tempFile = path.join(tempDir, 'mock-check.luau');
let mockOutput;
try {
  fs.writeFileSync(tempFile, mock.replace('__SOURCE__', source));
  mockOutput = run('luau.exe', [tempFile]).trim();
  assert(mockOutput.startsWith('MOCK_PASS:'), mockOutput);
} finally {
  if (fs.existsSync(tempFile)) fs.unlinkSync(tempFile);
  fs.rmdirSync(tempDir);
}
console.log(JSON.stringify({
  kind: 'OFFLINE_COMPILE_GEOMETRY_AND_MOCK_NOT_STUDIO',
  compiler: 'Luau --null', compile: 'PASS', streetAds: streets.length,
  interiorAds: commerce.World.StoreIds.length, expectedParts: outside.length + commerce.World.StoreIds.length * insideLocal.length,
  faceRatiosAndSizes: 'PASS', streetRouteSeparation: 'PASS', interiorTaskMarkerClearance: 'PASS',
  noExternalServicesOrCustomFallback: 'PASS', mock: mockOutput,
  unverified: ['Roblox Instance/API behavior', 'AdGui Status/rendering and default logo', 'Studio camera/lighting/streaming', 'Actual performance', 'Publisher/player eligibility, ad fill and earnings'],
}, null, 2));
