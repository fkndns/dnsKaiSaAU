require "PremiumPrediction"
require "DamageLib"
require "2DGeometry"
require "MapPositionGOS"
require "GGPrediction"

local EnemyHeroes = {}
local AllyHeroes = {}
local EnemySpawnPos = nil
local AllySpawnPos = nil
-- [ AutoUpdate ] --
do
    
    local Version = 1.5
    
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

local ItemHotKey = {[ITEM_1] = HK_ITEM_1, [ITEM_2] = HK_ITEM_2,[ITEM_3] = HK_ITEM_3, [ITEM_4] = HK_ITEM_4, [ITEM_5] = HK_ITEM_5, [ITEM_6] = HK_ITEM_6,}


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
local AARange = 525 + myHero.boundingRadius 
local EnemyLoaded = false
local MinionsAround = count
local DodgeableRange = 400
local GaleTargetRange = AARange + DodgeableRange + 50
local QMouseSpot = nil
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
--misc
	self.Menu:MenuElement({id = "Misc", name = "Activator", type = MENU})
	self.Menu.Misc:MenuElement({id = "Pots", name = "Auto Use Potions/Refill/Cookies", value = true})
	self.Menu.Misc:MenuElement({id = "HeaBar", name = "Auto Use Heal / Barrier", value = true})
	self.Menu.Misc:MenuElement({id = "Cleanse", name = "Auto Use Cleans", value = true})
	self.Menu.Misc:MenuElement({id = "QSS", name = "Auto Use QSS", value = true})
--GaleForce / Flash Evade
	self.Menu:MenuElement({id = "Evade", name = "Evade", type = MENU})
	self.Menu.Evade:MenuElement({id = "EvadeGaFo", name = "Use Galeforce to Dodge", value = true})
	self.Menu.Evade:MenuElement({id = "EvadeFla", name = "Use Flash to Dodge", value = true})
	self.Menu.Evade:MenuElement({id = "EvadeCalc", name = "Sometimes Dodge Away from Mouse", value = true})
	self.Menu.Evade:MenuElement({id = "EvadeSpells", name = "Enemy Spells to Dodge", type = MENU})
-- RangedHelper
	self.Menu:MenuElement({id = "RangedHelperWalk", name = "Enable KiteAssistance", value = true})
end

function Kaisa:MenuEvade()
	for i, enemy in pairs(EnemyHeroes) do
		self.Menu.Evade.EvadeSpells:MenuElement({id = enemy.charName, name = enemy.charName, type = MENU})
        self.Menu.Evade.EvadeSpells[enemy.charName]:MenuElement({id = enemy:GetSpellData(_Q).name, name = enemy:GetSpellData(_Q).name, value = false})
        self.Menu.Evade.EvadeSpells[enemy.charName]:MenuElement({id = enemy:GetSpellData(_W).name, name = enemy:GetSpellData(_W).name, value = false})
        self.Menu.Evade.EvadeSpells[enemy.charName]:MenuElement({id = enemy:GetSpellData(_E).name, name = enemy:GetSpellData(_E).name, value = false})
        self.Menu.Evade.EvadeSpells[enemy.charName]:MenuElement({id = enemy:GetSpellData(_R).name, name = enemy:GetSpellData(_R).name, value = false})
	end
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
	if CastingQ or CastingW or CastingR then
		return false
	else
		return true
	end
end

function Kaisa:CastingChecksE()
	if CastingQ or CastingW or CastingE or CastingR then
		return false
	else 
		return true
	end
end

function Kaisa:Spells()
	local Latency = Game.Latency()
	WPrediction = GGPrediction:SpellPrediction({Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.4+Latency, Radius = 100, Range = 1400, Speed = 1750, Collision = true, CollisionTypes = {GGPrediction.COLLISION_MINION}})
	WSpellData = {speed = 1750, range = 1400, delay = 0.4+Latency, radius = 100, collision = {"minion"}, type = "linear"}
end

