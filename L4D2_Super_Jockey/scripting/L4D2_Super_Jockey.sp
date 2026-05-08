
// <L4D2 Super Jockey Master> - <Biến Jockey thành Super Jockey với nhiều class và kỹ năng>
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
#include <keyvalues>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "9.0.0"

// ==========================================
// 22 ENUM CLASS
// ==========================================
enum JockeyClass {
    JockeyClass_None = -1,
    JockeyClass_Ghost,
    JockeyClass_Lava,
    JockeyClass_Gravity,
    JockeyClass_Quake,
    JockeyClass_Leaper,
    JockeyClass_Dread,
    JockeyClass_Freeze,
    JockeyClass_Lazy,
    JockeyClass_Rabies,
    JockeyClass_Bombard,
    JockeyClass_Spitter,
    JockeyClass_Warp,
    JockeyClass_Fire,
    JockeyClass_Cobalt,
    JockeyClass_Meteor,
    JockeyClass_Ice,
    JockeyClass_Shield,
    JockeyClass_Shock,
    JockeyClass_Witch,
    JockeyClass_Heal,
    JockeyClass_Smasher,
    JockeyClass_Jumper
};

// ==========================================
// BITMASK CHO CUSTOM CLASSES (CFG)
// ==========================================
#define ABILITY_GHOST    (1 << 0)
#define ABILITY_LAVA     (1 << 1)
#define ABILITY_GRAVITY  (1 << 2)
#define ABILITY_QUAKE    (1 << 3)
#define ABILITY_LEAPER   (1 << 4)
#define ABILITY_DREAD    (1 << 5)
#define ABILITY_FREEZE   (1 << 6)
#define ABILITY_LAZY     (1 << 7)
#define ABILITY_RABIES   (1 << 8)
#define ABILITY_BOMBARD  (1 << 9)
#define ABILITY_SPITTER  (1 << 10)
#define ABILITY_WARP     (1 << 11)
#define ABILITY_FIRE     (1 << 12)
#define ABILITY_COBALT   (1 << 13)
#define ABILITY_METEOR   (1 << 14)
#define ABILITY_ICE      (1 << 15)
#define ABILITY_SHIELD   (1 << 16)
#define ABILITY_SHOCK    (1 << 17)
#define ABILITY_WITCH    (1 << 18)
#define ABILITY_HEAL     (1 << 19)
#define ABILITY_SMASHER  (1 << 20)
#define ABILITY_JUMPER   (1 << 21)

enum struct CustomClassDef {
    char name[64];
    int abilities;
    int glow[3];
    float speed;
    float damage;
    float health;
    float gravity;
    float chance;
}

ArrayList g_CustomClasses;
JockeyClass g_iPlayerClass[MAXPLAYERS + 1] = {JockeyClass_None, ...};
int g_iPlayerCustomClass[MAXPLAYERS + 1] = {-1, ...};
int g_iPlayerAbilities[MAXPLAYERS + 1] = {0, ...};

// Cooldowns & Trackers
float g_fLastRockTime[MAXPLAYERS + 1];
float g_fLastWarpTime[MAXPLAYERS + 1];
float g_fLastDashTime[MAXPLAYERS + 1];
float g_fIceRideTime[MAXPLAYERS + 1]; // Quản lý đóng băng khi bị cưỡi

// ==========================================
// AUTO JUMP CVARS
// ==========================================
ConVar g_cvJumpEnable;
ConVar g_cvJumpBots;
ConVar g_cvJumpForce;
ConVar g_cvJumpMin;
ConVar g_cvJumpMax;

public Plugin myinfo = {
    name = "L4D2 Super Jockey Master",
    author = "Tyn Zũ",
    description = "Biến Jockey thành Super Jockey với nhiều class và kỹ năng",
    version = PLUGIN_VERSION,
    url = "https://github.com/Ledahvu/Left-4-Dead-2-SourcePawn-Collection/edit/main/L4D2_Super_Jockey/L4D2_Super_Jockey.sp"
};

public void OnPluginStart() {
    g_CustomClasses = new ArrayList(sizeof(CustomClassDef));
    
    // Auto Jump Cvars
    g_cvJumpEnable = CreateConVar("sj_autojump_enable", "1", "Bật/tắt Jockey tự động nhảy khi cưỡi Survivor (1=Bật, 0=Tắt)");
    g_cvJumpBots = CreateConVar("sj_autojump_bots", "2", "0=Chỉ người chơi thực, 1=Chỉ Bot, 2=Cả hai");
    g_cvJumpForce = CreateConVar("sj_autojump_force", "350.0", "Lực nảy của Jockey khi bám trên đầu Survivor");
    g_cvJumpMin = CreateConVar("sj_autojump_time_min", "0.1", "Thời gian ngẫu nhiên tối thiểu để nhảy tiếp");
    g_cvJumpMax = CreateConVar("sj_autojump_time_max", "0.5", "Thời gian ngẫu nhiên tối đa để nhảy tiếp");
    AutoExecConfig(true, "l4d2_super_jockey"); 
    
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("jockey_ride", Event_JockeyRide);
    HookEvent("jockey_ride_end", Event_JockeyRideEnd); // Bắt event rớt khỏi đầu
    
    RegAdminCmd("sm_reloadjockey", Cmd_ReloadCfg, ADMFLAG_ROOT, "Reload Super Jockey CFG");
    
    LoadCustomClassesConfig();
    
    CreateTimer(0.5, Timer_ProcessAbilities, _, TIMER_REPEAT);
    CreateTimer(1.5, Timer_SlowAbilities, _, TIMER_REPEAT);
    
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i)) SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
    }
}

