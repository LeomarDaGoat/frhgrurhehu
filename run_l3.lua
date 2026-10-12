-- Project Radium L3 host runner
-- Run:
--   lune.exe run run_l3.lua input.lua output.lua [options]

local process = require("@lune/process")
local fs = require("@lune/fs")
local net = require("@lune/net")
local serde = require("@lune/serde")
local luau = require("@lune/luau")

local CORE_PATH = "l3.lua"

local source = fs.readFile(CORE_PATH)

local env = {
    __RADIUM_HOST = {
        process = process,
        fs = fs,
        net = net,
        serde = serde,
        luau = luau,
    },
}

setmetatable(env, {
    __index = _G,
})

local fn, err = luau.load(source, {
    environment = env,
    chunkName = "=ProjectRadiumL3Core",
})

if not fn then
    error(err, 0)
end

local ok, runtimeErr = pcall(fn)

if not ok then
    error(runtimeErr, 0)
end
