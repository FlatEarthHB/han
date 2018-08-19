local orb = module.internal("orb");
local evade = module.internal("evade");
local pred = module.internal("pred");
local ts = module.internal('TS');

-------------------
-- Menu creation --
-------------------

local menu = menu("FlatEarthEzreal", "FlatEarth Ezreal");

menu:menu("q", "Q Settings")
menu.q:keybind("laneClear", "Lane Clear Q", nil, "K")
menu.q:keybind("jungleClear", "Jungle Clear Q", nil, "J")

menu:menu("r", "R Settings");
	menu.r:keybind("ult", "Manual R", "T", nil)
	menu.r:slider('range', "Max manual ult range", 2000, 0, 5000, 5);

ts.load_to_menu();

----------------
-- Spell data --
----------------

local spells = {};

spells.q = { 
	delay = 0.25; 
	width = 80;
	speed = 1200; 
	boundingRadiusMod = 1; 
	collision = { hero = true, minion = true }; 
	range = 1150;
}

-- Pred input for ult

spells.r = { 
	delay = 1; 
	width = 160;
	speed = 2000; 
	boundingRadiusMod = 1; 
	collision = { hero = true, minion = false }; 
}

local function ult_target(res, obj, dist)
	if dist > 5000 then return end
	
	res.obj = obj
	return true
end

-- Get target selector result

local function get_target(func)
	return ts.get_result(func).obj
end

-- Calculates physical damage on @target from @damageSource or player
function CalculatePhysicalDamage(target, damage, damageSource)
	local damageSource = damageSource or player
	if target then
		return (damage * PhysicalReduction(target, damageSource))
	end
	return 0
end

-- Calculates magic damage on @target from @damageSource or player
function CalculateMagicDamage(target, damage, damageSource)
	local damageSource = damageSource or player
	if target then
		return (damage * MagicReduction(target, damageSource))
	end
	return 0
end

-- Returns physical damage multiplier on @target from @damageSource or player
function PhysicalReduction(target, damageSource)
  local damageSource = damageSource or player
  local armor = ((target.bonusArmor * damageSource.percentBonusArmorPenetration) + (target.armor - target.bonusArmor)) * damageSource.percentArmorPenetration
  local lethality = (damageSource.physicalLethality * .4) + ((damageSource.physicalLethality * .6) * (damageSource.levelRef / 18))
  return armor >= 0 and (100 / (100 + (armor - lethality))) or (2 - (100 / (100 - (armor - lethality))))
end

-- Returns magic damage multiplier on @target from @damageSource or player
function MagicReduction(target, damageSource)
	local damageSource = damageSource or player
	local magicResist = (target.spellBlock * damageSource.percentMagicPenetration) - damageSource.flatMagicPenetration
	return magicResist >= 0 and (100 / (100 + magicResist)) or (2 - (100 / (100 - magicResist)))
end

-- Returns total AD of @obj or player
function getTotalAD(obj)
	local obj = obj or player
	return (obj.baseAttackDamage + obj.flatPhysicalDamageMod) * obj.percentPhysicalDamageMod
end

-- Returns total AP of @obj or player
function getTotalAP(obj)
	local obj = obj or player
	return obj.flatMagicDamageMod * obj.percentMagicDamageMod
end

local q_scale = {15,40,65,90,115};
local function q_damage_to_minion(unit)
	local basePhysicalDmg = q_scale[player:spellSlot(0).level] or 0;
  local totalPhysicalDmg = basePhysicalDmg + (getTotalAD() * 1.1);
  local totalMagicDmg = getTotalAP() * .4;
  
	return CalculatePhysicalDamage(unit, totalPhysicalDmg) + CalculateMagicDamage(unit, totalMagicDmg);
end


local function useQMinions()
  if not menu.q.laneClear:get() then return end;
  local enemyMinions = objManager.minions[TEAM_ENEMY];
  
    for i = 0, objManager.minions.size[TEAM_ENEMY] - 1 do
      local minion = enemyMinions[i];
      local distToMinion= player.pos:dist(minion.pos);
      if (distToMinion < spells.q.range 
            and distToMinion > player.attackRange 
            and not minion.isDead 
            and minion.health 
            and minion.health > 0 
            and minion.isVisible) then
              local timeToHit = distToMinion / spells.q.speed
              local compareHealth = orb.farm.predict_hp(minion, timeToHit);
              if (compareHealth < q_damage_to_minion(minion)) then
                local pos = pred.linear.get_prediction(spells.q, minion)
                if pos and pos.startPos:dist(pos.endPos) < spells.q.range then
                  player:castSpell("pos", 0, vec3(pos.endPos.x, mousePos.y, pos.endPos.y))
                end
              end
      end
    end
