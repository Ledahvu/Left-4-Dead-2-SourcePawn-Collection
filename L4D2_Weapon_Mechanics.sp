// <L4D2 Ultimate Weapon Mechanics> - <Gun clip reload, reload speed, and overheat mechanics.>
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
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "3.0"

// --- CVARS ---
ConVar g_cvEnable, g_cvReloadSpeedMulti;
ConVar g_cvMeleeBreakEnable, g_cvMeleeBreakChanceCI, g_cvMeleeBreakChanceSI, g_cvMeleeBreakChanceTank;
ConVar g_cvOverheatEnable, g_cvOverheatMaxShots, g_cvOverheatCooldownTime;

// Shotgun
ConVar g_cvShotgunClipReload;
ConVar g_cvPumpClip, g_cvChromeClip, g_cvAutoClip, g_cvSpasClip;

// Rifles
ConVar g_cvSingleReloadEnable, g_cvSingleReloadPistol, g_cvSingleReloadSMG, g_cvSingleReloadRifle, g_cvSingleReloadSniper;

// --- BIẾN TRẠNG THÁI ---
float g_fHeat[MAXPLAYERS + 1];
bool g_bOverheated[MAXPLAYERS + 1];

bool g_bIsReloading[MAXPLAYERS + 1];
int g_iReloadingWeapon[MAXPLAYERS + 1];
int g_iShadowClip[MAXPLAYERS + 1]; 
Handle g_hSingleReloadTimer[MAXPLAYERS + 1];

// Âm thanh
#define SOUND_BREAK_WOOD "physics/wood/wood_plank_break1.wav"
#define SOUND_BREAK_METAL "physics/metal/metal_solid_break1.wav"
#define SOUND_SINGLE_BULLET "weapons/shotgun/gunother/shotgun_load_shell_2.wav"

public Plugin myinfo = {
    name = "L4D2 Ultimate Weapon Mechanics",
    author = "Tyn Zũ",
    description = "Gun clip reload, reload speed, and overheat mechanics.",
    version = PLUGIN_VERSION,
    url = "https://github.com/Ledahvu/Left-4-Dead-2-SourcePawn-Collection/blob/main/L4D2_Weapon_Mechanics.sp"
};

public void OnPluginStart() {
    g_cvEnable = CreateConVar("sm_cwm_enable", "1", "Bật/Tắt plugin");
    g_cvReloadSpeedMulti = CreateConVar("sm_cwm_reload_speed", "1.5", "Tốc độ thay đạn chung");
    
    g_cvMeleeBreakEnable = CreateConVar("sm_cwm_melee_break", "1", "Cơ chế gãy vũ khí");
    g_cvMeleeBreakChanceCI = CreateConVar("sm_cwm_break_chance_ci", "2.0", "% CI");
    g_cvMeleeBreakChanceSI = CreateConVar("sm_cwm_break_chance_si", "10.0", "% SI");
    g_cvMeleeBreakChanceTank = CreateConVar("sm_cwm_break_chance_tank", "35.0", "% Tank");

    g_cvOverheatEnable = CreateConVar("sm_cwm_overheat_enable", "1", "Quá nhiệt");
    g_cvOverheatMaxShots = CreateConVar("sm_cwm_overheat_max", "260.0", "Nhiệt tối đa");
    g_cvOverheatCooldownTime = CreateConVar("sm_cwm_overheat_cooldown", "10.0", "Thời gian nguội");

    g_cvShotgunClipReload = CreateConVar("sm_cwm_shotgun_mag_reload", "1", "Shotgun nạp 1 lần");
    g_cvPumpClip = CreateConVar("sm_cwm_pump_clip", "8", "");
    g_cvChromeClip = CreateConVar("sm_cwm_chrome_clip", "8", "");
    g_cvAutoClip = CreateConVar("sm_cwm_auto_clip", "10", "");
    g_cvSpasClip = CreateConVar("sm_cwm_spas_clip", "10", "");

    g_cvSingleReloadEnable = CreateConVar("sm_cwm_single_reload", "1", "Súng trường nạp từng viên");
    g_cvSingleReloadPistol = CreateConVar("sm_cwm_single_pistol", "1", "");
    g_cvSingleReloadSMG = CreateConVar("sm_cwm_single_smg", "1", "");
    g_cvSingleReloadRifle = CreateConVar("sm_cwm_single_rifle", "1", "");
    g_cvSingleReloadSniper = CreateConVar("sm_cwm_single_sniper", "1", "");

    AutoExecConfig(true, "l4d2_weapons_mechanics");

    HookEvent("weapon_fire", Event_WeaponFire);
    HookEvent("infected_hurt", Event_InfectedHurt);
    HookEvent("player_hurt", Event_PlayerHurt);
    
    CreateTimer(0.1, Timer_NaturalCooldown, _, TIMER_REPEAT);

    for (int i = 1; i <= GetMaxEntities(); i++) {
        if (IsValidEntity(i) && HasEntProp(i, Prop_Send, "m_iClip1")) {
            char classname[64]; GetEdictClassname(i, classname, sizeof(classname));
            if (StrContains(classname, "weapon_") != -1) SDKHook(i, SDKHook_Reload, OnWeaponReload);
        }
    }
}

