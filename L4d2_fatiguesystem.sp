// <Fatigue System> - <Stamina & Fatigue for movement, melee, and shove.>
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

// ========================================================
// CONSTANTS
// ========================================================
#define MAX_FATIGUE_FLOAT 100.0

// ========================================================
// VARIABLES & CONVARS
// ========================================================
ConVar g_hMeleeEnableCvar;
ConVar g_hShowProgressCvar;

ConVar g_hMoveEnableCvar;
ConVar g_hMeleeEnableToggleCvar;
ConVar g_hShoveEnableToggleCvar;

ConVar g_hMoveDrainCvar;
ConVar g_hMeleeDrainCvar;
ConVar g_hShoveDrainCvar;

ConVar g_hMoveRecoverCvar;
ConVar g_hMeleeRecoverCvar;
ConVar g_hShoveRecoverCvar;

bool g_bMasterEnable = false;
bool g_bShowProgress = true;
bool g_bMoveEnable = true;
bool g_bMeleeEnable = true;
bool g_bShoveEnable = true;

float g_fMoveDrain = 10.0;
float g_fMeleeDrain = 15.0;
float g_fShoveDrain = 15.0;

float g_fMoveRecover = 15.0;
float g_fMeleeRecover = 15.0;
float g_fShoveRecover = 15.0;

float g_fMoveFatigue[MAXPLAYERS + 1] = {0.0, ...};
float g_fMeleeFatigue[MAXPLAYERS + 1] = {0.0, ...};
float g_fShoveFatigue[MAXPLAYERS + 1] = {0.0, ...};

bool g_bMeleeExhausted[MAXPLAYERS + 1] = {false, ...};
bool g_bShoveExhausted[MAXPLAYERS + 1] = {false, ...};

int g_iLastMoveBars[MAXPLAYERS + 1] = {0, ...};
int g_iLastMeleeBars[MAXPLAYERS + 1] = {0, ...};
int g_iLastShoveBars[MAXPLAYERS + 1] = {0, ...};
bool g_bLastMeleeExhausted[MAXPLAYERS + 1] = {false, ...};
bool g_bLastShoveExhausted[MAXPLAYERS + 1] = {false, ...};
float g_fLastTickTime[MAXPLAYERS + 1] = {0.0, ...};

// ========================================================
// PLUGIN INFO
// ========================================================
public Plugin myinfo = 
{
    name = "Independent Stamina & Fatigue",
    author = "Tyn Zũ",
    description = "Stamina & Fatigue for movement, melee, and shove.",
    version = "3.1.0",
    url = "https://github.com/Ledahvu/Left-4-Dead-2-SourcePawn-Collection/blob/main/L4d2_fatiguesystem.sp"
};

