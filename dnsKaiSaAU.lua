require "PremiumPrediction"
require "DamageLib"
require "2DGeometry"
require "MapPositionGOS"

local EnemyHeroes = {}
local AllyHeroes = {}
local EnemySpawnPos = nil
local AllySpawnPos = nil
-- [ AutoUpdate ] --
PrintChat(myHero:GetSpellData(_R).level)
do
    
    local Version = 1.0
    
    local Files = {
        Lua = {
            Path = SCRIPT_PATH,
            Name = "dnsKaiSaAU.lua",
            Url = "https://raw.githubusercontent.com/fkndns/dnsKaiSaAU/main/dnsKaiSaAU.lua"
        },
        Version = {
            Path = SCRIPT_PATH,
            Name = "dnsKaiSaAU.version",
            Url = "https://raw.githubusercontent.com/fkndns/dnsKaiSaAU/main/dnsKaiSaAU.version"    -- check if Raw Adress correct pls.. after you have create the version file on Github
        }
    }
    
    local function AutoUpdate()
        
        local function DownloadFile(url, path, fileName)
            DownloadFileAsync(url, path .. fileName, function() end)
            while not FileExist(path .. fileName) do end
        end
        
        local function ReadFile(path, fileName)
            local file = io.open(path .. fileName, "r")
            local result = file:read()
            file:close()
            return result
        end
        
        DownloadFile(Files.Version.Url, Files.Version.Path, Files.Version.Name)
        local textPos = myHero.pos:To2D()
        local NewVersion = tonumber(ReadFile(Files.Version.Path, Files.Version.Name))
        if NewVersion > Version then
            DownloadFile(Files.Lua.Url, Files.Lua.Path, Files.Lua.Name)
            print("New Series Version. Press 2x F6")     -- <-- you can change the massage for users here !!!!
        else
            print(Files.Version.Name .. ": No Updates Found")   --  <-- here too
        end
    
    end
    
    AutoUpdate()

end

local function IsNearEnemyTurret(pos, distance)
    --PrintChat("Checking Turrets")
    local turrets = _G.SDK.ObjectManager:GetTurrets(GetDistance(pos) + 1000)
    for i = 1, #turrets do
        local turret = turrets[i]
        if turret and GetDistance(turret.pos, pos) <= distance+915 and turret.team == 300-myHero.team then
            --PrintChat("turret")
            return turret
        end
    end
end

local function IsUnderEnemyTurret(pos)
    --PrintChat("Checking Turrets")
    local turrets = _G.SDK.ObjectManager:GetTurrets(GetDistance(pos) + 1000)
    for i = 1, #turrets do
        local turret = turrets[i]
        if turret and GetDistance(turret.pos, pos) <= 915 and turret.team == 300-myHero.team then
            --PrintChat("turret")
            return turret
        end
    end
end

function GetDifference(a,b)
    local Sa = a^2
    local Sb = b^2
    local Sdif = (a-b)^2
    return math.sqrt(Sdif)
end

function GetDistanceSqr(Pos1, Pos2)
    local Pos2 = Pos2 or myHero.pos
    local dx = Pos1.x - Pos2.x
    local dz = (Pos1.z or Pos1.y) - (Pos2.z or Pos2.y)
    return dx^2 + dz^2
end

function GetDistance(Pos1, Pos2)
    return math.sqrt(GetDistanceSqr(Pos1, Pos2))
end

function IsImmobile(unit)
    local MaxDuration = 0
    for i = 0, unit.buffCount do
        local buff = unit:GetBuff(i)
        if buff and buff.count > 0 then
            local BuffType = buff.type
            if BuffType == 5 or BuffType == 11 or BuffType == 21 or BuffType == 22 or BuffType == 24 or BuffType == 29 or buff.name == "recall" then
                local BuffDuration = buff.duration
                if BuffDuration > MaxDuration then
                    MaxDuration = BuffDuration
                end
            end
        end
    end
    return MaxDuration