public void OnClientPutInServer(int client) {
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnMapStart() {
    PrecacheModel("models/props_debris/concrete_chunk01a.mdl", true);
    PrecacheModel("models/props_junk/propanecanister001a.mdl", true);
    PrecacheSound("ambient/energy/spark1.wav", true);
    PrecacheSound("ambient/machines/teleport_1.wav", true);
    PrecacheSound("npc/witch/voice/idle/witch_cry_01.wav", true);
}

public Action Cmd_ReloadCfg(int client, int args) {
    LoadCustomClassesConfig();
    ReplyToCommand(client, "[Super Jockey] Đã tải lại Custom Classes.");
    return Plugin_Handled;
}

// ==========================================
// HỆ THỐNG ĐỌC FILE CFG
// ==========================================
void LoadCustomClassesConfig() {
    g_CustomClasses.Clear();
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "data/super_jockey_classes.cfg");
    
    if (!FileExists(path)) return;
    
    KeyValues kv = new KeyValues("Classes");
    if (!kv.ImportFromFile(path)) { delete kv; return; }
    
    if (kv.GotoFirstSubKey()) {
        do {
            CustomClassDef ccd;
            kv.GetSectionName(ccd.name, sizeof(ccd.name));
            char abilityStr[256];
            kv.GetString("abilities", abilityStr, sizeof(abilityStr));
            ccd.abilities = ParseAbilitiesString(abilityStr);
            ccd.glow[0] = kv.GetNum("glow_r", 255);
            ccd.glow[1] = kv.GetNum("glow_g", 255);
            ccd.glow[2] = kv.GetNum("glow_b", 255);
            ccd.speed = kv.GetFloat("speed", 1.5);
            ccd.damage = kv.GetFloat("damage", 1.0);
            ccd.health = kv.GetFloat("health", 1.0);
            ccd.gravity = kv.GetFloat("gravity", 1.0);
            ccd.chance = kv.GetFloat("chance", 10.0);
            g_CustomClasses.PushArray(ccd);
        } while (kv.GotoNextKey());
    }
    delete kv;
}

int ParseAbilitiesString(const char[] str) {
    int mask = 0;
    if (StrContains(str, "Ghost") != -1) mask |= ABILITY_GHOST;
    if (StrContains(str, "Lava") != -1) mask |= ABILITY_LAVA;
    if (StrContains(str, "Gravity") != -1) mask |= ABILITY_GRAVITY;
    if (StrContains(str, "Quake") != -1) mask |= ABILITY_QUAKE;
    if (StrContains(str, "Leaper") != -1) mask |= ABILITY_LEAPER;
    if (StrContains(str, "Dread") != -1) mask |= ABILITY_DREAD;
    if (StrContains(str, "Freeze") != -1) mask |= ABILITY_FREEZE;
    if (StrContains(str, "Lazy") != -1) mask |= ABILITY_LAZY;
    if (StrContains(str, "Rabies") != -1) mask |= ABILITY_RABIES;
    if (StrContains(str, "Bombard") != -1) mask |= ABILITY_BOMBARD;
    if (StrContains(str, "Spitter") != -1) mask |= ABILITY_SPITTER;
    if (StrContains(str, "Warp") != -1) mask |= ABILITY_WARP;
    if (StrContains(str, "Fire") != -1) mask |= ABILITY_FIRE;
    if (StrContains(str, "Cobalt") != -1) mask |= ABILITY_COBALT;
    if (StrContains(str, "Meteor") != -1) mask |= ABILITY_METEOR;
    if (StrContains(str, "Ice") != -1) mask |= ABILITY_ICE;
    if (StrContains(str, "Shield") != -1) mask |= ABILITY_SHIELD;
    if (StrContains(str, "Shock") != -1) mask |= ABILITY_SHOCK;
    if (StrContains(str, "Witch") != -1) mask |= ABILITY_WITCH;
    if (StrContains(str, "Heal") != -1) mask |= ABILITY_HEAL;
    if (StrContains(str, "Smasher") != -1) mask |= ABILITY_SMASHER;
    if (StrContains(str, "Jumper") != -1) mask |= ABILITY_JUMPER;
    return mask;
}

// ==========================================
// SPAWN & ÁP DỤNG CHỈ SỐ
// ==========================================
public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int userid = event.GetInt("userid");
    // Tạo Delay 0.1s để entity cập nhật 100% m_zombieClass trước khi xét IsValidJockey
    CreateTimer(0.1, Timer_AssignClassDelay, userid, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_AssignClassDelay(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);
    if (IsValidJockey(client)) {
        AssignRandomClass(client);
    }
    return Plugin_Stop;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && client <= MaxClients) ResetJockeyStats(client);
}

