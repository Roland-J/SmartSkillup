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

resistable_spells = T{ --avoid these since skillups cannot occur on resists nor on attempts to stack these effects
	['Enfeebling Magic'] = T{'Addle', 'Addle II', 'Bind', 'Blind', 'Blind II', 'Break', 'Breakga', 'Dispel',
		'Distract', 'Distract II', 'Distract III', 'Frazzle', 'Frazzle II', 'Frazzle III', 'Gravity', 'Gravity II',
		'Paralyze', 'Paralyze II', 'Poison', 'Poison II', 'Poisonga', 'Sleep', 'Sleep II', 'Sleepga', 'Sleepga II',
		'Silence', 'Slow', 'Slow II'},
	['Elemental Magic'] = T{'Burn', 'Choke', 'Drown', 'Frost', 'Rasp', 'Shock'},
	['Singing'] = T{'Foe Requiem', 'Foe Requiem II', 'Foe Requiem III', 'Foe Requiem IV', 'Foe Requiem V',
		'Foe Requiem VI', 'Foe Requiem VII', 'Fire Threnody', 'Ice Threnody', 'Wind Threnody', 'Earth Threnody',
		'Ltng. Threnody', 'Water Threnody', 'Light Threnody', 'Dark Threnody', 'Fire Threnody II', 'Ice Threnody II',
		'Wind Threnody II', 'Earth Threnody II', 'Ltng. Threnody II', 'Water Threnody II', 'Light Threnody II',
		'Dark Threnody II', 'Battlefield Elegy', 'Carnage Elegy', 'Foe Lullaby', 'Horde Lullaby'},
	--[[ ['Blue Magic'] = T{},]] -- could someone provide this, please?
}
resistable_spells['Wind Instrument'] = resistable_spells.Singing -- assign this also to the indirect skill
resistable_spells['Stringed Instrument'] = resistable_spells.Singing -- assign this also to the indirect skill
untargetable_trusts = T{'Brygid','Star Sibyl','Kuyin Hathdenna','Kupofried','Moogle','Sakura'} -- used to avoid attempting to skillup on these trusts
ignore_main_spells = T{ -- skills artificially available to main jobs who cannot necessarily skill up their related skill
	'Dispelga', -- granted via the 'Daybreak' club
	'Impact',   -- granted via the 'Twilight Cloak' or 'Crepuscular Cloak'
}
indirect_skills = T{ -- used to give spells to skills that inherit spells (Ex: Wind and String inherit from Singing spells)
	['Singing'] = T{
		T{id = 42, en = 'Wind Instrument', casts = 0, parent = 'Singing'},
		T{id = 41, en = 'Stringed Instrument', casts = 0, parent = 'Singing'},
	},
	['Geomancy'] = T{
		T{id = 45, en = 'Handbell', casts = 0, parent = 'Singing'},
	},
}
-- Add Flags to Geo Buffs
for id, indi in pairs(res.spells:filter(function(s) return s.en:startswith('Indi-') end)) do
	res.buffs[indi.status].en = res.buffs[indi.status].en .. ' (GEO)'
	res.buffs[indi.status].indi = indi
	res.buffs[indi.status].geo = {res.spells:find(function(s) return s.en == indi.en:gsub('Indi%-', 'Geo%-') end)}[2]
end
chat_colors = T{ -- used by logger for add_to_chat's 1st argument
	yellow = 36,
	red = 123,
	grey = 207,
	green = 215,
	purple = 200,
	lpurple = 8,
}
modules_order = T{ -- used to build the modules in a strict order
	'mp_limit',
	't_target',
	'food',
	'moogle',
	'convert',
	'refresh',
	'haste',
	'georef',
	'sublim',
}
numerals = T{'',' II',' III',' IV',' V',' VI'}
bags_ordered = T{
	T({res.bags:find(function(bag) return bag.en == 'Inventory' end)}[2]),
	T({res.bags:find(function(bag) return bag.en == 'Satchel'   end)}[2]),
	T({res.bags:find(function(bag) return bag.en == 'Sack'      end)}[2]),
	T({res.bags:find(function(bag) return bag.en == 'Case'      end)}[2]),
}
skillup_foods = T{ -- magic skillup foods, indexed by potency for ipairs usage
    T({res.items:find(function(i) return i.en == 'B.E.W. Pitaru'  end)}[2]), -- 80%
    T({res.items:find(function(i) return i.en == 'Seafood Pitaru' end)}[2]), -- 60%
    T({res.items:find(function(i) return i.en == 'Poultry Pitaru' end)}[2]), -- 40%
    T({res.items:find(function(i) return i.en == 'Stuffed Pitaru' end)}[2]), -- 20%
}
food_locations_template = T{ -- used in mapping out best/available food
	T{T{}--[[inv]],T{}--[[satchel]],T{}--[[sack]],T{}--[[case]]}, -- B.E.W. Pitaru
	T{T{}--[[inv]],T{}--[[satchel]],T{}--[[sack]],T{}--[[case]]}, -- Seafood Pitaru
	T{T{}--[[inv]],T{}--[[satchel]],T{}--[[sack]],T{}--[[case]]}, -- Poultry Pitaru
	T{T{}--[[inv]],T{}--[[satchel]],T{}--[[sack]],T{}--[[case]]}, -- Stuffed Pitaru
}
cities = S{ -- used to detect if the player can currently summon trusts
	"Ru'Lude Gardens",     "Upper Jeuno",          "Lower Jeuno",         "Port Jeuno",      "Port Windurst",
	"Windurst Waters",     "Windurst Woods",       "Windurst Walls",      "Heavens Tower",   "Port San d'Oria",
	"Northern San d'Oria", "Southern San d'Oria",  "Port Bastok",         "Bastok Markets",  "Bastok Mines",
	"Metalworks",          "Aht Urhgan Whitegate", "Tavanazian Safehold", "Nashmau",         "Selbina",
	"Mhaura",              "Norg",                 "Eastern Adoulin",     "Western Adoulin", "Kazham",
}
JA_lock_buffs = S{'amnesia', 'omerta'}
all_lock_buffs = S{'sleep','stun','charm','terror','petrification'}
cast_lock_buffs = S{'silence','mute','omerta'}
larr = chars.larr