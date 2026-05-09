// <L4D2 Super Hunter Master> 
// Phiên bản 9.0: Fix triệt để VScript & Lỗi Spit lơ lửng (Floating Bug)

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "9.0.0"

// ==========================================
// 22 ABILITIES BITMASK
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

enum struct CustomClassDef 
{
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
int g_iPlayerCustomClass[MAXPLAYERS + 1] = {-1, ...};
int g_iPlayerAbilities[MAXPLAYERS + 1] = {0, ...};
int g_iPouncePushEnt[MAXPLAYERS + 1] = {-1, ...};
int g_iPounceVictim[MAXPLAYERS + 1] = {0, ...};

// Biến cho hiệu ứng nâng cao (Chống Crash)
int g_iShieldEnt[MAXPLAYERS + 1] = {-1, ...};
int g_iMeteorActive[MAXPLAYERS + 1] = {0, ...};

// ConVars
ConVar g_cvEnable;
ConVar g_cvSmasherMult;
ConVar g_cvShieldMult;
ConVar g_cvJumperDmg;
ConVar g_cvWitchShockDmg;
ConVar g_cvWarpDmg;
ConVar g_cvFreezeTime;
ConVar g_cvHealAmount;

public Plugin myinfo = 
{
    name = "L4D2 Super Hunter Master",
    author = "Tyn Zũ (Adapted)",
    description = "Hunter với 22 kỹ năng hoàn chỉnh (Fix VScript Spit/Fire)",
    version = PLUGIN_VERSION,
};

public void OnPluginStart() 
{
    g_CustomClasses = new ArrayList(sizeof(CustomClassDef));
    
    g_cvEnable        = CreateConVar("sh_enable", "1", "Bật/Tắt plugin Super Hunter");
    g_cvSmasherMult   = CreateConVar("sh_smasher_mult", "1.8", "Sát thương nhân lên của Smasher");
    g_cvShieldMult    = CreateConVar("sh_shield_mult", "0.5", "Sát thương nhận vào của Shield");
    g_cvJumperDmg     = CreateConVar("sh_jumper_dmg", "20.0", "Sát thương dậm đất của Jumper");
    g_cvWitchShockDmg = CreateConVar("sh_witch_shock_dmg", "15.0", "Sát thương giật điện xung quanh của Witch");
    g_cvWarpDmg       = CreateConVar("sh_warp_dmg", "10.0", "Sát thương nổ khi dịch chuyển của Warp");
    g_cvFreezeTime    = CreateConVar("sh_freeze_time", "6.0", "Thời gian bị đóng băng");
    g_cvHealAmount    = CreateConVar("sh_heal_amount", "5.0", "Lượng máu hồi mỗi giây của Heal Hunter");
    
    AutoExecConfig(true, "L4D2_Super_Hunter");

    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_disconnect", Event_PlayerDisconnect);
    HookEvent("lunge_pounce", Event_LungePounce);
    HookEvent("pounce_end", Event_PounceEnd);
    HookEvent("pounce_stopped", Event_PounceStopped); 
    
    RegAdminCmd("sm_reloadhunter", Cmd_ReloadCfg, ADMFLAG_ROOT, "Reload Super Hunter CFG");
    
    LoadCustomClassesConfig();
    
    for (int i = 1; i <= MaxClients; i++) 
    {
        if (IsClientInGame(i)) 
        {
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
        }
    }
}

public void OnMapStart() 
{
    PrecacheModel("models/props_junk/propanecanister001a.mdl", true);
    PrecacheModel("models/props_unique/airport/atlas_break_ball.mdl", true);
    PrecacheModel("models/props_debris/concrete_chunk01a.mdl", true);
    
    PrecacheSound("ambient/energy/zap1.wav", true); 
    PrecacheSound("npc/witch/voice/idle/witch_cry_01.wav", true);
    PrecacheSound("ambient/explosions/explode_3.wav", true);
    PrecacheSound("ambient/machines/teleport_1.wav", true);
    PrecacheSound("weapons/grenade_launcher/grenadefire/grenade_launcher_fire_1.wav", true);
}

public void OnClientPutInServer(int client) 
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

// ==========================================
// ĐỌC CONFIG
// ==========================================
void LoadCustomClassesConfig() 
{
    g_CustomClasses.Clear();
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "data/super_hunter_classes.cfg");
    