void AssignRandomClass(int client) {
    if (g_CustomClasses.Length > 0 && GetRandomInt(0, 1) == 1) {
        int index = GetRandomInt(0, g_CustomClasses.Length - 1);
        CustomClassDef ccd;
        g_CustomClasses.GetArray(index, ccd);
        
        g_iPlayerCustomClass[client] = index;
        g_iPlayerAbilities[client] = ccd.abilities;
        g_iPlayerClass[client] = JockeyClass_None;
        
        ApplyStats(client, ccd.health, ccd.speed, ccd.gravity, ccd.glow);
        PrintToChatAll("\x04[CẢNH BÁO]\x01 \x03%s\x01 (Jockey) vừa xuất hiện!", ccd.name);
    } else {
        JockeyClass rc = view_as<JockeyClass>(GetRandomInt(1, 22));
        g_iPlayerClass[client] = rc;
        g_iPlayerCustomClass[client] = -1;
        g_iPlayerAbilities[client] = 0;
        
        int glow[3] = {255, 255, 255};
        float hp = 1.3, spd = 1.6, grav = 1.0; 
        
        if (rc == JockeyClass_Lazy) { hp = 5.0; spd = 0.9; glow[0]=255; glow[1]=0; glow[2]=255; }
        else if (rc == JockeyClass_Cobalt) { hp = 0.8; spd = 2.1; glow[0]=0; glow[1]=255; glow[2]=255; }
        else if (rc == JockeyClass_Witch) { spd = 1.9; glow[0]=128; glow[1]=0; glow[2]=0; }
        else if (rc == JockeyClass_Leaper) { grav = 0.25; glow[0]=0; glow[1]=255; glow[2]=0; }
        else if (rc == JockeyClass_Fire) { glow[0]=255; glow[1]=50; glow[2]=0; }
        else if (rc == JockeyClass_Ice || rc == JockeyClass_Freeze) { glow[0]=0; glow[1]=100; glow[2]=255; }
        else if (rc == JockeyClass_Ghost) { glow[0]=200; glow[1]=200; glow[2]=200; }
        else if (rc == JockeyClass_Shield) { glow[0]=255; glow[1]=255; glow[2]=0; hp = 1.8; } // Shield glow vàng
        else { glow[0]=255; glow[1]=100; glow[2]=100; } // Các hệ khác glow đỏ nhẹ
        
        ApplyStats(client, hp, spd, grav, glow);
        
        // ĐÃ SỬA: Lấy tên thật của 22 class gốc để in ra Chat
        char className[64];
        GetEnumClassName(rc, className, sizeof(className));
        PrintToChatAll("\x04[CẢNH BÁO]\x01 \x03%s\x01 (Jockey) vừa xuất hiện!", className);
    }
}

void GetEnumClassName(JockeyClass rc, char[] name, int maxlen) {
    switch(rc) {
        case JockeyClass_Ghost: strcopy(name, maxlen, "Ghost");
        case JockeyClass_Lava: strcopy(name, maxlen, "Lava");
        case JockeyClass_Gravity: strcopy(name, maxlen, "Gravity");
        case JockeyClass_Quake: strcopy(name, maxlen, "Quake");
        case JockeyClass_Leaper: strcopy(name, maxlen, "Leaper");
        case JockeyClass_Dread: strcopy(name, maxlen, "Dread");
        case JockeyClass_Freeze: strcopy(name, maxlen, "Freeze");
        case JockeyClass_Lazy: strcopy(name, maxlen, "Lazy");
        case JockeyClass_Rabies: strcopy(name, maxlen, "Rabies");
        case JockeyClass_Bombard: strcopy(name, maxlen, "Bombard");
        case JockeyClass_Spitter: strcopy(name, maxlen, "Spitter");
        case JockeyClass_Warp: strcopy(name, maxlen, "Warp");
        case JockeyClass_Fire: strcopy(name, maxlen, "Fire");
        case JockeyClass_Cobalt: strcopy(name, maxlen, "Cobalt");
        case JockeyClass_Meteor: strcopy(name, maxlen, "Meteor");
        case JockeyClass_Ice: strcopy(name, maxlen, "Ice");
        case JockeyClass_Shield: strcopy(name, maxlen, "Shield");
        case JockeyClass_Shock: strcopy(name, maxlen, "Shock");
        case JockeyClass_Witch: strcopy(name, maxlen, "Witch");
        case JockeyClass_Heal: strcopy(name, maxlen, "Heal");
        case JockeyClass_Smasher: strcopy(name, maxlen, "Smasher");
        case JockeyClass_Jumper: strcopy(name, maxlen, "Jumper");
        default: strcopy(name, maxlen, "Super");
    }
}

