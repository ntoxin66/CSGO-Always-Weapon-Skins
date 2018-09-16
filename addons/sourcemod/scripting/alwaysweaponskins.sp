#include <dhooks>
#include <cstrike>
#include <sdktools_entinput>
#include <sdktools_functions>
#include <sdkhooks>
#undef REQUIRE_PLUGIN
#include <lastrequest>
#define REQUIRE_PLUGIN
#pragma semicolon 1
#pragma newdecls required

/***************************************************
 * STATIC / GLOBALS STUFF
 **************************************************/
static Handle s_hGiveNamedItem = null;
static Handle s_hGiveNamedItemPost = null;
static bool s_HookInUse = false;
static bool s_bHostiesLoaded;
static Handle s_hMapWeapons = null;
static int s_OriginalClientTeam;
static bool s_TeamWasSwitched = false;

/***************************************************
 * PLUGIN STUFF
 **************************************************/
public Plugin myinfo =
{
	name = "Always Weapon Skins",
	author = "Neuro Toxin",
	description = "Players always get their weapon skins!",
	version = "2.2.6",
	url = "https://forums.alliedmods.net/showthread.php?t=237114",
}

public void OnPluginStart()
{
	if (!HookOnGiveNamedItem())
	{
		SetFailState("Unable to hook GiveNamedItem using DHooks");
		return;
	}
	
	if (!BuildItems())
	{
		SetFailState("Unable to load items data from 'items_game.txt'");
		return;
	}
	
	CreateConvars();
}

/***************************************************
 * CONVAR STUFF
 **************************************************/
static ConVar s_ConVar_Enable;
static ConVar s_ConVar_SkipMapWeapons;
static ConVar s_ConVar_SkipNamedWeapons;
static ConVar s_ConVar_DebugMessages;

static bool s_bEnable = false;
static bool s_bSkipMapWeapons = true;
static bool s_bSkipNamedWeapons = true;
static bool s_bDebugMessages = false;

stock void CreateConvars()
{
	s_ConVar_Enable = CreateConVar("aws_enable", "1", "Enables plugin");
	s_ConVar_SkipMapWeapons = CreateConVar("aws_skipmapweapons", "0", "Disables replacement of map weapons");
	s_ConVar_SkipNamedWeapons = CreateConVar("aws_skipnamedweapons", "1", "Disables replacement of map weapons which have names (special weapons)");
	s_ConVar_DebugMessages = CreateConVar("aws_debugmessages", "0", "Display debug messages in client console");
	
	HookConVarChange(s_ConVar_Enable, OnCvarChanged);
	HookConVarChange(s_ConVar_SkipMapWeapons, OnCvarChanged);
	HookConVarChange(s_ConVar_SkipNamedWeapons, OnCvarChanged);
	HookConVarChange(s_ConVar_DebugMessages, OnCvarChanged);
	
	Handle version = CreateConVar("aws_version", "2.2.2");
	int flags = GetConVarFlags(version);
	flags |= FCVAR_NOTIFY;
	SetConVarFlags(version, flags);
	CloseHandle(version);
}

stock void LoadConvars()
{
	s_bEnable = GetConVarBool(s_ConVar_Enable);
	s_bSkipMapWeapons = GetConVarBool(s_ConVar_SkipMapWeapons);
	s_bSkipNamedWeapons = GetConVarBool(s_ConVar_SkipNamedWeapons);
	s_bDebugMessages = GetConVarBool(s_ConVar_DebugMessages);
}

public void OnCvarChanged(Handle cvar, const char[] oldVal, const char[] newVal)
{
	if (cvar == s_ConVar_Enable)
		s_bEnable = StringToInt(newVal) == 0 ? false : true;
	else if (cvar == s_ConVar_SkipMapWeapons)
		s_bSkipMapWeapons = StringToInt(newVal) == 0 ? false : true;
	else if (cvar == s_ConVar_SkipNamedWeapons)
		s_bSkipNamedWeapons = StringToInt(newVal) == 0 ? false : true;
	else if (cvar == s_ConVar_DebugMessages)
		s_bDebugMessages = StringToInt(newVal) == 0 ? false : true;
}

/***************************************************
 * DHOOKS STUFF
 **************************************************/