    if (!FileExists(path)) return;
    
    KeyValues kv = new KeyValues("Classes");
    if (!kv.ImportFromFile(path) || !kv.GotoFirstSubKey()) 
    {
        delete kv; return; 
    }
    
    do 
    {
        CustomClassDef def;
        kv.GetSectionName(def.name, sizeof(def.name));
        
        char abilitiesStr[256];
        kv.GetString("abilities", abilitiesStr, sizeof(abilitiesStr));
        
        int mask = 0;
        if (StrContains(abilitiesStr, "Ghost", false) != -1) mask |= ABILITY_GHOST;
        if (StrContains(abilitiesStr, "Lava", false) != -1) mask |= ABILITY_LAVA;
        if (StrContains(abilitiesStr, "Gravity", false) != -1) mask |= ABILITY_GRAVITY;
        if (StrContains(abilitiesStr, "Quake", false) != -1) mask |= ABILITY_QUAKE;
        if (StrContains(abilitiesStr, "Leaper", false) != -1) mask |= ABILITY_LEAPER;
        if (StrContains(abilitiesStr, "Dread", false) != -1) mask |= ABILITY_DREAD;
        if (StrContains(abilitiesStr, "Freeze", false) != -1) mask |= ABILITY_FREEZE;
        if (StrContains(abilitiesStr, "Lazy", false) != -1) mask |= ABILITY_LAZY;
        if (StrContains(abilitiesStr, "Rabies", false) != -1) mask |= ABILITY_RABIES;
        if (StrContains(abilitiesStr, "Bombard", false) != -1) mask |= ABILITY_BOMBARD;
        if (StrContains(abilitiesStr, "Spitter", false) != -1) mask |= ABILITY_SPITTER;
        if (StrContains(abilitiesStr, "Warp", false) != -1) mask |= ABILITY_WARP;
        if (StrContains(abilitiesStr, "Fire", false) != -1) mask |= ABILITY_FIRE;
        if (StrContains(abilitiesStr, "Cobalt", false) != -1) mask |= ABILITY_COBALT;
        if (StrContains(abilitiesStr, "Meteor", false) != -1) mask |= ABILITY_METEOR;
        if (StrContains(abilitiesStr, "Ice", false) != -1) mask |= ABILITY_ICE;
        if (StrContains(abilitiesStr, "Shield", false) != -1) mask |= ABILITY_SHIELD;
        if (StrContains(abilitiesStr, "Shock", false) != -1) mask |= ABILITY_SHOCK;
        if (StrContains(abilitiesStr, "Witch", false) != -1) mask |= ABILITY_WITCH;
        if (StrContains(abilitiesStr, "Heal", false) != -1) mask |= ABILITY_HEAL;
        if (StrContains(abilitiesStr, "Smasher", false) != -1) mask |= ABILITY_SMASHER;
        if (StrContains(abilitiesStr, "Jumper", false) != -1) mask |= ABILITY_JUMPER;
        
        def.abilities = mask;
        def.glow[0] = kv.GetNum("glow_r", 255); 
        def.glow[1] = kv.GetNum("glow_g", 255); 
        def.glow[2] = kv.GetNum("glow_b", 255);
        def.speed   = kv.GetFloat("speed", 1.0); 
        def.damage  = kv.GetFloat("damage", 1.0);
        def.health  = kv.GetFloat("health", 1.0); 
        def.gravity = kv.GetFloat("gravity", 1.0);
        def.chance  = kv.GetFloat("chance", 1.0);
        
        g_CustomClasses.PushArray(def);
        
    } while (kv.GotoNextKey());
    delete kv;
}

public Action Cmd_ReloadCfg(int client, int args) 
{
    LoadCustomClassesConfig(); 
    ReplyToCommand(client, "[Super Hunter] Đã tải lại toàn bộ CFG!");
    return Plugin_Handled; 
}

