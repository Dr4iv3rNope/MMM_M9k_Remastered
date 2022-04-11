MMM_M9k_IsBaseInstalled = true -- Absolutely avoid global variables like this whenever possible and if there is no way around it, make it as unique as possible.

SWEP.SlotPos = 1

SWEP.Spawnable = false
SWEP.AdminSpawnable = false

SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false

SWEP.DrawAmmo = true
SWEP.DrawCrosshair = true
SWEP.DrawWeaponInfoBox = false
SWEP.BounceWeaponIcon = false

SWEP.ViewModelFOV = 70
SWEP.ViewModelFlip = true

SWEP.HoldType = "pistol"

SWEP.Primary.Sound = ""
SWEP.Primary.Cone = 0.2
SWEP.Primary.Recoil = 10
SWEP.Primary.Damage = 10
SWEP.Primary.Spread = .01
SWEP.Primary.NumShots = 1
SWEP.Primary.RPM = 0
SWEP.Primary.ClipSize = 0
SWEP.Primary.DefaultClip = 0

SWEP.Primary.KickUp = 0
SWEP.Primary.KickDown = 0
SWEP.Primary.KickHorizontal = 0
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "none"

SWEP.Secondary.DefaultClip = 0
SWEP.Secondary.Ammo = "none"

SWEP.CanReload = false

SWEP.AimMul = 0.2
SWEP.LastCurTick = 0
SWEP.PrimaryAnimationInt = 0
SWEP.ShouldDoMoveSpread = true

SWEP._IsM9kRemasteredBased = true -- Required for the m9k_command_logic.lua

SWEP.MaxRicochet = 1
SWEP.RicochetCoin = 1

local effectData = EffectData()

local EjectShellTypes = { -- This is needed to simulate shell ejections when aiming down the sights.
	["pistol"] = "ShellEject",
	["smg"] = "RifleShellEject",
	["ar2"] = "RifleShellEject",
	["shotgun"] = "ShotgunShellEject"
}

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
	self.OurIndex = self:EntIndex()

	if SERVER and game.SinglePlayer() then -- In singleplayer we need to force the weapon to be equipped after spawning
		timer.Simple(0,function()
			if not IsValid(self) or not IsValid(self.Owner) then return end -- We need to abort when the owner already had the weapon!
			self.Owner:SelectWeapon(self:GetClass())
		end)
	end

	if CLIENT then
		self.WepSelectIcon = surface.GetTextureID(string.gsub("vgui/hud/name","name",self:GetClass()))

		if self.Owner == LocalPlayer() then
			self:SendWeaponAnim(ACT_VM_IDLE)

			if self.Owner:GetActiveWeapon() == self then -- Compat/Bugfix
				self:Equip()
				self:Deploy()
			end
		end
	end
end

function SWEP:Equip()
	if SERVER and not self.Owner:IsPlayer() then
		self:Remove()
		return
	end
end

function SWEP:Deploy()
	if SERVER and game.SinglePlayer() then self:CallOnClient("Deploy") end -- Make sure that it runs on the CLIENT!
	self:SetHoldType(self.HoldType)

	local vm = self.Owner:GetViewModel()
	if IsValid(vm) then -- This is required since the code should only run on the server or on the player holding the gun (Causes errors otherwise)
		self.CanReload = false
		self:SetNWBool("CanIronSights",false)
		self:SendWeaponAnim(ACT_VM_DRAW)

		local Dur = vm:SequenceDuration() + 0.1
		self:SetNextPrimaryFire(CurTime() + Dur)
		self:SetNextSecondaryFire(CurTime() + Dur)

		timer.Remove("MMM_M9k_Deploy_" .. self.OurIndex)
		timer.Create("MMM_M9k_Deploy_" .. self.OurIndex,Dur,1,function()
			if not IsValid(self) or not IsValid(self.Owner) or not IsValid(self.Owner:GetActiveWeapon()) or self.Owner:GetActiveWeapon():GetClass() ~= self:GetClass() then return end
			self:SetNWBool("CanIronSights",true)
			self.CanReload = true
		end)
	end

	return true
end

function SWEP:AttackAnimation()
	if not IsValid(self.Owner) then return end
	self.Owner:SetAnimation(PLAYER_ATTACK1)
end

function SWEP:ShootBulletInformation()
	local Spread = self.Primary.Spread

	if self.IronSightState and self.Owner:KeyDown(IN_ATTACK2) then
		Spread = Spread / 2
	end

	if self.ShouldDoMoveSpread then
		if self.Owner:GetVelocity():Length() > 100 then
			Spread = Spread * 6
		elseif self.Owner:KeyDown(IN_DUCK) then
			Spread = Spread / 2
		end
	end

	self:ShootBullet(self.Primary.Damage, self.Primary.Recoil, self.Primary.NumShots, Spread)
