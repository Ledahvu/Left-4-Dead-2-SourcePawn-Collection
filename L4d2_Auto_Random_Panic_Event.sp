// <[L4D2] Auto Random Panic & Full Boss/SI Stats> - <Ngẫu nhiên gọi Panic, Tank và gọi Witch theo chu kỳ>
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

// --- CVAR THÔNG BÁO VÀ HUD ---
ConVar g_cvChatEnable, g_cvHintEnable;

// --- CVAR PANIC & QUY MÔ ---
ConVar g_cvEnable, g_cvMinTime, g_cvMaxTime, g_cvDuration, g_cvCICount, g_cvSICount;

// --- CVAR TANK & WITCH ---
ConVar g_cvTankEnable, g_cvTankMinTime, g_cvTankMaxTime;
ConVar g_cvWitchEnable, g_cvWitchTime;

// --- CVAR SI AUTO SPAWN ---
ConVar g_cvSIAutoEnable, g_cvSIAutoTime;

// --- CVAR STATS & KHOẢNG CÁCH ---
ConVar g_cvSafeDist;
ConVar g_cvCIHealth, g_cvCISpeed, g_cvTankHealth, g_cvTankSpeed, g_cvWitchHealth, g_cvWitchSpeed;
ConVar g_cvHunterHP, g_cvHunterSpeed, g_cvSmokerHP, g_cvSmokerSpeed, g_cvBoomerHP, g_cvBoomerSpeed;
ConVar g_cvSpitterHP, g_cvSpitterSpeed, g_cvJockeyHP, g_cvJockeySpeed, g_cvChargerHP, g_cvChargerSpeed;

// --- BIẾN HỆ THỐNG CỦA GAME ---
ConVar g_cvZMegaMobSize, g_cvZCommonLimit, g_cvZMaxPlayerZombies;
int g_iOldMegaMobSize, g_iOldCommonLimit, g_iOldMaxPlayerZombies;

Handle g_hPanicTimer = null;
Handle g_hRestoreTimer = null;
Handle g_hTankTimer = null;
Handle g_hWitchTimer = null;
Handle g_hSITimer = null;
Handle g_hCountdownTimer = null; 

float g_fTimeRemaining = 0.0;    
bool g_bHasLeftStartArea = false;
bool g_bIsPanicActive = false; 

public Plugin myinfo = {
    name = "Auto Random Panic & Perfect SI Spawner",
    author = "Tyn Zũ",
    description = "Ngẫu nhiên gọi Panic, Tank và gọi Witch theo chu kỳ",
    version = "2.1",
    url = "https://github.com/Ledahvu/Left-4-Dead-2-SourcePawn-Collection/blob/main/L4d2_Auto_Random_Panic_Event.sp"
};