// ==========================================
// SPAWN VÀ ÁP DỤNG CHỈ SỐ
// ==========================================
public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) 
{
    if (!g_cvEnable.BoolValue) return;
    int client = GetClientOfUserId(event.GetInt("userid"));
    CreateTimer(0.1, Timer_AssignClassDelay, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_AssignClassDelay(Handle timer, int userid) 
{
    int client = GetClientOfUserId(userid);
    
    if (!IsValidHunter(client) || g_CustomClasses.Length == 0) return Plugin_Stop;
    CleanupHunter(client);
    
    float totalChance = 0.0;
    for (int i = 0; i < g_CustomClasses.Length; i++) 
    {
        CustomClassDef def; g_CustomClasses.GetArray(i, def); 
        totalChance += def.chance;
    }
    
    float randomVal = GetRandomFloat(0.0, totalChance);
    float currentChance = 0.0;
    int selectedClass = -1;
    
    for (int i = 0; i < g_CustomClasses.Length; i++) 
    {
        CustomClassDef def; g_CustomClasses.GetArray(i, def); 
        currentChance += def.chance;
        if (randomVal <= currentChance) 
        { 
            selectedClass = i; break; 
        }
    }
    
    if (selectedClass != -1) 
    {
        CustomClassDef def; g_CustomClasses.GetArray(selectedClass, def);
        g_iPlayerCustomClass[client] = selectedClass; 
        g_iPlayerAbilities[client] = def.abilities;
        
        int baseHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
        int newHealth = RoundToNearest(baseHealth * def.health);
        SetEntProp(client, Prop_Data, "m_iMaxHealth", newHealth); 
        SetEntProp(client, Prop_Send, "m_iHealth", newHealth);
        SetEntityGravity(client, def.gravity); 
        SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", def.speed);
        
        SetEntProp(client, Prop_Send, "m_bClientSideAnimation", 1); 
        SetEntProp(client, Prop_Send, "m_iGlowType", 3);
        SetEntProp(client, Prop_Send, "m_nGlowRange", 9999); 
        
        int glowColor = def.glow[0] + (def.glow[1] * 256) + (def.glow[2] * 65536);
        SetEntProp(client, Prop_Send, "m_glowColorOverride", glowColor);
        
        if (def.abilities & ABILITY_GHOST)  Ability_Ghost_OnSpawn(client);
        if (def.abilities & ABILITY_FIRE)   Ability_Fire_OnSpawn(client);
        if (def.abilities & ABILITY_ICE)    Ability_Ice_OnSpawn(client);
        if (def.abilities & ABILITY_SHIELD) ActivateShield(client);
        if (def.abilities & ABILITY_JUMPER) PrintToChatAll("\x04[!] \x01Jumper Hunter chuẩn bị nhảy!");
        
        PrintToChatAll("\x04[CẢNH BÁO]\x01 Hunter biến dị: \x03%s\x01 vừa xuất hiện!", def.name);
    }
    return Plugin_Stop;
}

// ==========================================
// KHI HUNTER BẮT ĐẦU VỒ
// ==========================================
public void Event_LungePounce(Event event, const char[] name, bool dontBroadcast) 
{
    if (!g_cvEnable.BoolValue) return;
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidHunter(client)) return;
    
    int abs = g_iPlayerAbilities[client];
    if (abs & ABILITY_QUAKE)   Ability_Quake_OnLunge(client);
    if (abs & ABILITY_BOMBARD) Ability_Bombard_OnLunge(client);
    if (abs & ABILITY_METEOR)  Ability_Meteor_OnLunge(client);
    if (abs & ABILITY_WARP)    Ability_Warp_OnLunge(client);
    if (abs & ABILITY_LEAPER)  EmitSoundToAll("weapons/grenade_launcher/grenadefire/grenade_launcher_fire_1.wav", client);
}

// ==========================================
// KHI KẾT THÚC CÚ VỒ (Đáp đất hoặc Vồ Trúng)
// ==========================================
public void Event_PounceEnd(Event event, const char[] name, bool dontBroadcast) 
{
    if (!g_cvEnable.BoolValue) return;
    
    int client = GetClientOfUserId(event.GetInt("userid"));
    int victim = GetClientOfUserId(event.GetInt("victim"));
    
    if (client <= 0 || client > MaxClients) return;
    
    int abs = g_iPlayerAbilities[client];
    if (abs & ABILITY_QUAKE)   Ability_Quake_OnPounceEnd(client);
    if (abs & ABILITY_LAVA)    Ability_Lava_OnPounceEnd(client);
    if (abs & ABILITY_SPITTER) Ability_Spitter_OnPounceEnd(client);
    if (abs & ABILITY_SHOCK)   Ability_Shock_OnPounceEnd(client);
    if (abs & ABILITY_JUMPER)  Ability_Jumper_OnPounceEnd(client);
    
    if (victim > 0 && IsValidSurvivor(victim)) 
    {
        g_iPounceVictim[client] = victim;
        
        DataPack pack;
        CreateDataTimer(1.0, Timer_ProcessPounceAbilities, pack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        pack.WriteCell(GetClientUserId(client));
        pack.WriteCell(GetClientUserId(victim));
        
        if (abs & ABILITY_FIRE)   Ability_Fire_OnVictim(client, victim);
        if (abs & ABILITY_ICE)    Ability_Ice_OnVictim(client, victim);
        if (abs & ABILITY_FREEZE) Ability_Freeze_OnVictim(client, victim);
        if (abs & ABILITY_DREAD)  ScreenShake(victim, 50.0);
        if (abs & ABILITY_LAZY)   SetEntPropFloat(victim, Prop_Send, "m_flStamina", 100.0); 
        if (abs & ABILITY_WITCH)  Ability_Witch_OnVictim(client, victim);
    }
}

// ==========================================
// GỠ KẸT CỨNG (STUCK) KHI ĐƯỢC CỨU
// ==========================================
public void Event_PounceStopped(Event event, const char[] name, bool dontBroadcast) 
{
    int victim = GetClientOfUserId(event.GetInt("victim"));
    if (victim > 0 && IsClientInGame(victim)) 
    {
        SetEntityMoveType(victim, MOVETYPE_WALK);
        SetEntityRenderColor(victim, 255, 255, 255, 255);
        SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
    }
}

// ==========================================
// XỬ LÝ SÁT THƯƠNG
// ==========================================
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) 
{
    if (!g_cvEnable.BoolValue) return Plugin_Continue;
    
    if (IsValidHunter(victim)) 
    {
        if (g_iPlayerAbilities[victim] & ABILITY_SHIELD) damage *= g_cvShieldMult.FloatValue;
    }
    
    if (IsValidSurvivor(victim) && attacker > 0 && attacker <= MaxClients && IsValidHunter(attacker)) 
    {
        int abs = g_iPlayerAbilities[attacker];
        if (abs & ABILITY_SMASHER) damage *= g_cvSmasherMult.FloatValue;
        if (abs & ABILITY_COBALT)  damagetype |= DMG_BLAST;
    }
    return Plugin_Continue;
}

// ==========================================
// DỌN DẸP
// ==========================================
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) { CleanupHunter(GetClientOfUserId(event.GetInt("userid"))); }
public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) { CleanupHunter(GetClientOfUserId(event.GetInt("userid"))); }

