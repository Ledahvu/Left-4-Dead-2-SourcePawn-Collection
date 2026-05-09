// <[L4D2] Medic & Firebug (Weapon Categories Setup)> - <Thay thế đạn bằng particles hồi máu/sát thương>
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

#define PLUGIN_VERSION "11.0"

#define CLASS_NONE 0
#define CLASS_MEDIC 1
#define CLASS_FIREBUG 2

// Nhóm vũ khí
#define WPN_UNKNOWN 0
#define WPN_SMG 1
#define WPN_RIFLE 2
#define WPN_SHOTGUN 3
#define WPN_SNIPER 4

int g_iPlayerClass[MAXPLAYERS + 1];
float g_flNextAttack[MAXPLAYERS + 1];

#define PARTICLE_MEDIC "extinguisher_spray"
#define PARTICLE_FIREBUG "fire_jet_01_flame"

// --- CVARs Dùng chung ---
ConVar g_cvTickRate;
ConVar g_cvMaxDistance; 
ConVar g_cvMaxAngle;    

// --- CVARs MEDIC HỒI MÁU ---
ConVar g_cvMedicHeal_SMG;
ConVar g_cvMedicHeal_Rifle;
ConVar g_cvMedicHeal_Shotgun;
ConVar g_cvMedicHeal_Sniper;

// --- CVARs MEDIC SÁT THƯƠNG ---
ConVar g_cvMedicDmg_SMG;
ConVar g_cvMedicDmg_Rifle;
ConVar g_cvMedicDmg_Shotgun;
ConVar g_cvMedicDmg_Sniper;

// --- CVARs FIREBUG SÁT THƯƠNG ---
ConVar g_cvFirebugDmg_SMG;
ConVar g_cvFirebugDmg_Rifle;
ConVar g_cvFirebugDmg_Shotgun;
ConVar g_cvFirebugDmg_Sniper;

public Plugin myinfo = 
{
    name = "[L4D2] Medic & Firebug (Weapon Categories Setup)",
    author = "Tyn Zũ",
    description = "Thay thế đạn bằng particles hồi máu/sát thương",
    version = PLUGIN_VERSION,
    url = "https://github.com/Ledahvu/Left-4-Dead-2-SourcePawn-Collection/blob/main/L4D2_Survivors_Class.sp"
};

public void OnPluginStart()
{
    // Cài đặt chung
    g_cvTickRate = CreateConVar("l4d2_ability_tickrate", "0.25", "Tốc độ trừ đạn và tạo hạt", FCVAR_NOTIFY);
    g_cvMaxDistance = CreateConVar("l4d2_ability_distance", "400.0", "Tầm xa ngọn lửa", FCVAR_NOTIFY);
    g_cvMaxAngle = CreateConVar("l4d2_ability_angle", "30.0", "Độ rộng ngọn lửa", FCVAR_NOTIFY);

    // MEDIC HEAL
    g_cvMedicHeal_SMG = CreateConVar("l4d2_medic_heal_smg", "1", "Lượng máu Medic hồi (SMG)", FCVAR_NOTIFY);
    g_cvMedicHeal_Rifle = CreateConVar("l4d2_medic_heal_rifle", "2", "Lượng máu Medic hồi (Rifle)", FCVAR_NOTIFY);
    g_cvMedicHeal_Shotgun = CreateConVar("l4d2_medic_heal_shotgun", "5", "Lượng máu Medic hồi (Shotgun)", FCVAR_NOTIFY);
    g_cvMedicHeal_Sniper = CreateConVar("l4d2_medic_heal_sniper", "4", "Lượng máu Medic hồi (Sniper)", FCVAR_NOTIFY);

    // MEDIC DAMAGE
    g_cvMedicDmg_SMG = CreateConVar("l4d2_medic_dmg_smg", "3.0", "Sát thương Medic (SMG)", FCVAR_NOTIFY);
    g_cvMedicDmg_Rifle = CreateConVar("l4d2_medic_dmg_rifle", "5.0", "Sát thương Medic (Rifle)", FCVAR_NOTIFY);
    g_cvMedicDmg_Shotgun = CreateConVar("l4d2_medic_dmg_shotgun", "12.0", "Sát thương Medic (Shotgun)", FCVAR_NOTIFY);
    g_cvMedicDmg_Sniper = CreateConVar("l4d2_medic_dmg_sniper", "10.0", "Sát thương Medic (Sniper)", FCVAR_NOTIFY);

    // FIREBUG DAMAGE
    g_cvFirebugDmg_SMG = CreateConVar("l4d2_firebug_dmg_smg", "10.0", "Sát thương Firebug (SMG)", FCVAR_NOTIFY);
    g_cvFirebugDmg_Rifle = CreateConVar("l4d2_firebug_dmg_rifle", "18.0", "Sát thương Firebug (Rifle)", FCVAR_NOTIFY);
    g_cvFirebugDmg_Shotgun = CreateConVar("l4d2_firebug_dmg_shotgun", "40.0", "Sát thương Firebug (Shotgun)", FCVAR_NOTIFY);
    g_cvFirebugDmg_Sniper = CreateConVar("l4d2_firebug_dmg_sniper", "35.0", "Sát thương Firebug (Sniper)", FCVAR_NOTIFY);

    AutoExecConfig(true, "l4d2_custom_classes");
    RegConsoleCmd("sm_class", Command_ClassMenu, "Mở menu chọn Class");
    HookEvent("player_disconnect", Event_PlayerDisconnect);
}