void ApplyStats(int client, float hpMult, float speed, float gravity, int glow[3]) {
    int baseHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
    int newHealth = RoundToNearest(baseHealth * hpMult);
    SetEntProp(client, Prop_Data, "m_iMaxHealth", newHealth);
    SetEntProp(client, Prop_Send, "m_iHealth", newHealth);
    SetEntityGravity(client, gravity);
    SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", speed);
    SetupGlow(client, glow[0], glow[1], glow[2]);
}

void SetupGlow(int client, int r, int g, int b) {
    SetEntProp(client, Prop_Send, "m_bClientSideAnimation", 1);
    SetEntProp(client, Prop_Send, "m_iGlowType", 3);
    SetEntProp(client, Prop_Send, "m_nGlowRange", 9999);
    SetEntProp(client, Prop_Send, "m_glowColorOverride", r + (g * 256) + (b * 65536));
}

void ResetJockeyStats(int client) {
    g_iPlayerClass[client] = JockeyClass_None;
    g_iPlayerCustomClass[client] = -1;
    g_iPlayerAbilities[client] = 0;
    if (IsClientInGame(client)) {
        SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
        SetEntityGravity(client, 1.0);
        SetEntityRenderMode(client, RENDER_NORMAL);
        SetEntityRenderColor(client, 255, 255, 255, 255);
    }
}

// ==========================================
// FAST AURA (0.5s) - CƠ CHẾ RESET SLOW THÔNG MINH
// ==========================================
public Action Timer_ProcessAbilities(Handle timer) {
    // Mảng lưu trạng thái Survivor có đang nằm trong Aura chậm không
    bool isFrozenAura[MAXPLAYERS + 1] = {false, ...};
    bool isQuakeAura[MAXPLAYERS + 1] = {false, ...};

    for (int i = 1; i <= MaxClients; i++) {
        if (!IsValidJockey(i)) continue;
        float pos[3];
        GetClientAbsOrigin(i, pos);
        JockeyClass rc = g_iPlayerClass[i];
        int abs = g_iPlayerAbilities[i];

        if (rc == JockeyClass_Ghost || (abs & ABILITY_GHOST)) {
            SetEntityRenderMode(i, RENDER_TRANSCOLOR);
            SetEntityRenderColor(i, 255, 255, 255, 15);
        }

        if (rc == JockeyClass_Heal || (abs & ABILITY_HEAL)) {
            int hp = GetEntProp(i, Prop_Send, "m_iHealth");
            int maxHp = GetEntProp(i, Prop_Data, "m_iMaxHealth");
            if (hp < maxHp) SetEntProp(i, Prop_Send, "m_iHealth", hp + 20);
        }

        if (rc == JockeyClass_Shock || (abs & ABILITY_SHOCK)) {
            for (int j = 1; j <= MaxClients; j++) {
                if (IsValidSurvivor(j) && GetVectorDistance(pos, GetClientOrigin(j)) < 350.0) {
                    DealDamage(j, 5, i, DMG_SHOCK);
                    EmitSoundToAll("ambient/energy/spark1.wav", j);
                }
            }
        }

        if (rc == JockeyClass_Quake || (abs & ABILITY_QUAKE)) {
            for (int j = 1; j <= MaxClients; j++) {
                if (IsValidSurvivor(j) && GetVectorDistance(pos, GetClientOrigin(j)) < 400.0) {
                    PerformShake(j);
                    isQuakeAura[j] = true; // Đánh dấu Survivor đang trong vùng Quake
                }
            }
        }

        float vel[3];
        GetEntPropVector(i, Prop_Data, "m_vecVelocity", vel);
        if ((rc == JockeyClass_Lava || (abs & ABILITY_LAVA)) && GetVectorLength(vel) > 50.0) {
            CreateFire(pos);
        }

        // ĐÃ SỬA: Truyền 'i' làm chủ nhân (owner) để bãi axit nổ
        if ((rc == JockeyClass_Spitter || (abs & ABILITY_SPITTER)) && GetRandomInt(1, 10) <= 2) {
            CreateAoESpit(i, pos);
        }

        if (rc == JockeyClass_Gravity || (abs & ABILITY_GRAVITY)) {
            for (int j = 1; j <= MaxClients; j++) {
                if (IsValidSurvivor(j)) {
                    float tpos[3], dirVec[3];
                    GetClientAbsOrigin(j, tpos);
                    if (GetVectorDistance(pos, tpos) < 600.0) {
                        MakeVectorFromPoints(tpos, pos, dirVec);
                        NormalizeVector(dirVec, dirVec);
                        ScaleVector(dirVec, 350.0);
                        TeleportEntity(j, NULL_VECTOR, NULL_VECTOR, dirVec);
                    }
                }
            }
        }

        if (rc == JockeyClass_Dread || (abs & ABILITY_DREAD)) {
            for (int j = 1; j <= MaxClients; j++) {
                if (IsValidSurvivor(j) && GetVectorDistance(pos, GetClientOrigin(j)) < 400.0) {
                    PerformBlind(j, 245);
                }
            }
        }
        
        if (rc == JockeyClass_Freeze || (abs & ABILITY_FREEZE)) {
            for (int j = 1; j <= MaxClients; j++) {
                if (IsValidSurvivor(j) && GetVectorDistance(pos, GetClientOrigin(j)) < 300.0) {
                    isFrozenAura[j] = true; // Đánh dấu trong vùng Lạnh
                }
            }
        }

        if (rc == JockeyClass_Warp || (abs & ABILITY_WARP)) {
            float time = GetGameTime();
            if (time - g_fLastWarpTime[i] > 6.0 && GetRandomInt(1, 4) == 1) {
                int target = GetRandomSurvivor();
                if (target != -1) {
                    float targetPos[3], targetAng[3], fw[3];
                    GetClientAbsOrigin(target, targetPos);
                    GetClientEyeAngles(target, targetAng);
                    GetAngleVectors(targetAng, fw, NULL_VECTOR, NULL_VECTOR);
                    targetPos[0] -= fw[0] * 100.0;
                    targetPos[1] -= fw[1] * 100.0;
                    targetPos[2] += 20.0;
                    TeleportEntity(i, targetPos, NULL_VECTOR, NULL_VECTOR);
                    EmitSoundToAll("ambient/machines/teleport_1.wav", i);
                    g_fLastWarpTime[i] = time;
                }
            }
        }

        if (rc == JockeyClass_Jumper || (abs & ABILITY_JUMPER)) {
            float time = GetGameTime();
            if (time - g_fLastDashTime[i] > 3.0 && GetRandomInt(1, 3) == 1) {
                float dashVec[3];
                float eyeAngles[3];
                GetClientEyeAngles(i, eyeAngles); 
                GetAngleVectors(eyeAngles, dashVec, NULL_VECTOR, NULL_VECTOR);
                
                NormalizeVector(dashVec, dashVec);
                ScaleVector(dashVec, 800.0);
                dashVec[2] += 300.0;
                TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, dashVec);
                g_fLastDashTime[i] = time;
            }
        }
    }
    
    // ĐÃ SỬA: Reset & Cập nhật Speed 1 lần duy nhất cho toàn bộ Survivor mỗi 0.5s
    // Giải quyết triệt để lỗi chậm vĩnh viễn và kẹt nhảy/rơi (Gravity/Jump physics)
    float currentTime = GetGameTime();
    for (int j = 1; j <= MaxClients; j++) {
        if (IsValidSurvivor(j)) {
            if (currentTime < g_fIceRideTime[j]) {
                // Đang bị Ice Jockey cưỡi -> Tốc độ = 0
                SetEntPropFloat(j, Prop_Send, "m_flLaggedMovementValue", 0.0);
                SetEntityRenderColor(j, 0, 100, 255, 255);
            } else if (isFrozenAura[j]) {
                // Aura Freeze -> Chậm nhiều
                SetEntPropFloat(j, Prop_Send, "m_flLaggedMovementValue", 0.4);
                SetEntityRenderColor(j, 150, 200, 255, 255);
            } else if (isQuakeAura[j]) {
                // Aura Quake -> Chậm ít
                SetEntPropFloat(j, Prop_Send, "m_flLaggedMovementValue", 0.6);
                SetEntityRenderColor(j, 255, 255, 255, 255);
            } else {
                // Thoát mọi hiệu ứng -> Về bình thường 1.0 (Fix cứng)
                SetEntPropFloat(j, Prop_Send, "m_flLaggedMovementValue", 1.0);
                SetEntityRenderColor(j, 255, 255, 255, 255);
            }
        }
    }
    
    return Plugin_Continue;
}