end

function SWEP:PrimaryAttack()
	if SERVER and game.SinglePlayer() then self:CallOnClient("PrimaryAttack") end -- Make sure that it runs on the CLIENT!

	local iCurTime = CurTime()

	if self.Owner:WaterLevel() == 3 then -- No weapons may fire underwater
		if SERVER then
			self:EmitSound("Weapon_Pistol.Empty")
		end

		self:SetNextPrimaryFire(iCurTime + 0.2)
		return
	end

	if self:CanPrimaryAttack() and (self:GetNextPrimaryFire() < iCurTime or game.SinglePlayer()) then
		self:SetNextPrimaryFire(iCurTime + (1 / (self.Primary.RPM / 60)))

		if self.IronSightState then -- Let us not play messy fire animations while aiming down the sights.. WE WANT TO SEE DAMMIT!
			self:SendWeaponAnim(ACT_VM_IDLE) -- Unfortunately this gets rid of the muzzleflash and brass ejection (So we need to simulate it.)

			if (CLIENT or (SERVER and game.SinglePlayer())) and IsFirstTimePredicted() then
				local vm = self.Owner:GetViewModel()
				local vmAttachment = vm:GetAttachment("1")

				if istable(vmAttachment) then
					effectData:SetScale(1)
					effectData:SetEntity(vm)
					effectData:SetMagnitude(1)
					effectData:SetAttachment(1)
					effectData:SetOrigin(vmAttachment.Pos)
					effectData:SetAngles(vmAttachment.Ang)
					util.Effect("CS_MuzzleFlash",effectData)

					local Shell = EjectShellTypes[self.HoldType] or false
					if Shell then
						vmAttachment = vm:GetAttachment("2")

						if istable(vmAttachment) then
							effectData:SetAttachment(2)
							effectData:SetOrigin(vmAttachment.Pos)
							effectData:SetAngles(vmAttachment.Ang)
							util.Effect(Shell,effectData)
						end
					end
				end
			end

			self.PrimaryAnimationInt = 3 -- Recoil.
		else
			self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
		end

		self:MuzzleFlash() -- IDK if this is really needed tbh

		if CLIENT and game.SinglePlayer() then return end

		self:TakePrimaryAmmo(1)
		self:ShootBulletInformation()
		self:AttackAnimation()
		self:EmitSound(self.Primary.Sound)
	end
end

function SWEP:ShootBullet(damage, _, num_bullets, aimcone)
	num_bullets = num_bullets or 1
	aimcone = aimcone or 0

	local bullet = {
		Num = num_bullets,
		Src = self.Owner:GetShootPos(),
		Dir = self.Owner:GetAimVector(),
		Spread = Vector(aimcone, aimcone, 0),
		Tracer = TRACER_LINE_AND_WHIZ,
		TracerName = "Tracer",
		Force = damage * 0.3,
		Damage = damage,
		Callback = function(attacker, tracedata, dmginfo)
			return self:RicochetCallback(0, attacker, tracedata, dmginfo)
		end
	}

	local KickUp = self.Primary.KickUp
	local KickDown = self.Primary.KickDown
	local KickHorizontal = self.Primary.KickHorizontal

	if self.Owner:KeyDown(IN_DUCK) then
		KickUp = self.Primary.KickUp / 2
		KickDown = self.Primary.KickDown / 2
		KickHorizontal = self.Primary.KickHorizontal / 2
	end

	local SharedRandom = Angle(util.SharedRandom("m9k_gun_kick1",-KickDown,-KickUp),util.SharedRandom("m9k_gun_kick2",-KickHorizontal,KickHorizontal),0)
	self.Owner:ViewPunch(SharedRandom) -- This needs to be shared

	if SERVER and game.SinglePlayer() or SERVER and self.Owner:IsListenServerHost() then -- This is specifically for the host or when in singleplayer
		local eyes = self.Owner:EyeAngles()
		eyes:SetUnpacked(eyes.pitch + SharedRandom.pitch,eyes.yaw + SharedRandom.yaw,0)
		self.Owner:SetEyeAngles(eyes)
	elseif CLIENT and not game.SinglePlayer() then -- This is for other players in multiplayer (Or anyone on the server if dedicated)
		local eyes = self.Owner:EyeAngles()
		eyes:SetUnpacked(eyes.pitch + (SharedRandom.pitch/5),eyes.yaw + (SharedRandom.yaw/5),0)
		self.Owner:SetEyeAngles(eyes)
	end

	self.Owner:FireBullets(bullet) -- The bullet always comes out last! (Stop messing with simple logic pls.)
