-- Readiness only. No cloud writes, account/security/microphone changes or custom audio.
local voice=game:GetService("VoiceChatService")
local out={PlaceId=game.PlaceId,MaxPlayers=game.Players.MaxPlayers,ActualVoiceCall="UNVERIFIED",CloudPersistence="UNVERIFIED"}
for _,key in ipairs({"EnableDefaultVoice","UseAudioApi"}) do
 local ok,value=pcall(function() return voice[key] end)
 out[key]=ok and tostring(value) or "Unreadable"
end
local ok,value=pcall(function() return game:GetService("DataStoreService"):GetDataStore("NightShiftReadinessProbe") end)
out.DataStoreHandle={Ok=ok,Detail=ok and "handle only; no read or write" or tostring(value)}
return game.HttpService:JSONEncode(out)
