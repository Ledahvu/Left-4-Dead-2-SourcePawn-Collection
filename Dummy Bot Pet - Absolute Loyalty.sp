// <Dummy Bot Pet - Absolute Loyalty> - <Dummy Bot Pet - Absolute Loyalty>
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

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "46.0_AbsoluteLoyalty"
//#define FL_NOTARGET (1 << 0)
#define MAX_MEMORY_NODES 2000

// ==========================================
// CVARS: HỆ THỐNG ĐIỀU KHIỂN & CẤU HÌNH
// ==========================================
ConVar cv_pet_attack_enable;
ConVar cv_pet_scavenge_enable;
ConVar cv_pet_scavenge_medkit;
ConVar cv_pet_scavenge_defib;

ConVar cv_pet_prio_med;  
ConVar cv_pet_prio_pill; 
ConVar cv_pet_prio_nade; 

ConVar cv_pet_damage_multiplier; 
ConVar cv_dmg_smoker, cv_dmg_boomer, cv_dmg_hunter, cv_dmg_spitter, cv_dmg_jockey, cv_dmg_charger, cv_dmg_tank, cv_dmg_witch;

ConVar cv_pet_witch_mode; 
ConVar cv_pet_duration;
ConVar cv_req_mode_si, cv_req_shared, cv_req_tank, cv_req_witch;
ConVar cv_req_smoker, cv_req_boomer, cv_req_hunter, cv_req_spitter, cv_req_jockey, cv_req_charger;

// ==========================================
// KHO CHỨA ĐỒ (VOID INVENTORY) & BỘ NHỚ KILLS
// ==========================================
enum 
{
	ITEM_MEDKIT = 0,
	ITEM_DEFIB,
	ITEM_PILLS,
	ITEM_ADREN,
	ITEM_MOLOTOV,
	ITEM_PIPE,
	ITEM_VOMIT,
	MAX_ITEMS
};
char g_sItemClasses[MAX_ITEMS][] = {"weapon_first_aid_kit", "weapon_defibrillator", "weapon_pain_pills", "weapon_adrenaline", "weapon_molotov", "weapon_pipe_bomb", "weapon_vomitjar"};
char g_sItemNames[MAX_ITEMS][] = {"Túi Cứu Thương", "Máy Sốc Điện", "Thuốc Giảm Đau", "Tiêm Adrenaline", "Bom Lửa", "Bom Ống", "Bom Mật"};

int g_iPetInv[MAXPLAYERS + 1][MAX_ITEMS];
int g_iKills_SI[MAXPLAYERS + 1]; 
int g_iKills_Specific[MAXPLAYERS + 1][7]; 
int g_iKills_Tank[MAXPLAYERS + 1];
int g_iKills_Witch[MAXPLAYERS + 1];

int g_iPlayerPetClass[MAXPLAYERS + 1];
int g_iPlayerPetLifespan[MAXPLAYERS + 1];
int g_iWitchPet[MAXPLAYERS + 1];

// ==========================================
// DỮ LIỆU AI & HỆ THỐNG TRÁNH KẸT
// ==========================================
int g_iPetOwner[MAXPLAYERS + 1];
int g_iAttackCooldown[MAXPLAYERS + 1];
int g_iAttackState[MAXPLAYERS + 1];
int g_iAttackTarget[MAXPLAYERS + 1];
int g_iScavengeTarget[MAXPLAYERS + 1]; 
int g_iScavengeTicks[MAXPLAYERS + 1];  
bool g_bIsRescuing[MAXPLAYERS + 1];
bool g_bOwnerSwarmed[MAXPLAYERS + 1];

float g_vecStuckAnchor[MAXPLAYERS + 1][3];
int g_iStuckTicks[MAXPLAYERS + 1];
float g_vecBreadcrumbs[MAXPLAYERS + 1][64][3]; 
int g_iBreadcrumbCount[MAXPLAYERS + 1];
float g_flLastBreadcrumbTime[MAXPLAYERS + 1];

float g_vecSpatialMemory[MAX_MEMORY_NODES][3];
int g_iMemoryCount = 0;
float g_vecThreatMemory[2048][3]; 
float g_flThreatLastSeen[2048];

float g_flLastDamageTime[2048]; 

public Plugin myinfo = 
{
	name = "Dummy Bot Pet - Absolute Loyalty",
	author = "Tyn Zũ",
	description = "100% no friendly fire/knockback, close-range scavenge, fully optimized.",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart()
{
	cv_pet_attack_enable = CreateConVar("pet_attack_enable", "1", "1 = Cho phép Pet hỗ trợ diệt chủng quái, 0 = Chỉ đi theo cứu chủ và lượm đồ");
	cv_pet_scavenge_enable = CreateConVar("pet_scavenge_enable", "1", "1 = Cho phép Pet tự động lượm đồ");
	cv_pet_scavenge_medkit = CreateConVar("pet_scavenge_medkit", "1", "Cho phép lượm túi cứu thương");
	cv_pet_scavenge_defib = CreateConVar("pet_scavenge_defib", "1", "Cho phép lượm máy sốc điện");
	
	cv_pet_prio_med = CreateConVar("pet_give_prio_med", "2", "Ưu tiên đưa: 0=Medkit, 1=Defib, 2=Ngẫu nhiên");
	cv_pet_prio_pill = CreateConVar("pet_give_prio_pill", "2", "Ưu tiên đưa: 0=Pills, 1=Adren, 2=Ngẫu nhiên");
	cv_pet_prio_nade = CreateConVar("pet_give_prio_nade", "3", "Ưu tiên đưa: 0=Molotov, 1=Pipe, 2=Vomit, 3=Ngẫu nhiên");

	cv_pet_damage_multiplier = CreateConVar("pet_damage_multiplier", "1.0", "Hệ số nhân sát thương tổng thể của Pet");

	cv_dmg_smoker = CreateConVar("pet_dmg_smoker", "200.0");
	cv_dmg_boomer = CreateConVar("pet_dmg_boomer", "100.0");
	cv_dmg_hunter = CreateConVar("pet_dmg_hunter", "300.0");
	cv_dmg_spitter = CreateConVar("pet_dmg_spitter", "240.0");
	cv_dmg_jockey = CreateConVar("pet_dmg_jockey", "160.0");
	cv_dmg_charger = CreateConVar("pet_dmg_charger", "500.0");
	cv_dmg_tank = CreateConVar("pet_dmg_tank", "800.0");
	cv_dmg_witch = CreateConVar("pet_dmg_witch", "1000.0");

	cv_pet_witch_mode = CreateConVar("pet_witch_mode", "1", "1 = Witch Day (Trượt khóc sau lưng), 0 = Nổi Điên (Cắm đầu chạy theo chủ)");
	cv_pet_duration = CreateConVar("pet_duration", "2", "Số chapter khế ước tồn tại");

	cv_req_mode_si = CreateConVar("pet_req_mode_si", "0");
	cv_req_shared = CreateConVar("pet_req_shared", "5");
	cv_req_tank = CreateConVar("pet_req_tank", "1");
	cv_req_witch = CreateConVar("pet_req_witch", "1");
	cv_req_smoker = CreateConVar("pet_req_smoker", "2");
	cv_req_boomer = CreateConVar("pet_req_boomer", "2");
	cv_req_hunter = CreateConVar("pet_req_hunter", "3");
	cv_req_spitter = CreateConVar("pet_req_spitter", "2");
	cv_req_jockey = CreateConVar("pet_req_jockey", "3");
	cv_req_charger = CreateConVar("pet_req_charger", "3");

	RegConsoleCmd("sm_callpet", Command_CallPet, "Mở menu gọi Pet");
	RegConsoleCmd("sm_freepet", Command_FreePet, "Giải phóng Pet hiện tại");
	RegConsoleCmd("sm_petinv", Command_PetInv, "Kiểm tra kho đồ không gian");
	
	HookEvent("map_transition", Event_MapTransition);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("witch_killed", Event_WitchKilled);

	AddNormalSoundHook(Hook_NormalSound);
	AddAmbientSoundHook(Hook_AmbientSound);

	CreateTimer(0.1, Timer_WitchUpdate, _, TIMER_REPEAT);
	CreateTimer(1.0, Timer_ScavengeAndGive, _, TIMER_REPEAT); 

	AutoExecConfig(true, "l4d2_absolute_loyalty");

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) { SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage); SDKHook(i, SDKHook_TraceAttack, OnTraceAttack); }
	}
}

