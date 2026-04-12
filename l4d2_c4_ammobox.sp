// <L4D2 C4 Ammo Box> - <Place and detonate C4 using ammo packs>
// Copyright (C) <2026> <Vũ Trường Tuyền - Tyn Zũ>
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

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo =
{
	name = "L4D2 C4 Ammo Box",
	author = "Tyn Zũ",
	description = "Place and detonate C4 using ammo packs (with color presets for beam ring)",
	version = "2.0",
	url = "https://github.com/Ledahvu/Left-4-Dead-2-SourcePawn-Collection"
};

// Entities cho hộp đạn đã triển khai
#define EXPLOSIVE_AMMO_ENTITY "upgrade_ammo_explosive"
#define INCENDIARY_AMMO_ENTITY "upgrade_ammo_incendiary"

// Models cho hiệu ứng nổ
#define GASCAN_MODEL "models/props_junk/gascan001a.mdl"
#define PROPANE_MODEL "models/props_junk/propanecanister001a.mdl"

#define FIRE_SOUND "ambient/explosions/explode_1.wav"

// Định nghĩa các màu preset (số thứ tự)
#define COLOR_RED      0
#define COLOR_GREEN    1
#define COLOR_BLUE     2
#define COLOR_YELLOW   3
#define COLOR_CYAN     4
#define COLOR_MAGENTA  5
#define COLOR_ORANGE   6
#define COLOR_WHITE    7
#define COLOR_PURPLE   8
#define COLOR_MAX      9  // Tổng số màu

// Dữ liệu cho mỗi người chơi
int g_C4Entity[MAXPLAYERS+1];
int g_PlayerBombType[MAXPLAYERS+1];
bool g_HasC4Placed[MAXPLAYERS+1];
float g_PlaceStartTime[MAXPLAYERS+1];
bool g_IsPlacing[MAXPLAYERS+1];
Handle g_BeamTimer[MAXPLAYERS+1];
float g_LastActionTime[MAXPLAYERS+1];
float g_LastPlaceTime[MAXPLAYERS+1];

// Dữ liệu cho mỗi C4 đã đặt (lưu trực tiếp trên entity)
int g_C4UsesLeft[2048] = { -1, ... };
int g_C4Owner[2048] = { -1, ... };
int g_C4BombType[2048] = { -1, ... };   // Lưu loại bom của C4

int g_BeamSpriteIndex = -1;

ConVar g_CvarEnable;
ConVar g_CvarBeamStart;
ConVar g_CvarBeamEnd;
ConVar g_CvarExplosionMagnitude;
ConVar g_CvarExplosionRadius;
ConVar g_CvarCooldown;
ConVar g_CvarBeamInterval;
ConVar g_CvarPlaceDuration;

ConVar g_CvarAllowPickup;
ConVar g_CvarMaxUses;
ConVar g_CvarPlacementMode;

ConVar g_CvarBeamColorFire;        // Màu cho bom lửa
ConVar g_CvarBeamColorExplosive;   // Màu cho bom nổ

