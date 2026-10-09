local ADDON_NAME, Embolsao = ...

-- Public API for other addons: what the OTHER characters carry and keep in their banks, from the copies every character
-- saves account-wide (BankTooltip.lua's SaveCharacterItems: at logout and after every bag change). It is a global table so
-- that an addon can use it without Embolsao's private namespace, and it never hands out Embolsao's own tables (only copies
-- and numbers), so the way things are saved can change without breaking whoever calls it.
--
--   EmbolsaoAPI.version                     the API's version (1)
--   EmbolsaoAPI.GetCharacters()             { { key =, name =, class = "MAGE", time = }, ... }  the other characters, by name
--   EmbolsaoAPI.GetOthersItemCount(itemID)  bags, bank: how many of the item the other characters have in all
--   EmbolsaoAPI.GetItemHolders(itemID)      { { key =, name =, class =, bags =, bank = }, ... }  who has it (only those with
--                                           some), by name
--
-- (The character playing is never in the lists: its own items are live, ask the game.) Characters appear once they have
-- logged out, or entered the world, with a version of Embolsao that saves them.

local API = { version = 1 }

local function byName(a, b) return a.name < b.name end

function API.GetCharacters()
    local result = {}
    for _, character in ipairs(Embolsao:GetOtherCharacters()) do
        result[#result + 1] = {
            key = character.key,
            name = Embolsao:GetCharacterDisplayName(character.key, character.info),
            class = character.info.class,
            time = character.info.time,
        }
    end
    table.sort(result, byName)
    return result
end

function API.GetOthersItemCount(itemID)
    local bags, bank = 0, 0
    if type(itemID) ~= "number" then return bags, bank end
    for _, character in ipairs(Embolsao:GetOtherCharacters()) do
        local info = character.info
        bags = bags + ((info.bags and info.bags[itemID]) or 0)
        bank = bank + ((info.bank and info.bank[itemID]) or 0)
    end
    return bags, bank
end

function API.GetItemHolders(itemID)
    local result = {}
    if type(itemID) ~= "number" then return result end
    for _, character in ipairs(Embolsao:GetOtherCharacters()) do
        local info = character.info
        local inBags = (info.bags and info.bags[itemID]) or 0
        local inBank = (info.bank and info.bank[itemID]) or 0
        if inBags > 0 or inBank > 0 then
            result[#result + 1] = {
                key = character.key,
                name = Embolsao:GetCharacterDisplayName(character.key, info),
                class = info.class,
                bags = inBags,
                bank = inBank,
            }
        end
    end
    table.sort(result, byName)
    return result
end

EmbolsaoAPI = API
