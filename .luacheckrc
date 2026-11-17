-- luacheck configuration. The game runs Lua 5.1.
std = "lua51"
max_line_length = 120
exclude_files = { ".luarocks/", "lua_modules/" }

-- Saved variables and slash command globals the addon owns.
globals = {
  "TrailMateDB", "TrailMateCharDB",
  "SLASH_TRAILMATE1", "SLASH_TRAILMATE2", "SlashCmdList",
}

-- Game API the addon reads. Listed one by one on purpose: a typo in a global
-- name is exactly what luacheck should catch.
read_globals = {
  "BackdropTemplateMixin", "C_AddOns", "C_Container", "C_Item", "C_Map", "C_QuestLog",
  "C_SuperTrack", "C_Timer", "C_TooltipInfo", "CreateFrame", "GetAddOnMetadata",
  "GetBuildInfo", "GetContainerItemInfo", "GetContainerItemQuestInfo",
  "GetContainerNumFreeSlots", "GetContainerNumSlots", "GetInventoryItemID", "GetItemInfo",
  "GetLocale", "GetMoney", "GetNumQuestLogEntries", "GetNumTrainerServices",
  "GetQuestLogTitle", "GetTrainerServiceCost", "GetTrainerServiceInfo",
  "GetTrainerServiceLevelReq", "IsQuestFlaggedCompleted", "NUM_BAG_SLOTS",
  "NUM_REAGENTBAG_SLOTS", "QuestPOIGetIconInfo", "TomTom", "UIParent", "UiMapPoint",
  "UnitClass", "UnitLevel", "UnitXP", "UnitXPMax", "issecretvalue", "time",
}

files["spec/"] = { std = "+busted" }
