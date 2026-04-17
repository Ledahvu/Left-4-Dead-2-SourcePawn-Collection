// <[L4D2] Tank Earthquake Jump> - <The tank jumps high, charges into the Survivor, causes an earthquake that deals damage, knocks back, shakes the screen, and slows down time.>
// Copyright (C) <2026> <Vũ Trường Tuyền>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define L4D_Z_MULT 1.0
#define INVALID_CLIENT 0

public Plugin myinfo =
{
	name = "[L4D2] Tank Earthquake Jump",
	author = "Tyn Zũ",
	description = "Tank nhảy cao, lao vào Survivor, tạo động đất gây sát thương, đẩy văng, rung màn hình và làm chậm thời gian",
	version = "2.1.0",
	url = ""
};

// ============================================================================
// Globals
// ============================================================================
bool g_bL4D2;
bool g_bEnabled;
bool g_bHooked;

int g_iJumperTank = INVALID_CLIENT;
float g_fJumpChange[MAXPLAYERS+1];
bool g_bJumper[MAXPLAYERS+1];
bool g_bDelayJump[MAXPLAYERS+1];
Handle g_iTimerJump[MAXPLAYERS+1];

// ConVar handles
ConVar g_hCvarJumperEnable;
ConVar g_hCvarDamageSingle;
ConVar g_hCvarDamageMulti;
ConVar g_hCvarForceSingle;
ConVar g_hCvarAngleSingle;
ConVar g_hCvarForceMulti;
ConVar g_hCvarAngleMulti;
ConVar g_hCvarRadius;
ConVar g_hCvarRange;
ConVar g_hCvarChance;
ConVar g_hCvarShake;
ConVar g_hCvarSlow;
ConVar g_hCvarSlowSpeed;
ConVar g_hCvarTargetForce;

// Cached values
float g_fDamageSingle;
float g_fDamageMulti;
float g_fForceSingle;
float g_fAngleSingle;
float g_fForceMulti;
float g_fAngleMulti;
int   g_iRadius;
float g_fRange;
float g_fChance;
float g_fShake;
float g_fSlow;
float g_fSlowSpeed;
float g_fTargetForce;

float g_fResulting[3];

// Slow motion
ConVar host_timescale;
ConVar sv_cheats;
Handle g_hSlowMotionTimer = null;
float g_fOriginalTimescale = 1.0;
bool g_bTimescaleFixEnabled = false;

// ============================================================================
// Plugin Forwards
// ============================================================================