end

function SWEP:SecondaryAttack()
	return false
end

function SWEP:CanPrimaryAttack() -- Required for Singleplayer
	if self.NextReloadClicksound and self.NextReloadClicksound > CurTime() then
		return
	end -- We don't want the click sound to destroy our ears when we don't have any ammo in the weapon and in reserve

	if self:Clip1() <= 0 then
		if IsFirstTimePredicted() then
			self:EmitSound("Weapon_Pistol.Empty")
			self:SetNextPrimaryFire(CurTime() + 0.2)
			self.NextReloadClicksound = CurTime() + 0.2

			if SERVER and game.SinglePlayer() then
				self:Reload()
			elseif not game.SinglePlayer() then  -- We want to call reload in both realms if it is multiplayer, otherwise we can reload out of prediction and cause problems!
				self:Reload()
			end
		end

		return false
	end

	return true
end

function SWEP:Reload()
	if SERVER and game.SinglePlayer() then self:CallOnClient("Reload") end -- Make sure that it runs on the CLIENT!

	if self.CanReload and self.Owner:GetAmmoCount(self.Primary.Ammo) >= 1 and self:Clip1() < self.Primary.ClipSize then
		if self.IronSightState then
			self.Owner:SetFOV(0,0.3)
			self.IronSightState = false
			self.DrawCrosshair = true
		end

		self.Owner:SetAnimation(PLAYER_RELOAD)
		self:DefaultReload(ACT_VM_RELOAD)

		if SERVER then
			local vm = self.Owner:GetViewModel()

			if IsValid(vm) then
				self:SetNWBool("CanIronSights",false)

				timer.Simple(vm:SequenceDuration() + 0.1,function()
					if not IsValid(self) or not IsValid(self.Owner) or not IsValid(self.Owner:GetActiveWeapon()) or self.Owner:GetActiveWeapon():GetClass() ~= self:GetClass() then return end
					self:SetNWBool("CanIronSights",true)
				end)
			end
		end
	end
end

function SWEP:Holster()
	if SERVER and game.SinglePlayer() then self:CallOnClient("Holster") end -- Make sure that it runs on the CLIENT!
	if not SERVER and self.Owner ~= LocalPlayer() then return end

	if self.IronSightState then
		self.Owner:SetFOV(0,0.3)
		self.IronSightState = false
		self.DrawCrosshair = true
	end

	return true
end

function SWEP:IronSight()
	if self.Owner:GetViewEntity() ~= self.Owner or not self:GetNWBool("CanIronSights") then return end

	if self.Owner:KeyPressed(IN_ATTACK2) and not self.IronSightState then
		self.Owner:SetFOV(80,0.2)
		self.IronSightState = true
		self.DrawCrosshair = false
		self.LastCurTick = RealTime()
	elseif self.Owner:KeyReleased(IN_ATTACK2) then
		self.Owner:SetFOV(0,0.1)
		self.IronSightState = false
		self.DrawCrosshair = true
	end
end

function SWEP:Think()
	self:IronSight()
end