end

function GetEnemyHeroes()
    for i = 1, Game.HeroCount() do
        local Hero = Game.Hero(i)
        if Hero.isEnemy then
            table.insert(EnemyHeroes, Hero)
            PrintChat(Hero.name)
        end
    end
    --PrintChat("Got Enemy Heroes")
end

function GetEnemyBase()
    for i = 1, Game.ObjectCount() do
        local object = Game.Object(i)
        
        if not object.isAlly and object.type == Obj_AI_SpawnPoint then 
            EnemySpawnPos = object
            break
        end
    end
end

function GetAllyBase()
    for i = 1, Game.ObjectCount() do
        local object = Game.Object(i)
        
        if object.isAlly and object.type == Obj_AI_SpawnPoint then 
            AllySpawnPos = object
            break
        end
    end
end

function GetAllyHeroes()
    for i = 1, Game.HeroCount() do
        local Hero = Game.Hero(i)
        if Hero.isAlly then
            table.insert(AllyHeroes, Hero)
            PrintChat(Hero.name)
        end
    end
    --PrintChat("Got Enemy Heroes")
end

function GetBuffStart(unit, buffname)
    for i = 0, unit.buffCount do
        local buff = unit:GetBuff(i)
        if buff.name == buffname and buff.count > 0 then 
            return buff.startTime
        end
    end
    return nil
end

function GetBuffExpire(unit, buffname)
    for i = 0, unit.buffCount do
        local buff = unit:GetBuff(i)
        if buff.name == buffname and buff.count > 0 then 
            return buff.expireTime
        end
    end
    return nil
end

function GetBuffStacks(unit, buffname)
    for i = 0, unit.buffCount do
        local buff = unit:GetBuff(i)
        if buff.name == buffname and buff.count > 0 then 
            return buff.count
        end
    end
    return 0
end

local function GetWaypoints(unit) -- get unit's waypoints
    local waypoints = {}
    local pathData = unit.pathing
    table.insert(waypoints, unit.pos)
    local PathStart = pathData.pathIndex
    local PathEnd = pathData.pathCount
    if PathStart and PathEnd and PathStart >= 0 and PathEnd <= 20 and pathData.hasMovePath then
        for i = pathData.pathIndex, pathData.pathCount do
            table.insert(waypoints, unit:GetPath(i))
        end
    end
    return waypoints
end

local function GetUnitPositionNext(unit)
    local waypoints = GetWaypoints(unit)
    if #waypoints == 1 then
        return nil -- we have only 1 waypoint which means that unit is not moving, return his position
    end
    return waypoints[2] -- all segments have been checked, so the final result is the last waypoint
end

local function GetUnitPositionAfterTime(unit, time)
    local waypoints = GetWaypoints(unit)
    if #waypoints == 1 then
        return unit.pos -- we have only 1 waypoint which means that unit is not moving, return his position
    end
    local max = unit.ms * time -- calculate arrival distance
    for i = 1, #waypoints - 1 do
        local a, b = waypoints[i], waypoints[i + 1]
        local dist = GetDistance(a, b)
        if dist >= max then
            return Vector(a):Extended(b, dist) -- distance of segment is bigger or equal to maximum distance, so the result is point A extended by point B over calculated distance
        end
        max = max - dist -- reduce maximum distance and check next segments
    end
    return waypoints[#waypoints] -- all segments have been checked, so the final result is the last waypoint
end

function GetTarget(range)
    if _G.SDK then
        return _G.SDK.TargetSelector:GetTarget(range, _G.SDK.DAMAGE_TYPE_MAGICAL);
    else
        return _G.GOS:GetTarget(range,"AD")
    end
end

function GotBuff(unit, buffname)
    for i = 0, unit.buffCount do
        local buff = unit:GetBuff(i)
        --PrintChat(buff.name)
        if buff.name == buffname and buff.count > 0 then 
            return buff.count
        end
    end
    return 0
end

function BuffActive(unit, buffname)
    for i = 0, unit.buffCount do
        local buff = unit:GetBuff(i)
        if buff.name == buffname and buff.count > 0 then 
            return true
        end
    end
    return false
end

function IsReady(spell)
    return myHero:GetSpellData(spell).currentCd == 0 and myHero:GetSpellData(spell).level > 0 and myHero:GetSpellData(spell).mana <= myHero.mana and Game.CanUseSpell(spell) == 0
end

function Mode()
    if _G.SDK then
        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
            return "Combo"
        elseif _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] or Orbwalker.Key.Harass:Value() then
            return "Harass"
        elseif _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR] or Orbwalker.Key.Clear:Value() then
            return "LaneClear"
        elseif _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LASTHIT] or Orbwalker.Key.LastHit:Value() then
            return "LastHit"
        elseif _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_FLEE] then
            return "Flee"
        end
    else
        return GOS.GetMode()
    end
