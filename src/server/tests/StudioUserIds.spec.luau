-- Real domains, memory adapter. This is not an actual multiplayer result.
return function(Profiles,Commerce,Ranking,C)
 local checks=0
 for _,setting in ipairs({{true,"Memory",true},{false,"Memory",false},{true,"DataStore",false}}) do
  local studio,mode,allowed=unpack(setting)
  local store=Profiles.newMemoryStore();store.Mode=mode
  local p=Profiles.new({Config=C,Store=store,SessionId="id-test",UnixNow=function() return 1000 end,IsStudio=studio})
  for _,id in ipairs({-1,-2}) do assert(p:load(id).Ok==allowed);checks+=1 end
  local commerce=Commerce.new({Config=C,Now=function() return 0 end,NewId=function() return "id" end,World={},Delivery={},Progression={},IsStudio=studio,StorageMode=mode})
  local shift=commerce:beginShift("Store01","negative-round",{InitialUserIds={-1,-2},TeamSize=2,Mode="Practice",Protected=true})
  assert(shift.Ok==allowed);checks+=1
  local ranking=Ranking.new({Config=C,Profiles=p,IsStudio=studio,StorageMode=mode})
  local r=ranking:record({TransactionId="negative-record",StoreId="Store01",RoundId="negative-round",InitialUserIds={-1,-2},Sales=0,Revenue=0,TeamSize=2,ToolTier=1,Mode="Practice",Completed=false,HadSupport=false,HadReduction=false,FinishedAt=1000})
  assert(r.Ok==allowed,r.Code);checks+=1
 end
 print("STUDIO_USER_IDS_PASS "..checks.." profile/shift/ranking checks, explicit memory only; not multiplayer")
end