public void OnPluginStart()
{

	// ConVars
	g_hCvarJumperEnable = CreateConVar("l4d_tank_earthquake_jump_enable", "1", "Bật/tắt tính năng nhảy động đất của Tank?");
	g_hCvarDamageSingle = CreateConVar("l4d_tank_earthquake_jump_damage_single", "10.0", "Sát thương mỗi Survivor nhận từ cú nhảy trực tiếp");
	g_hCvarDamageMulti = CreateConVar("l4d_tank_earthquake_jump_damage_multiple_target", "1.0", "Hệ số nhân sát thương cho nhiều mục tiêu");
	g_hCvarForceSingle = CreateConVar("l4d_tank_earthquake_jump_force_single", "300.0", "Lực đẩy cho một Survivor");
	g_hCvarAngleSingle = CreateConVar("l4d_tank_earthquake_jump_angle_single", "300.0", "Góc đẩy thẳng đứng (càng cao càng hất lên)");
	g_hCvarForceMulti = CreateConVar("l4d_tank_earthquake_jump_force_multiple_target", "1.0", "Hệ số nhân lực đẩy cho nhiều mục tiêu");
	g_hCvarAngleMulti = CreateConVar("l4d_tank_earthquake_jump_vertical_multi", "0.1", "Hệ số nhân lực đẩy thẳng đứng cho nhiều mục tiêu");
	g_hCvarRadius = CreateConVar("l4d_tank_earthquake_jump_radius", "400", "Bán kính hiệu ứng động đất diện rộng");
	g_hCvarRange = CreateConVar("l4d_tank_earthquake_jump_range", "10000000", "Phạm vi sát thương trực tiếp khi tiếp đất");
	g_hCvarChance = CreateConVar("l4d_tank_earthquake_jump_cool_down", "15", "Thời gian hồi chiêu giữa các lần nhảy (giây)");
	g_hCvarShake = CreateConVar("l4d_tank_earthquake_jump_shaking_intensity", "20.0", "Cường độ rung màn hình", _, true, 0.0, true, 100.0);
	g_hCvarSlow = CreateConVar("l4d_tank_earthquake_jump_slow_motion_time", "3.0", "Thời gian làm chậm (giây)");
	g_hCvarSlowSpeed = CreateConVar("l4d_tank_earthquake_jump_slow_motion_speed", "0.1", "Tốc độ làm chậm", _, true, 0.03, true, 1.0);
	g_hCvarTargetForce = CreateConVar("l4d_tank_earthquake_jump_target_force", "500.0", "Lực lao ngang về phía Survivor mục tiêu");

	AutoExecConfig(true, "l4d_tank_earthquake_jump", "sourcemod");
	
	// Event hooks
	HookEvent("round_start_post_nav", Event_RoundStartPostNav);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("round_start", Event_RoundStart);

	// ConVar change callbacks
	g_hCvarJumperEnable.AddChangeHook(OnConVarChanged);
	g_hCvarDamageSingle.AddChangeHook(OnConVarChanged);
	g_hCvarDamageMulti.AddChangeHook(OnConVarChanged);
	g_hCvarForceSingle.AddChangeHook(OnConVarChanged);
	g_hCvarAngleSingle.AddChangeHook(OnConVarChanged);
	g_hCvarForceMulti.AddChangeHook(OnConVarChanged);
	g_hCvarAngleMulti.AddChangeHook(OnConVarChanged);
	g_hCvarRadius.AddChangeHook(OnConVarChanged);
	g_hCvarRange.AddChangeHook(OnConVarChanged);
	g_hCvarChance.AddChangeHook(OnConVarChanged);
	g_hCvarShake.AddChangeHook(OnConVarChanged);
	g_hCvarSlow.AddChangeHook(OnConVarChanged);
	g_hCvarSlowSpeed.AddChangeHook(OnConVarChanged);
	g_hCvarTargetForce.AddChangeHook(OnConVarChanged);

	// Setup slow motion
	host_timescale = FindConVar("host_timescale");
	sv_cheats = FindConVar("sv_cheats");
	
	if (host_timescale == null)
		SetFailState("Không tìm thấy host_timescale");
	if (sv_cheats == null)
		SetFailState("Không tìm thấy sv_cheats");
		
	EnableTimescaleFix();
	g_fOriginalTimescale = GetConVarFloat(host_timescale);
	HookConVarChange(host_timescale, OnTimescaleChanged);

	GetCvars();
}

public void OnMapStart()
{
	PrecacheEffect("ParticleEffect");
	PrecacheGeneric("particles/environment_fx.pcf", true);
	PrecacheParticleEffect("aircraft_destroy_fastFireTrail");
	PrecacheParticleEffect("sheetrock");
	PrecacheParticleEffect("fire_medium_01");               // Thay thế cho gas_explosion
	PrecacheModel("models/props_debris/concrete_chunk01a.mdl", true); // Precache model đá
	
	if (host_timescale != null)
		SetConVarFloat(host_timescale, 1.0);
}

public void OnMapEnd()
{
	ClearAllTimers();
	
	if (host_timescale != null)
		SetConVarFloat(host_timescale, 1.0);
}

public void OnConfigsExecuted()
{
	GetCvars();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	GetCvars();
}

// ============================================================================
// Slow Motion
// ============================================================================
void EnableTimescaleFix()
{
	if (host_timescale == null)
		return;
		
	int flags = GetConVarFlags(host_timescale);
	if (flags & FCVAR_CHEAT)
	{
		SetConVarFlags(host_timescale, flags & ~FCVAR_CHEAT);
		g_bTimescaleFixEnabled = true;
	}
	
	if (sv_cheats != null)
	{
		flags = GetConVarFlags(sv_cheats);
		if (flags & FCVAR_CHEAT)
			SetConVarFlags(sv_cheats, flags & ~FCVAR_CHEAT);
	}
}