public void OnMapStart() {
    PrecacheSound(SOUND_BREAK_WOOD, true);
    PrecacheSound(SOUND_BREAK_METAL, true);
    PrecacheSound(SOUND_SINGLE_BULLET, true);
}

public void OnEntityCreated(int entity, const char[] classname) {
    if (entity > 0 && IsValidEntity(entity) && StrContains(classname, "weapon_") != -1) {
        CreateTimer(0.1, Timer_HookWeapon, EntIndexToEntRef(entity));
    }
}

public Action Timer_HookWeapon(Handle timer, int ref) {
    int entity = EntRefToEntIndex(ref);
    if (entity > 0 && IsValidEntity(entity) && HasEntProp(entity, Prop_Send, "m_iClip1")) {
        SDKHook(entity, SDKHook_Reload, OnWeaponReload);
    }
    return Plugin_Continue;
}

// ====================================================================================
// HỆ THỐNG QUÁ NHIỆT 
// ====================================================================================
public Action Event_WeaponFire(Event event, const char[] name, bool dontBroadcast) {
    if (!g_cvEnable.BoolValue || !g_cvOverheatEnable.BoolValue) return Plugin_Continue;
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0) return Plugin_Continue;

    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEntity(weapon)) return Plugin_Continue;

    char wName[32]; GetEdictClassname(weapon, wName, sizeof(wName));
    if (StrContains(wName, "melee") != -1 || StrContains(wName, "grenade") != -1) return Plugin_Continue;

    float maxHeat = g_cvOverheatMaxShots.FloatValue;
    g_fHeat[client] += 1.0; 

    if (g_fHeat[client] >= maxHeat && !g_bOverheated[client]) {
        g_fHeat[client] = maxHeat;
        g_bOverheated[client] = true;
        
        float cooldown = g_cvOverheatCooldownTime.FloatValue;
        SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + cooldown + 0.5);
        SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime() + cooldown + 0.5);

        SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
        SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", cooldown);
        
        PrintHintText(client, "SÚNG QUÁ NHIỆT! Vui lòng đợi làm mát...");
    }
    return Plugin_Continue;
}

public Action Timer_NaturalCooldown(Handle timer) {
    if (!g_cvEnable.BoolValue || !g_cvOverheatEnable.BoolValue) return Plugin_Continue;
    float maxHeat = g_cvOverheatMaxShots.FloatValue;
    float dropRate = (maxHeat / 8.0) * 0.1; 

    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && IsPlayerAlive(i)) {
            if (g_bOverheated[i]) {
                float overheatDrop = (maxHeat / g_cvOverheatCooldownTime.FloatValue) * 0.1; 
                g_fHeat[i] -= overheatDrop;
                if (g_fHeat[i] <= 0.0) {
                    g_fHeat[i] = 0.0; g_bOverheated[i] = false;
                    SetEntPropFloat(i, Prop_Send, "m_flProgressBarStartTime", 0.0);
                    SetEntPropFloat(i, Prop_Send, "m_flProgressBarDuration", 0.0);
                    PrintHintText(i, "Súng đã sẵn sàng!");
                }
            } 
            else if (g_fHeat[i] > 0.0) {
                g_fHeat[i] -= dropRate;
                if (g_fHeat[i] < 0.0) g_fHeat[i] = 0.0;
            }
        }
    }
    return Plugin_Continue;
}

