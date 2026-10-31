-- Actual client -> server requests. Run at the rear loading area, end of a test
-- session: high request IDs intentionally prevent reuse of stale UI IDs.
local r=game.ReplicatedStorage.NightShift.Remotes
local v=shared.CommerceVerification
local me=v.Legacy.Self; local round=v.Legacy.Store.RoundId
local M=require(game.Players.LocalPlayer.PlayerScripts.NightShift.Modules.CommerceState)
local function snapshot()
 task.wait(2.2)
 local result=r.GetCommerceSnapshot:InvokeServer({ProtocolVersion=1})
 assert(result.Ok,result.Code)
 return result.Snapshot
end
local before=snapshot()
local out={Kind="ACTUAL_CLIENT_SERVER_REJECTIONS",Before=before.Store,Results={}}
local requestId=10000
local function send(label,payload,storeId,reuse)
 if not reuse then requestId+=1 end
 local request=M.request({StoreId=storeId or me.StoreId,RoundId=round,SeatGeneration=me.SeatGeneration},"OrderStock",payload,requestId)
 local start=#v.CommerceAcks
 r.CommerceAction:FireServer(request)
 local untilAt=os.clock()+5
 repeat task.wait(.05) until #v.CommerceAcks>start or os.clock()>untilAt
 assert(#v.CommerceAcks>start,"Missing response")
 local ack=v.CommerceAcks[#v.CommerceAcks]
 assert(ack.RequestId==requestId and not ack.Ok,label.." unexpectedly accepted")
 table.insert(out.Results,{Label=label,Ack=ack})
end
send("zero quantity",{Sku="Water",Quantity=0,StockRevision=before.Wholesale.Revision})
send("five exceeds per-order cap",{Sku="Water",Quantity=5,StockRevision=before.Wholesale.Revision})
send("foreign store",{Sku="Water",Quantity=1,StockRevision=before.Wholesale.Revision},"Store02")
send("remote own PC",{Sku="Water",Quantity=1,StockRevision=before.Wholesale.Revision})
send("duplicate remote request",{Sku="Water",Quantity=1,StockRevision=before.Wholesale.Revision},nil,true)
local after=snapshot();out.After=after.Store
assert(before.Store.OperatingCash==after.Store.OperatingCash and #before.Store.Items==#after.Store.Items,"Rejected input mutated stock/cash")
return game.HttpService:JSONEncode(out)
