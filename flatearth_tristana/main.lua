local orb = module.internal("orb");
local evade = module.internal("evade");
local pred = module.internal("pred");
local ts = module.internal('TS');

local menu = menu("FlatEarthTristana", "FlatEarth Tristana");

menu:menu("qset", "Q Settings")
menu.qset:boolean("combatQ", "Combat Q ", true)
menu.qset:menu("blacklist", "Q Blacklist")
for i = 0, objManager.enemies_n - 1 do
  local enemy = objManager.enemies[i];
  menu.qset.blacklist:boolean(enemy.name, "Block Q:" .. enemy.charName, false)
end

menu:menu("eset", "E Settings")
menu.eset:boolean("combatE", "Use Combo E", true)
menu.eset:menu("blacklist", "e Blacklist")
for i = 0, objManager.enemies_n - 1 do
  local enemy = objManager.enemies[i];
  menu.eset.blacklist:boolean(enemy.name, "Block E:" .. enemy.charName, false)
end

menu:menu("rset", "R Settings")
menu.rset:boolean("combatR", "Auto R killable - beta", true)
menu.rset:menu("blacklist", "R Blacklist")
for i = 0, objManager.enemies_n - 1 do
  local enemy = objManager.enemies[i];
  menu.rset.blacklist:boolean(enemy.name, "Block R:" .. enemy.charName, false)
end
menu.rset:boolean("panicR", "Auto Panic R enemy away", true)
menu.rset:slider('panicRMaxHealth', "when my health % is below", 25, 0, 100, 1);

spells = {};

spells.e = { 
  delay = .75; 
  speed = 2400;
}

