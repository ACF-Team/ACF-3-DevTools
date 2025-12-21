if SERVER then ACF_PHYSICSVISTEST_LASTREQUESTEDENTS = ACF_PHYSICSVISTEST_LASTREQUESTEDENTS or {} end
local RequestedEnts = SERVER and ACF_PHYSICSVISTEST_LASTREQUESTEDENTS or nil

local EntityKeyValues = ACF_DevTools.EntityKeyValues

local function ProcessLastTyped(Player, Request)
	local LUT = {}
	local Pieces = string.Split(Request, " ")
	for _, Piece in ipairs(Pieces) do
		local Idx = tonumber(Piece)
		if Idx then LUT[Idx] = true end
	end

	if SERVER then
		if #Pieces == 0 then
			RequestedEnts[Player] = nil
		else
			RequestedEnts[Player] = LUT
		end
		Player:ChatPrint("Now tracking: " .. table.concat(table.GetKeys(LUT), ", "))
	else
		if #Pieces == 0 then
			RequestedEnts = nil
		else
			RequestedEnts = LUT
		end
	end
end

if SERVER then
	concommand.Add("acf_physicsvistest", function(Player, _, _, Request)
		if Player == NULL then print("Cannot use this command from a dedicated server!") return end
		ProcessLastTyped(Player, Request)
	end, nil, "ACF physics visualizer for testing", FCVAR_USERINFO)
end

if SERVER then
	util.AddNetworkString("ACF_PhysVisData")
	local LastUpdateTime = 0
	local function NetworkPlayer(Player, LUT)
		net.Start("ACF_PhysVisData")
		net.WriteUInt(table.Count(LUT), 6)
		for EntIdx in pairs(LUT) do
			local Ent = Entity(EntIdx)
			if not IsValid(Ent) then net.WriteBool(false) continue end

			net.WriteBool(true)
			net.WriteUInt(EntIdx, MAX_EDICT_BITS)
			local PhysicsObjects = math.min(Ent:GetPhysicsObjectCount(), 63)
			net.WriteUInt(PhysicsObjects, 6)
			for i = 1, PhysicsObjects do
				local PhysObj = Ent:GetPhysicsObjectNum(i - 1)
				if not IsValid(PhysObj) then net.WriteBool(false) continue end
				net.WriteBool(true)
				net.WriteUInt(i, 6)
				net.WriteVector(Ent:WorldToLocal(PhysObj:GetPos()))
				net.WriteAngle(Ent:WorldToLocalAngles(PhysObj:GetAngles()))
				net.WriteVector(PhysObj:GetVelocity())
				net.WriteVector(PhysObj:GetAngleVelocity())
				net.WriteFloat(PhysObj:GetMass())
				local IS, ES = PhysObj:GetStress()
				net.WriteFloat(IS)
				net.WriteFloat(ES)
				net.WriteUInt(PhysObj:GetContents(), 32)
				local LD, AD = PhysObj:GetDamping()
				net.WriteFloat(LD)
				net.WriteFloat(AD)
				net.WriteFloat(PhysObj:GetEnergy())
				net.WriteVector(PhysObj:GetInertia())
				net.WriteVector(PhysObj:GetMassCenter())
				net.WriteString(PhysObj:GetMaterial())
				net.WriteFloat(PhysObj:GetSpeedDamping())
				net.WriteFloat(PhysObj:GetRotDamping())
				net.WriteAngle(PhysObj:GetShadowAngles())
				net.WriteVector(PhysObj:GetShadowPos())
				net.WriteFloat(PhysObj:GetSurfaceArea() or -1)
				net.WriteFloat(PhysObj:GetVolume() or -1)
				net.WriteBool(PhysObj:IsAsleep())
				net.WriteBool(PhysObj:IsCollisionEnabled())
				net.WriteBool(PhysObj:IsDragEnabled())
				net.WriteBool(PhysObj:IsGravityEnabled())
				net.WriteBool(PhysObj:IsMotionEnabled())
				net.WriteBool(PhysObj:IsMoveable())
				net.WriteBool(PhysObj:IsPenetrating())
			end
		end
		net.Send(Player)
	end
	local function DoPhysVis()
		local Now = CurTime()
		local Delta = Now - LastUpdateTime
		if Delta > 0.05 then
			for Player, LUT in pairs(RequestedEnts) do
				if IsValid(Player) then
					NetworkPlayer(Player, LUT)
				end
			end
			LastUpdateTime = Now
		end
	end

	hook.Add("Think", "ACF_FunDebuggingFuncs_PhysVis", DoPhysVis)
