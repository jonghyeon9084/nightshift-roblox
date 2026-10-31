local p=game:GetService("Players").LocalPlayer
local gui=p.PlayerGui:FindFirstChild("NightShiftHUD")
local out={HUD=gui~=nil,Labels={},Buttons={},Position=p.Character and tostring(p.Character:GetPivot().Position)}
if gui then for _,v in ipairs(gui:GetDescendants()) do
 if v:IsA("TextButton") then table.insert(out.Buttons,{Name=v.Name,Text=v.Text,Path=v:GetFullName(),Position=tostring(v.AbsolutePosition),Size=tostring(v.AbsoluteSize)})
 elseif v:IsA("TextLabel") then table.insert(out.Labels,v.Text) end
end end
return game:GetService("HttpService"):JSONEncode(out)