// ========================================================
// PLUGIN STARTUP
// ========================================================
public void OnPluginStart()
{
    char sModName[50];
    GetGameFolderName(sModName, sizeof(sModName));
    if (StrContains(sModName, "left4dead", false) == -1)
        SetFailState("Plugin này chỉ dành cho Left 4 Dead 1/2.");

    // Master Switch
    g_hMeleeEnableCvar = CreateConVar("sm_fatigue_master_enable", "1", "Công tắc tổng: Bật/Tắt toàn bộ hệ thống thể lực (0=Tắt, 1=Bật)", FCVAR_NONE);
    g_hShowProgressCvar = CreateConVar("sm_fatigue_show_hud", "1", "Bật/Tắt hiển thị HUD thể lực trên màn hình", FCVAR_NONE);
    
    // Toggle Features
    g_hMoveEnableCvar = CreateConVar("sm_fatigue_move_enable", "1", "Bật/Tắt tính năng mệt mỏi khi Di chuyển (0=Tắt, 1=Bật)", FCVAR_NONE);
    g_hMeleeEnableToggleCvar = CreateConVar("sm_fatigue_melee_enable", "1", "Bật/Tắt tính năng mệt mỏi khi Chém Cận Chiến (0=Tắt, 1=Bật)", FCVAR_NONE);
    g_hShoveEnableToggleCvar = CreateConVar("sm_fatigue_shove_enable", "1", "Bật/Tắt tính năng mệt mỏi khi Đẩy/Shove (0=Tắt, 1=Bật)", FCVAR_NONE);

    // Drain Rates
    g_hMoveDrainCvar = CreateConVar("sm_fatigue_move_drain", "10.0", "Số thể lực tiêu hao mỗi giây khi chạy (Mặc định: 10.0 / Max 100.0)", FCVAR_NONE);
    g_hMeleeDrainCvar = CreateConVar("sm_fatigue_melee_drain", "15.0", "Số thể lực tiêu hao mỗi lần chém vung vũ khí (Mặc định: 15.0)", FCVAR_NONE);
    g_hShoveDrainCvar = CreateConVar("sm_fatigue_shove_drain", "15.0", "Số thể lực tiêu hao mỗi lần đẩy/shove chuột phải (Mặc định: 15.0)", FCVAR_NONE);

    // Recovery Rates
    g_hMoveRecoverCvar = CreateConVar("sm_fatigue_move_recover", "15.0", "Tốc độ hồi phục thể lực di chuyển mỗi giây khi đi bộ/đứng im", FCVAR_NONE);
    g_hMeleeRecoverCvar = CreateConVar("sm_fatigue_melee_recover", "15.0", "Tốc độ hồi phục thể lực Chém Cận Chiến mỗi giây", FCVAR_NONE);
    g_hShoveRecoverCvar = CreateConVar("sm_fatigue_shove_recover", "15.0", "Tốc độ hồi phục thể lực Đẩy/Shove mỗi giây", FCVAR_NONE);
    
    //Hooks
    g_hMeleeEnableCvar.AddChangeHook(OnConVarChanged);
    g_hShowProgressCvar.AddChangeHook(OnConVarChanged);
    g_hMoveEnableCvar.AddChangeHook(OnConVarChanged);
    g_hMeleeEnableToggleCvar.AddChangeHook(OnConVarChanged);
    g_hShoveEnableToggleCvar.AddChangeHook(OnConVarChanged);
    g_hMoveDrainCvar.AddChangeHook(OnConVarChanged);
    g_hMeleeDrainCvar.AddChangeHook(OnConVarChanged);
    g_hShoveDrainCvar.AddChangeHook(OnConVarChanged);
    g_hMoveRecoverCvar.AddChangeHook(OnConVarChanged);
    g_hMeleeRecoverCvar.AddChangeHook(OnConVarChanged);
    g_hShoveRecoverCvar.AddChangeHook(OnConVarChanged);
    
    HookEvent("weapon_fire", OnWeaponFire);
    HookEvent("player_spawn", OnPlayerSpawn);
    HookEvent("player_death", OnPlayerDeath);
    HookEvent("round_start", OnRoundStart);
    
    AutoExecConfig(true, "l4d2_fatiguesystem");
}

public void OnConfigsExecuted()
{
    UpdateFatigueSettings();
}

public void OnMapStart()
{
    ResetAllFatigue();
}

public void OnMapEnd()
{
    ResetAllFatigue();
}