// ==========================================
// BỘ LỌC SÁT THƯƠNG HOÀN HẢO (CHẶN FRIENDLY FIRE & KNOCKBACK)
// ==========================================
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	// 1. Bảo vệ Pet khỏi sát thương bên ngoài
	if (victim > 0 && victim <= MaxClients && g_iPetOwner[victim] > 0) {
		if (damage > 9000.0) return Plugin_Continue; // Cho phép chết do script/rơi vực
		damage = 0.0; return Plugin_Handled; 
	}
	int wOwner = 0; for (int i = 1; i <= MaxClients; i++) { if (EntRefToEntIndex(g_iWitchPet[i]) == victim) { wOwner = i; break; } }
	if (wOwner > 0) { damage = 0.0; return Plugin_Handled; }
	
	// 2. Chặn tuyệt đối sát thương từ Pet SI lên Chủ nhân và Survivors
	if (attacker > 0 && attacker <= MaxClients && g_iPetOwner[attacker] > 0) {
		if (victim > 0 && victim <= MaxClients && GetClientTeam(victim) == 2) {
			damage = 0.0; return Plugin_Handled;
		}
	}

	// 3. Chặn tuyệt đối sát thương từ Pet Witch lên Chủ nhân và Survivors
	if (attacker > MaxClients && IsValidEntity(attacker)) {
		char cls[32]; GetEntityClassname(attacker, cls, sizeof(cls));
		if (StrEqual(cls, "witch")) {
			bool isWitchPet = false;
			for (int i = 1; i <= MaxClients; i++) { if (EntRefToEntIndex(g_iWitchPet[i]) == attacker) { isWitchPet = true; break; } }
			if (isWitchPet && victim > 0 && victim <= MaxClients && GetClientTeam(victim) == 2) {
				damage = 0.0; return Plugin_Handled;
			}
		}
	}
	
	return Plugin_Continue;
}

public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup) {
	// Lặp lại logic bảo vệ 100% trong TraceAttack để chặn đạn/vật lý
	if (victim > 0 && victim <= MaxClients && g_iPetOwner[victim] > 0) return Plugin_Handled; 
	int wOwner = 0; for (int i = 1; i <= MaxClients; i++) { if (EntRefToEntIndex(g_iWitchPet[i]) == victim) { wOwner = i; break; } }
	if (wOwner > 0) return Plugin_Handled; 
	
	if (attacker > 0 && attacker <= MaxClients && g_iPetOwner[attacker] > 0) {
		if (victim > 0 && victim <= MaxClients && GetClientTeam(victim) == 2) { damage = 0.0; return Plugin_Handled; }
	}
	
	if (attacker > MaxClients && IsValidEntity(attacker)) {
		char cls[32]; GetEntityClassname(attacker, cls, sizeof(cls));
		if (StrEqual(cls, "witch")) {
			bool isWitchPet = false;
			for (int i = 1; i <= MaxClients; i++) { if (EntRefToEntIndex(g_iWitchPet[i]) == attacker) { isWitchPet = true; break; } }
			if (isWitchPet && victim > 0 && victim <= MaxClients && GetClientTeam(victim) == 2) { damage = 0.0; return Plugin_Handled; }
		}
	}
	return Plugin_Continue;
}

// ==========================================
// HỆ THỐNG LƯU TRỮ KHÓA DỮ LIỆU
// ==========================================
void SaveClientData(int client) {
	if (IsFakeClient(client)) return;
	char authID[32]; GetClientAuthId(client, AuthId_Steam2, authID, sizeof(authID));
	char path[PLATFORM_MAX_PATH]; BuildPath(Path_SM, path, sizeof(path), "data/pet_loyalty_data.txt");
	
	KeyValues kv = new KeyValues("PetData"); FileToKeyValues(kv, path);
	if (kv.JumpToKey(authID, true)) {
		kv.SetNum("Kills_SI", g_iKills_SI[client]); kv.SetNum("Kills_Tank", g_iKills_Tank[client]); kv.SetNum("Kills_Witch", g_iKills_Witch[client]);
		for (int i = 1; i <= 6; i++) { char key[16]; Format(key, sizeof(key), "Kill_Spc_%d", i); kv.SetNum(key, g_iKills_Specific[client][i]); }
		for (int i = 0; i < MAX_ITEMS; i++) { char key[16]; Format(key, sizeof(key), "Inv_%d", i); kv.SetNum(key, g_iPetInv[client][i]); }
		kv.GoBack();
	}
	KeyValuesToFile(kv, path); delete kv;
}

void LoadClientData(int client) {
	if (IsFakeClient(client)) return;
	char authID[32]; GetClientAuthId(client, AuthId_Steam2, authID, sizeof(authID));
	char path[PLATFORM_MAX_PATH]; BuildPath(Path_SM, path, sizeof(path), "data/pet_loyalty_data.txt");
	
	KeyValues kv = new KeyValues("PetData");
	if (FileToKeyValues(kv, path)) {
		if (kv.JumpToKey(authID)) {
			g_iKills_SI[client] = kv.GetNum("Kills_SI", 0); g_iKills_Tank[client] = kv.GetNum("Kills_Tank", 0); g_iKills_Witch[client] = kv.GetNum("Kills_Witch", 0);
			for (int i = 1; i <= 6; i++) { char key[16]; Format(key, sizeof(key), "Kill_Spc_%d", i); g_iKills_Specific[client][i] = kv.GetNum(key, 0); }
			for (int i = 0; i < MAX_ITEMS; i++) { char key[16]; Format(key, sizeof(key), "Inv_%d", i); g_iPetInv[client][i] = kv.GetNum(key, 0); }
		}
	} delete kv;
}

public void OnClientAuthorized(int client, const char[] auth) { LoadClientData(client); }
public void OnClientDisconnect(int client) { SaveClientData(client); }

// ==========================================
// CHỨC NĂNG CHAT COMMANDS
// ==========================================
public Action Command_PetInv(int client, int args) {
	if (!IsClientInGame(client) || GetClientTeam(client) != 2) return Plugin_Handled;
	PrintToChat(client, "\x04[Hành Trang Hư Không]\x01 Vật phẩm Pet đang giữ:");
	PrintToChat(client, "\x05Hỗ Trợ:\x01 %d Túi Y Tế | %d Máy Sốc Điện", g_iPetInv[client][ITEM_MEDKIT], g_iPetInv[client][ITEM_DEFIB]);
	PrintToChat(client, "\x05Thuốc:\x01 %d Pills | %d Adrenaline", g_iPetInv[client][ITEM_PILLS], g_iPetInv[client][ITEM_ADREN]);
	PrintToChat(client, "\x05Vũ Khí Ném:\x01 %d Molotov | %d Pipebomb | %d Vomitjar", g_iPetInv[client][ITEM_MOLOTOV], g_iPetInv[client][ITEM_PIPE], g_iPetInv[client][ITEM_VOMIT]);
	return Plugin_Handled;
}

public Action Command_FreePet(int client, int args) {
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != 2) return Plugin_Handled;
	bool hasPet = false; int pet = GetPetOfOwner(client);
	if (pet > 0) { SetEntProp(pet, Prop_Data, "m_takedamage", 2); ForcePlayerSuicide(pet); g_iPetOwner[pet] = 0; hasPet = true; }
	int witch = EntRefToEntIndex(g_iWitchPet[client]);
	if (witch > 0 && IsValidEntity(witch)) { AcceptEntityInput(witch, "Kill"); g_iWitchPet[client] = 0; hasPet = true; }
	
	if (hasPet) { g_iPlayerPetClass[client] = 0; g_iPlayerPetLifespan[client] = 0; PrintToChat(client, "\x04[Pet]\x01 Giải trừ khế ước thành công."); }
	else PrintToChat(client, "\x04[Pet]\x01 Bạn không sở hữu Pet nào.");
	return Plugin_Handled;
}

// ==========================================
// THU THẬP LINH HỒN
// ==========================================
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid")); int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && GetClientTeam(attacker) == 2) {
		if (victim > 0 && victim <= MaxClients && IsClientInGame(victim) && GetClientTeam(victim) == 3 && g_iPetOwner[victim] == 0) {
			int zclass = GetEntProp(victim, Prop_Send, "m_zombieClass");
			if (zclass == 8) g_iKills_Tank[attacker]++; else if (zclass >= 1 && zclass <= 6) { g_iKills_SI[attacker]++; g_iKills_Specific[attacker][zclass]++; }
		}
	}
}

public void Event_WitchKilled(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("userid"));
	if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && GetClientTeam(attacker) == 2) g_iKills_Witch[attacker]++;
}

// ==========================================
// MENU TRIỆU HỒI
// ==========================================
int GetSpecificReq(int zclass) {
	switch(zclass) { case 1: return cv_req_smoker.IntValue; case 2: return cv_req_boomer.IntValue; case 3: return cv_req_hunter.IntValue; case 4: return cv_req_spitter.IntValue; case 5: return cv_req_jockey.IntValue; case 6: return cv_req_charger.IntValue; } return 99;
}