if CLIENT then
	function SWEP:CalcViewModelView(ViewModel,pos,ang,EyePos,EyeAng)
		if not IsValid(self.Owner) then return end

		if not self.IronSightState and not self.IronSightsPos or (not self.IronSightState and self.AimMul <= 0) then -- This reduces the non-ironsighted sway
			pos:SetUnpacked(pos.x + (EyePos.x - pos.x) * 0.75,pos.y + (EyePos.y - pos.y) * 0.75,pos.z + (EyePos.z - pos.z) * 0.75)
			ang:SetUnpacked(ang.p + (EyeAng.p - ang.p) * 0.75,ang.y + (EyeAng.y - ang.y) * 0.75,ang.r + EyeAng.r * 0.75)

			return pos, ang
		end

		-- We do want a bit of sway just not so extreme
		pos:SetUnpacked(pos.x + (EyePos.x - pos.x) * 0.05,pos.y + (EyePos.y - pos.y) * 0.05,pos.z + (EyePos.z - pos.z) * 0.05)
		ang:SetUnpacked(ang.p + (EyeAng.p - ang.p) * 0.25,ang.y + (EyeAng.y - ang.y) * 0.25,ang.r + EyeAng.r * 0.25)

		self.AimMul = self.IronSightState and (self.AimMul + math.abs(self.LastCurTick - RealTime())*5) or (self.AimMul - math.abs(self.LastCurTick - RealTime())*5)

		self.AimMul = math.Clamp(self.AimMul,0,1)
		self.LastCurTick = RealTime()

		if self.IronSightsAng then
			ang:RotateAroundAxis(ang:Right(),self.IronSightsAng.x * self.AimMul)
			ang:RotateAroundAxis(ang:Up(),self.IronSightsAng.y * self.AimMul)
			ang:RotateAroundAxis(ang:Forward(),self.IronSightsAng.z * self.AimMul)
		end

		pos = pos + self.IronSightsPos.x * ang:Right() * self.AimMul
		pos = pos + self.IronSightsPos.y * ang:Forward() * self.AimMul - (ang:Forward() * math.Clamp(self.PrimaryAnimationInt,0,10))
		pos = pos + self.IronSightsPos.z * ang:Up() * self.AimMul

		if self.PrimaryAnimationInt >= 0 then
			self.PrimaryAnimationInt = self.PrimaryAnimationInt - 0.05
		end

		return pos, ang
	end

	function SWEP:FireAnimationEvent(_,_,event)
		if event == 5001 or event == 5011 or event == 5021 or event == 5031 then
			if self.Owner:GetViewEntity() ~= self.Owner then return true end
			local vm = self.Owner:GetViewModel()
			if not IsValid(vm) then return end

			local vmAttachment = vm:GetAttachment("1")
			if not istable(vmAttachment) then return end

			effectData:SetAttachment(1)
			effectData:SetEntity(vm)
			effectData:SetScale(1)
			effectData:SetMagnitude(1)
			effectData:SetOrigin(vmAttachment.Pos)
			effectData:SetAngles(vmAttachment.Ang)
			util.Effect("CS_MuzzleFlash",effectData)

			return true
		end
	end
end

local bulletmiss = {
	Sound("weapons/fx/nearmiss/bulletLtoR03.wav"),
	Sound("weapons/fx/nearmiss/bulletLtoR04.wav"),
	Sound("weapons/fx/nearmiss/bulletLtoR06.wav"),
	Sound("weapons/fx/nearmiss/bulletLtoR07.wav"),
	Sound("weapons/fx/nearmiss/bulletLtoR09.wav"),
	Sound("weapons/fx/nearmiss/bulletLtoR10.wav"),
	Sound("weapons/fx/nearmiss/bulletLtoR13.wav"),
	Sound("weapons/fx/nearmiss/bulletLtoR14.wav")
}

local RicochetTable = {
	["SniperPenetratedRound"]	= 12,
	["pistol"]					= 2,
	["357"]						= 4,
	["smg1"]					= 5,
	["ar2"]						= 8,
	["buckshot"]				= 1,
	["slam"]					= 1,
	["AirboatGun"]				= 8,
}