// ====================================================================================
// MENU VÀ KẾT NỐI
// ====================================================================================
public Action Command_ClassMenu(int client, int args)
{
    if (client == 0 || !IsClientInGame(client)) return Plugin_Handled;
    Menu menu = new Menu(MenuHandler_Class);
    menu.SetTitle("--- Chọn Kỹ Năng ---");
    menu.AddItem("1", "Medic (Khói Cứu Hỏa)");
    menu.AddItem("2", "Firebug (Lửa Phun)");
    menu.AddItem("0", "Trở về bình thường");
    menu.Display(client, MENU_TIME_FOREVER);
    return Plugin_Handled;
}

public int MenuHandler_Class(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        g_iPlayerClass[param1] = StringToInt(info);
        
        switch (g_iPlayerClass[param1])
        {
            case CLASS_MEDIC: PrintToChat(param1, "\x04[Hệ thống] \x01Bạn chọn class \x03Medic\x01.");
            case CLASS_FIREBUG: PrintToChat(param1, "\x04[Hệ thống] \x01Bạn chọn class \x03Firebug\x01.");
            case CLASS_NONE: PrintToChat(param1, "\x04[Hệ thống] \x01Trở lại bắn đạn bình thường.");
        }
    }
    else if (action == MenuAction_End) { delete menu; }
    return 0;
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && client <= MaxClients) g_iPlayerClass[client] = CLASS_NONE;
}

// ====================================================================================
// NHẬN DIỆN VŨ KHÍ
// ====================================================================================
int GetWeaponCategory(int weapon)
{
    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));
    
    if (StrContains(classname, "smg") != -1) return WPN_SMG;
    if (StrContains(classname, "shotgun") != -1) return WPN_SHOTGUN;
    if (StrContains(classname, "hunting") != -1 || StrContains(classname, "sniper") != -1) return WPN_SNIPER;
    if (StrContains(classname, "rifle") != -1) return WPN_RIFLE; 
    
    return WPN_UNKNOWN;
}

// ====================================================================================
// ĐIỀU KHIỂN BẮN
// ====================================================================================
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != 2) return Plugin_Continue;
    
    int playerClass = g_iPlayerClass[client];
    if (playerClass == CLASS_NONE) return Plugin_Continue;

    int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (activeWeapon == -1) return Plugin_Continue;

    // Loại bỏ súng lục và súng máy hạng nặng cố định
    char wpnClass[64];
    GetEntityClassname(activeWeapon, wpnClass, sizeof(wpnClass));
    if (StrContains(wpnClass, "pistol") != -1 || StrContains(wpnClass, "minigun") != -1) return Plugin_Continue;

    int clip = GetEntProp(activeWeapon, Prop_Send, "m_iClip1");
    if (clip <= 0) return Plugin_Continue;

    if (buttons & IN_ATTACK)
    {
        float time = GetGameTime();
        SetEntPropFloat(activeWeapon, Prop_Send, "m_flNextPrimaryAttack", time + 1.0);
        
        float tickRate = g_cvTickRate.FloatValue;
        if (time >= g_flNextAttack[client])
        {
            g_flNextAttack[client] = time + tickRate; 
            SetEntProp(activeWeapon, Prop_Send, "m_iClip1", clip - 1);
            
            // Lấy nhóm vũ khí và truyền đi
            int weaponCat = GetWeaponCategory(activeWeapon);
            PerformCustomAbility(client, playerClass, activeWeapon, weaponCat);
        }
    }
    return Plugin_Continue;
}