// ==========================================
// SLOW AURA (1.5s)
// ==========================================
public Action Timer_SlowAbilities(Handle timer) {
    for (int i = 1; i <= MaxClients; i++) {
        if (!IsValidJockey(i)) continue;
        float pos[3];
        GetClientAbsOrigin(i, pos);
        JockeyClass rc = g_iPlayerClass[i];
        int abs = g_iPlayerAbilities[i];

        if (rc == JockeyClass_Bombard || (abs & ABILITY_BOMBARD)) {
            if (GetRandomInt(1, 4) == 1) SpawnExplosive(pos);
        }

        if (rc == JockeyClass_Witch || (abs & ABILITY_WITCH)) {
            EmitSoundToAll("npc/witch/voice/idle/witch_cry_01.wav", i);
        }
        
        if (rc == JockeyClass_Meteor || (abs & ABILITY_METEOR)) {
            int target = GetNearestSurvivor(i);
            if (target != -1 && GetRandomInt(1, 4) == 1) {
                float tpos[3];
                GetClientAbsOrigin(target, tpos);
                tpos[2] += 250.0;
                SpawnFlamingMeteor(tpos);
            }
        }
    }
    return Plugin_Continue;
}

// ==========================================
// KHI CƯỠI & KHI BỊ HẤT XUỐNG
// ==========================================
public void Event_JockeyRide(Event event, const char[] name, bool dontBroadcast) {
    int jockey = GetClientOfUserId(event.GetInt("userid"));
    int victim = GetClientOfUserId(event.GetInt("victim"));
    
    if (!IsValidJockey(jockey) || !IsValidSurvivor(victim)) return;
    
    if (g_cvJumpEnable.BoolValue) {
        CreateTimer(GetRandomFloat(g_cvJumpMin.FloatValue, g_cvJumpMax.FloatValue), Timer_AutoJump, GetClientUserId(jockey));
    }
    
    JockeyClass rc = g_iPlayerClass[jockey];
    int abs = g_iPlayerAbilities[jockey];

    if (rc == JockeyClass_Fire || (abs & ABILITY_FIRE)) {
        IgniteEntity(victim, 10.0);
    }
    
    if (rc == JockeyClass_Ice || (abs & ABILITY_ICE)) {
        // Đánh dấu mốc thời gian nạn nhân bị đóng băng
        g_fIceRideTime[victim] = GetGameTime() + 4.0;
    }
    
    if (rc == JockeyClass_Rabies || (abs & ABILITY_RABIES)) {
        CreateAoERabies(victim);
    }
    
    if (rc == JockeyClass_Smasher || (abs & ABILITY_SMASHER)) {
        DealDamage(victim, 40, jockey, DMG_CLUB);
        PerformShake(victim);
    }
}

