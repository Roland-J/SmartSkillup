--[[Copyright © 2022, RolandJ
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of <addon name> nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL RolandJ BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.]]

-- This is me data; a gutted player var packed with skillup related flags. Arrrr, me mateys.

-------------------------------------------------------------------------------------------------------------------
-- Me and it's associated external variables
-------------------------------------------------------------------------------------------------------------------
me = T{}
known_spells = T{} -- keep these separate to avoid bloating me data
ability_recasts = T{}
buffactive = T{}
buffidactive = T{}
event_pause = T{} -- used to track event pauses (movement, zoning, NPC locks)



-------------------------------------------------------------------------------------------------------------------
-- Builds the me table from ffxi.player and adds in additional flags
-------------------------------------------------------------------------------------------------------------------
function build_me_table()
	me = T(windower.ffxi.get_player())
	
	-- MOVE VITALS TO ROOT
	for k, v in pairs(me.vitals) do
		me[k] = v
	end
	
	-- MOVE BUFFS TO BUFFACTIVE
	me.JA_locked = false
	for _, id in pairs(me.buffs) do
		local buff = res.buffs[id]
		if buff then
			buffactive[buff.en] = true
			buffidactive[buff.id] = true
			process_buff_change:schedule(2, buff, true) -- allow modules to initialize
		end
	end
	
	-- TRIM UNMAINTANED KEYS
	for k, _ in pairs(me) do
		if not k:wmatch('main_job*|sub_job*|hp*|mp*|id|status|JA_locked') then
			me[k] = nil
		end
	end
	
	-- DETECT PAUSE EVENT VIA STATUS (newStatus, oldStatus, newStatusId, oldStatusId)
	process_status_events(res.statuses[me.status].en, nil, me.status)
	
	-- ADD/MANIPULATE VARIOUS DATA
	me.status = res.statuses[me.status] and res.statuses[me.status].en
	me.in_town = cities:find(res.zones[windower.ffxi.get_info().zone].en) or false
	
	-- ADD DATA VIA HELPER FUNCTIONS
	update_me_party()
	update_me_food_locations(true)
	update_best_cures()
	if S{me.main_job, me.sub_job}:contains('BLU') then
		update_me_blu_spells()
	end
end



-------------------------------------------------------------------------------------------------------------------
-- Rebuilds me's party table and sets the me.can_summon_trusts and me.has_trust_target flags
-------------------------------------------------------------------------------------------------------------------
function update_me_party()
	local p = windower.ffxi.get_party()
	me.party = T{}
	me.can_summon_trusts = p.party3_count == 0 and p.party2_count == 0 and p.party1_count == 1 or p.party1_leader == me.id
	me.has_trust_target = false
	for i = 0, 5, 1 do
		local m = p['p' .. i]
		if m and m.mob then
			-- RECORD MEMBER
			me.party[i+1] = m.name
			
			-- SET TRUST TARGET FLAG
			if not me.has_trust_target and m.mob.spawn_type == 14 and not untargetable_trusts:contains(m.name) then
				me.has_trust_target = true
			end
		end
	end
end



-------------------------------------------------------------------------------------------------------------------
-- Rebuilds me's food_locations immediately on item use and delayed on item moves
-- Frontloaded to do the processing on the rare event (item move/use) and no processing on the common event (make_decision)
-------------------------------------------------------------------------------------------------------------------
function update_me_food_locations(immediate, item_used)
	-- ITEM ADD/REMOVE/USE: IGNORE NON-SKILLUP-FOOD ITEM USES
	if item_used and not skillup_foods:find(function(food) return item_used.id == food.id end) then
		return logger(chat_colors.purple, '[MISC ITEM MOVED] Ignoring non-skillup food item "' .. item_used.en .. '".', true)
	
	-- ITEM ADD/REMOVE/USE: RESCHEDULE TO IGNORE ITEM ADD/REMOVE/USE SPAM
	elseif not immediate or immediate == false then
		coroutine.close(threads.update_me_food_locations) -- only process last event in spam scenario
		threads.update_me_food_locations = update_me_food_locations:schedule(3, true, item_used)
		return logger(chat_colors.purple, '[SKILLUP FOOD MOVED] Rebuilding food locations in 3 secs...', true)
	end
	
	-- BUILD FOOD LOCATIONS & HAS_SKILLUP_FOOD FLAG
	logger(chat_colors.purple, '[FOOD LOCATION UPDATE] Rebuilding food locations' .. (item_used and 'due to "' .. item_used.en .. '" usage' or '') .. '...', true)
	me.food_locations = food_locations_template:copy()
	local bags_dump = windower.ffxi.get_items()
	me.has_skillup_food = false
	me.inventory_full = bags_dump.count_inventory >= bags_dump.max_inventory -- cache to reduce use_module's processing 
	-- LOOP THROUGH ENABLED ITEM BAGS
	for bag_tier, bag in ipairs(bags_ordered) do
		local enabled = bag.en == 'Recycle' and true or bags_dump['enabled_' .. bag.en:lower()]
		if enabled then
			-- LOOP THROUGH BAG CONTENTS
			for slot, item in pairs(bags_dump[bag.en:lower()]) do
				local food_tier, skillup_food = skillup_foods:find(function(f) return type(item) == 'table' and f.id == item.id end)
				if skillup_food then
					me.food_locations[food_tier][bag_tier]:insert(slot)
					me.has_skillup_food = true
				end
			end
		end
	end
	
	-- BUILD BEST/AVAILABLE FOOD FLAGS
	me.best_overall_food = nil
	me.best_inventory_food = nil
	for food_tier, food_tier_data in ipairs(me.food_locations) do
		for bag_tier, slots in ipairs(food_tier_data) do
			if #slots > 0 then
				-- EXIT IF BOTH ARE CACHED
				if me.best_overall_food and me.best_inventory_food then
					break
				end
				
				-- RECORD BEST OVERALL FOOD
				if not me.best_overall_food then
					me.best_overall_food = T{id=skillup_foods[food_tier].id, en=skillup_foods[food_tier].en, bag=bags_ordered[bag_tier], slot=slots[1]}
					--me.best_overall_food = T{item=T{id=skillup_foods[food_tier].id, en=skillup_foods[food_tier].en}, bag=bags_ordered[bag_tier], slot=slots[1]}
				end
				
				-- RECORD BEST INVENTORY FOOD
				if bags_ordered[bag_tier].en == 'Inventory' and not me.best_inventory_food then
					me.best_inventory_food = T{id=skillup_foods[food_tier].id, en=skillup_foods[food_tier].en}
				end
			end
		end
	end
	
	-- DROP LOCATIONS: NO LONGER NEEDED
	me.food_locations = nil
	
	-- DROP FOOD MODULE IF APPLICABLE
	if not me.has_skillup_food and modules and modules.food.active then
		windower.send_command('sms togm silent food')
		logger(chat_colors.red, '[FOOD MODULE DEACTIVATED] No more skillup food in available bags.')
	end