public Action Command_CallPet(int client, int args) {
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != 2) return Plugin_Handled;
	int mode = cv_req_mode_si.IntValue; Menu menu = new Menu(MenuHandler_CallPet);
	if (mode == 0) menu.SetTitle("Khế Ước (Tổng Hợp)\nHồn SI: %d | Tank: %d | Witch: %d\n ", g_iKills_SI[client], g_iKills_Tank[client], g_iKills_Witch[client]);
	else menu.SetTitle("Khế Ước (Săn Đích Danh)\nTank Kill: %d | Witch Kill: %d\n ", g_iKills_Tank[client], g_iKills_Witch[client]);
	
	char itemTitle[128]; int clss[] = {3, 1, 6, 5, 4, 2}; char nms[][] = {"", "Smoker", "Boomer", "Hunter", "Spitter", "Jockey", "Charger"};
	for (int i = 0; i < 6; i++) {
		int c = clss[i]; char idxStr[8]; IntToString(c, idxStr, sizeof(idxStr));
		if (mode == 0) { Format(itemTitle, sizeof(itemTitle), "%s (Cần: %d Hồn)", nms[c], cv_req_shared.IntValue); } 
		else { Format(itemTitle, sizeof(itemTitle), "%s (Cần: %d - Bạn có: %d)", nms[c], GetSpecificReq(c), g_iKills_Specific[client][c]); }
		menu.AddItem(idxStr, itemTitle);
	}
	Format(itemTitle, sizeof(itemTitle), "[BOSS] Tank (Cần: %d - Bạn có: %d)", cv_req_tank.IntValue, g_iKills_Tank[client]); menu.AddItem("8", itemTitle);
	Format(itemTitle, sizeof(itemTitle), "[BOSS] Witch (Cần: %d - Bạn có: %d)", cv_req_witch.IntValue, g_iKills_Witch[client]); menu.AddItem("9", itemTitle);

	menu.Display(client, 20); return Plugin_Handled;
}

public int MenuHandler_CallPet(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		char info[32]; menu.GetItem(param2, info, sizeof(info)); int zclass = StringToInt(info); int client = param1;
		if (zclass == 8) { int req = cv_req_tank.IntValue; if (g_iKills_Tank[client] < req) { PrintToChat(client, "\x04[Pet]\x01 Không đủ hồn Tank."); return 0; } g_iKills_Tank[client] -= req; }
		else if (zclass == 9) { int req = cv_req_witch.IntValue; if (g_iKills_Witch[client] < req) { PrintToChat(client, "\x04[Pet]\x01 Không đủ hồn Witch."); return 0; } g_iKills_Witch[client] -= req; }
		else {
			int mode = cv_req_mode_si.IntValue;
			if (mode == 0) { int req = cv_req_shared.IntValue; if (g_iKills_SI[client] < req) { PrintToChat(client, "\x04[Pet]\x01 Không đủ hồn SI."); return 0; } g_iKills_SI[client] -= req; } 
			else { int req = GetSpecificReq(zclass); if (g_iKills_Specific[client][zclass] < req) { PrintToChat(client, "\x04[Pet]\x01 Không đủ hồn lớp này."); return 0; } g_iKills_Specific[client][zclass] -= req; }
		}

		SpawnPetForClient(client, zclass, true);
		int dur = cv_pet_duration.IntValue; int lifespan = (zclass >= 8) ? 1 : ((dur > 0) ? dur : 0); g_iPlayerPetLifespan[client] = lifespan;

		if (lifespan > 0) PrintToChat(client, "\x04[Pet]\x01 Triệu hồi thành công! Thời hạn: %d Chapter.", lifespan);
		else PrintToChat(client, "\x04[Pet]\x01 Triệu hồi thành công! Pet vô hạn.");
	}
	else if (action == MenuAction_End) { delete menu; } return 0;
}

int GetPetOfOwner(int owner) { for (int i = 1; i <= MaxClients; i++) { if (IsClientInGame(i) && g_iPetOwner[i] == owner) return i; } return 0; }

void SpawnPetForClient(int client, int zclass, bool isNew) {
	int oldPet = GetPetOfOwner(client); if (oldPet > 0) { SetEntProp(oldPet, Prop_Data, "m_takedamage", 2); ForcePlayerSuicide(oldPet); g_iPetOwner[oldPet] = 0; }
	int oldWitch = EntRefToEntIndex(g_iWitchPet[client]); if (oldWitch > 0 && IsValidEntity(oldWitch)) AcceptEntityInput(oldWitch, "Kill"); g_iWitchPet[client] = 0;

	if (isNew) { g_iPlayerPetClass[client] = zclass; }
	if (zclass == 9) {
		int witch = CreateEntityByName("witch"); float pos[3]; GetClientAbsOrigin(client, pos);
		TeleportEntity(witch, pos, NULL_VECTOR, NULL_VECTOR); DispatchSpawn(witch); g_iWitchPet[client] = EntIndexToEntRef(witch); return;
	}

	char zNames[][] = {"", "smoker", "boomer", "hunter", "spitter", "jockey", "charger", "", "tank"};
	int flags = GetCommandFlags("z_spawn"); SetCommandFlags("z_spawn", flags & ~FCVAR_CHEAT);
	char cmd[64]; Format(cmd, sizeof(cmd), "z_spawn %s auto", zNames[zclass]); FakeClientCommand(client, cmd); SetCommandFlags("z_spawn", flags);
	CreateTimer(0.1, Timer_AssignPet, GetClientUserId(client));
}

public Action Timer_AssignPet(Handle timer, int userid) {
	int client = GetClientOfUserId(userid); if (!client) return Plugin_Continue;
	for (int i = MaxClients; i >= 1; i--) {
		if (IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) == 3 && IsPlayerAlive(i) && g_iPetOwner[i] == 0) {
			g_iPetOwner[i] = client; g_iAttackCooldown[i] = 0; g_iAttackState[i] = 0; g_iScavengeTarget[i] = 0; g_bIsRescuing[i] = false;
			SetEntProp(i, Prop_Send, "m_iGlowType", 3); SetEntProp(i, Prop_Send, "m_glowColorOverride", 65280); 
			SetEntProp(i, Prop_Send, "m_CollisionGroup", 10); SetEntProp(i, Prop_Data, "m_bloodColor", -1); SetEntProp(i, Prop_Data, "m_takedamage", 0);  
			float ownerPos[3]; GetClientAbsOrigin(client, ownerPos); TeleportEntity(i, ownerPos, NULL_VECTOR, NULL_VECTOR); break; 
		}
	} return Plugin_Continue;
}

public void Event_MapTransition(Event event, const char[] name, bool dontBroadcast) {
	if (cv_pet_duration.IntValue > 0) {
		for (int i = 1; i <= MaxClients; i++) { if (g_iPlayerPetClass[i] > 0) { g_iPlayerPetLifespan[i]--; if (g_iPlayerPetLifespan[i] <= 0) g_iPlayerPetClass[i] = 0; } }
	}
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2) {
		if (g_iPlayerPetClass[client] > 0 && GetPetOfOwner(client) == 0 && EntRefToEntIndex(g_iWitchPet[client]) <= 0) { CreateTimer(3.0, Timer_RespawnPet, GetClientUserId(client)); }
	}
}
public Action Timer_RespawnPet(Handle timer, int userid) {
	int client = GetClientOfUserId(userid);
	if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == 2) { if (g_iPlayerPetClass[client] > 0) { SpawnPetForClient(client, g_iPlayerPetClass[client], false); } }
	return Plugin_Continue;
}

// ==========================================
// BỘ LỌC ÂM THANH
// ==========================================
public Action Hook_NormalSound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed) {
	if (entity > 0 && entity <= MaxClients && g_iPetOwner[entity] > 0) return Plugin_Handled;
	if (entity > MaxClients && IsValidEntity(entity)) {
		char cls[32]; GetEntityClassname(entity, cls, sizeof(cls));
		if (StrEqual(cls, "witch")) {
			bool isPet = false; for (int i = 1; i <= MaxClients; i++) { if (EntRefToEntIndex(g_iWitchPet[i]) == entity) { isPet = true; break; } }
			if (isPet) { if (cv_pet_witch_mode.IntValue == 1) { if (StrContains(sample, "mad") != -1 || StrContains(sample, "attack") != -1 || StrContains(sample, "startle") != -1 || StrContains(sample, "incapacitated") != -1) return Plugin_Handled; } }
		}
	} return Plugin_Continue;
}

