--!nonstrict
-- Only GameService's verified closing ledger calls record; no remote accepts scores.
local Service = {}; Service.__index=Service
local function copy(v) if type(v)~="table" then return v end local r={} for k,x in pairs(v) do r[k]=copy(x) end return r end
local function same(a,b) if type(a)~=type(b) then return false end if type(a)~="table" then return a==b end for k,v in pairs(a) do if not same(v,b[k]) then return false end end for k in pairs(b) do if a[k]==nil then return false end end return true end
local function result(code) return {Ok=code=="OK",Code=code,Value=false} end
local function int(n,max) return type(n)=="number" and n==n and n>=0 and n<=max and n%1==0 end
function Service.new(deps) return setmetatable({config=deps.Config,profiles=deps.Profiles,studioMemoryUsers=deps.IsStudio==true and deps.StorageMode=="Memory",transactions={},rounds={},rows={}},Service) end
function Service:record(r)
 local c=self.config
 if type(r)~="table" or type(r.TransactionId)~="string" or #r.TransactionId>96 or #r.TransactionId==0
  or not c.World.Stores[r.StoreId] or type(r.RoundId)~="string" or #r.RoundId>96
  or not int(r.Sales,c.Economy.MaxCurrency) or not int(r.Revenue,c.Economy.MaxCurrency)
  or not int(r.TeamSize,4) or r.TeamSize<1 or not int(r.ToolTier,5) or r.ToolTier<1
  or not table.find(c.Ranking.ModeTags,r.Mode) or type(r.Completed)~="boolean"
  or type(r.HadSupport)~="boolean" or type(r.HadReduction)~="boolean" or type(r.InitialUserIds)~="table"
  or type(r.FinishedAt)~="number" or r.FinishedAt~=r.FinishedAt or r.FinishedAt<0 or r.FinishedAt==math.huge then return result("BAD_REQUEST") end
 local prior=self.transactions[r.TransactionId]
 if prior and not same(prior.input,r) then return result("INVALID_STATE") end
 if not prior then
  if self.rounds[r.RoundId] then return result("INVALID_STATE") end
  local seen={}; local n=0
  for k,id in pairs(r.InitialUserIds) do
   local validUser=int(id,9007199254740991) and id>=1
   if self.studioMemoryUsers and type(id)=="number" and id<0 and int(-id,9007199254740991) then validUser=true end
   if not int(k,r.TeamSize) or k<1 or not validUser or seen[id] then return result("BAD_REQUEST") end
   seen[id]=true; n+=1
  end
  if n~=r.TeamSize then return result("BAD_REQUEST") end
  prior={input=copy(r),done={},epochs={}}; self.transactions[r.TransactionId]=prior; self.rounds[r.RoundId]=r.TransactionId
  for _,id in ipairs(r.InitialUserIds) do prior.epochs[id]=self.profiles:status(id).Epoch end
  local row={}
  for _,key in ipairs({"StoreId","RoundId","Sales","Revenue","TeamSize","ToolTier","Mode","HadSupport","HadReduction","FinishedAt"}) do row[key]=r[key] end
  row.UserId=false; table.insert(self.rows,row)
  -- Keep categories explicit; ordering compares only inside a category.
  table.sort(self.rows,function(a,b)
   local ka=a.Mode.."/"..a.TeamSize.."/"..a.ToolTier.."/"..tostring(a.HadSupport).."/"..tostring(a.HadReduction)
   local kb=b.Mode.."/"..b.TeamSize.."/"..b.ToolTier.."/"..tostring(b.HadSupport).."/"..tostring(b.HadReduction)
   if ka~=kb then return ka<kb end
   if a.Sales~=b.Sales then return a.Sales>b.Sales end
   if a.Revenue~=b.Revenue then return a.Revenue>b.Revenue end
   return a.FinishedAt<b.FinishedAt
  end)
  while #self.rows>c.Ranking.MaxRows do table.remove(self.rows) end
 end
 local key=r.Mode.."/"..r.TeamSize.."/"..r.ToolTier.."/"..tostring(r.HadSupport).."/"..tostring(r.HadReduction)
 local failure=false
 for _,id in ipairs(r.InitialUserIds) do if not prior.done[id] then
  local epoch=prior.epochs[id]
  if self.profiles:status(id).Epoch~=epoch then prior.done[id]=true else
   local updated=self.profiles:mutate(id,epoch,function(original)
    local p=copy(original)
    if r.Completed then p.CompletedFirstShift=true end
    local best={Key=key,Sales=r.Sales,Revenue=r.Revenue,TeamSize=r.TeamSize,ToolTier=r.ToolTier,Mode=r.Mode,HadSupport=r.HadSupport,HadReduction=r.HadReduction}
    for i,old in ipairs(p.Best) do if old.Key==key then
     if best.Sales>old.Sales or (best.Sales==old.Sales and best.Revenue>old.Revenue) then p.Best[i]=best end
     return p
    end end
    table.insert(p.Best,best); return p
   end)
   if updated.Ok then prior.done[id]=true else failure=updated.Code end
  end
 end end
 return result(failure or "OK")
end
function Service:view() return copy(self.rows) end
return Service
