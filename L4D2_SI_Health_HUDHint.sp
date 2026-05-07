// <[L4D2] Super Infected Health HUD Hint> - <Hiển thị HUD Hint máu SI có màu rainbow>
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

// ====================================================================================================
// CONSTANTS & MACROS - HẰNG SỐ & MACROS
// ====================================================================================================
#define TEAM_INFECTED       3
#define MAX_ENTITIES        2048
#define ZCLASS_SMOKER       1
#define ZCLASS_BOOMER       2
#define ZCLASS_HUNTER       3
#define ZCLASS_SPITTER      4
#define ZCLASS_JOCKEY       5
#define ZCLASS_CHARGER      6
#define ZCLASS_TANK         8

// ====================================================================================================
// GLOBAL VARIABLES - BIẾN TOÀN CỤC
// ====================================================================================================
int g_iHintRefs[MAX_ENTITIES + 1] = { INVALID_ENT_REFERENCE, ... };
int g_iHintEntities[MAX_ENTITIES + 1] = { INVALID_ENT_REFERENCE, ... };

ConVar g_cvShowSmoker, g_cvShowBoomer, g_cvShowHunter, g_cvShowSpitter;
ConVar g_cvShowJockey, g_cvShowCharger, g_cvShowTank, g_cvShowWitch;
ConVar g_cvRainbowMode;

// Biến lưu trữ nhịp độ màu hiện tại để tất cả SI đồng bộ cùng 1 màu
int g_iCurrentRainbowIndex = 0;

// Dải 13 màu cực sáng chuyển tiếp theo đúng phổ cầu vồng thực tế
static const char g_sNeonColors[][] = {
    "255 0 0",     // 1. Đỏ tươi
    "255 80 0",    // 2. Cam đậm
    "255 150 0",   // 3. Cam sáng
    "255 255 0",   // 4. Vàng chói
    "150 255 0",   // 5. Vàng chanh
    "0 255 0",     // 6. Xanh lá
    "0 255 150",   // 7. Xanh ngọc
    "0 255 255",   // 8. Xanh lơ (Cyan)
    "0 150 255",   // 9. Xanh biển sáng
    "100 100 255", // 10. Xanh dương (Pha trắng để dễ nhìn)
    "150 0 255",   // 11. Tím
    "255 0 255",   // 12. Hồng Magenta
    "255 0 150"    // 13. Hồng cánh sen
};

// ====================================================================================================
// PLUGIN INFO - Thông Tin Plugin
// ====================================================================================================
public Plugin myinfo = {
    name        = "[L4D2] Super Infected Health HUD Hint",
    author      = "Tyn Zũ",
    description = "Hiển thị HUD Hint máu SI có màu rainbow",
    version     = "3.0.2",
    url         = "https://github.com/Ledahvu/Left-4-Dead-2-SourcePawn-Collection/blob/main/L4D2_SI_Health_HUDHint.sp"
};

// ====================================================================================================
// PLUGIN EVENTS
// ====================================================================================================
public void OnPluginStart() {
    InitializeConVars();
    RegisterHooks();

    // Tốc độ nháy giảm xuống 0.15s (nhanh gấp đôi, rất mượt)
    CreateTimer(0.15, Timer_ProcessRainbow, _, TIMER_REPEAT);
    AutoExecConfig(true, "l4d2_si_health_hudhint");

    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i)) {
            OnClientPutInServer(i);
        }
    }
}

public void OnClientPutInServer(int client) {
    SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}

// ====================================================================================================
// CORE LOGIC & DAMAGE HANDLING - LÝ THUYẾT CHÍNH & XỬ LÝ SÁT THƯƠNG
// ====================================================================================================
public void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3]) {
    if (!IsValidClient(victim) || GetClientTeam(victim) != TEAM_INFECTED || IsIncapacitated(victim)) {
        return;
    }

    int currentHealth = GetEntProp(victim, Prop_Data, "m_iHealth");
    
    if (currentHealth <= 0 || GetEntProp(victim, Prop_Send, "m_lifeState") != 0) {
        RemoveInstructorHint(victim);
        return;
    }

    int zombieClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
    if (IsClassEnabled(zombieClass)) {
        char sDisplayText[32];
        Format(sDisplayText, sizeof(sDisplayText), "HP: %d", currentHealth);
        RenderInstructorHint(victim, sDisplayText);
    }
}

// ====================================================================================================
// GAME EVENTS
// ====================================================================================================
public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client) && GetClientTeam(client) == TEAM_INFECTED) SetupHintEntity(client);
}