public void OnPluginStart()
{
    g_cvChatEnable = CreateConVar("sm_autopanic_chat_enable", "1", "Bật/Tắt thông báo Chat");
    g_cvHintEnable = CreateConVar("sm_autopanic_hint_enable", "1", "Bật/Tắt đếm ngược trên màn hình (Hint)");

    g_cvEnable   = CreateConVar("sm_autopanic_enable", "1", "Bật/Tắt plugin (1=Bật, 0=Tắt)");
    g_cvMinTime  = CreateConVar("sm_autopanic_min", "15.0", "Thời gian xả hơi TỐI THIỂU");
    g_cvMaxTime  = CreateConVar("sm_autopanic_max", "30.0", "Thời gian xả hơi TỐI ĐA");
    g_cvDuration = CreateConVar("sm_autopanic_duration", "45.0", "Thời gian kéo dài Panic");
    g_cvCICount  = CreateConVar("sm_autopanic_ci_count", "50", "Tổng số CI sinh ra trong đợt Panic");
    g_cvSICount  = CreateConVar("sm_autopanic_si_count", "6", "Số lượng SI tối đa xuất hiện trong đợt Panic");

    g_cvTankEnable  = CreateConVar("sm_autotank_enable", "1", "Bật tự động gọi Tank ngẫu nhiên");
    g_cvTankMinTime = CreateConVar("sm_autotank_min", "180.0", "Chờ Tank TỐI THIỂU (giây)");
    g_cvTankMaxTime = CreateConVar("sm_autotank_max", "420.0", "Chờ Tank TỐI ĐA (giây)");
    g_cvWitchEnable = CreateConVar("sm_autowitch_enable", "1", "Bật tự động gọi Witch");
    g_cvWitchTime   = CreateConVar("sm_autowitch_time", "60.0", "Chu kỳ xuất hiện Witch (giây)");

    g_cvSIAutoEnable = CreateConVar("sm_autosi_enable", "1", "Bật sinh SI liên tục ngoài Panic");
    g_cvSIAutoTime   = CreateConVar("sm_autosi_time", "15.0", "Thời gian cực ngắn gọi SI (giây)");

    // Cvar cấu hình khoảng cách (Mặc định gốc của game là 250, mình nâng lên 600 để bao xa)
    g_cvSafeDist    = CreateConVar("sm_autopanic_safe_dist", "600", "Khoảng cách an toàn tối thiểu giữa quái spawn và người chơi");

    g_cvCIHealth    = CreateConVar("sm_stat_ci_hp", "50");
    g_cvCISpeed     = CreateConVar("sm_stat_ci_speed", "250");
    g_cvTankHealth  = CreateConVar("sm_stat_tank_hp", "4000");
    g_cvTankSpeed   = CreateConVar("sm_stat_tank_speed", "210");
    g_cvWitchHealth = CreateConVar("sm_stat_witch_hp", "1000");
    g_cvWitchSpeed  = CreateConVar("sm_stat_witch_speed", "300");

    g_cvHunterHP     = CreateConVar("sm_stat_hunter_hp", "250");
    g_cvHunterSpeed  = CreateConVar("sm_stat_hunter_speed", "300");
    g_cvSmokerHP     = CreateConVar("sm_stat_smoker_hp", "250");
    g_cvSmokerSpeed  = CreateConVar("sm_stat_smoker_speed", "210");
    g_cvBoomerHP     = CreateConVar("sm_stat_boomer_hp", "50");
    g_cvBoomerSpeed  = CreateConVar("sm_stat_boomer_speed", "175");
    g_cvSpitterHP    = CreateConVar("sm_stat_spitter_hp", "100");
    g_cvSpitterSpeed = CreateConVar("sm_stat_spitter_speed", "210");
    g_cvJockeyHP     = CreateConVar("sm_stat_jockey_hp", "325");
    g_cvJockeySpeed  = CreateConVar("sm_stat_jockey_speed", "250");
    g_cvChargerHP    = CreateConVar("sm_stat_charger_hp", "600");
    g_cvChargerSpeed = CreateConVar("sm_stat_charger_speed", "250");

    HookConVarChange(g_cvSafeDist, OnStatCvarChanged);
    HookConVarChange(g_cvCIHealth, OnStatCvarChanged);
    HookConVarChange(g_cvCISpeed, OnStatCvarChanged);
    HookConVarChange(g_cvTankHealth, OnStatCvarChanged);
    HookConVarChange(g_cvTankSpeed, OnStatCvarChanged);
    HookConVarChange(g_cvWitchHealth, OnStatCvarChanged);
    HookConVarChange(g_cvWitchSpeed, OnStatCvarChanged);
    HookConVarChange(g_cvHunterHP, OnStatCvarChanged);
    HookConVarChange(g_cvHunterSpeed, OnStatCvarChanged);
    HookConVarChange(g_cvSmokerHP, OnStatCvarChanged);
    HookConVarChange(g_cvSmokerSpeed, OnStatCvarChanged);
    HookConVarChange(g_cvBoomerHP, OnStatCvarChanged);
    HookConVarChange(g_cvBoomerSpeed, OnStatCvarChanged);
    HookConVarChange(g_cvSpitterHP, OnStatCvarChanged);
    HookConVarChange(g_cvSpitterSpeed, OnStatCvarChanged);
    HookConVarChange(g_cvJockeyHP, OnStatCvarChanged);
    HookConVarChange(g_cvJockeySpeed, OnStatCvarChanged);
    HookConVarChange(g_cvChargerHP, OnStatCvarChanged);
    HookConVarChange(g_cvChargerSpeed, OnStatCvarChanged);

    AutoExecConfig(true, "auto_random_panic");

    g_cvZMegaMobSize      = FindConVar("z_mega_mob_size");
    g_cvZCommonLimit      = FindConVar("z_common_limit");
    g_cvZMaxPlayerZombies = FindConVar("z_max_player_zombies");

    HookEvent("player_left_start_area", Event_PlayerLeftStartArea, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("map_transition", Event_RoundEnd, EventHookMode_PostNoCopy);
}

public void OnConfigsExecuted() { ApplyHealthAndSpeed(); }
public void OnStatCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue) { ApplyHealthAndSpeed(); }