end

function GetItemSlot(unit, id)
    for i = ITEM_1, ITEM_7 do
        if unit:GetItemData(i).itemID == id then
            return i
        end
    end
    return 0
end

function IsFacing(unit)
    local V = Vector((unit.pos - myHero.pos))
    local D = Vector(unit.dir)
    local Angle = 180 - math.deg(math.acos(V*D/(V:Len()*D:Len())))
    if math.abs(Angle) < 80 then 
        return true  
    end
    return false
end

function IsMyHeroFacing(unit)
    local V = Vector((myHero.pos - unit.pos))
    local D = Vector(myHero.dir)
    local Angle = 180 - math.deg(math.acos(V*D/(V:Len()*D:Len())))
    if math.abs(Angle) < 80 then 
        return true  
    end
    return false
end

function SetMovement(bool)
    if _G.PremiumOrbwalker then
        _G.PremiumOrbwalker:SetAttack(bool)
        _G.PremiumOrbwalker:SetMovement(bool)       
    elseif _G.SDK then
        _G.SDK.Orbwalker:SetMovement(bool)
        _G.SDK.Orbwalker:SetAttack(bool)
    end
end


local function CheckHPPred(unit, SpellSpeed)
     local speed = SpellSpeed
     local range = myHero.pos:DistanceTo(unit.pos)
     local time = range / speed
     if _G.SDK and _G.SDK.Orbwalker then
         return _G.SDK.HealthPrediction:GetPrediction(unit, time)
     elseif _G.PremiumOrbwalker then
         return _G.PremiumOrbwalker:GetHealthPrediction(unit, time)
    end
end

function EnableMovement()
    SetMovement(true)
end

local function IsValid(unit)
    if (unit and unit.valid and unit.isTargetable and unit.alive and unit.visible and unit.networkID and unit.pathing and unit.health > 0) then
        return true;
    end
    return false;
end


local function ValidTarget(unit, range)
    if (unit and unit.valid and unit.isTargetable and unit.alive and unit.visible and unit.networkID and unit.pathing and unit.health > 0) then
        if range then
            if GetDistance(unit.pos) <= range then
                return true;
            end
        else
            return true
        end
    end
    return false;
end

local function GetWDmg(unit)
	local Wdmg = getdmg("W", unit, myHero, 1)
	local W2dmg = getdmg("W", unit, myHero, 2)	
	local buff = GetBuffData(unit, "kaisapassivemarker")
	if buff and buff.count == 4 then
		return (Wdmg+W2dmg)		
	else		
		return Wdmg 
	end 
end


class "Manager"

function Manager:__init()
	if myHero.charName == "Kaisa" then
		DelayAction(function () self:LoadKaisa() end, 1.05)
	end
end


