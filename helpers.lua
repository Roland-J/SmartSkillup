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

-- Helper functions not running the skillup loop, events, or me

-------------------------------------------------------------------------------------------------------------------
-- A convenient logger that prefixes every message
-------------------------------------------------------------------------------------------------------------------
debugModes = T{norm=false, deep=false}
function logger(color, msg, isDebugMsg, deepDebugMsg)
	if isDebugMsg == nil or (debugModes.norm and isDebugMsg) or (debugModes.deep and deepDebugMsg) then
		windower.add_to_chat(color, '[SmartSkillup] ' .. tostring(msg))
	end
end



-------------------------------------------------------------------------------------------------------------------
-- The end-of-session report generation, provides count of casts and skill levels gained
-------------------------------------------------------------------------------------------------------------------
function print_skillup_report()
	local reported = false
	for skill_en, data in pairs(main_skills) do
		local gained_levels = (data.level or 0) - (data.level_init or 0)
		if data.casts > 0 or gained_levels > 0 then
			reported = true
			logger(chat_colors.grey, '   [' .. skill_en .. '] ' .. data.casts .. ' casts' .. (gained_levels > 0 and (' (+' .. gained_levels .. ' levels)') or ''))
		end
		logger(chat_colors.purple, '   [' .. skill_en .. '] Initial: ' .. data.level_init .. ', Current: ' .. data.level, true)
		data.casts = 0 -- reset this var now to prepare for the next session
	end
	if not reported then logger(chat_colors.grey, '   Nothing to report...') end
end