void CleanupHunter(int client) 
{
    if (client > 0 && client <= MaxClients) 
    {
        Ability_Quake_OnPounceEnd(client);
        RemoveShield(client);
        g_iMeteorActive[client] = 0;
        g_iPlayerCustomClass[client] = -1;
        g_iPlayerAbilities[client] = 0;
        
        if (g_iPounceVictim[client] > 0 && IsClientInGame(g_iPounceVictim[client])) 
        {
            SetEntityMoveType(g_iPounceVictim[client], MOVETYPE_WALK);
            SetEntityRenderColor(g_iPounceVictim[client], 255, 255, 255, 255);
            SetEntPropFloat(g_iPounceVictim[client], Prop_Send, "m_flLaggedMovementValue", 1.0);
        }
        g_iPounceVictim[client] = 0;
    }
}

// ======================================================================
// HÀM CHẠY VSCRIPT (CHỐNG LỖI ĐỎ CONSOLE & FIX FLOATING BUG)
// ======================================================================
stock void ExecuteVScript(const char[] code) 
{
    int ent = CreateEntityByName("logic_script");
    if (ent != -1) 
    {
        DispatchSpawn(ent);
        SetVariantString(code);
        AcceptEntityInput(ent, "RunScriptCode");
        AcceptEntityInput(ent, "Kill");
    }
}

// ======================================================================
// CÁC HÀM LOGIC KỸ NĂNG ĐỘC LẬP
// ======================================================================