function Manager:LoadKaisa()
	Kaisa:Spells()
	Kaisa:Menu()
	Callback.Add("Tick", function() Kaisa:Tick() end)
	Callback.Add("Draw", function() Kaisa:Draws() end)
	if _G.SDK then
        _G.SDK.Orbwalker:OnPreAttack(function(...) Kaisa:OnPreAttack(...) end)
        _G.SDK.Orbwalker:OnPostAttackTick(function(...) Kaisa:OnPostAttackTick(...) end)
        _G.SDK.Orbwalker:OnPostAttack(function(...) Kaisa:OnPostAttack(...) end)
    end
end

class "Kaisa"

local EnemyLoaded = false
local MinionsAround = count

function Kaisa:Menu()
-- menu
	self.Menu = MenuElement({type = MENU, id = "Kaisa", name = "dnsKai'Sa"})
-- q spell
	self.Menu:MenuElement({id = "QSpell", name = "Q", type = MENU})
	self.Menu.QSpell:MenuElement({id = "QCombo", name = "Combo", value = true})
	self.Menu.QSpell:MenuElement({id = "QSpace1", name = "", type = SPACE})
	self.Menu.QSpell:MenuElement({id = "QHarass", name = "Harass", value = false})
	self.Menu.QSpell:MenuElement({id = "QHarassMana", name = "Harass Mana %", value = 50, min = 0, max = 100, identifier = "%"})
	self.Menu.QSpell:MenuElement({id = "QSpace2", name = "", type = SPACE})
	self.Menu.QSpell:MenuElement({id = "QLaneClear", name = "LaneClear", value = false})
	self.Menu.QSpell:MenuElement({id = "QLaneClearCount", name = "LaneClear if Minions >", value = 2, min = 0, max = 7, step = 1})
	self.Menu.QSpell:MenuElement({id = "QLaneClearMana", name = "LaneClear Mana %", value = 50, min = 0, max = 100, identifier = "%"})
	self.Menu.QSpell:MenuElement({id = "QSpace3", name = "", type = SPACE})
	self.Menu.QSpell:MenuElement({id = "QLastHit", name = "LastHit", value = false})
	self.Menu.QSpell:MenuElement({id = "QLastHitMana", name = "LastHit Mana %", value = 50, min = 0, max = 100, identifier = "%"})
	self.Menu.QSpell:MenuElement({id = "QSpace4", name = "", type = SPACE})
-- w spell
	self.Menu:MenuElement({id = "WSpell", name = "W", type = MENU})
	self.Menu.WSpell:MenuElement({id = "WCombo", name = "Combo", value = true})
	self.Menu.WSpell:MenuElement({id = "WSpace1", name = "", type = SPACE})
	self.Menu.WSpell:MenuElement({id = "WHarass", name = "Harass", value = false})
	self.Menu.WSpell:MenuElement({id = "WHarassMana", name = "Harass Mana %", value = 50, min = 0, max = 100, identifier = "%"})
	self.Menu.WSpell:MenuElement({id = "WSpace2", name = "", type = SPACE})
	self.Menu.WSpell:MenuElement({id = "WLastHit", name = "LastHit Cannon when out of AA Range", value = true})
	self.Menu.WSpell:MenuElement({id = "WSpace3", name = "", type = SPACE})
	self.Menu.WSpell:MenuElement({id = "WKS", name = "KS", value = true})
	self.Menu.WSpell:MenuElement({id = "WSpace4", name = "", type = SPACE})
-- e spell 
	self.Menu:MenuElement({id = "ESpell", name = "E", type = MENU})
	self.Menu.ESpell:MenuElement({id = "ECombo", name = "Combo", value = true})
	self.Menu.ESpell:MenuElement({id = "ESpace1", name = "", type = SPACE})
	self.Menu.ESpell:MenuElement({id = "EFlee", name = "Flee", value = true})
	self.Menu.ESpell:MenuElement({id = "ESpace2", name = "", type = SPACE})
	self.Menu.ESpell:MenuElement({id = "EPeel", name = "Autopeel Meeledivers", value = true})
	self.Menu.ESpell:MenuElement({id = "ESpace3", name = "", type = SPACE})