function Kaisa:Tick()
    if _G.JustEvade and _G.JustEvade:Evading() or (_G.ExtLibEvade and _G.ExtLibEvade.Evading) or Game.IsChatOpen() or myHero.dead then return end
    target = GetTarget(1400)
    AARange = _G.SDK.Data:GetAutoAttackRange(myHero)
	if target then
        EAARange = _G.SDK.Data:GetAutoAttackRange(target)
    end
    if target and ValidTarget(target) then
        --PrintChat(target.pos:To2D())
        --PrintChat(mousePos:To2D())
        GaleMouseSpot = self:RangedHelper(target)
    else
        _G.SDK.Orbwalker.ForceMovement = nil
    end
	CastingQ = myHero.activeSpell.name == "KaisaQ"
	CastingW = myHero.activeSpell.name == "KaisaW"
	CastingE = myHero.activeSpell.name == "KaisaE"
	CastingR = myHero.activeSpell.name == "KaisaR"
    self:Logic()
	self:Auto()
	self:LastHit()
	self:LaneClear()
	self:Healing()
    if EnemyLoaded == false then
        local CountEnemy = 0
        for i, enemy in pairs(EnemyHeroes) do
            CountEnemy = CountEnemy + 1
        end
        if CountEnemy < 1 then
            GetEnemyHeroes()
        else
			self:MenuEvade()
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
		local WRange = 1400 + myHero.boundingRadius + enemy.boundingRadius 
		if enemy and not enemy.dead and ValidTarget(enemy, WRange) and self:CanUse(_W, "KS") and self:CastingChecks() and not _G.SDK.Attack:IsActive() then
			local WDamage = GetWDmg(enemy)
			WPrediction:GetPrediction(enemy, myHero)
			if WPrediction:CanHit(HITCHANCE_HIGH) and GetDistance(WPrediction.CastPosition) < WRange and enemy.health < WDamage then
				Control.CastSpell(HK_W, WPrediction.CastPosition)
			end
		end
		local Bedrohungsreichweite = 250 + myHero.boundingRadius + enemy.boundingRadius
		if enemy and not enemy.dead and ValidTarget(enemy, Bedrohungsreichweite) and self:CanUse(_E, "ChargePeel") and self:CastingChecksE() and not _G.SDK.Attack:IsActive() then
			if GetDistance(enemy.pos) <= Bedrohungsreichweite and (enemy.ms * 0.8 > myHero.ms or enemy.pathing.isDashing) and IsFacing(enemy)then
				Control.CastSpell(HK_E)
			end
		end
		if self.Menu.Misc.HeaBar:Value() and myHero.health / myHero.maxHealth <= 0.3 and enemy.activeSpell.target == myHero.handle then
			if myHero:GetSpellData(SUMMONER_1).name == "SummonerHeal" and IsReady(SUMMONER_1)then
				Control.CastSpell(HK_SUMMONER_1)
			elseif myHero:GetSpellData(SUMMONER_2).name == "SummonerHeal" and IsReady(SUMMONER_2)then
				Control.CastSpell(HK_SUMMONER_2)
			end
			if myHero:GetSpellData(SUMMONER_1).name == "SummonerBarrier" and IsReady(SUMMONER_1) then
				Control.CastSpell(HK_SUMMONER_1)
			elseif myHero:GetSpellData(SUMMONER_2).name == "SummonerBarrier" and IsReady(SUMMONER_2) then
				Control.CastSpell(HK_SUMMONER_2)
			end
		end
		if self.Menu.Misc.Cleanse:Value() and IsImmobile(myHero) > 0.5 and enemy.activeSpell.target == myHero.handle then
			if myHero:GetSpellData(SUMMONER_1).name == "SummonerBoost" and IsReady(SUMMONER_1) then
				DelayAction(function() Control.CastSpell(HK_SUMMONER_1) end, 0.04)
			elseif myHero:GetSpellData(SUMMONER_2).name == "SummonerBoost" and IsReady(SUMMONER_2) then
				DelayAction(function() Control.CastSpell(HK_SUMMONER_2) end, 0.04)
			end
		end
		if (myHero:GetSpellData(SUMMONER_1).name == "SummonerBoost" and IsReady(SUMMONER_1)) or (myHero:GetSpellData(SUMMONER_2).name == "SummonerBoost" and IsReady(SUMMONER_2)) then
		
		else
			if self.Menu.Misc.QSS:Value() and GetItemSlot(myHero, 3140) > 0 and myHero:GetSpellData(GetItemSlot(myHero, 3140)).currentCd == 0 and IsImmobile(myHero) > 0.5 and enemy.activeSpell.target == myHero.handle then
				DelayAction(function() Control.CastSpell(ItemHotKey[GetItemSlot(myHero, 3140)]) end, 0.04)
			elseif self.Menu.Misc.QSS:Value() and GetItemSlot(myHero, 3139) > 0 and myHero:GetSpellData(GetItemSlot(myHero, 3139)).currentCd == 0 and IsImmobile(myHero) > 0.5 and enemy.activeSpell.target == myHero.handle then
				DelayAction(function() Control.CastSpell(ItemHotKey[GetItemSlot(myHero, 3139)]) end, 0.04)
			elseif self.Menu.Misc.QSS:Value() and GetItemSlot(myHero, 6035) > 0 and myHero:GetSpellData(GetItemSlot(myHero, 6035)).currentCd == 0 and IsImmobile(myHero) > 0.5 and enemy.activeSpell.target == myHero.handle then
				DelayAction(function() Control.CastSpell(ItemHotKey[GetItemSlot(myHero, 6035)]) end, 0.04)
			end
		end
        local EEAARange = _G.SDK.Data:GetAutoAttackRange(enemy)
		local AARange = _G.SDK.Data:GetAutoAttackRange(myHero)
            if self:CastingChecks() and not (myHero.pathing and myHero.pathing.isDashing) then  
                local BestGaleDodgeSpot = nil
				--PrintChat("Got Dodge Spot")
                if enemy and ValidTarget(enemy, GaleTargetRange) and (GetDistance(GaleMouseSpot, enemy.pos) < AARange or GetDistance(enemy.pos, myHero.pos) < AARange+150) then
                        BestGaleDodgeSpot = self:GaleDodge(enemy, GaleMouseSpot)	
                else
                        BestGaleDodgeSpot = self:GaleDodge(enemy)
                end
                if  BestGaleDodgeSpot ~= nil then
					if GetItemSlot(myHero, 6671) > 0 and self.Menu.Evade.EvadeGaFo:Value() and myHero:GetSpellData(GetItemSlot(myHero, 6671)).currentCd == 0 then
							Control.CastSpell(ItemHotKey[GetItemSlot(myHero, 6671)], BestGaleDodgeSpot)
                    elseif myHero:GetSpellData(SUMMONER_1).name == "SummonerFlash" and IsReady(SUMMONER_1) and self.Menu.Evade.EvadeFla:Value() and myHero.health/myHero.maxHealth <= 0.4 then
						Control.CastSpell(HK_SUMMONER_1, BestGaleDodgeSpot)
					elseif myHero:GetSpellData(SUMMONER_2).name == "SummonerFlash" and IsReady(SUMMONER_2) and self.Menu.Evade.EvadeFla:Value() and myHero.health/myHero.maxHealth <= 0.4 then
						Control.CastSpell(HK_SUMMONER_2, BestGaleDodgeSpot)
					end	
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
	local ERange = 525 + 300 + myHero.boundingRadius + target.boundingRadius
	
	
	if Mode() == "Combo" and target then
		if target and not target.dead and ValidTarget(target, QRange) and self:CanUse(_Q, "Combo") and self:CastingChecks() and not _G.SDK.Attack:IsActive() then
			if GetDistance(target.pos) < QRange then
				Control.CastSpell(HK_Q)
			end
		end
		if target and not target.dead and ValidTarget(target, WRange) and self:CanUse(_W, "Combo") and self:CastingChecks() and not _G.SDK.Attack:IsActive() then
			WPrediction:GetPrediction(target, myHero)
			if WPrediction:CanHit(HITCHANCE_HIGH) and GetDistance(WPrediction.CastPosition) < WRange and GetBuffStacks(target, "kaisapassivemarker") >= 3 then 
				Control.CastSpell(HK_W, WPrediction.CastPosition)
			end
		end
		if target and not target.dead and ValidTarget(target, ERange) and self:CanUse(_E, "Combo") and self:CastingChecksE() and not _G.SDK.Attack:IsActive() then
			if GetDistance(target.pos) < ERange and GetDistance(target.pos) > 525 + myHero.boundingRadius + target.boundingRadius and IsMyHeroFacing(target) then
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
		if target and not target.dead and ValidTarget(target, WRange) and self:CanUse(_W, "Harass") and self:CastingChecksE() and not _G.SDK.Attack:IsActive() then
			local pred = _G.PremiumPrediction:GetPrediction(myHero, target, WSpellData)
			WPrediction:GetPrediction(target, myHero)
			if WPrediction:CanHit(HITCHANCE_HIGH) and GetDistance(WPrediction.CastPosition) < WRange and GetBuffStacks(target, "kaisapassivemarker") >= 3 then 
				Control.CastSpell(HK_W, WPrediction.CastPosition)
			end
		end
	end
	if Mode() == "Flee" and target then
		if target and not target.dead and ValidTarget(target, ERange) and self:CanUse(_E, "Flee") and self:CastingChecksE() and not _G.SDK.Attack:IsActive() then
			if GetDistance(target.pos) < ERange and not IsMyHeroFacing(target) then
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
					if pred and _G.PremiumPrediction.HitChance.Low then
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
	