public Action Hook_AmbientSound(char sample[PLATFORM_MAX_PATH], int &entity, float &volume, int &level, int &pitch, float pos[3], int &flags, float &delay) {
	if (StrContains(sample, "tank") != -1 && StrContains(sample, "music") != -1) {
		bool enemyTank = false; for (int i = 1; i <= MaxClients; i++) { if (IsClientInGame(i) && GetClientTeam(i) == 3 && GetEntProp(i, Prop_Send, "m_zombieClass") == 8 && g_iPetOwner[i] == 0) { enemyTank = true; break; } }
		if (!enemyTank) return Plugin_Handled; 
	}
	if (StrContains(sample, "witch") != -1 && StrContains(sample, "music") != -1) {
		bool enemyWitch = false; int ent = -1;
		while ((ent = FindEntityByClassname(ent, "witch")) != -1) {
			bool isPet = false; for (int i = 1; i <= MaxClients; i++) { if (EntRefToEntIndex(g_iWitchPet[i]) == ent) { isPet = true; break; } }
			if (!isPet) { enemyWitch = true; break; }
		} if (!enemyWitch) return Plugin_Handled;
	} return Plugin_Continue;
}

// ==========================================
// HỆ THỐNG QUẢN GIA: AUTO-SCAVENGE & AUTO-GIVE (1.0s/lần)
// ==========================================
int PickRandomAvailable(int client, int itemA, int itemB, int itemC = -1) {
	int count = 0; int av[3];
	if (g_iPetInv[client][itemA] > 0) av[count++] = itemA; if (g_iPetInv[client][itemB] > 0) av[count++] = itemB; if (itemC != -1 && g_iPetInv[client][itemC] > 0) av[count++] = itemC;
	if (count == 0) return -1; return av[GetRandomInt(0, count - 1)];
}

public Action Timer_ScavengeAndGive(Handle timer) {
	bool canScavenge = cv_pet_scavenge_enable.BoolValue;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2 && (GetPetOfOwner(i) > 0 || EntRefToEntIndex(g_iWitchPet[i]) > 0)) {
			float oPos[3]; GetClientAbsOrigin(i, oPos);
			
			if (GetPlayerWeaponSlot(i, 3) == -1) {
				int prio = cv_pet_prio_med.IntValue; int giveItem = -1;
				if (prio == 0) { if (g_iPetInv[i][ITEM_MEDKIT] > 0) giveItem = ITEM_MEDKIT; else if (g_iPetInv[i][ITEM_DEFIB] > 0) giveItem = ITEM_DEFIB; }
				else if (prio == 1) { if (g_iPetInv[i][ITEM_DEFIB] > 0) giveItem = ITEM_DEFIB; else if (g_iPetInv[i][ITEM_MEDKIT] > 0) giveItem = ITEM_MEDKIT; }
				else giveItem = PickRandomAvailable(i, ITEM_MEDKIT, ITEM_DEFIB);
				if (giveItem != -1) { g_iPetInv[i][giveItem]--; int wep = CreateEntityByName(g_sItemClasses[giveItem]); DispatchSpawn(wep); EquipPlayerWeapon(i, wep); PrintToChat(i, "\x04[Pet Quản Gia]\x01 Cung cấp \x05%s\x01.", g_sItemNames[giveItem]); }
			}

			if (GetPlayerWeaponSlot(i, 4) == -1) {
				int prio = cv_pet_prio_pill.IntValue; int giveItem = -1;
				if (prio == 0) { if (g_iPetInv[i][ITEM_PILLS] > 0) giveItem = ITEM_PILLS; else if (g_iPetInv[i][ITEM_ADREN] > 0) giveItem = ITEM_ADREN; }
				else if (prio == 1) { if (g_iPetInv[i][ITEM_ADREN] > 0) giveItem = ITEM_ADREN; else if (g_iPetInv[i][ITEM_PILLS] > 0) giveItem = ITEM_PILLS; }
				else giveItem = PickRandomAvailable(i, ITEM_PILLS, ITEM_ADREN);
				if (giveItem != -1) { g_iPetInv[i][giveItem]--; int wep = CreateEntityByName(g_sItemClasses[giveItem]); DispatchSpawn(wep); EquipPlayerWeapon(i, wep); PrintToChat(i, "\x04[Pet Quản Gia]\x01 Cung cấp \x05%s\x01.", g_sItemNames[giveItem]); }
			}

			if (GetPlayerWeaponSlot(i, 2) == -1) {
				int prio = cv_pet_prio_nade.IntValue; int giveItem = -1;
				if (prio == 0) giveItem = (g_iPetInv[i][ITEM_MOLOTOV] > 0) ? ITEM_MOLOTOV : PickRandomAvailable(i, ITEM_PIPE, ITEM_VOMIT);
				else if (prio == 1) giveItem = (g_iPetInv[i][ITEM_PIPE] > 0) ? ITEM_PIPE : PickRandomAvailable(i, ITEM_MOLOTOV, ITEM_VOMIT);
				else if (prio == 2) giveItem = (g_iPetInv[i][ITEM_VOMIT] > 0) ? ITEM_VOMIT : PickRandomAvailable(i, ITEM_MOLOTOV, ITEM_PIPE);
				else giveItem = PickRandomAvailable(i, ITEM_MOLOTOV, ITEM_PIPE, ITEM_VOMIT);
				if (giveItem != -1) { g_iPetInv[i][giveItem]--; int wep = CreateEntityByName(g_sItemClasses[giveItem]); DispatchSpawn(wep); EquipPlayerWeapon(i, wep); PrintToChat(i, "\x04[Pet Quản Gia]\x01 Cung cấp hỏa lực \x05%s\x01.", g_sItemNames[giveItem]); }
			}

			if (canScavenge) {
				int bot = GetPetOfOwner(i); if (bot == 0) bot = EntRefToEntIndex(g_iWitchPet[i]);
				if (bot > 0 && IsValidEntity(bot)) {
					if (EntRefToEntIndex(g_iScavengeTarget[i]) <= 0) {
						int bestEnt = -1; float bestDist = 300.0; // ĐÃ GIẢM TẦM NHẶT ĐỒ XUỐNG 300.0
						int ent = -1;
						while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1) {
							if (IsValidEntity(ent) && GetEntPropEnt(ent, Prop_Data, "m_hOwnerEntity") == -1) {
								char cls[64]; GetEntityClassname(ent, cls, sizeof(cls)); bool isTarget = false;
								if (StrContains(cls, "first_aid_kit") != -1 && cv_pet_scavenge_medkit.BoolValue) isTarget = true;
								else if (StrContains(cls, "defibrillator") != -1 && cv_pet_scavenge_defib.BoolValue) isTarget = true;
								else if (StrContains(cls, "pain_pills") != -1 || StrContains(cls, "adrenaline") != -1) isTarget = true;
								else if (StrContains(cls, "molotov") != -1 || StrContains(cls, "pipe_bomb") != -1 || StrContains(cls, "vomitjar") != -1) isTarget = true;
								if (isTarget) { float iPos[3]; GetEntPropVector(ent, Prop_Send, "m_vecOrigin", iPos); float d = GetVectorDistance(oPos, iPos); if (d < bestDist) { bestDist = d; bestEnt = ent; } }
							}
						}
						if (bestEnt != -1) { g_iScavengeTarget[i] = EntIndexToEntRef(bestEnt); g_iScavengeTicks[i] = 0; }
					}
				}
			}
		}
	} return Plugin_Continue;
}

void AbsorbItem(int owner, int itemEnt) {
	char cls[64]; GetEntityClassname(itemEnt, cls, sizeof(cls)); int type = -1;
	if (StrContains(cls, "first_aid_kit") != -1) type = ITEM_MEDKIT; else if (StrContains(cls, "defibrillator") != -1) type = ITEM_DEFIB; else if (StrContains(cls, "pain_pills") != -1) type = ITEM_PILLS; else if (StrContains(cls, "adrenaline") != -1) type = ITEM_ADREN; else if (StrContains(cls, "molotov") != -1) type = ITEM_MOLOTOV; else if (StrContains(cls, "pipe_bomb") != -1) type = ITEM_PIPE; else if (StrContains(cls, "vomitjar") != -1) type = ITEM_VOMIT;
	if (type != -1) { g_iPetInv[owner][type]++; AcceptEntityInput(itemEnt, "Kill"); PrintHintText(owner, "Pet vừa lượm %s vào không gian!", g_sItemNames[type]); }
	g_iScavengeTarget[owner] = 0; g_iScavengeTicks[owner] = 0;
}

// ==========================================
// THUẬT TOÁN ĐO QUÉT & BẢN ĐỒ
// ==========================================
public bool TraceFilter_Quantum(int entity, int contentsMask) {
	if (entity == 0) return true; if (entity >= 1 && entity <= MaxClients) return false; char c[64]; GetEntityClassname(entity, c, sizeof(c));
	if (StrContains(c, "infected") != -1 || StrContains(c, "witch") != -1 || StrContains(c, "trigger_") != -1 || StrContains(c, "prop_detail") != -1) return false; return true; 
}
public bool TraceFilter_LOS(int entity, int contentsMask) {
	if (entity == 0) return true; if (entity >= 1 && entity <= MaxClients) return false; char classname[64]; GetEntityClassname(entity, classname, sizeof(classname));
	if (StrContains(classname, "infected") != -1 || StrContains(classname, "witch") != -1) return false; return TraceFilter_Quantum(entity, contentsMask);
}
bool IsTargetVisible(float startPos[3], float targetPos[3]) {
	float sPos[3]; sPos[0] = startPos[0]; sPos[1] = startPos[1]; sPos[2] = startPos[2] + 40.0; float tPos[3]; tPos[0] = targetPos[0]; tPos[1] = targetPos[1]; tPos[2] = targetPos[2] + 40.0; 
	Handle tr = TR_TraceRayFilterEx(sPos, tPos, MASK_OPAQUE, RayType_EndPoint, TraceFilter_LOS); bool hit = TR_DidHit(tr); delete tr; return !hit; 
}