public bool HookOnGiveNamedItem()
{
	Handle config = LoadGameConfigFile("sdktools.games");
	if(config == null)
	{
		LogError("Unable to load game config file: sdktools.games");
		return false;
	}
	
	int offset = GameConfGetOffset(config, "GiveNamedItem");
	if (offset == -1)
	{
		CloseHandle(config);
		LogError("Unable to find offset 'GiveNamedItem' in game data 'sdktools.games'");
		return false;
	}
	
	/* POST HOOK */
	s_hGiveNamedItemPost = DHookCreate(offset, HookType_Entity, ReturnType_CBaseEntity, ThisPointer_CBaseEntity, OnGiveNamedItemPost);
	if (s_hGiveNamedItemPost == INVALID_HANDLE)
	{
		CloseHandle(config);
		LogError("Unable to post hook 'int CCSPlayer::GiveNamedItem(char const*, int, CEconItemView*, bool)'");
		return false;
	}
	
	DHookAddParam(s_hGiveNamedItemPost, HookParamType_CharPtr, -1, DHookPass_ByVal);
	DHookAddParam(s_hGiveNamedItemPost, HookParamType_Int, -1, DHookPass_ByVal);
	DHookAddParam(s_hGiveNamedItemPost, HookParamType_Int, -1, DHookPass_ByVal);
	DHookAddParam(s_hGiveNamedItemPost, HookParamType_Bool, -1, DHookPass_ByVal);
	
	/* PRE HOOK */
	s_hGiveNamedItem = DHookCreate(offset, HookType_Entity, ReturnType_CBaseEntity, ThisPointer_CBaseEntity, OnGiveNamedItemPre);
	if (s_hGiveNamedItem == INVALID_HANDLE)
	{
		CloseHandle(config);
		LogError("Unable to hook 'int CCSPlayer::GiveNamedItem(char const*, int, CEconItemView*, bool)'");
		return false;
	}
	
	DHookAddParam(s_hGiveNamedItem, HookParamType_CharPtr, -1, DHookPass_ByVal);
	DHookAddParam(s_hGiveNamedItem, HookParamType_Int, -1, DHookPass_ByVal);
	DHookAddParam(s_hGiveNamedItem, HookParamType_Int, -1, DHookPass_ByVal);
	DHookAddParam(s_hGiveNamedItem, HookParamType_Bool, -1, DHookPass_ByVal);
	return true;
}

/***************************************************
 * HOSTIES SUPPORT STUFF
 **************************************************/
public void OnAllPluginsLoaded()
{
	s_bHostiesLoaded = LibraryExists("lastrequest");
}

/***************************************************
 * EVENT STUFF
 **************************************************/
public void OnConfigsExecuted()
{
	LoadConvars();
}

public void OnMapStart()
{
	if (s_hMapWeapons != null)
		ClearArray(s_hMapWeapons);
	else
		s_hMapWeapons = CreateArray();
	
	for (int client = 1; client < MaxClients; client++)
	{
		if (!IsClientInGame(client))
			continue;
			
		if (!IsClientAuthorized(client))
			continue;
			
		OnClientPutInServer(client);
	}
}

public void OnClientPutInServer(int client)
{
	if (IsFakeClient(client))
		return;
		
	DHookEntity(s_hGiveNamedItem, false, client);
	DHookEntity(s_hGiveNamedItemPost, true, client);
	SDKHook(client, SDKHook_WeaponEquipPost, OnPostWeaponEquip);
}

public void OnClientDisconnect(int client)
{
	if (IsFakeClient(client))
		return;
		
	SDKUnhook(client, SDKHook_WeaponEquipPost, OnPostWeaponEquip);
}

public MRESReturn OnGiveNamedItemPre(int client, Handle hReturn, Handle hParams)
{
	if (!s_bEnable)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Plugin is disabled");
		return MRES_Ignored;
	}
	
	s_TeamWasSwitched = false;
	s_HookInUse = true;
	char classname[64];
	DHookGetParamString(hParams, 1, classname, sizeof(classname));
	
	if (s_bDebugMessages)
		PrintToConsole(client, "[AWS] OnGiveNamedItemPre(int client, char[] classname='%s')", classname);
	
	int itemdefinition = GetItemDefinitionByClassname(classname);
	
	if (itemdefinition == -1)
		return MRES_Ignored;
	
	if (IsItemDefinitionKnife(itemdefinition))
		return MRES_Ignored;
		
	int weaponteam = GetWeaponTeamByItemDefinition(itemdefinition);
	
	if (s_bDebugMessages)
		PrintToConsole(client, "[AWS] -> Item definition team: %d", weaponteam);
	
	if (weaponteam == CS_TEAM_NONE)
		return MRES_Ignored;
		
	s_OriginalClientTeam = GetEntProp(client, Prop_Data, "m_iTeamNum");
	
	if (s_OriginalClientTeam == weaponteam)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Skipped, player on correct team");
		return MRES_Ignored;
	}
		
	SetEntProp(client, Prop_Data, "m_iTeamNum", weaponteam);
	s_TeamWasSwitched = true;
	
	if (s_bDebugMessages)
		PrintToConsole(client, "[AWS] -> Player.m_iTeamNum set to %d", weaponteam);
	return MRES_Ignored;
}