public void OnTimescaleChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!g_bTimescaleFixEnabled)
		return;
		
	float timescale = StringToFloat(newValue);
	
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client))
		{
			if (timescale != 1.0)
				SendConVarValue(client, sv_cheats, "1");
			else
				SendConVarValue(client, sv_cheats, "0");
		}
	}
}

void SetSlowMotion(float duration, float speed)
{
	if (host_timescale == null)
		return;
		
	if (g_hSlowMotionTimer != null)
	{
		KillTimer(g_hSlowMotionTimer);
		g_hSlowMotionTimer = null;
	}
	
	if (speed < 0.03)
		speed = 0.03;
	if (speed > 1.0)
		speed = 1.0;
		
	SetConVarFloat(host_timescale, speed);
	
	if (duration > 0.0)
	{
		DataPack dp = new DataPack();
		dp.WriteFloat(g_fOriginalTimescale);
		g_hSlowMotionTimer = CreateTimer(duration, Timer_RestoreTimescale, dp, TIMER_DATA_HNDL_CLOSE);
	}
}

Action Timer_RestoreTimescale(Handle timer, DataPack dp)
{
	dp.Reset();
	float originalSpeed = dp.ReadFloat();
	
	if (host_timescale != null)
	{
		SetConVarFloat(host_timescale, originalSpeed);
	}
	
	g_hSlowMotionTimer = null;
	return Plugin_Stop;
}

void ResetTimescale()
{
	if (host_timescale != null)
	{
		SetConVarFloat(host_timescale, g_fOriginalTimescale);
	}
	
	if (g_hSlowMotionTimer != null)
	{
		KillTimer(g_hSlowMotionTimer);
		g_hSlowMotionTimer = null;
	}
}

// ============================================================================
// Events
// ============================================================================
public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int tank = GetClientOfUserId(userid);
	if (g_bEnabled && tank > 0)
	{
		SetEntityGravity(tank, 2.0);
		DataPack dp = new DataPack();
		dp.WriteCell(userid);
		dp.WriteFloat(g_fChance);
		dp.WriteCell(tank);
		g_iTimerJump[tank] = CreateTimer(g_fChance, Timer_Jump, dp, TIMER_REPEAT|TIMER_DATA_HNDL_CLOSE);
		g_fJumpChange[tank] = GetEngineTime();
		g_bJumper[tank] = true;
		g_iJumperTank = tank;
	}
	else
	{
		g_bJumper[tank] = false;
		if (tank == g_iJumperTank)
			g_iJumperTank = INVALID_CLIENT;
	}
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	ResetTimescale();
	ClearAllTimers();
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	ResetTimescale();
}

public void Event_RoundStartPostNav(Event event, const char[] name, bool dontBroadcast)
{
	ResetTimescale();
}

// ============================================================================
// Command
// ============================================================================
public Action CmdHulk(int client, int args)
{
	int tank = GetAnyTank();
	if (tank > 0)
		HulkJump(tank);
	return Plugin_Handled;
}

// ============================================================================
// Core Mechanics
// ============================================================================
int FindTargetSurvivor(int tank)
{
	int[] survivors = new int[MaxClients];
	int count = 0;
	
	float tankEye[3];
	GetClientEyePosition(tank, tankEye);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i != tank && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
		{
			float survivorPos[3];
			GetClientAbsOrigin(i, survivorPos);
			
			Handle trace = TR_TraceRayFilterEx(tankEye, survivorPos, MASK_SOLID, RayType_EndPoint, TraceRayNoPlayers, tank);
			bool visible = !TR_DidHit(trace);
			delete trace;
			
			if (visible)
			{
				survivors[count++] = i;
			}
		}
	}
	
	if (count == 0)
		return INVALID_CLIENT;
	
	return survivors[GetRandomInt(0, count - 1)];
}

