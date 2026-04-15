// <Bodytrap> - <Immortal Ghost Rider, Split CVars.>
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
#include <sdkhooks>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define MAX_EDICTS 2049

public Plugin myinfo = 
{
    name = "Body Trap Advanced",
    author = "Tyn Zũ",
    description = "ZSpawn Boomer Scanner Fixed, Pure VScript Stagger & DropSpit.",
    version = "25.0",
    url = ""
};

// CVar Core
ConVar g_cvEnable;
ConVar g_cvRange;
ConVar g_cvCountdown;

// CVar Damage & Duration (Pipebomb)
ConVar g_cvPipeDamage;
ConVar g_cvPipeRadius;
ConVar g_cvPipeStaggerDuration; 

// CVar Molotov
ConVar g_cvMolotovBodyDamage;    
ConVar g_cvMolotovTrailDamage;   
ConVar g_cvMolotovDuration;      
ConVar g_cvMolotovIgniteTime;    
ConVar g_cvMolotovTrailDuration; 

// CVar Vomit
ConVar g_cvVomitDamage;
ConVar g_cvVomitDuration;
ConVar g_cvVomitRadius;
ConVar g_cvVomitAcidScale;

// CVar Beam Ring Colors
ConVar g_cvBeamRadius;
ConVar g_cvBeamWidth;
ConVar g_cvColorPipe;
ConVar g_cvColorMolotov;
ConVar g_cvColorVomit;

enum TrapType
{
    TYPE_NONE,
    TYPE_PIPE,
    TYPE_MOLOTOV,
    TYPE_VOMIT
};

enum struct TrapData
{
    int ownerUserId;
    int targetEntRef;
    TrapType type;
    int countdown;
    Handle timer;
    Handle effectTimer;
    int beamSprite;
    int haloSprite;
}

TrapData g_Traps[MAX_EDICTS];
bool g_HasTrap[MAX_EDICTS];
bool g_IsHolding[MAXPLAYERS+1];
TrapType g_HoldingType[MAXPLAYERS+1];

bool g_bIsTrapInflictor[MAX_EDICTS];
TrapType g_TrapInflictorType[MAX_EDICTS];

public void OnPluginStart()
{
    g_cvEnable = CreateConVar("bodytrap_enable", "1", "Bật/tắt plugin");
    g_cvRange = CreateConVar("bodytrap_range", "150.0", "Khoảng cách gắn bẫy");
    g_cvCountdown = CreateConVar("bodytrap_countdown", "5", "Thời gian đếm ngược (giây)");
    
    g_cvPipeDamage = CreateConVar("bodytrap_pipe_damage", "500.0", "Sát thương nổ của pipebomb");
    g_cvPipeRadius = CreateConVar("bodytrap_pipe_radius", "400.0", "Bán kính nổ của pipebomb");
    g_cvPipeStaggerDuration = CreateConVar("bodytrap_pipe_stagger_duration", "2.0", "Thời gian chao đảo (giây)");
    
    g_cvMolotovBodyDamage = CreateConVar("bodytrap_molotov_body_damage", "10.0", "Sát thương thiêu đốt người bị gắn trap");
    g_cvMolotovTrailDamage = CreateConVar("bodytrap_molotov_trail_damage", "5.0", "Sát thương của vệt lửa dưới đất");
    g_cvMolotovDuration = CreateConVar("bodytrap_molotov_duration", "15.0", "Thời gian tồn tại của thùng xăng");
    g_cvMolotovIgniteTime = CreateConVar("bodytrap_molotov_ignite_time", "10.0", "Thời gian ngọn lửa bám chặt");
    g_cvMolotovTrailDuration = CreateConVar("bodytrap_molotov_trail_duration", "5.0", "Thời gian vệt lửa tồn tại");
    
    g_cvVomitDamage = CreateConVar("bodytrap_vomit_damage", "0.0", "Sát thương mỗi tick của acid");
    g_cvVomitDuration = CreateConVar("bodytrap_vomit_duration", "15.0", "Thời gian tồn tại bãi Acid");
    g_cvVomitRadius = CreateConVar("bodytrap_vomit_radius", "250.0", "Bán kính mù của Vomit");
    g_cvVomitAcidScale = CreateConVar("bodytrap_vomit_acid_scale", "1.0", "Khuếch đại vũng acid");
    
    g_cvBeamRadius = CreateConVar("bodytrap_beam_radius", "50.0", "Bán kính vòng beam");
    g_cvBeamWidth = CreateConVar("bodytrap_beam_width", "10.0", "Độ dày vòng beam");
    g_cvColorPipe = CreateConVar("bodytrap_color_pipe", "255 0 0 255", "Màu vòng beam Pipebomb");
    g_cvColorMolotov = CreateConVar("bodytrap_color_molotov", "255 128 0 255", "Màu vòng beam Molotov");
    g_cvColorVomit = CreateConVar("bodytrap_color_vomit", "0 255 0 255", "Màu vòng beam Vomitjar");
    
    AutoExecConfig(true, "bodytrap");
    
    HookEvent("entity_killed", Event_EntityKilled);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("round_start", Event_RoundStart);
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKHook(i, SDKHook_WeaponSwitch, OnWeaponSwitch);
            SDKHook(i, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
        }
    }
}