// ====================================================================================
// ĐIỀU KHIỂN NÚT BẤM (GẠT TAY ENGINE VÀ HỦY NẠP ĐẠN)
// ====================================================================================
public Action OnPlayerRunCmd(int client, int &buttons) {
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) return Plugin_Continue;
    
    if (g_bOverheated[client]) {
        if (buttons & IN_ATTACK) buttons &= ~IN_ATTACK;
        if (buttons & IN_ATTACK2) buttons &= ~IN_ATTACK2;
        return Plugin_Continue;
    }

    if (g_bIsReloading[client]) {
        int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
        
        if (weapon == g_iReloadingWeapon[client]) {
            char wName[32]; GetEdictClassname(weapon, wName, sizeof(wName));
            
            if (StrContains(wName, "pistol") != -1 || StrContains(wName, "magnum") != -1) {
                int engineClip = GetEntProp(weapon, Prop_Send, "m_iClip1");
                if (engineClip > g_iShadowClip[client]) {
                    SetEntProp(weapon, Prop_Send, "m_iClip1", g_iShadowClip[client]);
                }
            }

            if (buttons & IN_ATTACK) {
                float nextAttack = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack");
                if (GetGameTime() >= nextAttack) {
                    g_bIsReloading[client] = false;
                    if (g_hSingleReloadTimer[client] != null) {
                        KillTimer(g_hSingleReloadTimer[client]);
                        g_hSingleReloadTimer[client] = null;
                    }
                }
            }
        } else {
            g_bIsReloading[client] = false;
            if (g_hSingleReloadTimer[client] != null) {
                KillTimer(g_hSingleReloadTimer[client]);
                g_hSingleReloadTimer[client] = null;
            }
        }
    }
    return Plugin_Continue;
}