function Kaisa:Healing()
	if myHero.alive == false then return end 
	
	local ItemPot = GetItemSlot(myHero, 2003)
	local ItemRefill = GetItemSlot(myHero, 2031)
	local ItemCookie = GetItemSlot(myHero, 2010)
	--PrintChat(ItemRefill)
	if myHero.health / myHero.maxHealth <= 0.7 and not BuffActive(myHero, "Item2003") and self.Menu.Misc.Pots:Value() and ItemPot > 0 then
		Control.CastSpell(ItemHotKey[ItemPot])
	end
	if myHero.health / myHero.maxHealth <= 0.7 and not BuffActive(myHero, "ItemCrystalFlask") and self.Menu.Misc.Pots:Value() and myHero:GetItemData(ItemRefill).ammo > 0 and ItemRefill > 0 then
		Control.CastSpell(ItemHotKey[ItemRefill])
	end
	if (myHero.health / myHero.maxHealth <= 0.3 or myHero.mana / myHero.maxMana <= 0.2) and not BuffActive(myHero, "Item2010") and self.Menu.Misc.Pots:Value() and ItemCookie > 0 then
		Control.CastSpell(ItemHotKey[ItemCookie])
	end
	
end

function Kaisa:GaleDodge(enemy, HelperSpot) 
if enemy.activeSpell and enemy.activeSpell.valid then
        if enemy.activeSpell.target == myHero.handle then 

        elseif enemy.activeSpell.isStopped then
		
		else
            local SpellName = enemy.activeSpell.name
            if (self.Menu.Evade.EvadeSpells[enemy.charName] and self.Menu.Evade.EvadeSpells[enemy.charName][SpellName] and self.Menu.Evade.EvadeSpells[enemy.charName][SpellName]:Value()) or myHero.health/myHero.maxHealth <= 0.15 then




                local CastPos = enemy.activeSpell.startPos
                local PlacementPos = enemy.activeSpell.placementPos
                local width = 100
				local CastTime = enemy.activeSpell.startTime
				local TimeDif = Game.Timer() - CastTime
                if enemy.activeSpell.width > 0 then
                    width = enemy.activeSpell.width
                end
                local SpellType = "Linear"
                if SpellType == "Linear" and PlacementPos and CastPos and TimeDif >= 0.08 then

                    --PrintChat(CastPos)
                    local VCastPos = Vector(CastPos.x, CastPos.y, CastPos.z)
                    local VPlacementPos = Vector(PlacementPos.x, PlacementPos.y, PlacementPos.z)

                    local CastDirection = Vector((VCastPos-VPlacementPos):Normalized())
                    local PlacementPos2 = VCastPos - CastDirection * enemy.activeSpell.range

                    local TargetPos = Vector(enemy.pos)
                    local MouseDirection = Vector((myHero.pos-mousePos):Normalized())
                    local ScanDistance = width*2 + myHero.boundingRadius
                    local ScanSpot = myHero.pos - MouseDirection * ScanDistance
                    local ClosestSpot = Vector(self:ClosestPointOnLineSegment(myHero.pos, PlacementPos2, CastPos))
                    if HelperSpot then 
                        local ClosestSpotHelper = Vector(self:ClosestPointOnLineSegment(HelperSpot, PlacementPos2, CastPos))
                        if ClosestSpot and ClosestSpotHelper then
                            local PlacementDistance = GetDistance(myHero.pos, ClosestSpot)
                            local HelperDistance = GetDistance(HelperSpot, ClosestSpotHelper)
                            if PlacementDistance < width*2 + myHero.boundingRadius then
                                if HelperDistance > width*2 + myHero.boundingRadius then
                                    return HelperSpot
                                elseif self.Menu.Evade.EvadeCalc:Value() then
                                    local DodgeRange = width*2 + myHero.boundingRadius
                                    if DodgeRange < DodgeableRange then
                                        local DodgeSpot = self:GetDodgeSpot(CastPos, ClosestSpot, DodgeRange)
                                        if DodgeSpot ~= nil then
                                           --PrintChat("Dodging to Calced Spot")
                                            return DodgeSpot
                                        end
                                    end
                                end
                            end
                        end
                    else
                        if ClosestSpot then
                            local PlacementDistance = GetDistance(myHero.pos, ClosestSpot)
                            if PlacementDistance < width*2 + myHero.boundingRadius then
                                if self.Menu.Evade.EvadeCalc:Value() then
                                    local DodgeRange = width*2 + myHero.boundingRadius
                                    if DodgeRange < DodgeableRange then
                                        local DodgeSpot = self:GetDodgeSpot(CastPos, ClosestSpot, DodgeRange)
                                        if DodgeSpot ~= nil then
                                           --PrintChat("Dodging to Calced Spot")
                                            return DodgeSpot
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end    
    return nil