public void OnMapStart()
{
    ClearAllTraps();
    PrecacheModel("sprites/laserbeam.vmt", true);
    PrecacheModel("sprites/halo01.vmt", true);
    PrecacheModel("models/props_junk/gascan001a.mdl", true); 
    PrecacheModel("models/props_junk/propanecanister001a.mdl", true); 
    PrecacheParticle("burning_character_fire");
}

void PrecacheParticle(const char[] particleName)
{
    int particle = CreateEntityByName("info_particle_system");
    if (particle != -1)
    {
        DispatchKeyValue(particle, "effect_name", particleName);
        DispatchSpawn(particle);
        ActivateEntity(particle);
        AcceptEntityInput(particle, "Start");
        CreateTimer(0.1, Timer_KillEntity, EntIndexToEntRef(particle));
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_WeaponSwitch, OnWeaponSwitch);
    SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
    g_IsHolding[client] = false;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (entity <= 0 || entity >= MAX_EDICTS) return;
    if (StrEqual(classname, "infected") || StrEqual(classname, "witch") || StrEqual(classname, "env_fire"))
        SDKHook(entity, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public void OnEntityDestroyed(int entity)
{
    if (entity > 0 && entity < MAX_EDICTS) g_bIsTrapInflictor[entity] = false;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (!g_cvEnable.BoolValue || !IsPlayerAlive(client) || GetClientTeam(client) != 2) return Plugin_Continue; 
    
    char weaponName[64];
    GetClientWeapon(client, weaponName, sizeof(weaponName));
    
    TrapType trapType = TYPE_NONE;
    if (StrEqual(weaponName, "weapon_pipe_bomb")) trapType = TYPE_PIPE;
    else if (StrEqual(weaponName, "weapon_molotov")) trapType = TYPE_MOLOTOV;
    else if (StrEqual(weaponName, "weapon_vomitjar")) trapType = TYPE_VOMIT;
    
    if (trapType == TYPE_NONE)
    {
        g_IsHolding[client] = false;
        return Plugin_Continue;
    }
    
    if (buttons & IN_ATTACK)
    {
        if (!g_IsHolding[client])
        {
            g_IsHolding[client] = true;
            g_HoldingType[client] = trapType;
            PrintHintText(client, "Đang chuẩn bị bẫy: Áp sát mục tiêu và nhấn Chuột Phải (Shove)");
        }
    }
    else if (g_IsHolding[client] && (buttons & IN_ATTACK2))
    {
        int target = GetAimedTarget(client);
        if (target > 0 && target < MAX_EDICTS) AttachTrap(client, target, g_HoldingType[client]);
        g_IsHolding[client] = false;
        buttons &= ~IN_ATTACK2;
    }
    else if (g_IsHolding[client] && !(buttons & IN_ATTACK))
    {
        g_IsHolding[client] = false;
    }
    
    return Plugin_Continue;
}

int GetAimedTarget(int client)
{
    float origin[3], angles[3];
    GetClientEyePosition(client, origin);
    GetClientEyeAngles(client, angles);
    
    Handle trace = TR_TraceRayFilterEx(origin, angles, MASK_SHOT, RayType_Infinite, TraceFilter, client);
    int target = -1;
    if (TR_DidHit(trace))
    {
        target = TR_GetEntityIndex(trace);
        if (target > 0 && IsValidEntity(target))
        {
            float hitPos[3];
            TR_GetEndPosition(hitPos, trace);
            if (GetVectorDistance(origin, hitPos) <= g_cvRange.FloatValue)
            {
                CloseHandle(trace);
                return target;
            }
        }
    }
    CloseHandle(trace);
    return -1;
}

public bool TraceFilter(int entity, int mask, int data)
{
    if (entity == data) return false;
    if (entity > 0 && entity <= MaxClients) return true; 
    if (entity > MaxClients && IsValidEntity(entity))
    {
        char classname[64];
        GetEdictClassname(entity, classname, sizeof(classname));
        if (StrEqual(classname, "infected") || StrEqual(classname, "witch")) return true;
    }
    return false;
}

void AttachTrap(int owner, int target, TrapType type)
{
    if (g_HasTrap[target]) return;
    RemoveHeldItem(owner);
    
    g_HasTrap[target] = true;
    g_Traps[target].ownerUserId = GetClientUserId(owner);
    g_Traps[target].targetEntRef = EntIndexToEntRef(target);
    g_Traps[target].type = type;
    g_Traps[target].countdown = g_cvCountdown.IntValue;
    g_Traps[target].beamSprite = PrecacheModel("sprites/laserbeam.vmt");
    g_Traps[target].haloSprite = PrecacheModel("sprites/halo01.vmt");
    
    int ref = g_Traps[target].targetEntRef;
    g_Traps[target].timer = CreateTimer(1.0, Timer_TrapCountdown, ref, TIMER_REPEAT);
    g_Traps[target].effectTimer = CreateTimer(0.5, Timer_UpdateEffects, ref, TIMER_REPEAT);
    
    EmitSoundToAll("weapons/hegrenade/beep.wav", target);
}

void RemoveHeldItem(int client)
{
    int entity = GetPlayerWeaponSlot(client, 2);
    if (entity != -1)
    {
        RemovePlayerItem(client, entity);
        AcceptEntityInput(entity, "Kill");
    }
}

public Action Timer_TrapCountdown(Handle timer, int ref)
{
    int target = EntRefToEntIndex(ref);
    if (target == INVALID_ENT_REFERENCE || !IsValidEntity(target) || !g_HasTrap[target])
    {
        if (target > 0) g_HasTrap[target] = false;
        return Plugin_Stop;
    }

    if (target <= MaxClients && (!IsClientInGame(target) || !IsPlayerAlive(target)))
    {
        RemoveTrap(target);
        return Plugin_Stop;
    }
    
    g_Traps[target].countdown--;
    EmitSoundToAll("weapons/hegrenade/beep.wav", target);
    BlinkEntity(target, g_Traps[target].countdown, g_Traps[target].type);
    
    if (g_Traps[target].countdown <= 0)
    {
        ExplodeTrap(target);
        RemoveTrap(target);
        return Plugin_Stop;
    }
    
    CreateInstructorHint(target, g_Traps[target].countdown, g_Traps[target].type);
    
    return Plugin_Continue;
}

public Action Timer_UpdateEffects(Handle timer, int ref)
{
    int target = EntRefToEntIndex(ref);
    if (target == INVALID_ENT_REFERENCE || !IsValidEntity(target) || !g_HasTrap[target]) return Plugin_Stop;
    
    float pos[3];
    GetEntPropVector(target, Prop_Send, "m_vecOrigin", pos);
    pos[2] += 5.0;
    
    char sColor[32], sColors[4][8];
    if (g_Traps[target].type == TYPE_PIPE) g_cvColorPipe.GetString(sColor, sizeof(sColor));
    else if (g_Traps[target].type == TYPE_MOLOTOV) g_cvColorMolotov.GetString(sColor, sizeof(sColor));
    else g_cvColorVomit.GetString(sColor, sizeof(sColor));

    int color[4] = {255, 0, 0, 255};
    if (ExplodeString(sColor, " ", sColors, 4, 8) >= 3)
    {
        color[0] = StringToInt(sColors[0]);
        color[1] = StringToInt(sColors[1]);
        color[2] = StringToInt(sColors[2]);
    }
    
    TE_SetupBeamRingPoint(pos, 10.0, g_cvBeamRadius.FloatValue, g_Traps[target].beamSprite, g_Traps[target].haloSprite, 0, 15, 0.5, g_cvBeamWidth.FloatValue, 1.0, color, 10, 0);
    TE_SendToAll();
    
    return Plugin_Continue;
}

void CreateInstructorHint(int target, int timeleft, TrapType type)
{
    int hint = CreateEntityByName("env_instructor_hint");
    if (hint != -1)
    {
        char sTargetName[64];
        GetEntPropString(target, Prop_Data, "m_iName", sTargetName, sizeof(sTargetName));
        if (sTargetName[0] == '\0') 
        {
            Format(sTargetName, sizeof(sTargetName), "trap_victim_%d", target);
            DispatchKeyValue(target, "targetname", sTargetName);
        }

        char sCaption[64], sColor[32];
        Format(sCaption, sizeof(sCaption), "BOM NỔ SAU %d GIÂY!", timeleft);

        if (type == TYPE_PIPE) strcopy(sColor, sizeof(sColor), "255 0 0");
        else if (type == TYPE_MOLOTOV) strcopy(sColor, sizeof(sColor), "255 128 0");
        else strcopy(sColor, sizeof(sColor), "0 255 0");

        DispatchKeyValue(hint, "hint_target", sTargetName);
        DispatchKeyValue(hint, "hint_caption", sCaption);
        DispatchKeyValue(hint, "hint_color", sColor);
        DispatchKeyValue(hint, "hint_timeout", "1.1");
        DispatchKeyValue(hint, "hint_icon_onscreen", "icon_alert");
        DispatchKeyValue(hint, "hint_instance_type", "2");
        DispatchKeyValue(hint, "hint_static", "0");
        DispatchKeyValue(hint, "hint_forcecaption", "1");
        
        DispatchSpawn(hint);
        
        float pos[3];
        GetEntPropVector(target, Prop_Send, "m_vecOrigin", pos);
        pos[2] += 80.0;
        TeleportEntity(hint, pos, NULL_VECTOR, NULL_VECTOR);
        
        SetVariantString(sTargetName);
        AcceptEntityInput(hint, "SetParent");
        AcceptEntityInput(hint, "ShowHint");
        
        CreateTimer(1.1, Timer_KillEntity, EntIndexToEntRef(hint));
    }
}

void BlinkEntity(int target, int countdown, TrapType type)
{
    int glowColor = 0xFF0000;
    if (type == TYPE_VOMIT) glowColor = 0x00FF00;
    else if (type == TYPE_MOLOTOV) glowColor = 0xFF8000;

    if (target <= MaxClients)
    {
        SetEntProp(target, Prop_Send, "m_iGlowType", (countdown % 2 == 0) ? 3 : 0);
        SetEntProp(target, Prop_Send, "m_glowColorOverride", glowColor);
    }
    else
    {
        if (countdown % 2 == 0) 
        {
            if (type == TYPE_PIPE) SetEntityRenderColor(target, 255, 0, 0, 255);
            else if (type == TYPE_MOLOTOV) SetEntityRenderColor(target, 255, 128, 0, 255);
            else SetEntityRenderColor(target, 0, 255, 0, 255);
        }
        else SetEntityRenderColor(target, 255, 255, 255, 255);
    }
}

void ExplodeTrap(int target)
{
    float pos[3];
    GetEntPropVector(target, Prop_Send, "m_vecOrigin", pos);
    
    int owner = GetClientOfUserId(g_Traps[target].ownerUserId);
    if (owner == 0 || !IsClientInGame(owner)) owner = 0; 
    
    switch (g_Traps[target].type)
    {
        case TYPE_PIPE: ExecutePipebombEffect(pos, owner);
        case TYPE_MOLOTOV: ExecuteMolotovEffect(pos, target, owner); 
        case TYPE_VOMIT: ExecuteVomitjarEffect(pos, owner);
        case TYPE_NONE: { }
    }
}

// ==== VSCRIPT STAGGER ====
void ApplyStagger(int client, float pos[3])
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client)) return;
    
    int logic = CreateEntityByName("logic_script");
    if (logic != -1)
    {
        DispatchSpawn(logic);
        char code[256];
        Format(code, sizeof(code), "local p = GetPlayerFromUserID(%d); if(p) p.Stagger(Vector(%.1f, %.1f, %.1f));", GetClientUserId(client), pos[0], pos[1], pos[2]);
        SetVariantString(code);
        AcceptEntityInput(logic, "RunScriptCode");
        AcceptEntityInput(logic, "Kill");
    }
}

