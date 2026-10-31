-- Pure presentation checks only; no Roblox instances or game execution.
local TrayView = require("../Modules/TrayView")
local checks = 0
local function check(condition, message)
	assert(condition, message)
	checks += 1
end
local products = {
	Water={Name="물", Glyph="○"}, Bread={Name="빵", Glyph="△"}, Milk={Name="우유", Glyph="□"},
}
local function store(storeId, roundId, orderId, lines)
	return {StoreId=storeId, RoundId=roundId, Round={Order={OrderId=orderId, Lines=lines}}}
end
local function line(id, status, productId, trayIndex)
	return {LineId=id, Status=status, ProductId=productId, TrayIndex=trayIndex}
end
local function has(text, value) return string.find(text, value, 1, true) ~= nil end
local empty = TrayView.slots(false)
check(#empty==3 and empty[1].Status=="Empty" and empty[3].Slot==3, "Hub produces three numbered empty slots")
check(has(TrayView.text(empty[2], products), "트레이 2") and has(TrayView.text(empty[2], products), "상품 없음"), "empty slot number and text")
local original = store("Store01", "r1", "o1", {
	line(3, "Tray", "Milk", 3), line(1, "Accepted", "Water", 1), line(2, "Cancelled", "Bread", false),
})
local slots = TrayView.slots(original)
check(slots[1].Status=="Accepted" and slots[1].LineId==1, "accepted line retains slot one")
check(slots[2].Status=="Cancelled" and slots[2].LineId==2, "cancelled line retains slot two")
check(slots[3].Status=="Tray" and slots[3].TrayIndex==3 and slots[3].ProductId=="Milk", "array order and cancellation never compact slot three")
check(has(TrayView.text(slots[1], products), "접수 완료"), "accepted wording")
check(has(TrayView.text(slots[2], products), "취소") and has(TrayView.text(slots[2], products), "△ 빵"), "cancelled product name and glyph remain visible")
check(has(TrayView.text(slots[3], products), "계산대 대기") and has(TrayView.text(slots[3], products), "□ 우유"), "tray product name and glyph")
local missing = TrayView.slots(store("Store01", "r1", "o1", {line(3, "Tray", "Milk", 3)}))
check(missing[1].Status=="Empty" and missing[2].Status=="Empty" and missing[3].LineId==3, "sparse LineIds keep holes")
local before = TrayView.slots(store("Store01", "r1", "o1", {line(1, "Uncollected", "Water", false), line(2, "Carried", "Bread", false)}))
check(has(TrayView.text(before[1], products), "빈칸 · 미수집"), "uncollected is physically empty")
check(has(TrayView.text(before[2], products), "빈칸 · 운반 중"), "carried is physically empty")
local invalid = TrayView.slots(store("Store01", "r1", "o1", {line(3, "Tray", "Milk", 1)}))
check(invalid[1].Status=="Empty" and invalid[3].Status=="Sync", "inconsistent TrayIndex cannot move a LineId to another slot")
check(TrayView.context(original)~=TrayView.context(store("Store01", "r1", "o2", {})), "new order changes cleanup identity")
check(TrayView.context(original)~=TrayView.context(store("Store01", "r2", "o1", {})), "new round changes cleanup identity")
check(TrayView.context(original)~=TrayView.context(store("Store02", "r1", "o1", {})), "new store changes cleanup identity")
local rebound = TrayView.slots(original)
check(rebound[3].Status=="Tray" and rebound[2].Status=="Cancelled", "rebind derives exact current server state")
local nextOrder = TrayView.slots(store("Store01", "r1", "o2", {line(1, "Uncollected", "Bread", false)}))
check(nextOrder[1].ProductId=="Bread" and nextOrder[2].Status=="Empty" and nextOrder[3].Status=="Empty", "new order carries no old accepted/cancelled/product state")
local ended = TrayView.slots({StoreId="Store01", RoundId="r1", Round=false})
check(ended[1].Status=="Empty" and ended[3].Status=="Empty", "ended round clears contents")
check(original.Round.Order.Lines[1].LineId==3 and original.Round.Order.Lines[2].Status=="Accepted", "projection does not mutate wire state")
print("PASS: " .. checks .. " pure tray assertions; Roblox/Studio not executed")