end

local function findClosestJungleMinion()
  local closestMinion = nil;
  local jungleMinions = objManager.minions[TEAM_NEUTRAL];
  
  for i = 0, objManager.minions.size[TEAM_NEUTRAL] - 1 do
    local minion = jungleMinions[i];
    local distToMinion= player.pos:dist(minion.pos);
    
    if (not closestMinion) then
      closestMinion = minion; -- first minion
    end
    if (distToMinion < player.pos:dist(closestMinion.pos)) then
      closestMinion = minion;
    end
  end
  
  --print('returning ' + closestMinion)
  return closestMinion;
end

local function useQJungle()
  if not menu.q.jungleClear:get() then 
    return 
  end;
  if not player:spellSlot(1).state == 0 then 
    return 
  end;

  local closestMinion = findClosestJungleMinion();
--  print(closestMinion);
  if closestMinion then
    local minion = closestMinion;
    local distToMinion= player.pos:dist(minion.pos);
    if (distToMinion < spells.q.range 
      and not minion.isDead 
      and minion.health 
      and minion.health > 0 
      and minion.isVisible) then
      local pos = pred.linear.get_prediction(spells.q, minion)
      if pos and pos.startPos:dist(pos.endPos) < spells.q.range then
        player:castSpell("pos", 0, vec3(pos.endPos.x, mousePos.y, pos.endPos.y))
      end
    end
  end
end

local function manual_ult()
  if not menu.r.ult:get() then return end
  if player:spellSlot(3).state ~= 0 then return end

  player:move(game.mousePos);

  local target = get_target(ult_target);
  if not target then return end

  local dist = player.pos:dist(target);

  if not target.isDead and dist <= menu.r.range:get() then
    local rpred = pred.linear.get_prediction(spells.r, target)
    if not rpred then return end
    player:castSpell("pos", 3, vec3(rpred.endPos.x, game.mousePos.y, rpred.endPos.y))
  end
end

-----------
-- Hooks --
-----------

local executingLaneClearQ = false;

local function myfunction()

  if not menu.q.laneClear:get() then return end;
  if (executingLaneClearQ) then return end;
  executingLaneClearQ = true;
    local enemyMinions = objManager.minions[TEAM_ENEMY];
  
    for i = 0, objManager.minions.size[TEAM_ENEMY] - 1 do
      local minion = enemyMinions[i];
      local distToMinion= player.pos:dist(minion.pos);
      if (not minion == lastMinionAttacked and distToMinion < spells.q.range 
            and not minion.isDead 
            and minion.health 
            and minion.health > 0 
            and minion.isVisible) then
              local timeToHit = distToMinion / spells.q.speed
              local compareHealth = orb.farm.predict_hp(minion, timeToHit);
              if (compareHealth < q_damage_to_minion(minion)) then
                local pos = pred.linear.get_prediction(spells.q, minion)
                if pos and pos.startPos:dist(pos.endPos) < spells.q.range then
                  player:castSpell("pos", 0, vec3(pos.endPos.x, mousePos.y, pos.endPos.y))
                end
              end
      end
    end
  
  executingLaneClearQ = false;
end

local lastMinionAttacked = nil;

cb.add(cb.spell, function(spell)
  if(spell.owner == player and spell.isBasicAttack) then
    lastMinionAttacked = spell.target
  end
--  if(spell.owner == player) then
--    print(spell.name);
--    print(spell.static.missileSpeed)
--		print(spell.static.lineWidth)
--    print(spell.windUpTime)
--		print(spell.animationTime)
--  end
end)

-- Called pre tick

local function ontick()
	if orb.menu.lane_clear.key:get() then
		useQMinions()
    useQJungle()
	end
  
  manual_ult()
end

local function ondraw()
	local pos = graphics.world_to_screen(player.pos);
	if menu.q.laneClear:get() then 
		graphics.draw_text_2D("Spell Lane Clear", 14, pos.x - 50, pos.y + 50, graphics.argb(255,255,255,255))
    graphics.draw_text_2D("Spell Jungle Clear", 14, pos.x - 50, pos.y + 60, graphics.argb(255,255,255,255))
	end
end

cb.add(cb.draw, ondraw)
orb.combat.register_f_pre_tick(ontick)
orb.combat.set_invoke_after_attack(true)
orb.combat.register_f_after_attack(myfunction)
