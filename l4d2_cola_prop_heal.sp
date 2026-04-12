// <Cola Prop Heal> - <Using cola to heal>
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

#define COLA_W_MODEL "models/w_models/weapons/w_cola.mdl"
#define COLA_V_MODEL "models/v_models/v_cola.mdl"
#define ATTACH_HIP "medkit" 
#define MAX_STOWED_PACKS 10

public Plugin myinfo =
{
    name        = "[L4D2] Cola Prop Heal",
    author      = "Tyn Zũ",
    description = "Sử dụng cola để heal",
    version     = "2.1",
    url         = "https://github.com/Ledahvu/Left-4-Dead-2-SourcePawn-Collection/"
};

ConVar g_cvMaxPacks;
ConVar g_cvUsesPerPack;
ConVar g_cvHealAmount;
ConVar g_cvHealDuration;
ConVar g_cvKeepEmpty;

int g_iStowedPacksCount[MAXPLAYERS+1];
int g_iStowedPackUses[MAXPLAYERS+1][MAX_STOWED_PACKS];
int g_iColaProp[MAXPLAYERS+1];

bool g_bIsHealing[MAXPLAYERS+1];
float g_fHealStartTime[MAXPLAYERS+1];
bool g_bStowButtonDown[MAXPLAYERS+1];
bool g_bWasHoldingCola[MAXPLAYERS+1];

Handle g_hHintTimer = null;

public void OnPluginStart()
{
    g_cvMaxPacks = CreateConVar("l4d2_cola_max_packs", "3", "Số lốc cola tối đa mang trên người", FCVAR_NOTIFY, true, 1.0, true, float(MAX_STOWED_PACKS));
    g_cvUsesPerPack = CreateConVar("l4d2_cola_uses_per_pack", "6", "Số chai (lượt heal) trong 1 lốc", FCVAR_NOTIFY, true, 1.0, true, 20.0);
    g_cvHealAmount = CreateConVar("l4d2_cola_heal_amount", "20", "Lượng HP hồi mỗi chai", FCVAR_NOTIFY, true, 1.0, true, 100.0);
    g_cvHealDuration = CreateConVar("l4d2_cola_heal_duration", "3.0", "Thời gian heal (giây)", FCVAR_NOTIFY, true, 1.0, true, 5.0);
    g_cvKeepEmpty = CreateConVar("l4d2_cola_keep_empty", "0", "0 = Xoá lốc khi rỗng, 1 = Giữ lại vỏ lốc trên tay", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    AutoExecConfig(true, "l4d2_cola_prop_heal");

    //RegConsoleCmd("sm_cola", Command_ToggleCola, "Cất hoặc lấy cola bằng lệnh");

    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_spawn", Event_PlayerSpawn);

    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i)) ResetClient(i);
    }
}

public void OnMapStart()
{
    PrecacheModel(COLA_W_MODEL, true);
    PrecacheModel(COLA_V_MODEL, true); 
    PrecacheSound("items/medkit_use.wav", true);
    
    if (g_hHintTimer != null) KillTimer(g_hHintTimer);
    g_hHintTimer = CreateTimer(1.0, Timer_ShowColaHint, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd()
{
    if (g_hHintTimer != null) {
        KillTimer(g_hHintTimer);
        g_hHintTimer = null;
    }
    for (int i = 1; i <= MaxClients; i++) ResetClient(i);
}

public void OnClientDisconnect(int client)
{
    ResetClient(client);
}

void ResetClient(int client)
{
    g_iStowedPacksCount[client] = 0;
    for (int i = 0; i < MAX_STOWED_PACKS; i++) {
        g_iStowedPackUses[client][i] = 0;
    }
    
    g_bIsHealing[client] = false;
    g_bStowButtonDown[client] = false;
    g_bWasHoldingCola[client] = false;

    if (g_iColaProp[client] > MaxClients && IsValidEntity(g_iColaProp[client])) {
        AcceptEntityInput(g_iColaProp[client], "Kill");
    }
    g_iColaProp[client] = -1;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client && IsClientInGame(client)) ResetClient(client);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client) ResetClient(client);
}

int GetColaUses(int weapon)
{
    if (weapon <= MaxClients || !IsValidEntity(weapon)) return 0;
    int uses = GetEntProp(weapon, Prop_Data, "m_iHammerID");
    if (uses == 0) {
        uses = g_cvUsesPerPack.IntValue;
        SetEntProp(weapon, Prop_Data, "m_iHammerID", uses);
    }
    return uses;
}

void SetColaUses(int weapon, int uses)
{
    if (weapon > MaxClients && IsValidEntity(weapon)) {
        SetEntProp(weapon, Prop_Data, "m_iHammerID", uses);
    }
}

