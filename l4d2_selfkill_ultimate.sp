#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

// ==================== CVARS ====================
bool g_bEnabled;
float g_fRadiusClose, g_fRadiusMid, g_fRadiusFar;
int g_iActionClose, g_iActionMid;
float g_fPercentMax, g_fPercentMin;
char g_sSound[PLATFORM_MAX_PATH], g_sParticle[64];
int g_iPipeTime;
float g_fPipeSpeedMult, g_fPipeBlinkBase;

// CVars cho gravity mode 
float g_fGravityRange;
float g_fGravityForce;
float g_fGravityInterval;
int g_iMaxTargets;
float g_fGravityExplodeDist;
int g_iGravityExplodeThreshold; // SỐ LƯỢNG NGƯỜI CẦN THIẾT ĐỂ NỔ

// CVars cho sát thương SI/Tank
int g_iSIDamageMode;
float g_fSIDamageAmount;
bool g_bSeparateTank;
int g_iTankDamageMode;
float g_fTankDamageAmount;

// CVars cho rung màn hình
float g_fShakeRadiusMultiplier;
float g_fShakeCloseAmplitude, g_fShakeCloseFrequency, g_fShakeCloseDuration;
float g_fShakeMidAmplitude, g_fShakeMidFrequency, g_fShakeMidDuration;
float g_fShakeFarAmplitude, g_fShakeFarFrequency, g_fShakeFarDuration;
float g_fShakeOuterAmplitude, g_fShakeOuterFrequency, g_fShakeOuterDuration;
bool g_bShakeEnable;

// CVars cho stagger
bool g_bStaggerEnable;

// ==================== CVARS CHO RINGS ====================
bool g_bRingsEnable;
int g_iRingColorClose[4] = {255, 0, 0, 255};
int g_iRingColorMid[4] = {255, 255, 0, 255};
int g_iRingColorFar[4] = {0, 255, 0, 255};
float g_fRingAlphaMin;
float g_fRingAlphaMax;
bool g_bRingBlinkEnable;

// Sprites
int g_iBeamSprite;
int g_iHaloSprite;

// ==================== TRẠNG THÁI ====================
bool g_bPipeActive[MAXPLAYERS+1];
Handle g_hPipeTimer[MAXPLAYERS+1];
Handle g_hBlinkTimer[MAXPLAYERS+1];
Handle g_hRingTimer[MAXPLAYERS+1];
int g_iPipeCountdown[MAXPLAYERS+1];
float g_fOriginalSpeed[MAXPLAYERS+1];
int g_iInstructorHintEntity[MAXPLAYERS+1];

// Gravity mode
bool g_bGravityActive[MAXPLAYERS+1];
bool g_bShiftPressed[MAXPLAYERS+1];
Handle g_hGravityTimer[MAXPLAYERS+1];

public Plugin myinfo =
{
    name        = "L4D2 Selfkill Ultimate",
    author      = "Tyn Zũ",
    description = "Tự sát siêu nổ (5x Propane), gravity hút gom đủ người mới nổ",
    version     = "10.2",
    url         = ""
};

public void OnMapStart()
{
    if (strlen(g_sSound) > 0)
        PrecacheSound(g_sSound);

    if (strlen(g_sParticle) > 0)
        PrecacheParticle(g_sParticle);

    g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt", true);
    g_iHaloSprite = PrecacheModel("materials/sprites/glow01.vmt", true);
    
    // Precache mô hình bình gas cho vụ nổ vật lý siêu lớn
    PrecacheModel("models/props_junk/propanecanister001a.mdl", true);
}