public void Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client) && GetClientTeam(client) == TEAM_INFECTED) RemoveInstructorHint(client);
}

public void Event_OnTankSpawn(Event event, const char[] name, bool dontBroadcast) {
    int tank = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(tank)) SetupHintEntity(tank);
}

public Action Event_OnTankKilled(Event event, const char[] name, bool dontBroadcast) {
    int tank = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(tank)) RemoveInstructorHint(tank);
    return Plugin_Continue;
}

public void Event_OnWitchHurt(Event event, const char[] name, bool dontBroadcast) {
    int witchEntity = event.GetInt("entityid");

    if (IsValidEntity(witchEntity)) {
        char sClassname[16];
        GetEntityClassname(witchEntity, sClassname, sizeof(sClassname));
        
        if (!StrEqual(sClassname, "witch")) return;

        int currentHealth = GetEntProp(witchEntity, Prop_Data, "m_iHealth");
        if (currentHealth <= 0) {
            RemoveInstructorHint(witchEntity);
            return;
        }

        if (g_cvShowWitch.BoolValue) {
            char sDisplayText[32];
            Format(sDisplayText, sizeof(sDisplayText), "HP: %d", currentHealth);
            RenderInstructorHint(witchEntity, sDisplayText);
        }
    }
}

public void Event_OnWitchSpawn(Event event, const char[] name, bool dontBroadcast) {
    int witchEntity = event.GetInt("witchid");
    if (IsValidEntity(witchEntity)) SetupHintEntity(witchEntity);
}

public void Event_OnWitchKilled(Event event, const char[] name, bool dontBroadcast) {
    int witchEntity = event.GetInt("witchid");
    if (IsValidEntity(witchEntity)) RemoveInstructorHint(witchEntity);
}

// ====================================================================================================
// TIMERS (RAINBOW SYNC)
// ====================================================================================================
public Action Timer_ProcessRainbow(Handle timer) {
    if (!g_cvRainbowMode.BoolValue) return Plugin_Continue;

    // Tiến dải màu lên 1 bước, nếu vượt quá mảng thì quay lại số 0
    g_iCurrentRainbowIndex++;
    if (g_iCurrentRainbowIndex >= sizeof(g_sNeonColors)) {
        g_iCurrentRainbowIndex = 0;
    }

    for (int i = 1; i <= MAX_ENTITIES; i++) {
        if (IsValidEntityReference(g_iHintRefs[i])) {
            int hintEntity = EntRefToEntIndex(g_iHintRefs[i]);
            if (hintEntity != INVALID_ENT_REFERENCE) {
                // Áp dụng chung một màu cho tất cả SI để tạo sự đồng bộ mượt mà
                DispatchKeyValue(hintEntity, "hint_color", g_sNeonColors[g_iCurrentRainbowIndex]);
                AcceptEntityInput(hintEntity, "ShowHint");
            }
        }
    }
    return Plugin_Continue;
}

// ====================================================================================================
// INSTRUCTOR HINT API
// ====================================================================================================
void RenderInstructorHint(int targetIndex, const char[] sText) {
    if (!IsValidEntityReference(g_iHintRefs[targetIndex])) {
        SetupHintEntity(targetIndex);
    }
    
    int hintEntity = g_iHintEntities[targetIndex];
    char sTargetName[32];

    FormatEx(sTargetName, sizeof(sTargetName), "si_%d", targetIndex);
    DispatchKeyValue(targetIndex, "targetname", sTargetName);
    
    DispatchKeyValue(hintEntity, "hint_target", sTargetName);
    DispatchKeyValue(hintEntity, "hint_name", sTargetName);
    DispatchKeyValue(hintEntity, "hint_replace_key", sTargetName);
    DispatchKeyValue(hintEntity, "hint_static", "0");               
    DispatchKeyValue(hintEntity, "hint_timeout", "0.0");
    DispatchKeyValue(hintEntity, "hint_nooffscreen", "1");          
    DispatchKeyValue(hintEntity, "hint_forcecaption", "1");
    DispatchKeyValue(hintEntity, "hint_icon_onscreen", "");         
    DispatchKeyValue(hintEntity, "hint_icon_offscreen", "");
    
    // Kiểm tra nếu Rainbow đang bật thì dùng luôn màu của nhịp cầu vồng hiện tại
    if (g_cvRainbowMode.BoolValue) {
        DispatchKeyValue(hintEntity, "hint_color", g_sNeonColors[g_iCurrentRainbowIndex]);
    } else {
        DispatchKeyValue(hintEntity, "hint_color", "255 255 0"); // Vàng sáng nếu tắt Rainbow
    }

    DispatchKeyValue(hintEntity, "hint_caption", sText);
    DispatchKeyValue(hintEntity, "hint_activator_caption", sText);
    DispatchKeyValue(hintEntity, "hint_suppress_rest", "1");
    DispatchKeyValue(hintEntity, "hint_instance_type", "2");
    DispatchKeyValue(hintEntity, "hint_local_player_only", "true");

    DispatchSpawn(hintEntity);
    AcceptEntityInput(hintEntity, "ShowHint");
    
    g_iHintRefs[targetIndex] = EntIndexToEntRef(hintEntity);
}