end



-------------------------------------------------------------------------------------------------------------------
-- Updates me's assigned BLU spells (versus known BLU spells)
-------------------------------------------------------------------------------------------------------------------
function update_me_blu_spells()
	me.blu_spells = T(windower.ffxi.get_mjob_data().spells):map(function(id) return res.spells[id].en end) --CREDIT: Azuresets.lua
end



-------------------------------------------------------------------------------------------------------------------
-- Updates me's vitals
-------------------------------------------------------------------------------------------------------------------
function update_me_vitals(id, data)
	if data:unpack('I', 5) == me.id then
		me.hp  = data:unpack('I', 9)
		me.mp  = data:unpack('I', 13)
		me.hpp = data:byte  (     id == 0x0DF and 0x17 or 0x1E)
		me.mpp = data:byte  (     id == 0x0DF and 0x18 or 0x1F)
	end
end



-------------------------------------------------------------------------------------------------------------------
-- Updates me's zone
-------------------------------------------------------------------------------------------------------------------
function update_me_zone(new_id, old_id)
	me.zone = res.zones[new_id].en
	me.in_town = cities:find(me.zone)
	me.zoning = true
	coroutine.schedule(function() me.zoning = nil end, 2)
end



------------------------------------------------------------------------------------------------------------------
-- Updates to various me's coords
-------------------------------------------------------------------------------------------------------------------
function update_me_coords(packet)
	local old_coords = me.coords
	local was_moving = me.moving
	me.coords = T{x=packet.X, y=packet.Y, z=packet.Z}
	me.moving = not me.coords:equals(old_coords)
	
	-- RETURN: FIRST OCCURRENCE
	if old_coords == nil then
		me.moving = false --needs to be initialized
		return logger(chat_colors.purple, '[COORDS] Exited on first occurrence.', true)
	
	-- BEGAN MOVING
	elseif me.moving and was_moving == false then
		pause_event('Moving')
		
	-- FINISHED MOVING
	elseif was_moving and me.moving == false then
		unpause_event('Moving', 1)
	end
end



-------------------------------------------------------------------------------------------------------------------
-- Updates me's job data on job change
-------------------------------------------------------------------------------------------------------------------
function update_me_job(main_job_id, main_job_level, sub_job_id, sub_job_level)
	me.main_job, me.main_job_full     = res.jobs[main_job_id].ens, res.jobs[main_job_id].en
	me.main_job_id, me.main_job_level	= main_job_id, main_job_level
	me.sub_job, me.sub_job_full 		= res.jobs[sub_job_id].ens, res.jobs[sub_job_id].en
	me.sub_job_id, me.sub_job_level	= sub_job_id, sub_job_level
	logger(chat_colors.purple, '[JOB CHANGE] Job changed  to ' .. me.main_job .. main_job_level .. '/' .. me.sub_job .. sub_job_level .. ', re-initializing...', true)
	initialize_sms('job change')
end



-------------------------------------------------------------------------------------------------------------------
-- Updates me's job levels on level up/down
-------------------------------------------------------------------------------------------------------------------
function update_me_level(level)
	me.main_job_level, me.sub_job_level = level,  math.floor(level/2)
	get_valid_spells()
end