void HulkJump(int tank)
{
	if (GetDistanceToRoof(tank, 3000.0) < 600.0)
		return;
		
	SetEntityGravity(tank, 1.0);
	AddVelocity(tank, 1000.0);
	
	int target = FindTargetSurvivor(tank);
	if (target != INVALID_CLIENT)
	{
		float tankPos[3], targetPos[3], direction[3];
		GetClientAbsOrigin(tank, tankPos);
		GetClientAbsOrigin(target, targetPos);
		
		SubtractVectors(targetPos, tankPos, direction);
		direction[2] = 0.0;
		NormalizeVector(direction, direction);
		ScaleVector(direction, g_fTargetForce);
		
		float currentVel[3];
		GetEntPropVector(tank, Prop_Data, "m_vecVelocity", currentVel);
		currentVel[0] += direction[0];
		currentVel[1] += direction[1];
		TeleportEntity(tank, NULL_VECTOR, NULL_VECTOR, currentVel);
	}
	
	g_bDelayJump[tank] = true;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i != tank && IsClientInGame(i) && GetClientTeam(i) == 2)
		{
			int soundNum = GetRandomInt(1, 5);
			char snd[PLATFORM_MAX_PATH];
			Format(snd, sizeof(snd), "player/tank/voice/growl/tank_climb_0%d.wav", soundNum);
			EmitSoundToClient(i, snd);
		}
	}
	
	SpawnEffect(tank, "fire_medium_01"); // Dùng particle có sẵn
	CreateTimer(2.5, Timer_HulkEffect, GetClientUserId(tank), TIMER_FLAG_NO_MAPCHANGE);
}

void HulkEffect(int tank)
{
	float vTank[3];
	GetClientAbsOrigin(tank, vTank);
	
	SpawnEffect(tank, "sheetrock");
	
	// Đẩy và gây sát thương cho từng survivor trong tầm
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i != tank && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
		{
			float vPlayer[3];
			GetClientAbsOrigin(i, vPlayer);
			float dist = GetVectorDistance(vTank, vPlayer);
			if (dist < g_fRange)
			{
				float forceDir[3];
				SubtractVectors(vPlayer, vTank, forceDir);
				forceDir[2] = 0.0;
				if (NormalizeVector(forceDir, forceDir) == 0.0)
				{
					float ang[3];
					GetClientEyeAngles(tank, ang);
					GetAngleVectors(ang, forceDir, NULL_VECTOR, NULL_VECTOR);
				}
				ScaleVector(forceDir, g_fForceSingle);
				forceDir[2] = g_fAngleSingle;
				
				FlingSurvivor(i, forceDir);
				SDKHooks_TakeDamage(i, tank, tank, g_fDamageSingle, DMG_CLUB, -1, forceDir, NULL_VECTOR);
			}
		}
	}
	
	// Gọi các hiệu ứng động đất (rung, slowmo, đá, đẩy diện rộng)
	ApplyEarthquakeEffects(tank);
	
	// Kiểm tra survivor dưới chân
	int floorEnt = GetFloorEntity(tank, 1161527296.0);
	if (floorEnt > 0 && floorEnt <= MaxClients && !IsIncapped(floorEnt))
	{
		IncapPlayer(floorEnt);
	}
}

void ApplyEarthquakeEffects(int tank)
{
	SetSlowMotion(g_fSlow, g_fSlowSpeed);
	
	// Rung màn hình và âm thanh
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i != tank && IsClientInGame(i) && GetClientTeam(i) == 2)
		{
			ScreenShake(i, g_fShake);
			EmitSoundToClient(i, "ambient/explosions/explode_3.wav");
		}
	}
	
	// Tạo vòng đá và particle
	CreateHit(tank);
	
	// Đẩy văng diện rộng lần 2 (multi-target)
	CreateForces(tank);
}

