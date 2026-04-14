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
	description = "Place multiple C4s, Crosshair Hint for Manual, Separate Countdown Hint",
	version = "2.5.0",
	url = "https://github.com/Ledahvu/Left-4-Dead-2-SourcePawn-Collection"
};

#define EXPLOSIVE_AMMO_ENTITY "upgrade_ammo_explosive"
#define INCENDIARY_AMMO_ENTITY "upgrade_ammo_incendiary"

#define GASCAN_MODEL "models/props_junk/gascan001a.mdl"
#define PROPANE_MODEL "models/props_junk/propanecanister001a.mdl"
#define FIRE_SOUND "ambient/explosions/explode_1.wav"

#define COLOR_RED      0
#define COLOR_GREEN    1
#define COLOR_BLUE     2
#define COLOR_YELLOW   3
#define COLOR_CYAN     4
#define COLOR_MAGENTA  5
#define COLOR_ORANGE   6
#define COLOR_WHITE    7
#define COLOR_PURPLE   8

#define MAX_C4_LIMIT 50 

// Dữ liệu quản lý mảng C4 cho người chơi
int g_PlayerC4Refs[MAXPLAYERS+1][MAX_C4_LIMIT];
int g_PlayerBombType[MAXPLAYERS+1];
float g_PlaceStartTime[MAXPLAYERS+1];
bool g_IsPlacing[MAXPLAYERS+1];
float g_LastActionTime[MAXPLAYERS+1];

// Tính năng Crosshair Hint cho C4 Thủ Công
float g_LastTraceTime[MAXPLAYERS+1];
int g_ClientAimingAt[MAXPLAYERS+1] = { -1, ... };
int g_ClientAimHint[MAXPLAYERS+1] = { INVALID_ENT_REFERENCE, ... };

// Dữ liệu độc lập trên mỗi Entity (entIndex của C4)
int g_C4UsesLeft[2048] = { -1, ... };
int g_C4Owner[2048] = { -1, ... };
int g_C4BombType[2048] = { -1, ... };
int g_C4Slot[2048] = { -1, ... };
bool g_C4IsManual[2048] = { false, ... };
Handle g_C4HintUpdateTimer[2048] = { null, ... };
Handle g_C4CountdownTimer[2048] = { null, ... };
int g_C4HintEntity[2048] = { -1, ... }; // Dành riêng cho đếm ngược
float g_C4CountdownRemaining[2048] = { 0.0, ... };
Handle g_C4BeamSyncTimer[2048] = { null, ... };

int g_BeamSpriteIndex = -1;

ConVar g_CvarEnable, g_CvarBeamStart, g_CvarBeamEnd, g_CvarExplosionMagnitude, g_CvarExplosionRadius;
ConVar g_CvarCooldown, g_CvarBeamInterval, g_CvarPlaceDuration, g_CvarAllowPickup, g_CvarMaxUses;
ConVar g_CvarPlacementMode, g_CvarBeamColorFire, g_CvarBeamColorExplosive, g_CvarDetonationMode;
ConVar g_CvarCountdownTime, g_CvarShowCountdownHint, g_CvarBeamFlashPerSecond, g_CvarMaxC4PerPlayer;