public void OnPluginStart()
{
    RegConsoleCmd("sm_selfkill", Command_SelfKill);
    RegConsoleCmd("sm_selfkillp", Command_SelfKillPipe);
    RegConsoleCmd("sm_selfkillg", Command_SelfKillGravity);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
            OnClientPutInServer(i);
    }

    CreateConVar("selfkill_version", "10.2", "Plugin version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
    ConVar cvEnable = CreateConVar("selfkill_enable", "1", "Bật/tắt plugin");
    
    ConVar cvRadClose = CreateConVar("selfkill_radius_close", "150.0", "Bán kính vùng 1");
    ConVar cvRadMid = CreateConVar("selfkill_radius_mid", "300.0", "Bán kính vùng 2");
    ConVar cvRadFar = CreateConVar("selfkill_radius_far", "500.0", "Bán kính vùng 3 (tối đa)");
    ConVar cvActionClose = CreateConVar("selfkill_action_close", "0", "Hành động vùng 1: 0 = Chắc chắn chết, 1 = Chỉ Incap");
    ConVar cvActionMid = CreateConVar("selfkill_action_mid", "0", "Hành động vùng 2: 0 = Incap, 1 = Mất máu %");
    ConVar cvPercentMax = CreateConVar("selfkill_dmg_percent_max", "80.0", "% máu mất tối đa khi đứng sát tâm nổ");
    ConVar cvPercentMin = CreateConVar("selfkill_dmg_percent_min", "10.0", "% máu mất tối thiểu ở rìa vùng xa nhất");
    ConVar cvSound = CreateConVar("selfkill_sound", "weapons/explode5.wav", "Âm thanh nổ");
    ConVar cvParticle = CreateConVar("selfkill_particle", "explosion_tank_large", "Hiệu ứng nổ");
    ConVar cvPipeTime = CreateConVar("selfkill_pipe_time", "5", "Thời gian đếm ngược pipebomb");
    ConVar cvPipeSpeed = CreateConVar("selfkill_pipe_speed_mult", "1.3", "Hệ số tăng tốc pipebomb");
    ConVar cvPipeBlink = CreateConVar("selfkill_pipe_blink_base", "0.3", "Tốc độ chớp nháy");
    
    // CVars cho gravity mode
    ConVar cvGravRange = CreateConVar("selfkill_gravity_range", "500.0", "Phạm vi hút");
    ConVar cvGravForce = CreateConVar("selfkill_gravity_force", "150.0", "Lực hút");
    ConVar cvGravInterval = CreateConVar("selfkill_gravity_interval", "0.05", "Chu kỳ hút");
    ConVar cvGravMaxTargets = CreateConVar("selfkill_gravity_max_targets", "5", "Số lượng mục tiêu tối đa bị hút cùng lúc");
    ConVar cvGravDist = CreateConVar("selfkill_gravity_explode_dist", "60.0", "Khoảng cách nổ khi hút");
    ConVar cvGravThreshold = CreateConVar("selfkill_gravity_explode_threshold", "1", "Số lượng người tối thiểu bị hút vào để phát nổ");

    // CVars cho SI/Tank
    ConVar cvSIDamageMode = CreateConVar("selfkill_si_damage_mode", "0", "0=Chết ngay, 1=Sát thương tuyệt đối, 2=Sát thương %");
    ConVar cvSIDamageAmount = CreateConVar("selfkill_si_damage_amount", "100.0", "Sát thương cho SI", _, true, 0.0, true, 100.0);
    ConVar cvSeparateTank = CreateConVar("selfkill_separate_tank", "0", "0=Không, 1=Có");
    ConVar cvTankDamageMode = CreateConVar("selfkill_tank_damage_mode", "2", "0=Chết ngay, 1=Sát thương tuyệt đối, 2=Sát thương %");
    ConVar cvTankDamageAmount = CreateConVar("selfkill_tank_damage_amount", "50.0", "Sát thương cho Tank", _, true, 0.0, true, 100.0);

    // CVars cho rung màn hình
    ConVar cvShakeEnable = CreateConVar("selfkill_shake_enable", "1", "Bật/tắt hiệu ứng rung màn hình");
    ConVar cvShakeRadiusMult = CreateConVar("selfkill_shake_radius_mult", "2.0", "Hệ số nhân bán kính rung");
    ConVar cvShakeCloseDur = CreateConVar("selfkill_shake_close_duration", "3.5", "Thời gian rung vùng gần");
    ConVar cvShakeCloseAmp = CreateConVar("selfkill_shake_close_amplitude", "50.0", "Biên độ rung vùng gần");
    ConVar cvShakeCloseFreq = CreateConVar("selfkill_shake_close_frequency", "60.0", "Tần số rung vùng gần");
    ConVar cvShakeMidDur = CreateConVar("selfkill_shake_mid_duration", "3.0", "Thời gian rung vùng giữa");
    ConVar cvShakeMidAmp = CreateConVar("selfkill_shake_mid_amplitude", "40.0", "Biên độ rung vùng giữa");
    ConVar cvShakeMidFreq = CreateConVar("selfkill_shake_mid_frequency", "50.0", "Tần số rung vùng giữa");
    ConVar cvShakeFarDur = CreateConVar("selfkill_shake_far_duration", "2.5", "Thời gian rung vùng xa");
    ConVar cvShakeFarAmp = CreateConVar("selfkill_shake_far_amplitude", "30.0", "Biên độ rung vùng xa");
    ConVar cvShakeFarFreq = CreateConVar("selfkill_shake_far_frequency", "40.0", "Tần số rung vùng xa");
    ConVar cvShakeOuterDur = CreateConVar("selfkill_shake_outer_duration", "1.5", "Thời gian rung ngoài vùng sát thương");
    ConVar cvShakeOuterAmp = CreateConVar("selfkill_shake_outer_amplitude", "8.0", "Biên độ rung ngoài vùng");
    ConVar cvShakeOuterFreq = CreateConVar("selfkill_shake_outer_frequency", "10.0", "Tần số rung ngoài vùng");

    // CVars cho stagger
    ConVar cvStaggerEnable = CreateConVar("selfkill_stagger_enable", "1", "Bật/tắt hiệu ứng chao đảo (stagger)");

    // ==================== CVars cho rings ====================
    ConVar cvRingsEnable = CreateConVar("selfkill_rings_enable", "1", "Bật/tắt vòng tròn mở rộng");
    ConVar cvRingColorClose = CreateConVar("selfkill_ring_color_close", "255 0 0", "Màu vùng gần (R G B)");
    ConVar cvRingColorMid = CreateConVar("selfkill_ring_color_mid", "255 255 0", "Màu vùng giữa (R G B)");
    ConVar cvRingColorFar = CreateConVar("selfkill_ring_color_far", "0 255 0", "Màu vùng xa (R G B)");
    ConVar cvRingAlphaMin = CreateConVar("selfkill_ring_alpha_min", "50", "Độ mờ tối thiểu (0-255) khi sắp nổ");
    ConVar cvRingAlphaMax = CreateConVar("selfkill_ring_alpha_max", "255", "Độ mờ tối đa (0-255) khi bắt đầu");
    ConVar cvRingBlinkEnable = CreateConVar("selfkill_ring_blink_enable", "1", "Bật/tắt hiệu ứng nhấp nháy cho rings");

    AutoExecConfig(true, "l4d2_selfkill_ultimate");

    // Hook CVars
    cvEnable.AddChangeHook(OnCvarChanged);
    cvRadClose.AddChangeHook(OnCvarChanged);
    cvRadMid.AddChangeHook(OnCvarChanged);
    cvRadFar.AddChangeHook(OnCvarChanged);
    cvActionClose.AddChangeHook(OnCvarChanged);
    cvActionMid.AddChangeHook(OnCvarChanged);
    cvPercentMax.AddChangeHook(OnCvarChanged);
    cvPercentMin.AddChangeHook(OnCvarChanged);
    cvSound.AddChangeHook(OnCvarChanged);
    cvParticle.AddChangeHook(OnCvarChanged);
    cvPipeTime.AddChangeHook(OnCvarChanged);
    cvPipeSpeed.AddChangeHook(OnCvarChanged);
    cvPipeBlink.AddChangeHook(OnCvarChanged);
    cvGravRange.AddChangeHook(OnCvarChanged);
    cvGravForce.AddChangeHook(OnCvarChanged);
    cvGravInterval.AddChangeHook(OnCvarChanged);
    cvGravMaxTargets.AddChangeHook(OnCvarChanged);
    cvGravDist.AddChangeHook(OnCvarChanged);
    cvGravThreshold.AddChangeHook(OnCvarChanged);

    cvSIDamageMode.AddChangeHook(OnCvarChanged);
    cvSIDamageAmount.AddChangeHook(OnCvarChanged);
    cvSeparateTank.AddChangeHook(OnCvarChanged);
    cvTankDamageMode.AddChangeHook(OnCvarChanged);
    cvTankDamageAmount.AddChangeHook(OnCvarChanged);

    cvShakeEnable.AddChangeHook(OnCvarChanged);
    cvShakeRadiusMult.AddChangeHook(OnCvarChanged);
    cvShakeCloseDur.AddChangeHook(OnCvarChanged);
    cvShakeCloseAmp.AddChangeHook(OnCvarChanged);
    cvShakeCloseFreq.AddChangeHook(OnCvarChanged);
    cvShakeMidDur.AddChangeHook(OnCvarChanged);
    cvShakeMidAmp.AddChangeHook(OnCvarChanged);
    cvShakeMidFreq.AddChangeHook(OnCvarChanged);
    cvShakeFarDur.AddChangeHook(OnCvarChanged);
    cvShakeFarAmp.AddChangeHook(OnCvarChanged);
    cvShakeFarFreq.AddChangeHook(OnCvarChanged);
    cvShakeOuterDur.AddChangeHook(OnCvarChanged);
    cvShakeOuterAmp.AddChangeHook(OnCvarChanged);
    cvShakeOuterFreq.AddChangeHook(OnCvarChanged);

    cvStaggerEnable.AddChangeHook(OnCvarChanged);

    cvRingsEnable.AddChangeHook(OnCvarChanged);
    cvRingColorClose.AddChangeHook(OnCvarChanged);
    cvRingColorMid.AddChangeHook(OnCvarChanged);
    cvRingColorFar.AddChangeHook(OnCvarChanged);
    cvRingAlphaMin.AddChangeHook(OnCvarChanged);
    cvRingAlphaMax.AddChangeHook(OnCvarChanged);
    cvRingBlinkEnable.AddChangeHook(OnCvarChanged);

    UpdateAllCvars();
}