public Action Timer_ProcessPounceAbilities(Handle timer, DataPack pack) 
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    int victim = GetClientOfUserId(pack.ReadCell());
    
    if (!IsValidHunter(client) || !IsValidSurvivor(victim) || GetEntPropEnt(victim, Prop_Send, "m_pounceAttacker") != client) 
    {
        if (client > 0) g_iPounceVictim[client] = 0;
        return Plugin_Stop;
    }
    
    int abs = g_iPlayerAbilities[client];
    if (abs & ABILITY_HEAL) 
    {
        int hp = GetClientHealth(client); 
        int heal = g_cvHealAmount.IntValue;
        SetEntityHealth(client, (hp + heal <= 6000) ? hp + heal : hp);
    }
    if (abs & ABILITY_RABIES) 
    {
        int hp = GetClientHealth(victim);
        if (hp > 2) SetEntityHealth(victim, hp - 2);
    }
    return Plugin_Continue;
}

void Ability_Ghost_OnSpawn(int client) 
{
    SetEntityRenderMode(client, RENDER_TRANSCOLOR); 
    SetEntityRenderColor(client, 255, 255, 255, 30);
}

// -------------------------------------------------------------------
// SỬ DỤNG LỆNH VSCRIPT GỐC: SpawnEntityFromTable
// Nâng Z + 40.0, thêm velocity hướng xuống đáy -500 để nổ tung tạo vũng
// -------------------------------------------------------------------
void Ability_Spitter_OnPounceEnd(int client) 
{
    float pos[3]; 
    GetClientAbsOrigin(client, pos);
    
    char code[256];
    Format(code, sizeof(code), "SpawnEntityFromTable(\"spitter_projectile\", { origin = Vector(%f, %f, %f), velocity = Vector(0, 0, -500) });", pos[0], pos[1], pos[2] + 40.0);
    ExecuteVScript(code); 
}

void Ability_Lava_OnPounceEnd(int client) 
{
    float pos[3]; 
    GetClientAbsOrigin(client, pos);
    
    char code[256];
    Format(code, sizeof(code), "SpawnEntityFromTable(\"inferno\", { origin = Vector(%f, %f, %f) });", pos[0], pos[1], pos[2] + 5.0);
    ExecuteVScript(code); 
}

void Ability_Fire_OnSpawn(int client) 
{ 
    IgniteEntity(client, 999.0); 
}

void Ability_Fire_OnVictim(int client, int victim) 
{
    #pragma unused client
    IgniteEntity(victim, 8.0);
    
    float pos[3]; 
    GetClientAbsOrigin(victim, pos);
    
    char code[256];
    Format(code, sizeof(code), "SpawnEntityFromTable(\"inferno\", { origin = Vector(%f, %f, %f) });", pos[0], pos[1], pos[2] + 5.0);
    ExecuteVScript(code); 
}

void Ability_Quake_OnLunge(int client) 
{
    Ability_Quake_OnPounceEnd(client); 
    
    for (int i = 1; i <= MaxClients; i++) 
    {
        if (i != client && IsClientInGame(i) && GetClientTeam(i) == 2) 
        {
            ScreenShake(i, 30.0); 
            EmitSoundToClient(i, "ambient/explosions/explode_3.wav");
        }
    }
    
    int pushEnt = CreateEntityByName("point_push");
    if (pushEnt != -1) 
    {
        DispatchKeyValue(pushEnt, "spawnflags", "24"); 
        DispatchSpawn(pushEnt); 
        ActivateEntity(pushEnt);
        
        g_iPouncePushEnt[client] = EntIndexToEntRef(pushEnt); 
        
        DataPack pack;
        CreateDataTimer(0.1, Timer_QuakeUpdate, pack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        pack.WriteCell(GetClientUserId(client)); 
        pack.WriteCell(g_iPouncePushEnt[client]);
    }
}

public Action Timer_QuakeUpdate(Handle timer, DataPack pack) 
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    int ent = EntRefToEntIndex(pack.ReadCell());
    
    if (!IsValidHunter(client) || ent <= 0 || !IsValidEntity(ent)) 
    {
        if (ent > 0 && IsValidEntity(ent)) AcceptEntityInput(ent, "Kill");
        return Plugin_Stop;
    }
    
    float pos[3]; GetClientAbsOrigin(client, pos);
    DispatchKeyValueFloat(ent, "magnitude", 450.0); 
    DispatchKeyValueFloat(ent, "radius", 300.0);
    TeleportEntity(ent, pos, NULL_VECTOR, NULL_VECTOR); 
    AcceptEntityInput(ent, "Enable");
    return Plugin_Continue;
}