// ========================== GIAO DIỆN & HƯỚNG DẪN ==========================

// Bảng nhỏ hiển thị số lượng (Tối giản để không bị tràn chữ)
public Action Timer_ShowColaHint(Handle timer)
{
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
            if (IsHoldingCola(i)) {
                int wep = GetEntPropEnt(i, Prop_Send, "m_hActiveWeapon");
                int currentUses = GetColaUses(wep);

                if (!g_bIsHealing[i]) {
                    PrintHintText(i, "Cola: %d chai | Dự trữ: %d lốc", currentUses, g_iStowedPacksCount[i]);
                } else {
                    PrintHintText(i, "Đang uống... (Hồi %d HP)", g_cvHealAmount.IntValue);
                }
            }
        }
    }
    return Plugin_Continue;
}

// Hiển thị Popup hướng dẫn Instructor Hint (như thông báo của game)
void ShowInstructorHint(int client)
{
    int ent = CreateEntityByName("env_instructor_hint");
    if (ent == -1) return;

    char sTargetName[32];
    Format(sTargetName, sizeof(sTargetName), "hint_target_%d", client);
    DispatchKeyValue(client, "targetname", sTargetName);

    DispatchKeyValue(ent, "hint_target", sTargetName);
    DispatchKeyValue(ent, "hint_timeout", "6");
    DispatchKeyValue(ent, "hint_icon_onscreen", "icon_tip"); // Icon bóng đèn
    DispatchKeyValue(ent, "hint_caption", "Giữ Shift + Chuột Trái: Uống\nShift + Chuột Phải: Cất");
    DispatchKeyValue(ent, "hint_color", "255 255 255");
    DispatchKeyValue(ent, "hint_local_player_only", "1"); // Chỉ người này mới thấy
    
    DispatchSpawn(ent);
    AcceptEntityInput(ent, "ShowHint", client);

    SetVariantString("OnUser1 !self:Kill::6.0:-1");
    AcceptEntityInput(ent, "AddOutput");
    AcceptEntityInput(ent, "FireUser1");
}

// ========================== CẤT / LẤY COLA ==========================
public Action Command_ToggleCola(int client, int args)
{
    if (!IsValidClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != 2) return Plugin_Handled;
    ToggleCola(client);
    return Plugin_Handled;
}

void ToggleCola(int client)
{
    if (IsHoldingCola(client)) StowCola(client);
    else DrawCola(client);
}

void StowCola(int client)
{
    if (!IsHoldingCola(client) || g_bIsHealing[client]) return;

    if (g_iStowedPacksCount[client] >= g_cvMaxPacks.IntValue) {
        PrintToChat(client, "\x04[Cola]\x01 Túi đồ đầy (%d/%d lốc). Không thể cất thêm.", g_iStowedPacksCount[client], g_cvMaxPacks.IntValue);
        return;
    }

    int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (wep > MaxClients && IsValidEntity(wep)) { 
        int uses = GetColaUses(wep);
        
        if (uses <= 0) {
            PrintToChat(client, "\x04[Cola]\x01 Lốc cola này đã rỗng, không thể cất!");
            return;
        }

        g_iStowedPackUses[client][g_iStowedPacksCount[client]] = uses;
        g_iStowedPacksCount[client]++;

        RemovePlayerItem(client, wep);
        AcceptEntityInput(wep, "Kill");

        PrintToChat(client, "\x04[Cola]\x01 Đã cất lốc cola (%d chai) vào người.", uses);
        UpdateColaProp(client);
    }
}

void DrawCola(int client)
{
    if (IsHoldingCola(client) || g_bIsHealing[client]) return;

    if (g_iStowedPacksCount[client] <= 0) {
        PrintToChat(client, "\x04[Cola]\x01 Không có lốc cola nào trong người.");
        return;
    }

    int wep = GivePlayerItem(client, "weapon_cola_bottles");
    if (wep != -1) {
        g_iStowedPacksCount[client]--;
        int uses = g_iStowedPackUses[client][g_iStowedPacksCount[client]];
        SetColaUses(wep, uses);

        PrintToChat(client, "\x04[Cola]\x01 Lấy ra lốc cola (%d chai). Còn dự trữ: %d lốc.", uses, g_iStowedPacksCount[client]);
        UpdateColaProp(client);
    }
}

