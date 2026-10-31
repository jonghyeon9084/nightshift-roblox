--!nonstrict
-- Pure continuous relative-motion slab test; never accepts client touch events.
local G={}
function G.finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
function G.point(p) return p and G.finite(p.X) and G.finite(p.Y) and G.finite(p.Z) end
function G.road(p,zone)
	return G.point(p) and math.abs(p.X-zone.X)<=zone.HalfX and math.abs(p.Z-zone.Z)<=zone.HalfZ
		and p.Y>=zone.MinY and p.Y<=zone.MaxY
end
function G.sweep(a,b,fromX,toX,route,halfLength,maxDistance)
	if not G.point(a) or not G.point(b) then return false end
	local starts={a.X-fromX,a.Y-(route.Y+2.2),a.Z-route.Z}
	local ends={b.X-toX,b.Y-(route.Y+2.2),b.Z-route.Z}
	local halves={halfLength+1.25,3.5,3.55}; local enter,leave=0,1
	for i=1,3 do
		local d=ends[i]-starts[i]
		if math.abs(d)<0.000001 then if math.abs(starts[i])>halves[i] then return false end
		else
			local lo,hi=(-halves[i]-starts[i])/d,(halves[i]-starts[i])/d
			if lo>hi then lo,hi=hi,lo end
			enter=math.max(enter,lo); leave=math.min(leave,hi)
			if enter>leave then return false end
		end
	end
	local distance=0
	for i=1,3 do local value=starts[i]+(ends[i]-starts[i])*enter; distance+=value*value end
	return distance<=maxDistance*maxDistance,enter
end
return G