void PerformCustomAbility(int client, int playerClass, int weapon, int weaponCat)
{
    float particleTime = g_cvTickRate.FloatValue + 0.1;

    if (playerClass == CLASS_MEDIC) {
        ShowParticleAttached(client, weapon, PARTICLE_MEDIC, particleTime);
    } else if (playerClass == CLASS_FIREBUG) {
        ShowParticleAttached(client, weapon, PARTICLE_FIREBUG, particleTime);
    }

    ProcessAreaOfEffect(client, playerClass, weaponCat);
}

// ====================================================================================
// LOGIC AOE & XỬ LÝ SÁT THƯƠNG THEO TỪNG LOẠI SÚNG
// ====================================================================================
void ProcessAreaOfEffect(int client, int playerClass, int weaponCat)
{
    float eyePos[3], eyeAng[3], aimVec[3];
    GetClientEyePosition(client, eyePos);
    GetClientEyeAngles(client, eyeAng);
    GetAngleVectors(eyeAng, aimVec, NULL_VECTOR, NULL_VECTOR);
    NormalizeVector(aimVec, aimVec);

    float maxDist = g_cvMaxDistance.FloatValue;
    float maxAngle = g_cvMaxAngle.FloatValue;
    float minDotProduct = Cosine(DegToRad(maxAngle));

    for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i) || !IsPlayerAlive(i) || i == client) continue;
        ProcessTarget(client, i, playerClass, eyePos, aimVec, maxDist, minDotProduct, weaponCat);
    }

    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "infected")) != -1) {
        ProcessTarget(client, ent, playerClass, eyePos, aimVec, maxDist, minDotProduct, weaponCat);
    }

    ent = -1;
    while ((ent = FindEntityByClassname(ent, "witch")) != -1) {
        ProcessTarget(client, ent, playerClass, eyePos, aimVec, maxDist, minDotProduct, weaponCat);
    }
}

void ProcessTarget(int client, int target, int playerClass, float eyePos[3], float aimVec[3], float maxDist, float minDotProduct, int weaponCat)
{
    bool isClient = (target > 0 && target <= MaxClients && IsClientInGame(target));
    
    float targetPos[3];
    if (isClient) {
        GetClientEyePosition(target, targetPos);
        targetPos[2] -= 15.0; 
    } else {
        GetEntPropVector(target, Prop_Send, "m_vecOrigin", targetPos);
        targetPos[2] += 40.0; 
    }

    float dir[3];
    MakeVectorFromPoints(eyePos, targetPos, dir);
    float dist = GetVectorLength(dir);
    
    if (dist > maxDist) return; 
    
    NormalizeVector(dir, dir);
    float dotProduct = GetVectorDotProduct(aimVec, dir);
    
    if (dotProduct >= minDotProduct) 
    {
        Handle trace = TR_TraceRayFilterEx(eyePos, targetPos, MASK_OPAQUE, RayType_EndPoint, TraceFilter_IgnorePlayersAndInfected, client);
        bool isBlockedByWall = false;
        
        if (TR_DidHit(trace)) {
            int hitEnt = TR_GetEntityIndex(trace);
            if (hitEnt == 0) isBlockedByWall = true; 
        }
        delete trace;

        if (!isBlockedByWall) {
            ApplyEffect(client, target, playerClass, isClient, weaponCat);
        }
    }
}