-- r spell
	self.Menu:MenuElement({id = "RSpell", name = "R", type = MENU})
	self.Menu.RSpell:MenuElement({id = "Sorry", name = "R is an automatical thingy", type = SPACE})
	self.Menu.RSpell:MenuElement({id = "Sorry2", name = "I'm really sorry", type = SPACE})
-- draws
	self.Menu:MenuElement({id = "Draws", name = "Draws", type = MENU})
	self.Menu.Draws:MenuElement({id = "EnableDraws", name = "Enable", value = false})
	self.Menu.Draws:MenuElement({id = "DrawsSpace1", name = "", type = SPACE})
	self.Menu.Draws:MenuElement({id = "QDraw", name = "Q Range", value = false})
	self.Menu.Draws:MenuElement({id = "WDraw", name = "W Range", value = false})
	self.Menu.Draws:MenuElement({id = "RDraw", name = "R Range", value = false})
end

function Kaisa:Draws()
	if self.Menu.Draws.EnableDraws:Value() then
        if self.Menu.Draws.QDraw:Value() then
            Draw.Circle(myHero.pos, 600 + myHero.boundingRadius, 1, Draw.Color(255, 255, 0, 0))
        end
		if self.Menu.Draws.WDraw:Value() then
			Draw.Circle(myHero.pos, 3000, 1, Draw.Color(255, 0, 255, 0))
		end
		if self.Menu.Draws.RDraw:Value() and myHero:GetSpellData(_R).level <= 1 then
			Draw.Circle(myHero.pos, 1500, 1, Draw.Color(255, 255, 255, 255))
		end
		if self.Menu.Draws.RDraw:Value() and myHero:GetSpellData(_R).level == 2 then
			Draw.Circle(myHero.pos, 2250, 1, Draw.Color(255, 255, 255, 255))
		end
		if self.Menu.Draws.RDraw:Value() and myHero:GetSpellData(_R).levelv == 3 then
			Draw.Circle(myHero.pos, 3000, 1, Draw.Color(255, 255, 255, 255))
		end
    end
end

function Kaisa:CastingChecks()
	if CastingQ or CastingW or CastingE or CastingR then
		return false
	else
		return true
	end
end


function Kaisa:Spells()
	WSpellData = {speed = 1750, range = 3000, delay = 0.40, radius = 100, collision = {"minion"}, type = "linear"}
end

function Kaisa:Tick()
    if _G.JustEvade and _G.JustEvade:Evading() or (_G.ExtLibEvade and _G.ExtLibEvade.Evading) or Game.IsChatOpen() or myHero.dead then return end
    target = GetTarget(1400)
    AARange = _G.SDK.Data:GetAutoAttackRange(myHero)
	CastingQ = myHero.activeSpell.name == "KaisaQ"
	CastingW = myHero.activeSpell.name == "KaisaW"
	CastingE = myHero.activeSpell.name == "KaisaE"
	CastingR = myHero.activeSpell.name == "KaisaR"
    self:Logic()
	self:Auto()
	self:LastHit()
	self:LaneClear()
    if EnemyLoaded == false then
        local CountEnemy = 0
        for i, enemy in pairs(EnemyHeroes) do
            CountEnemy = CountEnemy + 1
        end
        if CountEnemy < 1 then
            GetEnemyHeroes()
        else
            EnemyLoaded = true
            PrintChat("Enemy Loaded")
        end
    end
end 