void CreateForces(int tank, int excludeTarget = INVALID_CLIENT)
{
	float tankPos[3], targetPos[3], heading[3], resulting[3];
	GetClientAbsOrigin(tank, tankPos);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2 && i != excludeTarget)
		{
			GetClientAbsOrigin(i, targetPos);
			float dist = GetVectorDistance(tankPos, targetPos);
			if (dist <= g_iRadius)
			{
				GetClientEyeAngles(tank, heading);
				resulting[0] = Cosine(DegToRad(heading[1])) * g_fForceMulti;
				resulting[1] = Sine(DegToRad(heading[1])) * g_fForceMulti;
				resulting[2] = g_fForceMulti * g_fAngleMulti;
				if (!g_bL4D2)
					resulting[2] *= L4D_Z_MULT;
				
				FlingSurvivor(i, resulting);
				SDKHooks_TakeDamage(i, tank, tank, g_fDamageMulti, DMG_CLUB, -1, resulting, NULL_VECTOR);
			}
		}
	}
}

// ============================================================================
// Tạo hố đá (Crater) thay cho vòng đá đơn giản
// ============================================================================
void CreateHit(int tank)
{
	float pos[3];
	GetClientAbsOrigin(tank, pos);
	
	// Tạo particle khói bụi trung tâm
	CreateParticles(pos);
	
	// Tạo hố đá nhiều lớp
	DataPack dp = new DataPack();
	dp.WriteFloat(pos[0]);
	dp.WriteFloat(pos[1]);
	dp.WriteFloat(pos[2]);
	CreateTimer(0.3, Timer_CreateCrater, dp, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
}

Action Timer_CreateCrater(Handle timer, DataPack dp)
{
	dp.Reset();
	float centerPos[3];
	centerPos[0] = dp.ReadFloat();
	centerPos[1] = dp.ReadFloat();
	centerPos[2] = dp.ReadFloat();
	
	// Cấu hình các lớp đá (bán kính, số đá, độ cao offset)
	// Lớp trong cùng (gần tâm) -> bán kính nhỏ, đá thấp hơn
	// Lớp ngoài cùng -> bán kính lớn, đá cao hơn
	float layers[4][3] = {
		{ 60.0,  8.0, -15.0 },  // Lớp 1: bán kính 60, 8 đá, thấp hơn 15 đơn vị
		{ 100.0, 12.0, -8.0  },  // Lớp 2: bán kính 100, 12 đá, thấp hơn 8
		{ 140.0, 16.0, 0.0   },  // Lớp 3: bán kính 140, 16 đá, cao ngang mặt đất
		{ 180.0, 20.0, 10.0  }   // Lớp 4: bán kính 180, 20 đá, nhô cao hơn
	};
	
	for (int layer = 0; layer < sizeof(layers); layer++)
	{
		float radius = layers[layer][0];
		int rockCount = RoundToNearest(layers[layer][1]);
		float heightOffset = layers[layer][2];
		
		// Thêm một ít random vào bán kính để trông tự nhiên
		float radiusVar = radius * 0.1;
		
		for (int i = 0; i < rockCount; i++)
		{
			// Góc phân bố đều, thêm jitter nhẹ
			float angle = (float(i) * 360.0 / float(rockCount)) + GetRandomFloat(-5.0, 5.0);
			float rad = DegToRad(angle);
			
			// Tính vị trí trên vòng tròn với bán kính có biến thiên
			float actualRadius = radius + GetRandomFloat(-radiusVar, radiusVar);
			float rockPos[3];
			rockPos[0] = centerPos[0] + actualRadius * Cosine(rad);
			rockPos[1] = centerPos[1] + actualRadius * Sine(rad);
			rockPos[2] = centerPos[2] + heightOffset + GetRandomFloat(-5.0, 5.0);
			
			// Tạo đá
			CreateRockEx(rockPos, true);
		}
	}
	
	// Thêm một vài viên đá ngẫu nhiên rải rác bên trong
	for (int i = 0; i < 8; i++)
	{
		float angle = GetRandomFloat(0.0, 360.0);
		float rad = DegToRad(angle);
		float dist = GetRandomFloat(20.0, 180.0);
		float rockPos[3];
		rockPos[0] = centerPos[0] + dist * Cosine(rad);
		rockPos[1] = centerPos[1] + dist * Sine(rad);
		rockPos[2] = centerPos[2] + GetRandomFloat(-10.0, 10.0);
		CreateRockEx(rockPos, false);
	}
	
	return Plugin_Continue;
}

// Tạo một viên đá với model và kích thước ngẫu nhiên
stock void CreateRockEx(const float pos[3], bool useRandomRotation = true)
{
	int rock = CreateEntityByName("prop_dynamic");
	if (rock == -1) return;
	
	// Chọn ngẫu nhiên giữa 2 model đá để đa dạng
	if (GetRandomInt(0, 1) == 0)
		SetEntityModel(rock, "models/props_debris/concrete_chunk01a.mdl");
	else
		SetEntityModel(rock, "models/props_debris/concrete_chunk02a.mdl"); // Model đá thứ 2 (cần precache nếu dùng)
	
	DispatchSpawn(rock);
	
	float scale = GetRandomFloat(0.8, 1.5);
	SetEntPropFloat(rock, Prop_Send, "m_flModelScale", scale);
	
	float ang[3];
	if (useRandomRotation)
	{
		ang[0] = float(GetRandomInt(0, 360));
		ang[1] = float(GetRandomInt(0, 360));
		ang[2] = float(GetRandomInt(0, 360));
	}
	
	TeleportEntity(rock, pos, ang, NULL_VECTOR);
	
	// Tự hủy sau 8 giây
	CreateTimer(8.0, Timer_DeleteEntity, EntIndexToEntRef(rock), TIMER_FLAG_NO_MAPCHANGE);
}

// ============================================================================
// Timers
// ============================================================================
Action Timer_Jump(Handle timer, DataPack dp)
{
	dp.Reset();
	int userid = dp.ReadCell();
	int tank = GetClientOfUserId(userid);
	if (tank > 0 && !g_bDelayJump[tank] && IsClientInGame(tank) && IsPlayerAlive(tank) && IsOnGround(tank))
	{
		HulkJump(tank);
	}
	return Plugin_Continue;
}

Action Timer_HulkEffect(Handle timer, int userid)
{
	int tank = GetClientOfUserId(userid);
	if (IsTank(tank))
	{
		HulkEffect(tank);
		g_bDelayJump[tank] = false;
	}
	return Plugin_Continue;
}

/*Action Timer_CreateRing(Handle timer, DataPack dp)
{
	dp.Reset();
	float rad = dp.ReadFloat();
	float nPos[3];
	nPos[0] = dp.ReadFloat();
	nPos[1] = dp.ReadFloat();
	nPos[2] = dp.ReadFloat();
	float direction[3], ang[3], rockpos[3];
	for (int i = 1; i <= 10; i++)
	{
		ang[1] = float(i * 36);
		GetAngleVectors(ang, direction, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(direction, rad);
		AddVectors(nPos, direction, rockpos);
		CreateRock(rockpos);
	}
	return Plugin_Continue;
}*/

Action Timer_DeleteEntity(Handle timer, int ref)
{
	int entity = EntRefToEntIndex(ref);
	if (entity != INVALID_ENT_REFERENCE)
		AcceptEntityInput(entity, "Kill");
	return Plugin_Continue;
}

// ============================================================================
// Frame Callback
// ============================================================================
public void Frame_Push(int userid)
{
	int target = GetClientOfUserId(userid);
	if (target > 0)
		TeleportEntity(target, NULL_VECTOR, NULL_VECTOR, g_fResulting);
}

// ============================================================================
// Trace Filters
// ============================================================================
public bool TraceRayNoPlayers(int entity, int mask, any data)
{
	if (entity == data) return false;
	if (1 <= entity <= MaxClients) return false;
	return true;
}

// ============================================================================
// Utility Functions
// ============================================================================
void GetCvars()
{
	g_bEnabled = g_hCvarJumperEnable.BoolValue;
	g_fDamageSingle = g_hCvarDamageSingle.FloatValue;
	g_fDamageMulti = g_hCvarDamageMulti.FloatValue;
	g_fForceSingle = g_hCvarForceSingle.FloatValue;
	g_fAngleSingle = g_hCvarAngleSingle.FloatValue;
	g_fForceMulti = g_hCvarForceMulti.FloatValue;
	g_fAngleMulti = g_hCvarAngleMulti.FloatValue;
	g_iRadius = g_hCvarRadius.IntValue;
	g_fRange = g_hCvarRange.FloatValue;
	g_fChance = g_hCvarChance.FloatValue;
	g_fShake = g_hCvarShake.FloatValue;
	g_fSlow = g_hCvarSlow.FloatValue;
	g_fSlowSpeed = g_hCvarSlowSpeed.FloatValue;
	g_fTargetForce = g_hCvarTargetForce.FloatValue;
	InitHook();
}

void InitHook()
{
	if (g_bEnabled && !g_bHooked)
	{
		HookEvent("tank_spawn", Event_TankSpawn);
		HookEvent("round_end", Event_RoundEnd);
		HookEvent("map_transition", Event_RoundEnd);
		g_bHooked = true;
	}
	else if (!g_bEnabled && g_bHooked)
	{
		UnhookEvent("tank_spawn", Event_TankSpawn);
		UnhookEvent("round_end", Event_RoundEnd);
		UnhookEvent("map_transition", Event_RoundEnd);
		g_bHooked = false;
	}
}

void ClearAllTimers()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		KillTimerSafe(i);
		g_bDelayJump[i] = false;
	}
	
	if (g_hSlowMotionTimer != null)
	{
		KillTimer(g_hSlowMotionTimer);
		g_hSlowMotionTimer = null;
	}
}