void Ability_Quake_OnPounceEnd(int client) 
{
    int ent = EntRefToEntIndex(g_iPouncePushEnt[client]);
    if (ent > 0 && IsValidEntity(ent)) 
    {
        AcceptEntityInput(ent, "Disable"); 
        AcceptEntityInput(ent, "Kill");
    }
    g_iPouncePushEnt[client] = -1;
}

void Ability_Freeze_OnVictim(int client, int victim) 
{
    #pragma unused client
    SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 0.3);
    CreateTimer(g_cvFreezeTime.FloatValue, Timer_RestoreSpeed, GetClientUserId(victim), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RestoreSpeed(Handle timer, int userid) 
{
    int victim = GetClientOfUserId(userid);
    if (IsValidSurvivor(victim)) SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
    return Plugin_Stop;
}

void Ability_Bombard_OnLunge(int client) 
{
    int ent = CreateEntityByName("env_explosion");
    if (ent != -1) 
    {
        float pos[3]; GetClientAbsOrigin(client, pos);
        DispatchSpawn(ent); 
        TeleportEntity(ent, pos, NULL_VECTOR, NULL_VECTOR); 
        AcceptEntityInput(ent, "Explode");
    }
}

void Ability_Warp_OnLunge(int client) 
{
    float pos[3], ang[3], vec[3];
    GetClientAbsOrigin(client, pos); 
    GetClientEyeAngles(client, ang); 
    GetAngleVectors(ang, vec, NULL_VECTOR, NULL_VECTOR);
    int warpDmg = g_cvWarpDmg.IntValue;
    
    for (int i = 1; i <= MaxClients; i++) 
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) 
        {
            float tPos[3]; GetClientAbsOrigin(i, tPos);
            if (GetVectorDistance(pos, tPos) <= 150.0) 
            {
                DealDamagePlayer(i, client, DMG_ENERGYBEAM, warpDmg);
            }
        }
    }
    
    pos[0] += vec[0] * 300.0; pos[1] += vec[1] * 300.0; pos[2] += 50.0;
    TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR); 
    EmitSoundToAll("ambient/machines/teleport_1.wav", client);
}

void Ability_Meteor_OnLunge(int client) { StartMeteorFall(client); }

void Ability_Ice_OnSpawn(int client) { SetEntityRenderColor(client, 0, 100, 255, 255); }

void Ability_Ice_OnVictim(int client, int victim) 
{
    #pragma unused client
    SetEntityRenderColor(victim, 0, 100, 255, 255);
    SetEntityMoveType(victim, MOVETYPE_NONE); 
    PrintToChat(victim, "\x04[!] \x01Bạn đã bị đóng băng!");
    CreateTimer(g_cvFreezeTime.FloatValue, Timer_IceDefrost, GetClientUserId(victim), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_IceDefrost(Handle timer, int userid) 
{
    int victim = GetClientOfUserId(userid);
    if (IsValidSurvivor(victim)) 
    {
        SetEntityMoveType(victim, MOVETYPE_WALK); 
        SetEntityRenderColor(victim, 255, 255, 255, 255);
    }
    return Plugin_Stop;
}

void Ability_Shock_OnPounceEnd(int client) 
{
    float pos[3]; GetClientAbsOrigin(client, pos);
    int tesla = CreateEntityByName("env_spark");
    if (tesla != -1) 
    {
        DispatchKeyValue(tesla, "MaxDelay", "0"); 
        DispatchSpawn(tesla);
        TeleportEntity(tesla, pos, NULL_VECTOR, NULL_VECTOR);
        AcceptEntityInput(tesla, "SparkOnce"); 
        AcceptEntityInput(tesla, "Kill");
        EmitSoundToAll("ambient/energy/zap1.wav", client);
    }
}

void Ability_Witch_OnVictim(int client, int victim) 
{
    EmitSoundToAll("npc/witch/voice/idle/witch_cry_01.wav", client);
    
    float pos[3]; GetClientAbsOrigin(victim, pos);
    int spark = CreateEntityByName("env_spark");
    if (spark != -1) 
    {
        DispatchKeyValue(spark, "MaxDelay", "0"); 
        DispatchKeyValue(spark, "Magnitude", "2"); 
        DispatchKeyValue(spark, "TrailLength", "2");
        DispatchSpawn(spark); 
        TeleportEntity(spark, pos, NULL_VECTOR, NULL_VECTOR);
        AcceptEntityInput(spark, "SparkOnce"); 
        AcceptEntityInput(spark, "Kill");
        EmitSoundToAll("ambient/energy/zap1.wav", client);
    }
    
    int shockDmg = g_cvWitchShockDmg.IntValue;
    for (int i = 1; i <= MaxClients; i++) 
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2 && i != victim) 
        {
            float tPos[3]; GetClientAbsOrigin(i, tPos);
            if (GetVectorDistance(pos, tPos) <= 250.0) DealDamagePlayer(i, client, DMG_SHOCK, shockDmg);
        }
    }
}

