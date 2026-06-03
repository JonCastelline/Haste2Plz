--[[
Copyright 2026 Jon Castelline

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

require('luau')
local config = require('config')
local packets = require('packets')
local resources = require('resources')

_addon.name = 'Haste2Plz'
_addon.author = 'Jon Castelline'
_addon.version = '1.0.0'
_addon.commands = {'haste2plz', 'h2p'}

local defaults = {
    enabled = true,
}

local settings = config.load(defaults)

local KORU_MORU = 'koru-moru'
local HASTE_I_ID = 33

local function normalize(name)
    if not name or name == '' then
        return nil
    end
    return name:lower()
end

local function player_has_buff(buff_id)
    local player = windower.ffxi.get_player()
    if not player or not player.buffs then
        return false
    end

    for _, id in ipairs(player.buffs) do
        if id == buff_id then
            return true
        end
    end

    return false
end

local last_haste_source = nil
local evaluate
local pending_haste_check = false

local function koru_moru_in_party()
    local party = windower.ffxi.get_party()
    if not party then
        return false
    end

    for i = 1, 18 do
        local member = party['p' .. i]
        if member and normalize(member.name) == KORU_MORU then
            return true
        end
    end

    return false
end

local function cancel_buff(buff_id)
    if windower.ffxi.cancel_buff then
        local ok = pcall(windower.ffxi.cancel_buff, buff_id)
        if ok then
            return true
        end
    end

    windower.send_command('cancel ' .. tostring(buff_id))
    return true
end

local function can_cancel_haste()
    if not settings.enabled then
        return false, 'disabled'
    end

    if not koru_moru_in_party() then
        return false, 'Koru-Moru is not in party'
    end

    if not player_has_buff(HASTE_I_ID) then
        return false, 'you do not have Haste'
    end

    if not last_haste_source or last_haste_source.kind ~= 'haste_i' then
        return false, 'last haste source is not plain Haste'
    end

    return true, nil
end

local function schedule_haste_check(delay)
    if pending_haste_check then
        return
    end

    pending_haste_check = true
    coroutine.schedule(function()
        pending_haste_check = false
        evaluate()
    end, delay or 0.25)
end

local function is_player_target(target_id)
    local player = windower.ffxi.get_player()
    return player and target_id and player.id == target_id
end

local function note_haste_action(packet)
    local actor = packet.Actor and windower.ffxi.get_mob_by_id(packet.Actor)
    if not actor or normalize(actor.name) == nil then
        return
    end

    local spell_id = tonumber(packet['Target 1 Action 1 Param'] or packet.Param)
    local spell = spell_id and resources.spells[spell_id] or nil
    local spell_name = spell and (spell.english or spell.name) or nil
    if not spell_name then
        return
    end

    local spell_name_lower = spell_name:lower()
    if not spell_name_lower:find('haste', 1, true) then
        return
    end

    if not is_player_target(packet['Target 1 ID']) then
        return
    end

    local actor_name = normalize(actor.name)
    if spell_name_lower == 'haste ii' then
        last_haste_source = { kind = 'haste_ii', time = os.clock() }
        return
    end

    if spell_name_lower == 'haste' then
        last_haste_source = { kind = 'haste_i', time = os.clock() }
        schedule_haste_check(0.35)
        return
    end

    -- Fallback for localized variants that still contain "haste" in the resource name.
    if actor_name == KORU_MORU then
        last_haste_source = { kind = 'haste_ii', time = os.clock() }
    else
        last_haste_source = { kind = 'haste_i', time = os.clock() }
        schedule_haste_check(0.35)
    end
end

function evaluate(announce)
    local ok, reason = can_cancel_haste()
    if not ok then
        if announce then
            windower.add_to_chat(200, 'Haste2Plz: No action - ' .. reason .. '.')
        end
        return false
    end

    cancel_buff(HASTE_I_ID)
    last_haste_source = nil
    if announce then
        windower.add_to_chat(200, 'Haste2Plz: Cancelled Haste so Koru-Moru can land Haste II.')
    end
    return true
end

windower.register_event('load', function()
    last_haste_source = nil
    coroutine.schedule(evaluate, 1)
end)

windower.register_event('login', function()
    last_haste_source = nil
    coroutine.schedule(evaluate, 1)
end)

windower.register_event('zone change', function()
    last_haste_source = nil
    coroutine.schedule(evaluate, 1)
end)

windower.register_event('logout', function()
    last_haste_source = nil
end)

windower.register_event('party change', function()
    coroutine.schedule(evaluate, 0.5)
end)

windower.register_event('gain buff', function(buff_id)
    if buff_id == HASTE_I_ID then
        schedule_haste_check(0.4)
    end
end)

windower.register_event('incoming chunk', function(id, data)
    if id ~= 0x028 then
        return
    end

    local packet = packets.parse('incoming', data)
    if not packet or (packet.Category ~= 8 and packet.Category ~= 4) then
        return
    end

    note_haste_action(packet)
end)

windower.register_event('addon command', function(command)
    command = command and command:lower() or 'status'

    if command == 'on' then
        settings.enabled = true
        settings:save()
        windower.add_to_chat(200, 'Haste2Plz: Enabled.')
        evaluate()
    elseif command == 'off' then
        settings.enabled = false
        settings:save()
        windower.add_to_chat(200, 'Haste2Plz: Disabled.')
    elseif command == 'check' then
        evaluate(true)
    elseif command == 'status' then
        local koru = koru_moru_in_party() and 'yes' or 'no'
        local haste = player_has_buff(HASTE_I_ID) and 'yes' or 'no'
        local source = last_haste_source and last_haste_source.kind or 'unknown'
        windower.add_to_chat(200, 'Haste2Plz: ' .. (settings.enabled and 'Enabled' or 'Disabled'))
        windower.add_to_chat(200, 'Haste2Plz: Koru-Moru in party: ' .. koru)
        windower.add_to_chat(200, 'Haste2Plz: Haste buff: ' .. haste .. ', last source: ' .. source)
    else
        windower.add_to_chat(200, 'Haste2Plz: Commands: on, off, check, status.')
    end
end)