// ====================================================================================
// HỆ THỐNG KIỂM SOÁT RELOAD CHÍNH 
// ====================================================================================
public Action OnWeaponReload(int weapon) {
    if (!g_cvEnable.BoolValue) return Plugin_Continue;

    int client = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
    if (client <= 0 || !IsClientInGame(client) || g_bOverheated[client] || g_bIsReloading[client]) return Plugin_Continue;

    char classname[64]; GetEdictClassname(weapon, classname, sizeof(classname));

    // -------------------------------------------------------------------------
    // 1. SHOTGUN (THỦ THUẬT ĐÁNH LỪA ENGINE TỨC THÌ ĐÃ ĐƯỢC PHỤC HỒI)
    // -------------------------------------------------------------------------
    if (g_cvShotgunClipReload.BoolValue && (StrContains(classname, "shotgun") != -1 || StrContains(classname, "spas") != -1)) {
        int maxClip = 8;
        if (StrEqual(classname, "weapon_pumpshotgun")) maxClip = g_cvPumpClip.IntValue;
        else if (StrEqual(classname, "weapon_shotgun_chrome")) maxClip = g_cvChromeClip.IntValue;
        else if (StrEqual(classname, "weapon_autoshotgun")) maxClip = g_cvAutoClip.IntValue;
        else if (StrEqual(classname, "weapon_shotgun_spas")) maxClip = g_cvSpasClip.IntValue;

        int current = GetEntProp(weapon, Prop_Send, "m_iClip1");
        int reserve = GetWeaponAmmo(client, weapon);
        if (current >= maxClip || reserve <= 0) return Plugin_Continue;

        int totalAmmo = current + reserve;
        int targetClip = (totalAmmo >= maxClip) ? maxClip : totalAmmo;

        // Bơm đạn lên Max - 1. Nếu cần nạp nhiều hơn 1 viên, plugin sẽ bơm sẵn.
        // Engine sẽ nhận ra chỉ còn thiếu đúng 1 viên đạn.
        // Nó sẽ chạy animation nạp 1 viên cuối cùng rồi KÉO NÒNG BẮN mượt mà.
        if (targetClip > current + 1) {
            SetEntProp(weapon, Prop_Send, "m_iClip1", targetClip - 1);
            SetWeaponAmmo(client, weapon, totalAmmo - (targetClip - 1));
        }

        return Plugin_Continue; 
    }
    
    // -------------------------------------------------------------------------
    // 2. PHÂN LOẠI SÚNG TRƯỜNG & SÚNG LỤC (GIỮ NGUYÊN BẢN V13.7 HOÀN HẢO)
    // -------------------------------------------------------------------------
    if (g_cvSingleReloadEnable.BoolValue) {
        bool bShouldSingleReload = false; 
        bool isPistolClass = false;
        int maxClip = 30; 
        float speedPerBullet = 0.1;
        int startSeq = 1;
        float defaultAnimTime = 2.0;

        if (StrContains(classname, "hunting") != -1) {
            bShouldSingleReload = g_cvSingleReloadSniper.BoolValue; maxClip = 15; startSeq = 2; speedPerBullet = 0.15; defaultAnimTime = 2.5;
        } else if (StrContains(classname, "sniper_military") != -1) {
            bShouldSingleReload = g_cvSingleReloadSniper.BoolValue; maxClip = 30; startSeq = 2; speedPerBullet = 0.08; defaultAnimTime = 2.0;
        } else if (StrContains(classname, "awp") != -1) {
            bShouldSingleReload = g_cvSingleReloadSniper.BoolValue; maxClip = 20; startSeq = 2; speedPerBullet = 0.12; defaultAnimTime = 2.5;
        } else if (StrContains(classname, "scout") != -1) {
            bShouldSingleReload = g_cvSingleReloadSniper.BoolValue; maxClip = 15; startSeq = 2; speedPerBullet = 0.15; defaultAnimTime = 2.0;
        } 
        else if (StrContains(classname, "pistol") != -1 || StrContains(classname, "magnum") != -1) {
            bShouldSingleReload = g_cvSingleReloadPistol.BoolValue;
            isPistolClass = true;
            bool isDual = false;
            bool isMagnum = (StrContains(classname, "magnum") != -1);
            
            if (HasEntProp(weapon, Prop_Send, "m_hasDualWeapons")) {
                isDual = (GetEntProp(weapon, Prop_Send, "m_hasDualWeapons") != 0);
            }
            
            if (isMagnum) maxClip = 8;
            else maxClip = isDual ? 30 : 15;
            
            speedPerBullet = 0.08; 
            defaultAnimTime = 2.0;
        } 
        else if (StrContains(classname, "desert") != -1) {
            bShouldSingleReload = g_cvSingleReloadRifle.BoolValue; maxClip = 60; startSeq = 1; speedPerBullet = 0.04; defaultAnimTime = 2.2;
        } else if (StrContains(classname, "rifle") != -1) {
            bShouldSingleReload = g_cvSingleReloadRifle.BoolValue; maxClip = 50; startSeq = 1; speedPerBullet = 0.05; defaultAnimTime = 2.0;
        } else if (StrContains(classname, "smg") != -1) {
            bShouldSingleReload = g_cvSingleReloadSMG.BoolValue; maxClip = 50; startSeq = 1; speedPerBullet = 0.05; defaultAnimTime = 2.0;
        }

        if (bShouldSingleReload) {
            int current = GetEntProp(weapon, Prop_Send, "m_iClip1");
            if (current >= maxClip) return Plugin_Handled; 
            int reserve = GetWeaponAmmo(client, weapon);
            if (reserve <= 0 && !isPistolClass) return Plugin_Handled;

            g_bIsReloading[client] = true; 
            g_iReloadingWeapon[client] = weapon;
            g_iShadowClip[client] = current; 

            float speedMulti = g_cvReloadSpeedMulti.FloatValue;
            if (speedMulti <= 0.0) speedMulti = 1.0;
            speedPerBullet = speedPerBullet / speedMulti;

            int needed = maxClip - current;
            float totalTimeNeed = float(needed) * speedPerBullet;
            
            if (isPistolClass) {
                SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + totalTimeNeed);
                SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime() + totalTimeNeed);
                
                DataPack pack;
                g_hSingleReloadTimer[client] = CreateDataTimer(speedPerBullet, Timer_SingleBulletTick, pack, TIMER_REPEAT);
                pack.WriteCell(client); pack.WriteCell(weapon); pack.WriteCell(maxClip);

                return Plugin_Continue; 
            }
            
            float newPlaybackRate = defaultAnimTime / totalTimeNeed;
            float lockTime = defaultAnimTime / newPlaybackRate; 
            
            SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + lockTime);
            SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime() + lockTime);

            int vm = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
            if (IsValidEntity(vm)) {
                SetEntProp(vm, Prop_Send, "m_nSequence", startSeq); 
                SetEntPropFloat(vm, Prop_Send, "m_flPlaybackRate", newPlaybackRate);
            }

            DataPack pack;
            g_hSingleReloadTimer[client] = CreateDataTimer(speedPerBullet, Timer_SingleBulletTick, pack, TIMER_REPEAT);
            pack.WriteCell(client); pack.WriteCell(weapon); pack.WriteCell(maxClip);

            return Plugin_Handled; 
        }
    }
    return Plugin_Continue;
}