void Ability_Jumper_OnPounceEnd(int client) 
{
    float pos[3]; GetClientAbsOrigin(client, pos); int jumpDmg = g_cvJumperDmg.IntValue;
    for (int i = 1; i <= MaxClients; i++) 
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) 
        {
            float tPos[3]; GetClientAbsOrigin(i, tPos);
            if (GetVectorDistance(pos, tPos) <= 200.0) 
            {
                DealDamagePlayer(i, client, DMG_CRUSH, jumpDmg); 
                ScreenShake(i, 20.0);
            }
        }
    }
}

// ==========================================
// UTILITIES VÀ STOCKS
// ==========================================
bool IsValidHunter(int client) 
{
    if (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == 3)
    {
        return (GetEntProp(client, Prop_Send, "m_zombieClass") == 3);
    }
    return false;
}

bool IsValidSurvivor(int client) 
{ 
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == 2); 
}

stock void DealDamagePlayer(int target, int attacker, int dmgtype, int dmg) 
{
    if (target > 0 && target <= MaxClients && IsClientInGame(target) && IsPlayerAlive(target)) 
    {
        char damage[16]; IntToString(dmg, damage, 16); char type[16]; IntToString(dmgtype, type, 16);
        int pointHurt = CreateEntityByName("point_hurt");
        if (pointHurt) 
        {
            DispatchKeyValue(target, "targetname", "hurtme"); 
            DispatchKeyValue(pointHurt, "Damage", damage);
            DispatchKeyValue(pointHurt, "DamageTarget", "hurtme"); 
            DispatchKeyValue(pointHurt, "DamageType", type);
            DispatchSpawn(pointHurt); 
            AcceptEntityInput(pointHurt, "Hurt", attacker);
            AcceptEntityInput(pointHurt, "Kill"); 
            DispatchKeyValue(target, "targetname", "donthurtme");
        }
    }
}

stock void ScreenShake(int client, float intensity) 
{
    Handle msg = StartMessageOne("Shake", client);
    if (msg != null) 
    { 
        BfWriteByte(msg, 0); BfWriteFloat(msg, intensity); 
        BfWriteFloat(msg, 10.0); BfWriteFloat(msg, 3.0); EndMessage(); 
    }
}

stock void ActivateShield(int client) 
{
    if (g_iShieldEnt[client] == -1) 
    {
        float Origin[3]; GetClientAbsOrigin(client, Origin); Origin[2] -= 20.0; 
        int entity = CreateEntityByName("prop_dynamic");
        if (IsValidEntity(entity)) 
        {
            char tName[64]; Format(tName, sizeof(tName), "HunterShield%d", client);
            DispatchKeyValue(client, "targetname", tName); DispatchKeyValue(entity, "targetname", "Player");
            DispatchKeyValue(entity, "parentname", tName); DispatchKeyValue(entity, "model", "models/props_unique/airport/atlas_break_ball.mdl");
            DispatchKeyValueVector(entity, "origin", Origin); DispatchSpawn(entity); SetVariantString(tName);
            AcceptEntityInput(entity, "SetParent", entity, entity); AcceptEntityInput(entity, "DisableShadow"); 
            SetEntityRenderMode(entity, view_as<RenderMode>(3)); SetEntityRenderColor(entity, 25, 125, 125, 100); 
            SetEntData(entity, GetEntSendPropOffs(entity, "m_CollisionGroup"), 1, 1, true);
            SetEntProp(entity, Prop_Send, "m_hOwnerEntity", client);
            g_iShieldEnt[client] = EntIndexToEntRef(entity);
        }
    }
}