void ApplyChainStagger(int victim, int owner, float pos[3], float duration)
{
    ApplyStagger(victim, pos);
    
    if (duration > 2.0)
    {
        DataPack pack;
        CreateDataTimer(2.0, Timer_ChainStagger, pack, TIMER_FLAG_NO_MAPCHANGE);
        pack.WriteCell(GetClientUserId(victim));
        pack.WriteCell(GetClientUserId(owner));
        pack.WriteFloat(pos[0]);
        pack.WriteFloat(pos[1]);
        pack.WriteFloat(pos[2]);
        pack.WriteFloat(duration - 2.0);
    }
}

public Action Timer_ChainStagger(Handle timer, DataPack pack)
{
    pack.Reset();
    int victim = GetClientOfUserId(pack.ReadCell());
    int owner = GetClientOfUserId(pack.ReadCell());
    float pos[3];
    pos[0] = pack.ReadFloat();
    pos[1] = pack.ReadFloat();
    pos[2] = pack.ReadFloat();
    float remaining = pack.ReadFloat();

    if (victim > 0 && IsClientInGame(victim) && IsPlayerAlive(victim) && !IsIncapped(victim))
    {
        ApplyChainStagger(victim, owner, pos, remaining);
    }
    
    return Plugin_Stop;
}

void ExecutePipebombEffect(float pos[3], int owner)
{
    float offsets[5][3] = {
        {0.0, 0.0, 15.0}, {25.0, 0.0, 15.0}, {-25.0, 0.0, 15.0}, {0.0, 25.0, 15.0}, {0.0, -25.0, 15.0} 
    };

    for (int i = 0; i < 5; i++)
    {
        int prop = CreateEntityByName("prop_physics");
        if (prop > MaxClients && IsValidEntity(prop))
        {
            float spawnPos[3];
            spawnPos[0] = pos[0] + offsets[i][0];
            spawnPos[1] = pos[1] + offsets[i][1];
            spawnPos[2] = pos[2] + offsets[i][2];

            DispatchKeyValue(prop, "model", "models/props_junk/propanecanister001a.mdl");
            DispatchSpawn(prop);
            SetEntData(prop, GetEntSendPropOffs(prop, "m_CollisionGroup"), 1, 1, true); 
            TeleportEntity(prop, spawnPos, NULL_VECTOR, NULL_VECTOR);
            AcceptEntityInput(prop, "break");
        }
    }
    
    float radius = g_cvPipeRadius.FloatValue;
    float damage = g_cvPipeDamage.FloatValue;
    float staggerDuration = g_cvPipeStaggerDuration.FloatValue;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i))
        {
            float clientPos[3];
            GetClientAbsOrigin(i, clientPos);
            if (GetVectorDistance(pos, clientPos) <= radius)
            {
                SDKHooks_TakeDamage(i, owner, owner, damage, DMG_BLAST);
                if (!IsIncapped(i)) ApplyChainStagger(i, owner, pos, staggerDuration);
            }
        }
    }
    
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "infected")) != -1)
    {
        float entPos[3];
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entPos);
        if (GetVectorDistance(pos, entPos) <= radius) SDKHooks_TakeDamage(entity, owner, owner, damage, DMG_BLAST);
    }
    entity = -1;
    while ((entity = FindEntityByClassname(entity, "witch")) != -1)
    {
        float entPos[3];
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entPos);
        if (GetVectorDistance(pos, entPos) <= radius) SDKHooks_TakeDamage(entity, owner, owner, damage, DMG_BLAST);
    }
}