public void OnClientPutInServer(int client)
{
    g_bShiftPressed[client] = false;
}

public void OnCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    UpdateAllCvars();
}

void ParseColor(const char[] str, int color[4])
{
    char parts[3][8];
    if (ExplodeString(str, " ", parts, sizeof(parts), sizeof(parts[])) >= 3)
    {
        color[0] = StringToInt(parts[0]);
        color[1] = StringToInt(parts[1]);
        color[2] = StringToInt(parts[2]);
        color[3] = 255;
    }
}

void UpdateAllCvars()
{
    g_bEnabled = GetConVarBool(FindConVar("selfkill_enable"));
    g_fRadiusClose = GetConVarFloat(FindConVar("selfkill_radius_close"));
    g_fRadiusMid = GetConVarFloat(FindConVar("selfkill_radius_mid"));
    g_fRadiusFar = GetConVarFloat(FindConVar("selfkill_radius_far"));
    g_iActionClose = GetConVarInt(FindConVar("selfkill_action_close"));
    g_iActionMid = GetConVarInt(FindConVar("selfkill_action_mid"));
    g_fPercentMax = GetConVarFloat(FindConVar("selfkill_dmg_percent_max"));
    g_fPercentMin = GetConVarFloat(FindConVar("selfkill_dmg_percent_min"));
    GetConVarString(FindConVar("selfkill_sound"), g_sSound, sizeof(g_sSound));
    GetConVarString(FindConVar("selfkill_particle"), g_sParticle, sizeof(g_sParticle));
    g_iPipeTime = GetConVarInt(FindConVar("selfkill_pipe_time"));
    g_fPipeSpeedMult = GetConVarFloat(FindConVar("selfkill_pipe_speed_mult"));
    g_fPipeBlinkBase = GetConVarFloat(FindConVar("selfkill_pipe_blink_base"));
    
    g_fGravityRange = GetConVarFloat(FindConVar("selfkill_gravity_range"));
    g_fGravityForce = GetConVarFloat(FindConVar("selfkill_gravity_force"));
    g_fGravityInterval = GetConVarFloat(FindConVar("selfkill_gravity_interval"));
    g_iMaxTargets = GetConVarInt(FindConVar("selfkill_gravity_max_targets"));
    g_fGravityExplodeDist = GetConVarFloat(FindConVar("selfkill_gravity_explode_dist"));
    g_iGravityExplodeThreshold = GetConVarInt(FindConVar("selfkill_gravity_explode_threshold"));
    if (g_iGravityExplodeThreshold < 1) g_iGravityExplodeThreshold = 1;

    g_iSIDamageMode = GetConVarInt(FindConVar("selfkill_si_damage_mode"));
    g_fSIDamageAmount = GetConVarFloat(FindConVar("selfkill_si_damage_amount"));
    g_bSeparateTank = GetConVarBool(FindConVar("selfkill_separate_tank"));
    g_iTankDamageMode = GetConVarInt(FindConVar("selfkill_tank_damage_mode"));
    g_fTankDamageAmount = GetConVarFloat(FindConVar("selfkill_tank_damage_amount"));

    g_bShakeEnable = GetConVarBool(FindConVar("selfkill_shake_enable"));
    g_fShakeRadiusMultiplier = GetConVarFloat(FindConVar("selfkill_shake_radius_mult"));
    g_fShakeCloseDuration = GetConVarFloat(FindConVar("selfkill_shake_close_duration"));
    g_fShakeCloseAmplitude = GetConVarFloat(FindConVar("selfkill_shake_close_amplitude"));
    g_fShakeCloseFrequency = GetConVarFloat(FindConVar("selfkill_shake_close_frequency"));
    g_fShakeMidDuration = GetConVarFloat(FindConVar("selfkill_shake_mid_duration"));
    g_fShakeMidAmplitude = GetConVarFloat(FindConVar("selfkill_shake_mid_amplitude"));
    g_fShakeMidFrequency = GetConVarFloat(FindConVar("selfkill_shake_mid_frequency"));
    g_fShakeFarDuration = GetConVarFloat(FindConVar("selfkill_shake_far_duration"));
    g_fShakeFarAmplitude = GetConVarFloat(FindConVar("selfkill_shake_far_amplitude"));
    g_fShakeFarFrequency = GetConVarFloat(FindConVar("selfkill_shake_far_frequency"));
    g_fShakeOuterDuration = GetConVarFloat(FindConVar("selfkill_shake_outer_duration"));
    g_fShakeOuterAmplitude = GetConVarFloat(FindConVar("selfkill_shake_outer_amplitude"));
    g_fShakeOuterFrequency = GetConVarFloat(FindConVar("selfkill_shake_outer_frequency"));

    g_bStaggerEnable = GetConVarBool(FindConVar("selfkill_stagger_enable"));

    g_bRingsEnable = GetConVarBool(FindConVar("selfkill_rings_enable"));
    char sColor[32];
    GetConVarString(FindConVar("selfkill_ring_color_close"), sColor, sizeof(sColor));
    ParseColor(sColor, g_iRingColorClose);
    GetConVarString(FindConVar("selfkill_ring_color_mid"), sColor, sizeof(sColor));
    ParseColor(sColor, g_iRingColorMid);
    GetConVarString(FindConVar("selfkill_ring_color_far"), sColor, sizeof(sColor));
    ParseColor(sColor, g_iRingColorFar);
    
    g_fRingAlphaMin = float(GetConVarInt(FindConVar("selfkill_ring_alpha_min")));
    g_fRingAlphaMax = float(GetConVarInt(FindConVar("selfkill_ring_alpha_max")));
    g_bRingBlinkEnable = GetConVarBool(FindConVar("selfkill_ring_blink_enable"));
}