// Event khi có người giải cứu Survivor (bắn chết Jockey, báng súng, v.v.)
public void Event_JockeyRideEnd(Event event, const char[] name, bool dontBroadcast) {
    int victim = GetClientOfUserId(event.GetInt("victim"));
    if (IsValidSurvivor(victim)) {
        // Hủy bỏ trạng thái đóng băng ICE lập tức
        g_fIceRideTime[victim] = 0.0; 
    }
}

// Vòng lặp kích hoạt nhảy tưng tưng
public Action Timer_AutoJump(Handle timer, any userid) {
    DoAutoJump(userid);
    return Plugin_Continue;
}

void DoAutoJump(int userid) {
    int client = GetClientOfUserId(userid);
    if (client && IsClientInGame(client) && GetClientTeam(client) == 3 && IsPlayerAlive(client)) {
        int bots = g_cvJumpBots.IntValue;
        if (bots != 2) {
            bool fake = IsFakeClient(client);
            if (fake && bots == 0) return;
            if (!fake && bots == 1) return;
        }

        int victim = GetEntPropEnt(client, Prop_Send, "m_jockeyVictim");
        if (victim > 0 && IsClientInGame(victim) && IsPlayerAlive(victim) && GetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker") == client) {
            
            if (GetEntityFlags(victim) & FL_ONGROUND) {
                float vel[3];
                // Lấy vận tốc hiện tại
                GetEntPropVector(victim, Prop_Data, "m_vecVelocity", vel);
                
                // ĐÃ SỬA AUTOJUMP: Ghi đè lực Z để nhảy dứt khoát
                vel[2] = g_cvJumpForce.FloatValue; 
                TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, vel);
                
                CreateTimer(GetRandomFloat(g_cvJumpMin.FloatValue, g_cvJumpMax.FloatValue), Timer_AutoJump, userid);
            } else {
                RequestFrame(Frame_AutoJump, userid);
            }
        }
    }
}

void Frame_AutoJump(int userid) {
    DoAutoJump(userid);
}

// ==========================================
// PHÒNG THỦ: SHIELD / COBALT
// ==========================================
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
    if (IsValidJockey(victim)) {
        JockeyClass rc = g_iPlayerClass[victim];
        int abs = g_iPlayerAbilities[victim];
        
        if (rc == JockeyClass_Shield || (abs & ABILITY_SHIELD)) {
            damage *= 0.2;
            return Plugin_Changed;
        }
        if (rc == JockeyClass_Cobalt || (abs & ABILITY_COBALT)) {
            damage *= 0.5;
            return Plugin_Changed;
        }
        if (rc == JockeyClass_Meteor || rc == JockeyClass_Fire || (abs & ABILITY_METEOR) || (abs & ABILITY_FIRE)) {
            if (damagetype & DMG_BURN) {
                damage = 0.0;
                return Plugin_Changed;
            }
        }
    }
    return Plugin_Continue;
}

// ==========================================
// KỸ NĂNG: NÉM ĐÁ (M2) & HOMING LEAP (M1/JUMP)
// ==========================================
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon) {
    if (IsValidJockey(client)) {
        if ((buttons & IN_ATTACK2)) {
            float currentTime = GetGameTime();
            if (currentTime - g_fLastRockTime[client] > 6.0) {
                g_fLastRockTime[client] = currentTime;
                PerformRockThrow(client);
            }
        }
        
        if ((buttons & IN_ATTACK) && !(GetEntityFlags(client) & FL_ONGROUND)) {
            int target = GetNearestSurvivor(client);
            if (target != -1) {
                float pos[3], tpos[3], autoAimVec[3];
                GetClientAbsOrigin(client, pos);
                GetClientAbsOrigin(target, tpos);
                tpos[2] += 40.0;
                
                MakeVectorFromPoints(pos, tpos, autoAimVec);
                NormalizeVector(autoAimVec, autoAimVec);
                ScaleVector(autoAimVec, 550.0);
                
                float currentVel[3];
                GetEntPropVector(client, Prop_Data, "m_vecVelocity", currentVel);
                currentVel[0] = (currentVel[0] + autoAimVec[0]) * 0.5;
                currentVel[1] = (currentVel[1] + autoAimVec[1]) * 0.5;
                TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, currentVel);
            }
        }
    }
    return Plugin_Continue;
}