function SWEP:RicochetCallback(bouncenum, attacker, tr, dmginfo)
	if not IsFirstTimePredicted() then
		return { damage = false, effects = false }
	end

	local DoDefaultEffect = true
	if (tr.HitSky) then return end

	-- -- Can we go through whatever we hit?
	if (self:BulletPenetrate(bouncenum, attacker, tr, dmginfo)) then
		return { damage = true, effects = DoDefaultEffect }
	end

	-- -- Your screen will shake and you'll hear the savage hiss of an approaching bullet which passing if someone is shooting at you.
	if (tr.MatType ~= MAT_METAL) then
		if (SERVER) then
			util.ScreenShake(tr.HitPos, 5, 0.1, 0.5, 64)
			sound.Play(bulletmiss[math.random(1, #bulletmiss)], tr.HitPos, 75, math.random(75,150), 1)
		end

		if type(tr.Tracer) == "number" then
			local effectdata = EffectData()
			effectdata:SetOrigin(tr.HitPos)
			effectdata:SetNormal(tr.HitNormal)
			effectdata:SetScale(20)

			if tr.Tracer >= 0 and tr.Tracer <= 2 then
				util.Effect("AR2Impact", effectdata)
			elseif tr.Tracer == 3 then
				util.Effect("StunstickImpact", effectdata)
			end
		end

		return
	end

	if (self.Ricochet == false) then return {damage = true, effects = DoDefaultEffect} end

	self.MaxRicochet = RicochetTable[self.Primary.Ammo] or 1

	if (bouncenum > self.MaxRicochet) then return end

 	local DotProduct = tr.HitNormal:Dot(tr.Normal * -1)

	local ricochetbullet = {
		Num			= 1,
		Src			= tr.HitPos + (tr.HitNormal * 5),
		Dir			= ((2 * tr.HitNormal * DotProduct) + tr.Normal) + (VectorRand() * 0.05),
		Spread		= Vector(0, 0, 0),
		Tracer		= 1,
		TracerName	= "m9k_effect_mad_ricochet_trace",
		Force		= dmginfo:GetDamage() * 0.15,
		Damage		= dmginfo:GetDamage() * 0.5,
		Callback		= function(...)
			if (self.Ricochet) then
				local impactnum = tr.MatType == MAT_GLASS and 0 or 1

				return self:RicochetCallback(bouncenum + impactnum, ...)
			end
		end
	}

	timer.Simple(0, function() attacker:FireBullets(ricochetbullet) end)

	return {damage = true, effects = DoDefaultEffect}
end

local MaxPenetrationTable = {
	["SniperPenetratedRound"]	= 20,
	["pistol"]					= 9,
	["357"]						= 12,
	["smg1"]					= 14,
	["ar2"]						= 16,
	["buckshot"]				= 5,
	["slam"]					= 5,
	["AirboatGun"]				= 17,
}

local MaxRicochetTable = {
	["SniperPenetratedRound"]	= 10,
	["pistol"]					= 2,
	["357"]						= 5,
	["smg1"]					= 4,
	["ar2"]						= 5,
	["buckshot"]				= 0,
	["slam"]					= 0,
	["AirboatGun"]				= 8
}

local DamageMultiplierTable = {
	[MAT_CONCRETE] =	0.3,
	[MAT_METAL] =		0.3,
	[MAT_WOOD] =		0.8,
	[MAT_PLASTIC] =		0.8,
	[MAT_GLASS] =		0.8,
	[MAT_FLESH] =		0.9,
	[MAT_ALIENFLESH] =	0.9,
}

local DoublePenetrationTable = {
	[MAT_GLASS] =		true,
	[MAT_PLASTIC] =		true,
	[MAT_WOOD] =		true,
	[MAT_FLESH] =		true,
	[MAT_ALIENFLESH] =	true
}

function SWEP:BulletPenetrate(bouncenum, attacker, tr, paininfo)
	local MaxPenetration = MaxPenetrationTable[self.Primary.Ammo] or 5

	if
		self.Primary.Ammo == "pistol" or
		self.Primary.Ammo == "buckshot" or
		self.Primary.Ammo == "slam"
	then
		self.Ricochet = true
	else
		if self.RicochetCoin == 1 then
			self.Ricochet = true
		elseif self.RicochetCoin >= 2 then
			self.Ricochet = false
		end
	end

	if self.Primary.Ammo == "SniperPenetratedRound" then self.Ricochet = true end

	self.MaxRicochet = MaxRicochetTable[self.Primary.Ammo] or 1

	if (tr.MatType == MAT_METAL and self.Ricochet == true and self.Primary.Ammo ~= "SniperPenetratedRound" ) then return false end

	-- Don't go through more than 3 times
	if (bouncenum > self.MaxRicochet) then return false end

	-- Direction (and length) that we are going to penetrate
	local PenetrationDirection = tr.Normal * MaxPenetration

	if DoublePenetrationTable[tr.MatType] then
		PenetrationDirection = tr.Normal * (MaxPenetration * 2)
	end

	local trace = util.TraceLine({
		endpos	= tr.HitPos,
		start	= tr.HitPos + PenetrationDirection,
		mask	= MASK_SHOT,
		filter	= self.Owner
	})

	-- Bullet didn't penetrate.
	if (trace.StartSolid or trace.Fraction >= 1.0 or tr.Fraction <= 0.0) then return false end

	-- Damage multiplier depending on surface
	local damageMul = 0.5

	if self.Primary.Ammo == "SniperPenetratedRound" then
		damageMul = 1
	else
		damageMul = DamageMultiplierTable[tr.MatType] or damageMul
	end

	-- Fire bullet from the exit point using the original trajectory
	local penetratedbullet = {
		Num			= 1,
		Src			= trace.HitPos,
		Dir			= tr.Normal,
		Spread		= Vector(0, 0, 0),
		Tracer		= 2,
		TracerName	= "m9k_effect_mad_penetration_trace",
		Force		= 5,
		Damage		= paininfo:GetDamage() * damageMul,
		Callback	= function(...)
			if (self.Ricochet) then

				local impactnum = tr.MatType == MAT_GLASS and 0 or 1

				return self:RicochetCallback(bouncenum + impactnum, ...)
			end
		end
	}

	timer.Simple(0, function()
		if attacker ~= nil then
			attacker:FireBullets(penetratedbullet)
		end
	end)

	return true
end