function Kaisa:CanUse(spell, mode)
	local ManaPercent = myHero.mana / myHero.maxMana * 100
	if mode == nil then
		mode = Mode()
	end
	if spell == _Q then
		if mode == "Combo" and IsReady(spell) and self.Menu.QSpell.QCombo:Value() then
			return true
		end
		if mode == "Harass" and IsReady(spell) and self.Menu.QSpell.QHarass:Value() and ManaPercent > self.Menu.QSpell.QHarassMana:Value() then
			return true
		end
		if mode == "LaneClear" and IsReady(spell) and self.Menu.QSpell.QLaneClear:Value() and ManaPercent > self.Menu.QSpell.QLaneClearMana:Value() then
			return true
		end
		if mode == "LastHit" and IsReady(spell) and self.Menu.QSpell.QLastHit:Value() and ManaPercent > self.Menu.QSpell.QLastHitMana:Value() then
			return true
		end
	elseif spell == _W then
		if mode == "Combo" and IsReady(spell) and self.Menu.WSpell.WCombo:Value() then
			return true
		end
		if mode == "Harass" and IsReady(spell) and self.Menu.WSpell.WHarass:Value() and ManaPercent > self.Menu.WSpell.WHarassMana:Value() then
			return true
		end
		if mode == "LastHit" and IsReady(spell) and self.Menu.WSpell.WLastHit:Value() then
			return true
		end
		if mode == "KS" and IsReady(spell) and self.Menu.WSpell.WKS:Value() then
			return true
		end
	elseif spell == _E then
		if mode == "Combo" and IsReady(spell) and self.Menu.ESpell.ECombo:Value() then
		--PrintChat("Can Use W KS")
			return true
		end
		if mode == "Flee" and IsReady(spell) and self.Menu.ESpell.EFlee:Value() then
			return true
		end
		if mode == "ChargePeel" and IsReady(spell) and self.Menu.ESpell.EPeel:Value() then
			return true
		end
	end
	return false
end

function Kaisa:Auto()
	for i, enemy in pairs(EnemyHeroes) do
	-- w ks
	--PrintChat("looking for ks")
		local WRange = 1400 + myHero.boundingRadius + enemy.boundingRadius 
		if enemy and not enemy.dead and ValidTarget(enemy, WRange) and self:CanUse(_W, "KS") and self:CastingChecks() and not _G.SDK.Attack:IsActive() then
			local WDamage = GetWDmg(enemy)
			--PrintChat(WDamage)
			local pred = _G.PremiumPrediction:GetPrediction(myHero, enemy, WSpellData)
			if pred.CastPos and _G.PremiumPrediction.HitChance.High(pred.HitChance) and GetDistance(pred.CastPos) < WRange and enemy.health < WDamage then
				Control.CastSpell(HK_W, pred.CastPos)
				--PrintChat("pew")
			end
		end
		local Bedrohungsreichweite = 250 + myHero.boundingRadius + enemy.boundingRadius
		if enemy and not enemy.dead and ValidTarget(enemy, Bedrohungsreichweite) and self:CanUse(_E, "ChargePeel") and self:CastingChecks() and not _G.SDK.Attack:IsActive() then
			if GetDistance(enemy.pos) <= Bedrohungsreichweite and (enemy.ms * 1.0 > myHero.ms or enemy.pathing.isDashing) and IsFacing(enemy)then
				Control.CastSpell(HK_E)
			end
		end
	end
end