public void OnPluginStart()
{
	g_CvarEnable = CreateConVar("l4d2_c4_enable", "1", "Enable/disable C4 plugin", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_CvarBeamStart = CreateConVar("l4d2_c4_beam_radius_start", "30.0", "Beam ring start radius", FCVAR_NOTIFY, true, 0.0);
	g_CvarBeamEnd = CreateConVar("l4d2_c4_beam_radius_end", "200.0", "Beam ring end radius", FCVAR_NOTIFY, true, 0.0);
	g_CvarExplosionMagnitude = CreateConVar("l4d2_c4_explosion_magnitude", "350", "Explosion magnitude", FCVAR_NOTIFY, true, 1.0);
	g_CvarExplosionRadius = CreateConVar("l4d2_c4_explosion_radius", "600", "Explosion radius", FCVAR_NOTIFY, true, 1.0);
	g_CvarCooldown = CreateConVar("l4d2_c4_cooldown", "1.5", "Cooldown between actions", FCVAR_NOTIFY, true, 0.1);
	g_CvarBeamInterval = CreateConVar("l4d2_c4_beam_interval", "1.5", "Beam ring update interval", FCVAR_NOTIFY, true, 0.05);
	g_CvarPlaceDuration = CreateConVar("l4d2_c4_place_duration", "2.0", "Time in seconds to place C4", FCVAR_NOTIFY, true, 0.5);
	
	g_CvarAllowPickup = CreateConVar("l4d2_c4_allow_pickup", "0", "Allow picking up ammo from placed C4 (0=No, 1=Yes)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_CvarMaxUses = CreateConVar("l4d2_c4_max_uses", "4", "Max times ammo can be taken from C4 (0=unlimited). Only works if pickup allowed.", FCVAR_NOTIFY, true, 0.0);
	g_CvarPlacementMode = CreateConVar("l4d2_c4_placement_mode", "0", "C4 placement mode: 0 = at crosshair, 1 = at player's feet", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	// Sửa lỗi: dùng float cho min/max, không dùng enum
	g_CvarBeamColorFire = CreateConVar("l4d2_c4_beam_color_fire", "0", "Beam color for fire bomb (0=Red,1=Green,2=Blue,3=Yellow,4=Cyan,5=Magenta,6=Orange,7=White,8=Purple)", FCVAR_NOTIFY, true, 0.0, true, 8.0);
	g_CvarBeamColorExplosive = CreateConVar("l4d2_c4_beam_color_explosive", "2", "Beam color for explosive bomb (0=Red,1=Green,2=Blue,3=Yellow,4=Cyan,5=Magenta,6=Orange,7=White,8=Purple)", FCVAR_NOTIFY, true, 0.0, true, 8.0);
	
	AutoExecConfig(true, "l4d2_c4_ammobox");
	
	for (int i = 1; i <= MaxClients; i++)
	{
		g_C4Entity[i] = INVALID_ENT_REFERENCE;
		g_PlayerBombType[i] = -1;
		g_BeamTimer[i] = null;
		g_IsPlacing[i] = false;
	}
	
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_hurt", Event_PlayerHurt);
}

public void OnMapStart()
{
	PrecacheModel(GASCAN_MODEL, true);
	PrecacheModel(PROPANE_MODEL, true);
	g_BeamSpriteIndex = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	PrecacheSound(FIRE_SOUND, true);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponEquip, OnWeaponEquip);
}

public void OnClientDisconnect(int client)
{
	RemoveClientC4(client);
	if (g_IsPlacing[client])
	{
		SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
		g_IsPlacing[client] = false;
	}
	g_PlayerBombType[client] = -1;
	SDKUnhook(client, SDKHook_WeaponEquip, OnWeaponEquip);
}

public void OnWeaponEquip(int client, int weapon)
{
	if (!client || !IsClientInGame(client) || !IsPlayerAlive(client))
		return;
	
	char classname[64];
	GetEntityClassname(weapon, classname, sizeof(classname));
	
	if (StrEqual(classname, "weapon_upgradepack_incendiary"))
		g_PlayerBombType[client] = 0;
	else if (StrEqual(classname, "weapon_upgradepack_explosive"))
		g_PlayerBombType[client] = 1;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!g_CvarEnable.BoolValue)
		return Plugin_Continue;
	if (!IsPlayerAlive(client) || !IsClientInGame(client))
	{
		if (g_IsPlacing[client])
		{
			SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
			g_IsPlacing[client] = false;
		}
		return Plugin_Continue;
	}
	
	float currentTime = GetGameTime();
	float placeDuration = g_CvarPlaceDuration.FloatValue;
	
	// Kích hoạt nổ
	if (g_HasC4Placed[client] && (buttons & IN_DUCK) && (buttons & IN_ATTACK))
	{
		if (currentTime - g_LastPlaceTime[client] >= 0.5 && currentTime - g_LastActionTime[client] >= g_CvarCooldown.FloatValue)
		{
			g_LastActionTime[client] = currentTime;
			DetonateC4(client);
		}
		buttons &= ~IN_ATTACK;
		return Plugin_Continue;
	}
	
	// Tiến trình đặt C4
	if (!g_HasC4Placed[client] && (buttons & IN_DUCK) && (buttons & IN_ATTACK))
	{
		int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (activeWeapon != -1)
		{
			char classname[64];
			GetEntityClassname(activeWeapon, classname, sizeof(classname));
			bool isValidWeapon = (StrEqual(classname, "weapon_upgradepack_incendiary") || StrEqual(classname, "weapon_upgradepack_explosive"));
			
			if (isValidWeapon)
			{
				int bombType = g_PlayerBombType[client];
				if (bombType != -1)
				{
					if (!g_IsPlacing[client])
					{
						g_IsPlacing[client] = true;
						g_PlaceStartTime[client] = currentTime;
						SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", g_PlaceStartTime[client]);
						SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", placeDuration);
					}
					
					float elapsed = currentTime - g_PlaceStartTime[client];
					if (elapsed >= placeDuration)
					{
						PlaceC4(client, bombType);
						SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
						g_IsPlacing[client] = false;
						g_LastPlaceTime[client] = currentTime;
						RemoveAmmoPack(client);
					}
					else
					{
						SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", g_PlaceStartTime[client]);
						SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", placeDuration);
					}
					
					buttons &= ~IN_ATTACK;
					return Plugin_Continue;
				}
			}
		}
		
		if (g_IsPlacing[client])
		{
			SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
			g_IsPlacing[client] = false;
		}
	}
	else if (!(buttons & IN_DUCK) && g_IsPlacing[client])
	{
		SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
		g_IsPlacing[client] = false;
		PrintToChat(client, "\x04[C4]\x01 Placement cancelled!");
	}
	
	return Plugin_Continue;
}

void RemoveAmmoPack(int client)
{
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weapon != -1)
	{
		char classname[64];
		GetEntityClassname(weapon, classname, sizeof(classname));
		if (StrEqual(classname, "weapon_upgradepack_incendiary") || StrEqual(classname, "weapon_upgradepack_explosive"))
		{
			RemovePlayerItem(client, weapon);
			RemoveEntity(weapon);
		}
	}
}