end

function Kaisa:ClosestPointOnLineSegment(p, p1, p2)
    local px = p.x
    local pz = p.z
    local ax = p1.x
    local az = p1.z
    local bx = p2.x
    local bz = p2.z
    local bxax = bx - ax
    local bzaz = bz - az
    local t = ((px - ax) * bxax + (pz - az) * bzaz) / (bxax * bxax + bzaz * bzaz)
    if (t < 0) then
        return p1, false
    end
    if (t > 1) then
        return p2, false
    end
    return {x = ax + t * bxax, z = az + t * bzaz}, true
end

function Kaisa:GetDodgeSpot(CastSpot, ClosestSpot, width)
    local DodgeSpot = nil
    local RadAngle1 = 90 * math.pi / 180
    local CheckPos1 = ClosestSpot + (CastSpot - ClosestSpot):Rotated(0, RadAngle1, 0):Normalized() * width
    local RadAngle2 = 270 * math.pi / 180
    local CheckPos2 = ClosestSpot + (CastSpot - ClosestSpot):Rotated(0, RadAngle2, 0):Normalized() * width

    if GetDistance(CheckPos1, mousePos) < GetDistance(CheckPos2, mousePos) then
        if GetDistance(CheckPos1, myHero.pos) < DodgeableRange then
            DodgeSpot = CheckPos1
        elseif GetDistance(CheckPos2, myHero.pos) < DodgeableRange then
            DodgeSpot = CheckPos2
        end
    else
        if GetDistance(CheckPos2, myHero.pos) < DodgeableRange then
            DodgeSpot = CheckPos2
        elseif GetDistance(CheckPos1, myHero.pos) < DodgeableRange then
            DodgeSpot = CheckPos1
        end
    end
    return DodgeSpot