public void OnMapStart()
{
    g_bHasLeftStartArea = false;
    g_bIsPanicActive = false;
    StopAllTimers();
    
    if (g_cvZMegaMobSize != null)      g_iOldMegaMobSize = g_cvZMegaMobSize.IntValue;
    if (g_cvZCommonLimit != null)      g_iOldCommonLimit = g_cvZCommonLimit.IntValue;
    if (g_cvZMaxPlayerZombies != null) g_iOldMaxPlayerZombies = g_cvZMaxPlayerZombies.IntValue;
}

public void Event_PlayerLeftStartArea(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bHasLeftStartArea)
    {
        g_bHasLeftStartArea = true;
        if (g_cvEnable.BoolValue) TryExecutePanicEvent(); 
        if (g_cvTankEnable.BoolValue) StartRandomTankTimer();
        if (g_cvWitchEnable.BoolValue) StartWitchTimer();
        if (g_cvSIAutoEnable.BoolValue) StartAutoSITimer();
    }
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_bHasLeftStartArea = false;
    g_bIsPanicActive = false;
    StopAllTimers();
}

// =========================================================
// HỆ THỐNG GỌI QUÁI BẰNG VSCRIPT (HOÀN HẢO TẦM NHÌN)
// =========================================================
void SpawnZombieVscript(int classID)
{
    // Lột cờ cheat của hệ thống script máy chủ
    int flags = GetCommandFlags("script");
    SetCommandFlags("script", flags & ~FCVAR_CHEAT);
    
    // Gọi lệnh VScript nội bộ ZSpawn (tự động check góc khuất của cả 4 người)
    ServerCommand("script ZSpawn({type=%d})", classID);
    
    SetCommandFlags("script", flags | FCVAR_CHEAT);
}

// =========================================================
// HÀM CHEAT COMMAND (Chỉ dùng cho Panic Event)
// =========================================================
int GetSurvivorClient()
{
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) return i;
    }
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) return i;
    }
    return 0; 
}

void CheatCommand(int client, const char[] command, const char[] arguments = "")
{
    if (client == 0 || !IsClientInGame(client)) return;

    int flags = GetCommandFlags(command);
    SetCommandFlags(command, flags & ~FCVAR_CHEAT);
    
    if (arguments[0] != '\0') {
        FakeClientCommand(client, "%s %s", command, arguments);
    } else {
        FakeClientCommand(client, "%s", command);
    }
    
    SetCommandFlags(command, flags | FCVAR_CHEAT);
}

// =========================================================
// HỆ THỐNG MÁU, TỐC ĐỘ VÀ KHOẢNG CÁCH NÚP
// =========================================================
void SetGameCvarInt(const char[] name, int value)
{
    ConVar cv = FindConVar(name);
    if (cv != null) cv.IntValue = value;
}

void ApplyHealthAndSpeed()
{
    // Ép khoảng cách an toàn. Game mặc định là 250, mình ép theo Cvar (600)
    SetGameCvarInt("z_safe_spawn_range", g_cvSafeDist.IntValue);

    SetGameCvarInt("z_health", g_cvCIHealth.IntValue);
    SetGameCvarInt("z_speed", g_cvCISpeed.IntValue);
    SetGameCvarInt("z_tank_health", g_cvTankHealth.IntValue);
    SetGameCvarInt("z_tank_speed", g_cvTankSpeed.IntValue);
    SetGameCvarInt("z_witch_health", g_cvWitchHealth.IntValue);
    SetGameCvarInt("z_witch_speed", g_cvWitchSpeed.IntValue);
    
    SetGameCvarInt("z_hunter_health", g_cvHunterHP.IntValue);
    SetGameCvarInt("z_hunter_speed", g_cvHunterSpeed.IntValue);
    SetGameCvarInt("z_gas_health", g_cvSmokerHP.IntValue);       
    SetGameCvarInt("z_gas_speed", g_cvSmokerSpeed.IntValue);
    SetGameCvarInt("z_exploding_health", g_cvBoomerHP.IntValue); 
    SetGameCvarInt("z_exploding_speed", g_cvBoomerSpeed.IntValue);
    SetGameCvarInt("z_spitter_health", g_cvSpitterHP.IntValue);
    SetGameCvarInt("z_spitter_speed", g_cvSpitterSpeed.IntValue);
    SetGameCvarInt("z_jockey_health", g_cvJockeyHP.IntValue);
    SetGameCvarInt("z_jockey_speed", g_cvJockeySpeed.IntValue);
    SetGameCvarInt("z_charger_health", g_cvChargerHP.IntValue);
    SetGameCvarInt("z_charger_speed", g_cvChargerSpeed.IntValue);
}

