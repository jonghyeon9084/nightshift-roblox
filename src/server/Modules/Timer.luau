--!nonstrict
local Timer = {}
function Timer.new(seconds, now, running)
	return { left = seconds, due = running and now + seconds or false }
end
function Timer.remaining(timer, now)
	if not timer then return 0 end
	return timer.due and math.max(0, timer.due - now) or timer.left
end
function Timer.expired(timer, now)
	return timer and timer.due and now >= timer.due
end
function Timer.pause(timer, now)
	if timer and timer.due then timer.left = Timer.remaining(timer, now); timer.due = false end
end
function Timer.resume(timer, now)
	if timer and not timer.due then timer.due = now + timer.left end
end
function Timer.wire(timer, now)
	return { Remaining = Timer.remaining(timer, now), Running = timer ~= nil and timer ~= false and timer.due ~= false }
end
return Timer
