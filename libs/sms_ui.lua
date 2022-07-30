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
DISCLAIMED. IN NO EVENT SHALL <your name> BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.]]

local images = require('libs/sms_images')
local texts = require('libs/sms_texts')
require('tables')



-------------------------------------------------------------------------------------------------------------------
-- Various local variables used throughout the UI
-------------------------------------------------------------------------------------------------------------------

local drag_positions -- cache of positions while dragging. (drag moves need original pos intact)
local path = windower.addon_path .. 'data/' -- where the button images are located (ui.set_path(str))
local header_text -- an optional header. (set using ui.set_header_text(str))
local main_job -- an optional subheader (set using ui.set_main_job(str))
local colors = {
	white  = function() return 255, 255, 255 end,
	grey   = function() return  96,  96,  96 end,
	blue   = function() return  51, 153, 255 end,
	yellow = function() return 250, 250, 100 end,
	orange = function() return 255, 153,  51 end,
}


-------------------------------------------------------------------------------------------------------------------
-- Set the button size settings using the user's UI scalar (CREDIT: Joshuateverday: https://github.com/SirEdeonX/FFXIAddons/issues/6)
-------------------------------------------------------------------------------------------------------------------

local windower_settings = windower.get_windower_settings()
local ui_scalar = ((windower_settings.ui_x_res * 1.0) / (windower_settings.x_res * 1.0)) --TODO: user customizable
local scalars = T{
	images = {
		width     = 209 * ui_scalar,
		height    = 23  * ui_scalar,
		sidecar_w = 70  * ui_scalar,
		sidecar_h = 17  * ui_scalar,
	},
	texts = {
		size         = 13 * ui_scalar,
		stroke_width =  1 * ui_scalar,
		padding      =  1 * ui_scalar,
	},
	offsets = {
		texts     = {x =   6 * ui_scalar, y =   0},
		subtexts  = {x = 167 * ui_scalar, y =   0},
		header    = {x =   2 * ui_scalar, y = -13 * ui_scalar},
		on        = {x =  87 * ui_scalar, y = -11 * ui_scalar},
		slash     = {x = 101 * ui_scalar, y = -11 * ui_scalar},
		off       = {x = 106 * ui_scalar, y = -11 * ui_scalar},
		pause     = {x = 131 * ui_scalar, y = -11 * ui_scalar},
		paused    = {x = 129 * ui_scalar, y = -11 * ui_scalar},
		help      = {x = 172 * ui_scalar, y = -11 * ui_scalar},
		mj_hdr    = {x =  90 * ui_scalar, y =  -3 * ui_scalar},
		mj_label  = {x = 173 * ui_scalar, y =  -3 * ui_scalar},
		shutdown  = {x =   2 * ui_scalar, y =  -3 * ui_scalar},
		sidecar   = {x = 210 * ui_scalar, y =   0},
		sc_texts  = {x =   6 * ui_scalar, y =   0},
		modules   = {x = 213 * ui_scalar, y = -11 * ui_scalar},
		limit_hdr = {x =   3 * ui_scalar, y =  -3 * ui_scalar},
		limit     = {x =  46 * ui_scalar, y =  -3 * ui_scalar},
		--TODO: MP LIMIT (∞ default)
	},
}
local user_scalars = T{} -- updated by config



-------------------------------------------------------------------------------------------------------------------
-- The UI object, contains metadata and functions for modifying the UI
-------------------------------------------------------------------------------------------------------------------

local ui = T{
	meta = T{} -- The master record of UI objects, used for tracking active state, lookups, and caching for deletion
}



-------------------------------------------------------------------------------------------------------------------
-- functions that update various flags for the UI (path, header, main job)
-------------------------------------------------------------------------------------------------------------------

function ui.set_path(str)
	if str == nil then return end
	path = str
end

function ui.set_header_text(str)
	if str == nil then return end
	header_text = str
end

function ui.set_main_job(str)
	if str == nil then return end
	main_job = str
end


-------------------------------------------------------------------------------------------------------------------
-- A function that sets the UI's main button config (if ommitted, UI cannot be built)
-------------------------------------------------------------------------------------------------------------------