// =========================================================
// HỆ THỐNG AUTO SI
// =========================================================
void StartAutoSITimer()
{
    if (g_hSITimer != null) KillTimer(g_hSITimer);
    g_hSITimer = CreateTimer(g_cvSIAutoTime.FloatValue, Timer_SpawnSI, _, TIMER_REPEAT);
}

public Action Timer_SpawnSI(Handle timer)
{
    if (!g_cvSIAutoEnable.BoolValue) return Plugin_Continue;

    int limit = g_bIsPanicActive ? g_cvSICount.IntValue : (g_cvSICount.IntValue / 2);
    if (limit < 1) limit = 1;

    if (CountAliveSI() < limit)
    {
        // 1=Smoker, 2=Boomer, 3=Hunter, 4=Spitter, 5=Jockey, 6=Charger
        int siClasses[] = {1, 2, 3, 4, 5, 6};
        int randomIdx = GetRandomInt(0, 5);
        SpawnZombieVscript(siClasses[randomIdx]);
    }
    return Plugin_Continue;
}

int CountAliveSI()
{
    int count = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && GetClientTeam(i) == 3 && IsPlayerAlive(i)) {
            int zClass = GetEntProp(i, Prop_Send, "m_zombieClass");
            if (zClass >= 1 && zClass <= 6) count++; 
        }
    }
    return count;
}

// =========================================================
// HỆ THỐNG TANK VÀ WITCH
// =========================================================
bool IsTankAlive()
{
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && GetClientTeam(i) == 3 && IsPlayerAlive(i)) {
            int zombieClass = GetEntProp(i, Prop_Send, "m_zombieClass");
            if (zombieClass == 8) return true;
        }
    }
    return false;
}

void StartRandomTankTimer()
{
    if (g_hTankTimer != null) KillTimer(g_hTankTimer);
    float fWaitTime = GetRandomFloat(g_cvTankMinTime.FloatValue, g_cvTankMaxTime.FloatValue);
    g_hTankTimer = CreateTimer(fWaitTime, Timer_SpawnTank);
}

public Action Timer_SpawnTank(Handle timer)
{
    g_hTankTimer = null;
    if (!g_cvTankEnable.BoolValue) return Plugin_Stop;

    SpawnZombieVscript(8); // Type 8 = Tank
    if (g_cvChatEnable.BoolValue) {
        PrintToChatAll("\x04[Director] \x01Cảnh báo! Một con Tank đã xuất hiện chặn đường!");
    }
    return Plugin_Stop;
}

void StartWitchTimer()
{
    if (g_hWitchTimer != null) KillTimer(g_hWitchTimer);
    g_hWitchTimer = CreateTimer(g_cvWitchTime.FloatValue, Timer_SpawnWitch);
}

public Action Timer_SpawnWitch(Handle timer)
{
    g_hWitchTimer = null;
    if (!g_cvWitchEnable.BoolValue) return Plugin_Stop;

    SpawnZombieVscript(7); // Type 7 = Witch
    if (g_cvChatEnable.BoolValue) {
        PrintToChatAll("\x04[Director] \x01Bạn có nghe thấy tiếng khóc của Witch không?");
    }
    StartWitchTimer();
    return Plugin_Stop;
}