function Kaisa:Logic()
	if target == nil then
		return
	end
	local QRange = 600 + myHero.boundingRadius + target.boundingRadius
	local WRange = 1400 + myHero.boundingRadius + target.boundingRadius
	local ERange = AARange + 300 + myHero.boundingRadius + target.boundingRadius
	
	
	if Mode() == "Combo" and target then
		if target and not target.dead and ValidTarget(target, QRange) and self:CanUse(_Q, "Combo") and self:CastingChecks() and not _G.SDK.Attack:IsActive() then
			if GetDistance(target.pos) < QRange then
				Control.CastSpell(HK_Q)
			end
		end
		if target and not target.dead and ValidTarget(target, WRange) and self:CanUse(_W, "Combo") and self:CastingChecks() and not _G.SDK.Attack:IsActive() then
			local pred = _G.PremiumPrediction:GetPrediction(myHero, target, WSpellData)
			if pred.CastPos and _G.PremiumPrediction.HitChance.High(pred.HitChance) and GetDistance(target.pos) < WRange and GetBuffStacks(target, "kaisapassivemarker") >= 3 then 
				Control.CastSpell(HK_W, pred.CastPos)
			end
		end
		if target and not target.dead and ValidTarget(target, ERange) and self:CanUse(_E, "Combo") and self:CastingChecks() and not _G.SDK.Attack:IsActive() then
			if GetDistance(target.pos) < ERange and GetDistance(target.pos) > AARange then
				Control.CastSpell(HK_E)
			end
		end
	end
	if Mode() == "Harass" and target then
		if target and not target.dead and ValidTarget(target, QRange) and self:CanUse(_Q, "Harass") and self:CastingChecks() and not _G.SDK.Attack:IsActive() then
			if GetDistance(target.pos) < QRange then
				Control.CastSpell(HK_Q)
			end
		end
		if target and not target.dead and ValidTarget(target, WRange) and self:CanUse(_W, "Harass") and self:CastingChecks() and not _G.SDK.Attack:IsActive() then
			local pred = _G.PremiumPrediction:GetPrediction(myHero, target, WSpellData)
			if pred.CastPos and _G.PremiumPrediction.HitChance.High(pred.HitChance) and GetDistance(target.pos) < WRange and GetBuffStacks(target, "kaisapassivemarker") >= 3 then 
				Control.CastSpell(HK_W, pred.CastPos)
			end
		end
	end
	if Mode() == "Flee" and target then
		if target and not target.dead and ValidTarget(target, AARange) and self:CanUse(_E, "Flee") and self:CastingChecks() and not _G.SDK.Attack:IsActive() then
			if GetDistance(target.pos) < AARange then
				Control.CastSpell(HK_E)
			end
		end
	end	
end

function Kaisa:LastHit()
	if self:CanUse(_W, "LastHit") and (Mode == "LastHit" or Mode() == "LaneClear" or Mode() == "Harass") then
		local minions = _G.SDK.ObjectManager:GetEnemyMinions(1400)
		for i = 1, #minions do 
			local minion = minions[i]
			if GetDistance(minion.pos) > 525 + myHero.boundingRadius and GetDistance(minion.pos) < 1400 + myHero.boundingRadius and (minion.charName == "SRU_ChaosMinionSiege" or minion.charName == "SRU_OrderMinionSiege") then
				--PrintChat("Got Cannon")
				local WDamage = GetWDmg(minion)
				if minion and not minion.dead and WDamage >= minion.health and self:CastingChecks() and not _G.SDK.Attack:IsActive() then 
					local pred = _G.PremiumPrediction:GetPrediction(myHero, minion, WSpellData)
					--PrintChat("Got Prediction")
					if pred.CastPos and _G.PremiumPrediction.HitChance.Low(pred.HitChance) then
						Control.CastSpell(HK_W, pred.CastPos)
					end
				end
			end
		end
	end
end

function Kaisa:LaneClear()
	local count = 0 
	if self:CanUse(_Q, "LaneClear") and Mode() == "LaneClear" then
		local minions = _G.SDK.ObjectManager:GetEnemyMinions(600 + myHero.boundingRadius)
		for i = 1, #minions do 
			local minion = minions[i]
			if GetDistance(minion.pos) < 600 + myHero.boundingRadius then
				count = count + 1
			end
				
				if minion and not minion.dead and MinionsAround > self.Menu.QSpell.QLaneClearCount:Value() then
					Control.CastSpell(HK_Q)
				end
		end
	end
	MinionsAround = count
end
	
	
	
function Kaisa:OnPostAttack(args)
end

function Kaisa:OnPostAttackTick(args)
end

function Kaisa:OnPreAttack(args)
end


function OnLoad()
    Manager()
end