-------------------------------------------------------------------------------------------------------------------
-- The spell availability report, helps users understand which spells SmartSkillup is using, and why
-------------------------------------------------------------------------------------------------------------------
function print_spell_availability(show_weight)
	logger(chat_colors.grey, '[SPELL REPORT] Printing your spell ' .. (show_weight and 'weight' or 'availability') .. ' report...')
	logger(chat_colors.grey, 'NOTE: Only spells your ' .. me.main_job .. me.main_job_level .. '/' .. me.sub_job .. me.sub_job_level .. ' knows & can cast/skillup on.')
	if show_weight then
		logger(chat_colors.grey, 'NOTE: Spells are weighted equally by MP cost and cast time.')
		logger(chat_colors.grey, 'LEGEND: Spells are prefixed by spell weight; lower is better.')
	else
		logger(chat_colors.grey, 'LEGEND: ' .. chars.wcircle --[[⚪]] .. ' SmartSkillup will use these spells')
		logger(chat_colors.grey, 'LEGEND: ' .. chars.bcircle --[[⚫]] .. ' SmartSkillup ignores these spells')
	end
	for skill_en, spells in pairs(valid_spells_sorted) do
		logger(chat_colors.grey, '  ' .. chars.ref --[[¤]] .. ' ' .. skill_en:upper())
		if not main_skills[skill_en].parent then
			-- PRINT VALID SPELLS
			for _, spell in pairs(spells) do
				local prefix = show_weight and string.format("%.0f", spell.weight*100) or chars.wcircle --[[⚪]]
				logger(chat_colors.grey, '      ' .. prefix .. ' ' .. spell.en)
			end
			
			-- PRINT IGNORED SPELLS (don't do this for the weighted variant, though)
			if not show_weight then
				for _, spell in pairs(ignored_spells[main_skills[skill_en].parent or skill_en] or {}) do
					logger(chat_colors.grey, '      ' .. chars.bcircle --[[⚫]] .. ' ' .. spell.en .. ' (' .. spell.reason .. ')')
				end
			end
			
			-- PRINT NO-SPELLS PLACEHOLDER (main job can skill it but player has no spells yet)
			if #spells == 0 and #ignored_spells[main_skills[skill_en].parent or skill_en] == 0 then
				logger(chat_colors.grey, '      ' .. chars.bcircle --[[⚫]] .. ' No available spells')
			end
		else
			logger(chat_colors.grey, '      ' .. chars.circlejot --[[◎]] .. ' See "' .. main_skills[skill_en].parent:upper() .. '"')
		end
	end
	logger(chat_colors.grey, 'End of spell report...')
end



-------------------------------------------------------------------------------------------------------------------
-- A toggle that adds support for allowing a player to skill multiple skills in one session
-------------------------------------------------------------------------------------------------------------------
toggle_to_next_skill = function()
	if #skills_to_skillup == 0 then
		skill_to_skillup = nil
		if not active then return end
		return coroutine.schedule(function()
			logger(chat_colors.yellow, '[END OF SESSION] No skills remain in the current session. Ending session...')
			if auto_shutdown then 
				if me.status == 'Engaged' then
					me.shutdown_awaiting_disengage = true
				else
					windower.send_command('input /shutdown')
					logger(chat_colors.yellow, '[AUTO-SHUTDOWN] Performing the requested /shutdown.')
				end
			else
				windower.send_command('sms stop')
			end
		end, 1) --delay for correct log order
	end
	
	local current_index = skills_to_skillup:find(skill_to_skillup) or 0
	local desired_index = current_index < #skills_to_skillup and current_index + 1 or 1 -- increment unless on max index, goto 1 if so
	skill_to_skillup = skills_to_skillup[desired_index]
end



-------------------------------------------------------------------------------------------------------------------
-- A function that removes a skill from the skill session and handles termination, if applicable
-------------------------------------------------------------------------------------------------------------------
remove_skill_from_session = function(skill_en, cap_event)
	logger(chat_colors.purple, 'Removing ' .. skill_en .. ' from the session...', true)
	if not skills_to_skillup:find(skill_en) then --this skill isn't in the session
		if not cap_event then
			return logger(chat_colors.red, '[REMOVE] Attempted to remove not-in-session ' .. skill_en .. ', why?', true)
		end
	elseif #skills_to_skillup >= 1 then
		if skills_to_skillup:find(skill_en) then
			skills_to_skillup:delete(skill_en)
			toggle_to_next_skill()
			ui.button_active(skill_en, false)
		else
			return logger(chat_colors.purple, '[REMOVE ISSUE] Cannot remove "' .. skill_en .. '", it is not the skill_to_skillup (' .. skill_to_skillup .. ')', true)
		end
	else
		return logger(chat_colors.red, '[REMOVE] Unhandled skill cap event. Why?', true)
	end
end



-------------------------------------------------------------------------------------------------------------------
-- Processes spells to determine if the player's main job can skill them up
-------------------------------------------------------------------------------------------------------------------
local function is_valid(spell, skill_en, for_module) --half of this function came from SMD111
	if not known_spells[spell.id] then --player doesn't know
		return false
	elseif (not spell.levels[me.main_job_id] or spell.levels[me.main_job_id] > me.main_job_level) --mj can't cast
	and (not spell.levels[me.sub_job_id] or spell.levels[me.sub_job_id] > me.sub_job_level) then --sj can't cast
		return false
	elseif skill_en == 'Blue Magic' and not me.blu_spells:find(spell.en) then
		spell.reason = 'Unset'
		if not for_module then ignored_spells[skill_en]:insert(spell) end -- process, but don't insert, while generating modules
		return false
	elseif not for_module and (resistable_spells[skill_en] or T{}):contains(spell.en) then --resistable and bad for skillup
		spell.reason = 'Resistable/unstackable, poor for skillup'
		ignored_spells[skill_en]:insert(spell)
		return false
	elseif not for_module and spell.en:wmatch('Teleport-*|Raise*|Warp*|Tractor*|Retrace|Escape|Geo-*|Sacrifice|Odin|Alexander|Recall-*|Full Cure') then --not for skillup
		spell.reason = 'Not for skillup'
		ignored_spells[skill_en]:insert(spell)
		return false
	end
	return true
end



-------------------------------------------------------------------------------------------------------------------
-- Get the mj-relevant spells known by the player and weight them
-------------------------------------------------------------------------------------------------------------------
function get_valid_spells()
	-- RE-INITIALIZE VALID SPELL TABLE
	valid_spells = T{}
	for skill_en, data in pairs(main_skills) do
		valid_spells[skill_en] = T{}
		ignored_spells[skill_en] = T{}
		for _, data in pairs(indirect_skills[skill_en] or {}) do --these rely on its spells
			valid_spells[data.en] = T{}
		end
	end

	-- PROCESS EACH SPELL
	known_spells = windower.ffxi.get_spells() --known spells, all jobs
	for id, spell in pairs(res.spells) do
		local skill_en = res.skills[spell.skill].en
		if main_skills[skill_en] and is_valid(spell, skill_en) then
			valid_spells[skill_en][spell.id] = spell
			for _, data in pairs(indirect_skills[skill_en] or {}) do --these rely on its spells
				valid_spells[data.en][spell.id] = spell
			end
		end
	end
	
	-- PREPARE MAX MEASUREMENTS FOR WEIGHTING
	local meta = T{max_mp_cost = T{}, max_cast_time = T{}} -- metadata on maxes per skill
	for skill_en, spells in pairs(valid_spells) do
		meta.max_mp_cost[skill_en], meta.max_cast_time[skill_en] = 0, 0
		for id, spell in pairs(spells) do
			meta.max_mp_cost[skill_en]   = math.max(meta.max_mp_cost[skill_en]   or 0, spell.mp_cost  )
			meta.max_cast_time[skill_en] = math.max(meta.max_cast_time[skill_en] or 0, spell.cast_time)
		end
	end
	
	-- BUILD SPELLS SORTED BY WEIGHT
	valid_spells_sorted = T{}
	for skill_en, spells in pairs(valid_spells) do
		valid_spells_sorted[skill_en] = T{}
		for id, spell in pairs(spells) do
			-- CALCULATE/ASSIGN WEIGHT AND PUSH EACH SPELL TO NEW TABLE
			local mp_cost_weight   = math.max(0, spell.mp_cost   / meta.max_mp_cost[skill_en]   * 0.5) --50% weight
			local cast_time_weight = math.max(0, spell.cast_time / meta.max_cast_time[skill_en] * 0.5) --50% weight
			spell.weight = mp_cost_weight + cast_time_weight
			valid_spells_sorted[skill_en]:insert(spell)
		end
		-- SORT NEW TABLE BY WEIGHT (LOWEST IS BEST)
		table.sort(valid_spells_sorted[skill_en], function(a,b) return a.weight < b.weight end)
	end
end



-------------------------------------------------------------------------------------------------------------------
-- Get the magic skills that are native to the main job (it can only skill-up these skills)
-------------------------------------------------------------------------------------------------------------------
function get_main_skills()
	main_skills = T{}
	-- PROCESS ALL SPELLS (only these can be skilled up by said main job!)
	for id, spell in pairs(res.spells) do
		if spell.skill ~= 0 then --trusts
			local skill_en = res.skills[spell.skill].en
			-- INITIALIZE MAIN JOB SKILLS
			if main_skills[skill_en] == nil and spell.levels[me.main_job_id] and not ignore_main_spells:find(spell.en) then --main job can cast it
				main_skills[skill_en] = T{id=spell.skill, en=skill_en, casts=0}
				valid_spells[skill_en] = T{}
				-- INITIALIZE INDIRECT SKILLS ALSO (Ex: Wind and String are both tied to Singing)
				for _, indirect_skill in pairs(indirect_skills[skill_en] or {}) do
					main_skills[indirect_skill.en] = indirect_skill
					valid_spells[indirect_skill.en] = T{}
				end
			end
		end
	end
	me.no_magic_skills = main_skills:length() == 0
end



-------------------------------------------------------------------------------------------------------------------
-- Unpack the skill packet into level/capped data for main_skills. Initialize UI on first round.
-------------------------------------------------------------------------------------------------------------------
function process_skill_data(packet)
	logger(chat_colors.purple, '[SKILL DATA] Processing incoming skill level/cap data...', true)
	for skill, data in pairs(main_skills) do
		local level, capped = packet[skill .. ' Level'], packet[skill .. ' Capped']
		-- CAPTURE INITIAL LEVEL
		if data.level == nil then
			data.level_init, data.capped = level, capped
		else
			-- SKILL UP
			if level ~= data.level then
				ui.set_subtext(data.en, level)
			end
			-- SKILL CAP/UNCAP (uncap on levelup)
			if capped ~= data.capped then
				if capped then
					logger(chat_colors.green, '[SKILL CAP] Congratulations, "' .. skill .. '" skill has capped!')
					remove_skill_from_session(data.en, true)
				end
				ui.set_text_color(skill, capped and 'blue' or 'white')
			end
		end
		data.level, data.capped = level, capped
	end
		
	-- INITIALIZE UI (ON FIRST DATA RETRIEVAL)
	if not skill_data_retrieved then
		skill_data_retrieved = true
		initialize_ui('Initial skill retrieval')
	end
end



-------------------------------------------------------------------------------------------------------------------
-- Requests skill data from the server, with a timeout, with a cutscene failsafe
-- NOTE: During events the server queues your packet replies, so a spam of requests would get a spam of replies
-------------------------------------------------------------------------------------------------------------------
function skill_data_request_timeout(attempts)
	attempts = attempts or 0
	local freq = 10 --seconds
	local attempts_max = (60/freq)*1 --1 minute
	-- SKILL DATA RETRIEVED
	if skill_data_retrieved then
		logger(chat_colors.purple, '[SKILL DATA RECEIVED] Recieved the data on attempt ' .. attempts .. '/' .. attempts_max, true)
	
	-- SKILL DATA NEEDED
	elseif attempts <= attempts_max then
		-- CUTSCENE NOTIFICATION
		if event_pauses.Event and attempts == 0 then
			logger(chat_colors.yellow, '[INITIALIZATION DELAY] SmartSkillup will initialize after your cutscene/dialogue ends.')
		end
		
		attempts = attempts + 1
		windower.packets.inject_outgoing(0x061, 0:char():rep(8)) -- requests skill packet, packet processor runs initialize_ui() if skill_data_retrieved is false
		coroutine.close(threads.skill_data_request_timeout)
		threads.skill_data_request_timeout = skill_data_request_timeout:schedule(freq, attempts)
		logger(chat_colors.purple, '[SKILL REQUEST] Requesting skill data from server; attempt ' .. attempts .. '/' .. attempts_max, true)
	
	-- NOTIFY: OUT OF ATTEMPTS
	elseif not event_pauses.Event then
		logger(chat_colors.red, '[SKILL DATA ISSUE] Unable to retrieve skill data from server after ' .. attempts .. ' attempts.')
		logger(chat_colors.red, '[NOTE] Cutscenes queue packets and is the most likely cause; initialization should finish after cutscene.')
	end
end



-------------------------------------------------------------------------------------------------------------------
-- Increment relevant cast count for main_skills on each aftercast event
-------------------------------------------------------------------------------------------------------------------
function increment_casts(event)
	if event.res == nil then return end
	if not res.skills[event.res.skill] or not main_skills[res.skills[event.res.skill].en] then return end
	main_skills[res.skills[event.res.skill].en].casts = main_skills[res.skills[event.res.skill].en].casts + 1
end



-------------------------------------------------------------------------------------------------------------------
-- A function to handle processing requests to begin the loop and the situational actions required to do so correctly
-------------------------------------------------------------------------------------------------------------------
function begin_loop(source, notify)
	source = source or 'NEW LOOP'
	logger(chat_colors.purple, '[BEGIN LOOP'..larr..source:upper()..'] Beginning loop...', false,true)
	local verbiage = active and {'RESUME', 'resuming'} or {'START', 'starting'}
	
	-- RETURN: NO SKILLS TO SKILLUP
	if #skills_to_skillup == 0 then
		return logger(chat_colors.red, '[DENIED] No skills have been added to attempt to begin. (TIP: //sms addskill [searchterm])')
	elseif going then
		return logger(chat_colors.purple, '[DENIED] Loop is already going.', true)
	end
	
	-- ACTIVATE UI TEXT
	active = true
	ui.active(true)
	
	-- RETURN: NEED TO START GETTING UP
	if event_pauses.Resting and not me.getting_up then
		me.getting_up = true
		windower.send_command('input /heal')
		end_timeout_and_decision(source, chat_colors.purple, '[NEW LOOP] Ending any scheduled timeout and decision...', true)
		schedule_decision(3, source .. '+GET UP')
		return logger(chat_colors.green, '[' .. verbiage[1] .. '] Getting up and ' .. verbiage[2] ..' in 3 seconds...')
	
	-- RETURN: GET UP FASTER (just wait, lol)
	elseif event_pauses.Resting then
		return logger(chat_colors.green, '[START] Resuming skillup session...')
	
	-- RETURN: AWAITING EVENT PAUSES
	elseif event_pauses:length() > 0 then
		me.awaiting_event_pause_end = true -- required when player unpauses during an event pause
		return logger(chat_colors.green, '[START] Waiting on the following pause events to end: ' .. event_pauses:keyset():concat(', '))
	
	end
	
	-- RESET VARIOUS VARS
	paused = false
	ui.paused(false)
	loop.issues = 0
	auto_resting = false
		
	-- NOTIFY CLIENT IF NOTIFY TRUE
	logger(chat_colors.green, '[' .. verbiage[1] .. '] Skillup session ' .. verbiage[2] .. '...', not notify and true or nil)
	
	-- ENSURE SINGLE TIMEOUT, THEN START DECISION
	coroutine.close(threads.begin_loop)
	end_timeout_and_decision(source, chat_colors.purple, '[NEW LOOP] Ending any scheduled timeout and decision...', true)
	going = true
	make_decision(source)
end



-------------------------------------------------------------------------------------------------------------------
-- Process the char update packets
-------------------------------------------------------------------------------------------------------------------
function process_char_update(id, data)
	update_me_vitals(id, data)
	-- END OF RESTING SESSION
	if id == 0x0DF and active and me.status == 'Resting' and me.mpp == 100 and auto_resting then-- CREDIT: SMD111
		logger(chat_colors.purple, '[HEALING FINISHED] Sending the "//sms go" command to continue.', true)
		windower.send_command('sms go "Finished healing"')
	end
end



-------------------------------------------------------------------------------------------------------------------
-- A rhythmic player notice of upcoming healing session that can be prematurely terminated (10, 6, 3, 2, 1, 0 rhythm)
-------------------------------------------------------------------------------------------------------------------
function initialize_healing_notice(total_delay, reason, first)
	me.healing_countdown_running = true
	total_delay = total_delay or 9 -- total time till alert expires
	local next_tick = total_delay <= 3 and 1 or math.fmod(total_delay, 3) == 0 and 3 or math.fmod(total_delay, 3) + 3
	if total_delay > 0 then
		logger(chat_colors.yellow, '[RESTING SCHEDULED] Beginning a resting session in ' .. total_delay .. ' seconds...' .. (first and ' (Reason: ' .. reason .. ')' or ''))
		threads.healing_notice = initialize_healing_notice:schedule(next_tick, total_delay - next_tick, reason)
	else
		auto_resting = true
		me.healing_countdown_running = nil
		windower.send_command('input /heal')
	end
end

function terminate_healing_notice(reason)
	coroutine.close(threads.healing_notice)
	if me.healing_countdown_running then
		me.healing_countdown_running = nil
		logger(chat_colors.yellow, '[RESTING CANCELLED] Cancelled the scheduled healing session.' .. (reason and ' (Reason: ' .. reason .. ')' or ''))
	end
end



-------------------------------------------------------------------------------------------------------------------
-- The new and improved event pause system, allowing all event pauses to co-exist!
-- KEYS: healing, moving, npc, zoning, various-statuses
-------------------------------------------------------------------------------------------------------------------
event_pauses = T(setmetatable({}, {__index=function(t,k) return t[k] end,__newindex=function()end}))
event_pauses_metatable = setmetatable({}, {
	__newindex = function(t, k, v)
		-- GET START COUNT
		local start_count = event_pauses:count(true)

		-- RECORD EVENT (never write to self to ensure __newindex always fires)
		rawset(event_pauses, k, v)

		-- GET END COUNT
		local end_count = event_pauses:count(true)
		
		-- EVENT PAUSE STARTED
		if start_count == 0 and end_count > 0 then
			ui.event_paused(true) -- always color button
			local reason = 'PAUSE EVENT' .. larr .. k:upper()
			-- LOOP INACTIVE OR PLAYER PAUSED
			if not active or paused then
				logger(chat_colors.lpurple, '['.. reason .. '] Ignored, inactive or player-paused.', true)
			-- END ACTIVE LOOP
			else
				going = false
				coroutine.close(begin_loop)
				end_timeout_and_decision(reason, chat_colors.purple, '[' .. reason .. '] "' .. k .. '" started an event pause and ended the timeout and decisions.', true)
			end
		
		-- EVENT PAUSE ENDED
		elseif end_count == 0 and start_count > 0 then
			ui.event_paused(false) -- always color button
			local reason = 'UNPAUSE EVENT' .. larr .. k:upper()
			-- LOOP ALREADY GOING
			if going and not me.awaiting_event_pause_end then
				logger(chat_colors.lpurple, '[' .. reason .. '] Ignored, loop already going.', true)
			-- LOOP INACTIVE OR PLAYER PAUSED
			elseif not active or paused then
				logger(chat_colors.lpurple, '[' .. reason .. '] Ignored, inactive or player-paused.', true)
			-- AWAITING HEALING
			elseif me.healing_countdown_running then
				logger(chat_colors.lpurple, '[' .. reason .. '] Ignored, awaiting healing from notice.', true)
			-- LOOP REVIVAL
			else
				going = true --causes issues when clicking ON to get up and start
				me.awaiting_event_pause_end = nil -- reset
				schedule_decision(1, reason, chat_colors.purple, '[' .. reason .. '] The last event, "' .. k .. '", scheduled a decision in 1 sec...', true)
			end
		
		-- A NESTED EVENT STARTED OR ENDED
		else
			local mode = v and 'pause' or 'unpause'
			local events = event_pauses:keyset():concat(', ')
			logger(chat_colors.lpurple, '[' .. mode:upper() .. ' EVENT' .. larr .. k:upper() .. '] Ignored a nested "' .. k .. '" ' .. mode .. '. (pauses: ' .. events .. ')', false, true)
		end
	end
})

function pause_event(event)
	coroutine.close(threads['sched_' .. event .. '_unpause']) -- end event's delayed unpause, it'd be premature now
	event_pauses_metatable[event] = true
end

function unpause_event(event, delay)
	threads['sched_' .. event .. '_unpause'] = coroutine.schedule(function()
		event_pauses_metatable[event] = nil
	end, delay or 0)
end



-------------------------------------------------------------------------------------------------------------------
-- Specialized processing for statuses (event pauses and auto_resting)
-------------------------------------------------------------------------------------------------------------------
function process_status_events(newStatus, oldStatus, newStatusId, oldStatusId)
	-- STATUS PAUSE EVENTS -- Dead, Chocobo, Cutscene, Resting, etc
	if newStatusId > 1 then
		if newStatus == 'Resting' then terminate_healing_notice('Status change') end
		pause_event(newStatus)
	end
	if oldStatusId and oldStatusId > 1 then
		unpause_event(oldStatus, 1)
	end
end

function processing_resting_change(newStatus, oldStatus, newStatusId, oldStatusId)
	if not active or paused then return end
	if not S{oldStatus, newStatus}:contains('Resting') then return end
	
	-- STARTED RESTING
	if newStatus == 'Resting' then
		me.healing_countdown_running = nil
		if auto_resting or (not auto_resting and me.mpp < 70) then -- ignore rests where the player is apparently arbitrarily healing
			logger(chat_colors.yellow, '[RESTING] Skillup will resume automatically when MP is full.')
			auto_resting = true -- will get up when full
		end
	
	-- GOT UP FROM RESTING
	else
		auto_resting = false
		me.getting_up = true -- used to track get-up animation lock
		coroutine.schedule(function() me.getting_up = nil end, 1.5)
	end
end



-------------------------------------------------------------------------------------------------------------------
-- Specialized processing for buffs
-------------------------------------------------------------------------------------------------------------------
function process_buff_change(buff, gain)
	if not buff then return end
	buffactive[buff.en] = gain
	buffidactive[buff.id] = gain
	
	-- GEO REFRESH TRACKING
	if buff.geo and buff.geo.en == 'Geo-Refresh' then
		modules.georef.buffactive = gain
	end
	
	-- JA LOCKED
	if JA_lock_buffs:contains(buff.en) then
		me.JA_locked = JA_lock_buffs:intersection(buffactive):length() > 0
	-- TRACK CASTING-LOCKABLE BUFFS AS EVENT PAUSES
	elseif all_lock_buffs:contains(buff.en) or cast_lock_buffs:contains(buff.en) then
		local proper = (buff.en:gsub('^%l', string.upper)) -- 'silence' to 'Silence'
		if gain then
			pause_event(proper)
		else
			unpause_event(proper, 0.5)
		end
		if active and not paused then -- we don't usually say anything about event pauses, but this is an exception
			logger(chat_colors.yellow, '[NOTICE] An event pause has ' .. (gain and 'started' or 'ended') .. ' for "' .. proper .. '".')
		end
	elseif buff.en == 'Composure' then
		modules.compo.buffactive = gain
	elseif S{'Refresh','Haste'}:contains(buff.en) and modules.compo.available then
		evaluate_composure_active()
	end
end



-------------------------------------------------------------------------------------------------------------------
-- Get the modules relevant to the player and/or its main job
-------------------------------------------------------------------------------------------------------------------
function determine_modules()
	-- GET AVAILABLE MODULES
	local known_spells = windower.ffxi.get_spells()
	local ability_recasts = windower.ffxi.get_ability_recasts()
	local player = windower.ffxi.get_player()
	modules = modules_default:copy()
	
	-- MOOGLE MODULE
	if known_spells[modules.moogle.res.id] then
		modules.moogle.available = true -- res already populated
	end
	-- DYNAMIC SPELL MODULES (Refresh/Haste)
	for id, spell in pairs(res.spells) do
		local skill_en = res.skills[spell.skill].en
		if is_valid(spell, skill_en, true) then
			-- REFRESH MODULE, weighted by priority
			if spell.en == 'Refresh III' then
				modules.refresh:update({available = true, res = {res.spells:find(function(r) return r.en == 'Refresh III' end)}[2]})
			elseif spell.en == 'Refresh II' and modules.refresh.en ~= 'Refresh III' then
				modules.refresh:update({available = true, res = {res.spells:find(function(r) return r.en == 'Refresh II' end)}[2]})
			elseif spell.en == 'Refresh' and not modules.refresh.available then
				modules.refresh:update({available = true, res = {res.spells:find(function(r) return r.en == 'Refresh' end)}[2]})
			elseif spell.en == 'Battery Charge' then
				modules.refresh:update({available = true, res = {res.spells:find(function(r) return r.en == 'Battery Charge' end)}[2]})
			-- HASTE MODULE, weighted by priority
			elseif spell.en == 'Erratic Fluttter' then
				modules.haste:update  ({available = true, res = {res.spells:find(function(r) return r.en == 'Erratic Flutter' end)}[2]})
			elseif spell.en == 'Haste II' then
				modules.haste:update({available = true, res = {res.spells:find(function(r) return r.en == 'Haste II' end)}[2]})
			elseif spell.en == 'Haste' and not modules.haste.available then
				modules.haste:update({available = true, res = {res.spells:find(function(r) return r.en == 'Haste' end)}[2]})
			end
		end
	end
	-- CONVERT MODULE
	if (me.main_job == 'RDM' and me.main_job_level >= 40) or (me.sub_job == 'RDM' and me.sub_job_level >= 40) then
		modules.convert.available = true -- res already populated
		schedule_module_readiness(modules.convert, true)
	end
	-- COMPOSURE MODULE
	if me.main_job == 'RDM' and me.main_job_level >= 50 then --not available to lv50 sj
		modules.compo.available = true -- res already populated
		schedule_module_readiness(modules.compo, true)
	end
	-- GEO REFRESH MODULE
	if (me.main_job == 'GEO' and me.main_job_level > 34) or (me.sub_job == 'GEO' and me.sub_job_level > 34) and known_spells[modules.georef.res.id] then
		modules.georef.available = true -- res already populated
		modules.georef.buffactive = buffactive['Refresh (GEO)']
	end
	-- RADIAL ARCANA MODULE
	if me.main_job == 'GEO' and me.main_job_level >= 75 and player.merits.radial_arcana > 0 then
		modules.radial.available = true -- res already populated
		schedule_module_readiness(modules.radial, true)
	end
	-- SUBLIMATION MODULE
	if (me.main_job == 'SCH' and me.main_job_level >= 35) or (me.sub_job == 'SCH' and me.sub_job_level >= 35) then
		modules.sublim.available = true -- res already populated
		schedule_module_readiness(modules.sublim, true)
	end
end



-------------------------------------------------------------------------------------------------------------------
-- Specialized processing for the composure module's active state
-------------------------------------------------------------------------------------------------------------------
function evaluate_composure_active()
	modules.compo.active = (function()
		if (modules.refresh.active and not buffidactive[modules.refresh.res.status])
		or (modules.haste.active and not buffidactive[modules.haste.res.status]) then
			return true
		end
		return false
	end)()
end



-------------------------------------------------------------------------------------------------------------------
-- Checks readiness on addon load and schedules anticipated readiness as JA-related modules are used
-------------------------------------------------------------------------------------------------------------------
function schedule_module_readiness(mod, immediate)
	if not immediate then return schedule_module_readiness:schedule(2, mod, true) end
	
	local recast = windower.ffxi.get_ability_recasts()[mod.res.recast_id]
	if recast == 0 then
		mod.ready = true
	else
		mod.ready = false
		schedule_module_readiness:schedule(recast+0.1, true)
	end
end



-------------------------------------------------------------------------------------------------------------------
-- Builds the user's two best cures known and castable by their main job, for recovering from convert
-------------------------------------------------------------------------------------------------------------------
function update_best_cures()
	known_spells = windower.ffxi.get_spells()
	me.best_cures = T{}
	for i = 6, 1, -1 do
		local cure = {res.spells:find(function(r) return r.en == 'Cure' .. numerals[i] end)}[2]
		if is_valid(cure, res.skills[cure.skill].en, true) then
			-- BEST CURE
			if me.best_cures[1] == nil then
				me.best_cures[1] = T{en=cure.en, mp_cost=cure.mp_cost, prefix=cure.prefix}
				me.best_cure_index = 1
			
			-- SECOND BEST CURE
			else
				me.best_cures[2] = T{en=cure.en, mp_cost=cure.mp_cost, prefix=cure.prefix}
				break
			end
		end
	end
end