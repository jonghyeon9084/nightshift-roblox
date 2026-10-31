-- Real WorldAdapter observer; only vectors/Players/clock are fake.
return function(WorldAdapter, config, players)
 local vector={}
 vector.__sub=function(a,b) return {Magnitude=math.abs(a.x-b.x)} end
 local function v(x) return setmetatable({x=x},vector) end
 local checks=0
 local function eq(a,b) checks+=1; assert(a==b,tostring(a).." ~= "..tostring(b)) end
 local function fixture()
  local player={UserId=1}; local root={Position=v(0)}
  players.list={player}
  local w=setmetatable({commerceConfig=config,movement={},itemParts={}},WorldAdapter)
  function w:alive() return root end
  w:sample(0)
  return w,player,root
 end
 for _,hz in ipairs({30,60}) do
  local w,p,r=fixture()
  for i=1,hz do r.Position=v(16*i/hz); w:sample(i/hz); eq(w:invalidMovement(p),false) end
  w,p,r=fixture()
  for i=1,hz do r.Position=v(180*i/hz); w:sample(i/hz) end
  eq(w:invalidMovement(p),true)
 end
 local w,p,r=fixture(); r.Position=v(180); w:sample(0.1)
 eq(w:invalidMovement(p),true); w:sample(20); eq(w:invalidMovement(p),true)
 eq(w.movement[1].position.x,0)
 w,p,r=fixture(); r.Position=v(16); w:sample(1); eq(w:invalidMovement(p),false)
 -- Repeated checks at the same time cannot refill slack.
 for i=1,6 do r.Position=v(16+i); w:observe(p,1) end
 eq(w:invalidMovement(p),true)
 eq(w.movement[1].invalidUntil,config.Interaction.RecoveryGraceSeconds)
 print("MOVEMENT_BUDGET_PASS "..checks.." checks; real observer, fake vectors/clock; no real exploit or multiplayer")
end