void PlaceC4(int client, int bombType)
{
	float hitPos[3];
	
	if (g_CvarPlacementMode.IntValue == 1)  // Đặt tại chân
	{
		GetClientAbsOrigin(client, hitPos);
		
		float traceStart[3];
		traceStart[0] = hitPos[0];
		traceStart[1] = hitPos[1];
		traceStart[2] = hitPos[2] + 50.0;
		
		float traceEnd[3];
		traceEnd[0] = hitPos[0];
		traceEnd[1] = hitPos[1];
		traceEnd[2] = hitPos[2] - 100.0;
		
		Handle trace = TR_TraceRayFilterEx(traceStart, traceEnd, MASK_SOLID, RayType_EndPoint, TraceFilter, client);
		if (TR_DidHit(trace))
		{
			TR_GetEndPosition(hitPos, trace);
		}
		delete trace;
		
		hitPos[2] += 10.0;
	}
	else  // Đặt tại crosshair
	{
		float pos[3], ang[3];
		GetClientEyePosition(client, pos);
		GetClientEyeAngles(client, ang);
		
		Handle trace = TR_TraceRayFilterEx(pos, ang, MASK_SOLID, RayType_Infinite, TraceFilter, client);
		if (TR_DidHit(trace))
		{
			TR_GetEndPosition(hitPos, trace);
			hitPos[2] += 10.0;
		}
		else
		{
			delete trace;
			return;
		}
		delete trace;
	}
	
	char entityName[64];
	if (bombType == 0) {
		strcopy(entityName, sizeof(entityName), INCENDIARY_AMMO_ENTITY);
	} else {
		strcopy(entityName, sizeof(entityName), EXPLOSIVE_AMMO_ENTITY);
	}
	
	int c4 = CreateEntityByName(entityName);
	if (c4 == -1)
		return;
	
	DispatchKeyValue(c4, "solid", "6");
	TeleportEntity(c4, hitPos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(c4);
	
	g_C4Entity[client] = EntIndexToEntRef(c4);
	g_HasC4Placed[client] = true;
	
	int entIndex = EntRefToEntIndex(g_C4Entity[client]);
	if (entIndex != INVALID_ENT_REFERENCE)
	{
		g_C4Owner[entIndex] = client;
		g_C4BombType[entIndex] = bombType;
		
		if (g_CvarAllowPickup.BoolValue)
		{
			int maxUses = g_CvarMaxUses.IntValue;
			g_C4UsesLeft[entIndex] = (maxUses > 0) ? maxUses : 0;
		}
		else
		{
			g_C4UsesLeft[entIndex] = -1;
		}
	}
	
	SDKHook(c4, SDKHook_Use, OnC4Use);
	
	if (g_BeamTimer[client] != null)
		KillTimer(g_BeamTimer[client]);
	g_BeamTimer[client] = CreateTimer(g_CvarBeamInterval.FloatValue, Timer_BeamRing, client, TIMER_REPEAT);
	
	PrintToChat(client, "\x04[C4]\x01 %s bomb placed. Ctrl + Attack to detonate.", 
		bombType == 0 ? "Fire" : "Explosive");
}

public Action OnC4Use(int entity, int activator, int caller, UseType type, float value)
{
	if (!g_CvarEnable.BoolValue) return Plugin_Continue;
	if (activator < 1 || activator > MaxClients) return Plugin_Continue;
	if (!IsClientInGame(activator) || !IsPlayerAlive(activator)) return Plugin_Continue;
	
	int entIndex = EntRefToEntIndex(entity);
	if (entIndex == INVALID_ENT_REFERENCE) return Plugin_Continue;
	
	int owner = g_C4Owner[entIndex];
	if (owner == -1) return Plugin_Continue;
	
	if (!g_CvarAllowPickup.BoolValue)
	{
		PrintHintText(activator, "Cannot pickup ammo from C4!");
		return Plugin_Handled;
	}
	
	int usesLeft = g_C4UsesLeft[entIndex];
	if (usesLeft == 0)
	{
		return Plugin_Continue;
	}
	else if (usesLeft > 0)
	{
		g_C4UsesLeft[entIndex]--;
		if (g_C4UsesLeft[entIndex] <= 0)
		{
			PrintHintText(activator, "C4 ammo depleted!");
			
			int client = owner;
			if (client > 0 && IsClientInGame(client))
			{
				RemoveClientC4(client);
				PrintToChat(client, "\x04[C4]\x01 Your C4 has been used up and disappeared.");
			}
			else
			{
				RemoveEntity(entity);
			}
			return Plugin_Handled;
		}
		else
		{
			PrintHintText(activator, "Ammo taken (%d uses left)", g_C4UsesLeft[entIndex]);
		}
		return Plugin_Continue;
	}
	
	return Plugin_Handled;
}

// Hàm lấy màu RGBA từ preset (int)
void GetColorFromPreset(int preset, int color[4])
{
	switch (preset)
	{
		case COLOR_RED:     { color[0] = 255; color[1] = 0;   color[2] = 0;   }
		case COLOR_GREEN:   { color[0] = 0;   color[1] = 255; color[2] = 0;   }
		case COLOR_BLUE:    { color[0] = 0;   color[1] = 0;   color[2] = 255; }
		case COLOR_YELLOW:  { color[0] = 255; color[1] = 255; color[2] = 0;   }
		case COLOR_CYAN:    { color[0] = 0;   color[1] = 255; color[2] = 255; }
		case COLOR_MAGENTA: { color[0] = 255; color[1] = 0;   color[2] = 255; }
		case COLOR_ORANGE:  { color[0] = 255; color[1] = 128; color[2] = 0;   }
		case COLOR_WHITE:   { color[0] = 255; color[1] = 255; color[2] = 255; }
		case COLOR_PURPLE:  { color[0] = 128; color[1] = 0;   color[2] = 128; }
		default:            { color[0] = 255; color[1] = 0;   color[2] = 0;   }
	}
	color[3] = 255;  // Alpha mặc định 255
}

public Action Timer_BeamRing(Handle timer, int client)
{
	if (!g_CvarEnable.BoolValue || !IsClientInGame(client) || !IsPlayerAlive(client) || !g_HasC4Placed[client])
	{
		g_BeamTimer[client] = null;
		return Plugin_Stop;
	}
	
	int c4Ent = EntRefToEntIndex(g_C4Entity[client]);
	if (c4Ent == INVALID_ENT_REFERENCE || !IsValidEntity(c4Ent))
	{
		g_HasC4Placed[client] = false;
		g_BeamTimer[client] = null;
		return Plugin_Stop;
	}
	
	float origin[3];
	GetEntPropVector(c4Ent, Prop_Data, "m_vecAbsOrigin", origin);
	origin[2] += 5.0;
	
	int bombType = g_C4BombType[c4Ent];
	int colorPreset;
	if (bombType == 0)
		colorPreset = g_CvarBeamColorFire.IntValue;
	else
		colorPreset = g_CvarBeamColorExplosive.IntValue;
	
	int color[4];
	GetColorFromPreset(colorPreset, color);
	
	TE_SetupBeamRingPoint(origin, g_CvarBeamStart.FloatValue, g_CvarBeamEnd.FloatValue, 
	                      g_BeamSpriteIndex, 0, 0, 0, 0.1, 5.0, 0.0, color, 10, 0);
	TE_SendToAll();
	
	return Plugin_Continue;
}

void DetonateC4(int client)
{
	if (!g_HasC4Placed[client])
		return;
	
	int c4Ent = EntRefToEntIndex(g_C4Entity[client]);
	if (c4Ent == INVALID_ENT_REFERENCE || !IsValidEntity(c4Ent))
	{
		RemoveClientC4(client);
		return;
	}
	
	float pos[3];
	GetEntPropVector(c4Ent, Prop_Data, "m_vecAbsOrigin", pos);
	
	int bombType = g_PlayerBombType[client];
	if (bombType == 0)
	{
		CreateExplosiveFireEffect(pos);
		CreateExplosion(pos, 80, 200, client);
		EmitSoundToAll(FIRE_SOUND);
		PrintToChatAll("\x04[C4]\x01 Fire bomb detonated by %N", client);
	}
	else
	{
		CreateExplosiveEffect(pos);
		CreateExplosion(pos, g_CvarExplosionMagnitude.IntValue, g_CvarExplosionRadius.IntValue, client);
		PrintToChatAll("\x04[C4]\x01 Explosive bomb detonated by %N", client);
	}
	
	RemoveEntity(c4Ent);
	RemoveClientC4(client);
}

void CreateExplosiveFireEffect(float pos[3])
{
	int propane = CreateEntityByName("prop_physics");
	if (propane != -1)
	{
		float pPos[3];
		pPos[0] = pos[0];
		pPos[1] = pos[1];
		pPos[2] = pos[2] + 10.0;

		SetEntityModel(propane, PROPANE_MODEL);
		DispatchKeyValue(propane, "solid", "6");
		DispatchSpawn(propane);
		SetEntProp(propane, Prop_Send, "m_CollisionGroup", 1);
		TeleportEntity(propane, pPos, NULL_VECTOR, NULL_VECTOR);
		AcceptEntityInput(propane, "Break");
		CreateTimer(0.5, Timer_RemoveEntity, EntIndexToEntRef(propane));
	}
	
	float offX[3] = {20.0, -10.0, -10.0};
	float offY[3] = {0.0, 17.32, -17.32};
	for (int i = 0; i < 3; i++)
	{
		int gascan = CreateEntityByName("prop_physics");
		if (gascan != -1)
		{
			float gPos[3];
			gPos[0] = pos[0] + offX[i];
			gPos[1] = pos[1] + offY[i];
			gPos[2] = pos[2] + 15.0;
			
			SetEntityModel(gascan, GASCAN_MODEL);
			DispatchKeyValue(gascan, "solid", "6");
			DispatchSpawn(gascan);
			SetEntProp(gascan, Prop_Send, "m_CollisionGroup", 1);
			TeleportEntity(gascan, gPos, NULL_VECTOR, NULL_VECTOR);
			AcceptEntityInput(gascan, "Break");
			CreateTimer(0.5, Timer_RemoveEntity, EntIndexToEntRef(gascan));
		}
	}
}

void CreateExplosiveEffect(float pos[3])
{
	float offX[5] = {0.0, 25.0, -25.0, 0.0, 0.0};
	float offY[5] = {0.0, 0.0, 0.0, 25.0, -25.0};
	float offZ[5] = {15.0, 15.0, 15.0, 15.0, 15.0};
	
	for (int i = 0; i < 5; i++)
	{
		int prop = CreateEntityByName("prop_physics");
		if (prop != -1)
		{
			float spawnPos[3];
			spawnPos[0] = pos[0] + offX[i];
			spawnPos[1] = pos[1] + offY[i];
			spawnPos[2] = pos[2] + offZ[i];
			
			SetEntityModel(prop, PROPANE_MODEL);
			DispatchKeyValue(prop, "solid", "6");
			DispatchSpawn(prop);
			SetEntProp(prop, Prop_Send, "m_CollisionGroup", 1);
			TeleportEntity(prop, spawnPos, NULL_VECTOR, NULL_VECTOR);
			AcceptEntityInput(prop, "Break");
			CreateTimer(0.5, Timer_RemoveEntity, EntIndexToEntRef(prop));
		}
	}
}

void CreateExplosion(float pos[3], int magnitude, int radius, int owner)
{
	int explosion = CreateEntityByName("env_explosion");
	if (explosion != -1)
	{
		char mag[16], rad[16];
		IntToString(magnitude, mag, sizeof(mag));
		IntToString(radius, rad, sizeof(rad));
		DispatchKeyValue(explosion, "iMagnitude", mag);
		DispatchKeyValue(explosion, "iRadiusOverride", rad);
		SetEntPropEnt(explosion, Prop_Data, "m_hOwnerEntity", owner);
		TeleportEntity(explosion, pos, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(explosion);
		AcceptEntityInput(explosion, "Explode");
		CreateTimer(0.1, Timer_RemoveEntity, EntIndexToEntRef(explosion));
	}
}

public Action Timer_RemoveEntity(Handle timer, int entRef)
{
	int ent = EntRefToEntIndex(entRef);
	if (ent != INVALID_ENT_REFERENCE && IsValidEntity(ent))
		RemoveEntity(ent);
	return Plugin_Stop;
}

void RemoveClientC4(int client)
{
	if (g_BeamTimer[client] != null)
	{
		KillTimer(g_BeamTimer[client]);
		g_BeamTimer[client] = null;
	}
	int c4Ref = g_C4Entity[client];
	if (c4Ref != INVALID_ENT_REFERENCE)
	{
		int c4Ent = EntRefToEntIndex(c4Ref);
		if (c4Ent != INVALID_ENT_REFERENCE && IsValidEntity(c4Ent))
		{
			g_C4Owner[c4Ent] = -1;
			g_C4UsesLeft[c4Ent] = -1;
			g_C4BombType[c4Ent] = -1;
			SDKUnhook(c4Ent, SDKHook_Use, OnC4Use);
			RemoveEntity(c4Ent);
		}
	}
	g_C4Entity[client] = INVALID_ENT_REFERENCE;
	g_HasC4Placed[client] = false;
}

public bool TraceFilter(int entity, int mask, any data)
{
	return (entity != data);
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && g_IsPlacing[client])
	{
		SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
		g_IsPlacing[client] = false;
		PrintToChat(client, "\x04[C4]\x01 Placement cancelled (you were hurt)!");
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
	{
		if (g_IsPlacing[client])
		{
			SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
			g_IsPlacing[client] = false;
		}
		RemoveClientC4(client);
		g_PlayerBombType[client] = -1;
	}
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_IsPlacing[i])
		{
			SetEntPropFloat(i, Prop_Send, "m_flProgressBarDuration", 0.0);
			g_IsPlacing[i] = false;
		}
		RemoveClientC4(i);
		g_PlayerBombType[i] = -1;
	}
	return Plugin_Continue;
}