public void OnClientDisconnect(int client)
{
    ResetPipeState(client);
    ResetGravityState(client);
    g_bShiftPressed[client] = false;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (g_bGravityActive[client] && IsPlayerAlive(client))
    {
        bool isShiftDown = (buttons & IN_SPEED) != 0;
        
        if (isShiftDown && !g_bShiftPressed[client])
        {
            g_bShiftPressed[client] = true;
            g_hGravityTimer[client] = CreateTimer(g_fGravityInterval, Timer_GravityPull, client, TIMER_REPEAT);
        }
        else if (!isShiftDown && g_bShiftPressed[client])
        {
            g_bShiftPressed[client] = false;
            StopGravityPull(client);
        }
    }
    return Plugin_Continue;
}

// ==================== LỆNH SELFKILL ====================
public Action Command_SelfKill(int client, int args)
{
    if (!g_bEnabled || !IsValidAlive(client)) return Plugin_Handled;
    DoExplosionAtClient(client);
    PrintToChat(client, "[SM] Bạn đã tự nổ tung!");
    return Plugin_Handled;
}

// ==================== SELFKILLP ====================
public Action Command_SelfKillPipe(int client, int args)
{
    if (!g_bEnabled || !IsValidAlive(client) || g_bPipeActive[client]) return Plugin_Handled;
    
    g_bPipeActive[client] = true;
    g_iPipeCountdown[client] = g_iPipeTime;

    g_fOriginalSpeed[client] = GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue");
    SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", g_fOriginalSpeed[client] * g_fPipeSpeedMult);

    CreateInstructorHint(client, g_iPipeCountdown[client]);
    UpdateBlinkRate(client);
    
    g_hPipeTimer[client] = CreateTimer(1.0, Timer_PipeCountdown, client, TIMER_REPEAT);
    g_hRingTimer[client] = CreateTimer(0.8, Timer_DrawRings, client, TIMER_REPEAT);

    PrintToChat(client, "[SM] Kích hoạt pipebomb (%d giây)!", g_iPipeTime);
    return Plugin_Handled;
}

