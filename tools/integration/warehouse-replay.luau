-- Replay an actual successful order from the current final solo test session.
-- Does not advance the connection request watermark or change authoritative data.
local r=game.ReplicatedStorage.NightShift.Remotes
local v=shared.CommerceVerification
local function snapshot()
 task.wait(2.2)
 local s=r.GetCommerceSnapshot:InvokeServer({ProtocolVersion=1});assert(s.Ok,s.Code);return s.Snapshot
end
local before=snapshot()
local request={ProtocolVersion=1,RequestId=1,Action="OrderStock",StoreId="Store01",RoundId="r-1",SeatGeneration=2,Payload={Sku="Water",Quantity=4,StockRevision=1}}
local responses={}
local connection=r.CommerceActionResult.OnClientEvent:Connect(function(a) if a.RequestId==1 then table.insert(responses,a) end end)
r.CommerceAction:FireServer(request);task.wait(.5)
request.Payload.Quantity=3;r.CommerceAction:FireServer(request);task.wait(.5)
connection:Disconnect()
local after=snapshot()
assert(#responses==2 and responses[1].Ok and responses[2].Code=="REQUEST_ID_REUSED","Unexpected replay result")
assert(before.Self.Wallet==after.Self.Wallet and before.Store==false and after.Store==false,"Replay recreated closed shift or changed wallet")
return game.HttpService:JSONEncode({Kind="ACTUAL_SUCCESSFUL_ORDER_REPLAY",Responses=responses,Wallet=after.Self.Wallet,Cash=false,Items=0})