void KillTimerSafe(int client)
{
	if (g_iTimerJump[client] != null)
	{
		delete g_iTimerJump[client];
	}
}

stock bool IsTank(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
		return false;
	
	if (GetClientTeam(client) != 3)
		return false;
	
	int zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
	return g_bL4D2 ? (zombieClass == 8) : (zombieClass == 5);
}

stock bool IsOnGround(int client)
{
	return GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") != -1;
}

stock bool IsIncapped(int client)
{
	return view_as<bool>(GetEntProp(client, Prop_Send, "m_isIncapacitated", 1));
}

stock void IncapPlayer(int client)
{
	SetEntityHealth(client, 1);
	SetEntProp(client, Prop_Send, "m_isIncapacitated", 1);
	SetEntityHealth(client, FindConVar("survivor_incap_health").IntValue);
}

stock int GetAnyTank()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsTank(i) && IsPlayerAlive(i))
			return i;
	}
	return INVALID_CLIENT;
}

stock void FlingSurvivor(int victim, const float velocity[3])
{
	float currentVel[3];
	GetEntPropVector(victim, Prop_Data, "m_vecVelocity", currentVel);
	
	float newVel[3];
	newVel[0] = currentVel[0] + velocity[0];
	newVel[1] = currentVel[1] + velocity[1];
	newVel[2] = currentVel[2] + velocity[2];
	
	TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, newVel);
}

