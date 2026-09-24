local _, Embolsao = ...

-- Any key nobody has translated yet just falls back to itself (the key),
-- so enUS.lua is expected to define every real string; locale files only
-- need to override the keys they actually translate, and an unsupported
-- client locale silently ends up using the enUS strings.
Embolsao.L = setmetatable({}, {
    __index = function(t, key)
        rawset(t, key, key)
        return key
    end,
})
