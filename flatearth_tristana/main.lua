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

function anyQableChampsInRange() 
  for i = 0, objManager.enemies_n - 1 do
    local enemy = objManager.enemies[i];
    if (not menu.qset.blacklist[enemy.name]:get() and
          not enemy.isDead and
          player.pos:dist(enemy.pos) < player.attackRange) then
            return true
    end
  end
  
  return false;
end

local e_range = {525,533,541,549,557,565,573,581,589,597,605,613,621,629,637,645,653,661};
function doE() 
  for i = 0, objManager.enemies_n - 1 do
    local enemy = objManager.enemies[i];
    
    if (not menu.eset.blacklist[enemy.name]:get()) then
      local currERange = e_range[player.levelRef];
      
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
      local currRRange = e_range[player.levelRef];
      
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
local e_physical_scale = {60 , 70 , 80 ,90 , 100};
local e_physical_pct_scale = {.5 , .65 , .80 , .95 , 1.1};
function damageFromEForRCalc(unit)
  local totalDamageFromE = 0;

  if (enemyWithE == unit) then
    local stacksAfterR = enemyEStacks + 1;
    if (stacksAfterR > 4) then
      stacksAfterR = 4;
    end

    local baseMagicDmg = e_magic_scale[player:spellSlot(2).level] or 0;
    local totalMagicDmg = baseMagicDmg + (.25 * getTotalAP())

    local basePhysicalDmg = e_physical_scale[player:spellSlot(2).level] or 0;
    local basePhysicalPctDmg = e_physical_pct_scale[player:spellSlot(2).level] or 0;
    local stackPct = stacksAfterR * .3;
    local stackedPhysicalDmg = basePhysicalDmg + (basePhysicalDmg * stackPct);
    local stackedPhysicalPctDmg = basePhysicalPctDmg + (basePhysicalPctDmg * stackPct);
    local stackedApPct = .5 + (.5*stackPct)
    local totalPhysicalDmg = stackedPhysicalDmg + (stackedPhysicalPctDmg * GetBonusAD()) + (stackedApPct * getTotalAP())

    totalDamageFromE = CalculateMagicDamage(unit, totalMagicDmg) + CalculatePhysicalDamage(unit, totalPhysicalDmg);
  end

  return totalDamageFromE;
end

local r_scale = {300,400,500};
function r_damage_to_champion(unit)
	local baseMagicDmg = r_scale[player:spellSlot(3).level] or 0;
  local totalMagicDmgFromR = CalculateMagicDamage(unit, baseMagicDmg + getTotalAP());
  
	-- return totalMagicDmgFromR + damageFromEForRCalc(unit);
  return totalMagicDmgFromR - unit.magicalShield;
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



local function ontick()
  useCombatQ();
  useCombatR();
  useCombatE();

  panicR();

  -- if enemyWithE then
  --   print(enemyWithE.name);
  --   print(enemyEStacks);
  -- end

  -- if not enemyWithE then
  --   print("noEnemyWithE");
  -- end

  -- for i = 0, objManager.enemies_n - 1 do
  --   local enemy = objManager.enemies[i];
    
  --   print(r_damage_to_champion(enemy));
  -- end
end


local function after_aa()
  -- useCombatE();
end

enemyWithE = nil;
enemyEStacks = 0;

function resetEnemyWithE()
  enemyWithE = nil;
  enemyEStacks = 0;
end

cb.add(cb.spell, function(spell)
  -- if(string.find(spell.name, "TristanaE")) then
  --   enemyWithE = spell.target;
  --   DelayAction(resetEnemyWithE, 4 + spells.e.delay);
  -- end

  -- if (spell.owner == player and spell.isBasicAttack and spell.target == enemyWithE) then
  --   enemyEStacks = enemyEStacks + 1;

  --   if (enemyEStacks == 4) then
  --     DelayAction(resetEnemyWithE, .25);
  --   end
  -- end
 -- if(spell.owner == player) then
 --   print(spell.name)
 --   print(spell.owner.charName);
 -- end
end)

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