stock void RemoveShield(int client) 
{
    int ent = EntRefToEntIndex(g_iShieldEnt[client]);
    if (ent > 0 && IsValidEntity(ent)) AcceptEntityInput(ent, "Kill");
    g_iShieldEnt[client] = -1;
}

stock void StartMeteorFall(int client) 
{
    if (g_iMeteorActive[client]) return; 
    g_iMeteorActive[client] = 1;
    float vPos[3]; GetClientEyePosition(client, vPos);    
    DataPack hPack; CreateDataTimer(0.6, UpdateMeteorFall, hPack, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
    hPack.WriteCell(GetClientUserId(client)); hPack.WriteFloat(vPos[0]); hPack.WriteFloat(vPos[1]); hPack.WriteFloat(vPos[2]); hPack.WriteFloat(GetEngineTime());
}

public Action UpdateMeteorFall(Handle hTimer, DataPack hPack) 
{
    hPack.Reset();
    int userid = hPack.ReadCell(); int client = GetClientOfUserId(userid);
    float vPos[3]; vPos[0] = hPack.ReadFloat(); vPos[1] = hPack.ReadFloat(); vPos[2] = hPack.ReadFloat();
    float fTime = hPack.ReadFloat();
    
    if (client <= 0 || !IsClientInGame(client) || !IsValidHunter(client) || (GetEngineTime() - fTime) > 5.0) 
    {
        if (client > 0) g_iMeteorActive[client] = 0;
        int entity = -1;
        while ((entity = FindEntityByClassname(entity, "tank_rock")) != INVALID_ENT_REFERENCE) 
        {
            if (GetEntProp(entity, Prop_Send, "m_hOwnerEntity") == client) ExplodeMeteor(entity);
        }
        return Plugin_Stop;
    }
    
    float angle[3], velocity[3], hitpos[3];
    angle[0] = 0.0 + GetRandomFloat(-20.0, 20.0); angle[1] = 0.0 + GetRandomFloat(-20.0, 20.0); angle[2] = 60.0;
    GetVectorAngles(angle, angle);
    
    Handle trace = TR_TraceRayFilterEx(vPos, angle, MASK_SOLID, RayType_Infinite, TraceRayDontHitSelf, client);
    if (TR_DidHit(trace)) TR_GetEndPosition(hitpos, trace);
    CloseHandle(trace);
    
    float dis = GetVectorDistance(vPos, hitpos);
    if (dis > 2000.0) dis = 1600.0;
    
    float T[3]; MakeVectorFromPoints(vPos, hitpos, T); NormalizeVector(T, T); ScaleVector(T, dis - 40.0); AddVectors(vPos, T, hitpos);
    
    if (dis > 100.0) 
    {
        int ent = CreateEntityByName("tank_rock");
        if (ent > 0) 
        {
            DispatchKeyValue(ent, "model", "models/props_debris/concrete_chunk01a.mdl"); DispatchSpawn(ent);  
            float angle2[3]; angle2[0] = GetRandomFloat(-180.0, 180.0); angle2[1] = GetRandomFloat(-180.0, 180.0); angle2[2] = GetRandomFloat(-180.0, 180.0);
            velocity[0] = GetRandomFloat(0.0, 350.0); velocity[1] = GetRandomFloat(0.0, 350.0); velocity[2] = GetRandomFloat(0.0, 30.0);
            TeleportEntity(ent, hitpos, angle2, velocity); ActivateEntity(ent); AcceptEntityInput(ent, "Ignite");
            SetEntProp(ent, Prop_Send, "m_hOwnerEntity", client);
        }
    } 
    return Plugin_Continue;    
}

stock void ExplodeMeteor(int entity) 
{
    if (IsValidEntity(entity)) 
    {
        float pos[3]; GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
        int explosion = CreateEntityByName("env_explosion");
        if (explosion != -1) 
        {
            DispatchKeyValue(explosion, "iMagnitude", "100"); DispatchKeyValue(explosion, "iRadiusOverride", "200");
            DispatchSpawn(explosion); TeleportEntity(explosion, pos, NULL_VECTOR, NULL_VECTOR); AcceptEntityInput(explosion, "Explode");
        }
        AcceptEntityInput(entity, "Kill");
    }
}

public bool TraceRayDontHitSelf(int entity, int mask, any data) { return (entity != data); }