void PerformRockThrow(int client) {
    int target = GetNearestSurvivor(client);
    if (target == -1) return;
    
    float pos[3];
    GetClientAbsOrigin(client, pos);
    pos[2] -= 45.0;
    
    int rock = CreateEntityByName("prop_physics");
    if (rock != -1) {
        DispatchKeyValue(rock, "model", "models/props_debris/concrete_chunk01a.mdl");
        DispatchSpawn(rock);
        SetEntProp(rock, Prop_Send, "m_CollisionGroup", 1); 
        TeleportEntity(rock, pos, NULL_VECTOR, NULL_VECTOR);
        
        float upVelocity[3] = {0.0, 0.0, 350.0};
        TeleportEntity(rock, NULL_VECTOR, NULL_VECTOR, upVelocity);
        
        DataPack pack;
        CreateDataTimer(1.2, Timer_LaunchRock, pack, TIMER_FLAG_NO_MAPCHANGE);
        pack.WriteCell(EntIndexToEntRef(rock));
        pack.WriteCell(GetClientUserId(target));
        pack.WriteCell(GetClientUserId(client));
    }
}

public Action Timer_LaunchRock(Handle timer, DataPack pack) {
    pack.Reset();
    int rock = EntRefToEntIndex(pack.ReadCell());
    int target = GetClientOfUserId(pack.ReadCell());
    int attacker = GetClientOfUserId(pack.ReadCell());
    
    if (rock != -1 && IsValidEntity(rock) && IsValidSurvivor(target)) {
        float rockPos[3], targetPos[3], velocity[3];
        GetEntPropVector(rock, Prop_Send, "m_vecOrigin", rockPos);
        GetClientAbsOrigin(target, targetPos);
        targetPos[2] += 45.0;
        
        MakeVectorFromPoints(rockPos, targetPos, velocity);
        NormalizeVector(velocity, velocity);
        ScaleVector(velocity, 2000.0);
        
        SetEntProp(rock, Prop_Send, "m_CollisionGroup", 0);
        TeleportEntity(rock, NULL_VECTOR, NULL_VECTOR, velocity);
        SetEntPropEnt(rock, Prop_Send, "m_hOwnerEntity", attacker);
    } else if (rock != -1 && IsValidEntity(rock)) {
        RemoveEntity(rock);
    }
    return Plugin_Stop;
}

// ==========================================
// CÁC HÀM TIỆN ÍCH (UTILITIES) & HIỆU ỨNG
// ==========================================
bool IsValidSurvivor(int client) {
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == 2);
}

bool IsValidJockey(int client) {
    if (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client)) {
        if (GetClientTeam(client) == 3 && GetEntProp(client, Prop_Send, "m_zombieClass") == 5) return true;
    }
    return false;
}

int GetRandomSurvivor() {
    int[] survs = new int[MaxClients];
    int count = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsValidSurvivor(i)) survs[count++] = i;
    }
    return (count > 0) ? survs[GetRandomInt(0, count - 1)] : -1;
}

int GetNearestSurvivor(int client) {
    float pos[3], tpos[3];
    GetClientAbsOrigin(client, pos);
    float minDist = 999999.0;
    int nearest = -1;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsValidSurvivor(i)) {
            GetClientAbsOrigin(i, tpos);
            float dist = GetVectorDistance(pos, tpos);
            if (dist < minDist) { minDist = dist; nearest = i; }
        }
    }
    return nearest;
}

float[] GetClientOrigin(int client) {
    float pos[3];
    GetClientAbsOrigin(client, pos);
    return pos;
}

void PerformShake(int client) {
    Handle msg = StartMessageOne("Shake", client);
    if (msg != null) {
        BfWriteByte(msg, 0); 
        BfWriteFloat(msg, 15.0);
        BfWriteFloat(msg, 150.0);
        BfWriteFloat(msg, 2.5);
        EndMessage();
    }
}

void CreateFire(float pos[3]) {
    int fire = CreateEntityByName("env_fire");
    if (fire != -1) {
        DispatchKeyValue(fire, "firesize", "50");
        DispatchKeyValue(fire, "health", "3");
        DispatchKeyValue(fire, "fireattack", "1");
        DispatchSpawn(fire);
        TeleportEntity(fire, pos, NULL_VECTOR, NULL_VECTOR);
        AcceptEntityInput(fire, "StartFire");
        CreateTimer(4.0, Timer_RemoveEntity, EntIndexToEntRef(fire));
    }
}