int AttachFireToBody(int target)
{
    int particle = CreateEntityByName("info_particle_system");
    if (particle != -1)
    {
        DispatchKeyValue(particle, "effect_name", "burning_character_fire");
        DispatchSpawn(particle);
        
        float tPos[3];
        GetEntPropVector(target, Prop_Send, "m_vecOrigin", tPos);
        TeleportEntity(particle, tPos, NULL_VECTOR, NULL_VECTOR);
        
        SetVariantString("!activator");
        AcceptEntityInput(particle, "SetParent", target, particle, 0);
        AcceptEntityInput(particle, "Start");
    }
    return particle;
}

void ExecuteMolotovEffect(float pos[3], int target, int owner)
{
    EmitSoundToAll("ambient/explosions/explode_1.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, -1, pos);

    int propane = CreateEntityByName("prop_physics");
    if (propane > MaxClients && IsValidEntity(propane))
    {
        float pPos[3]; pPos = pos; pPos[2] += 10.0;
        DispatchKeyValue(propane, "model", "models/props_junk/propanecanister001a.mdl");
        DispatchSpawn(propane);
        SetEntData(propane, GetEntSendPropOffs(propane, "m_CollisionGroup"), 1, 1, true); 
        TeleportEntity(propane, pPos, NULL_VECTOR, NULL_VECTOR);
        AcceptEntityInput(propane, "break");
    }

    float offsets[3][2] = { {20.0, 0.0}, {-10.0, 17.32}, {-10.0, -17.32} };
    for (int i = 0; i < 3; i++)
    {
        int gascan = CreateEntityByName("prop_physics");
        if (gascan > MaxClients && IsValidEntity(gascan))
        {
            float gPos[3];
            gPos[0] = pos[0] + offsets[i][0];
            gPos[1] = pos[1] + offsets[i][1];
            gPos[2] = pos[2] + 15.0; 
            
            DispatchKeyValue(gascan, "model", "models/props_junk/gascan001a.mdl");
            DispatchSpawn(gascan);
            SetEntData(gascan, GetEntSendPropOffs(gascan, "m_CollisionGroup"), 1, 1, true); 
            TeleportEntity(gascan, gPos, NULL_VECTOR, NULL_VECTOR);
            AcceptEntityInput(gascan, "break"); 
        }
    }
    TagTrapInflictor(pos, TYPE_MOLOTOV); 

    float igniteTime = g_cvMolotovIgniteTime.FloatValue;
    if (igniteTime > 0.0 && target > 0 && IsValidEntity(target))
    {
        int bodyFire = AttachFireToBody(target);
        
        DataPack pack;
        CreateDataTimer(0.5, Timer_FireTrail, pack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        pack.WriteCell(EntIndexToEntRef(target));
        pack.WriteCell(GetClientUserId(owner));
        pack.WriteFloat(igniteTime);
        pack.WriteCell(EntIndexToEntRef(bodyFire)); 
    }
}

public Action Timer_FireTrail(Handle timer, DataPack pack)
{
    pack.Reset();
    int targetRef = pack.ReadCell();
    int ownerUserId = pack.ReadCell();
    float remainingTime = pack.ReadFloat() - 0.5;
    int bodyFireRef = pack.ReadCell();

    int target = EntRefToEntIndex(targetRef);
    int bodyFire = EntRefToEntIndex(bodyFireRef);

    if (target == INVALID_ENT_REFERENCE || remainingTime <= 0.0 || !IsValidEntity(target) || (target <= MaxClients && !IsPlayerAlive(target)))
    {
        if (bodyFire != INVALID_ENT_REFERENCE) AcceptEntityInput(bodyFire, "Kill");
        if (target != INVALID_ENT_REFERENCE && IsValidEntity(target)) ExtinguishEntity(target);
        return Plugin_Stop;
    }
    
    if (GetEntityFlags(target) & FL_INWATER)
    {
        if (bodyFire != INVALID_ENT_REFERENCE) AcceptEntityInput(bodyFire, "Kill");
        ExtinguishEntity(target);
        return Plugin_Stop;
    }

    if (bodyFire == INVALID_ENT_REFERENCE)
    {
        bodyFire = AttachFireToBody(target);
        bodyFireRef = EntIndexToEntRef(bodyFire);
    }

    IgniteEntity(target, 1.0);

    pack.Reset();
    pack.WriteCell(targetRef);
    pack.WriteCell(ownerUserId);
    pack.WriteFloat(remainingTime);
    pack.WriteCell(bodyFireRef);

    float pos[3];
    GetEntPropVector(target, Prop_Send, "m_vecOrigin", pos);

    int owner = GetClientOfUserId(ownerUserId);
    if (owner == 0 || !IsClientInGame(owner)) owner = 0;

    float bodyDamage = g_cvMolotovBodyDamage.FloatValue;
    if (bodyDamage > 0.0) SDKHooks_TakeDamage(target, owner, owner, bodyDamage, DMG_BURN);

    int groundFire = CreateEntityByName("env_fire");
    if (groundFire != -1)
    {
        char sDuration[16], sTrailDamage[16];
        FloatToString(g_cvMolotovTrailDuration.FloatValue, sDuration, sizeof(sDuration));
        FloatToString(g_cvMolotovTrailDamage.FloatValue * 2.0, sTrailDamage, sizeof(sTrailDamage)); 
        
        DispatchKeyValue(groundFire, "health", sDuration);  
        DispatchKeyValue(groundFire, "firesize", "60");     
        DispatchKeyValue(groundFire, "fireattack", sTrailDamage); 
        DispatchSpawn(groundFire);
        
        TeleportEntity(groundFire, pos, NULL_VECTOR, NULL_VECTOR);
        AcceptEntityInput(groundFire, "StartFire");
        
        g_bIsTrapInflictor[groundFire] = true;
        g_TrapInflictorType[groundFire] = TYPE_MOLOTOV;
        
        float duration = g_cvMolotovTrailDuration.FloatValue;
        if (duration > 0.0) CreateTimer(duration, Timer_KillEntity, EntIndexToEntRef(groundFire));
    }

    float aoeRadius = 100.0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (i != target && IsClientInGame(i) && IsPlayerAlive(i))
        {
            float clientPos[3];
            GetClientAbsOrigin(i, clientPos);
            if (GetVectorDistance(pos, clientPos) <= aoeRadius)
            {
                SDKHooks_TakeDamage(i, owner, owner, bodyDamage, DMG_BURN);
            }
        }
    }

    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "infected")) != -1)
    {
        float entPos[3];
        GetEntPropVector(ent, Prop_Send, "m_vecOrigin", entPos);
        if (GetVectorDistance(pos, entPos) <= aoeRadius)
        {
            SDKHooks_TakeDamage(ent, owner, owner, bodyDamage, DMG_BURN);
            IgniteEntity(ent, 3.0); 
        }
    }
    
    ent = -1;
    while ((ent = FindEntityByClassname(ent, "witch")) != -1)
    {
        float entPos[3];
        GetEntPropVector(ent, Prop_Send, "m_vecOrigin", entPos);
        if (GetVectorDistance(pos, entPos) <= aoeRadius)
        {
            SDKHooks_TakeDamage(ent, owner, owner, bodyDamage, DMG_BURN);
            IgniteEntity(ent, 3.0);
        }
    }

    return Plugin_Continue;
}