// -------------------------------------------------------------------------
// TIMER RIFLES & PISTOLS ĐẾM ĐẠN TĂNG DẦN
// -------------------------------------------------------------------------
public Action Timer_SingleBulletTick(Handle timer, DataPack pack) {
    pack.Reset(); int client = pack.ReadCell(); int weapon = pack.ReadCell(); int maxClip = pack.ReadCell();

    if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") != weapon) {
        g_bIsReloading[client] = false;
        g_hSingleReloadTimer[client] = null;
        return Plugin_Stop;
    }

    int reserve = GetWeaponAmmo(client, weapon);
    char wName[32]; GetEdictClassname(weapon, wName, sizeof(wName));
    bool isPistol = (StrContains(wName, "pistol") != -1 || StrContains(wName, "magnum") != -1);

    if (g_iShadowClip[client] < maxClip && (reserve > 0 || isPistol)) {
        g_iShadowClip[client]++;
        
        SetEntProp(weapon, Prop_Send, "m_iClip1", g_iShadowClip[client]);
        if (!isPistol) SetWeaponAmmo(client, weapon, reserve - 1);
        
        EmitSoundToClient(client, SOUND_SINGLE_BULLET);
        return Plugin_Continue;
    } else {
        g_bIsReloading[client] = false;
        g_hSingleReloadTimer[client] = null;
        return Plugin_Stop;
    }
}

// ====================================================================================
// MELEE BREAKING 
// ====================================================================================
public Action Event_InfectedHurt(Event event, const char[] name, bool dontBroadcast) {
    if (!g_cvEnable.BoolValue || !g_cvMeleeBreakEnable.BoolValue) return Plugin_Continue;
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    char weaponName[64]; event.GetString("weapon", weaponName, sizeof(weaponName));
    if (attacker > 0 && IsClientInGame(attacker) && StrContains(weaponName, "melee") != -1) CheckMeleeBreak(attacker, g_cvMeleeBreakChanceCI.FloatValue);
    return Plugin_Continue;
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
    if (!g_cvEnable.BoolValue || !g_cvMeleeBreakEnable.BoolValue) return Plugin_Continue;
    int attacker = GetClientOfUserId(event.GetInt("attacker")); int victim = GetClientOfUserId(event.GetInt("userid"));
    char weaponName[64]; event.GetString("weapon", weaponName, sizeof(weaponName));
    if (attacker > 0 && IsClientInGame(attacker) && victim > 0 && IsClientInGame(victim) && GetClientTeam(victim) == 3 && StrContains(weaponName, "melee") != -1) {
        int zombieClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
        float chance = (zombieClass == 8) ? g_cvMeleeBreakChanceTank.FloatValue : g_cvMeleeBreakChanceSI.FloatValue;
        CheckMeleeBreak(attacker, chance);
    }
    return Plugin_Continue;
}

void CheckMeleeBreak(int client, float chance) {
    if (GetRandomFloat(0.0, 100.0) <= chance) {
        int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
        if (IsValidEntity(weapon)) {
            char meleeName[64]; GetEntPropString(weapon, Prop_Data, "m_strMapSetScriptName", meleeName, sizeof(meleeName));
            float pos[3]; GetClientEyePosition(client, pos);
            if (StrContains(meleeName, "bat") != -1 || StrContains(meleeName, "guitar") != -1 || StrContains(meleeName, "tonfa") != -1) {
                EmitSoundToAll(SOUND_BREAK_WOOD, client); ShowParticle(pos, "impact_wood");
            } else { EmitSoundToAll(SOUND_BREAK_METAL, client); ShowParticle(pos, "impact_metal"); }
            PrintHintText(client, "Vũ khí cận chiến của bạn đã BỊ GÃY NÁT!");
            RemovePlayerItem(client, weapon); AcceptEntityInput(weapon, "Kill");
        }
    }
}

void ShowParticle(float pos[3], char[] particlename) {
    int particle = CreateEntityByName("info_particle_system");
    if (IsValidEdict(particle)) {
        TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
        DispatchKeyValue(particle, "effect_name", particlename); DispatchSpawn(particle); ActivateEntity(particle);
        AcceptEntityInput(particle, "Start"); CreateTimer(1.0, Timer_KillParticle, EntIndexToEntRef(particle));
    }
}

public Action Timer_KillParticle(Handle timer, int ref) {
    int entity = EntRefToEntIndex(ref);
    if (entity > 0 && IsValidEntity(entity)) AcceptEntityInput(entity, "Kill");
    return Plugin_Continue;
}

int GetWeaponAmmo(int client, int weapon) {
    int type = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
    return (type == -1) ? 0 : GetEntProp(client, Prop_Send, "m_iAmmo", _, type);
}

void SetWeaponAmmo(int client, int weapon, int ammo) {
    int type = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
    if (type != -1) SetEntProp(client, Prop_Send, "m_iAmmo", ammo, _, type);
}