// ĐÃ SỬA BÃI AXIT: Sử dụng VScript DropSpit để tạo bãi axit dính chặt xuống đất
void CreateAoESpit(int client, float pos[3]) {
    #pragma unused client
    
    // 1. Tạo 1 bãi axit ngay dưới chân Jockey
    SpawnVScriptSpit(pos);
    
    // 2. Tạo thêm 3 bãi axit mở rộng xung quanh để tăng AoE
    float angles[3] = {0.0, 0.0, 0.0};
    for(int i = 0; i < 3; i++) {
        angles[1] = i * 120.0;
        float dir[3], spawnPos[3];
        GetAngleVectors(angles, dir, NULL_VECTOR, NULL_VECTOR);
        
        spawnPos[0] = pos[0] + dir[0] * 65.0; // Khoảng cách giãn ra
        spawnPos[1] = pos[1] + dir[1] * 65.0;
        spawnPos[2] = pos[2] + 15.0; // Nâng lên 1 chút để không bị kẹt dưới sàn nhà
        
        SpawnVScriptSpit(spawnPos);
    }
}

// Hàm hỗ trợ: Gọi VScript ẩn của L4D2 để rải Spit
void SpawnVScriptSpit(float pos[3]) {
    int script = CreateEntityByName("logic_script");
    if (script != -1) {
        DispatchSpawn(script);
        
        char code[256];
        // Sử dụng hàm DropSpit() gốc của game
        Format(code, sizeof(code), "DropSpit(Vector(%.2f, %.2f, %.2f));", pos[0], pos[1], pos[2]);
        
        SetVariantString(code);
        AcceptEntityInput(script, "RunScriptCode");
        
        RemoveEntity(script);
    }
}

void SpawnExplosive(float pos[3]) {
    int prop = CreateEntityByName("prop_physics");
    if (prop != -1) {
        DispatchKeyValue(prop, "model", "models/props_junk/propanecanister001a.mdl");
        DispatchSpawn(prop);
        pos[2] += 20.0;
        TeleportEntity(prop, pos, NULL_VECTOR, NULL_VECTOR);
        AcceptEntityInput(prop, "break");
    }
}

void SpawnFlamingMeteor(float pos[3]) {
    int rock = CreateEntityByName("prop_physics");
    if (rock != -1) {
        DispatchKeyValue(rock, "model", "models/props_debris/concrete_chunk01a.mdl");
        DispatchSpawn(rock);
        TeleportEntity(rock, pos, NULL_VECTOR, NULL_VECTOR);
        
        float downVec[3] = {0.0, 0.0, -1500.0}; 
        TeleportEntity(rock, NULL_VECTOR, NULL_VECTOR, downVec);
        IgniteEntity(rock, 8.0);
        
        CreateTimer(3.0, Timer_RemoveEntity, EntIndexToEntRef(rock));
    }
}

void PerformBlind(int client, int amount) {
    Handle message = StartMessageOne("Fade", client);
    if (message != null) {
        BfWriteShort(message, 1500); BfWriteShort(message, 1000);
        BfWriteShort(message, (0x0001 | 0x0010));
        BfWriteByte(message, 0); BfWriteByte(message, 0); BfWriteByte(message, 0);
        BfWriteByte(message, amount);
        EndMessage();
    }
}

void CreateAoERabies(int centerClient) {
    float pos[3];
    GetClientAbsOrigin(centerClient, pos);
    for(int i = 1; i <= MaxClients; i++) {
        if(IsValidSurvivor(i)) {
            float tpos[3];
            GetClientAbsOrigin(i, tpos);
            if(GetVectorDistance(pos, tpos) < 300.0) {
                SDKCallBiled(i, centerClient);
            }
        }
    }
}

void SDKCallBiled(int victim, int attacker) {
    #pragma unused attacker
    int itEnt = CreateEntityByName("env_splash");
    if (itEnt != -1) {
        float pos[3];
        GetClientAbsOrigin(victim, pos);
        pos[2] += 40.0;
        DispatchSpawn(itEnt);
        TeleportEntity(itEnt, pos, NULL_VECTOR, NULL_VECTOR);
        AcceptEntityInput(itEnt, "Splash");
        RemoveEntity(itEnt);
        SetEntPropFloat(victim, Prop_Send, "m_itTimer", GetGameTime() + 15.0);
    }
}

void DealDamage(int victim, int damage, int attacker, int damageType) {
    if (IsValidSurvivor(victim)) {
        char dmg_str[16], type_str[32];
        IntToString(damage, dmg_str, sizeof(dmg_str));
        IntToString(damageType, type_str, sizeof(type_str));
        int ptHurt = CreateEntityByName("point_hurt");
        if (ptHurt) {
            DispatchKeyValue(victim, "targetname", "sj_hurt");
            DispatchKeyValue(ptHurt, "DamageTarget", "sj_hurt");
            DispatchKeyValue(ptHurt, "Damage", dmg_str);
            DispatchKeyValue(ptHurt, "DamageType", type_str);
            DispatchSpawn(ptHurt);
            AcceptEntityInput(ptHurt, "Hurt", attacker);
            DispatchKeyValue(victim, "targetname", "donothing");
            RemoveEntity(ptHurt);
        }
    }
}

public Action Timer_RemoveEntity(Handle timer, int ref) {
    int ent = EntRefToEntIndex(ref);
    if (ent != -1 && IsValidEntity(ent)) RemoveEntity(ent);
    return Plugin_Stop;
}