void AddSpatialMemoryNode(float pos[3]) {
	for (int i = 0; i < g_iMemoryCount; i++) { if (GetVectorDistance(pos, g_vecSpatialMemory[i]) < 150.0) return; }
	if (g_iMemoryCount >= MAX_MEMORY_NODES) { for (int i = 0; i < MAX_MEMORY_NODES - 1; i++) g_vecSpatialMemory[i] = g_vecSpatialMemory[i+1]; g_iMemoryCount = MAX_MEMORY_NODES - 1; }
	g_vecSpatialMemory[g_iMemoryCount][0] = pos[0]; g_vecSpatialMemory[g_iMemoryCount][1] = pos[1]; g_vecSpatialMemory[g_iMemoryCount][2] = pos[2]; g_iMemoryCount++;
}

bool QuerySpatialMemory(float botPos[3], float targetPos[3], float bestPos[3]) {
	if (g_iMemoryCount == 0) return false; float bestScore = 999999.0; int bestIndex = -1;
	for (int i = g_iMemoryCount - 1; i >= 0; i--) {
		float nodePos[3]; nodePos[0] = g_vecSpatialMemory[i][0]; nodePos[1] = g_vecSpatialMemory[i][1]; nodePos[2] = g_vecSpatialMemory[i][2];
		float distToNode = GetVectorDistance(botPos, nodePos); if (distToNode > 500.0) continue; 
		if (IsTargetVisible(botPos, nodePos)) { float distFromNodeToTarget = GetVectorDistance(nodePos, targetPos); float currentDistToTarget = GetVectorDistance(botPos, targetPos); if (distFromNodeToTarget < currentDistToTarget) { float score = distToNode + distFromNodeToTarget; if (score < bestScore) { bestScore = score; bestIndex = i; } } }
	}
	if (bestIndex != -1) { bestPos[0] = g_vecSpatialMemory[bestIndex][0]; bestPos[1] = g_vecSpatialMemory[bestIndex][1]; bestPos[2] = g_vecSpatialMemory[bestIndex][2]; return true; } return false;
}

bool FindHeuristicEscapeRoute(float startPos[3], float originalDir[3], float targetPos[3], float bestDir[3]) {
	float scanStart[3]; scanStart[0] = startPos[0]; scanStart[1] = startPos[1]; scanStart[2] = startPos[2] + 30.0;
	float distances[] = {40.0, 70.0, 100.0, 130.0}; float anglesToCheck[] = {0.0, 15.0, -15.0, 30.0, -30.0, 45.0, -45.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0}; float bestScore = 999999.0; bool foundPath = false; float mins[3] = {-16.0, -16.0, -10.0}; float maxs[3] = {16.0, 16.0, 40.0};
	for (int d = 0; d < sizeof(distances); d++) {
		for (int a = 0; a < sizeof(anglesToCheck); a++) {
			float rad = anglesToCheck[a] * 3.14159265 / 180.0; float rotDir[3]; rotDir[0] = originalDir[0] * Cosine(rad) - originalDir[1] * Sine(rad); rotDir[1] = originalDir[0] * Sine(rad) + originalDir[1] * Cosine(rad); rotDir[2] = 0.0; NormalizeVector(rotDir, rotDir);
			float endPos[3]; endPos[0] = scanStart[0] + rotDir[0] * distances[d]; endPos[1] = scanStart[1] + rotDir[1] * distances[d]; endPos[2] = scanStart[2];
			Handle tr = TR_TraceHullFilterEx(scanStart, endPos, mins, maxs, MASK_PLAYERSOLID, TraceFilter_Quantum); bool hit = TR_DidHit(tr); delete tr;
			if (!hit) { float heuristicCost = GetVectorDistance(endPos, targetPos); if (heuristicCost < bestScore) { bestScore = heuristicCost; bestDir[0] = rotDir[0]; bestDir[1] = rotDir[1]; bestDir[2] = rotDir[2]; foundPath = true; } }
		} if (foundPath) return true;
	} return foundPath;
}

int GetOwnerThreatLevel(int owner, float ownerPos[3], float ownerEyePos[3]) {
	int threatCount = 0; int ent = -1; float currentTime = GetGameTime();
	while ((ent = FindEntityByClassname(ent, "infected")) != -1) {
		if (!IsValidEntity(ent) || GetEntProp(ent, Prop_Data, "m_iHealth") <= 0) continue;
		float pos[3]; GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);
		if (IsTargetVisible(ownerEyePos, pos)) { if (ent >= 0 && ent < 2048) { g_vecThreatMemory[ent][0] = pos[0]; g_vecThreatMemory[ent][1] = pos[1]; g_vecThreatMemory[ent][2] = pos[2]; g_flThreatLastSeen[ent] = currentTime; } }
		if (GetVectorDistance(ownerPos, pos) <= 300.0) threatCount++;
	}
	for (int i = 1; i <= MaxClients; i++) {
		if (i != owner && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3 && g_iPetOwner[i] == 0) {
			float pos[3]; GetClientAbsOrigin(i, pos);
			if (IsTargetVisible(ownerEyePos, pos)) { if (i >= 0 && i < 2048) { g_vecThreatMemory[i][0] = pos[0]; g_vecThreatMemory[i][1] = pos[1]; g_vecThreatMemory[i][2] = pos[2]; g_flThreatLastSeen[i] = currentTime; } }
			if (GetVectorDistance(ownerPos, pos) <= 350.0) threatCount += 2; 
		}
	} return threatCount;
}

int FindNearestEnemyToPos(float centerPos[3], int botToIgnore, float maxDist, float botEyePos[3]) {
	int bestTarget = -1; float bestDist = maxDist; int ent = -1; float currentTime = GetGameTime();
	while ((ent = FindEntityByClassname(ent, "infected")) != -1) {
		if (!IsValidEntity(ent) || GetEntProp(ent, Prop_Data, "m_iHealth") <= 0) continue;
		float pos[3]; GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos); float d = GetVectorDistance(centerPos, pos);
		bool inMemory = false; if (ent >= 0 && ent < 2048) { inMemory = (currentTime - g_flThreatLastSeen[ent] < 10.0); }
		if (d < bestDist && (IsTargetVisible(botEyePos, pos) || inMemory)) { bestDist = d; bestTarget = ent; }
	}
	for (int i = 1; i <= MaxClients; i++) {
		if (i != botToIgnore && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3 && g_iPetOwner[i] == 0) {
			float pos[3]; GetClientAbsOrigin(i, pos); float d = GetVectorDistance(centerPos, pos);
			bool inMemory = false; if (i >= 0 && i < 2048) { inMemory = (currentTime - g_flThreatLastSeen[i] < 10.0); }
			if (d < bestDist && (IsTargetVisible(botEyePos, pos) || inMemory)) { bestDist = d; bestTarget = i; }
		}
	} return bestTarget;
}

bool ShouldJumpOverLedge(float botPos[3], float dir[3]) {
	float pFoot[3]; pFoot[0] = botPos[0]; pFoot[1] = botPos[1]; pFoot[2] = botPos[2] + 15.0; float pHead[3]; pHead[0] = botPos[0]; pHead[1] = botPos[1]; pHead[2] = botPos[2] + 60.0; float eFoot[3]; eFoot[0] = pFoot[0] + dir[0] * 50.0; eFoot[1] = pFoot[1] + dir[1] * 50.0; eFoot[2] = pFoot[2]; float eHead[3]; eHead[0] = pHead[0] + dir[0] * 50.0; eHead[1] = pHead[1] + dir[1] * 50.0; eHead[2] = pHead[2];
	Handle tFoot = TR_TraceRayFilterEx(pFoot, eFoot, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilter_Quantum); bool hitFoot = TR_DidHit(tFoot); delete tFoot;
	Handle tHead = TR_TraceRayFilterEx(pHead, eHead, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilter_Quantum); bool hitHead = TR_DidHit(tHead); delete tHead;
	return (hitFoot && !hitHead);
}