public bool TraceFilter_IgnorePlayers(int entity, int contentsMask)
{
    if (entity <= MaxClients) return false;
    char classname[64];
    GetEdictClassname(entity, classname, sizeof(classname));
    if (StrEqual(classname, "infected") || StrEqual(classname, "witch")) return false;
    return true; 
}

bool GetGroundPosition(float pos[3], float groundPos[3])
{
    float start[3], end[3];
    start = pos;
    end = pos;
    start[2] += 100.0;
    end[2] -= 100.0;
    
    Handle trace = TR_TraceRayFilterEx(start, end, MASK_SOLID, RayType_EndPoint, TraceFilter_IgnorePlayers);
    bool hit = TR_DidHit(trace);
    if (hit)
    {
        TR_GetEndPosition(groundPos, trace);
        groundPos[2] += 5.0;
    }
    else groundPos = pos;
    
    CloseHandle(trace);
    return hit;
}

// ==== VOMIT TRAP FIX: ZSPAWN SCANNER VỚI CELL DATA ==== //
void ExecuteVomitjarEffect(float pos[3], int owner)
{
    // 1. VSCRIPT STAGGER
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
        {
            float vEnd[3];
            GetClientAbsOrigin(i, vEnd);
            if (GetVectorDistance(pos, vEnd) <= g_cvVomitRadius.FloatValue)
            {
                ApplyStagger(i, pos);
            }
        }
    }

    // 2. ÉP ENGINE L4D2 ĐẺ MỘT CON BOOMER TỪ VSCRIPT
    int logicBoomer = CreateEntityByName("logic_script");
    if (logicBoomer != -1)
    {
        DispatchSpawn(logicBoomer);
        char code[256];
        Format(code, sizeof(code), "ZSpawn({type=2, pos=Vector(%.1f, %.1f, %.1f)});", pos[0], pos[1], pos[2] + 20.0);
        SetVariantString(code);
        AcceptEntityInput(logicBoomer, "RunScriptCode");
        AcceptEntityInput(logicBoomer, "Kill");
    }

    // 3. KHỞI TẠO RADAR QUÉT TÌM CON BOOMER VỪA ĐẺ
    DataPack bPack;
    CreateDataTimer(0.1, Timer_FindAndDetonateBoomer, bPack, TIMER_FLAG_NO_MAPCHANGE);
    bPack.WriteFloat(pos[0]);
    bPack.WriteFloat(pos[1]);
    bPack.WriteFloat(pos[2] + 20.0);
    bPack.WriteCell(GetClientUserId(owner));
    bPack.WriteCell(0); // LƯU Ý: Đã sửa thành WriteCell

    EmitSoundToAll("player/boomer/explode/exp_boomer.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, -1, pos);
    
    // 4. DROPSPIT VSCRIPT
    float groundPos[3];
    GetGroundPosition(pos, groundPos);
    
    float scale = g_cvVomitAcidScale.FloatValue;
    int repeat = RoundToNearest(scale);
    if (repeat < 1) repeat = 1;
    if (repeat > 5) repeat = 5;

    float offsets[5][2] = { {0.0, 0.0}, {40.0, 0.0}, {-20.0, 34.6}, {-20.0, -34.6}, {0.0, -40.0} };

    for (int r = 0; r < repeat; r++)
    {
        float spitPos[3];
        spitPos = groundPos;
        
        if (r < 5)
        {
            spitPos[0] += offsets[r][0];
            spitPos[1] += offsets[r][1];
        }

        int logicSpit = CreateEntityByName("logic_script");
        if (logicSpit != -1)
        {
            DispatchSpawn(logicSpit);
            char spitCode[128];
            Format(spitCode, sizeof(spitCode), "DropSpit(Vector(%.1f, %.1f, %.1f));", spitPos[0], spitPos[1], spitPos[2]);
            SetVariantString(spitCode);
            AcceptEntityInput(logicSpit, "RunScriptCode");
            AcceptEntityInput(logicSpit, "Kill");
        }
    }
    
    int swarm = CreateEntityByName("insect_swarm");
    if (swarm > MaxClients && IsValidEntity(swarm))
    {
        if (owner > 0) SetEntPropEnt(swarm, Prop_Send, "m_hOwnerEntity", owner);
        DispatchSpawn(swarm);
        TeleportEntity(swarm, groundPos, NULL_VECTOR, NULL_VECTOR);
        AcceptEntityInput(swarm, "Start");
    }
    
    TagTrapInflictor(groundPos, TYPE_VOMIT);
}

