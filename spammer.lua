-- ==========================================
-- spammer by 1722% capa sem hack (credit to them)
-- ==========================================

local SpammerWindow = gui.Window("spammer_v6_window", "Spammer by 1722% capa sem hack", 100, 100, 320, 380)

local ModeCombo = gui.Combobox(SpammerWindow, "spam_mode", " Spammer mode", "Disable", "Fixed text (Single)", "Multi-Lines (Ctrl+V)")
local CustomText = gui.Editbox(SpammerWindow, "spam_text", " Single msg")
local MultiLineText = gui.Editbox(SpammerWindow, "spam_multi", " Paste the lines here")
local DelaySlider = gui.Slider(SpammerWindow, "spam_delay", " Delay", 0.1, 0.05, 5.0, 0.05)
local ChatType = gui.Combobox(SpammerWindow, "spam_chat_type", " Type of chat", "All Chat", "Team Chat")

local last_time = 0
local multi_index = 1
local is_paused = false

local PauseBtn = gui.Button(SpammerWindow, "pause", function()
    is_paused = not is_paused
end)

local function SafeChat(message)
    if not message or message == "" or message:match("^%s*$") then return end
    pcall(function()
        if ChatType:GetValue() == 0 then
            client.ChatSay(message)
        else
            client.ChatTeamSay(message)
        end
    end)
end

local function GetLines(str)
    local lines = {}
    if str then
        for line in str:gmatch("[^\r\n]+") do
            table.insert(lines, line)
        end
    end
    return lines
end

callbacks.Register("Draw", "Spammer_Logic_Pedro_Global", function()
    local menu_active = gui.Reference("Menu"):IsActive()
    SpammerWindow:SetInvisible(not menu_active)

    PauseBtn:SetText(is_paused and "play" or "pause")

    local mode = ModeCombo:GetValue()
    CustomText:SetInvisible(mode ~= 1)
    MultiLineText:SetInvisible(mode ~= 2)

    if mode == 0 or is_paused then return end

    local current_time = common.Time()
    
    if (current_time - last_time) >= DelaySlider:GetValue() then
        if engine.GetServerIP() ~= nil then 
            
            if mode == 1 then
                SafeChat(CustomText:GetValue())
            elseif mode == 2 then
                local lines = GetLines(MultiLineText:GetValue())
                if #lines > 0 then
                    if multi_index > #lines then multi_index = 1 end
                    SafeChat(lines[multi_index])
                    multi_index = multi_index + 1
                end
            end
            
            last_time = current_time
        end
    end
end)