void CreateInstructorHint(int client, int number)
{
    if (g_iInstructorHintEntity[client] != 0 && IsValidEntity(g_iInstructorHintEntity[client]))
    {
        AcceptEntityInput(g_iInstructorHintEntity[client], "EndHint");
        RemoveEntity(g_iInstructorHintEntity[client]);
    }

    int entity = CreateEntityByName("env_instructor_hint");
    if (entity == -1) return;
    
    char sTargetName[32], sNumber[16];
    FormatEx(sTargetName, sizeof(sTargetName), "selfkill_hint_%d", client);
    IntToString(number, sNumber, sizeof(sNumber));
    
    DispatchKeyValue(client, "targetname", sTargetName);
    DispatchKeyValue(entity, "hint_target", sTargetName);
    DispatchKeyValue(entity, "hint_caption", sNumber);
    DispatchKeyValue(entity, "hint_color", "255 0 0");
    DispatchKeyValue(entity, "hint_forcecaption", "1");
    DispatchKeyValue(entity, "hint_nooffscreen", "1");
    DispatchKeyValue(entity, "hint_icon_onscreen", "icon_skull");
    DispatchKeyValue(entity, "hint_icon_offset", "80");
    DispatchKeyValue(entity, "hint_timeout", "0");
    DispatchKeyValue(entity, "hint_static", "0");
    
    DispatchSpawn(entity);
    ActivateEntity(entity);
    
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && !IsFakeClient(i))
            AcceptEntityInput(entity, "ShowHint", i);
    g_iInstructorHintEntity[client] = entity;
}