// Radar tìm và ép nổ Boomer
public Action Timer_FindAndDetonateBoomer(Handle timer, DataPack pack)
{
    pack.Reset();
    float pos[3];
    pos[0] = pack.ReadFloat();
    pos[1] = pack.ReadFloat();
    pos[2] = pack.ReadFloat();
    int ownerUserId = pack.ReadCell();
    int attempts = pack.ReadCell(); // LƯU Ý: Đã sửa thành ReadCell

    if (attempts >= 10) return Plugin_Stop; 

    bool found = false;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && IsFakeClient(i) && GetClientTeam(i) == 3 && GetEntProp(i, Prop_Send, "m_zombieClass") == 2)
        {
            float bPos[3];
            GetClientAbsOrigin(i, bPos);
            if (GetVectorDistance(pos, bPos) < 200.0) 
            {
                int owner = GetClientOfUserId(ownerUserId);

                SetEntityRenderMode(i, RENDER_NONE);

                if (owner > 0 && IsClientInGame(owner))
                {
                    SDKHooks_TakeDamage(i, owner, owner, 1000.0, 64);
                }
                ForcePlayerSuicide(i); 

                CreateTimer(0.1, Timer_KickFakeClient, GetClientUserId(i));
                
                found = true;
                break; 
            }
        }
    }

    if (!found)
    {
        DataPack newPack;
        CreateDataTimer(0.1, Timer_FindAndDetonateBoomer, newPack, TIMER_FLAG_NO_MAPCHANGE);
        newPack.WriteFloat(pos[0]);
        newPack.WriteFloat(pos[1]);
        newPack.WriteFloat(pos[2]);
        newPack.WriteCell(ownerUserId);
        newPack.WriteCell(attempts + 1); // LƯU Ý: Đã sửa thành WriteCell
    }

    return Plugin_Stop;
}