// =========================================================
// HỆ THỐNG PANIC EVENT CHÍNH VÀ ĐẾM NGƯỢC HUD
// =========================================================
void TryExecutePanicEvent()
{
    if (IsTankAlive())
    {
        g_fTimeRemaining = 10.0; 
        if (g_hPanicTimer != null) KillTimer(g_hPanicTimer);
        g_hPanicTimer = CreateTimer(10.0, Timer_TriggerPanicEvent);
        
        if (g_hCountdownTimer == null)
            g_hCountdownTimer = CreateTimer(1.0, Timer_UpdateHint, _, TIMER_REPEAT);
            
        return;
    }
    ExecutePanicEvent();
}

void ExecutePanicEvent()
{
    g_bIsPanicActive = true;

    if (g_cvZMegaMobSize != null)      g_cvZMegaMobSize.IntValue = g_cvCICount.IntValue;
    if (g_cvZCommonLimit != null)      g_cvZCommonLimit.IntValue = g_cvCICount.IntValue;
    if (g_cvZMaxPlayerZombies != null) g_cvZMaxPlayerZombies.IntValue = g_cvSICount.IntValue;

    int client = GetSurvivorClient();
    if (client > 0)
    {
        CheatCommand(client, "director_force_panic_event");
    }
    else
    {
        int director = FindEntityByClassname(-1, "info_director");
        if (director != -1) AcceptEntityInput(director, "ForcePanicEvent");
    }

    if (g_cvChatEnable.BoolValue) {
        PrintToChatAll("\x04[Director] \x01Cảnh báo! Một đợt horde lớn đang kéo đến!");
    }
    
    if (g_hRestoreTimer != null) KillTimer(g_hRestoreTimer);
    g_hRestoreTimer = CreateTimer(g_cvDuration.FloatValue, Timer_RestoreLimits);

    StartRandomPanicTimer();
}

void StartRandomPanicTimer()
{
    if (g_hPanicTimer != null) KillTimer(g_hPanicTimer);
    if (g_hCountdownTimer != null) KillTimer(g_hCountdownTimer);
    
    float fWaitTime = GetRandomFloat(g_cvMinTime.FloatValue, g_cvMaxTime.FloatValue) + g_cvDuration.FloatValue;
    
    g_fTimeRemaining = fWaitTime;
    
    g_hPanicTimer = CreateTimer(fWaitTime, Timer_TriggerPanicEvent);
    g_hCountdownTimer = CreateTimer(1.0, Timer_UpdateHint, _, TIMER_REPEAT);
}

public Action Timer_UpdateHint(Handle timer)
{
    g_fTimeRemaining -= 1.0;
    
    if (g_fTimeRemaining > 0.0)
    {
        if (g_cvHintEnable.BoolValue)
        {
            PrintHintTextToAll("Đợt Panic tiếp theo trong: %.0f giây", g_fTimeRemaining);
        }
    }
    else
    {
        g_hCountdownTimer = null;
        return Plugin_Stop;
    }
    
    return Plugin_Continue;
}

public Action Timer_TriggerPanicEvent(Handle timer)
{
    g_hPanicTimer = null;
    if (!g_cvEnable.BoolValue) return Plugin_Stop;

    TryExecutePanicEvent();
    return Plugin_Stop;
}

public Action Timer_RestoreLimits(Handle timer)
{
    g_hRestoreTimer = null;
    g_bIsPanicActive = false; 

    if (g_cvZMegaMobSize != null)      g_cvZMegaMobSize.IntValue = g_iOldMegaMobSize;
    if (g_cvZCommonLimit != null)      g_cvZCommonLimit.IntValue = g_iOldCommonLimit;
    if (g_cvZMaxPlayerZombies != null) g_cvZMaxPlayerZombies.IntValue = g_iOldMaxPlayerZombies;

    return Plugin_Stop;
}

void StopAllTimers()
{
    if (g_hPanicTimer != null) { KillTimer(g_hPanicTimer); g_hPanicTimer = null; }
    if (g_hRestoreTimer != null) { KillTimer(g_hRestoreTimer); g_hRestoreTimer = null; }
    if (g_hTankTimer != null) { KillTimer(g_hTankTimer); g_hTankTimer = null; }
    if (g_hWitchTimer != null) { KillTimer(g_hWitchTimer); g_hWitchTimer = null; }
    if (g_hSITimer != null) { KillTimer(g_hSITimer); g_hSITimer = null; }
    if (g_hCountdownTimer != null) { KillTimer(g_hCountdownTimer); g_hCountdownTimer = null; }
}
