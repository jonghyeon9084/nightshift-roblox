--!nonstrict
local U={}
function U.copy(v)
	if type(v)~="table" then return v end
	local t={}; for k,x in pairs(v) do t[k]=U.copy(x) end; return t
end
function U.result(code,value) return {Ok=code=="OK",Code=code,Value=value==nil and false or U.copy(value)} end
function U.same(a,b)
	if type(a)~=type(b) then return false end
	if type(a)~="table" then return a==b end
	for k,v in pairs(a) do if not U.same(v,b[k]) then return false end end
	for k in pairs(b) do if a[k]==nil then return false end end; return true
end
-- Fail closed on a missing, throwing, or yielding authority adapter.
function U.call(object,method,...)
	if not object or type(object[method])~="function" then return U.result("NOT_READY") end
	local co=coroutine.create(object[method]); local ok,value=coroutine.resume(co,object,...)
	if coroutine.status(co)~="dead" then coroutine.close(co); return U.result("INTERNAL_ERROR") end
	if not ok then return U.result("INTERNAL_ERROR") end
	if type(value)=="table" and value.Ok~=nil then return value end
	return value==true and U.result("OK") or U.result("NOT_READY")
end
return U