public void OnClientDisconnect(int client)
{
    ResetClientFatigue(client);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (!g_bMasterEnable || !IsValidSurvivor(client)) return Plugin_Continue;

    // Khóa nút khi kiệt sức
    if (g_bShoveEnable && g_bShoveExhausted[client]) buttons &= ~IN_ATTACK2; 
    if (g_bMeleeEnable && g_bMeleeExhausted[client])
    {
        int iWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
        if (iWeapon != -1 && IsValidEntity(iWeapon))
        {
            char sWeapon[32];
            GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
            if (IsMeleeWeapon(sWeapon)) buttons &= ~IN_ATTACK; 
        }
    }

    int shovePenalty = GetEntProp(client, Prop_Send, "m_iShovePenalty");
    if (shovePenalty > 0 && g_bShoveEnable) ApplyShoveFatigue(client, g_fShoveDrain);
    SetEntProp(client, Prop_Send, "m_iShovePenalty", 0); 

    float currentTime = GetGameTime();
    float dt = currentTime - g_fLastTickTime[client];
    if (dt <= 0.0 || dt > 0.1) dt = 0.015;
    g_fLastTickTime[client] = currentTime;

    // Di chuyển
    if (g_bMoveEnable)
    {
        bool isRunning = false;
        if ((buttons & (IN_FORWARD|IN_BACK|IN_MOVELEFT|IN_MOVERIGHT)) && !(buttons & IN_SPEED) && !(buttons & IN_DUCK) && (vel[0] != 0.0 || vel[1] != 0.0))
            isRunning = true;

        if (isRunning) g_fMoveFatigue[client] += g_fMoveDrain * dt;
        else g_fMoveFatigue[client] -= g_fMoveRecover * dt;

        if (g_fMoveFatigue[client] > MAX_FATIGUE_FLOAT) g_fMoveFatigue[client] = MAX_FATIGUE_FLOAT;
        if (g_fMoveFatigue[client] < 0.0) g_fMoveFatigue[client] = 0.0;
        
        if (g_fMoveFatigue[client] >= MAX_FATIGUE_FLOAT)
        {
            vel[0] *= 0.15;
            vel[1] *= 0.15;
        }
        else if (g_fMoveFatigue[client] > 60.0)
        {
            float slowFactor = 1.0 - ((g_fMoveFatigue[client] - 60.0) / 40.0) * 0.5;
            vel[0] *= slowFactor;
            vel[1] *= slowFactor;
        }
    }

    // Hồi phục
    if (g_bMeleeEnable && g_fMeleeFatigue[client] > 0.0)
    {
        g_fMeleeFatigue[client] -= g_fMeleeRecover * dt;
        if (g_fMeleeFatigue[client] <= 0.0)
        {
            g_fMeleeFatigue[client] = 0.0;
            g_bMeleeExhausted[client] = false;
        }
    }
    if (g_bShoveEnable && g_fShoveFatigue[client] > 0.0)
    {
        g_fShoveFatigue[client] -= g_fShoveRecover * dt;
        if (g_fShoveFatigue[client] <= 0.0)
        {
            g_fShoveFatigue[client] = 0.0;
            g_bShoveExhausted[client] = false;
        }
    }

    // Update HUD
    int moveBars = g_bMoveEnable ? RoundToNearest((g_fMoveFatigue[client] / MAX_FATIGUE_FLOAT) * 10.0) : 0;
    int meleeBars = g_bMeleeEnable ? RoundToNearest((g_fMeleeFatigue[client] / MAX_FATIGUE_FLOAT) * 10.0) : 0;
    int shoveBars = g_bShoveEnable ? RoundToNearest((g_fShoveFatigue[client] / MAX_FATIGUE_FLOAT) * 10.0) : 0;

    if (moveBars != g_iLastMoveBars[client] || meleeBars != g_iLastMeleeBars[client] || shoveBars != g_iLastShoveBars[client] ||
        g_bMeleeExhausted[client] != g_bLastMeleeExhausted[client] || g_bShoveExhausted[client] != g_bLastShoveExhausted[client])
    {
        g_iLastMoveBars[client] = moveBars;
        g_iLastMeleeBars[client] = meleeBars;
        g_iLastShoveBars[client] = shoveBars;
        g_bLastMeleeExhausted[client] = g_bMeleeExhausted[client];
        g_bLastShoveExhausted[client] = g_bShoveExhausted[client];
        
        ShowCustomHUD(client, moveBars, meleeBars, shoveBars);
    }
    return Plugin_Continue;
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client)) ResetClientFatigue(client);
}
public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client)) ResetClientFatigue(client);
}
public void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    ResetAllFatigue();
}
public void OnWeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bMasterEnable || !g_bMeleeEnable) return;
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidSurvivor(client))
    {
        char sWeapon[32];
        event.GetString("weapon", sWeapon, sizeof(sWeapon));
        if (IsMeleeWeapon(sWeapon)) ApplyMeleeFatigue(client, g_fMeleeDrain);
    }
}

void ApplyMeleeFatigue(int client, float amount)
{
    if (amount <= 0.0 || g_bMeleeExhausted[client]) return;
    g_fMeleeFatigue[client] += amount;
    if (g_fMeleeFatigue[client] >= MAX_FATIGUE_FLOAT) 
    {
        g_fMeleeFatigue[client] = MAX_FATIGUE_FLOAT;
        g_bMeleeExhausted[client] = true;
    }
}
void ApplyShoveFatigue(int client, float amount)
{
    if (amount <= 0.0 || g_bShoveExhausted[client]) return;
    g_fShoveFatigue[client] += amount;
    if (g_fShoveFatigue[client] >= MAX_FATIGUE_FLOAT) 
    {
        g_fShoveFatigue[client] = MAX_FATIGUE_FLOAT;
        g_bShoveExhausted[client] = true;
    }
}
void ResetClientFatigue(int client)
{
    g_fMoveFatigue[client] = 0.0;
    g_fMeleeFatigue[client] = 0.0;
    g_fShoveFatigue[client] = 0.0;
    g_bMeleeExhausted[client] = false;
    g_bShoveExhausted[client] = false;
    g_iLastMoveBars[client] = 0;
    g_iLastMeleeBars[client] = 0;
    g_iLastShoveBars[client] = 0;
    g_bLastMeleeExhausted[client] = false;
    g_bLastShoveExhausted[client] = false;
    if (IsClientInGame(client)) PrintHintText(client, "");
}
void ResetAllFatigue()
{
    for (int i = 1; i <= MaxClients; i++) if (IsValidClient(i)) ResetClientFatigue(i);
}