local delayedActions, delayedActionsExecuter = {}, nil
function DelayAction(func, delay, args) --delay in seconds
  if not delayedActionsExecuter then
    function delayedActionsExecuter()
      for t, funcs in pairs(delayedActions) do
        if t <= os.clock() then
          for i = 1, #funcs do
            local f = funcs[i]
            if f and f.func then
              f.func(unpack(f.args or {}))
            end
          end
          delayedActions[t] = nil
        end
      end
    end
    cb.add(cb.tick, delayedActionsExecuter)
  end
  local t = os.clock() + (delay or 0)
  if delayedActions[t] then
    delayedActions[t][#delayedActions[t] + 1] = {func = func, args = args}
  else
    delayedActions[t] = {{func = func, args = args}}
  end
end

-- Used by target selector, without pred

function select_target(res, obj, dist)
  if dist > 1000 then return end
  
  res.obj = obj
  return true
end

-- Get target selector result

local function get_target()
  return ts.get_result(select_target).obj
end

function anyQableChampsInRange() 
  for i = 0, objManager.enemies_n - 1 do
    local enemy = objManager.enemies[i];
    if (not menu.qset.blacklist[enemy.name]:get() and
          not enemy.isDead and enemy.isVisible and
          player.pos:dist(enemy.pos) < player.attackRange) then
            return true
    end
  end
  
  return false;
end

local e_range = {525,533,541,549,557,565,573,581,589,597,605,613,621,629,637,645,653,661};
function doE() 
  local currERange = e_range[player.levelRef];

  -- first try to e target 
  local target = get_target();
  if (target and target.type == 1 and player.pos:dist(target.pos) < currERange and not menu.eset.blacklist[target.name]:get()) then
    player:castSpell("obj", 2, target)
  end

  -- otherwise just anyone
  for i = 0, objManager.enemies_n - 1 do
    local enemy = objManager.enemies[i];
    
    if (not menu.eset.blacklist[enemy.name]:get()) then
      if (player.pos:dist(enemy.pos) < currERange) then
        player:castSpell("obj", 2, enemy)
      end
    end
  end
  
  return false;
end

function doR()
  for i = 0, objManager.enemies_n - 1 do
    local enemy = objManager.enemies[i];
    
    if (not menu.rset.blacklist[enemy.name]:get()) then
      local currRRange = e_range[player.levelRef] + 200;
      
      if (player.pos:dist(enemy.pos) < currRRange and r_damage_to_champion(enemy) > enemy.health) then
        player:castSpell("obj", 3, enemy)
      end
    end
  end
  
  return false;
end

-- Returns total AP of @obj or player
function getTotalAP(obj)
  local obj = obj or player
  return obj.flatMagicDamageMod * obj.percentMagicDamageMod
end

function GetBonusAD(obj)
  local obj = obj or player
  return ((obj.baseAttackDamage + obj.flatPhysicalDamageMod) * obj.percentPhysicalDamageMod) - obj.baseAttackDamage
end

-- Returns magic damage multiplier on @target from @damageSource or player
function MagicReduction(target, damageSource)
  local damageSource = damageSource or player
  local magicResist = (target.spellBlock * damageSource.percentMagicPenetration) - damageSource.flatMagicPenetration
  return magicResist >= 0 and (100 / (100 + magicResist)) or (2 - (100 / (100 - magicResist)))
end

function PhysicalReduction(target, damageSource)
  local damageSource = damageSource or player
  local armor = ((target.bonusArmor * damageSource.percentBonusArmorPenetration) + (target.armor - target.bonusArmor)) * damageSource.percentArmorPenetration
  local lethality = (damageSource.physicalLethality * .4) + ((damageSource.physicalLethality * .6) * (damageSource.levelRef / 18))
  return armor >= 0 and (100 / (100 + (armor - lethality))) or (2 - (100 / (100 - (armor - lethality))))
end

-- Calculates magic damage on @target from @damageSource or player
function CalculateMagicDamage(target, damage, damageSource)
  local damageSource = damageSource or player
  if target then
    return (damage * MagicReduction(target, damageSource))
  end
  return 0
end

function CalculatePhysicalDamage(target, damage, damageSource)
  local damageSource = damageSource or player
  if target then
    return (damage * PhysicalReduction(target, damageSource))
  end
  return 0
end

local e_magic_scale = {50 , 75 , 100 ,125, 150};
local max_e_physical_scale = {132, 154, 176, 198, 220};
local max_e_bonus_ad_multiplier_scale = {1.10, 1.43, 1.76, 2.09, 2.42};
function damageFromEForRCalc(unit)
  local totalDamageFromE = 0;
  local enemyEStacks = get_e_stacks(unit);

  if (enemyEStacks == 3) then -- so we're about to get the 4th stack if we use r
      local baseMagicDmg = e_magic_scale[player:spellSlot(2).level] or 0;
      local totalMagicDmg = baseMagicDmg + (.25 * getTotalAP())

      local physicalDmg = max_e_physical_scale[player:spellSlot(2).level] or 0;
      local bonusAdMultiplier = max_e_bonus_ad_multiplier_scale[player:spellSlot(2).level] or 0;
      local totalPhysicalDmg = physicalDmg + (bonusAdMultiplier * GetBonusAD()) + (1.1 * getTotalAP())

      totalDamageFromE = CalculateMagicDamage(unit, totalMagicDmg) + CalculatePhysicalDamage(unit, totalPhysicalDmg) - unit.physicalShield;
      print("Damage from max stacked e: " .. tostring(totalDamageFromE));
  end

  return totalDamageFromE;
end

local r_scale = {300,400,500};
function r_damage_to_champion(unit)
	local baseMagicDmg = r_scale[player:spellSlot(3).level] or 0;
  local totalMagicDmgFromR = CalculateMagicDamage(unit, baseMagicDmg + getTotalAP());
  
	-- return totalMagicDmgFromR + damageFromEForRCalc(unit);
  return totalMagicDmgFromR - unit.magicalShield + damageFromEForRCalc(unit);
end

function useCombatQ() 
  if (player:spellSlot(0).state == 0 and orb.menu.combat.key:get() and menu.qset.combatQ:get() and anyQableChampsInRange()) then
    player:castSpell("pos", 0, player.pos)
  end
end

function useCombatE() 
  if (player:spellSlot(2).state == 0 and orb.menu.combat.key:get() and menu.eset.combatE:get()) then
    doE();
  end
end

function useCombatR() 
  if (player:spellSlot(3).state == 0 and orb.menu.combat.key:get() and menu.rset.combatR:get()) then
    doR();
  end
end

function findClosestEnemy()
  local closestEnemy = nil;
  local enemies = objManager.enemies;
  
  for i = 0, objManager.enemies_n - 1 do
    local enemy = enemies[i];
    local distToEnemy = player.pos:dist(enemy.pos);
    
    if (not closestEnemy) then
      closestEnemy = enemy; -- first minion
    end
    if (distToEnemy < player.pos:dist(closestEnemy.pos)) then
      closestEnemy = enemy;
    end
  end
  
  --print('returning ' + closestMinion)
  return closestEnemy;
end

function panicR()
  if(menu.rset.panicR:get() and player.health < (menu.rset.panicRMaxHealth:get() / 100 * player.maxHealth)) then
    closestEnemy = findClosestEnemy();
    if (closestEnemy and player.pos:dist(closestEnemy) < 300) then
      player:castSpell("obj", 3, closestEnemy);
    end
  end
end

local function ondraw()
  -- local pos = graphics.world_to_screen(player.pos);
  -- if menu.qset.combatQ:get() then 
  --   graphics.draw_text_2D("Auto Combat Q", 14, pos.x - 50, pos.y + 50, graphics.argb(255,255,255,255))
  -- end
  
  -- if menu.eset.combatE:get() then 
  --   graphics.draw_text_2D("Auto Combat E", 14, pos.x - 50, pos.y + 60, graphics.argb(255,255,255,255))
  -- end
  
  -- if menu.rset.combatR:get() then 
  --   graphics.draw_text_2D("Auto R", 14, pos.x - 50, pos.y + 70, graphics.argb(255,255,255,255))
  -- end
end

function has_buff(unit, name)
  for i = 0, unit.buffManager.count - 1 do
      local buff = unit.buffManager:get(i)
      if buff and buff.valid and string.lower(buff.name) == name then
        if game.time <= buff.endTime then
            return true, buff.stacks
        end
      end
    end
    return false, 0
end

-- Return W stacks

function get_e_stacks(unit)
  local buff, stacks = has_buff(unit, "tristanaecharge")
  if buff then
    return stacks;
  end
  return 0;
end

local function ontick()
  useCombatQ();
  useCombatR();
  useCombatE();

  panicR();

  -- for i = 0, objManager.enemies_n - 1 do
  --   local enemy = objManager.enemies[i];
    
  --   for i = 0, enemy.buffManager.count - 1 do
  --     local buff = enemy.buffManager:get(i)
  --     if buff and buff.valid then
  --       if game.time <= buff.endTime and buff.name == "tristanaecharge" then
  --         print(buff.name);
  --         print(buff.stacks);
  --       end
  --     end
  --   end
  -- end
  -- return false, 0
end
  -- end


local function after_aa()
  -- useCombatE();
end


-- cb.add(cb.spell, function(spell)
--  -- if(spell.owner == player) then
--  --   print(spell.name)
--  --   print(spell.owner.charName);
--  -- end
-- end)

--cb.add(cb.create_missile, function(missile)
--  if missile.spell.owner == player then
--    print("missle created: " .. missile.name);
--  end
--end)

--cb.add(cb.delete_missile, function(missile)
--  if missile.spell.owner == player then
--    print("missle deleted: " .. missile.name);
--  end
--end)

--cb.add(cb.create_particle, function(particle)
--  if particle.owner == player then
--    print("particle: " .. particle.name);
--  end
--end)



cb.add(cb.draw, ondraw)
cb.add(cb.tick, ontick)
orb.combat.register_f_after_attack(after_aa)