stock void AddVelocity(int client, float amount)
{
	float vecVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vecVelocity);
	vecVelocity[2] += amount;
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vecVelocity);
}

stock void PrecacheEffect(const char[] sEffect)
{
	int table = FindStringTable("EffectDispatch");
	bool save = LockStringTables(false);
	AddToStringTable(table, sEffect);
	LockStringTables(save);
}

stock void PrecacheParticleEffect(const char[] sEffect)
{
	int table = FindStringTable("ParticleEffectNames");
	bool save = LockStringTables(false);
	AddToStringTable(table, sEffect);
	LockStringTables(save);
}

stock void SpawnEffect(int client, const char[] effectName)
{
	float pos[3];
	GetClientEyePosition(client, pos);
	int entity = CreateEntityByName("info_particle_system");
	if (entity != -1)
	{
		DispatchKeyValue(entity, "effect_name", effectName);
		DispatchKeyValueVector(entity, "origin", pos);
		DispatchSpawn(entity);
		SetVariantString("!activator");
		AcceptEntityInput(entity, "SetParent", client);
		ActivateEntity(entity);
		AcceptEntityInput(entity, "Start");
		SetVariantString("OnUser1 !self:kill::5.0:1");
		AcceptEntityInput(entity, "AddOutput");
		AcceptEntityInput(entity, "FireUser1");
	}
}

