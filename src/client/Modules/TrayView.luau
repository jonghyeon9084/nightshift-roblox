--!strict
-- Pure presentation projection. Slot numbers are never compacted after a
-- cancellation; server LineId 1..3 owns its corresponding physical tray slot.
local TrayView = {}

function TrayView.context(store: any): string
	if not store then return "Hub" end
	local order = store.Round and store.Round.Order
	return table.concat({store.StoreId, tostring(store.RoundId), tostring(order and order.OrderId)}, "\0")
end

function TrayView.slots(store: any): {any}
	local slots = {}
	for index = 1, 3 do
		slots[index] = { Slot=index, LineId=false, ProductId=false, Status="Empty", TrayIndex=false }
	end
	local order = store and store.Round and store.Round.Order
	local lines: {any} = order and order.Lines or {}
	for _, line in ipairs(lines) do
		local index = line.LineId
		if type(index) == "number" and index % 1 == 0 and index >= 1 and index <= 3 then
			-- TrayIndex is a server occupancy assertion, not permission to renumber.
			local status = line.Status
			if status == "Tray" and line.TrayIndex ~= index then status = "Sync" end
			slots[index] = { Slot=index, LineId=index, ProductId=line.ProductId,
				Status=status, TrayIndex=line.TrayIndex }
		end
	end
	return slots
end

function TrayView.text(slot: any, products: any): string
	local product: any = slot.ProductId and products[slot.ProductId]
	local item = if product then tostring(product.Glyph or "") .. " " .. tostring(product.Name) else "— 상품 없음"
	local labels: {[string]: string} = {
		Empty="빈칸", Uncollected="빈칸 · 미수집", Carried="빈칸 · 운반 중",
		Tray="계산대 대기", Accepted="접수 완료", Cancelled="취소 · 빈칸",
		Sync="상태 확인 중",
	}
	return "트레이 " .. tostring(slot.Slot) .. (slot.LineId and (" · 품목 " .. tostring(slot.LineId)) or "")
		.. "\n" .. item .. "\n" .. (labels[slot.Status] or "상태 확인 중")
end

return TrayView