void ExecuteAntiStuckBlink(int bot, float botPos[3], float aimTargetPos[3]) {
	float dir[3]; MakeVectorFromPoints(botPos, aimTargetPos, dir); dir[2] = 0.0; NormalizeVector(dir, dir); float anglesToCheck[] = {0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0}; float mins[3] = {-16.0, -16.0, -10.0}; float maxs[3] = {16.0, 16.0, 40.0}; bool found = false;
	for (int i = 0; i < sizeof(anglesToCheck); i++) {
		float rad = anglesToCheck[i] * 3.14159265 / 180.0; float rotDir[3]; rotDir[0] = dir[0] * Cosine(rad) - dir[1] * Sine(rad); rotDir[1] = dir[0] * Sine(rad) + dir[1] * Cosine(rad); rotDir[2] = 0.0; float scanStart[3]; scanStart[0] = botPos[0]; scanStart[1] = botPos[1]; scanStart[2] = botPos[2] + 30.0; float testPos[3]; testPos[0] = scanStart[0] + rotDir[0] * 120.0; testPos[1] = scanStart[1] + rotDir[1] * 120.0; testPos[2] = scanStart[2];
		Handle tr = TR_TraceHullFilterEx(scanStart, testPos, mins, maxs, MASK_PLAYERSOLID, TraceFilter_Quantum); if (!TR_DidHit(tr)) { testPos[2] -= 30.0; TeleportEntity(bot, testPos, NULL_VECTOR, NULL_VECTOR); found = true; delete tr; break; } delete tr;
	}
	if (!found) { int owner = g_iPetOwner[bot]; if (owner > 0 && IsClientInGame(owner)) { float oPos[3]; GetClientAbsOrigin(owner, oPos); TeleportEntity(bot, oPos, NULL_VECTOR, NULL_VECTOR); } }
}

float GetDamageForClass(int zclass) {
	float baseDmg = 1000.0;
	switch(zclass) {
		case 1: baseDmg = cv_dmg_smoker.FloatValue; case 2: baseDmg = cv_dmg_boomer.FloatValue; case 3: baseDmg = cv_dmg_hunter.FloatValue;
		case 4: baseDmg = cv_dmg_spitter.FloatValue; case 5: baseDmg = cv_dmg_jockey.FloatValue; case 6: baseDmg = cv_dmg_charger.FloatValue; case 8: baseDmg = cv_dmg_tank.FloatValue;
	} return baseDmg * cv_pet_damage_multiplier.FloatValue;
}

void TryHitTarget(int bot, int owner, int victim, float botPos[3], float centerDir[3]) {
	float targetPos[3], dirToVictim[3]; GetEntPropVector(victim, Prop_Send, "m_vecOrigin", targetPos); float dist = GetVectorDistance(botPos, targetPos);
	if (dist <= 160.0) {
		MakeVectorFromPoints(botPos, targetPos, dirToVictim); dirToVictim[2] = 0.0; NormalizeVector(dirToVictim, dirToVictim);
		if (GetVectorDotProduct(centerDir, dirToVictim) >= 0.866 || dist <= 60.0) {
			float knockback[3]; int petClass = GetEntProp(bot, Prop_Send, "m_zombieClass"); float customDmg = GetDamageForClass(petClass);
			if (g_bIsRescuing[bot] && victim >= 1 && victim <= MaxClients) {
				int zClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
				if (zClass != 6 && zClass != 8) { knockback[0] = dirToVictim[0] * 2200.0; knockback[1] = dirToVictim[1] * 2200.0; knockback[2] = 500.0; targetPos[2] += 10.0; TeleportEntity(victim, targetPos, NULL_VECTOR, knockback); SDKHooks_TakeDamage(victim, bot, owner, 15.0, 64, -1, knockback, botPos); return; }
			}
			knockback[0] = dirToVictim[0] * 5000.0; knockback[1] = dirToVictim[1] * 5000.0; knockback[2] = 1500.0; targetPos[2] += 10.0; TeleportEntity(victim, targetPos, NULL_VECTOR, knockback);
			int damageType = 16 | 64 | 128 | 8192; SDKHooks_TakeDamage(victim, bot, owner, customDmg, damageType, -1, knockback, botPos);
		}
	}
}

int GetPinnedAttacker(int victim) {
	if (!IsClientInGame(victim) || !IsPlayerAlive(victim)) return -1;
	int attacker = GetEntPropEnt(victim, Prop_Send, "m_pounceAttacker"); if (attacker > 0) return attacker; attacker = GetEntPropEnt(victim, Prop_Send, "m_tongueOwner"); if (attacker > 0) return attacker; attacker = GetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker"); if (attacker > 0) return attacker; attacker = GetEntPropEnt(victim, Prop_Send, "m_carryAttacker"); if (attacker > 0) return attacker; attacker = GetEntPropEnt(victim, Prop_Send, "m_pummelAttacker"); if (attacker > 0) return attacker; return -1;
}

// ==========================================
// WITCH AI: CƯỠNG CHẾ TỌA ĐỘ VÀ SÁT THƯƠNG COOLDOWN
// ==========================================
public Action Timer_WitchUpdate(Handle timer)
{
	float customDmg = cv_dmg_witch.FloatValue * cv_pet_damage_multiplier.FloatValue;
	int mode = cv_pet_witch_mode.IntValue; bool attackEnabled = cv_pet_attack_enable.BoolValue; float curTime = GetGameTime();

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && IsPlayerAlive(i) && g_iPlayerPetClass[i] == 9) {
			int witch = EntRefToEntIndex(g_iWitchPet[i]);
			if (witch > 0 && IsValidEntity(witch)) {
				SetEntProp(witch, Prop_Send, "m_iGlowType", 3); SetEntProp(witch, Prop_Send, "m_glowColorOverride", 65280); 
				SetEntProp(witch, Prop_Data, "m_takedamage", 0); SetEntProp(witch, Prop_Send, "m_CollisionGroup", 10);
				
				float oPos[3], wPos[3]; GetClientAbsOrigin(i, oPos); GetEntPropVector(witch, Prop_Send, "m_vecOrigin", wPos);
				if (GetVectorDistance(oPos, wPos) > 1000.0) { TeleportEntity(witch, oPos, NULL_VECTOR, NULL_VECTOR); }

				float aimPos[3]; bool isScavenging = false; int scTarget = EntRefToEntIndex(g_iScavengeTarget[i]);
				if (scTarget > 0 && IsValidEntity(scTarget)) {
					isScavenging = true; GetEntPropVector(scTarget, Prop_Send, "m_vecOrigin", aimPos); float d = GetVectorDistance(wPos, aimPos);
					g_iScavengeTicks[i]++; if (d < 60.0 || g_iScavengeTicks[i] > 20) { AbsorbItem(i, scTarget); isScavenging = false; }
				}

				if (!isScavenging) {
					if (mode == 1) { float fwd[3]; GetClientEyeAngles(i, fwd); GetAngleVectors(fwd, fwd, NULL_VECTOR, NULL_VECTOR); aimPos[0] = oPos[0] - fwd[0] * 120.0; aimPos[1] = oPos[1] - fwd[1] * 120.0; aimPos[2] = oPos[2]; } 
					else { aimPos[0] = oPos[0]; aimPos[1] = oPos[1]; aimPos[2] = oPos[2]; }
				}

				SetEntPropFloat(witch, Prop_Send, "m_rage", (mode == 1) ? 0.5 : 1.0);
				if (GetVectorDistance(wPos, aimPos) > 60.0) {
					float dir[3], ang[3]; MakeVectorFromPoints(wPos, aimPos, dir); dir[2] = 0.0; NormalizeVector(dir, dir); GetVectorAngles(dir, ang); ang[0] = 0.0;
					float speed = isScavenging ? 40.0 : ((mode == 1) ? 30.0 : 45.0); float nextPos[3]; nextPos[0] = wPos[0] + dir[0] * speed; nextPos[1] = wPos[1] + dir[1] * speed; nextPos[2] = wPos[2] + 30.0; 
					float rayEnd[3]; rayEnd[0] = nextPos[0]; rayEnd[1] = nextPos[1]; rayEnd[2] = nextPos[2] - 100.0; Handle tr = TR_TraceRayFilterEx(nextPos, rayEnd, MASK_SOLID, RayType_EndPoint, TraceFilter_Quantum); if (TR_DidHit(tr)) { float hitPos[3]; TR_GetEndPosition(hitPos, tr); nextPos[2] = hitPos[2] + 2.0; } delete tr;
					float zeroVel[3] = {0.0, 0.0, 0.0}; TeleportEntity(witch, nextPos, ang, zeroVel);
				}

				if (attackEnabled) {
					float dmgRadius = (mode == 1) ? 250.0 : 180.0; int ent = -1;
					while ((ent = FindEntityByClassname(ent, "infected")) != -1) {
						if (IsValidEntity(ent) && GetEntProp(ent, Prop_Data, "m_iHealth") > 0) {
							float pos[3]; GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);
							if (GetVectorDistance(wPos, pos) < dmgRadius) { if (curTime - g_flLastDamageTime[ent] >= 1.0) { float kb[3] = {0.0, 0.0, 600.0}; SDKHooks_TakeDamage(ent, witch, i, customDmg, 64, -1, kb, wPos); g_flLastDamageTime[ent] = curTime; } }
						}
					}
					for (int j = 1; j <= MaxClients; j++) {
						if (j != i && IsClientInGame(j) && IsPlayerAlive(j) && GetClientTeam(j) == 3 && g_iPetOwner[j] == 0) {
							float pos[3]; GetClientAbsOrigin(j, pos);
							if (GetVectorDistance(wPos, pos) < dmgRadius) { if (curTime - g_flLastDamageTime[j] >= 1.0) { float kb[3] = {0.0, 0.0, 600.0}; SDKHooks_TakeDamage(j, witch, i, customDmg, 64, -1, kb, wPos); g_flLastDamageTime[j] = curTime; } }
						}
					}
				}
			}
		}
	} return Plugin_Continue;
}