stock void ScreenShake(int client, float intensity)
{
	Handle msg = StartMessageOne("Shake", client);
	if (msg != null)
	{
		BfWriteByte(msg, 0);
		BfWriteFloat(msg, intensity);
		BfWriteFloat(msg, 10.0);
		BfWriteFloat(msg, 3.0);
		EndMessage();
	}
}

stock void CreateParticles(const float pos[3])
{
	char effects[][] = {
		"gas_explosion_initialburst_smoke",
		"gas_explosion_chunks_02",
		"gas_explosion_initialburst_smoke"
	};
	for (int i = 0; i < sizeof(effects); i++)
	{
		int particle = CreateEntityByName("info_particle_system");
		if (IsValidEntity(particle))
		{
			DispatchKeyValue(particle, "effect_name", effects[i]);
			DispatchSpawn(particle);
			ActivateEntity(particle);
			TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
			AcceptEntityInput(particle, "Start");
			CreateTimer(3.0, Timer_DeleteEntity, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

stock void CreateRock(const float pos[3])
{
	int rock = CreateEntityByName("prop_dynamic");
	if (rock == -1) return;
	SetEntityModel(rock, "models/props_debris/concrete_chunk01a.mdl");
	DispatchSpawn(rock);
	float ang[3];
	ang[0] = float(GetRandomInt(0, 360));
	ang[1] = float(GetRandomInt(0, 360));
	ang[2] = float(GetRandomInt(0, 360));
	TeleportEntity(rock, pos, ang, NULL_VECTOR);
	CreateTimer(5.0, Timer_DeleteEntity, EntIndexToEntRef(rock), TIMER_FLAG_NO_MAPCHANGE);
}

stock float GetDistanceToRoof(int client, float maxDist)
{
	float vStart[3], vEnd[3], vMins[3], vMaxs[3];
	GetClientAbsOrigin(client, vStart);
	vStart[2] += 10.0;
	vEnd[0] = vStart[0];
	vEnd[1] = vStart[1];
	vEnd[2] = vStart[2] + maxDist;
	GetClientMins(client, vMins);
	GetClientMaxs(client, vMaxs);
	TR_TraceHullFilter(vStart, vEnd, vMins, vMaxs, MASK_SOLID, TraceRayNoPlayers, client);
	float fDistance = maxDist;
	if (TR_DidHit())
	{
		float fEndPos[3];
		TR_GetEndPosition(fEndPos);
		vStart[2] -= 10.0;
		fDistance = GetVectorDistance(vStart, fEndPos);
	}
	return fDistance;
}

stock int GetFloorEntity(int client, float maxDist)
{
	if (GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") == -1)
		return 0;
	
	float vStart[3], vEnd[3], vMins[3], vMaxs[3];
	GetClientAbsOrigin(client, vStart);
	vStart[2] += 10.0;
	vEnd[0] = vStart[0];
	vEnd[1] = vStart[1];
	vEnd[2] = vStart[2] - maxDist;
	GetClientMins(client, vMins);
	GetClientMaxs(client, vMaxs);
	vMins[0] -= 5.0; vMins[1] -= 5.0;
	vMaxs[0] += 5.0; vMaxs[1] += 5.0;
	TR_TraceHullFilter(vStart, vEnd, vMins, vMaxs, MASK_SOLID, TraceRayNoPlayers, client);
	
	int entity = 0;
	if (TR_DidHit())
		entity = TR_GetEntityIndex();
	
	return entity;
}
