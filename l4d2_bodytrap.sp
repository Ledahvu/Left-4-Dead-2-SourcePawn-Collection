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
    description = "No L4DHooks Dependency, Immortal Ghost Rider, Split CVars.",
    version = "15.0",
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

// CVar Molotov (Tách biệt Body và Trail)
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

// SDKCall Handles
Handle g_hVomitOnPlayer;
Handle g_hSpitterDetonate;

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
    Handle conf = LoadGameConfigFile("bodytrap");
    if (conf != null)
    {
        StartPrepSDKCall(SDKCall_Player);
        if (PrepSDKCall_SetFromConf(conf, SDKConf_Signature, "CTerrorPlayer_OnVomitedUpon"))
        {
            PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
            PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
            g_hVomitOnPlayer = EndPrepSDKCall();
        }
        
        StartPrepSDKCall(SDKCall_Entity);
        if (PrepSDKCall_SetFromConf(conf, SDKConf_Signature, "CSpitterProjectile_Detonate"))
            g_hSpitterDetonate = EndPrepSDKCall();
            
        CloseHandle(conf);
    }

    g_cvEnable = CreateConVar("bodytrap_enable", "1", "Bật/tắt plugin");
    g_cvRange = CreateConVar("bodytrap_range", "150.0", "Khoảng cách gắn bẫy");
    g_cvCountdown = CreateConVar("bodytrap_countdown", "5", "Thời gian đếm ngược (giây)");
    
    g_cvPipeDamage = CreateConVar("bodytrap_pipe_damage", "500.0", "Sát thương nổ của pipebomb");
    g_cvPipeRadius = CreateConVar("bodytrap_pipe_radius", "400.0", "Bán kính nổ của pipebomb");
    g_cvPipeStaggerDuration = CreateConVar("bodytrap_pipe_stagger_duration", "2.0", "Thời gian chao đảo (giây)");
    
    g_cvMolotovBodyDamage = CreateConVar("bodytrap_molotov_body_damage", "10.0", "Sát thương thiêu đốt người bị gắn trap (mỗi 0.5s)");
    g_cvMolotovTrailDamage = CreateConVar("bodytrap_molotov_trail_damage", "5.0", "Sát thương của vệt lửa dưới đất (DPS)");
    g_cvMolotovDuration = CreateConVar("bodytrap_molotov_duration", "15.0", "Thời gian tồn tại của 3 thùng xăng trung tâm (giây)");
    g_cvMolotovIgniteTime = CreateConVar("bodytrap_molotov_ignite_time", "10.0", "Thời gian ngọn lửa bám chặt trên cơ thể (giây)");
    g_cvMolotovTrailDuration = CreateConVar("bodytrap_molotov_trail_duration", "5.0", "Thời gian vệt lửa tồn tại trên mặt đất (giây)");
    
    g_cvVomitDamage = CreateConVar("bodytrap_vomit_damage", "0.0", "Sát thương mỗi tick của acid");
    g_cvVomitDuration = CreateConVar("bodytrap_vomit_duration", "15.0", "Thời gian tồn tại bãi Acid (giây)");
    g_cvVomitRadius = CreateConVar("bodytrap_vomit_radius", "250.0", "Bán kính mù của Vomit");
    g_cvVomitAcidScale = CreateConVar("bodytrap_vomit_acid_scale", "1.0", "Khuếch đại vũng acid");
    
    g_cvBeamRadius = CreateConVar("bodytrap_beam_radius", "50.0", "Bán kính vòng beam");
    g_cvBeamWidth = CreateConVar("bodytrap_beam_width", "10.0", "Độ dày vòng beam");
    g_cvColorPipe = CreateConVar("bodytrap_color_pipe", "255 0 0 255", "Màu vòng beam Pipebomb");
    g_cvColorMolotov = CreateConVar("bodytrap_color_molotov", "255 128 0 255", "Màu vòng beam Molotov");
    g_cvColorVomit = CreateConVar("bodytrap_color_vomit", "0 255 0 255", "Màu vòng beam Vomitjar");
    
    AutoExecConfig(true, "l4d2_bodytrap");
    
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
        char sCaption[64], sColor[32];
        Format(sCaption, sizeof(sCaption), "BOM NỔ SAU %d GIÂY!", timeleft);

        if (type == TYPE_PIPE) strcopy(sColor, sizeof(sColor), "255 0 0");
        else if (type == TYPE_MOLOTOV) strcopy(sColor, sizeof(sColor), "255 128 0");
        else strcopy(sColor, sizeof(sColor), "0 255 0");

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
        
        SetVariantString("!activator");
        AcceptEntityInput(hint, "SetParent", target);
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

// ==== THAY THẾ L4D_StaggerPlayer: Hệ thống Knockback vật lý ==== //
void ApplyKnockback(int client, float pos[3])
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client)) return;
    
    float vClient[3], vDir[3];
    GetClientAbsOrigin(client, vClient);
    SubtractVectors(vClient, pos, vDir);
    
    // Nếu đứng trùng tâm nổ, tạo hướng đẩy ngẫu nhiên
    if (GetVectorLength(vDir) < 1.0)
    {
        vDir[0] = GetRandomFloat(-1.0, 1.0);
        vDir[1] = GetRandomFloat(-1.0, 1.0);
    }
    
    vDir[2] = 0.0;
    NormalizeVector(vDir, vDir);
    ScaleVector(vDir, 250.0); // Lực đẩy văng ra xa
    vDir[2] = 150.0;          // Lực hất lên không trung
    
    // Set MoveType thành Walk để nạn nhân bị hất văng (bypass anti-bhop)
    SetEntityMoveType(client, MOVETYPE_WALK);
    TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vDir);
}

void ApplyChainStagger(int victim, int owner, float pos[3], float duration)
{
    // Gọi hàm Knockback vật lý thay thế Stagger
    ApplyKnockback(victim, pos);
    
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
        float pPos[3]; pPos = pos; pPos[2] +