public MRESReturn OnGiveNamedItemPost(int client, Handle hReturn, Handle hParams)
{
	if (s_bDebugMessages)
		PrintToConsole(client, "[AWS] OnGiveNamedItemPost(int client, char[] classname)");
		
	if (!s_bEnable)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Plugin is disabled");
		return MRES_Ignored;
	}
	
	if (!s_TeamWasSwitched)
	{
		s_HookInUse = false;
		return MRES_Ignored;
	}
	
	s_TeamWasSwitched = false;
	SetEntProp(client, Prop_Data, "m_iTeamNum", s_OriginalClientTeam);
	
	if (s_bDebugMessages)
		PrintToConsole(client, "[AWS] -> Player.m_iTeamNum set to %d", s_OriginalClientTeam);
	s_HookInUse = false;
	return MRES_Ignored;
}

public Action OnPostWeaponEquip(int client, int weapon)
{
	if (s_HookInUse)
		return Plugin_Continue;
		
	if (s_bDebugMessages)
		PrintToConsole(client, "[AWS] OnPostWeaponEquip(weapon=%d)", weapon);
	
	if (!s_bEnable)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Plugin is disabled");
		return Plugin_Continue;
	}
	
	if (s_bSkipMapWeapons)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Skip Map Weapons is enabled");
		return Plugin_Continue;
	}
	
	// Skip utilities
	int itemdefinition = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	if (itemdefinition == 43 || itemdefinition == 44 || itemdefinition == 45 || 
		itemdefinition == 46 || itemdefinition == 47 || itemdefinition == 48)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Skipped: IsUtility(defindex=%d)", itemdefinition);
		return Plugin_Continue;
	}

	// Check for map weapon
	if (!IsMapWeapon(weapon, true))
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Skipped: IsMapWeapon(weapon=%d)==false", weapon);
		return Plugin_Continue;
	}
	
	// remake weapon string for m4a1_silencer, usp_silencer, cz75a and revolver
	char classname[64];
	switch (itemdefinition)
	{
		case 60:
		{
			if (s_bDebugMessages)
				PrintToConsole(client, "[SM] -> Index 60: Classname reset to: weapon_m4a1_silencer from: %s", classname);
			classname = "weapon_m4a1_silencer";
		}
		case 61:
		{
			if (s_bDebugMessages)
				PrintToConsole(client, "[SM] -> Index 61: Classname reset to: weapon_usp_silencer from: %s", classname);
			classname = "weapon_usp_silencer";
		}
		case 63:
		{
			if (s_bDebugMessages)
				PrintToConsole(client, "[SM] -> Index 63: Classname reset to: weapon_cz75a from: %s", classname);
			classname = "weapon_cz75a";
		}
		case 64:
		{
			if (s_bDebugMessages)
				PrintToConsole(client, "[SM] -> Index 64: Classname reset to: weapon_revolver from: %s", classname);
			classname = "weapon_revolver";
		}
		default:
		{
			GetEdictClassname(weapon, classname, sizeof(classname));
		}
	}
	
	if (s_bDebugMessages)
		PrintToServer("[AWS] OnEntityClearedFromMapWeapons(entity=%d, classname=%s, mapweaponarraysize=%d)", weapon, classname, GetArraySize(s_hMapWeapons));
	
	// Skip if hosties is loaded and client is in last request
	if (s_bHostiesLoaded)
		if (IsClientInLastRequest(client))
			return Plugin_Continue;
	
	// Skip if previously owned
	int m_hPrevOwner = GetEntProp(weapon, Prop_Send, "m_hPrevOwner");
	if (m_hPrevOwner > 0)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Skipped: m_hPrevOwner == %d", m_hPrevOwner);
		return Plugin_Continue;
	}
		
	// Skip if the weapon is named while CvarSkipNamedWeapons is enabled
	if (s_bSkipNamedWeapons)
	{
		char entname[64];
		GetEntPropString(weapon, Prop_Data, "m_iName", entname, sizeof(entname));
		if (!StrEqual(entname, ""))
		{
			if (s_bDebugMessages)
				PrintToConsole(client, "[AWS] -> Skipped: m_iName == %s", entname);
			return Plugin_Continue;
		}
	}
	
	// Debug logging
	if (s_bDebugMessages)
		PrintToConsole(client, "[AWS] Respawning %s (defindex=%d)", classname, itemdefinition);
	
	// Processing weapon switch
	// Remove current weapon from player
	AcceptEntityInput(weapon, "Kill");
	
	// Give player new weapon so the GNI hook can set the correct team inside the GiveNamedItemEx call
	GivePlayerItem(client, classname);
	return Plugin_Handled;
}