// ========================================================
// HINT TEXT HUD SYSTEM (ULTRA-COMPRESSED)
// ========================================================
void ShowCustomHUD(int client, int moveBars, int meleeBars, int shoveBars)
{
    if (!g_bShowProgress || !IsPlayerAlive(client)) return;

    if (moveBars <= 0 && meleeBars <= 0 && shoveBars <= 0)
    {
        PrintHintText(client, "");
        return;
    }

    // Bộ nhớ vẫn cấp dồi dào nhưng chuỗi thực tế gửi đi sẽ cực ngắn
    char szHUD[256];
    szHUD[0] = '\0';
    char tempLine[64];

    if (g_bMoveEnable && moveBars > 0)
    {
        char szBar[64];
        GenerateBarString(moveBars, 10, szBar, sizeof(szBar));
        Format(tempLine, sizeof(tempLine), "CHẠY: %s\n", szBar);
        StrCat(szHUD, sizeof(szHUD), tempLine);
    }
    
    if (g_bMeleeEnable && meleeBars > 0)
    {
        char szBar[64];
        GenerateBarString(meleeBars, 10, szBar, sizeof(szBar));
        Format(tempLine, sizeof(tempLine), "CHÉM: %s%s\n", szBar, g_bMeleeExhausted[client] ? " X" : "");
        StrCat(szHUD, sizeof(szHUD), tempLine);
    }
    
    if (g_bShoveEnable && shoveBars > 0)
    {
        char szBar[64];
        GenerateBarString(shoveBars, 10, szBar, sizeof(szBar));
        Format(tempLine, sizeof(tempLine), "ĐẢY : %s%s\n", szBar, g_bShoveExhausted[client] ? " X" : "");
        StrCat(szHUD, sizeof(szHUD), tempLine);
    }

    int len = strlen(szHUD);
    if (len > 0 && szHUD[len - 1] == '\n') szHUD[len - 1] = '\0';

    PrintHintText(client, "%s", szHUD);
}

void GenerateBarString(int bars, int maxBars, char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    StrCat(buffer, maxlen, "[");
    for (int i = 0; i < maxBars; i++)
    {
        if (i < bars) StrCat(buffer, maxlen, "■");
        else StrCat(buffer, maxlen, "□");
    }
    StrCat(buffer, maxlen, "]");
}

// ========================================================
// UTILITIES
// ========================================================
public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) { UpdateFatigueSettings(); }
void UpdateFatigueSettings()
{
    g_bMasterEnable = g_hMeleeEnableCvar.BoolValue;
    g_bShowProgress = g_hShowProgressCvar.BoolValue;
    g_bMoveEnable = g_hMoveEnableCvar.BoolValue;
    g_bMeleeEnable = g_hMeleeEnableToggleCvar.BoolValue;
    g_bShoveEnable = g_hShoveEnableToggleCvar.BoolValue;
    g_fMoveDrain = g_hMoveDrainCvar.FloatValue;
    g_fMeleeDrain = g_hMeleeDrainCvar.FloatValue;
    g_fShoveDrain = g_hShoveDrainCvar.FloatValue;
    g_fMoveRecover = g_hMoveRecoverCvar.FloatValue;
    g_fMeleeRecover = g_hMeleeRecoverCvar.FloatValue;
    g_fShoveRecover = g_hShoveRecoverCvar.FloatValue;
}
bool IsValidClient(int client) { return (client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client)); }
bool IsValidSurvivor(int client) { return (IsValidClient(client) && IsPlayerAlive(client) && GetClientTeam(client) == 2); }
bool IsMeleeWeapon(const char[] sWeapon) { return (StrContains(sWeapon, "melee", false) != -1 || StrContains(sWeapon, "chainsaw", false) != -1); }
