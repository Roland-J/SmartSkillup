--[[ CREDIT: This document is originally authored by Windower & included in Windower v4.
	It's current form has only been modified, not authored, by RolandJ. ]]
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

--[[
	A library to facilitate image primitive creation and manipulation.
]]

local table = require('table')
local math = require('math')

local images = {}
local meta = {}

saved_images = {}
local drag
local click
local hover

local events = {
	reload = true,
	left_click = true,
	double_left_click = true,
	right_click = true,
	double_right_click = true,
	middle_click = true,
	scroll_click = true,
	scroll_up = true,
	scroll_down = true,
	hover = true,
	left_drag = true,
	right_drag = true,
	scroll_drag = true,
}

local event_map = {
	drag = 'left_drag',
	click = 'left_click',
	double_click = 'double_left_click',
}

_libs = _libs or {}
_libs.images = images

_meta = _meta or {}
_meta.Image = _meta.Image or {}
_meta.Image.__class = 'Image'
_meta.Image.__index = images

local set_value = function(t, key, value)
	local m = meta[t]
	m.values[key] = value
	m.images[key] = value ~= nil and (m.formats[key] and m.formats[key]:format(value) or tostring(value)) or m.defaults[key]
end

_meta.Image.__newindex = function(t, k, v)
	set_value(t, k, v)
	t:update()
end

--[[
	Local variables
]]

local default_settings = {}
default_settings.pos = {}
default_settings.pos.x = 0
default_settings.pos.y = 0
default_settings.visible = true
default_settings.color = {}
default_settings.color.alpha = 255
default_settings.color.red = 255
default_settings.color.green = 255
default_settings.color.blue = 255
default_settings.size = {}
default_settings.size.width = 0
default_settings.size.height = 0
default_settings.texture = {}
default_settings.texture.path = ''
default_settings.texture.fit = true
default_settings.repeatable = {}
default_settings.repeatable.x = 1
default_settings.repeatable.y = 1
default_settings.left_draggable = true -- rename (legacy aliases added below)
default_settings.right_draggable = false -- new
default_settings.scroll_draggable = false -- new
default_settings.drag_tolerance = 0 --new

math.randomseed(os.clock())

local amend
amend = function(settings, defaults)
	for key, val in pairs(defaults) do
		if type(val) == 'table' then
			settings[key] = amend(settings[key] or {}, val)
		elseif settings[key] == nil then
			settings[key] = val
		end
	end

	return settings
end

local call_events = function(t, event, ...)
	if not meta[t].events[event] then
		return
	end

	-- Trigger registered post-reload events
	for _, event in ipairs(meta[t].events[event]) do
		event(t, meta[t].root_settings, ...)
	end
end

local apply_settings = function(_, t, settings)
	settings = settings or meta[t].settings
	images.pos(t, settings.pos.x, settings.pos.y)
	images.visible(t, meta[t].status.visible)
	images.alpha(t, settings.color.alpha)
	images.color(t, settings.color.red, settings.color.green, settings.color.blue)
	images.size(t, settings.size.width, settings.size.height)
	images.fit(t, settings.texture.fit)
	images.path(t, settings.texture.path)
	images.repeat_xy(t, settings.repeatable.x, settings.repeatable.y)
	images.left_draggable(t, settings.left_draggable)
	images.right_draggable(t, settings.right_draggable)
	images.scroll_draggable(t, settings.scroll_draggable)

	call_events(t, 'reload')
end

function images.new(str, settings, root_settings)
	if type(str) ~= 'string' then
		str, settings, root_settings = '', str, settings
	end
	
	-- Capture legacy draggable alias for settings
	if type(settings) == 'table' then settings.left_draggable = settings.draggable end
	if type(root_settings) == 'table' then root_settings.left_draggable = root_settings.draggable end

	-- Sets the settings table to the provided settings, if not separately provided and the settings are a valid settings table
	if not _libs.config then
		root_settings = nil
	else
		root_settings =
			root_settings and class(root_settings) == 'settings' and
				root_settings
			or settings and class(settings) == 'settings' and
				settings
			or
				nil
	end

	t = {}
	local m = {}
	meta[t] = m
	m.name = (_addon and _addon.name or 'image') .. '_gensym_' .. tostring(t):sub(8) .. '_%.8x':format(16^8 * math.random()):sub(3)
	m.settings = settings or {}
	m.status = m.status or {visible = false, image = {}}
	m.root_settings = root_settings
	m.base_str = str

	m.events = {}

	m.keys = {}
	m.values = {}
	m.imageorder = {}
	m.defaults = {}
	m.formats = {}
	m.images = {}

	windower.prim.create(m.name)

	amend(m.settings, default_settings)
	if m.root_settings then
		config.save(m.root_settings)
	end

	if _libs.config and m.root_settings and settings then
		_libs.config.register(m.root_settings, apply_settings, t, settings)
	else
		apply_settings(_, t, settings)
	end

	-- Cache for deletion
	table.insert(saved_images, 1, t)

	return setmetatable(t, _meta.Image)
end

function images.update(t, attr)
	attr = attr or {}
	local m = meta[t]

	-- Add possibly new keys
	for key, value in pairs(attr) do
		m.keys[key] = true
	end

	-- Update all image segments
	for key in pairs(m.keys) do
		set_value(t, key, attr[key] == nil and m.values[key] or attr[key])
	end
end

function images.clear(t)
	local m = meta[t]
	m.keys = {}
	m.values = {}
	m.imageorder = {}
	m.images = {}
	m.defaults = {}
	m.formats = {}
end

-- Makes the primitive visible
function images.show(t)
	windower.prim.set_visibility(meta[t].name, true)
	meta[t].status.visible = true
end

-- Makes the primitive invisible
function images.hide(t)
	windower.prim.set_visibility(meta[t].name, false)
	meta[t].status.visible = false
end

-- Returns whether or not the image object is visible
function images.visible(t, visible)
	local m = meta[t]
	if visible == nil then
		return m.status.visible
	end

	windower.prim.set_visibility(m.name, visible)
	m.status.visible = visible
end

--[[
	The following methods all either set the respective values or return them, if no arguments to set them are provided.
]]

function images.pos(t, x, y)
	local m = meta[t]
	if x == nil then
		return m.settings.pos.x, m.settings.pos.y
	end

	windower.prim.set_position(m.name, x, y)
	m.settings.pos.x = x
	m.settings.pos.y = y
end

function images.pos_x(t, x)
	if x == nil then
		return meta[t].settings.pos.x
	end

	t:pos(x, meta[t].settings.pos.y)
end

function images.pos_y(t, y)
	if y == nil then
		return meta[t].settings.pos.y
	end

	t:pos(meta[t].settings.pos.x, y)
end

function images.size(t, width, height)
	local m = meta[t]
	if width == nil then
		return m.settings.size.width, m.settings.size.height
	end

	windower.prim.set_size(m.name, width, height)
	m.settings.size.width = width
	m.settings.size.height = height
end

function images.width(t, width)
	if width == nil then
		return meta[t].settings.size.width
	end

	t:size(width, meta[t].settings.size.height)
end

function images.height(t, height)
	if height == nil then
		return meta[t].settings.size.height
	end

	t:size(meta[t].settings.size.width, height)
end

function images.path(t, path)
	if path == nil then
		return meta[t].settings.texture.path
	end

	windower.prim.set_texture(meta[t].name, path)
	meta[t].settings.texture.path = path
end

function images.fit(t, fit)
	if fit == nil then
		return meta[t].settings.texture.fit
	end

	windower.prim.set_fit_to_texture(meta[t].name, fit)
	meta[t].settings.texture.fit = fit
end

function images.repeat_xy(t, x, y)
	local m = meta[t]
	if x == nil then
		return m.settings.repeatable.x, m.settings.repeatable.y
	end

	windower.prim.set_repeat(m.name, x, y)
	m.settings.repeatable.x = x
	m.settings.repeatable.y = y
end

function images.left_draggable(t, left_draggable)
	if left_draggable == nil then
		return meta[t].settings.left_draggable
	end

	meta[t].settings.left_draggable = left_draggable
end

images.draggable = images.left_draggable

function images.right_draggable(t, right_draggable) -- new for right-drag support
	if right_draggable == nil then
		return meta[t].settings.right_draggable
	end

	meta[t].settings.right_draggable = right_draggable
end

function images.scroll_draggable(t, scroll_draggable) -- new for right-drag support
	if scroll_draggable == nil then
		return meta[t].settings.scroll_draggable
	end

	meta[t].settings.scroll_draggable = scroll_draggable
end

function images.drag_tolerance(t, tolerance) --new: number of pixels to move mouse before dragging
	if tolerance == nil then
		return meta[t].settings.drag_tolerance
	end

	meta[t].settings.drag_tolerance = tolerance
end

function images.color(t, red, green, blue)
	local m = meta[t]
	if red == nil then
		return m.settings.color.red, m.settings.color.green, m.settings.color.blue
	end

	windower.prim.set_color(m.name, m.settings.color.alpha, red, green, blue)
	m.settings.color.red = red
	m.settings.color.green = green
	m.settings.color.blue = blue
end

function images.alpha(t, alpha)
	local m = meta[t]
	if alpha == nil then
		return m.settings.color.alpha
	end

	windower.prim.set_color(m.name, alpha, m.settings.color.red, m.settings.color.green, m.settings.color.blue)
	m.settings.color.alpha = alpha
end

-- Sets/returns image transparency. Based on percentage values, with 1 being fully transparent, while 0 is fully opaque.
function images.transparency(t, alpha)
	local m = meta[t]
	if alpha == nil then
		return 1 - m.settings.color.alpha/255
	end

	alpha = math.floor(255*(1-alpha))
	windower.prim.set_color(m.name, alpha, m.settings.color.red, m.settings.color.green, m.settings.color.blue)
	m.settings.color.alpha = alpha
end

-- Returns true if the coordinates are currently over the image object
function images.hover(t, x, y)
	if not t:visible() then
		return false
	end

	local start_pos_x, start_pos_y = t:pos()
	local end_pos_x, end_pos_y = t:get_extents()

	return (start_pos_x <= x and x <= end_pos_x
		or start_pos_x >= x and x >= end_pos_x)
	and (start_pos_y <= y and y <= end_pos_y
		or start_pos_y >= y and y >= end_pos_y)
end

function images.destroy(t)
	for i, t_needle in ipairs(saved_images) do
		if t == t_needle then
			table.remove(saved_images, i)
			break
		end
	end
	windower.prim.delete(meta[t].name)
	meta[t] = nil
end

function images.get_extents(t)
	local m = meta[t]
	
	local ext_x = m.settings.pos.x + m.settings.size.width
	local ext_y = m.settings.pos.y + m.settings.size.height

	return ext_x, ext_y
end

-- Handle drag and drop
windower.register_event('mouse', function(type, x, y, delta, blocked)
	if blocked then return end

	if type == 0 then
		-- Mouse unhover (new)
		if hover then
			hover = meta[hover.t] and hover or nil --reset hover on UI rebuild
			if meta[(hover or {}).t] and not hover.t:hover(x, y)  then
				call_events(hover.t, 'hover', false, click ~= nil)
				hover = nil
			end
		-- Mouse hover (new)
		else
			for _, t in ipairs(saved_images) do
				if t:hover(x, y) and ((meta[t] or {}).events or {}).hover then
					hover = {t = t}
					return call_events(t, 'hover', true, click ~= nil)
				end
			end
		end
		
		-- Mouse drag (added left/right drag, self-events, and new event args)
		if drag and meta[drag.t] then --not destroyed
			if not drag.active then
				local tol = meta[drag.t].settings.drag_tolerance
				if tol == 0 or (math.abs(x - drag.click.x) + math.abs(y - drag.click.y)) / 2 > tol then
					local pos_x, pos_y = drag.t:pos() --t's location on screen
					local internal = {x = drag.click.x - pos_x, y = drag.click.y - pos_y} --mouse's location in t
					drag:update({active = true, x = x, y = y, internal = internal})
				end
			end
			if drag.active then
				drag.t:pos(x - drag.internal.x, y - drag.internal.y)
				call_events(drag.t, drag.mode .. '_drag', {mouse = {x = x, y = y}, click = drag.click}) -- a simple delta would desync if the initial delta exceeds the tolerance
				drag.x, drag.y = x, y
			end
		end

	-- Mouse left/right/scroll click (added right click support and self-events)
	elseif type == 1 or type == 4 or type == 7 then
		if click or drag then return true end --ignore embedded clicks (ex: ldown > *rdown* > rup > lup)
		local mode = ({[1]='left', [4]='right', [7]='scroll'})[type]
		for _, t in ipairs(saved_images) do
			if t:hover(x, y) and meta[t] then
				if click and drag then return true end --process no further once both have occurred
				if not click and (meta[t].events or {})[mode .. '_click'] then
					click = {t = t, x = x, y = y, mode = mode}
					call_events(t, mode .. '_click', {release = false, x = x, y = y})
				end
				if not drag and meta[t].settings[mode .. '_draggable'] then
					drag = T{t = t, click = {x = x, y = y}, mode = mode}
				end
			end
		end
		return click or drag and true

	-- Mouse left/right/scroll release (added right-release support and self-events)
	elseif type == 2 or type == 5 or type == 8 then
		local mode = ({[2]='left', [5]='right', [8]='scroll'})[type]
		if (click and click.mode ~= mode) or (drag and drag.mode ~= mode) then return true end -- ignore embedded releases
		if click or drag then
			if click and meta[click.t] then
				call_events(click.t, mode .. '_click', {release = true, x = x, y = y, dragged = (drag or {}).active})
			end
			if drag and drag.active then
				if (meta[drag.t] or {}).root_settings then
					config.save(meta[drag.t].root_settings)
				end
				call_events(drag.t, mode .. '_drag', {release = true})
			end
			if hover and meta[hover.t] and hover.t:hover(x, y) then
				call_events(hover.t, 'hover', true) -- re-initialize hover, it won't do this itself
			end
			click = nil
			drag = nil
			return true
		end
	
	-- Mouse scroll (brand new)
	elseif type == 10 then
		local mode = delta > 0 and 'up' or 'down' --variable delta
		for _, t in ipairs(saved_images) do
			if t:hover(x, y) and ((meta[t] or {}).events or {})['scroll_' .. mode] then
				call_events(t, 'scroll_' .. mode)
				return true -- stop at top-most element
			end
		end
	end

	return false
end)

-- Can define functions to execute every time the settings are reloaded
function images.register_event(t, key, fn)
	if not events[key] then
		error('Event %s not available for text objects.':format(key))
		return
	end

	local m = meta[t]
	key = event_map[key] or key
	m.events[key] = m.events[key] or {}
	m.events[key][#m.events[key] + 1] = fn
	return #m.events[key]
end

function images.unregister_event(t, key, fn)
	if not (events[key] and meta[t].events[key]) then
		return
	end

	if type(fn) == 'number' then
		table.remove(meta[t].events[key], fn)
	else
		for index, event in ipairs(meta[t].events[key]) do
			if event == fn then
				table.remove(meta[t].events[key], index)
				return
			end
		end
	end
end

return images

--[[
Copyright © 2015, Windower
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

	* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
	* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
	* Neither the name of Windower nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL Windower BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]