/***************************************************
 * MAP WEAPON STUFF
 **************************************************/
stock bool IsMapWeapon(int entity, bool remove=false)
{
	if (s_hMapWeapons == null)
		return false;
		
	int count = GetArraySize(s_hMapWeapons);
	for (int i = 0; i < count; i++)
	{
		if (GetArrayCell(s_hMapWeapons, i) != entity)
			continue;
		
		if (remove)
			RemoveFromArray(s_hMapWeapons, i);
		return true;
	}
	return false;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	// Skip if plugin is disabled
	if (!s_bEnable)
		return;
	
	// Skip if map weapons are not being replaced
	if (s_bSkipMapWeapons)
		return;
	
	// Skip if hook is in use!
	if (s_HookInUse)
		return;
		
	// Skip if map weapons array is null
	if (s_hMapWeapons == null)
		return;
		
	// Skip if GNI doesn't know the item definition
	int itemdefinition = GetItemDefinitionByClassname(classname);
	if (itemdefinition == -1) return;
	
	// Skip knives
	if (IsItemDefinitionKnife(itemdefinition))
		return;
	
	// Store the entity index as this is a map weapon
	PushArrayCell(s_hMapWeapons, entity);
	
	if (s_bDebugMessages)
		PrintToServer("[AWS] OnEntityCreated(entity=%d, classname=%s, itemdefinition=%d, mapweaponarraysize=%d)", entity, classname, itemdefinition, GetArraySize(s_hMapWeapons));
}

public void OnEntityDestroyed(int entity)
{
	if (IsMapWeapon(entity, true) && s_bDebugMessages)
		PrintToServer("[AWS] OnEntityDestroyed(entity=%d, mapweaponarraysize=%d)", entity, GetArraySize(s_hMapWeapons));
}

/***************************************************
 * ITEMS_GAME DATA STUFF
 **************************************************/
static Handle s_hWeaponClassname = null;
static Handle s_hWeaponItemDefinition = null;
static Handle s_hWeaponIsKnife = null;
static Handle s_hWeaponTeam = null;

stock int GetWeaponIndexOfClassname(const char[] classname)
{
	int count = GetArraySize(s_hWeaponClassname);
	char buffer[128];
	for (int i = 0; i < count; i++)
	{
		GetArrayString(s_hWeaponClassname, i, buffer, sizeof(buffer));
		if (StrEqual(buffer, classname))
			return i;
	}
	return -1;
}

public int GetItemDefinitionByClassname(const char[] classname)
{
	if (StrEqual(classname, "weapon_knife"))
		return 42;
	if (StrEqual(classname, "weapon_knife_t"))
		return 59;
	
	int count = GetArraySize(s_hWeaponItemDefinition);
	char buffer[64];
	for (int i = 0; i < count; i++)
	{
		GetArrayString(s_hWeaponClassname, i, buffer, sizeof(buffer));
		if (StrEqual(classname, buffer))
		{
			return GetArrayCell(s_hWeaponItemDefinition, i);
		}
	}
	return -1;
}

static int GetWeaponTeamByItemDefinition(int itemdefinition)
{
	// weapon_knife
	if (itemdefinition == 42)
		return CS_TEAM_CT;
	
	// weapon_knife_t
	if (itemdefinition == 59)
		return CS_TEAM_T;
	
	int count = GetArraySize(s_hWeaponTeam);
	for (int i = 0; i < count; i++)
	{
		if (GetArrayCell(s_hWeaponItemDefinition, i) == itemdefinition)
			return GetArrayCell(s_hWeaponTeam, i);
	}
	return CS_TEAM_NONE;
}