// ==========================================
// ĐIỀU KHIỂN SI PETS & HIVE MIND PATHFINDING
// ==========================================
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (IsClientInGame(client) && !IsFakeClient(client) && GetClientTeam(client) == 2) {
		float ownerPos[3]; GetClientAbsOrigin(client, ownerPos); float eyePos[3], eyeAngles[3], fwd[3]; GetClientEyePosition(client, eyePos); GetClientEyeAngles(client, eyeAngles); GetAngleVectors(eyeAngles, fwd, NULL_VECTOR, NULL_VECTOR);
		if (tickcount % 15 == 0 && (GetEntityFlags(client) & FL_ONGROUND)) {
			AddSpatialMemoryNode(ownerPos); float currentTime = GetGameTime();
			if (currentTime - g_flLastBreadcrumbTime[client] > 0.3) {
				if (g_iBreadcrumbCount[client] == 0 || GetVectorDistance(ownerPos, g_vecBreadcrumbs[client][g_iBreadcrumbCount[client]-1]) > 50.0) {
					if (g_iBreadcrumbCount[client] >= 64) { for (int i = 0; i < 63; i++) g_vecBreadcrumbs[client][i] = g_vecBreadcrumbs[client][i+1]; g_iBreadcrumbCount[client] = 63; }
					g_vecBreadcrumbs[client][g_iBreadcrumbCount[client]] = ownerPos; g_iBreadcrumbCount[client]++; g_flLastBreadcrumbTime[client] = currentTime;
				}
			}
		}
		if (tickcount % 30 == 0) {
			float endPos[3]; endPos[0] = eyePos[0] + fwd[0] * 1000.0; endPos[1] = eyePos[1] + fwd[1] * 1000.0; endPos[2] = eyePos[2] + fwd[2] * 1000.0;
			Handle tr = TR_TraceRayFilterEx(eyePos, endPos, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilter_Quantum);
			if (TR_DidHit(tr)) { float hitPos[3]; TR_GetEndPosition(hitPos, tr); float hitNormal[3]; TR_GetPlaneNormal(tr, hitNormal); if (hitNormal[2] > 0.7) AddSpatialMemoryNode(hitPos); } delete tr;
		}
	}

	if (IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == 2 && IsFakeClient(client)) {
		float eyePos[3], fwd[3]; GetClientEyePosition(client, eyePos); GetClientEyeAngles(client, fwd); GetAngleVectors(fwd, fwd, NULL_VECTOR, NULL_VECTOR);
		for (int i = 1; i <= MaxClients; i++) {
			if (g_iPetOwner[i] > 0) { float pC[3]; GetClientAbsOrigin(i, pC); pC[2] += 35.0; float vP[3]; SubtractVectors(pC, eyePos, vP); float proj = GetVectorDotProduct(vP, fwd); if (proj > 0.0 && proj < 1500.0) { float lp[3]; lp[0] = eyePos[0] + fwd[0]*proj; lp[1] = eyePos[1] + fwd[1]*proj; lp[2] = eyePos[2] + fwd[2]*proj; if (GetVectorDistance(pC, lp) <= 35.0) { buttons &= ~IN_ATTACK; break; } } }
		}
	}

	if (IsFakeClient(client) && g_iPetOwner[client] > 0) {
		int bot = client; int owner = g_iPetOwner[bot];
		if (!IsClientInGame(owner) || !IsPlayerAlive(owner)) { SetEntProp(bot, Prop_Data, "m_takedamage", 2); ForcePlayerSuicide(bot); g_iPetOwner[bot] = 0; return Plugin_Continue; }

		buttons = 0; int botFlags = GetEntityFlags(bot); if (!(botFlags & FL_NOTARGET)) SetEntityFlags(bot, botFlags | FL_NOTARGET);
		float zeroVec[3] = {0.0, 0.0, 0.0}; SetEntPropVector(bot, Prop_Data, "m_vecBaseVelocity", zeroVec); int zClass = GetEntProp(bot, Prop_Send, "m_zombieClass"); if (zClass == 8) SetEntProp(bot, Prop_Send, "m_frustration", 0);
		if (tickcount % 30 == 0) { int ability = GetEntPropEnt(bot, Prop_Send, "m_customAbility"); if (ability > 0 && IsValidEntity(ability)) SetEntPropFloat(ability, Prop_Send, "m_timestamp", GetGameTime() + 9999.0); }

		float botPos[3], ownerPos[3]; GetClientAbsOrigin(bot, botPos); GetClientAbsOrigin(owner, ownerPos); float ownerEyePos[3]; GetClientEyePosition(owner, ownerEyePos); float distToOwner = GetVectorDistance(botPos, ownerPos); float curTime = GetGameTime();

		if (cv_pet_attack_enable.BoolValue && tickcount % 10 == 0) {
			float customDmg = GetDamageForClass(zClass); int ent = -1;
			while ((ent = FindEntityByClassname(ent, "infected")) != -1) {
				if (IsValidEntity(ent) && GetEntProp(ent, Prop_Data, "m_iHealth") > 0) { float pos[3]; GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos); if (GetVectorDistance(botPos, pos) < 130.0) { if (curTime - g_flLastDamageTime[ent] >= 1.0) { float kb[3] = {0.0, 0.0, 400.0}; SDKHooks_TakeDamage(ent, bot, owner, customDmg, 64, -1, kb, botPos); g_flLastDamageTime[ent] = curTime; } } }
			}
			for (int j = 1; j <= MaxClients; j++) {
				if (j != bot && IsClientInGame(j) && IsPlayerAlive(j) && GetClientTeam(j) == 3 && g_iPetOwner[j] == 0) { float pos[3]; GetClientAbsOrigin(j, pos); if (GetVectorDistance(botPos, pos) < 130.0) { if (curTime - g_flLastDamageTime[j] >= 1.0) { float kb[3] = {0.0, 0.0, 400.0}; SDKHooks_TakeDamage(j, bot, owner, customDmg, 64, -1, kb, botPos); g_flLastDamageTime[j] = curTime; } } }
			}
		}

		if (tickcount % 10 == 0) { int threatLevel = GetOwnerThreatLevel(owner, ownerPos, ownerEyePos); g_bOwnerSwarmed[bot] = (threatLevel >= 4); }
		int pinnedAttacker = GetPinnedAttacker(owner); int target = -1;
		if (pinnedAttacker > 0 && IsValidEntity(pinnedAttacker)) { g_bIsRescuing[bot] = true; target = pinnedAttacker; } else if (g_bOwnerSwarmed[bot]) { g_bIsRescuing[bot] = true; target = FindNearestEnemyToPos(ownerPos, bot, 400.0, botPos); } else { g_bIsRescuing[bot] = false; target = FindNearestEnemyToPos(botPos, bot, 400.0, botPos); }
		if (g_iAttackCooldown[bot] > 0) g_iAttackCooldown[bot]--;

		if (target > 0 && IsValidEntity(target) && !g_bIsRescuing[bot]) {
			float tPos[3]; GetEntPropVector(target, Prop_Send, "m_vecOrigin", tPos);
			if (target <= MaxClients && GetClientTeam(target) == 3) { if (FloatAbs(botPos[2] - tPos[2]) > 60.0 || GetVectorDistance(botPos, tPos) > 450.0) { float tAngles[3], bwd[3]; GetClientEyeAngles(target, tAngles); GetAngleVectors(tAngles, bwd, NULL_VECTOR, NULL_VECTOR); float tpPos[3]; tpPos[0] = tPos[0] - bwd[0] * 40.0; tpPos[1] = tPos[1] - bwd[1] * 40.0; tpPos[2] = tPos[2] + 5.0; TeleportEntity(bot, tpPos, NULL_VECTOR, NULL_VECTOR); return Plugin_Changed; } }
		}

		float zDiff = FloatAbs(botPos[2] - ownerPos[2]); if (zDiff > 160.0 && !g_bIsRescuing[bot]) { TeleportEntity(bot, ownerPos, NULL_VECTOR, NULL_VECTOR); return Plugin_Changed; }

		if (g_bIsRescuing[bot]) {
			float teleThreshold = (pinnedAttacker > 0) ? 150.0 : 600.0;
			if (distToOwner > teleThreshold) { float rescueTeleportPos[3], ownerAngles[3], fwd[3], right[3]; GetClientEyeAngles(owner, ownerAngles); GetAngleVectors(ownerAngles, fwd, right, NULL_VECTOR); rescueTeleportPos[0] = ownerPos[0] - fwd[0] * 50.0 + right[0] * 30.0; rescueTeleportPos[1] = ownerPos[1] - fwd[1] * 50.0 + right[1] * 30.0; rescueTeleportPos[2] = ownerPos[2] + 10.0; TeleportEntity(bot, rescueTeleportPos, NULL_VECTOR, NULL_VECTOR); return Plugin_Changed; }
			else { if (target > 0 && IsValidEntity(target)) { float centerDir[3]; float tPos[3]; GetEntPropVector(target, Prop_Send, "m_vecOrigin", tPos); MakeVectorFromPoints(botPos, tPos, centerDir); centerDir[2] = 0.0; NormalizeVector(centerDir, centerDir); TryHitTarget(bot, owner, target, botPos, centerDir); } }
		} else if (distToOwner > 800.0) {
			bool teleSuccess = false; if (g_iBreadcrumbCount[owner] > 0) { for (int i = g_iBreadcrumbCount[owner] - 1; i >= 0; i--) { float d = GetVectorDistance(ownerPos, g_vecBreadcrumbs[owner][i]); if (d > 100.0 && d < 250.0) { TeleportEntity(bot, g_vecBreadcrumbs[owner][i], NULL_VECTOR, NULL_VECTOR); teleSuccess = true; break; } } }
			if (!teleSuccess) { float fallback[3]; fallback[0] = ownerPos[0]; fallback[1] = ownerPos[1]; fallback[2] = ownerPos[2] + 20.0; TeleportEntity(bot, fallback, NULL_VECTOR, NULL_VECTOR); } return Plugin_Changed;
		}

		if (g_iAttackState[bot] > 0) {
			vel[0] = 350.0; vel[1] = 0.0; vel[2] = 0.0; buttons |= IN_FORWARD; 
			if (zClass == 8) { if (distToOwner > 400.0) buttons |= IN_ATTACK; } // KHÓA TANK ĐẤM NẾU Ở GẦN
			else { buttons |= IN_ATTACK; }

			if (g_iAttackState[bot] == 12) {
				float centerDir[3]; int tk = EntRefToEntIndex(g_iAttackTarget[bot]); if (tk > 0 && IsValidEntity(tk)) { float tkPos[3]; GetEntPropVector(tk, Prop_Send, "m_vecOrigin", tkPos); MakeVectorFromPoints(botPos, tkPos, centerDir); } else { float eyeAngles[3]; GetClientEyeAngles(bot, eyeAngles); GetAngleVectors(eyeAngles, centerDir, NULL_VECTOR, NULL_VECTOR); } centerDir[2] = 0.0; NormalizeVector(centerDir, centerDir);
				int ent = -1; while ((ent = FindEntityByClassname(ent, "infected")) != -1) { if (IsValidEntity(ent) && GetEntProp(ent, Prop_Data, "m_iHealth") > 0) TryHitTarget(bot, owner, ent, botPos, centerDir); }
				ent = -1; while ((ent = FindEntityByClassname(ent, "witch")) != -1) { if (IsValidEntity(ent) && GetEntProp(ent, Prop_Data, "m_iHealth") > 0) TryHitTarget(bot, owner, ent, botPos, centerDir); }
				for (int i = 1; i <= MaxClients; i++) { if (i != bot && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3 && g_iPetOwner[i] == 0) TryHitTarget(bot, owner, i, botPos, centerDir); }
			} g_iAttackState[bot]--;
			int tk = EntRefToEntIndex(g_iAttackTarget[bot]); if (tk > 0 && IsValidEntity(tk)) { float tPos[3], dir[3]; GetEntPropVector(tk, Prop_Send, "m_vecOrigin", tPos); MakeVectorFromPoints(botPos, tPos, dir); GetVectorAngles(dir, angles); angles[0] = 0.0; TeleportEntity(bot, NULL_VECTOR, angles, NULL_VECTOR); }
			return Plugin_Changed;
		}

		float aimTargetPos[3]; bool isRunningToOwner = false; bool isScavenging = false; int scTarget = EntRefToEntIndex(g_iScavengeTarget[owner]);
		if (scTarget > 0 && IsValidEntity(scTarget)) { isScavenging = true; GetEntPropVector(scTarget, Prop_Send, "m_vecOrigin", aimTargetPos); g_iScavengeTicks[owner]++; if (GetVectorDistance(botPos, aimTargetPos) < 60.0 || g_iScavengeTicks[owner] > 60) { AbsorbItem(owner, scTarget); isScavenging = false; } }
		if (!isScavenging) { isRunningToOwner = true; float memoryPathNode[3]; if (QuerySpatialMemory(botPos, ownerPos, memoryPathNode)) { aimTargetPos[0] = memoryPathNode[0]; aimTargetPos[1] = memoryPathNode[1]; aimTargetPos[2] = memoryPathNode[2]; } else { aimTargetPos[0] = ownerPos[0]; aimTargetPos[1] = ownerPos[1]; aimTargetPos[2] = ownerPos[2]; } }

		float originalDir[3], bestDir[3]; MakeVectorFromPoints(botPos, aimTargetPos, originalDir); originalDir[2] = 0.0; NormalizeVector(originalDir, originalDir); bestDir[0] = originalDir[0]; bestDir[1] = originalDir[1]; bestDir[2] = originalDir[2]; float distToAim = GetVectorDistance(botPos, aimTargetPos);

		if (distToAim > 110.0 || (isRunningToOwner && distToAim > 120.0)) {
			if (g_iStuckTicks[bot] == 0) { g_vecStuckAnchor[bot][0] = botPos[0]; g_vecStuckAnchor[bot][1] = botPos[1]; g_vecStuckAnchor[bot][2] = botPos[2]; } g_iStuckTicks[bot]++;
			if (g_iStuckTicks[bot] >= 60) { if (GetVectorDistance(botPos, g_vecStuckAnchor[bot]) < 70.0) { ExecuteAntiStuckBlink(bot, botPos, aimTargetPos); } g_iStuckTicks[bot] = 0; }
			if (!FindHeuristicEscapeRoute(botPos, originalDir, aimTargetPos, bestDir)) { float memoryPathNode[3]; if (QuerySpatialMemory(botPos, aimTargetPos, memoryPathNode)) { MakeVectorFromPoints(botPos, memoryPathNode, bestDir); bestDir[2] = 0.0; NormalizeVector(bestDir, bestDir); } else { if (ShouldJumpOverLedge(botPos, originalDir) && (GetEntityFlags(bot) & FL_ONGROUND)) buttons |= IN_JUMP; else { vel[1] = (tickcount % 40 < 20) ? 300.0 : -300.0; } } } else { if (ShouldJumpOverLedge(botPos, bestDir) && (GetEntityFlags(bot) & FL_ONGROUND)) buttons |= IN_JUMP; }
			vel[0] = (g_bIsRescuing[bot] || isScavenging) ? 450.0 : 350.0; vel[1] = 0.0; 
			if (g_bIsRescuing[bot] || isScavenging) { SetEntPropFloat(bot, Prop_Send, "m_flLaggedMovementValue", 1.8); } else { SetEntPropFloat(bot, Prop_Send, "m_flLaggedMovementValue", 1.25); } buttons |= IN_FORWARD; 
		} else {
			vel[0] = 0.1; vel[1] = 0.0; SetEntPropFloat(bot, Prop_Send, "m_flLaggedMovementValue", 1.0); g_iStuckTicks[bot] = 0; 
			if (target != -1 && g_iAttackCooldown[bot] <= 0) { buttons |= IN_FORWARD; g_iAttackState[bot] = 25; if (g_bIsRescuing[bot]) g_iAttackCooldown[bot] = 5; else g_iAttackCooldown[bot] = 45; g_iAttackTarget[bot] = EntIndexToEntRef(target); } else if (isRunningToOwner) vel[0] = 0.0; 
		}

		GetVectorAngles(bestDir, angles); angles[0] = 0.0; TeleportEntity(bot, NULL_VECTOR, angles, NULL_VECTOR); return Plugin_Changed;
	} return Plugin_Continue;
}