end

function Kaisa:RangedHelper(unit)
    local EAARangel = _G.SDK.Data:GetAutoAttackRange(unit)
    local MoveSpot = nil
    local RangeDif = AARange - EAARangel
    local ExtraRangeDist = RangeDif + -50
    local ExtraRangeChaseDist = RangeDif + -150

    local ScanDirection = Vector((myHero.pos-mousePos):Normalized())
    local ScanDistance = GetDistance(myHero.pos, unit.pos) * 0.8
    local ScanSpot = myHero.pos - ScanDirection * ScanDistance
	

    local MouseDirection = Vector((unit.pos-ScanSpot):Normalized())
    local MouseSpotDistance = EAARangel + ExtraRangeDist
    if not IsFacing(unit) then
        MouseSpotDistance = EAARangel + ExtraRangeChaseDist
    end
    if MouseSpotDistance > AARange then
        MouseSpotDistance = AARange
    end

    local MouseSpot = unit.pos - MouseDirection * (MouseSpotDistance)
	local MouseDistance = GetDistance(unit.pos, mousePos)
    local GaleMouseSpotDirection = Vector((myHero.pos-MouseSpot):Normalized())
    local GalemouseSpotDistance = GetDistance(myHero.pos, MouseSpot)
    if GalemouseSpotDistance > 300 then
        GalemouseSpotDistance = 300
    end
    local GaleMouseSpoty = myHero.pos - GaleMouseSpotDirection * GalemouseSpotDistance
    MoveSpot = MouseSpot

    if MoveSpot then
        if GetDistance(myHero.pos, MoveSpot) < 50 or IsUnderEnemyTurret(MoveSpot) then
            _G.SDK.Orbwalker.ForceMovement = nil
        elseif self.Menu.RangedHelperWalk:Value() and GetDistance(myHero.pos, unit.pos) <= AARange-50 and (Mode() == "Combo" or Mode() == "Harass") and self:CastingChecks() and MouseDistance < 750 then
            _G.SDK.Orbwalker.ForceMovement = MoveSpot
        else
            _G.SDK.Orbwalker.ForceMovement = nil
        end
    end
    return GaleMouseSpoty
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