void ApplyEffect(int client, int target, int playerClass, bool isClient, int weaponCat)
{
    bool isSurvivor = false;
    bool isInfected = false;

    if (isClient) {
        int team = GetClientTeam(target);
        if (team == 2) isSurvivor = true;
        else if (team == 3) isInfected = true;
    } else {
        isInfected = true; 
    }

    // LẤY GIÁ TRỊ TỪ CVAR DỰA THEO LOẠI SÚNG
    int healAmt = 0;
    float medDmg = 0.0;
    float fireDmg = 0.0;

    switch(weaponCat) {
        case WPN_SMG: {
            healAmt = g_cvMedicHeal_SMG.IntValue;
            medDmg = g_cvMedicDmg_SMG.FloatValue;
            fireDmg = g_cvFirebugDmg_SMG.FloatValue;
        }
        case WPN_RIFLE: {
            healAmt = g_cvMedicHeal_Rifle.IntValue;
            medDmg = g_cvMedicDmg_Rifle.FloatValue;
            fireDmg = g_cvFirebugDmg_Rifle.FloatValue;
        }
        case WPN_SHOTGUN: {
            healAmt = g_cvMedicHeal_Shotgun.IntValue;
            medDmg = g_cvMedicDmg_Shotgun.FloatValue;
            fireDmg = g_cvFirebugDmg_Shotgun.FloatValue;
        }
        case WPN_SNIPER: {
            healAmt = g_cvMedicHeal_Sniper.IntValue;
            medDmg = g_cvMedicDmg_Sniper.FloatValue;
            fireDmg = g_cvFirebugDmg_Sniper.FloatValue;
        }
        default: { // Backup an toàn nếu hệ thống không nhận dạng được
            healAmt = 2; medDmg = 5.0; fireDmg = 25.0; 
        }
    }

    // THỰC THI HIỆU ỨNG
    if (playerClass == CLASS_MEDIC) {
        if (isSurvivor && client != target) {
            int hp = GetClientHealth(target);
            int maxHp = 100; 
            if (hp < maxHp) SetEntityHealth(target, hp + healAmt > maxHp ? maxHp : hp + healAmt);
        } else if (isInfected) {
            SDKHooks_TakeDamage(target, client, client, medDmg, DMG_BULLET);
        }
    } else if (playerClass == CLASS_FIREBUG) {
        if (isInfected) {
            SDKHooks_TakeDamage(target, client, client, fireDmg, DMG_BURN);
            IgniteEntity(target, 3.0);
        }
    }
}

public bool TraceFilter_IgnorePlayersAndInfected(int entity, int contentsMask, any data)
{
    if (entity > 0 && entity <= MaxClients) return false;
    if (IsValidEntity(entity)) {
        char classname[64];
        GetEntityClassname(entity, classname, sizeof(classname));
        if (StrContains(classname, "infected") != -1 || StrContains(classname, "witch") != -1) 
            return false;
    }
    return true; 
}

// ====================================================================================
// HỆ THỐNG PARTICLES HOÀN HẢO
// ====================================================================================
void ShowParticleAttached(int client, int weapon, const char[] particleName, float time)
{
    int viewmodel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
    if (viewmodel > 0 && IsValidEntity(viewmodel))
    {
        int p1 = CreateEntityByName("info_particle_system");
        if (IsValidEntity(p1))
        {
            DispatchKeyValue(p1, "effect_name", particleName);
            DispatchSpawn(p1);
            ActivateEntity(p1);
            
            SetVariantString("!activator");
            AcceptEntityInput(p1, "SetParent", viewmodel, p1, 0);
            SetVariantString("muzzle_flash"); 
            AcceptEntityInput(p1, "SetParentAttachment", p1, p1, 0);
            
            AcceptEntityInput(p1, "Start");
            CreateTimer(time, Timer_KillParticle, EntIndexToEntRef(p1), TIMER_FLAG_NO_MAPCHANGE);
        }
    }

    if (weapon > 0 && IsValidEntity(weapon))
    {
        int p2 = CreateEntityByName("info_particle_system");
        if (IsValidEntity(p2))
        {
            DispatchKeyValue(p2, "effect_name", particleName);
            DispatchSpawn(p2);
            ActivateEntity(p2);
            
            SetVariantString("!activator");
            AcceptEntityInput(p2, "SetParent", weapon, p2, 0); 
            SetVariantString("muzzle_flash"); 
            AcceptEntityInput(p2, "SetParentAttachment", p2, p2, 0);
            
            AcceptEntityInput(p2, "Start");
            SetEntPropEnt(p2, Prop_Send, "m_hOwnerEntity", client);
            SDKHook(p2, SDKHook_SetTransmit, Hook_HideFromOwner);

            CreateTimer(time, Timer_KillParticle, EntIndexToEntRef(p2), TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

public Action Hook_HideFromOwner(int entity, int client)
{
    int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    if (client == owner) return Plugin_Handled; 
    return Plugin_Continue; 
}

public Action Timer_KillParticle(Handle timer, any ref)
{
    int particle = EntRefToEntIndex(ref);
    if (particle > 0 && IsValidEntity(particle))
    {
        AcceptEntityInput(particle, "Stop");
        AcceptEntityInput(particle, "Kill");
    }
    return Plugin_Continue;
}