public Action Timer_KickFakeClient(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client) && IsFakeClient(client))
    {
        KickClient(client);
    }
    return Plugin_Stop;
}

void TagTrapInflictor(float pos[3], TrapType type)
{
    Handle pack;
    CreateDataTimer(0.1, Timer_TagInflictor, pack); 
    WritePackFloat(pack, pos[0]);
    WritePackFloat(pack, pos[1]);
    WritePackFloat(pack, pos[2]);
    WritePackCell(pack, type);
}

public Action Timer_TagInflictor(Handle timer, Handle pack)
{
    ResetPack(pack);
    float pos[3];
    pos[0] = ReadPackFloat(pack);
    pos[1] = ReadPackFloat(pack);
    pos[2] = ReadPackFloat(pack);
    TrapType type = view_as<TrapType>(ReadPackCell(pack));

    char classname[32];
    float radius = 0.0, duration = 0.0;

    if (type == TYPE_MOLOTOV)
    {
        strcopy(classname, sizeof(classname), "inferno");
        radius = 200.0;
        duration = g_cvMolotovDuration.FloatValue;
    }
    else if (type == TYPE_VOMIT)
    {
        strcopy(classname, sizeof(classname), "insect_swarm"); 
        radius = 350.0; 
        duration = g_cvVomitDuration.FloatValue;
    }

    int ent = -1;
    while ((ent = FindEntityByClassname(ent, classname)) != -1)
    {
        if (!g_bIsTrapInflictor[ent]) 
        {
            float entPos[3];
            GetEntPropVector(ent, Prop_Send, "m_vecOrigin", entPos);
            if (GetVectorDistance(pos, entPos) <= radius)
            {
                g_bIsTrapInflictor[ent] = true;
                g_TrapInflictorType[ent] = type;
                if (duration > 0.0) CreateTimer(duration, Timer_KillEntity, EntIndexToEntRef(ent));
            }
        }
    }
    return Plugin_Stop;
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (inflictor > 0 && inflictor < MAX_EDICTS && g_bIsTrapInflictor[inflictor])
    {
        if (g_TrapInflictorType[inflictor] == TYPE_MOLOTOV)
        {
            char classname[64];
            GetEdictClassname(inflictor, classname, sizeof(classname));
            
            if (StrEqual(classname, "env_fire"))
            {
                float customDmg = g_cvMolotovTrailDamage.FloatValue;
                if (customDmg > 0.0)
                {
                    damage = customDmg;
                    return Plugin_Changed;
                }
            }
            else
            {
                float customDmg = g_cvMolotovBodyDamage.FloatValue; 
                if (customDmg > 0.0)
                {
                    damage = customDmg;
                    return Plugin_Changed;
                }
            }
        }
        else if (g_TrapInflictorType[inflictor] == TYPE_VOMIT)
        {
            float customDmg = g_cvVomitDamage.FloatValue;
            if (customDmg > 0.0)
            {
                damage = customDmg;
                return Plugin_Changed;
            }
        }
    }
    return Plugin_Continue;
}