else
	local PhysData = {}
	hook.Add("ACF_DevTools_QueryPhysObjLocalPosition", "PhysVisProvider", function(EntIdx, PhysIdx)
		local Test = PhysData[EntIdx]
		if Test then
			Test = Test[PhysIdx]
			if Test then return Test.Position end
		end
	end)

	net.Receive("ACF_PhysVisData", function()
		table.Empty(PhysData)
		local Ents = net.ReadUInt(6)
		for _ = 1, Ents do
			local Valid = net.ReadBool()
			if not Valid then continue end

			local LUT = {}
			local EntIdx = net.ReadUInt(MAX_EDICT_BITS)
			local Objects = net.ReadUInt(6)

			for PhysIdx = 1, Objects do
				local ValidPhys = net.ReadBool()
				local PhysObjIdx = net.ReadUInt(6)
				local Category, ExistedBefore = EntityKeyValues.GetPhysObjCategory(EntIdx, PhysObjIdx, "Physics Information")
				if not ExistedBefore then
					Category.Collapsed = true
				end
				Category = Category.Data
				Category.ValidPhys = ValidPhys
				Category.Index = ValidPhys and PhysObjIdx
				Category.Position = ValidPhys and net.ReadVector()
				Category.Angles = ValidPhys and net.ReadAngle()
				Category.Velocity = ValidPhys and net.ReadVector()
				Category.AngularVelocity = ValidPhys and net.ReadVector()
				Category.Mass = ValidPhys and net.ReadFloat()
				Category.InternalStress = ValidPhys and net.ReadFloat()
				Category.ExternalStress = ValidPhys and net.ReadFloat()
				Category.Contents = ValidPhys and net.ReadUInt(32)
				Category.LinearDamping = ValidPhys and net.ReadFloat()
				Category.AngularDamping = ValidPhys and net.ReadFloat()
				Category.Energy = ValidPhys and net.ReadFloat()
				Category.AngularInertia = ValidPhys and net.ReadVector()
				Category.MassCenter = ValidPhys and net.ReadVector()
				Category.Material = ValidPhys and net.ReadString()
				Category.SpeedDamping = ValidPhys and net.ReadFloat()
				Category.RotationDamping = ValidPhys and net.ReadFloat()
				Category.ShadowPosition = ValidPhys and net.ReadVector()
				Category.ShadowAngles = ValidPhys and net.ReadAngle()
				Category.SurfaceArea = ValidPhys and net.ReadFloat()
				Category.Volume = ValidPhys and net.ReadFloat()

				local Flags = ""
				if ValidPhys and net.ReadBool() then Flags = Flags .. "asleep " end
				if ValidPhys and net.ReadBool() then Flags = Flags .. "collisions " end
				if ValidPhys and net.ReadBool() then Flags = Flags .. "drag " end
				if ValidPhys and net.ReadBool() then Flags = Flags .. "gravity " end
				if ValidPhys and net.ReadBool() then Flags = Flags .. "motion " end
				if ValidPhys and net.ReadBool() then Flags = Flags .. "moveable " end
				if ValidPhys and net.ReadBool() then Flags = Flags .. "penetrating " end
				Category.Flags = string.Trim(Flags)

				local Obj = {Position = Category.Position, Velocity = Category.Velocity}
				LUT[PhysObjIdx] = Obj
			end
			PhysData[EntIdx] = LUT
		end
	end)

	local BeamColor = Color(255, 61, 61)

	hook.Add("PostDrawTranslucentRenderables", "ACF_FunDebuggingFuncs_PhysVis", function()
		for EntIdx, EntPhys in pairs(PhysData) do
			local Ent = Entity(EntIdx)
			if not IsValid(Ent) then continue end

			for _, PhysObj in ipairs(EntPhys) do
				if not PhysObj.Position or not PhysObj.Velocity then continue end
				local Pos = Ent:LocalToWorld(PhysObj.Position)

				render.SetColorMaterial()
				ACF.DrawOutlineBeam(2, BeamColor, Pos, Pos + PhysObj.Velocity)
			end
		end
	end)
end