void SetupHintEntity(int targetIndex) {
    RemoveInstructorHint(targetIndex);

    int newEntity = CreateEntityByName("env_instructor_hint");
    if (newEntity != -1) {
        g_iHintEntities[targetIndex] = newEntity;
        DispatchSpawn(newEntity);
        g_iHintRefs[targetIndex] = EntIndexToEntRef(newEntity);
    }
}

void RemoveInstructorHint(int targetIndex) {
    if (IsValidEntityReference(g_iHintRefs[targetIndex])) {
        AcceptEntityInput(g_iHintRefs[targetIndex], "Kill");
        g_iHintRefs[targetIndex] = INVALID_ENT_REFERENCE;
        g_iHintEntities[targetIndex] = INVALID_ENT_REFERENCE;
    }
}

// ====================================================================================================
// INITIALIZATION & HELPERS - KHỞI TẠO & TRỢ GIÚP
// ====================================================================================================
void InitializeConVars() {
    g_cvShowSmoker  = CreateConVar("l4d2_show_smoker", "1", "Bật/Tắt HUD máu cho Smoker");
    g_cvShowBoomer  = CreateConVar("l4d2_show_boomer", "1", "Bật/Tắt HUD máu cho Boomer");
    g_cvShowHunter  = CreateConVar("l4d2_show_hunter", "1", "Bật/Tắt HUD máu cho Hunter");
    g_cvShowSpitter = CreateConVar("l4d2_show_spitter", "1", "Bật/Tắt HUD máu cho Spitter");
    g_cvShowJockey  = CreateConVar("l4d2_show_jockey", "1", "Bật/Tắt HUD máu cho Jockey");
    g_cvShowCharger = CreateConVar("l4d2_show_charger", "1", "Bật/Tắt HUD máu cho Charger");
    g_cvShowTank    = CreateConVar("l4d2_show_tank", "1", "Bật/Tắt HUD máu cho Tank");
    g_cvShowWitch   = CreateConVar("l4d2_show_witch", "1", "Bật/Tắt HUD máu cho Witch");
    g_cvRainbowMode = CreateConVar("l4d2_show_rainbow", "1", "Bật hiệu ứng dạ quang đổi màu liên tục");
}

void RegisterHooks() {
    HookEvent("player_spawn", Event_OnPlayerSpawn);
    HookEvent("player_death", Event_OnPlayerDeath, EventHookMode_Pre);
    HookEvent("tank_spawn", Event_OnTankSpawn);
    HookEvent("tank_killed", Event_OnTankKilled, EventHookMode_Pre);
    HookEvent("infected_hurt", Event_OnWitchHurt);
    HookEvent("witch_spawn", Event_OnWitchSpawn);
    HookEvent("witch_killed", Event_OnWitchKilled, EventHookMode_Pre);
}

bool IsClassEnabled(int zombieClass) {
    switch (zombieClass) {
        case ZCLASS_SMOKER:  return g_cvShowSmoker.BoolValue;
        case ZCLASS_BOOMER:  return g_cvShowBoomer.BoolValue;
        case ZCLASS_HUNTER:  return g_cvShowHunter.BoolValue;
        case ZCLASS_SPITTER: return g_cvShowSpitter.BoolValue;
        case ZCLASS_JOCKEY:  return g_cvShowJockey.BoolValue;
        case ZCLASS_CHARGER: return g_cvShowCharger.BoolValue;
        case ZCLASS_TANK:    return g_cvShowTank.BoolValue;
    }
    return false;
}

bool IsValidClient(int client) {
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

bool IsIncapacitated(int client) {
    return (GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) > 0);
}

bool IsValidEntityReference(int reference) {
    if (reference == INVALID_ENT_REFERENCE || reference == -1) return false;
    int entityIndex = EntRefToEntIndex(reference);
    return (entityIndex != INVALID_ENT_REFERENCE && IsValidEntity(entityIndex));
}