public void OnPluginStart()
{
	g_CvarEnable = CreateConVar("l4d2_c4_enable", "1", "Enable/disable C4 plugin", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_CvarMaxC4PerPlayer = CreateConVar("l4d2_c4_max_per_player", "10", "Maximum C4 placed at once", FCVAR_NOTIFY, true, 1.0, true, 50.0);
	g_CvarBeamStart = CreateConVar("l4d2_c4_beam_radius_start", "30.0", "Beam ring start radius", FCVAR_NOTIFY, true, 0.0);
	g_CvarBeamEnd = CreateConVar("l4d2_c4_beam_radius_end", "70.0", "Beam ring end radius", FCVAR_NOTIFY, true, 0.0);
	g_CvarExplosionMagnitude = CreateConVar("l4d2_c4_explosion_magnitude", "350", "Explosion magnitude", FCVAR_NOTIFY, true, 1.0);
	g_CvarExplosionRadius = CreateConVar("l4d2_c4_explosion_radius", "600", "Explosion radius", FCVAR_NOTIFY, true, 1.0);
	g_CvarCooldown = CreateConVar("l4d2_c4_cooldown", "1.0", "Cooldown between actions", FCVAR_NOTIFY, true, 0.1);
	g_CvarBeamInterval = CreateConVar("l4d2_c4_beam_interval", "1.0", "Beam flash interval for manual C4", FCVAR_NOTIFY, true, 0.05);
	g_CvarPlaceDuration = CreateConVar("l4d2_c4_place_duration", "2.0", "Time in seconds to place C4", FCVAR_NOTIFY, true, 0.5);
	g_CvarAllowPickup = CreateConVar("l4d2_c4_allow_pickup", "0", "Allow picking up ammo from placed C4", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_CvarMaxUses = CreateConVar("l4d2_c4_max_uses", "4", "Max times ammo can be taken from C4", FCVAR_NOTIFY, true, 0.0);
	g_CvarPlacementMode = CreateConVar("l4d2_c4_placement_mode", "0", "C4 placement mode: 0 = crosshair, 1 = feet", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_CvarBeamColorFire = CreateConVar("l4d2_c4_beam_color_fire", "0", "Beam color for fire bomb", FCVAR_NOTIFY, true, 0.0, true, 8.0);
	g_CvarBeamColorExplosive = CreateConVar("l4d2_c4_beam_color_explosive", "2", "Beam color for explosive bomb", FCVAR_NOTIFY, true, 0.0, true, 8.0);
	g_CvarDetonationMode = CreateConVar("l4d2_c4_detonation_mode", "0", "Detonation mode: 0 = manual Menu, 1 = countdown timer", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_CvarCountdownTime = CreateConVar("l4d2_c4_countdown_time", "10.0", "Countdown time in seconds", FCVAR_NOTIFY, true, 1.0);
	g_CvarShowCountdownHint = CreateConVar("l4d2_c4_show_countdown_hint", "1", "Show instructor hint on C4", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_CvarBeamFlashPerSecond = CreateConVar("l4d2_c4_beam_flash_per_second", "2.0", "Beam flashes per second during countdown", FCVAR_NOTIFY, true, 1.0);
	
	AutoExecConfig(true, "l4d2_c4_ammobox");
	
	for (int i = 1; i <= MaxClients; i++)
	{
		for (int j = 0; j < MAX_C4_LIMIT; j++)
			g_PlayerC4Refs[i][j] = INVALID_ENT_REFERENCE;
			
		g_PlayerBombType[i] = -1;
		g_IsPlacing[i] = false;
		g_LastTraceTime[i] = 0.0;
		g_ClientAimingAt[i] = -1;
		g_ClientAimHint[i] = INVALID_ENT_REFERENCE;
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

public void OnClientPutInServer(int client) { SDKHook(client, SDKHook_WeaponEquip, OnWeaponEquip); }

public void OnClientDisconnect(int client)
{
	RemoveClientAllC4(client);
	HideManualHintFromClient(client);
	if (g_IsPlacing[client]) g_IsPlacing[client] = false;
	g_PlayerBombType[client] = -1;
	g_ClientAimingAt[client] = -1;
	SDKUnhook(client, SDKHook_WeaponEquip, OnWeaponEquip);
}

public void OnWeaponEquip(int client, int weapon)
{
	if (!client || !IsClientInGame(client) || !IsPlayerAlive(client)) return;
	char classname[64];
	GetEntityClassname(weapon, classname, sizeof(classname));
	if (StrEqual(classname, "weapon_upgradepack_incendiary")) g_PlayerBombType[client] = 0;
	else if (StrEqual(classname, "weapon_upgradepack_explosive")) g_PlayerBombType[client] = 1;
}

int GetFreeC4Slot(int client)
{
	int max = g_CvarMaxC4PerPlayer.IntValue;
	if (max > MAX_C4_LIMIT) max = MAX_C4_LIMIT;
	
	for (int i = 0; i < max; i++)
	{
		int ent = EntRefToEntIndex(g_PlayerC4Refs[client][i]);
		if (ent == INVALID_ENT_REFERENCE || !IsValidEntity(ent)) return i;
	}
	return -1;
}

bool HasManualC4(int client)
{
	int max = g_CvarMaxC4PerPlayer.IntValue;
	if (max > MAX_C4_LIMIT) max = MAX_C4_LIMIT;
	
	for (int i = 0; i < max; i++)
	{
		int ent = EntRefToEntIndex(g_PlayerC4Refs[client][i]);
		if (ent != INVALID_ENT_REFERENCE && IsValidEntity(ent)) return true;
	}
	return false;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!g_CvarEnable.BoolValue || !IsPlayerAlive(client) || !IsClientInGame(client))
	{
		if (g_IsPlacing[client]) { SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0); g_IsPlacing[client] = false; }
		return Plugin_Continue;
	}
	
	float currentTime = GetGameTime();
	
	// --- HỆ THỐNG CROSSHAIR HINT CHO C4 THỦ CÔNG ---
	if (currentTime - g_LastTraceTime[client] >= 0.1) // Kiểm tra mỗi 0.1s
	{
		g_LastTraceTime[client] = currentTime;
		float pos[3], ang[3];
		GetClientEyePosition(client, pos);
		GetClientEyeAngles(client, ang);
		Handle trace = TR_TraceRayFilterEx(pos, ang, MASK_SOLID, RayType_Infinite, TraceFilter, client);
		
		int hitEnt = -1;
		if (TR_DidHit(trace)) hitEnt = TR_GetEntityIndex(trace);
		delete trace;
		
		bool lookingAtManualC4 = false;
		if (hitEnt > MaxClients && IsValidEntity(hitEnt) && g_C4Owner[hitEnt] != -1 && g_C4IsManual[hitEnt])
		{
			lookingAtManualC4 = true;
			// Nếu mới lia tâm vào cục C4 thủ công này
			if (g_ClientAimingAt[client] != hitEnt)
			{
				g_ClientAimingAt[client] = hitEnt;
				ShowManualHintToClient(client, hitEnt);
			}
		}
		
		// Nếu lia tâm đi chỗ khác
		if (!lookingAtManualC4 && g_ClientAimingAt[client] != -1)
		{
			g_ClientAimingAt[client] = -1;
			HideManualHintFromClient(client);
		}
	}
	// -----------------------------------------------

	float placeDuration = g_CvarPlaceDuration.FloatValue;
	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	bool isHoldingAmmoPack = false;
	
	if (activeWeapon != -1)
	{
		char classname[64];
		GetEntityClassname(activeWeapon, classname, sizeof(classname));
		if (StrEqual(classname, "weapon_upgradepack_incendiary") || StrEqual(classname, "weapon_upgradepack_explosive"))
			isHoldingAmmoPack = true;
	}
	
	// Mở Menu Kích nổ
	if (g_CvarDetonationMode.IntValue == 0 && !isHoldingAmmoPack && HasManualC4(client) && (buttons & IN_DUCK) && (buttons & IN_ATTACK))
	{
		if (currentTime - g_LastActionTime[client] >= g_CvarCooldown.FloatValue)
		{
			g_LastActionTime[client] = currentTime;
			ShowDetonateMenu(client);
		}
		buttons &= ~IN_ATTACK;
		return Plugin_Continue;
	}
	
	// Tiến trình đặt C4
	if (isHoldingAmmoPack && (buttons & IN_DUCK) && (buttons & IN_ATTACK))
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
			
			if (currentTime - g_PlaceStartTime[client] >= placeDuration)
			{
				PlaceC4(client, bombType);
				SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
				g_IsPlacing[client] = false;
				RemoveAmmoPack(client);
			}
			buttons &= ~IN_ATTACK;
			return Plugin_Continue;
		}
	}
	else if (!(buttons & IN_DUCK) && g_IsPlacing[client])
	{
		SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
		g_IsPlacing[client] = false;
		PrintToChat(client, "\x04[C4]\x01 Đã hủy thao tác đặt C4!");
	}
	
	return Plugin_Continue;
}

// ----------------------------------------------------------------------------------
// CÁC HÀM XỬ LÝ INSTRUCTOR HINT CHO C4 THỦ CÔNG (CHỈ XUẤT HIỆN KHI LIA TÂM)
// ----------------------------------------------------------------------------------
void ShowManualHintToClient(int client, int c4Ent)
{
	HideManualHintFromClient(client); // Xóa hint cũ nếu có
	
	int hint = CreateEntityByName("env_instructor_hint");
	if (hint == -1) return;
	
	char targetName[64];
	Format(targetName, sizeof(targetName), "c4_target_%d", c4Ent);
	
	char caption[64];
	Format(caption, sizeof(caption), "C4 #%d", g_C4Slot[c4Ent] + 1);
	
	DispatchKeyValue(hint, "hint_target", targetName);
	DispatchKeyValue(hint, "hint_static", "0");
	DispatchKeyValue(hint, "hint_allow_nodraw_target", "1");
	DispatchKeyValue(hint, "hint_range", "0");
	DispatchKeyValue(hint, "hint_timeout", "0");
	DispatchKeyValue(hint, "hint_icon_onscreen", "icon_skull");
	DispatchKeyValue(hint, "hint_caption", caption);
	DispatchKeyValue(hint, "hint_color", "255 128 0"); 
	DispatchKeyValue(hint, "hint_forcecaption", "1");
	DispatchKeyValue(hint, "hint_local_player_only", "1"); // CHỈ HIỆN CHO NGƯỜI ĐANG NHÌN
	
	float pos[3];
	GetEntPropVector(c4Ent, Prop_Data, "m_vecAbsOrigin", pos);
	pos[2] += 20.0;
	TeleportEntity(hint, pos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(hint);
	
	AcceptEntityInput(hint, "ShowHint", client, client); // Kích hoạt chỉ cho client này
	
	g_ClientAimHint[client] = EntIndexToEntRef(hint);
}

void HideManualHintFromClient(int client)
{
	int hintRef = g_ClientAimHint[client];
	int hint = EntRefToEntIndex(hintRef);
	if (hint != INVALID_ENT_REFERENCE && IsValidEntity(hint))
	{
		AcceptEntityInput(hint, "EndHint");
		AcceptEntityInput(hint, "Kill");
	}
	g_ClientAimHint[client] = INVALID_ENT_REFERENCE;
}
// ----------------------------------------------------------------------------------


void ShowDetonateMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Detonate);
	menu.SetTitle("🚀 KÍCH NỔ C4 (Thủ công):\n ");
	
	int count = 0;
	int max = g_CvarMaxC4PerPlayer.IntValue;
	if (max > MAX_C4_LIMIT) max = MAX_C4_LIMIT;
	
	for (int i = 0; i < max; i++)
	{
		int c4Ent = EntRefToEntIndex(g_PlayerC4Refs[client][i]);
		if (c4Ent != INVALID_ENT_REFERENCE && IsValidEntity(c4Ent))
		{
			char info[8], display[64];
			IntToString(i, info, sizeof(info));
			int bType = g_C4BombType[c4Ent];
			Format(display, sizeof(display), "💥 Kích nổ C4 #%d [%s]", i + 1, bType == 0 ? "Lửa" : "Nổ");
			menu.AddItem(info, display);
			count++;
		}
	}
	
	if (count > 0)
	{
		menu.AddItem("all", "🔥 KÍCH NỔ TẤT CẢ");
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else
	{
		delete menu;
		PrintToChat(client, "\x04[C4]\x01 Bạn không có C4 nào trên bản đồ.");
	}
}

int MenuHandler_Detonate(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1;
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		
		if (StrEqual(info, "all"))
		{
			int max = g_CvarMaxC4PerPlayer.IntValue;
			if (max > MAX_C4_LIMIT) max = MAX_C4_LIMIT;
			for (int i = 0; i < max; i++) DetonateC4BySlot(client, i);
		}
		else
		{
			int slot = StringToInt(info);
			DetonateC4BySlot(client, slot);
			if (HasManualC4(client)) ShowDetonateMenu(client);
		}
	}
	else if (action == MenuAction_End) delete menu;
	return 0;
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
	int slot = GetFreeC4Slot(client);
	if (slot == -1)
	{
		PrintToChat(client, "\x04[C4]\x01 Đã đạt giới hạn tối đa %d C4!", g_CvarMaxC4PerPlayer.IntValue);
		return;
	}

	float hitPos[3];
	if (g_CvarPlacementMode.IntValue == 1)
	{
		GetClientAbsOrigin(client, hitPos);
		float traceStart[3], traceEnd[3];
		traceStart = hitPos; traceStart[2] += 50.0;
		traceEnd = hitPos;   traceEnd[2]   -= 100.0;
		Handle trace = TR_TraceRayFilterEx(traceStart, traceEnd, MASK_SOLID, RayType_EndPoint, TraceFilter, client);
		if (TR_DidHit(trace)) TR_GetEndPosition(hitPos, trace);
		delete trace;
		hitPos[2] += 10.0;
	}
	else
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
		else { delete trace; return; }
		delete trace;
	}
	
	char entityName[64];
	strcopy(entityName, sizeof(entityName), (bombType == 0) ? INCENDIARY_AMMO_ENTITY : EXPLOSIVE_AMMO_ENTITY);
	
	int c4 = CreateEntityByName(entityName);
	if (c4 == -1) return;
	
	char targetName[64];
	Format(targetName, sizeof(targetName), "c4_target_%d", c4);
	DispatchKeyValue(c4, "targetname", targetName);
	DispatchKeyValue(c4, "solid", "6");
	TeleportEntity(c4, hitPos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(c4);
	
	g_PlayerC4Refs[client][slot] = EntIndexToEntRef(c4);
	int entIndex = c4;
	
	g_C4Owner[entIndex] = client;
	g_C4BombType[entIndex] = bombType;
	g_C4Slot[entIndex] = slot;
	g_C4IsManual[entIndex] = (g_CvarDetonationMode.IntValue == 0);
	g_C4UsesLeft[entIndex] = g_CvarAllowPickup.BoolValue ? (g_CvarMaxUses.IntValue > 0 ? g_CvarMaxUses.IntValue : 0) : -1;
	
	if (g_CvarDetonationMode.IntValue == 1) // Chế độ đếm ngược
	{
		float countdown = g_CvarCountdownTime.FloatValue;
		g_C4CountdownRemaining[entIndex] = countdown;
		g_C4CountdownTimer[entIndex] = CreateTimer(countdown, Timer_CountdownExplode, EntIndexToEntRef(c4));
		
		if (g_CvarShowCountdownHint.BoolValue)
		{
			// TẠO HINT ĐẾM NGƯỢC (Tách biệt hoàn toàn)
			CreateCountdownHint(c4, entIndex, targetName, countdown);
			g_C4HintUpdateTimer[entIndex] = CreateTimer(1.0, Timer_UpdateCountdownHint, entIndex, TIMER_REPEAT);
		}
		StartSynchronizedBeam(entIndex, true);
		PrintToChat(client, "\x04[C4]\x01 Đã đặt bom đếm ngược. Nổ sau %.0f giây.", countdown);
	}
	else // Chế độ thủ công
	{
		// C4 Thủ công KHÔNG TẠO HINT SẴN TẠI ĐÂY, sẽ tự hiện khi lia Crosshair
		StartSynchronizedBeam(entIndex, false);
		PrintToChat(client, "\x04[C4]\x01 Đã đặt bom thủ công #%d.", slot + 1);
	}
	
	SDKHook(c4, SDKHook_Use, OnC4Use);
}

// ----------------------------------------------------------------------------------
// HỆ THỐNG HINT DÀNH RIÊNG CHO C4 ĐẾM NGƯỢC (GIỮ NGUYÊN HOẠT ĐỘNG TỐT)
// ----------------------------------------------------------------------------------
void CreateCountdownHint(int c4Ent, int entIndex, const char[] targetName, float timeRemaining)
{
	float pos[3];
	GetEntPropVector(c4Ent, Prop_Data, "m_vecAbsOrigin", pos);
	pos[2] += 20.0; 

	int hint = CreateEntityByName("env_instructor_hint");
	if (hint == -1) return;
	
	char caption[64];
	int mins = RoundToFloor(timeRemaining / 60.0);
	int secs = RoundToFloor(timeRemaining) % 60;
	Format(caption, sizeof(caption), "%02d:%02d", mins, secs);
	
	DispatchKeyValue(hint, "hint_target", targetName);
	DispatchKeyValue(hint, "hint_static", "0");
	DispatchKeyValue(hint, "hint_allow_nodraw_target", "1");
	DispatchKeyValue(hint, "hint_range", "0");
	DispatchKeyValue(hint, "hint_timeout", "0");
	DispatchKeyValue(hint, "hint_icon_onscreen", "icon_skull");
	DispatchKeyValue(hint, "hint_caption", caption);
	DispatchKeyValue(hint, "hint_color", "255 0 0"); 
	DispatchKeyValue(hint, "hint_forcecaption", "1");
	
	TeleportEntity(hint, pos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(hint);
	AcceptEntityInput(hint, "ShowHint");
	
	g_C4HintEntity[entIndex] = EntIndexToEntRef(hint);
}

public Action Timer_UpdateCountdownHint(Handle timer, int entIndex)
{
	if (entIndex < 0 || entIndex >= 2048) return Plugin_Stop;
	
	int c4Ent = entIndex;
	// Chỉ đụng tới hint đếm ngược, nếu là thủ công thì bỏ qua
	if (!IsValidEntity(c4Ent) || g_C4IsManual[entIndex])
	{
		g_C4HintUpdateTimer[entIndex] = null;
		return Plugin_Stop;
	}

	int hintRef = g_C4HintEntity[entIndex];
	int hint = EntRefToEntIndex(hintRef);
	if (hint != INVALID_ENT_REFERENCE && IsValidEntity(hint)) AcceptEntityInput(hint, "Kill");
	g_C4HintEntity[entIndex] = -1;
	
	char targetName[64];
	Format(targetName, sizeof(targetName), "c4_target_%d", c4Ent);

	float remaining = g_C4CountdownRemaining[entIndex] - 1.0;
	if (remaining <= 0.0)
	{
		g_C4CountdownRemaining[entIndex] = 0.0;
		g_C4HintUpdateTimer[entIndex] = null;
		return Plugin_Stop; 
	}
	
	g_C4CountdownRemaining[entIndex] = remaining;
	CreateCountdownHint(c4Ent, entIndex, targetName, remaining);
	return Plugin_Continue;
}

void DestroyCountdownHint(int entIndex)
{
	if (g_C4HintUpdateTimer[entIndex] != null)
	{
		KillTimer(g_C4HintUpdateTimer[entIndex]);
		g_C4HintUpdateTimer[entIndex] = null;
	}
	int hint = EntRefToEntIndex(g_C4HintEntity[entIndex]);
	if (hint != INVALID_ENT_REFERENCE && IsValidEntity(hint)) AcceptEntityInput(hint, "Kill");
	g_C4HintEntity[entIndex] = -1;
}
// ----------------------------------------------------------------------------------

void StartSynchronizedBeam(int entIndex, bool isCountdown)
{
	if (g_C4BeamSyncTimer[entIndex] != null) KillTimer(g_C4BeamSyncTimer[entIndex]);
	float interval = isCountdown ? (1.0 / g_CvarBeamFlashPerSecond.FloatValue) : g_CvarBeamInterval.FloatValue;
	g_C4BeamSyncTimer[entIndex] = CreateTimer(interval, Timer_SyncedBeamRing, entIndex, TIMER_REPEAT);
}

public Action Timer_SyncedBeamRing(Handle timer, int entIndex)
{
	if (entIndex < 0 || entIndex >= 2048) return Plugin_Stop;
	int c4Ent = entIndex;
	if (!IsValidEntity(c4Ent))
	{
		g_C4BeamSyncTimer[entIndex] = null;
		return Plugin_Stop;
	}
	
	if (!g_C4IsManual[entIndex] && g_C4CountdownRemaining[entIndex] <= 0.0)
	{
		g_C4BeamSyncTimer[entIndex] = null;
		return Plugin_Stop;
	}
	
	float origin[3];
	GetEntPropVector(c4Ent, Prop_Data, "m_vecAbsOrigin", origin);
	origin[2] += 5.0;
	
	int bombType = g_C4BombType[entIndex];
	int colorPreset = (bombType == 0) ? g_CvarBeamColorFire.IntValue : g_CvarBeamColorExplosive.IntValue;
	int color[4];
	GetColorFromPreset(colorPreset, color);
	
	TE_SetupBeamRingPoint(origin, g_CvarBeamStart.FloatValue, g_CvarBeamEnd.FloatValue, g_BeamSpriteIndex, 0, 0, 0, 0.1, 5.0, 0.0, color, 10, 0);
	TE_SendToAll();
	
	return Plugin_Continue;
}

public Action Timer_CountdownExplode(Handle timer, int c4Ref)
{
	int c4Ent = EntRefToEntIndex(c4Ref);
	if (c4Ent == INVALID_ENT_REFERENCE || !IsValidEntity(c4Ent)) return Plugin_Stop;
	
	int owner = -1;
	int slot = -1;
	for (int i = 1; i <= MaxClients; i++)
	{
		for (int j = 0; j < MAX_C4_LIMIT; j++)
		{
			if (EntRefToEntIndex(g_PlayerC4Refs[i][j]) == c4Ent)
			{
				owner = i; slot = j; break;
			}
		}
		if (owner != -1) break;
	}
	
	if (owner != -1 && IsClientInGame(owner))
	{
		DetonateC4BySlot(owner, slot);
	}
	else
	{
		int entIndex = c4Ent;
		g_C4CountdownTimer[entIndex] = null;
		DestroyCountdownHint(entIndex);
		if (g_C4BeamSyncTimer[entIndex] != null) KillTimer(g_C4BeamSyncTimer[entIndex]);
		
		float pos[3];
		GetEntPropVector(c4Ent, Prop_Data, "m_vecAbsOrigin", pos);
		int bombType = g_C4BombType[entIndex];
		
		if (bombType == 0)
		{
			CreateExplosiveFireEffect(pos);
			CreateExplosion(pos, 80, 200, 0);
			EmitSoundToAll(FIRE_SOUND);
		}
		else
		{
			CreateExplosiveEffect(pos);
			CreateExplosion(pos, g_CvarExplosionMagnitude.IntValue, g_CvarExplosionRadius.IntValue, 0);
		}
		RemoveEntity(c4Ent);
	}
	return Plugin_Stop;
}

void DetonateC4BySlot(int client, int slot)
{
	int c4Ent = EntRefToEntIndex(g_PlayerC4Refs[client][slot]);
	if (c4Ent == INVALID_ENT_REFERENCE || !IsValidEntity(c4Ent))
	{
		g_PlayerC4Refs[client][slot] = INVALID_ENT_REFERENCE;
		return;
	}
	
	int entIndex = c4Ent;
	if (g_C4CountdownTimer[entIndex] != null)
	{
		KillTimer(g_C4CountdownTimer[entIndex]);
		g_C4CountdownTimer[entIndex] = null;
	}
	
	DestroyCountdownHint(entIndex);
	if (g_C4BeamSyncTimer[entIndex] != null)
	{
		KillTimer(g_C4BeamSyncTimer[entIndex]);
		g_C4BeamSyncTimer[entIndex] = null;
	}
	
	float pos[3];
	GetEntPropVector(c4Ent, Prop_Data, "m_vecAbsOrigin", pos);
	int bombType = g_C4BombType[entIndex];
	
	if (bombType == 0)
	{
		CreateExplosiveFireEffect(pos);
		CreateExplosion(pos, 80, 200, client);
		EmitSoundToAll(FIRE_SOUND);
		PrintToChatAll("\x04[C4]\x01 Bom Lửa #%d kích nổ bởi %N", slot + 1, client);
	}
	else
	{
		CreateExplosiveEffect(pos);
		CreateExplosion(pos, g_CvarExplosionMagnitude.IntValue, g_CvarExplosionRadius.IntValue, client);
		PrintToChatAll("\x04[C4]\x01 Bom Nổ #%d kích nổ bởi %N", slot + 1, client);
	}
	
	RemoveEntity(c4Ent);
	CleanEntityData(client, slot, entIndex);
}

void DestroyC4Quietly(int client, int slot)
{
	int c4Ent = EntRefToEntIndex(g_PlayerC4Refs[client][slot]);
	if (c4Ent != INVALID_ENT_REFERENCE && IsValidEntity(c4Ent))
	{
		int entIndex = c4Ent;
		if (g_C4CountdownTimer[entIndex] != null) KillTimer(g_C4CountdownTimer[entIndex]);
		DestroyCountdownHint(entIndex);
		if (g_C4BeamSyncTimer[entIndex] != null) KillTimer(g_C4BeamSyncTimer[entIndex]);
		
		SDKUnhook(c4Ent, SDKHook_Use, OnC4Use);
		RemoveEntity(c4Ent);
		CleanEntityData(client, slot, entIndex);
	}
}

void CleanEntityData(int client, int slot, int entIndex)
{
	g_PlayerC4Refs[client][slot] = INVALID_ENT_REFERENCE;
	g_C4Owner[entIndex] = -1;
	g_C4UsesLeft[entIndex] = -1;
	g_C4BombType[entIndex] = -1;
	g_C4Slot[entIndex] = -1;
	g_C4IsManual[entIndex] = false;
	g_C4CountdownRemaining[entIndex] = 0.0;
}

void RemoveClientAllC4(int client)
{
	for (int i = 0; i < MAX_C4_LIMIT; i++) DestroyC4Quietly(client, i);
}

public Action OnC4Use(int entity, int activator, int caller, UseType type, float value)
{
	if (!g_CvarEnable.BoolValue || activator < 1 || activator > MaxClients || !IsClientInGame(activator) || !IsPlayerAlive(activator)) return Plugin_Continue;
	
	int entIndex = entity;
	int owner = g_C4Owner[entIndex];
	if (owner == -1 || !g_CvarAllowPickup.BoolValue)
	{
		PrintHintText(activator, "Không thể nhặt đạn từ C4 này!");
		return Plugin_Handled;
	}
	
	int usesLeft = g_C4UsesLeft[entIndex];
	if (usesLeft == 0) return Plugin_Continue;
	if (usesLeft > 0)
	{
		g_C4UsesLeft[entIndex]--;
		if (g_C4UsesLeft[entIndex] <= 0)
		{
			PrintHintText(activator, "C4 đã cạn đạn và biến mất!");
			if (owner > 0 && IsClientInGame(owner))
			{
				for (int i = 0; i < MAX_C4_LIMIT; i++)
				{
					if (EntRefToEntIndex(g_PlayerC4Refs[owner][i]) == entity)
					{
						DestroyC4Quietly(owner, i);
						break;
					}
				}
			}
			else RemoveEntity(entity);
			return Plugin_Handled;
		}
		PrintHintText(activator, "Đã nhặt đạn (Còn %d lần nhặt)", g_C4UsesLeft[entIndex]);
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

void CreateExplosiveFireEffect(float pos[3])
{
	float offX[5] = {0.0, 25.0, -25.0, 0.0, 0.0};
	float offY[5] = {0.0, 0.0, 0.0, 25.0, -25.0};
	for (int i = 0; i < 5; i++)
	{
		int prop = CreateEntityByName("prop_physics");
		if (prop != -1)
		{
			float spawnPos[3];
			spawnPos[0] = pos[0] + offX[i];
			spawnPos[1] = pos[1] + offY[i];
			spawnPos[2] = pos[2] + 15.0;
			SetEntityModel(prop, GASCAN_MODEL);
			DispatchKeyValue(prop, "solid", "6");
			DispatchSpawn(prop);
			SetEntProp(prop, Prop_Send, "m_CollisionGroup", 1);
			TeleportEntity(prop, spawnPos, NULL_VECTOR, NULL_VECTOR);
			AcceptEntityInput(prop, "Break");
			CreateTimer(0.5, Timer_RemoveEntity, EntIndexToEntRef(prop));
		}
	}
}

void CreateExplosiveEffect(float pos[3])
{
	float offX[5] = {0.0, 25.0, -25.0, 0.0, 0.0};
	float offY[5] = {0.0, 0.0, 0.0, 25.0, -25.0};
	for (int i = 0; i < 5; i++)
	{
		int prop = CreateEntityByName("prop_physics");
		if (prop != -1)
		{
			float spawnPos[3];
			spawnPos[0] = pos[0] + offX[i];
			spawnPos[1] = pos[1] + offY[i];
			spawnPos[2] = pos[2] + 15.0;
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

void GetColorFromPreset(int preset, int color[4])
{
	switch (preset)
	{
		case COLOR_RED:     { color[0]=255; color[1]=0;   color[2]=0;   }
		case COLOR_GREEN:   { color[0]=0;   color[1]=255; color[2]=0;   }
		case COLOR_BLUE:    { color[0]=0;   color[1]=0;   color[2]=255; }
		case COLOR_YELLOW:  { color[0]=255; color[1]=255; color[2]=0;   }
		case COLOR_CYAN:    { color[0]=0;   color[1]=255; color[2]=255; }
		case COLOR_MAGENTA: { color[0]=255; color[1]=0;   color[2]=255; }
		case COLOR_ORANGE:  { color[0]=255; color[1]=128; color[2]=0;   }
		case COLOR_WHITE:   { color[0]=255; color[1]=255; color[2]=255; }
		case COLOR_PURPLE:  { color[0]=128; color[1]=0;   color[2]=128; }
		default:            { color[0]=255; color[1]=0;   color[2]=0;   }
	}
	color[3] = 255;
}

public Action Timer_RemoveEntity(Handle timer, int entRef)
{
	int ent = EntRefToEntIndex(entRef);
	if (ent != INVALID_ENT_REFERENCE && IsValidEntity(ent)) RemoveEntity(ent);
	return Plugin_Stop;
}

public bool TraceFilter(int entity, int mask, any data) { return (entity != data); }

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && g_IsPlacing[client])
	{
		SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
		g_IsPlacing[client] = false;
		PrintToChat(client, "\x04[C4]\x01 Đã hủy đặt C4 do bị sát thương!");
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
	{
		if (g_IsPlacing[client]) { SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0); g_IsPlacing[client] = false; }
		RemoveClientAllC4(client);
		HideManualHintFromClient(client);
	}
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++) { 
		RemoveClientAllC4(i); 
		g_IsPlacing[i] = false; 
		HideManualHintFromClient(i);
	}
	return Plugin_Continue;
}