void UpdateBlinkRate(int client)
{
    if (g_hBlinkTimer[client] != null) { KillTimer(g_hBlinkTimer[client]); g_hBlinkTimer[client] = null; }
    float ratio = float(g_iPipeCountdown[client]) / float(g_iPipeTime);
    float interval = g_fPipeBlinkBase * ratio;
    if (interval < 0.05) interval = 0.05;
    g_hBlinkTimer[client] = CreateTimer(interval, Timer_BlinkColor, client, TIMER_REPEAT);
}

public Action Timer_PipeCountdown(Handle timer, int client)
{
    if (!g_bPipeActive[client] || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        ResetPipeState(client);
        return Plugin_Stop;
    }
    
    g_iPipeCountdown[client]--;
    if (g_iPipeCountdown[client] <= 0)
    {
        ResetPipeState(client);
        DoExplosionAtClient(client);
        PrintToChat(client, "[SM] BÙM! Bạn đã phát nổ!");
        return Plugin_Stop;
    }
    
    CreateInstructorHint(client, g_iPipeCountdown[client]);
    UpdateBlinkRate(client);
    EmitSoundToClient(client, "buttons/blip1.wav", _, _, _, _, 0.5);
    return Plugin_Continue;
}

public Action Timer_BlinkColor(Handle timer, int client)