void UpdateColaProp(int client)
{
    if (GetClientTeam(client) != 2) return;

    if (g_iStowedPacksCount[client] > 0) {
        if (g_iColaProp[client] <= MaxClients || !IsValidEntity(g_iColaProp[client])) {
            int prop = CreateEntityByName("prop_dynamic_override");
            if (prop != -1) {
                SetEntityModel(prop, COLA_W_MODEL);
                if (DispatchSpawn(prop)) {
                    SetVariantString("!activator");
                    AcceptEntityInput(prop, "SetParent", client, prop);
                    SetVariantString(ATTACH_HIP);
                    AcceptEntityInput(prop, "SetParentAttachment", prop, prop, 0);
                    g_iColaProp[client] = prop;
                } else AcceptEntityInput(prop, "Kill"); 
            }
        }
    } else {
        if (g_iColaProp[client] > MaxClients && IsValidEntity(g_iColaProp[client])) {
            AcceptEntityInput(g_iColaProp[client], "Kill");
        }
        g_iColaProp[client] = -1;
    }
}

// ========================== INPUT THAO TÁC ==========================
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (!IsValidClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != 2) return Plugin_Continue;

    int originalButtons = buttons;

    if ((originalButtons & IN_SPEED) && (originalButtons & IN_ATTACK2)) {
        if (!g_bStowButtonDown[client] && !g_bIsHealing[client]) {
            g_bStowButtonDown[client] = true;
            ToggleCola(client);
        }
    } else {
        g_bStowButtonDown[client] = false;
    }

    bool isHolding = IsHoldingCola(client);
    
    // Kích hoạt Instructor Hint 1 lần khi vừa cầm Cola lên tay
    if (isHolding && !g_bWasHoldingCola[client]) {
        ShowInstructorHint(client);
    }
    g_bWasHoldingCola[client] = isHolding;

    if (isHolding && !g_bIsHealing[client]) {
        if ((originalButtons & IN_SPEED) && (originalButtons & IN_ATTACK)) {
            buttons &= ~IN_ATTACK;
            
            int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
            if (GetColaUses(wep) > 0) {
                if (GetClientHealth(client) < 100 && !GetEntProp(client, Prop_Send, "m_isIncapacitated")) {
                    StartHealAnimation(client);
                }
            } else {
                PrintCenterText(client, "Lốc cola này đã rỗng!");
            }
        }
    }

    if (g_bIsHealing[client]) {
        vel[0] = 0.0;
        vel[1] = 0.0;
        buttons &= ~IN_JUMP;
        buttons &= ~IN_ATTACK;

        if (!(originalButtons & IN_ATTACK) || !(originalButtons & IN_SPEED) || !isHolding) {
            CancelHealAnimation(client);
            return Plugin_Continue;
        }

        float elapsed = GetGameTime() - g_fHealStartTime[client];
        if (elapsed >= g_cvHealDuration.FloatValue) {
            FinishHealAnimation(client);
        }
    }

    return Plugin_Continue;
}

// ========================== HEAL CORE ==========================
void StartHealAnimation(int client)
{
    g_bIsHealing[client] = true;
    g_fHealStartTime[client] = GetGameTime();

    SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
    SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", g_cvHealDuration.FloatValue);
    
    EmitSoundToClient(client, "items/medkit_use.wav");
}

void CancelHealAnimation(int client)
{
    g_bIsHealing[client] = false;
    
    if (IsValidClient(client) && IsPlayerAlive(client)) {
        SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", 0.0);
        SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
    }
}

void FinishHealAnimation(int client)
{
    g_bIsHealing[client] = false;

    if (IsValidClient(client) && IsPlayerAlive(client)) {
        SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", 0.0);
        SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);

        int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
        if (wep > MaxClients && IsValidEntity(wep)) {
            
            int uses = GetColaUses(wep) - 1;
            SetColaUses(wep, uses);

            int newHealth = GetClientHealth(client) + g_cvHealAmount.IntValue;
            if (newHealth > 100) newHealth = 100;
            SetEntityHealth(client, newHealth);
            SetEntPropFloat(client, Prop_Send, "m_healthBuffer", 0.0);
            SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());

            if (uses <= 0) {
                if (g_cvKeepEmpty.BoolValue) {
                    PrintToChat(client, "\x04[Cola]\x01 Lốc cola đã rỗng! (Vỏ lốc được giữ lại)");
                } else {
                    RemovePlayerItem(client, wep);
                    AcceptEntityInput(wep, "Kill");
                    PrintToChat(client, "\x04[Cola]\x01 Bạn đã uống hết toàn bộ lốc Cola này!");
                }
            } else {
                PrintToChat(client, "\x04[Cola]\x01 Đã uống 1 chai, hồi %d máu! Lốc này còn %d chai.", g_cvHealAmount.IntValue, uses);
            }
        }
    }
}

// ========================== UTILITIES ==========================
bool IsValidClient(int client) {
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

bool IsHoldingCola(int client) {
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon > MaxClients && IsValidEntity(weapon)) {
        char cls[64];
        GetEntityClassname(weapon, cls, sizeof(cls));
        return StrEqual(cls, "weapon_cola_bottles");
    }
    return false;
}
