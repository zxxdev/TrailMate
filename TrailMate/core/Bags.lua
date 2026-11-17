-- Bag advisor: each item gets "sell", "keep" or "auction", with a reason.
-- It only advises: it never sells, buys or destroys anything. Pure Lua 5.1.
--
-- Item: { itemID, count, quality (0 grey .. 5), sellPrice (copper each),
--         classID, isQuest, isBound, equipLoc, itemLevel, equippedLevel }
-- equippedLevel is the item level worn in the same slot, or nil.

local _, ns = ...

local Bags = {}
ns.Bags = Bags

-- Item class ids of the modern client.
local CLASS_CONSUMABLE, CLASS_TRADEGOODS, CLASS_QUEST = 0, 7, 12

-- Inventory slot for each equip location (for "is it worse than mine?").
Bags.SLOT_FOR_EQUIPLOC = {
  INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_BODY = 4,
  INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7,
  INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11,
  INVTYPE_TRINKET = 13, INVTYPE_CLOAK = 15, INVTYPE_WEAPON = 16,
  INVTYPE_WEAPONMAINHAND = 16, INVTYPE_2HWEAPON = 16, INVTYPE_SHIELD = 17,
  INVTYPE_WEAPONOFFHAND = 17, INVTYPE_HOLDABLE = 17, INVTYPE_RANGED = 18,
  INVTYPE_RANGEDRIGHT = 18, INVTYPE_THROWN = 18,
}

local function isGear(item)
  return type(item.equipLoc) == "string" and Bags.SLOT_FOR_EQUIPLOC[item.equipLoc] ~= nil
end

--- Verdict and reason for one item.
function Bags.adviseItem(item, ctx, L)
  local prefs = ctx.prefs or {}
  local canAuction = ctx.auctionAvailable ~= false
  local price = item.sellPrice or 0

  if prefs.keep and prefs.keep[item.itemID] then
    return "keep", L["On your keep list"]
  end
  if item.isQuest or item.classID == CLASS_QUEST then
    return "keep", L["Quest item"]
  end
  if item.quality == 0 then
    if price > 0 then
      return "sell", L["Junk"]
    end
    return "keep", L["No vendor value"]
  end
  if item.classID == CLASS_CONSUMABLE then
    return "keep", L["Consumable"]
  end
  if isGear(item) then
    if not item.isBound and (item.quality or 0) >= 2 and canAuction then
      return "auction", L["Unbound green or better: usually worth more at the auction house"]
    end
    if item.equippedLevel and item.itemLevel and item.itemLevel <= item.equippedLevel and price > 0 then
      return "sell", L["Lower item level than what you wear (rough guide)"]
    end
    return "keep", L["Possible upgrade: check it"]
  end
  if item.classID == CLASS_TRADEGOODS and not item.isBound and canAuction then
    return "auction", L["Trade goods sell well at the auction house"]
  end
  return "keep", L["No rule for this item: your call"]
end

--- Advice for a list of items. Returns the list of
--- { item, verdict, reason } and the vendor value of the "sell" ones.
function Bags.advise(items, ctx, L)
  local results, value = {}, 0
  for _, item in ipairs(items) do
    local verdict, reason = Bags.adviseItem(item, ctx, L)
    results[#results + 1] = { item = item, verdict = verdict, reason = reason }
    if verdict == "sell" then
      value = value + (item.sellPrice or 0) * (item.count or 1)
    end
  end
  return results, value
end

--- True when the bags are nearly full and it is time to go back to a vendor.
function Bags.shouldReturn(free, prefs)
  local limit = (prefs and prefs.minFreeSlots) or 2
  return type(free) == "number" and free <= limit
end
