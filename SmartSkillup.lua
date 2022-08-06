--[[Copyright © 2022, RolandJ
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of SmartSkillup nor the
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

_addon.version = '0.0.7'
_addon.name = 'SmartSkillup'
_addon.author = 'RolandJ'
_addon.commands = {'sms','smartskillup'}



-------------------------------------------------------------------------------------------------------------------
-- Libraries used throughout the addon
-------------------------------------------------------------------------------------------------------------------
chars = require('chat/chars')
packets = require('packets')
ui = require('libs/sms_ui')
res = require('resources')
require('functions')
require('statics')
require('helpers')
require('tables')
require('luau')
require('me')
config = require('config')
defaults = T{
	user_ui_scalar = 1,
	top_left = {
		x = 100,
		y = 100,
	},
	ui_hidden = false,
}
settings = config.load(defaults)
config.save(settings)



-------------------------------------------------------------------------------------------------------------------
-- Variables used for generating main job skills/spells and weighting said spells
-------------------------------------------------------------------------------------------------------------------
skill_to_skillup = false -- the current skill to skillup, toggles between the skills_to_skillup if multiple are defined
skills_to_skillup = T{} -- the list of skills to skillup for the current session
valid_spells = T{} -- the player's main job's current list of valid spells (based on known spells & main job's level)
valid_spells_sorted = T{} -- the same as above, but sorted by weight (see below for details)
ignored_spells = T{} -- a bonus record of spell handling, to provide curious users better visibility ingame to how their list was compiled
main_skills = T{} -- the player's current list of skill statuses. structure: {['Healing Magic'] = {level= 360, capped= true, en= 'Healing Magic', id= 33}, etc}



-------------------------------------------------------------------------------------------------------------------
-- Variables used for handling/tracking/preserving the skillup loop
-------------------------------------------------------------------------------------------------------------------
active = false -- the main on/off switch for skilling up
paused = false -- toggles true when over the limit for decision.issues or out of mp and idle. (Over-Limit Triggers: invalid targets, or continuous movement)
loop = T{issues=0, issues_max=6} -- misc flags about the loop
going = false -- flags if the loop is going, used to prevent duplicate loops
auto_shutdown = false -- tracks if the auto shutdown feature is engaged
skill_data_retrieved = false -- tracks if skill data has been fetched from the server for the current session
threads = T{} -- holds the names returned by various coroutines, used for closing them when needed
decision = T{} -- holds information about the most recent decision
auto_resting = false -- used to track when the SMS decided to /heal, to avoid interrupting full-MP player /heals



-------------------------------------------------------------------------------------------------------------------
-- Modules variables: misc logic that can be added to the session
-------------------------------------------------------------------------------------------------------------------
modules_default = T{
	mp_limit = T{label = 'MP Limit', available = true , hidden = false}, -- first three are always available
	t_target = T{label = 'T.Target', available = true , hidden = false},
	food     = T{label = 'Food'    , available = true , hidden = false},
	moogle   = T{label = 'Moogle'  , available = false, hidden = false, res = {res.spells:find(function(r) return r.en == 'Moogle' end)}[2]}, -- use dynamic lookups to protect against ID shifts
	refresh  = T{label = 'Refresh' , available = false, hidden = false, --[[res varies]]},
	haste    = T{label = 'Haste'   , available = false, hidden = false, --[[res varies]]},
	georef   = T{label = 'Geo-Ref.', available = false, hidden = false, res = {res.spells:find(function(r) return r.en == 'Geo-Refresh' end)}[2]},
	sublim   = T{label = 'Sublim.' , available = false, hidden = false, res = {res.job_abilities:find(function(r) return r.en == 'Sublimation' end)}[2]},
	convert  = T{label = 'Convert' , available = false, hidden = false, res = {res.job_abilities:find(function(r) return r.en == 'Convert' end)}[2]},
	compo    = T{label = 'Compos.' , available = false, hidden = true , res = {res.job_abilities:find(function(r) return r.en == 'Composure' end)}[2]},
	radial   = T{label = 'Radial.A', available = false, hidden = true , res = {res.job_abilities:find(function(r) return r.en == 'Radial Arcana' end)}[2]},
}



-------------------------------------------------------------------------------------------------------------------
-- Functions to keep the loop/timeout mechanism functioning in a uniform/legible/debuggable manner
-------------------------------------------------------------------------------------------------------------------
function start_timeout(delay, source)
	threads.timeout = process_event:schedule(delay or 1, {timeout=true, source=source})
	logger(chat_colors.purple, '[TIMEOUT START] Timeout started in ' .. (delay or 1) .. ' secs' .. (source and ' by ' .. source or '') .. '.', false, true)
end

function end_timeout(source)
	coroutine.close(threads.timeout)
	logger(chat_colors.purple, '[TIMEOUT END] Timeout ended' .. (source and ' by ' .. source or '') .. '.', false, true)
end

function schedule_decision(delay, source, ...)
	threads.make_decision = make_decision:schedule(delay, source)
	if {...}[2] then logger(...) end
end

function end_decision()
	coroutine.close(threads.make_decision)
end

function end_timeout_and_decision(source, ...)
	end_timeout(source or 'end_timeout_and_decision')
	end_decision()
	if {...}[2] then logger(...) end
end



-------------------------------------------------------------------------------------------------------------------
-- The main brains of the skillup loop/timeout CREDIT: This was only  made possible by Rubenator's extensive consultation.
-- ISSUE: If the player heals in the 0.3 secs between sending a cast command and midcasting, the cast can go through
-------------------------------------------------------------------------------------------------------------------
function process_event(event)
	if not active or paused then
		return logger(chat_colors.purple, '[EVENT CANCEL] SMS inactive or paused. (timeout: ' .. tostring(event.timeout) .. (event.stage and ', stage: ' .. event.stage .. ' ' .. event.name or '') .. ')', true)
	elseif event_pauses:count(true) > 0 then
		return logger(chat_colors.purple, '[EVENT CANCEL] Event pauses active: ' .. event_pauses:keyset():concat(', ') .. ' (timeout: ' .. tostring(event.timeout) .. (event.stage and ', stage: ' .. event.stage .. ' ' .. event.name or '') .. ')', true)
	end
	
	-- TIMEOUT: AN ANTICIPATED EVENT DID NOT OCCUR
	if event.timeout then
		logger(chat_colors.purple, '[TIMEOUT] Making a new decision.', true)
		make_decision(event.source)
		
	-- EVENT: AN ACTUAL EVENT IS OCCURRING
	else
		local reason = event.stage:upper() .. ' EVENT' .. larr .. (event.res and event.res.en or event.name):upper()
		-- PRECAST: NO SUCH EVENT
		-- MIDCAST: AN ACTION STARTED
		if event.stage == 'midcast' then
			decision.stage = 'midcast'
			local aftercast_delay = event.res.cast_time * (buffactive.Addle and 1.2 or 1) + 2.5
			end_timeout_and_decision(reason)
			logger(chat_colors.purple, '[' .. reason .. '] Scheduled a timeout in ' .. aftercast_delay .. ' secs.', true)
			start_timeout(aftercast_delay, reason)
			
		-- AFTERCAST: AN ACTION ENDED
		elseif event.stage == 'aftercast' and not me.moving then
			-- HANDLE LOOP
			decision.stage = 'aftercast'
			increment_casts(event)
			end_timeout_and_decision(reason) --E.PAUSE schedules a decision, we need to end it too on interrupts (workflow skips midcast in that case, accelerating this step)
			schedule_decision(2, reason, chat_colors.purple, '[' .. reason .. '] Scheduled a decision in 2 secs.', true)
		
			-- TRACK ACTIVE INDICOLURE
			if S{'Casting Completed','Already Active'}:contains(event.name) and event.res and event.res.en:startswith('Indi-') then
				me.indicolure = event.res.en
				logger(chat_colors.purple, '[INDICOLURE] "' .. event.res.en .. '" is active...', true)
			end
		end
	end
end



-------------------------------------------------------------------------------------------------------------------
-- Help make_decision decide if a module needs to be used right now (return true to halt the decision in favor of the module usage)
-------------------------------------------------------------------------------------------------------------------
function use_module()
	local spell_recasts = windower.ffxi.get_spell_recasts()
	local ability_recasts = windower.ffxi.get_ability_recasts()
	
	-- MOOGLE/TRUST-TARGET MODULES IN-TOWN NOTICE
	if me.in_town and me.can_summon_trusts then
		if modules.t_target.active and not me.has_trust_target then
			logger(chat_colors.yellow, '[TRUST TARGET MODULE] Please move out of a city in order to summon a trust to target...')
		elseif modules.moogle.active and not me.party:find(modules.moogle.res.en) then
			logger(chat_colors.yellow, '[MOOGLE MODULE] Please move out of a city in order to summon Moogle...')
		end
	end
	
	-- TRUST TARGET SUMMON MODULE
	if modules.t_target.active and me.can_summon_trusts and not me.has_trust_target and not me.in_town then
		for id, spell in pairs(res.spells) do
			if spell.type == 'Trust' and known_spells[id] and spell_recasts[spell.recast_id] == 0 then
				logger(chat_colors.grey, '[TRUST TARGET MODULE] Summoning "' .. spell.en .. '" as a trust target...')
				if me.main_job_level < 99 then
					logger(chat_colors.yellow, '[NOTICE] You are not ilvl, so your mileage with this module may vary.')
				end
				windower.send_command('input ' .. spell.prefix .. ' "' .. spell.en .. '"')
				return true
			end
		end
	
	-- MOOGLE MODULE (actual)
	elseif modules.moogle.active and me.can_summon_trusts and not me.party:find(modules.moogle.res.en) and not me.in_town then
		windower.send_command('input ' .. modules.moogle.res.prefix .. ' "' .. modules.moogle.res.en .. '"')
		return true
	
	-- CONVERT MODULE
	elseif modules.convert.active and not me.JA_locked and me.mpp < 25 and me.mp > 0 and modules.convert.ready then
		logger(chat_colors.grey, '[CONVERT MODULE] Using "' .. modules.convert.res.en .. '"...')
		windower.send_command('input ' .. modules.convert.res.prefix .. ' "' .. modules.convert.res.en .. '" <me>')
		schedule_module_readiness(modules.convert)
		modules.convert.recovering = true
		return true
	
	-- CONVERT HP RECOVERY MODULE
	elseif modules.convert.recovering then
		local cure = me.best_cures[me.best_cure_index]
		if me.hpp > 80 or me.mp < me.best_cures[me.best_cure_index].mp_cost then
			modules.convert.recovering = nil
			if me.hpp > 80 then return false end
			logger(chat_colors.yellow, '[CONVERT RECOVERY ISSUE] Not enough MP to recover.')
		elseif me.mp >= me.best_cures[me.best_cure_index].mp_cost then
			me.best_cure_index = me.best_cure_index == 1 and 2 or 1
			windower.send_command('input ' .. cure.prefix .. ' "' .. cure.en .. '" <me>')
			return true
		end
	
	-- RADIAL ARCANA MODULE
	elseif modules.radial.available and not me.JA_locked and me.mpp < 60 and modules.radial.ready and windower.ffxi.get_mob_by_target('pet') then
		logger(chat_colors.grey, '[AUTO MODULE] Using "' .. modules.radial.res.en .. '"...')
		windower.send_command('input ' .. modules.radial.res.prefix .. ' "' .. modules.radial.res.en .. '" <me>')
		schedule_module_readiness(modules.radial)
		return true
		
	-- COMPOSURE ON MODULE (before refresh/haste)
	elseif modules.compo.active and not me.JA_locked and not modules.compo.buffactive and modules.compo.ready then
		logger(chat_colors.grey, '[AUTO MODULE] Temporarily applying "Composure"...')
		if modules.refresh.active then windower.send_command('cancel refresh') end
		if modules.haste.active then windower.send_command('cancel haste') end
		windower.send_command('input ' .. modules.compo.res.prefix .. ' "' .. modules.compo.res.en .. '" <me>') --this will trigger a decision in 1.5
		schedule_module_readiness(modules.compo)
		return true
		
	-- REFRESH MODULE
	elseif modules.refresh.active and not buffidactive[modules.refresh.res.status] and me.mp >= modules.refresh.res.mp_cost then
		logger(chat_colors.grey, '[REFRESH MODULE] Buffing self with "' .. modules.refresh.res.en .. '"...')
		windower.send_command('input ' .. modules.refresh.res.prefix .. ' "' .. modules.refresh.res.en .. '" <me>')
		return true
		
	-- HASTE MODULE
	elseif modules.haste.active and not buffidactive[modules.haste.res.status] and me.mp >= modules.haste.res.mp_cost then
		logger(chat_colors.grey, '[HASTE MODULE] Buffing self with "' .. modules.haste.res.en .. '"...')
		windower.send_command('input ' .. modules.haste.res.prefix .. ' "' .. modules.haste.res.en .. '" <me>')
		return true
	
	-- COMPOSURE OFF MODULE (after refresh/haste)
	elseif buffactive.Composure then
		logger(chat_colors.grey, '[AUTO MODULE] Removing "Composure"...')
		windower.send_command('cancel composure') -- won't occur for 1~2 seconds
		buffactive.Composure = nil -- accelerate the flag
		return use_module() -- restart module processing from the top
	
	-- GEO-REFRESH MODULE
	elseif modules.georef.active and not modules.georef.buffactive and not me.in_town then
		local pet = windower.ffxi.get_mob_by_target('pet')
		-- NO LUOPAN YET
		if not pet then
			logger(chat_colors.grey, '[GEO-REFRESH MODULE] Buffing self with "' .. modules.georef.res.en .. '"...')
			windower.send_command('input ' .. modules.georef.res.prefix .. ' "' .. modules.georef.res.en .. '" <me>')
			modules.georef.buffactive = true -- speed up this flag
			modules.georef.warned = nil
		-- LUOPAN TOO FAR TO RELEASE
		elseif math.sqrt(pet.distance) >= 20 then
			if modules.georef.warned then return false end
			local distance = math.sqrt(pet.distance) > 50 and '50+' or string.format("%.1f", math.sqrt(pet.distance))
			logger(chat_colors.yellow, '[GEO-REFRESH MODULE] Luopan is too far away to release. (' .. distance .. ' yalms. Limit: 20)')
			me.modules.georef.warned = true
		-- LUOPAN CAN BE RELEASED
		else
			windower.send_command('input /ja "Full Circle" <me>')
		end
		return true
		
	-- SUBLIMATION MODULE
	elseif modules.sublim.active and me.status ~= 'Resting' then
		-- NOT ACTIVATED NOR COMPLETED & NOT HEALING SOON (activated: 187, completed: 188 (hence the +1))
		if (not buffidactive[modules.sublim.res.status] and not buffidactive[modules.sublim.res.status+1] and me.mpp > 25 and modules.sublim.ready)
		-- INCOMPLETE BUT PLAYER NEEDS TO HEAL (don't check ready, just lock the loop here till sublimation is deactivated)
		or (buffidactive[modules.sublim.res.status] and me.mpp < 10)
		-- COMPLETE AND PLAYER NEEDS MP
		or (buffidactive[modules.sublim.res.status+1] and me.mpp < 50 and modules.sublim.ready) then
			windower.send_command('input ' .. modules.sublim.res.prefix .. ' "' .. modules.sublim.res.en .. '" <me>')
			schedule_module_readiness(modules.sublim)
			return true
		end
	
	-- SKILL UP FOOD MODULE	
	elseif modules.food.active and not buffactive.Food and me.has_skillup_food then
		-- MAKE BEST FOOD AVAILABLE IF INVENTORY IS NOT FULL
		if not me.inventory_full and me.best_overall_food and me.best_overall_food.en ~= (me.best_inventory_food or {}).en then
			logger(chat_colors.yellow, '[FOOD MODULE] Moving your ' .. me.best_overall_food.bag.en .. '\'s "' .. me.best_overall_food.en .. '" to your inventory...')
			windower.ffxi.get_item(me.best_overall_food.bag.id, me.best_overall_food.slot, 1)
			me.best_inventory_food = me.best_overall_food
			coroutine.sleep(0.5)
		end
		-- NOTIFY IF BEST FOOD UNAVAILABLE
		if me.best_overall_food.en ~= me.best_inventory_food.en then
			logger(chat_colors.yellow, '[FOOD MODULE] Cannot access your ' .. me.best_overall_food.bag.en .. '\'s "' .. me.best_overall_food.en .. '". (' .. (me.best_overall_food.id-5888)*20 .. '% boost)')
		end
		logger(chat_colors.grey, '[FOOD MODULE] Using magic skill up food "' .. me.best_inventory_food.en .. '. (' .. (me.best_inventory_food.id-5888)*20 .. '% boost)')
		windower.send_command('input /item "' .. me.best_inventory_food.en .. '" <me>')
		return true
	end
	
	return false
end


-------------------------------------------------------------------------------------------------------------------
-- THE function that wears the pants and makes the decisions around here ;)
-------------------------------------------------------------------------------------------------------------------
local force_stop_cast = false -- a temp testing measure
function make_decision(source) --must be global to both A) be called from above and B) schedule itself internally
	logger(chat_colors.purple, '[MAKE DECISION] Source: ' .. tostring(source), false, true)
	-- PROCESS EXIT SCENARIOS
	if not active or paused then -- not in a skillup session
		end_timeout()
		return logger(chat_colors.purple, '[DECISION STOP] SmartSkillup ' .. (paused and 'paused' or 'not active') ..', exiting make_decision.', true)
	elseif skill_to_skillup == nil then -- skillup session with nothing to skillup
		end_timeout('no skills remaining')
		return logger(chat_colors.purple, '[DECISION STOP] CAUSE: No skill to skillup.', true)
	elseif force_stop_cast then -- a temp testing measure
		end_timeout('force stop cast')
		force_stop_cast = false
		return logger(chat_colors.purple, '[DECISION STOP] Force stopped make_decision and reset force_stop_cast var.', true)
	elseif use_module() then
		start_timeout(2.5, 'module use')
		return logger(chat_colors.purple, '[DECISION STOP] CAUSE: Module being used.', true)
	elseif skill_to_skillup == 'Summoning Magic' and windower.ffxi.get_mob_by_target('pet') then
		start_timeout(1, 'release')
		windower.send_command('input /release')
		return logger(chat_colors.purple, '[DECISION STOP] Releasing the player\'s avatar...', true)
	end
	
	-- PROCESS MP LIMIT ISSUE
	local spells_below_limit = mp_limit and valid_spells_sorted[skill_to_skillup]:count(function(s) return s.mp_cost <= mp_limit end)
	if mp_limit and spells_below_limit == 0 then
		windower.send_command('sms mplimit toggle silent')
		logger(chat_colors.yellow, '[MP LIMIT ISSUE] No "' .. skill_to_skillup .. '" spells available cheaper than ' .. mp_limit .. '; increasing limit')
	end
	
	-- DETERMINE & CAST NEXT SPELL
	local spell_recasts = windower.ffxi.get_spell_recasts()
	decision = T{min_recast = 0}
	for _, spell in ipairs(valid_spells_sorted[skill_to_skillup]) do
		-- CONTINUE: INDOCOLURE ALREADY ACTIVE
		if spell.en == me.indicolure then -- can't recast active indicolure
			logger(chat_colors.purple, 'SKIP: Skipping ' .. spell.en .. ', indicolure already active...', true)
			if mp_limit and spells_below_limit == 1 then
				windower.send_command('sms mplimit toggle silent')
				logger(chat_colors.yellow, '[MP LIMIT ISSUE] Increasing limit to allow a second indi spell.')
			end
		
		-- CONTINUE: SPELL AWAITING RECAST
		elseif spell_recasts[spell.recast_id] > 0 then -- Spell waiting on recast
			if decision.min_recast == 0 or spell_recasts[spell.id] < decision.min_recast then
				decision.best_spell, decision.min_recast = spell, spell_recasts[spell.id]
			end
			
		-- BREAK: WAIT FOR TWICE AS CHEAP SPELL IF READY IN LESS THAN 1.2 SECS
		elseif decision.best_spell and spell_recasts[decision.best_spell.recast_id]/60 < 1.2 and spell.mp_cost / decision.best_spell.mp_cost > 2 then
			decision.awaiting_more_efficient_spell = true
			logger(chat_colors.purple, '[SPELL BREAK] Broke on "' .. spell.en ..'" due to comparison to "' .. decision.best_spell.en .. '"...', false, true)
			break
			
		-- BREAK: SPELL OVER MP_LIMIT (MODULE)
		elseif mp_limit and spell.mp_cost > mp_limit then
			decision.over_mp_limit = true
			logger(chat_colors.purple, '[SPELL BREAK] Broke on "' .. spell.en ..'" due to being ' .. (spell.mp_cost - mp_limit) .. ' over the MP limit of ' .. mp_limit .. '.', false, true)
			break
		
		-- RETURN: CHEAPEST SPELL TOO EXPENSIVE (NEED TO REST)
		elseif me.mp < spell.mp_cost + (me.convert_ready and 1 or 0) then -- ensure 1 MP is left if convert is viable
			logger(chat_colors.red, '[MP NEEDED] Insufficient MP for next spell "' .. spell.en .. '" (MP: ' .. me.mp .. '/' .. spell.mp_cost .. ')')
			decision.out_of_mp = true
			return decide_to_rest('Out of MP')
		else
			-- RESOLVE TARGET STRING (<me>, <p1>, <t>, etc)
			local target_string = (function()
				-- SELF/PARTY SPELLS (Prefer trusts for ilvl target skillup chance multiplier)
				if spell.targets.Self and spell.targets.Party then
					for i = 1, 5, 1 do
						local entity = windower.ffxi.get_mob_by_target('p' .. i)
						local castable = not untargetable_trusts:contains((entity or {}).name)
						if (entity or {}).spawn_type == 14 and castable and entity.distance:sqrt() <= 20 then
							return 'p' .. i
						end
					end
					return '<me>' -- fallback target
					
				-- SELF-ONLY SPELLS
				elseif spell.targets.Self then
					return '<me>'
					
				-- ENEMY-ONLY SPELLS (Prefer <t>, fallback to <bt> for the convenience of multiboxers, but no claim botting here.)
				elseif spell.targets.Enemy then
					for _, target_option in ipairs(T{'<t>', '<bt>'}) do
						local entity = windower.ffxi.get_mob_by_target(target_option)
						if entity and entity.spawn_type == 16 and entity.hpp > 0 then
							if math.sqrt(entity.distance) > 20 then decision.target_issue = {'Target out of range',spell.en}
							else return target_option end
						else
							decision.target_issue = decision.target_issue or {'Unable to find target',spell.en}
						end
					end
				end
			end)()
			
			-- CAST SPELL IF TARGET OBTAINED
			if target_string then
				loop.issues = 0
				toggle_to_next_skill()
				windower.send_command('input /ma "' .. spell.en .. '" ' .. target_string)
				decision.res = spell
				decision.stage = 'precast'
				start_timeout(1.5, 'decision')
				logger(chat_colors.purple, '[DECISION] Attempting to cast "' .. spell.en .. '" on ' .. target_string .. '...', true)
				return true
			end
		end
	end
	
	-------------------------------------
	-- PAST THIS POINT: ISSUE TERRITORY
	-------------------------------------
	
	-- TRACK ISSUE COUNT & GET NEXT DECISION DELAY
	loop.issues = loop.issues + 1 -- reset on each successful decision
	me.session_issues = (me.session_issues or 0) + 1 -- reset on OFF
	local delay = decision.min_recast > 0 and (decision.min_recast/60) + 0.1 --[[recast issue]] or 4 --[[target issue]]
	
	-- RETURN: TARGET ISSUE, BUT ANOTHER SKILL IS CASTABLE (ex: if a target can't be found for Dark Magic, move on to immediately cast the first castable skill
	-- TODO
	
	-- RETURN: REST IF NEEDED ON 10TH ISSUE (player is probably AFK, fill-er-up!)
	if loop.issues == 10 then
		local resting = decide_to_rest('10th Issue', true)
		if resting then return end
	end
	
	-- DETERMINE WHEN TO NOTIFY (don't spam the player)
	local notify = (function()
		if loop.issues < 10 then -- once per issue until 10th issue
			return true
		elseif loop.issues == 10 then -- special notice on 10th issue
			logger:schedule(0.2, chat_colors.yellow, '[IMPORTANT] You will now only be notified once every 10 consecutive issues.')
			return true
		elseif loop.issues:fmod(10) == 0 and loop.issues < 100 then -- once per 10 until 100
			return true
		elseif loop.issues == 100 then -- special notice on 100th issue
			logger:schedule(0.2, chat_colors.yellow, '[IMPORTANT] You will now only be notified once every 100 consecutive issues.')
			return true
		elseif loop.issues:fmod(100) == 0 then -- once per 100 issues from there on out
			return true
		end
		return false
	end)()
	
	-- NOTIFY IF APPLICABLE
	if notify then
		local count_string = ' (Issue #' .. loop.issues .. ')'
		if decision.target_issue then
			toggle_to_next_skill()
			logger(chat_colors.yellow, '[TARGET ISSUE] ' .. decision.target_issue[1] .. ' for "' .. decision.target_issue[2] .. '".' .. count_string)
		elseif decision.min_recast > 0 then
			logger(chat_colors.purple, '[DECISION DELAY] Scheduling a retry in ' .. string.format("%.2f",delay) .. ' due to "' .. decision.best_spell.en .. '" recast timer...' .. count_string, true)
		elseif decision.over_mp_limit then
			--don't mention this?
		else
			logger(chat_colors.purple, '[DECISION ISSUE] Unable to cast, scheduling another cast in ' .. string.format("%.2f",delay) .. ' seconds...' .. count_string, true)
		end
	end
	
	-- SCHEDULE NEXT DECISION
	schedule_decision(delay, 'DECISION:ISSUE ' .. loop.issues)
end



-------------------------------------------------------------------------------------------------------------------
-- A function where we decide whether or not to rest after running out of MP or make_decision tries
-------------------------------------------------------------------------------------------------------------------
function decide_to_rest(source, give_countdown, override)
	source = source or 'UNDEFINED'
	logger(chat_colors.purple, '[DECIDE TO REST] Source: ' .. source, true)
	
	-- RETURN: POTENTIALLY VALID MOB
	for _, target in ipairs({'t', 'bt'}) do
		local mob = windower.ffxi.get_mob_by_target(target)
		if me.status == 'Engaged' -- I know, this could go on it's own line. I'm condensing it into here, though.
		or (target == 't' and mob and mob.claim_id == me.id and mob.hpp > 0)
		or (target == 'bt' and mob and mob.spawn_type == 16 and mob.hpp > 0 and mob.distance:sqrt() < 20) then
			return logger(chat_colors.yellow, '[MP NEEDED] Cannot rest due to valid target "' .. mob.name .. '".')
		end
	end
	-- RETURN: MP NOT NEEDED
	if not decision.out_of_mp and me.mpp > 30 and loop.issues < loop.issues_max then
		return logger(chat_colors.purple, '[PROCESS RESTING] CANCEL: MP Needed flag is false and player MPP above 30.', true)
	-- RETURN: ALREADY RESTING
	elseif me.status == 'Resting' or event_pauses.Resting then
		return
	end
	
	-- BEGIN RESTING
	loop.issues = 0
	auto_resting = true
	end_timeout_and_decision(source)
	if give_countdown then
		initialize_healing_notice(10, source .. (override and ' <30% MP' or ''), true)
	else
		windower.send_command('input /heal')
	end
	return true
end



-------------------------------------------------------------------------------------------------------------------
-- The processors for the various windower events (and a packet) being monitored
-------------------------------------------------------------------------------------------------------------------
function process_status_change(newStatusId, oldStatusId)
	local newStatus, oldStatus = res.statuses[newStatusId].en, res.statuses[oldStatusId].en
	me.status = newStatus
	process_status_events(newStatus, oldStatus, newStatusId, oldStatusId)
	processing_resting_change(newStatus, oldStatus, newStatusId, oldStatusId)
	
	if active then
		if oldStatus == 'Resting' and active and not paused then
			me.getting_up = true
			coroutine.schedule(function() me.getting_up = nil end, 3)
		end
		
		-- PLAYER IS ENGAGED
		if newStatus == 'Engaged' then
			-- TERMINATE ANY HEALING COUNTDOWN
			terminate_healing_notice('Player engaged')
			-- ENGAGE TO UNPAUSE
			if not paused then
				begin_loop('PLAYER ENGAGED', true)
			end
		
		-- PLAYER IS IDLE
		elseif newStatus == 'Idle' then
			-- DISENGAGEMENT
			if oldStatus == 'Engaged' then
				if me.shutdown_awaiting_disengage then
					windower.send_command:schedule(2, 'input /shutdown')
					return logger(chat_colors.yellow, '[AUTO-SHUTDOWN] Performing the requested /shutdown.')
				end
			
				local override = not auto_resting and me.mpp < 30
				if auto_resting or override then
					decide_to_rest('Player disengaged', true, override)
				end
			end
		
		-- PLAYER IS RESTING
		elseif newStatus == 'Resting' then
			-- handled in processing_resting_change
		end
	end
end

function process_action(act)
	if not act.actor_id or act.actor_id ~= me.id then return end

	-- CASTING STARTED
	if act.category == 8 and act.param ~= 28787 then
		process_event({name='Casting Started',     stage='midcast',   timeout=false, res=res.spells[act.targets[1].actions[1].param]})
		
	-- CASTING INTERRUPTED
	elseif act.category == 8 then
		process_event({name='Casting Interrupted', stage='aftercast', timeout=false}) -- no spell provided in act data

	-- CASTING COMPLETED
	elseif act.category == 4 then
		process_event({name='Casting Completed',   stage='aftercast', timeout=false, res=res.spells[act.param]})
		
	-- JOB ABILITY USE
	elseif act.category == 6 then
		process_event({name='Job Ability Used',    stage='aftercast', timeout=false, res=res.job_abilities[act.param]})

	-- ITEM STARTED
	elseif act.category == 9 and act.param == 24931 then
		process_event({name='Item Started',        stage='midcast',   timeout=false, res=res.items[act.targets[1].actions[1].param]})
		
	-- ITEM INTERRUPTED
	elseif act.category == 9 then
		process_event({name='Item Interrupted',    stage='aftercast', timeout=false}) -- no item provided in act data
		
	-- ITEM COMPLETED
	elseif act.category == 5 then
		process_event({name='Item Completed',      stage='aftercast', timeout=false, res=res.items[act.param]})
		update_me_food_locations(false, res.items[act.param])
	end
end

function process_action_message_packet(packet) -- https://github.com/Windower/Lua/wiki/Message-IDs
	-- UNABLE TO CAST
	if S{17 --[[Unable1]], 18 --[[Unable2]]}:contains(packet.Message) then
		process_event({name='Unable to Cast',      stage='aftercast', timeout=false}) -- no spell provided in act data
	
	-- EFFECT ALREADY ACTIVE
	elseif packet.Message == 523 then
		process_event({name='Already Active', stage='aftercast', timeout=false, res=res.spells[packet['Param 1']]})
	
	-- STANDARD/BLU SPELL LEARN MESSAGE
	elseif S{23 --[[Normal]], 419 --[[Blue Magic]]}:contains(packet.Message) then
		get_valid_spells() --rebuilds list
		logger(chat_colors.purple, '[SPELL LEARNED] Rebuilt valid spells.', true)
	end
end

function process_outgoing_chunk(id, data, modified, injected, blocked)
	--logger(chat_colors.purple,'Outgoing Chunk ID: 0x' .. string.format('%.3X', id))
	--logger(207, tostring(packets.parse('ougoing', data) or {}))
	
	-- PLAYER MOVEMENT
	if id == 0x015 then
		update_me_coords(packets.parse('outgoing', data))
	
	-- PLAYER CHANGED SET BLU SPELLS
	elseif id == 0x102 then
		coroutine.close(threads.update_me_blu_spells) -- avoid processing spammed packets
		threads.update_me_blu_spells = update_me_blu_spells:schedule(7)
	
	-- PLAYER INCREASED A MERIT ABILITY
	elseif id == 0x0BE then
		determine_modules()
	
	end
end

function process_incoming_chunk(id, data, modified, injected, blocked)
	--logger(chat_colors.purple,'Incoming Chunk ID: 0x' .. string.format('%.3X', id))
	--table.vprint(packets.parse('incoming', data) or {})
	
	-- SKILL INFO PACKETS
	if id == 0x062 then -- CREDIT: Partially SMD111
		process_skill_data(packets.parse('incoming', data))
		
	-- CHAR UPDATE PACKETS
	elseif S{0x0DF --[[resting]], 0x0E2 --[[misc, like refresh]]}:contains(id) then
		process_char_update(id, data)
	
	-- ACTION MESSAGES (BATTLEMOD WORKAROUND: It blocks action msg register_events, but not these.)
	elseif id == 0x029 then
		process_action_message_packet(packets.parse('incoming', data))
		
	-- NPC LOCK PACKET (IDs: NPC Lock 1 & 2, String Lock)
	elseif S{0x032, 0x033, 0x034}:contains(id) then
		pause_event('NPC')
	
	-- NPC MENU PACKET (HPs: lock > *MENU* > unlock #1 > player decision > unlock #2
	elseif id == 0x05c then
		me.awaiting_0x052 = true
		coroutine.schedule(function() me.awaiting_0x052 = nil end, 1.5)
	
	-- NPC UNLOCK PACKET
	elseif id == 0x052 then
		if me.awaiting_0x052 then return (function() me.awaiting_0x052 = nil end)() end -- ignores HP's unlock #1
		unpause_event('NPC', 1.5)
	
	-- ZONE OUT PACKET
	elseif id == 0x00B then
		ui.show_primitives(false)
		pause_event('Zoning')
	
	-- ZONE IN PACKET
	elseif id == 0x00A then
		ui.show_primitives(true)
		unpause_event('Zoning', 6)

	-- PARTY STRUCTURE UPDATE PACKETS
	elseif id == 0x0C8 then
		coroutine.close(threads.update_me_party) -- avoid processing spammed packets
		threads.update_me_party = update_me_party:schedule(1)
	end
end


-------------------------------------------------------------------------------------------------------------------
-- Function that initializes the UI when skill data is retrieved if skill_data_retrieved is false
-------------------------------------------------------------------------------------------------------------------
function initialize_ui()
	ui.set_header_text('SmartSkillup') -- Adds our label to the UI
	ui.set_main_job(me.main_job) -- Adds our main job to the UI footer
	local button_config = (function()
		local config = T{}
		for skill_en, data in pairs(main_skills) do
			config[skill_en] = T{
				command   = 'sms togs silent ' .. skill_en,
				subtext  = tostring(data.level),
				color    = data.capped and 'blue' or 'white',
			}
		end
		return config
	end)()
	local sidecar_config = (function()
		local config = T{}
		for _, key in ipairs(modules_order) do
			if modules[key].available and not modules[key].hidden then
				config:insert(T{
					name    = modules[key].label,
					command = 'sms togm silent ' .. modules[key].label,
					color   = 'white',
				})
			end
		end
		return config
	end)()
	ui.set_button_config(button_config, sidecar_config) -- Defines the button layout
	if settings.ui_hidden then
		return logger(chat_colors.yellow, '[UI HIDDEN] The UI is hidden due to user preferences. Type "//sms uishow" to restore the UI.')
	end
	ui.rebuild_buttons() -- Shows the button if not settings.ui_hidden
end



-------------------------------------------------------------------------------------------------------------------
-- The initialize function that is auto-called on load and on-job-change, and can also be called ad-hoc via //sms resetsession
-------------------------------------------------------------------------------------------------------------------
initialize_sms = function()
	active, paused, going, skill_data_retrieved, skill_to_skillup, skills_to_skillup = false, false, false, false, false, T{}
	build_me_table()
	get_main_skills()
	get_valid_spells()
	determine_modules()
	skill_data_request_timeout() -- triggers UI build once data is retrieved
end



-------------------------------------------------------------------------------------------------------------------
-- All event registrations
-------------------------------------------------------------------------------------------------------------------
windower.register_event('outgoing chunk', process_outgoing_chunk)
windower.register_event('incoming chunk', process_incoming_chunk)
windower.register_event('gain buff', function(id) process_buff_change(res.buffs[id], true) end)
windower.register_event('lose buff', function(id) process_buff_change(res.buffs[id], nil ) end)
windower.register_event('level up', 'level down', update_me_level)
windower.register_event('job change', update_me_job)
windower.register_event('status change', process_status_change)
windower.register_event('zone change', update_me_zone)
windower.register_event('action', process_action)
windower.register_event('load', initialize_sms)
windower.register_event('unload', 'logout', ui.destroy_primitives)
windower.register_event('add item', 'remove item', function(_, _, id) update_me_food_locations(false, res.items[id]) end)

windower.register_event('addon command', function(...)
	local cmd = T{...}[1] and T{...} or T{'help'}
	local callback = cmd[1] == 'callback' and cmd:remove(1) or false
	logger(chat_colors.purple, '[COMMAND] ' .. cmd:concat(' '), false, true)
	---------------------------
	--[[ STANDARD COMMANDS ]]--
	---------------------------
	if T{'addskill', 'adds', 'delskill', 'dels', 'rs', 'togskill', 'togs'}:contains(cmd[1]:lower()) then
		local silent = cmd[2] == 'silent' and cmd:remove(2) or false --UI buttons use this
		local origCmd = cmd:remove(1) --drop 'addskill' arg
		local toggling = T{'togskill', 'togs'}:contains(origCmd)
		
		-- ENSURE INITIALIZED
		if not skill_data_retrieved then
			if callback then -- prevent infinite loops
				return logger(chat_colors.red, '[ERROR] Failed to retrieve skill level/cap data.')
			end
			windower.send_command('wait 3; skillup callback ' .. origCmd .. ' ' .. cmd:concat(' '))
			return logger(chat_colors.yellow, '[WAIT] Processing, please wait... (SmartSkillup is still initializing)')
		end
		
		-- SEARCH FOR MATCH
		local search_term = windower.convert_auto_trans(cmd:concat('')):lower():gsub("%s", ""):gsub("%p", "")
		local main_skill, match_en, matches = nil, nil, 0
		for _, skill in pairs(res.skills) do
			local fuzzyname = skill.en:lower():gsub("%s", ""):gsub("%p", "") -- CREDIT: SuperWarp
			if fuzzyname:startswith(search_term) then
				main_skill, match_en, matches = main_skills[skill.en], skill.en, matches + 1
			end
		end
		
		-- DETERMINE CURRENT ACTION
		local adding = toggling and not skills_to_skillup:find(match_en) or T{'addskill', 'adds'}:contains(origCmd)
		
		-- PROCESS EXIT SCENARIOS
		if matches ~= 1 then
			return logger(chat_colors.red, '[ERROR] ' .. matches .. ' matches found. Please try again to narrow your search to one result...')
		elseif not main_skill then
			return logger(chat_colors.red, '[DENIED] As a ' .. me.main_job .. ', you cannot skill up ' .. match_en .. '.')
		elseif main_skill.capped == nil then
			if callback then
				return logger(chat_colors.red, '[ERROR] Failed to retrieve skill cap status, please try again.') --to prevent infinite loops
			end
			packets.inject(packets.new('outgoing', 0x061)) -- requests skill packet
			windower.send_command('wait 2; skillup callback ' .. origCmd .. ' ' .. cmd:concat(' '))
			return logger(chat_colors.yellow, '[WAIT] Please wait, fetching skill cap status...')
		elseif adding then
			if main_skill.capped and not debugModes:find(true) then
				return logger(chat_colors.red, '[DENIED] ' .. match_en .. ' is currently capped. (' .. main_skill.level .. '/' .. main_skill.level .. ')')
			elseif skills_to_skillup:find(match_en) then
				return logger(chat_colors.yellow, '[UNNECESSARY] "' .. match_en .. '" is already in your skillup list.')
			elseif valid_spells[match_en] == nil or valid_spells[match_en]:length() == 0 then
				return logger(chat_colors.red, '[DENIED] No "' .. match_en .. '" spells available. Try //sms spellreport!')
			elseif S{'Geomancy','Handbell'}[match_en] and 2 > valid_spells_sorted[match_en]:count(function(s) return s.en:startswith('Indi-') end) then
				return logger(chat_colors.red '[DENIED] Not enough indi spells to alternate. Please learn more indi spells and try again.')
			end
		elseif not adding then
			if not skills_to_skillup:find(match_en) then
				return logger(chat_colors.red, '[DENIED] ' .. match_en .. ' has not been added to the current session.')
			end
		end
		
		-- ADD/REMOVE SKILL FROM SESSION
		if adding then
			ui.button_active(main_skill.en, true) --on the flip side, this goes in remove_skill_from_session
			skills_to_skillup:insert(main_skill.en)
			toggle_to_next_skill() -- this is needful, otherwise skill_to_skillup would never get an initial value
			if not silent then return logger(chat_colors.green, '[SUCCESS] Added "' .. main_skill.en .. '" to your skillup list.') end
		else
			remove_skill_from_session(main_skill.en)
			if not silent then return logger(chat_colors.green, '[SUCCESS] Removed "' .. main_skill.en .. '" from your skillup list.') end
		end
	elseif T{'on', 'go', 'start', 'begin', 'commence'}:contains(cmd[1]:lower()) then
		begin_loop('SMS GO', true)
	elseif T{'off', 'come', 'stop', 'finish', 'complete'}:contains(cmd[1]:lower()) then
		-- PROCESS EXIT SCENARIO
		if not active then
			return logger(chat_colors.red, '[DENIED] There is no active skillup session to attempt to stop.')
		end
		
		-- END AND PRODUCE REPORT
		logger(chat_colors.grey, '[FINISH] Skillup ending, producing your skillup report...')
		going, active = false, false
		ui.active(false)
		print_skillup_report()
	elseif cmd[1] == 'paused' then -- UI puts out this command, remap it
		windower.send_command('sms pause')
	elseif T{'pause', 'pauseon', 'pauseoff'}:contains(cmd[1]:lower()) then
		local pausing = cmd[1]:lower() == 'pause' and not paused or cmd[1]:lower() == 'pauseon'
		local silent = cmd[2] and cmd[2] == 'silent' and cmd:remove(2) or false
		-- PROCESS EXIT SCENARIOS
		if not active then
			return logger(chat_colors.red, '[DENIED] There is no active skillup session to attempt to pause.')
		elseif pausing == paused then
			return logger(chat_colors.red, '[DENIED] The skillup session is already ' .. (pausing and '' or 'un') .. 'paused.')
		end
		
		paused = pausing
		ui.paused(pausing) -- will revert to orange if there's an event pause active
		
		if not silent then
			local term = pausing and 'paused' or 'unpaused'
			logger(chat_colors.yellow, '[' .. term:upper() .. '] Skillup session has been ' .. term .. (issues and ' for issues; engage to resume' or '') .. '.')
		end
		
		if pausing then
			going = false -- don't do the inverse of this, as begin_loop is requiring going to be false
			end_timeout_and_decision('PLAYER PAUSE')
		else
			begin_loop('PLAYER UNPAUSE')
		end
	elseif cmd[1] == 'autoshutdown' then
		auto_shutdown = not auto_shutdown
		logger(chat_colors.yellow, '[AUTO-SHUTDOWN] Feature has been ' .. (auto_shutdown and 'activated; will /shutdown when last skill is capped' or 'deactivated') .. '.')
		ui.auto_shutdown(auto_shutdown)
	elseif cmd[1] == 'nomagicskills' then -- called by UI button
		logger(chat_colors.yellow, 'There are no magic skills that the player\'s main job can skill up.')
	elseif cmd[1] == 'resetsession' then
		if active or #skills_to_skillup > 0 then
			logger(chat_colors.yellow, '[SESSION RESET] Session resetting, producing your skillup report...' .. (reason and ' (Trigger: ' .. reason .. ')' or ''))
			print_skillup_report()
		end
		initialize_sms('user')
	-------------------------
	--[[ MODULE COMMANDS ]]--
	-------------------------
	elseif cmd[1]:lower() == 'mplimit' then
		local toggle = cmd[2] == 'toggle' and cmd:remove(2) or false
		local silent = cmd[2] == 'silent' and cmd:remove(2) or false
		if toggle then
			mp_limit = mp_limit or 10
			mp_limit = (math.floor(mp_limit/5)*5) + 5
			if mp_limit > 50 then mp_limit = 10 end
		elseif not cmd[2] then
			return logger(chat_colors.grey, 'MP Limit is ' .. tostring(mp_limit))
		else
			mp_limit = tonumber(cmd[2])
		end
		ui.set_text('limit', mp_limit)
		if not modules.mp_limit.active then
			windower.send_command('sms addm MPLimit')
		end
		if not silent then logger(chat_colors.grey, 'Set MP Limit to ' .. mp_limit) end
	elseif T{'addmodule', 'addm', 'delmodule', 'delm', 'togmodule', 'togm'}:contains(cmd[1]:lower()) then
		local silent = cmd[2] == 'silent' and cmd:remove(2) or false --UI buttons use this
		local name = cmd[2] and cmd[2]:lower()
		if not name then
			logger(chat_colors.red, '[DENIED] Please specify a module...')
		end
		
		-- SEARCH FOR RESULT
		local mod_i, mod
		for i, data in pairs(modules) do
			local fuzzyname = data.label:lower():gsub("%s", ""):gsub("%p", "") -- CREDIT: SuperWarp
			if fuzzyname:startswith(name) or data.label:lower():startswith(name) then
				if mod then
					mod = 'multiple results'
				else
					mod_key, mod = i, data
				end
			end
		end
		
		-- PROCESS EXIT SCENARIOS
		if mod == nil then
			return logger(chat_colors.red, '[DENIED] Module "' .. name .. '" does not exist...')
		elseif mod == 'multiple results' then
			return logger(chat_colors.red, '[DENIED] Matched multiple modules, please narrow your search term and try again.')
		elseif not mod.available then
			return logger(chat_colors.red, '[DENIED] Your main job does not get access to module "' .. name .. '"...')
		end
		
		-- DETERMINE ADDING/TOGGLING & EXECUTE
		local toggling = T{'togmodule', 'togm'}:contains(cmd[1]) --used to determine adding var
		local adding = toggling and not mod.active or T{'addmodule', 'addm'}:contains(cmd[1]:lower())
		
		-- PERFORM ADDITIONAL MODULE-SPECIFIC CHECKS
		if mod.label == 'MP Limit' then
			mp_limit = adding and (mp_limit or 10) or nil
			ui.set_visible('limit_hdr', adding)
			ui.set_visible('limit', adding)
		elseif mod.label == 'Convert' and me.best_cures:empty() then
			return logger(chat_colors.red, '[DENIED] No cure spells available for convert recovery.')
		elseif adding and mod.label == 'Refresh' and modules.sublim.available then
			modules.sublim.active = false
			ui.button_active('Sublim.', false)
		elseif adding and mod.label == 'Sublim.' and modules.refresh.available then
			modules.refresh.active = false
			ui.button_active('Refresh', false)
		elseif adding and mod.label:wmatch('Moogle|T.Target') then
			if not me.can_summon_trusts then
				logger(chat_colors.yellow, '[NOTICE] Your character can\'t summon trusts due to party composition.')
			elseif me.in_town then
				logger(chat_colors.yellow, '[NOTICE] Your character can\'t summon trusts due to being in ' .. me.in_town .. '.')
			end
		elseif adding and mod.label == 'Food' and not me.has_skillup_food then
			return logger(chat_colors.red, '[DENIED] No magic skillup food in available bags.')
		elseif adding and mod.label == 'Geo-Ref.' and me.in_town then
			logger(chat_colors.yellow, '[NOTICE] Cannot currently cast Geo-Refresh due to being in ' .. me.in_town .. '.')
		end
		
		-- ACTIVATE MODULE
		mod.active = adding
		ui.button_active(mod.label, adding)
		if not silent then logger(chat_colors[adding and 'green' or 'red'], '[MODULE] ' .. (adding and 'Activated' or 'Deactivated') .. ' the "' .. mod.label .. '" module...') end
		
		if S{'Refresh','Haste'}[mod.label] and modules.compo.available then
			evaluate_composure_active()
		end
	---------------------
	--[[ UI COMMANDS ]]--
	---------------------
	elseif 'uizoom' == cmd[1]:lower() then
		local mode = cmd[2] and S{'in','out'}[cmd[2]] and cmd:remove(2) or nil
		if mode == nil then
			logger(chat_colors.red, '[UI ZOOM] Please specify "in" or "out".')
		else
			if (settings.user_ui_scalar < 1.5 and mode == 'in') or (settings.user_ui_scalar > 0.5 and mode == 'out') then
				settings.user_ui_scalar = settings.user_ui_scalar + (mode == 'in' and 0.1 or -0.1)
				config.save(settings)
				ui.set_new_scalar()
			end
		end
	elseif T{'uiscale', 'uis', 'scale'}:contains(cmd[1]:lower()) then
		if cmd[2] == nil then
			logger(chat_colors.grey, '[UI SCALE] Your UI\'s current scale is ' .. settings.user_ui_scalar)
		else
			local new_scalar = tonumber(cmd[2])
			if new_scalar == nil or new_scalar > 1.5 or new_scalar < 0.5 then
				return logger(chat_colors.red, '[DENIED] Please provide a ui scale between 0.5 and 1.5.')
			else
				settings.user_ui_scalar = tonumber(cmd[2])
				config.save(settings)
				ui.set_new_scalar()
			end
		end
	elseif 'uipos' == cmd[1]:lower() then
		if cmd[2] == nil then
			return logger(chat_colors.grey, '[UI POSITION] Your UI\'s current x/y coordinates are ' .. settings.top_left.x .. '/' .. settings.top_left.y)
		else
			local x, y = tonumber(cmd[2]), tonumber(cmd[3])
			if x == nil or y == nil then
				return logger(chat_colors.grey, '[SET UI POSITION] Please provide two numbers, separated by a space, as the x/y coordinates.')
			else
				settings.top_left.x, settings.top_left.y = x, y
				config.save(settings) 
				ui.rebuild_buttons()
			end
		end
	elseif 'uirebuild' == cmd[1]:lower() then
		ui.rebuild_buttons()
		logger(chat_colors.grey, '[UI REBUILD] Rebuilt user UI. (TIP: Use this if your buttons get desynced on dragging.)')
	elseif 'uidefaults' == cmd[1]:lower() then
		settings:update(defaults, true) --overwrites settings with defaults
		config.save(settings)
		ui.rebuild_buttons()
		logger(chat_colors.grey, '[UI DEFAULTS] Restored UI defaults. (TIP: Use this or uipos if you drag your UI offscreen.)')
	elseif T{'uihide', 'uishow'}:contains(cmd[1]:lower()) then
		local hiding = cmd[1]:lower() == 'uihide'
		if (hiding and settings.ui_hidden) or (not hiding and not settings.ui_hidden) then
			return logger(chat_colors.grey, '[UI ' .. (hiding and 'HIDE' or 'SHOW') .. '] Denied, UI is already ' .. (hiding and 'hidden' or 'visible') .. '.')
		end
		ui.show_primitives(not hiding)
		settings.ui_hidden = hiding
		config.save(settings)
		return logger(chat_colors.grey, '[UI ' .. (hiding and 'HIDE' or 'SHOW') .. '] UI has been ' .. (hiding and 'hidden' or 'revealed') .. '.')
	------------------------
	--[[ DEBUG COMMANDS ]]--
	------------------------
	elseif T{'reload', 'r'}:contains(cmd[1]:lower()) then
		windower.send_command('lua r smartskillup')
	elseif T{'unload', 'u'}:contains(cmd[1]:lower()) then
		windower.send_command('lua u smartskillup')
	elseif cmd[1]:lower() == 'debug' then -- "//sms debug" or "//sms debug deep"
		local desiredMode = cmd[2] and cmd[2]:lower() or 'norm'
		if not debugModes:keyset():find(desiredMode) then
			return logger(chat_colors.red, '[ERROR] No "' .. cmd[2] .. '" debug mode exists.')
		end
		debugModes[desiredMode] = not debugModes[desiredMode]
		logger(chat_colors.purple, '[DEBUG MODES] Active modes: ' .. (debugModes:find(true) and debugModes:filter(true):keyset():concat(', ') or '[NONE]'))
		for en, data in pairs(main_skills) do -- helps player know they can add capped skills
			ui.set_text_color(en, (debugModes:find(true) or not data.capped) and 'white' or 'blue')
		end
	elseif cmd[1] == 'test' then
	elseif cmd[1] == 'allchars' then
		local chars = require('chat/chars')
		for k, v in pairs(chars) do
			logger(chat_colors.grey, v .. ' (' .. k .. ')')
		end
	elseif cmd[1] == 'allcolors' then
		for i = 0, 255, 1 do
			logger(i, 'color code ' .. i)
		end
	elseif cmd[1] == 'forcestopcast' then
		force_stop_cast = true
	elseif cmd[1]:lower() == 'printplayer' then
		logger(chat_colors.grey, 'Printing player...')
		table.vprint(windower.ffxi.get_player())
	elseif cmd[1]:lower() == 'printtarget' then
		local entity = windower.ffxi.get_mob_by_target(cmd[2] and cmd[2]:lower() or 't')
		if type(entity) == 'table' then
			logger(chat_colors.grey, 'Printing target...')
			table.vprint(entity)
		else
			logger(chat_colors.grey, 'Invalid target...')
		end
	elseif cmd[1]:lower() == 'print' then -- ex: //sms print main_skills['Enfeebling Magic'].capped
		if cmd[2] == nil then
			return logger(chat_colors.grey, '[PRINT ERROR] A subject is required. (//sms print subject)')
		end
		local subject = assert(loadstring('return ' .. cmd:slice(2):concat(' ')))()
		if subject == nil then
			logger(chat_colors.grey, '[PRINT ERROR] ' .. cmd[2] .. ' does not exist...')
		else
			logger(chat_colors.grey, '[PRINT] Printing ' .. cmd:slice(2):concat(' ') .. '...')
			if type(subject) == 'table' then
				table.vprint(subject)
			else
				logger(chat_colors.grey, tostring(subject))
			end
		end
	elseif S{'eval','exec'}[cmd[1]:lower()] then -- ex: //sms eval ui.rebuild_buttons()
		logger(chat_colors.grey, '[EVALUATE] Evaluating "' .. cmd:slice(2):concat(' ') .. '"...')
		assert(loadstring(cmd:slice(2):concat(' ')), 'Eval error, check syntax: ' .. cmd:slice(2):concat(' '))()
		logger(chat_colors.grey, '[EVALUATE FINISHED] Processing complete.')
	-----------------------
	--[[ HELP COMMANDS ]]--
	-----------------------
	elseif cmd[1]:lower() == 'spellreport' then
		print_spell_availability(cmd[2] and cmd[2]:lower() == 'weighted')
	elseif cmd[1]:lower() == 'modulehelp' then
		logger(chat_colors.grey, _addon.name .. '  v' .. _addon.version .. ' modules:')
		logger(chat_colors.grey, 'MP Limit:     Only spells below the current limit will be auto-cast.')
		logger(chat_colors.grey, 'Trust Target: Ensures a targetable trust is summoned, as their ilvl mob status boosts skillup rate.')
		logger(chat_colors.grey, 'SkillUp Food: Uses the best magic food available in your inventory, sack, satchel, or case.')
		logger(chat_colors.grey, '*Moogle:      Summons the "Moogle" trust to utilize its refresh and skillup rate boost.')
		logger(chat_colors.grey, '*Convert:     Uses convert when MP is below 25%. Requires a cure spell for use in recovering.')
		logger(chat_colors.grey, '*Refresh:     Casts the most potent refresh available to your main/sub jobs.')
		logger(chat_colors.grey, '*Haste:       Casts the most potent haste available to your main/sub jobs.')
		logger(chat_colors.grey, '*Geo-Refresh: Sustains a Geo-Refresh colure on the player.')
		logger(chat_colors.grey, '*Sublimation: Automatically activates and completes Sublimation.')
		logger(chat_colors.grey, 'NOTE: Modules marked with * are only available when the player is on a relevant main job.')
	elseif cmd[1]:lower() == 'automodules' then
		logger(chat_colors.grey, _addon.name .. '  v' .. _addon.version .. ' auto modules:')
		logger(chat_colors.grey, 'Composure: Used prior to refresh and haste - and removed after - if player is RDM50+.')
		logger(chat_colors.grey, 'Radial Arcana: Used when MP is below 60% if player is GEO75+ and has the related merit.')
	elseif cmd[1]:lower() == 'help' then
		logger(chat_colors.grey, _addon.name .. '  v' .. _addon.version .. ' commands:')
		logger(chat_colors.grey, '//sms [command]')
		logger(chat_colors.grey, 'addskill     - If skillable by the player\'s main job, adds the given skill to the current skillup session.')
		logger(chat_colors.grey, 'delskill     - Removes the given skill from the current skillup session.')
		logger(chat_colors.grey, 'togskill     - Adds/removes, if applicable, the given skill from the current skillup session.')
		logger(chat_colors.grey, 'mplimit      - An optional limit to provide heavier MP conservation; any spells below this limit will be skipped.')
		logger(chat_colors.grey, 'go           - Activates a skillup session. Cannot activate if no skills have been added.')
		logger(chat_colors.grey, 'stop         - If active, deactivates the skillup session and provides a skillup report.')
		logger(chat_colors.grey, 'pause        - If active, toggles the session\'s paused/unpaused state.')
		logger(chat_colors.grey, 'pauseon      - If active and unpaused, pauses the session.')
		logger(chat_colors.grey, 'pauseoff     - If active and paused, unpauses the session.')
		logger(chat_colors.grey, 'autoshutdown - If active, will perform /shutdown when the session\'s last remaining skill is capped.')
		logger(chat_colors.grey, 'addmodule    - Turns on the selected module. (Modules are additional misc skillup logic.)')
		logger(chat_colors.grey, 'delmodule    - Turns of the selected module. (Modules are additional misc skillup logic.)')
		logger(chat_colors.grey, 'resetsession - Deactivates any active skillup session and removes all selected skills. (called on job change)')
		logger(chat_colors.grey, 'uihide       - Hides the UI if it was visible. (persists on reload)')
		logger(chat_colors.grey, 'uishow       - Reveals the UI if it was hidden. (persists on reload)')
		logger(chat_colors.grey, 'uiscale      - Returns the UI scale or sets it to the provided scale. (persists on reload)')
		logger(chat_colors.grey, 'uipos        - Returns the UI position or sets it to the provided x/y coordinates. (persists on reloadd)')
		logger(chat_colors.grey, 'uirebuild    - Rebuilds the UI using the user preferences. (useful to restore the UI without reloading addon)')
		logger(chat_colors.grey, 'uidefaults   - Returns the UI to the default position and scale. (wipes all persisting settings)')
		logger(chat_colors.grey, 'debug        - Reveals debug-level logging in the chat window and allows capped skills to be added to the session.')
		logger(chat_colors.grey, 'spellreport  - Prints the spells SmartSkillup will use. Do "//sms spellreport weighted" to see the spell weights!')
		logger(chat_colors.grey, 'modulehelp   - Displays additional information on each module.')
		logger(chat_colors.grey, 'automodules  - Displays information on the automatic modules not listed in the UI.')
		logger(chat_colors.grey, 'help         - Shows this help text.')
		logger(chat_colors.grey, 'DID YOU KNOW: You can only recieve skillups for skills natively available to your current main job.')
		logger(chat_colors.grey, 'DID YOU KNOW: The UI can be dragged with right mouse clicks! Try it out!')
		logger(chat_colors.grey, 'DID YOU KNOW: For additional module information, type "//sms modulehelp"!')
	else
		return windower.send_command('skillup help')
	end
end)