--[[ SAMPLE: button_config = {Label = { active='input //cmd1', command='input //cmd'}, subtext='151', color='blue'}]]
function ui.set_button_config(button_config, sidecar_config) 
	if button_config == nil or type(button_config) ~= 'table' then return end
	--print('[SET_BUTTON_CONFIG] Setting button config...')
	ui.button_config = button_config
	if type(sidecar_config) == 'table' then
		ui.sidecar_config = sidecar_config
	end
	
	-- Reset meta (destroy elements first, if applicable)
	if #ui.meta > 0 then
		--print('[SET_BUTTON_CONFIG] Calling destroy_primitives...', #ui.meta)
		ui.destroy_primitives()
	end
	ui.meta = T{}
end



-------------------------------------------------------------------------------------------------------------------
-- Functions that set and tracks the state of the header's ON/OFF button on-click commands (if ommitted, no ON/OFF buttons are displayed)
-------------------------------------------------------------------------------------------------------------------

function ui.active(bool)
	if bool == nil then return end
	
	local _, on = ui.meta:find(function(m) return m.name == 'on' end)
	local _, off = ui.meta:find(function(m) return m.name == 'off' end)
	local _, paused = ui.meta:find(function(m) return m.name == 'paused' end)
	on.t:color(colors[bool and 'white' or 'grey']())
	on.active = bool
	off.t:color(colors[bool and 'grey' or 'white']())
	off.active = not bool
	if not bool and paused.active then --unpause on deactivation
		paused.t:color(colors.grey())
		paused.active = false
	end
end



-------------------------------------------------------------------------------------------------------------------
-- Functions that sets and tracks the state and color of the header's PAUSE/PAUSED
-------------------------------------------------------------------------------------------------------------------
function ui.paused(norm, event, issue)
	if norm == nil and event == nil and issue == nil then return end
	local _, paused = ui.meta:find(function(m) return m.name == 'paused' end)
	if paused == nil or paused.t == nil then return end
	
	paused.active = norm == nil and paused.active or norm
	paused.event = event == nil and paused.event or event
	paused.t:color(colors[paused.active and 'white' or (paused.event and 'orange' or 'grey')]())
end

function ui.event_paused(bool)
	if bool == nil then return end
	ui.paused(nil, bool)
end



-------------------------------------------------------------------------------------------------------------------
-- Functions sets the color of the AUTO-SHUTDOWN text
-------------------------------------------------------------------------------------------------------------------
function ui.auto_shutdown(bool)
	if bool == nil and event == nil then return end
	local _, shutdown = ui.meta:find(function(m) return m.name == 'shutdown' end)
	if shutdown == nil or shutdown.t == nil then return end

	shutdown.active = bool
	shutdown.t:color(colors[bool and 'orange' or 'grey']());
end



-------------------------------------------------------------------------------------------------------------------
-- A function that lets you toggle the active state on any button based on the button's label
-------------------------------------------------------------------------------------------------------------------

function ui.button_active(name, bool, sidecar)
	if name == nil then return end
	local _, m = ui.meta:find(function(m) return m.name == name and m.kind == 'image' end)
	if not m then return print('unable to get image ' .. name) end
	
	m.active = bool
	m.t:path(path .. 'Button002-' .. (bool and 'Orange' or 'Blue') .. '.png')
end


function ui.set_visible(name, bool)
	if name == nil or bool == nil then return end
	local _, m = ui.meta:find(function(m) return m.name == name end)
	if not m then return print('unable to get element ' .. name) end
	
	m.t:visible(bool)
	m.visible = bool
	m.hidden = not bool
end

-------------------------------------------------------------------------------------------------------------------
-- A functions that let you modify text (change skill level on skillup, change color on cap, etc)
-------------------------------------------------------------------------------------------------------------------

function ui.set_text(name, str)
	if name == nil or str == nil then return end
	local _, m = ui.meta:find(function(m) return m.name == name and m.kind == 'text' end)
	if not m then return print('unable to get text ' .. name) end
	
	m.t:text(tostring(str))
end

function ui.set_subtext(name, str)
	if name == nil or str == nil then return end
	local _, m = ui.meta:find(function(m) return m.name == name and m.kind == 'subtext' end)
	if not m then return print('unable to get subtext ' .. name) end
	
	m.t:text(tostring(str))
end

function ui.set_text_color(name, color)
	if name == nil or color == nil then return end
	local _, m_t = ui.meta:find(function(m) return m.name == name and m.kind == 'text' end)
	local _, m_st = ui.meta:find(function(m) return m.name == name and m.kind == 'subtext' end)
	if m_t == nil or m_st == nil then return print('unable to get text ' .. name) end
	
	m_t.t:color(colors[color]())
	m_st.t:color(colors[color]())
end


-------------------------------------------------------------------------------------------------------------------
-- A function that builds user scalars by multiplying the default scalars by the user scalar preference (which defaults to 1)
-------------------------------------------------------------------------------------------------------------------

function ui.update_user_scalars()
	user_scalars = T{}
	for k, v in pairs(scalars) do
		user_scalars[k] = {} --images, texts, offsets
		for k2, v2 in pairs(v) do
			if k ~= 'offsets' then
				user_scalars[k][k2] = v2 * settings.user_ui_scalar --width, height, size, stroke, padding
			else
				user_scalars[k][k2] = {}
				for k3, v3 in pairs(v2) do
					user_scalars[k][k2][k3] = v3 * settings.user_ui_scalar -- x, y
				end
			end
		end
	end
end

function ui.set_new_scalar(new_scalar)
	user_scalar = new_scalar
	ui.update_user_scalars()
	ui.rebuild_buttons()
end

function ui.store_table(t, name, kind, command)
	local _, m = ui.meta:find(function(m) return m.name == name and m.kind == kind end)
	local x, y = t:pos()
	-- CACHED META: REFERENCE NEW PRIMITIVE (Destroy>Rebuild)
	if m then
		m.t = t
		m.pos = {x = x, y = y}
	-- NEW ITEM: CREATE NEW META
	else
		ui.meta[#ui.meta+1] = T{
			name = name,
			kind = kind,
			index = #ui.meta+1,
			active = name == 'off' and true or false, -- on initialize OFF is the default
			command = command,
			t = t,
			pos = {x = x, y = y},
			hidden = name:startswith('limit') and true or nil,
		}
	end
end



-------------------------------------------------------------------------------------------------------------------
-- The function that creates and displays the UI (main, misc, and sidecar buttons)
-------------------------------------------------------------------------------------------------------------------

function ui.create_buttons()
	if not ui.button_config then return end
	local button_config = ui.button_config
	
	-- Update Settings (User Scalar, Top Left)
	ui.top_left = {x = settings.top_left.x, y = settings.top_left.y}
	ui.update_user_scalars()
	
	-- Sort incoming table by keys (for alphabetically ordered button labels)
	local button_labels = T{}
	for k in pairs(button_config) do button_labels:insert(k) end
	table.sort(button_labels)
	ui.button_labels = button_labels
	
	-- Detect/create placeholder
	ui.placeholder = #button_labels == 0
	if ui.placeholder then
		button_config = {['No Magic Skills'] = { color='white', command='sms nomagicskills', }}
		button_labels = {'No Magic Skills'}
	end
	
	-- Create a button per table key
	for i, name in ipairs(button_labels) do
		-- Declare button's ui.props
		local x, y = ui.top_left.x, ui.top_left.y + (1 + user_scalars.images.height) * (i - 1)
		local _, m = ui.meta:find(function(m) return m.name == name and m.kind == 'image' end)
		local sn = name:len() <= 16 and name or name:sub(1, 16) .. '...'
		
		-- Add Image
		local image = images.new()
		image:pos(x, y)
		image:path(path .. 'Button002-' .. (m and m.active and 'Orange' or 'Blue') .. '.png')
		image:fit(false) --this, if true, would make the button ignore the custom size
		image:size(user_scalars.images.width, user_scalars.images.height)
		image:drag_tolerance(15)
		image:clickable(true)
		image:register_event('left_click', ui.left_click_event)
		image:register_event('drag', ui.move_event)
		ui.store_table(image, name, 'image', button_config[name].command)
		image:show()
		
		-- Add Text
		local text = texts.new(sn)
		text:pos(x + user_scalars.offsets.texts.x, y)
		text:size(user_scalars.texts.size)
		text:color(colors[debugModes:find(true) and 'white' or button_config[name].color]())
		text:stroke_width(user_scalars.texts.stroke_width)
		text:pad(user_scalars.texts.padding)
		text:italic(true)
		text:bold(true)
		text:bg_visible(false)
		text:draggable(false)
		ui.store_table(text, name, 'text')
		text:show()
		
		-- Add Subtext
		local subtext = texts.new(button_config[name].subtext or '')
		subtext:pos(x + user_scalars.offsets.subtexts.x, y)
		subtext:size(user_scalars.texts.size)
		subtext:color(colors[debugModes:find(true) and 'white' or button_config[name].color]())
		subtext:stroke_width(user_scalars.texts.stroke_width)
		subtext:pad(user_scalars.texts.padding)
		--subtext:right_justified(true) --bugs out on subtext:pos(x, y)
		subtext:italic(true)
		subtext:bold(true)
		subtext:bg_visible(false)
		subtext:draggable(false)
		ui.store_table(subtext, name, 'subtext')
		subtext:show()
	end
	
	-- Get Cached Semi-Uniform Misc
	local _, on = ui.meta:find(function(m) return m.name == 'on' end)
	local _, pause = ui.meta:find(function(m) return m.name == 'paused' end)
	-- Add Semi-Uniform Misc
	local color_map = {
		header = 'yellow',
		on = on and on.active and 'white' or 'grey',
		slash = 'grey',
		off = on and on.active and 'grey' or 'white',
		paused = pause and (pause.active and 'white' or (pause.event and 'orange' or 'grey')) or 'grey',
	}
	for _, name in ipairs({'header', 'on', 'slash', 'off', 'paused', 'help'}) do
		-- Prepare Misc
		local italic = T{'on', 'slash', 'off'}:contains(name) and false or true
		local display_name = name == 'slash' and '/' or (name == 'header' and header_text or name:upper())
		
		-- Add Misc
		local misc = texts.new(display_name)
		misc:pos(ui.top_left.x + user_scalars.offsets[name].x, ui.top_left.y + user_scalars.offsets[name].y)
		misc:size(user_scalars.texts.size * (name == 'header' and 0.7 or 0.5))
		misc:color(colors[color_map[name] or 'white']())
		misc:stroke_width(user_scalars.texts.stroke_width*2)
		misc:pad(user_scalars.texts.padding)
		misc:bold(true)
		misc:italic(italic)
		misc:bg_visible(false)
		misc:drag_tolerance(15)
		misc:draggable(true)
		misc:clickable(true)
		misc:show()
		misc:register_event('left_click', ui.left_click_event)
		misc:register_event('drag', ui.move_event)
		ui.store_table(misc, name, 'text', not T{'header', 'slash'}:contains(name) and 'sms ' .. name)
	end
	
	-- Add Main Job Skills Subheader
	local pos = ui.meta[(#button_labels*3)-2].pos
	local mj_hdr = texts.new('MAIN JOB SKILLS:')
	mj_hdr:pos(pos.x + user_scalars.offsets.mj_hdr.x, pos.y + user_scalars.offsets.mj_hdr.y + user_scalars.images.height)
	mj_hdr:size(user_scalars.texts.size * 0.5)
	mj_hdr:color(colors.white())
	mj_hdr:stroke_width(user_scalars.texts.stroke_width*2)
	mj_hdr:pad(user_scalars.texts.padding)
	mj_hdr:bold(true)
	mj_hdr:italic(true)
	mj_hdr:bg_visible(false)
	mj_hdr:drag_tolerance(15)
	mj_hdr:draggable(true)
	mj_hdr:visible(true)
	mj_hdr:register_event('drag', ui.move_event)
	ui.store_table(mj_hdr, 'mj_hdr', 'text')
	
	-- Add MainJob Label
	local mj_label = texts.new(main_job)
	mj_label:pos(pos.x + user_scalars.offsets.mj_label.x, pos.y + user_scalars.offsets.mj_label.y + user_scalars.images.height)
	mj_label:size(user_scalars.texts.size * 0.5)
	mj_label:color(colors.orange())
	mj_label:stroke_width(user_scalars.texts.stroke_width*2)
	mj_label:pad(user_scalars.texts.padding)
	mj_label:bold(true)
	mj_label:italic(true)
	mj_label:bg_visible(false)
	mj_label:drag_tolerance(15)
	mj_label:draggable(true)
	mj_label:visible(true)
	mj_label:register_event('drag', ui.move_event)
	ui.store_table(mj_label, 'mj_label', 'text')
	
	-- Add Shutdown Label
	local _, sd = ui.meta:find(function(m) return m.name == 'shutdown' end) --get cache
	local shutdown = texts.new('AUTO-SHUTDOWN')
	shutdown:pos(pos.x + user_scalars.offsets.shutdown.x, pos.y + user_scalars.offsets.shutdown.y + user_scalars.images.height)
	shutdown:size(user_scalars.texts.size * 0.5)
	shutdown:color(colors[(sd and sd.active) and 'orange' or 'grey']())
	shutdown:stroke_width(user_scalars.texts.stroke_width*2)
	shutdown:pad(user_scalars.texts.padding)
	shutdown:bold(true)
	shutdown:italic(true)
	shutdown:bg_visible(false)
	shutdown:drag_tolerance(15)
	shutdown:draggable(true)
	shutdown:clickable(true)
	shutdown:visible(true)
	shutdown:register_event('left_click', ui.left_click_event)
	shutdown:register_event('drag', ui.move_event)
	ui.store_table(shutdown, 'shutdown', 'text', 'sms autoshutdown')
	
	
	-- Build Sidecar
	--if ui.placeholder or ui.sidecar_config == nil then return end
	if not ui.placeholder and ui.sidecar_config ~= nil then
		local sidecar_config = ui.sidecar_config
		
		-- Add Modules Header
		local modules = texts.new('MODULES')
		modules:pos(ui.top_left.x + user_scalars.offsets.modules.x, ui.top_left.y + user_scalars.offsets.modules.y)
		modules:size(user_scalars.texts.size * 0.5)
		modules:color(colors.white())
		modules:stroke_width(user_scalars.texts.stroke_width*2)
		modules:pad(user_scalars.texts.padding)
		modules:bold(true)
		modules:italic(true)
		modules:bg_visible(false)
		modules:clickable(true)
		modules:drag_tolerance(15)
		modules:draggable(true)
		modules:visible(true)
		modules:register_event('left_click', ui.left_click_event)
		modules:register_event('drag', ui.move_event)
		ui.store_table(modules, 'modules', 'text', 'sms modulehelp')
		
		for i, data in ipairs(sidecar_config) do
			local __, m = ui.meta:find(function(m) return m.name == data.name and m.kind == 'image' end)
			local x = ui.top_left.x + user_scalars.offsets.sidecar.x
			local y = ui.top_left.y + (1 + user_scalars.images.sidecar_h) * (i - 1)
			
			-- Add Sidecar Image
			local sc_image = images.new()
			sc_image:pos(x, y)
			sc_image:path(path .. 'Button002-' .. (m and m.active and 'Orange' or 'Blue') .. '.png')
			sc_image:fit(false) --this, if true, would make the button ignore the custom size
			sc_image:size(user_scalars.images.sidecar_w, user_scalars.images.sidecar_h)
			sc_image:clickable(true)
			sc_image:drag_tolerance(15)
			sc_image:show()
			--ui.store_table(sc_image, name, 'image', sidecar_config[name].command)
			ui.store_table(sc_image, data.name, 'image', sidecar_config[i].command)
			sc_image:register_event('drag', ui.move_event)
			sc_image:register_event('left_click', ui.left_click_event)
			
			-- Add Sidecar Text
			--local sc_text = texts.new(name)
			local sc_text = texts.new(data.name)
			sc_text:pos(x + user_scalars.offsets.sc_texts.x, y)
			sc_text:size(user_scalars.texts.size * 0.7)
			sc_text:color(colors.white())
			sc_text:stroke_width(user_scalars.texts.stroke_width)
			sc_text:pad(user_scalars.texts.padding)
			sc_text:italic(true)
			sc_text:bold(true)
			sc_text:bg_visible(false)
			sc_text:draggable(false)
			sc_text:show()
			--ui.store_table(sc_text, name, 'text')
			ui.store_table(sc_text, data.name, 'text')
		end
		
		local _, l = ui.meta:find(function(m) return m.name == 'limit' end)
		local pos = ui.meta[#ui.meta-1-(l and 2 or 0)].pos
			
		local limit_hdr = texts.new('MP LIMIT:')
		limit_hdr:pos(pos.x + user_scalars.offsets.limit_hdr.x, pos.y + user_scalars.offsets.limit_hdr.y + user_scalars.images.sidecar_h)
		limit_hdr:size(user_scalars.texts.size * 0.5)
		limit_hdr:color(colors.white())
		limit_hdr:stroke_width(user_scalars.texts.stroke_width*2)
		limit_hdr:pad(user_scalars.texts.padding)
		limit_hdr:bold(true)
		limit_hdr:italic(true)
		limit_hdr:bg_visible(false)
		limit_hdr:draggable(false) -- causes desync when dragged. why?
		limit_hdr:visible(l and l.visible == true)
		ui.store_table(limit_hdr, 'limit_hdr', 'text')
		
		local limit = texts.new(mp_limit and tostring(mp_limit) or '10')
		limit:pos(pos.x + user_scalars.offsets.limit.x, pos.y + user_scalars.offsets.limit.y + user_scalars.images.sidecar_h)
		limit:size(user_scalars.texts.size * 0.5)
		limit:color(colors.orange())
		limit:stroke_width(user_scalars.texts.stroke_width*2)
		limit:pad(user_scalars.texts.padding)
		limit:bold(true)
		limit:italic(true)
		limit:bg_visible(false)
		limit:draggable(true) -- causes desync when dragged. why?
		limit:clickable(true)
		limit:visible(l and l.visible == true)
		limit:register_event('left_click', ui.left_click_event)
		ui.store_table(limit, 'limit', 'text', 'sms mplimit toggle silent')
		
	end
end



-------------------------------------------------------------------------------------------------------------------
-- A function that can show/hide the UI
-------------------------------------------------------------------------------------------------------------------
function ui.show_primitives(bool)
	for _, m in ipairs(ui.meta) do
		if m.t and not m.hidden then
			m.t[bool and 'show' or 'hide'](m.t)
		end
	end
end



-------------------------------------------------------------------------------------------------------------------
-- A function that can destroy the UI. Useful if the UI needs to be rebuilt.
-------------------------------------------------------------------------------------------------------------------
function ui.destroy_primitives()
	for _, m in ipairs(ui.meta) do
		if m.t then
			m.t:destroy()
			m.t = nil
		end
	end
end

function ui.deactivate_all()
	for _, m in ipairs(ui.meta) do
		m.active = false
	end
end

-------------------------------------------------------------------------------------------------------------------
-- A function that can rebuild the UI.  Useful if the UI needs to be rebuilt or shown.
-------------------------------------------------------------------------------------------------------------------

function ui.rebuild_buttons()
	if ui.button_config == nil then return end
	
	if #ui.meta > 0 then
		--print('[REBUILD_BUTTONS] Destroying primitives and then rebuilding buttons...', #ui.meta)
		ui.destroy_primitives()
	else
		--print('[REBUILD_BUTTONS] Building initial buttons...')
	end
	ui.create_buttons(ui.button_config, ui.sidecar_config)
end

function ui.reset_meta()
	ui.meta = T{}
end

-------------------------------------------------------------------------------------------------------------------
-- The function that moves the buttons in tandem, by comparing the positions of the click, mouse, and image (/headache)
-------------------------------------------------------------------------------------------------------------------

function ui.move_event(t, root_settings, mouse, click)
	drag_positions = T{}
	for i, m in ipairs(ui.meta) do
		local internal = {x = click.x - m.pos.x, y = click.y - m.pos.y}
		local x, y = mouse.x - internal.x, mouse.y - internal.y
		m.t:pos(x, y)
		drag_positions[i] = {x = x, y = y} --movement accelerates if if we update m.t.positions
	end
end

function ui.left_click_event(t, root_settings, release, dragged)
	--print('[UI CLICK EVENT] release: ',release,' dragged: ',dragged)
	if release then
		if dragged then
			for i, m in ipairs(ui.meta) do
				m.pos = drag_positions[i]
			end
			drag_positions = nil
			settings.top_left = ui.meta[1].pos
			config.save(settings)
		else
			local i, m = ui.meta:find(function(m) return m.t == t end)
			if m.command then
				windower.send_command(m.command)
			end
		end
	end
end


return ui