bool IsIncapped(int client)
{
    return (GetClientTeam(client) == 2 && GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) == 1);
}

public Action Timer_KillEntity(Handle timer, int ref)
{
    int entity = EntRefToEntIndex(ref);
    if (entity != INVALID_ENT_REFERENCE) AcceptEntityInput(entity, "Kill");
    return Plugin_Stop;
}

public Action OnWeaponSwitch(int client, int weapon)
{
    g_IsHolding[client] = false;
    return Plugin_Continue;
}

void RemoveTrap(int target)
{
    if (target <= 0 || target >= MAX_EDICTS || !g_HasTrap[target]) return;
    
    if (g_Traps[target].timer != null) KillTimer(g_Traps[target].timer);
    if (g_Traps[target].effectTimer != null) KillTimer(g_Traps[target].effectTimer);
    
    g_Traps[target].timer = null;
    g_Traps[target].effectTimer = null;
    
    if (target <= MaxClients && IsClientInGame(target)) SetEntProp(target, Prop_Send, "m_iGlowType", 0);
    else if (IsValidEntity(target)) SetEntityRenderColor(target, 255, 255, 255, 255);
    
    g_HasTrap[target] = false;
}

public void Event_EntityKilled(Event event, const char[] name, bool dontBroadcast)
{
    int entity = event.GetInt("entindex_killed");
    if (entity > 0 && entity < MAX_EDICTS && g_HasTrap[entity]) RemoveTrap(entity);
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) { ClearAllTraps(); }
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) { ClearAllTraps(); }

void ClearAllTraps()
{
    for (int i = 1; i < MAX_EDICTS; i++)
    {
        if (g_HasTrap[i]) RemoveTrap(i);
    }
}
