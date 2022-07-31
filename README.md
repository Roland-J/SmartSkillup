## Instructions
1. Extract the "SmartSkillup-main" folder into your Windower/addons folder.
2. Type `//lua l smartskillup` ingame
3. Use the addon's ingame UI to add/remove skills and modules, then click ON to begin your skillup session. (See UI image below.)
4. To manually pause your skillup session, click the UI's PAUSED button.
5. For additional help, click the UI's HELP button or type `//sms help` ingame!

## Disclaimer
1. SmartSkillup is a bot, though without the potential to impede other players - _aside from a few edge cases_ - nor can it affect the gil economy.
2. Though it is rather harmless, please do not use SmartSkillup on servers where it is against the rules. If you do so anyways, it was not suggested here.

## Needs
 - Please create GitHub issues for any counter-intuitive or obnoxious behaviors you find in the addon! If it's a relatively easy fix and was not intended then I'd like to get them fixed. Thanks!

## Credit
 - NOTE: Most of SmartSkillup is brand new source code
 - SMD111: Anything credited to SMD111 is from https://github.com/smd111/Gearswap-Skillup/blob/master/skillup.lua
 - GEARSWAP: I copied their updateVitals code for char update packet parsing.
 - AUTO GEO: I copied their is_moving logic for the movement tracking.
 - RUBENATOR: Rubenator helped me the most by assisting with various questions as they came up during this development.
 - ARCHON: Archon helped me a lot with various details about the UI.
 - KAIN: For not giving me an Echad ring until I released this addon. (Helped me focus on my work, lol.)
 - MANY OTHERS: There were many other people and resources I referenced when developing this addon. Sorry for not listing you, please comment and I'll add you!


## WHY SmartSkillup?
 1. No more building your own spell lists. Ever.
     - This will automatically pull your known spells, that your main can skillup on, that your mj/sj can cast, and weight them for you.
     - This automatically excludes spells not for skillup: warp, raise, tractor, alexander, etc.
     - This automatically excludes resistable and not-self-stacking spells: poison, paralyze, foe requiem, etc.
     - This automatically excludes known but not set BLU spells.
     - As an author, I'm glad to save 2-10 minutes, per-user, for thousands of users.
 2. Features an exclusive "**Event Pause**" system that pauses casting for various actions such as running, cutscenes, zoning, and more!
 <img align="right" src="https://user-images.githubusercontent.com/107378114/182002464-60b57bb7-f134-4f5f-b1d4-4e07b96a8363.png">
 
 3. Includes a fully-featured UI to make using the addon as intuitive and user friendly as possible.
      - It shows you if there is currently an event pause
      - Can be dragged from anywhere
      - Can be hidden and even shrunk/enlarged
      - It remembers your preferences on each load!

 4. Now you can skill up combat skills with an addon.
     - However, SmartSkillup is not and will not be your claim bot. The furthest it will go is a `<bt>` fallback for multiboxers.
     - Also, SmartSkillup is not and will not be situationally aware. You still need to summon survival trusts and engage as needed when skilling combat magic.
 5. You can skillup multiple skills, and even mix between self-targeting and enemy-targeting skills, all with ease and in the same session, even!
 6. You can use "modules" to employ additional logic.
     - MP Limit:      Only spells below the current limit will be auto-cast,
     - Trust Target:  Ensures a targetable trust is summoned, as their ilvl mob status boosts skillup rate.
     - SkillUp Food:  Uses the best magic food available in your inventory, sack, satchel, or case
     - Moogle:        Summons the "Moogle" trust to utilize its refresh and skillup rate boost.
     - Convert:       Uses convert when MP is below 25%.
     - Refresh:       Casts the most potent refresh available to your main/sub jobs. (Refresh 1-3 & Battery Charge)
     - Haste:         Casts the most potent haste available to your main/sub jobs. (Haste 1&2, Erratic Flutter)
     - Geo-Refresh:   Sustains a Geo-Refresh colure on the player.
     - Sublimation:   Automatically activates and completes Sublimation.
     - Composure:     A hidden module that applies composure prior to casting refresh & haste and removes it afterwards.
     - Radial Arcana: A hidden module that, if a pet is out, will use Radial Arcana when MP is below 60%.
     - Skill up with Moogle, use magic skillup food, Refresh, Haste, summon trusts to target for their ilvl skill rate boosts, and more!