static bool IsItemDefinitionKnife(int itemdefinition)
{
	if (itemdefinition == 42 || itemdefinition == 59)
		return true;

	int count = GetArraySize(s_hWeaponItemDefinition);
	for (int i = 0; i < count; i++)
	{
		if (GetArrayCell(s_hWeaponItemDefinition, i) == itemdefinition)
		{
			if (GetArrayCell(s_hWeaponIsKnife, i))
				return true;
			else
				return false;
		}
	}
	return false;
}

stock bool BuildItems()
{
	Handle kv = CreateKeyValues("items_game");
	if (!FileToKeyValues(kv, "scripts/items/items_game.txt"))
	{
		LogError("Unable to open/read file at 'scripts/items/items_game.txt'.");
		return false;
	}
	
	if (!KvJumpToKey(kv, "prefabs"))
		return false;
	
	if (!KvGotoFirstSubKey(kv, false))
		return false;
	
	s_hWeaponClassname = CreateArray(128);
	s_hWeaponItemDefinition = CreateArray();
	s_hWeaponIsKnife = CreateArray();
	s_hWeaponTeam = CreateArray();
	
	// Loop through all prefabs
	char buffer[128];
	char classname[128];
	int len;
	do
	{
		// Get prefab value and check for weapon_base
		KvGetString(kv, "prefab", buffer, sizeof(buffer));
		if (StrEqual(buffer, "weapon_base") || StrEqual(buffer, "primary") || StrEqual(buffer, "melee"))
		{
			// This conditions are ignored
		}
		else
		{
			// Get the section name and check if its a weapon
			KvGetSectionName(kv, buffer, sizeof(buffer));
			if (StrContains(buffer, "weapon_") == 0)
			{
				// Remove _prefab to get the classname
				len = StrContains(buffer, "_prefab");
				if (len == -1) continue;
				strcopy(classname, len+1, buffer);
				
				// Store data
				PushArrayString(s_hWeaponClassname, classname);
				PushArrayCell(s_hWeaponItemDefinition, -1);
				PushArrayCell(s_hWeaponIsKnife, 0);
				
				if (!KvJumpToKey(kv, "used_by_classes"))
				{
					PushArrayCell(s_hWeaponTeam, CS_TEAM_NONE);
					continue;
				}
				
				int team_ct = KvGetNum(kv, "counter-terrorists");
				int team_t = KvGetNum(kv, "terrorists");
				
				if (team_ct)
				{
					if (team_t)
						PushArrayCell(s_hWeaponTeam, CS_TEAM_NONE);
					else
						PushArrayCell(s_hWeaponTeam, CS_TEAM_CT);
				}
				else if (team_t)
					PushArrayCell(s_hWeaponTeam, CS_TEAM_T);
				else
					PushArrayCell(s_hWeaponTeam, CS_TEAM_NONE);
					
				KvGoBack(kv);
			}
		}
	} while (KvGotoNextKey(kv));
	
	KvGoBack(kv);
	KvGoBack(kv);
	
	if (!KvJumpToKey(kv, "items"))
		return false;
	
	if (!KvGotoFirstSubKey(kv, false))
		return false;

	char weapondefinition[12]; char weaponclassname[128]; char weaponprefab[128];
	do
	{
		KvGetString(kv, "name", weaponclassname, sizeof(weaponclassname));
		int index = GetWeaponIndexOfClassname(weaponclassname);
		
		// This item was not listed in the prefabs
		if (index == -1)
		{
			KvGetString(kv, "prefab", weaponprefab, sizeof(weaponprefab));
			
			// Skip knives
			if (!StrEqual(weaponprefab, "melee") && !StrEqual(weaponprefab, "melee_unusual"))
				continue;
			
			// Get weapon data
			KvGetSectionName(kv, weapondefinition, sizeof(weapondefinition));
			
			// Store weapon data
			PushArrayString(s_hWeaponClassname, weaponclassname);
			PushArrayCell(s_hWeaponItemDefinition, StringToInt(weapondefinition));
			PushArrayCell(s_hWeaponIsKnife, 1); // only knives are detected here
			PushArrayCell(s_hWeaponTeam, CS_TEAM_NONE);
		}
		
		// This item was found in prefabs. We just need to store the weapon index
		else
		{
			// Get weapon data
			KvGetSectionName(kv, weapondefinition, sizeof(weapondefinition));
			
			// Set weapon data
			SetArrayCell(s_hWeaponItemDefinition, index, StringToInt(weapondefinition));
		}
	
	} while (KvGotoNextKey(kv));

	return true;
}