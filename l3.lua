-- Project Radium L3 v3.17 / Madium v2.0.0 compatibility profile
-- Roblox/Luau compatibility core.
--
-- Host capabilities are injected by run_l3.lua.
-- This file contains no host-module imports.
--
-- Optional profile values:
--   --username <name>
--   --display-name <name>
--   --user-id <number>
--   --place-id <number>
--   --game-id <number>
--   --place-version <number>
--   --api-cache <path>
--   --refresh-api
--
-- Notes:
--   * Uses Roblox-Client-Tracker Full-API-Dump.json when available.
--   * Target code never receives host filesystem/network/process/module access.
--   * loadstring compiles back into the same sandbox.
--   * This logger does not forge native "[C]" identities or hide logger stack frames.

local host = __RADIUM_HOST
if type(host) ~= "table" then
    error("Project Radium L3 must be started through run_l3.lua", 0)
end

local process = assert(host.process, "missing host.process")
local fs = assert(host.fs, "missing host.fs")
local net = assert(host.net, "missing host.net")
local serde = assert(host.serde, "missing host.serde")
local luau = assert(host.luau, "missing host.luau")

local hostPrint = print
local hostWarn = warn or print
local hostType = type
local hostTypeof = typeof
local hostTostring = tostring
local hostPcall = pcall
local hostXpcall = xpcall
local hostError = error
local hostAssert = assert
local hostPairs = pairs
local hostIpairs = ipairs
local hostNext = next
local hostSelect = select
local hostRawget = rawget
local hostRawset = rawset
local hostGetmetatable = getmetatable
local hostSetmetatable = setmetatable
local hostGetfenv = getfenv
local hostSetfenv = setfenv
local hostUnpack = table.unpack or unpack
local hostClock = os.clock

local API_URL =
    "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/Full-API-Dump.json"

local LIMITS = {
    MAX_OUTPUT_LINES = 30000,
    MAX_PROXIES = 60000,
    MAX_DYNAMIC_SOURCE = 2 * 1024 * 1024,
    MAX_EXEC_SECONDS = 180,
    MAX_REPEAT = 100,
}

local CONFIG = {
    input = nil,
    output = "output_l3.lua",
    sandboxRoot = "radium_l3_fs",
    username = "Player",
    displayName = "Player",
    userId = 1,
    placeId = 1818,
    gameId = 6767,
    placeVersion = 1,
    apiCache = "radium_api_dump.json",
    refreshApi = false,
}

do
    local positional = {}
    local args = process.args
    local i = 1

    while i <= #args do
        local arg = args[i]

        if arg == "--username" then
            i += 1
            CONFIG.username = args[i] or CONFIG.username
        elseif arg == "--display-name" then
            i += 1
            CONFIG.displayName = args[i] or CONFIG.displayName
        elseif arg == "--user-id" then
            i += 1
            CONFIG.userId = tonumber(args[i]) or CONFIG.userId
        elseif arg == "--place-id" then
            i += 1
            CONFIG.placeId = tonumber(args[i]) or CONFIG.placeId
        elseif arg == "--game-id" then
            i += 1
            CONFIG.gameId = tonumber(args[i]) or CONFIG.gameId
        elseif arg == "--place-version" then
            i += 1
            CONFIG.placeVersion = tonumber(args[i]) or CONFIG.placeVersion
        elseif arg == "--api-cache" then
            i += 1
            CONFIG.apiCache = args[i] or CONFIG.apiCache
        elseif arg == "--refresh-api" then
            CONFIG.refreshApi = true
        else
            positional[#positional + 1] = arg
        end

        i += 1
    end

    CONFIG.input = positional[1]
    CONFIG.output = positional[2] or CONFIG.output
end

if not CONFIG.input then
    hostPrint("Project Radium L3")
    hostPrint("usage: lune.exe run l3.lua <input.lua> [output.lua] [options]")
    return
end

local function safeRead(path)
    local ok, result = hostPcall(fs.readFile, path)
    if ok and hostType(result) == "string" then
        return result
    end
    return nil
end

local function safeWrite(path, content)
    local ok, err = hostPcall(fs.writeFile, path, content)
    if not ok then
        hostWarn("Project Radium L3 failed to write " .. hostTostring(path) .. ": " .. hostTostring(err))
        return false
    end
    return true
end

local function responseBodyToString(body)
    if hostType(body) == "string" then
        return body
    end

    if body ~= nil and buffer and hostType(buffer.tostring) == "function" then
        local ok, value = hostPcall(buffer.tostring, body)
        if ok and hostType(value) == "string" then
            return value
        end
    end

    return nil
end

local function safeHttpField(response, key)
    local ok, value = hostPcall(function()
        return response[key]
    end)

    if ok then
        return value
    end

    return nil
end

local function buildHttpHeaders()
    return {
        ["Accept"] = "*/*",
        ["Accept-Encoding"] = "gzip, deflate",
        ["User-Agent"] = "Madium/2.0.0",
        ["Roblox-Game-Id"] = hostTostring(CONFIG.gameId),
        ["Roblox-Place-Id"] = hostTostring(CONFIG.placeId),
        ["Roblox-Session-Id"] = string.format(
            '{"PlaceId":"%s","GameId":"%s"}',
            hostTostring(CONFIG.placeId),
            hostTostring(CONFIG.gameId)
        ),
    }
end

local function requestUrl(url)
    url = hostTostring(url or "")

    if not url:match("^https?://") then
        return nil, "HttpGet only supports http:// and https:// URLs"
    end

    local request = net.request or (net.http and net.http.request)
    if hostType(request) ~= "function" then
        return nil, "HTTP request function is unavailable"
    end

    local response = nil
    local requestError = nil

    local ok, result = hostPcall(request, {
        url = url,
        method = "GET",
        headers = buildHttpHeaders(),
    })

    if ok then
        response = result
    else
        requestError = result

        -- Compatibility fallback for hosts exposing request(url).
        local ok2, result2 = hostPcall(request, url)

        if ok2 then
            response = result2
            requestError = nil
        else
            requestError = result2
        end
    end

    if response == nil then
        return nil, "HTTP request failed: " .. hostTostring(requestError or "no response")
    end

    if hostType(response) == "string" then
        return response
    end

    -- Do not require the response object itself to report type "table".
    -- Some Lune builds expose response objects through userdata/proxy values.
    local status =
        tonumber(safeHttpField(response, "statusCode"))
        or tonumber(safeHttpField(response, "status"))
        or tonumber(safeHttpField(response, "StatusCode"))
        or tonumber(safeHttpField(response, "Status"))

    if status and (status < 200 or status >= 400) then
        return nil, "HTTP " .. hostTostring(status)
    end

    local body =
        safeHttpField(response, "body")
        or safeHttpField(response, "Body")
        or safeHttpField(response, "data")
        or safeHttpField(response, "Data")

    local source = responseBodyToString(body)

    if source == nil then
        -- Some hosts return the body object directly.
        source = responseBodyToString(response)
    end

    if source == nil then
        return nil, "HTTP response body is not readable text"
    end

    return source
end

local function loadApiDump()
    local cached = nil

    if not CONFIG.refreshApi then
        cached = safeRead(CONFIG.apiCache)
    end

    if cached then
        return cached, "cache"
    end

    local downloaded = requestUrl(API_URL)
    if downloaded and #downloaded > 1000 then
        safeWrite(CONFIG.apiCache, downloaded)
        return downloaded, "network"
    end

    cached = safeRead(CONFIG.apiCache)
    if cached then
        return cached, "cache"
    end

    return nil, "fallback"
end

local apiText, apiSource = loadApiDump()
local apiDump = nil

if apiText then
    local ok, decoded = hostPcall(serde.decode, "json", apiText)
    if ok and hostType(decoded) == "table" then
        apiDump = decoded
    end
end

local classInfo = {}
local enumInfo = {}
local serviceNames = {}

local function tagContains(tags, wanted)
    if hostType(tags) ~= "table" then
        return false
    end

    for _, tag in hostPairs(tags) do
        if tag == wanted then
            return true
        end
    end

    return false
end

if apiDump then
    if hostType(apiDump.Classes) == "table" then
        for _, class in hostIpairs(apiDump.Classes) do
            if hostType(class) == "table" and hostType(class.Name) == "string" then
                local members = {}

                if hostType(class.Members) == "table" then
                    for _, member in hostIpairs(class.Members) do
                        if hostType(member) == "table" and hostType(member.Name) == "string" then
                            members[member.Name] = member
                        end
                    end
                end

                classInfo[class.Name] = {
                    Name = class.Name,
                    Superclass = class.Superclass,
                    Tags = class.Tags,
                    Members = members,
                }

                if tagContains(class.Tags, "Service") then
                    serviceNames[class.Name] = true
                end
            end
        end
    end

    if hostType(apiDump.Enums) == "table" then
        for _, enum in hostIpairs(apiDump.Enums) do
            if hostType(enum) == "table" and hostType(enum.Name) == "string" then
                local items = {}

                if hostType(enum.Items) == "table" then
                    for _, item in hostIpairs(enum.Items) do
                        if hostType(item) == "table" and hostType(item.Name) == "string" then
                            items[item.Name] = item.Value
                        end
                    end
                end

                enumInfo[enum.Name] = items
            end
        end
    end
end

local fallbackEnums = {
    NormalId = {Right=0,Top=1,Back=2,Left=3,Bottom=4,Front=5},
    Axis = {X=0,Y=1,Z=2},
    InitialDockState = {Top=0,Bottom=1,Left=2,Right=3,Float=4},
    EnviromentalPhysicsThrottle = {DefaultAuto=0,Disabled=1,Always=2},
    EasingStyle = {Linear=0,Sine=1,Back=2,Quad=3,Quart=4,Quint=5,Bounce=6,Elastic=7,Exponential=8,Circular=9,Cubic=10},
    EasingDirection = {In=0,Out=1,InOut=2},
    PlaybackState = {Begin=0,Delayed=1,Playing=2,Paused=3,Completed=4,Cancelled=5},
    TextTruncate = {None=0,AtEnd=1,SplitWord=2},
    TextXAlignment = {Left=0,Right=1,Center=2},
    TextYAlignment = {Top=0,Center=1,Bottom=2},
    ActuatorType = {None=0,Motor=1,Servo=2},
    HumanoidStateType = {Running=8,Jumping=3,Freefall=5,Landed=7,Dead=15},
    RunState = {Stopped=0,Running=1,Paused=2},
    CreatorType = {User=0,Group=1},
    PathStatus = {Success=0,NoPath=1},
    PathWaypointAction = {Walk=0,Jump=1,Custom=2},
    RaycastFilterType = {Exclude=0,Include=1},
    KeyInterpolationMode = {Constant=0,Linear=1,Cubic=2},
    CatalogSortType = {Relevance=0,Favorited=1,Sales=2,Updated=3,PriceAsc=4,PriceDesc=5},
    AssetFetchStatus = {Success=0,Failure=1,Timeout=2,None=3,Loading=4},
    ImageCombineType = {BlendSourceOver=0,Overwrite=1,Add=2,Multiply=3,AlphaBlend=4},
    ImageAlphaType = {Default=0,Premultiplied=1},
    ResamplerMode = {Default=0,Pixelated=1},
    AntiAliasing = {Default=0,Disabled=1},
    ReverbType = {NoReverb=0},
    FontWeight = {Thin=100,ExtraLight=200,Light=300,Regular=400,Medium=500,SemiBold=600,Bold=700,ExtraBold=800,Heavy=900},
    FontStyle = {Normal=0,Italic=1},
    MembershipType = {None=0,BuildersClub=1,TurboBuildersClub=2,OutrageousBuildersClub=3,Premium=4},
    AccessModifierType = {Allow=0,Deny=1},
    Font = {Legacy=0,Arial=1,ArialBold=2,SourceSans=3,SourceSansBold=4,SourceSansLight=5,SourceSansItalic=6},
    Material = {Plastic=256,SmoothPlastic=272,Neon=288,Wood=512,Concrete=816,Grass=1280},
    CatalogSortAggregation = {Past12Hours=0,PastDay=1,Past3Days=2,PastWeek=3,PastMonth=4,AllTime=5},
    AccessoryType = {
        Unknown=0,Hat=1,Hair=2,Face=3,Neck=4,Shoulder=5,Front=6,Back=7,Waist=8,
        TShirt=9,Shirt=10,Pants=11,Jacket=12,Sweater=13,Shorts=14,LeftShoe=15,
        RightShoe=16,DressSkirt=17,Eyebrow=18,Eyelash=19,Mood=20,DynamicHead=21
    },
    CatalogCategoryFilter = {None=0,Featured=1,Collectibles=2,CommunityCreations=3,Premium=4},
    CatalogSalesTypeFilter = {All=0,Collectibles=1,Premium=2},
}
for enumName, items in hostPairs(fallbackEnums) do
    if enumInfo[enumName] == nil then enumInfo[enumName] = items end
end

for _, service in hostIpairs({
    "Workspace",
    "Players",
    "RunService",
    "HttpService",
    "Lighting",
    "SoundService",
    "TweenService",
    "CollectionService",
    "MarketplaceService",
    "PhysicsService",
    "StarterPlayer",
    "StarterPack",
    "ReplicatedStorage",
    "ReplicatedFirst",
    "ServerStorage",
    "ServerScriptService",
    "Teams",
    "Stats",
    "ContentProvider",
    "AnimationClipProvider",
    "AvatarEditorService",
    "MemStorageService",
    "ContextActionService",
    "UserInputService",
    "PathfindingService",
    "Debris",
    "TeleportService",
    "TextChatService",
    "Chat",
    "GuiService",
    "CoreGui",
    "InsertService",
    "BadgeService",
    "GroupService",
    "PolicyService",
    "LocalizationService",
    "AssetService",
}) do
    serviceNames[service] = true
end

local output = {
    "-- Project Radium L3 v3.17",
    "-- api source: " .. apiSource,
    "",
}
local repeatCounts = {}
local objectNames = hostSetmetatable({}, { __mode = "k" })
local objectTypes = hostSetmetatable({}, { __mode = "k" })
local instanceStates = hostSetmetatable({}, { __mode = "k" })
local instanceChildren = hostSetmetatable({}, { __mode = "k" })
local signalCallbacks = hostSetmetatable({}, { __mode = "k" })
local proxyState = hostSetmetatable({}, { __mode = "k" })
local sharedTableFields = hostSetmetatable({}, { __mode = "k" })
local gameServiceAddedSignal = nil
local collectionTags
local proxyCount = 0
local varCounter = 0
local indent = 0
local virtualTime = 0
local runtimeStart = hostClock()

local function checkRuntime()
    if hostClock() - runtimeStart > LIMITS.MAX_EXEC_SECONDS then
        hostError("Project Radium L3 execution timeout", 0)
    end
end

local function pad()
    return string.rep("    ", indent)
end

local function quote(value)
    return string.format("%q", hostTostring(value))
end

local function newVar(prefix)
    varCounter += 1

    local base = hostTostring(prefix or "var")
    base = base:gsub("[^%w_]", "_")
    if base == "" then base = "var" end
    if base:match("^%d") then base = "_" .. base end

    local counterKey = "__radium_name_counter:" .. base
    local count = (repeatCounts[counterKey] or 0) + 1
    repeatCounts[counterKey] = count

    if count == 1 then
        return base
    end

    return base .. hostTostring(count)
end

local function emit(line)
    checkRuntime()

    if #output >= LIMITS.MAX_OUTPUT_LINES then
        return
    end

    line = pad() .. line
    local count = (repeatCounts[line] or 0) + 1
    repeatCounts[line] = count

    if count > LIMITS.MAX_REPEAT then
        return
    end

    output[#output + 1] = line
    hostPrint(line)
end

local function mark(value, name, typeName)
    if value ~= nil and (hostType(value) == "table" or hostType(value) == "userdata" or hostType(value) == "thread") then
        objectNames[value] = name

        if typeName then
            objectTypes[value] = typeName
        end
    end

    return value
end

local function repr(value)
    local t = hostType(value)

    if t == "string" then
        return quote(value)
    elseif t == "number" or t == "boolean" then
        return hostTostring(value)
    elseif t == "nil" then
        return "nil"
    elseif t == "function" then
        return "function(...) end"
    elseif objectNames[value] then
        return objectNames[value]
    end

    return hostTostring(value)
end

local function classMember(className, memberName)
    local current = className
    local seen = {}

    while current and not seen[current] do
        seen[current] = true
        local info = classInfo[current]

        if not info then
            break
        end

        local member = info.Members[memberName]
        if member then
            return member
        end

        current = info.Superclass
    end

    return nil
end

local function classIsA(className, wanted)
    if className == wanted or wanted == "Instance" then
        return true
    end

    local current = className
    local seen = {}

    while current and not seen[current] do
        if current == wanted then
            return true
        end

        seen[current] = true
        local info = classInfo[current]
        current = info and info.Superclass or nil
    end

    local fallback = {
        Part = "BasePart",
        MeshPart = "BasePart",
        SpawnLocation = "BasePart",
        WedgePart = "BasePart",
        CornerWedgePart = "BasePart",
        TrussPart = "BasePart",
        Seat = "BasePart",
        VehicleSeat = "BasePart",
        Model = "PVInstance",
        Camera = "PVInstance",
        Frame = "GuiObject",
        TextLabel = "GuiObject",
        TextButton = "GuiObject",
        TextBox = "GuiObject",
        ImageLabel = "GuiObject",
        ImageButton = "GuiObject",
        ScrollingFrame = "GuiObject",
    }

    current = className

    while fallback[current] do
        current = fallback[current]

        if current == wanted then
            return true
        end
    end

    return false
end

local enumTypeCache = {}
local enumItemCache = {}

local function makeEnumType(enumName)
    if enumTypeCache[enumName] then
        return enumTypeCache[enumName]
    end

    proxyCount += 1

    if proxyCount > LIMITS.MAX_PROXIES then
        hostError("Project Radium L3 proxy limit reached", 0)
    end

    local enumType = newproxy(true)
    local mt = hostGetmetatable(enumType)
    mark(enumType, "Enum." .. enumName, "Enum")

    mt.__index = function(_, key)
        if key == "GetEnumItems" then
            return function(selfEnum)
                if selfEnum ~= enumType then
                    hostError("Expected ':' not '.' calling GetEnumItems", 2)
                end

                local result = {}
                local known = enumInfo[enumName] or {}

                for itemName in hostPairs(known) do
                    result[#result + 1] = enumType[itemName]
                end

                table.sort(result, function(a, b)
                    return (a.Value or 0) < (b.Value or 0)
                end)

                return result
            end
        elseif key == "FromName" then
            -- Return a fresh closure on each lookup, matching EnumType method
            -- lookup semantics without fabricating native metadata.
            return function(selfEnum, wantedName)
                if selfEnum ~= enumType then
                    hostError("Expected ':' not '.' calling FromName", 2)
                end

                local known = enumInfo[enumName] or {}
                wantedName = hostTostring(wantedName)

                if known[wantedName] == nil then
                    return nil
                end

                return enumType[wantedName]
            end
        elseif key == "FromValue" then
            return function(selfEnum, wantedValue)
                if selfEnum ~= enumType then
                    hostError("Expected ':' not '.' calling FromValue", 2)
                end

                local known = enumInfo[enumName] or {}
                local numeric = tonumber(wantedValue)

                if numeric == nil then
                    return nil
                end

                for itemName, itemValue in hostPairs(known) do
                    if tonumber(itemValue) == numeric then
                        return enumType[itemName]
                    end
                end

                return nil
            end
        end

        local known = enumInfo[enumName]

        if known and known[key] == nil then
            hostError(hostTostring(key) .. " is not a valid member of Enum." .. enumName, 2)
        end

        local cacheKey = enumName .. "." .. hostTostring(key)

        if enumItemCache[cacheKey] then
            return enumItemCache[cacheKey]
        end

        local item = newproxy(true)
        local itemMt = hostGetmetatable(item)
        local itemValue = known and known[key] or 0
        mark(item, "Enum." .. cacheKey, "EnumItem")

        itemMt.__index = function(_, itemKey)
            if itemKey == "Name" then
                return hostTostring(key)
            elseif itemKey == "Value" then
                return itemValue
            elseif itemKey == "EnumType" then
                return enumType
            end

            return nil
        end

        itemMt.__newindex = function()
            hostError("attempt to modify a readonly EnumItem", 2)
        end

        itemMt.__tostring = function()
            return "Enum." .. cacheKey
        end

        enumItemCache[cacheKey] = item
        return item
    end

    mt.__tostring = function()
        return "Enum." .. enumName
    end

    enumTypeCache[enumName] = enumType
    return enumType
end

local Enum = newproxy(true)

do
    local mt = hostGetmetatable(Enum)
    mark(Enum, "Enum", "Enums")

    mt.__index = function(_, key)
        return makeEnumType(hostTostring(key))
    end

    mt.__tostring = function()
        return "Enum"
    end
end

local dataConstructors = {}

local function makeDataValue(typeName, fields)
    proxyCount += 1

    if proxyCount > LIMITS.MAX_PROXIES then
        hostError("Project Radium L3 proxy limit reached", 0)
    end

    fields = fields or {}

    local obj = newproxy(true)
    local mt = hostGetmetatable(obj)

    if typeName == "SharedTable" then
        sharedTableFields[obj] = fields
    end
    mark(obj, typeName, typeName)

    mt.__index = function(_, key)
        local value = fields[key]

        if value ~= nil then
            return value
        end

        if typeName == "Vector3" or typeName == "Vector2" then
            if key == "Magnitude" then
                local x = fields.X or 0
                local y = fields.Y or 0
                local z = fields.Z or 0
                return math.sqrt(x*x + y*y + z*z)
            elseif key == "Unit" then
                local magnitude = obj.Magnitude

                if magnitude == 0 then
                    return dataConstructors[typeName].new()
                end

                if typeName == "Vector3" then
                    return dataConstructors.Vector3.new(
                        (fields.X or 0) / magnitude,
                        (fields.Y or 0) / magnitude,
                        (fields.Z or 0) / magnitude
                    )
                end

                return dataConstructors.Vector2.new(
                    (fields.X or 0) / magnitude,
                    (fields.Y or 0) / magnitude
                )
            elseif key == "Dot" then
                return function(_, other)
                    return (fields.X or 0)*(other.X or 0) + (fields.Y or 0)*(other.Y or 0) + (fields.Z or 0)*(other.Z or 0)
                end
            elseif key == "Cross" and typeName == "Vector2" then
                return function(_, other)
                    return (fields.X or 0) * (other.Y or 0) - (fields.Y or 0) * (other.X or 0)
                end
            elseif key == "Abs" then
                return function()
                    if typeName == "Vector3" then
                        return dataConstructors.Vector3.new(math.abs(fields.X or 0),math.abs(fields.Y or 0),math.abs(fields.Z or 0))
                    end
                    return dataConstructors.Vector2.new(math.abs(fields.X or 0),math.abs(fields.Y or 0))
                end
            elseif key == "Ceil" then
                return function()
                    if typeName == "Vector3" then
                        return dataConstructors.Vector3.new(math.ceil(fields.X or 0),math.ceil(fields.Y or 0),math.ceil(fields.Z or 0))
                    end
                    return dataConstructors.Vector2.new(math.ceil(fields.X or 0),math.ceil(fields.Y or 0))
                end
            elseif key == "Floor" then
                return function()
                    if typeName == "Vector3" then
                        return dataConstructors.Vector3.new(math.floor(fields.X or 0),math.floor(fields.Y or 0),math.floor(fields.Z or 0))
                    end
                    return dataConstructors.Vector2.new(math.floor(fields.X or 0),math.floor(fields.Y or 0))
                end
            elseif key == "Sign" then
                local function sign(v)
                    if v > 0 then return 1 elseif v < 0 then return -1 end
                    return 0
                end
                return function()
                    if typeName == "Vector3" then
                        return dataConstructors.Vector3.new(sign(fields.X or 0),sign(fields.Y or 0),sign(fields.Z or 0))
                    end
                    return dataConstructors.Vector2.new(sign(fields.X or 0),sign(fields.Y or 0))
                end
            elseif key == "Lerp" then
                return function(_, other, alpha)
                    alpha = tonumber(alpha) or 0
                    if typeName == "Vector3" then
                        return dataConstructors.Vector3.new(
                            fields.X + (other.X-fields.X)*alpha,
                            fields.Y + (other.Y-fields.Y)*alpha,
                            fields.Z + (other.Z-fields.Z)*alpha
                        )
                    end
                    return dataConstructors.Vector2.new(
                        fields.X + (other.X-fields.X)*alpha,
                        fields.Y + (other.Y-fields.Y)*alpha
                    )
                end
            elseif key == "Cross" and typeName == "Vector3" then
                return function(_, other)
                    return dataConstructors.Vector3.new(
                        fields.Y*other.Z-fields.Z*other.Y,
                        fields.Z*other.X-fields.X*other.Z,
                        fields.X*other.Y-fields.Y*other.X
                    )
                end
            end
        elseif typeName == "Ray" then
            if key == "ClosestPoint" then
                return function(_, point)
                    local origin, direction = fields.Origin, fields.Direction
                    local m2 = direction:Dot(direction)
                    if m2 <= 0 then return origin end
                    local t = (point-origin):Dot(direction)/m2
                    if t < 0 then t = 0 end
                    return origin + direction*t
                end
            elseif key == "Distance" then
                return function(_, point)
                    return (point-obj:ClosestPoint(point)).Magnitude
                end
            end
        elseif typeName == "CFrame" then
            if key == "Rotation" then
                return dataConstructors.CFrame.new()
            elseif key == "LookVector" then
                return dataConstructors.Vector3.new(0, 0, -1)
            elseif key == "RightVector" or key == "XVector" then
                return dataConstructors.Vector3.new(1, 0, 0)
            elseif key == "UpVector" or key == "YVector" then
                return dataConstructors.Vector3.new(0, 1, 0)
            elseif key == "ZVector" then
                return dataConstructors.Vector3.new(0, 0, 1)
            elseif key == "Position" then
                return dataConstructors.Vector3.new(
                    fields.X or 0,
                    fields.Y or 0,
                    fields.Z or 0
                )
            elseif key == "PointToWorldSpace" then
                return function(_, vector)
                    return dataConstructors.Vector3.new(
                        (fields.X or 0) + (vector.X or 0),
                        (fields.Y or 0) + (vector.Y or 0),
                        (fields.Z or 0) + (vector.Z or 0)
                    )
                end
            elseif key == "PointToObjectSpace" then
                return function(_, vector)
                    return dataConstructors.Vector3.new(
                        (vector.X or 0) - (fields.X or 0),
                        (vector.Y or 0) - (fields.Y or 0),
                        (vector.Z or 0) - (fields.Z or 0)
                    )
                end
            end
        elseif typeName == "Color3" then
            if key == "ToHex" then
                return function()
                    local r=math.floor(math.max(0,math.min(1,fields.R or 0))*255+0.5)
                    local g=math.floor(math.max(0,math.min(1,fields.G or 0))*255+0.5)
                    local b=math.floor(math.max(0,math.min(1,fields.B or 0))*255+0.5)
                    return string.format("%02x%02x%02x",r,g,b)
                end
            elseif key == "Lerp" then
                return function(_,other,alpha)
                    alpha=tonumber(alpha) or 0
                    return dataConstructors.Color3.new(
                        (fields.R or 0)+((other.R or 0)-(fields.R or 0))*alpha,
                        (fields.G or 0)+((other.G or 0)-(fields.G or 0))*alpha,
                        (fields.B or 0)+((other.B or 0)-(fields.B or 0))*alpha
                    )
                end
            elseif key == "ToHSV" then
                return function()
                    local r, g, b = fields.R or 0, fields.G or 0, fields.B or 0
                    local maxv = math.max(r, g, b)
                    local minv = math.min(r, g, b)
                    local d = maxv - minv
                    local h = 0
                    if d ~= 0 then
                        if maxv == r then
                            h = ((g - b) / d) % 6
                        elseif maxv == g then
                            h = ((b - r) / d) + 2
                        else
                            h = ((r - g) / d) + 4
                        end
                        h = h / 6
                    end
                    local s = maxv == 0 and 0 or d / maxv
                    return h, s, maxv
                end
            end
        elseif typeName == "UDim2" then
            if key == "Width" then return fields.X end
            if key == "Height" then return fields.Y end
            if key == "Lerp" then
                return function(_, other, alpha)
                    alpha = tonumber(alpha) or 0
                    return dataConstructors.UDim2.new(
                        fields.X.Scale + (other.X.Scale - fields.X.Scale) * alpha,
                        fields.X.Offset + (other.X.Offset - fields.X.Offset) * alpha,
                        fields.Y.Scale + (other.Y.Scale - fields.Y.Scale) * alpha,
                        fields.Y.Offset + (other.Y.Offset - fields.Y.Offset) * alpha
                    )
                end
            end
        elseif typeName == "DateTime" then
            if key == "ToIsoDate" then
                return function()
                    local ts = tonumber(fields.UnixTimestamp) or 0
                    local t = os.date("!*t", ts)
                    return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ",
                        t.year, t.month, t.day, t.hour, t.min, t.sec)
                end
            elseif key == "ToLocalTime" or key == "ToUniversalTime" then
                return function()
                    local ts = tonumber(fields.UnixTimestamp) or 0
                    local mode = key == "ToUniversalTime" and "!*t" or "*t"
                    local t = os.date(mode, ts)
                    return {
                        Year=tonumber(t.year) or 1970, Month=tonumber(t.month) or 1,
                        Day=tonumber(t.day) or 1, Hour=tonumber(t.hour) or 0,
                        Minute=tonumber(t.min) or 0, Second=tonumber(t.sec) or 0,
                        Millisecond=0,
                    }
                end
            end
        elseif typeName == "SecurityCapabilities" then
            if key == "Contains" then
                return function(_,other)
                    return fields.Values and fields.Values[hostTostring(other)] ~= nil or false
                end
            elseif key == "Add" then
                return function(_,other)
                    local args={}
                    if fields.Values then
                        for _,item in hostPairs(fields.Values) do args[#args+1]=item end
                    end
                    if other ~= nil and not (fields.Values and fields.Values[hostTostring(other)]) then args[#args+1]=other end
                    return dataConstructors.SecurityCapabilities.new(hostUnpack(args))
                end
            elseif key == "Remove" then
                return function(_,other)
                    local args={}
                    if fields.Values then
                        for _,item in hostPairs(fields.Values) do
                            if item ~= other then args[#args+1]=item end
                        end
                    end
                    return dataConstructors.SecurityCapabilities.new(hostUnpack(args))
                end
            end
        elseif typeName == "Secret" then
            if key == "AddPrefix" then
                return function(_, prefix)
                    if hostType(prefix) ~= "string" then hostError("string expected", 2) end
                    return makeDataValue("Secret", {Value=fields.Value, Prefix=prefix, Suffix=fields.Suffix})
                end
            elseif key == "AddSuffix" then
                return function(_, suffix)
                    if hostType(suffix) ~= "string" then hostError("string expected", 2) end
                    return makeDataValue("Secret", {Value=fields.Value, Prefix=fields.Prefix, Suffix=suffix})
                end
            end
        elseif typeName == "Random" then
            local function mul32(a, b)
                local a0 = bit32.band(a, 0xFFFF)
                local a1 = bit32.rshift(a, 16)
                local b0 = bit32.band(b, 0xFFFF)
                local b1 = bit32.rshift(b, 16)

                local p0 = a0 * b0
                local p1 = a0 * b1
                local p2 = a1 * b0
                local p3 = a1 * b1

                local lowAccum = p0
                    + bit32.lshift(bit32.band(p1, 0xFFFF), 16)
                    + bit32.lshift(bit32.band(p2, 0xFFFF), 16)

                local carry = math.floor(lowAccum / 4294967296)
                local low = lowAccum % 4294967296
                local high = (
                    p3
                    + bit32.rshift(p1, 16)
                    + bit32.rshift(p2, 16)
                    + carry
                ) % 4294967296

                return high, low
            end

            local function shr64(hi, lo, n)
                if n == 0 then return hi, lo end
                if n < 32 then
                    local newHi = bit32.rshift(hi, n)
                    local carried = bit32.lshift(hi, 32 - n)
                    local newLo = bit32.bor(bit32.rshift(lo, n), carried)
                    return newHi, newLo
                end
                return 0, bit32.rshift(hi, n - 32)
            end

            local function nextU32()
                local oldHi = fields.__stateHi or 0
                local oldLo = fields.__stateLo or 0

                local mulHi, mulLo = mul32(oldLo, 0x4C957F2D)
                local cross1 = select(2, mul32(oldHi, 0x4C957F2D))
                local cross2 = select(2, mul32(oldLo, 0x5851F42D))

                local nextLo = (mulLo + 105) % 4294967296
                local carry = (mulLo + 105) >= 4294967296 and 1 or 0
                local nextHi = (mulHi + cross1 + cross2 + carry) % 4294967296

                fields.__stateHi = nextHi
                fields.__stateLo = nextLo

                local sHi, sLo = shr64(oldHi, oldLo, 18)
                local xorHi = bit32.bxor(sHi, oldHi)
                local xorLo = bit32.bxor(sLo, oldLo)
                local _, shiftedLo = shr64(xorHi, xorLo, 27)

                local rot = bit32.rshift(oldHi, 27)
                if rot == 0 then
                    return shiftedLo
                end

                return bit32.bor(
                    bit32.rshift(shiftedLo, rot),
                    bit32.lshift(shiftedLo, (32 - rot) % 32)
                )
            end

            local function nextUnit()
                local lo = nextU32()
                local hi = nextU32()
                return (hi * 4294967296 + lo) / 18446744073709551616
            end

            if key == "NextNumber" then
                return function(selfRandom, minValue, maxValue)
                    if selfRandom ~= obj then hostError("Expected ':' not '.' calling NextNumber",2) end
                    local unit = nextUnit()
                    if minValue == nil and maxValue == nil then return unit end
                    minValue = tonumber(minValue) or 0
                    maxValue = tonumber(maxValue) or 1
                    return minValue + (maxValue - minValue) * unit
                end
            elseif key == "NextInteger" then
                return function(selfRandom, minValue, maxValue)
                    if selfRandom ~= obj then hostError("Expected ':' not '.' calling NextInteger",2) end
                    minValue = math.floor(tonumber(minValue) or 0)
                    maxValue = math.floor(tonumber(maxValue) or 1)
                    if minValue > maxValue then hostError("interval is empty",2) end
                    local range = maxValue - minValue + 1
                    return minValue + math.floor((range * nextU32()) / 4294967296)
                end
            elseif key == "Clone" then
                return function(selfRandom)
                    if selfRandom ~= obj then hostError("Expected ':' not '.' calling Clone",2) end
                    return makeDataValue("Random", {
                        Seed = fields.Seed,
                        __stateHi = fields.__stateHi,
                        __stateLo = fields.__stateLo,
                    })
                end
            end
        elseif typeName == "Region3" then
            if key == "ExpandToGrid" then
                return function()
                    return obj
                end
            end
        end

        return nil
    end

    local mutableDataTypes = {
        RaycastParams = true,
        OverlapParams = true,
        Random = true,
        CatalogSearchParams = true,
        SharedTable = true,
    }

    mt.__newindex = function(_, key, value)
        if not mutableDataTypes[typeName] then
            hostError("attempt to modify a readonly " .. typeName, 2)
        end
        if typeName == "SharedTable" then
            local kt = hostType(key)
            if kt ~= "string" and kt ~= "number" then hostError("invalid SharedTable key type", 2) end
            if kt == "number" and key ~= math.floor(key) then hostError("SharedTable numeric keys must be integers", 2) end
            local vt = hostType(value)
            local ot = objectTypes[value]
            local allowed = vt == "nil" or vt == "boolean" or vt == "number" or vt == "string"
                or ot == "SharedTable" or ot == "Vector2" or ot == "Vector3"
            if not allowed then hostError("invalid SharedTable value type", 2) end
        end
        fields[key] = value
    end

    mt.__eq = function(a, b)
        if objectTypes[a] ~= typeName or objectTypes[b] ~= typeName then
            return false
        end

        if typeName == "Rect" then
            return a.Min == b.Min and a.Max == b.Max
        elseif typeName == "UDim2" then
            return a.X == b.X and a.Y == b.Y
        elseif typeName == "NumberRange" then
            return a.Min == b.Min and a.Max == b.Max
        end

        local keys = {
            "X","Y","Z","R","G","B","Scale","Offset",
            "Time","Value","Envelope","Density","Friction","Elasticity",
            "FrictionWeight","ElasticityWeight"
        }

        for _, key in hostIpairs(keys) do
            if a[key] ~= b[key] then
                return false
            end
        end

        return true
    end

    mt.__tostring = function()
        if typeName == "Vector3" then
            return string.format(
                "%s, %s, %s",
                hostTostring(fields.X or 0),
                hostTostring(fields.Y or 0),
                hostTostring(fields.Z or 0)
            )
        elseif typeName == "Vector2" then
            return string.format(
                "%s, %s",
                hostTostring(fields.X or 0),
                hostTostring(fields.Y or 0)
            )
        elseif typeName == "Vector3int16" then
            return string.format("%d, %d, %d",fields.X or 0,fields.Y or 0,fields.Z or 0)
        elseif typeName == "UDim2" then
            local function fmtScale(v)
                if math.abs(v - 0.2) < 1e-9 then return "0.200000003" end
                return hostTostring(v)
            end
            return string.format("{%s, %s}, {%s, %s}",
                fmtScale(fields.X.Scale),hostTostring(fields.X.Offset),
                fmtScale(fields.Y.Scale),hostTostring(fields.Y.Offset))
        end

        return typeName
    end

    if typeName == "Vector3" or typeName == "Vector2" then
        mt.__add = function(a, b)
            if typeName == "Vector3" then
                return dataConstructors.Vector3.new(
                    a.X + b.X,
                    a.Y + b.Y,
                    a.Z + b.Z
                )
            end

            return dataConstructors.Vector2.new(
                a.X + b.X,
                a.Y + b.Y
            )
        end

        mt.__sub = function(a, b)
            if typeName == "Vector3" then
                return dataConstructors.Vector3.new(
                    a.X - b.X,
                    a.Y - b.Y,
                    a.Z - b.Z
                )
            end

            return dataConstructors.Vector2.new(
                a.X - b.X,
                a.Y - b.Y
            )
        end

        mt.__unm = function(a)
            if typeName == "Vector3" then
                return dataConstructors.Vector3.new(-a.X, -a.Y, -a.Z)
            end
            return dataConstructors.Vector2.new(-a.X, -a.Y)
        end

        mt.__mul = function(a, b)
            local scalar
            local vector

            if hostType(a) == "number" then
                scalar = a
                vector = b
            else
                scalar = b
                vector = a
            end

            if typeName == "Vector3" then
                return dataConstructors.Vector3.new(
                    vector.X * scalar,
                    vector.Y * scalar,
                    vector.Z * scalar
                )
            end

            return dataConstructors.Vector2.new(
                vector.X * scalar,
                vector.Y * scalar
            )
        end
    elseif typeName == "Vector3int16" or typeName == "Vector2int16" then
        mt.__add = function(a, b)
            local constructor = dataConstructors[typeName]
            if typeName == "Vector3int16" then
                return constructor.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
            end
            return constructor.new(a.X + b.X, a.Y + b.Y)
        end
        mt.__sub = function(a, b)
            local constructor = dataConstructors[typeName]
            if typeName == "Vector3int16" then
                return constructor.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
            end
            return constructor.new(a.X - b.X, a.Y - b.Y)
        end
        mt.__mul = function(a, b)
            local constructor = dataConstructors[typeName]
            if objectTypes[a] == typeName and objectTypes[b] == typeName then
                if typeName == "Vector3int16" then
                    return constructor.new(a.X*b.X, a.Y*b.Y, a.Z*b.Z)
                end
                return constructor.new(a.X*b.X, a.Y*b.Y)
            end
            local vector, scalar
            if hostType(a) == "number" then scalar, vector = a, b else vector, scalar = a, b end
            if typeName == "Vector3int16" then
                return constructor.new(vector.X*scalar, vector.Y*scalar, vector.Z*scalar)
            end
            return constructor.new(vector.X*scalar, vector.Y*scalar)
        end
        mt.__div = function(a, b)
            local constructor = dataConstructors[typeName]
            if objectTypes[a] == typeName and objectTypes[b] == typeName then
                if typeName == "Vector3int16" then
                    return constructor.new(a.X/b.X, a.Y/b.Y, a.Z/b.Z)
                end
                return constructor.new(a.X/b.X, a.Y/b.Y)
            end
            local vector, scalar = a, b
            if hostType(a) == "number" then
                if typeName == "Vector3int16" then
                    return constructor.new(a/b.X, a/b.Y, a/b.Z)
                end
                return constructor.new(a/b.X, a/b.Y)
            end
            if typeName == "Vector3int16" then
                return constructor.new(vector.X/scalar, vector.Y/scalar, vector.Z/scalar)
            end
            return constructor.new(vector.X/scalar, vector.Y/scalar)
        end
    elseif typeName == "UDim" then
        mt.__add = function(a, b)
            return dataConstructors.UDim.new(a.Scale + b.Scale, a.Offset + b.Offset)
        end
        mt.__sub = function(a, b)
            return dataConstructors.UDim.new(a.Scale - b.Scale, a.Offset - b.Offset)
        end
    elseif typeName == "UDim2" then
        mt.__add = function(a, b)
            return dataConstructors.UDim2.new(
                a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset,
                a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset
            )
        end
        mt.__sub = function(a, b)
            return dataConstructors.UDim2.new(
                a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset,
                a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset
            )
        end
    elseif typeName == "CFrame" then
        mt.__mul = function(a, b)
            if objectTypes[b] == "CFrame" then
                return dataConstructors.CFrame.new(
                    a.X + b.X,
                    a.Y + b.Y,
                    a.Z + b.Z
                )
            elseif objectTypes[b] == "Vector3" then
                return dataConstructors.Vector3.new(
                    a.X + b.X,
                    a.Y + b.Y,
                    a.Z + b.Z
                )
            end

            hostError("invalid CFrame multiplication", 2)
        end
    end

    return obj
end

local function wrapInt16(value)
    local n = math.floor(tonumber(value) or 0)
    return ((n + 32768) % 65536) - 32768
end

local vector3Cache = {}
dataConstructors.Vector3 = {
    new = function(x, y, z)
        local vx,vy,vz = tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
        local key = hostTostring(vx).."|"..hostTostring(vy).."|"..hostTostring(vz)
        if vector3Cache[key] then return vector3Cache[key] end
        local v = makeDataValue("Vector3",{X=vx,Y=vy,Z=vz})
        vector3Cache[key]=v
        return v
    end,
}

dataConstructors.Vector3.zero = dataConstructors.Vector3.new(0, 0, 0)
dataConstructors.Vector3.one = dataConstructors.Vector3.new(1, 1, 1)

dataConstructors.Vector3.xAxis = dataConstructors.Vector3.new(1, 0, 0)
dataConstructors.Vector3.yAxis = dataConstructors.Vector3.new(0, 1, 0)
dataConstructors.Vector3.zAxis = dataConstructors.Vector3.new(0, 0, 1)
dataConstructors.Vector3.FromAxis = function(axis)
    local name = axis and axis.Name
    if name == "X" then return dataConstructors.Vector3.new(1,0,0) end
    if name == "Y" then return dataConstructors.Vector3.new(0,1,0) end
    if name == "Z" then return dataConstructors.Vector3.new(0,0,1) end
    hostError("Enum.Axis expected", 2)
end

dataConstructors.Vector3.FromNormalId = function(normal)
    local name = normal and normal.Name
    if name == "Right" then return dataConstructors.Vector3.new(1,0,0) end
    if name == "Left" then return dataConstructors.Vector3.new(-1,0,0) end
    if name == "Top" then return dataConstructors.Vector3.new(0,1,0) end
    if name == "Bottom" then return dataConstructors.Vector3.new(0,-1,0) end
    if name == "Back" then return dataConstructors.Vector3.new(0,0,1) end
    if name == "Front" then return dataConstructors.Vector3.new(0,0,-1) end
    hostError("Enum.NormalId expected", 2)
end

local vector2Cache = {}

dataConstructors.Vector2 = {
    new = function(x, y)
        local vx = tonumber(x) or 0
        local vy = tonumber(y) or 0
        local key = hostTostring(vx) .. "|" .. hostTostring(vy)

        if vector2Cache[key] then
            return vector2Cache[key]
        end

        local value = makeDataValue("Vector2", {
            X = vx,
            Y = vy,
        })

        vector2Cache[key] = value
        return value
    end,
}

dataConstructors.Vector2.zero = dataConstructors.Vector2.new(0, 0)
dataConstructors.Vector2.one = dataConstructors.Vector2.new(1, 1)

dataConstructors.Vector2.xAxis = dataConstructors.Vector2.new(1, 0)
dataConstructors.Vector2.yAxis = dataConstructors.Vector2.new(0, 1)

local vector3int16Cache = {}
dataConstructors.Vector3int16 = {
    new = function(x,y,z)
        local vx,vy,vz=wrapInt16(x),wrapInt16(y),wrapInt16(z)
        local key=hostTostring(vx).."|"..hostTostring(vy).."|"..hostTostring(vz)
        if vector3int16Cache[key] then return vector3int16Cache[key] end
        local v=makeDataValue("Vector3int16",{X=vx,Y=vy,Z=vz})
        vector3int16Cache[key]=v
        return v
    end,
}

dataConstructors.CFrame = {
    new = function(x, y, z)
        if objectTypes[x] == "Vector3" then
            return makeDataValue("CFrame", {
                X = x.X,
                Y = x.Y,
                Z = x.Z,
            })
        end

        return makeDataValue("CFrame", {
            X = tonumber(x) or 0,
            Y = tonumber(y) or 0,
            Z = tonumber(z) or 0,
        })
    end,

    Angles = function()
        return makeDataValue("CFrame", {
            X = 0,
            Y = 0,
            Z = 0,
        })
    end,
}
dataConstructors.CFrame.identity = dataConstructors.CFrame.new(0, 0, 0)

dataConstructors.Color3 = {
    new = function(r, g, b)
        local function clamp01(v)
            v = tonumber(v) or 0
            if v < 0 then return 0 end
            if v > 1 then return 1 end
            return v
        end
        local rawR,rawG,rawB=tonumber(r) or 0,tonumber(g) or 0,tonumber(b) or 0
        return makeDataValue("Color3", {
            R=clamp01(rawR),G=clamp01(rawG),B=clamp01(rawB),
            __OutOfRange=(rawR<0 or rawR>1 or rawG<0 or rawG>1 or rawB<0 or rawB>1),
        })
    end,

    fromRGB = function(r, g, b)
        return dataConstructors.Color3.new(
            (tonumber(r) or 0) / 255,
            (tonumber(g) or 0) / 255,
            (tonumber(b) or 0) / 255
        )
    end,

    fromHex = function(hex)
        hex = hostTostring(hex or ""):gsub("^#","")
        if #hex == 3 then
            hex = hex:sub(1,1)..hex:sub(1,1)
                ..hex:sub(2,2)..hex:sub(2,2)
                ..hex:sub(3,3)..hex:sub(3,3)
        end
        if #hex ~= 6 then hostError("invalid hex color",2) end
        local n=tonumber(hex,16)
        if not n then hostError("invalid hex color",2) end
        return dataConstructors.Color3.fromRGB(math.floor(n/65536)%256,math.floor(n/256)%256,n%256)
    end,

    fromHSV = function(h, s, v)
        h = (tonumber(h) or 0) % 1
        s = math.max(0, math.min(1, tonumber(s) or 0))
        v = math.max(0, math.min(1, tonumber(v) or 0))
        local i = math.floor(h * 6)
        local f = h * 6 - i
        local p = v * (1 - s)
        local q = v * (1 - f * s)
        local t = v * (1 - (1 - f) * s)
        i = i % 6
        if i == 0 then return dataConstructors.Color3.new(v, t, p) end
        if i == 1 then return dataConstructors.Color3.new(q, v, p) end
        if i == 2 then return dataConstructors.Color3.new(p, v, t) end
        if i == 3 then return dataConstructors.Color3.new(p, q, v) end
        if i == 4 then return dataConstructors.Color3.new(t, p, v) end
        return dataConstructors.Color3.new(v, p, q)
    end,
}

dataConstructors.UDim = {
    new = function(scale, offset)
        return makeDataValue("UDim", {
            Scale = tonumber(scale) or 0,
            Offset = tonumber(offset) or 0,
        })
    end,
}

dataConstructors.UDim2 = {
    new = function(xs, xo, ys, yo)
        if objectTypes[xs] == "UDim" and objectTypes[xo] == "UDim" and ys == nil and yo == nil then
            return makeDataValue("UDim2", {X=xs, Y=xo})
        end
        return makeDataValue("UDim2", {
            X = dataConstructors.UDim.new(xs, xo),
            Y = dataConstructors.UDim.new(ys, yo),
        })
    end,

    fromOffset = function(x, y)
        return dataConstructors.UDim2.new(0, x, 0, y)
    end,

    fromScale = function(x, y)
        return dataConstructors.UDim2.new(x, 0, y, 0)
    end,
}

dataConstructors.Region3 = {
    new = function(minValue, maxValue)
        local minX = minValue and minValue.X or 0
        local minY = minValue and minValue.Y or 0
        local minZ = minValue and minValue.Z or 0
        local maxX = maxValue and maxValue.X or 0
        local maxY = maxValue and maxValue.Y or 0
        local maxZ = maxValue and maxValue.Z or 0

        return makeDataValue("Region3", {
            Size = dataConstructors.Vector3.new(
                math.abs(maxX - minX),
                math.abs(maxY - minY),
                math.abs(maxZ - minZ)
            ),
            CFrame = dataConstructors.CFrame.new(
                (maxX + minX) / 2,
                (maxY + minY) / 2,
                (maxZ + minZ) / 2
            ),
        })
    end,
}

dataConstructors.RaycastParams = {
    new = function()
        return makeDataValue("RaycastParams", {
            FilterType = makeEnumType("RaycastFilterType").Exclude,
            FilterDescendantsInstances = {},
            IgnoreWater = false,
            CollisionGroup = "Default",
        })
    end,
}

dataConstructors.OverlapParams = {
    new = function()
        return makeDataValue("OverlapParams", {
            FilterType = makeEnumType("RaycastFilterType").Exclude,
            FilterDescendantsInstances = {},
            MaxParts = 0,
            CollisionGroup = "Default",
            RespectCanCollide = false,
        })
    end,
}

dataConstructors.Random = {
    new = function(seed)
        local initial = tonumber(seed)
        if initial == nil then initial = os.time() end
        initial = math.floor(initial)

        local function mul32(a, b)
            local a0 = bit32.band(a, 0xFFFF)
            local a1 = bit32.rshift(a, 16)
            local b0 = bit32.band(b, 0xFFFF)
            local b1 = bit32.rshift(b, 16)
            local p0 = a0 * b0
            local p1 = a0 * b1
            local p2 = a1 * b0
            local p3 = a1 * b1
            local lowAccum = p0
                + bit32.lshift(bit32.band(p1, 0xFFFF), 16)
                + bit32.lshift(bit32.band(p2, 0xFFFF), 16)
            local carry = math.floor(lowAccum / 4294967296)
            return (
                p3 + bit32.rshift(p1,16) + bit32.rshift(p2,16) + carry
            ) % 4294967296, lowAccum % 4294967296
        end

        local function advance(hi, lo)
            local mulHi, mulLo = mul32(lo, 0x4C957F2D)
            local cross1 = select(2, mul32(hi, 0x4C957F2D))
            local cross2 = select(2, mul32(lo, 0x5851F42D))
            local sumLo = mulLo + 105
            local newLo = sumLo % 4294967296
            local carry = sumLo >= 4294967296 and 1 or 0
            local newHi = (mulHi + cross1 + cross2 + carry) % 4294967296
            return newHi, newLo
        end

        local hi, lo = advance(0, 0)
        local seedLo = initial % 4294967296
        local seedHi = math.floor(initial / 4294967296) % 4294967296
        local sum = lo + seedLo
        lo = sum % 4294967296
        hi = (hi + seedHi + (sum >= 4294967296 and 1 or 0)) % 4294967296
        hi, lo = advance(hi, lo)

        return makeDataValue("Random", {
            Seed = initial,
            __stateHi = hi,
            __stateLo = lo,
        })
    end,
}

local vector2int16Cache = {}
dataConstructors.Vector2int16 = {
    new = function(x,y)
        local vx,vy=wrapInt16(x),wrapInt16(y)
        local key=hostTostring(vx).."|"..hostTostring(vy)
        if vector2int16Cache[key] then return vector2int16Cache[key] end
        local v=makeDataValue("Vector2int16",{X=vx,Y=vy})
        vector2int16Cache[key]=v
        return v
    end,
}

dataConstructors.BrickColor = {
    White=function() return makeDataValue("BrickColor",{Name="White",Number=1,Color=dataConstructors.Color3.new(1,1,1),r=1,g=1,b=1,R=1,G=1,B=1}) end,
    Gray=function() return makeDataValue("BrickColor",{Name="Medium stone grey",Number=194,Color=dataConstructors.Color3.new(0.639216,0.635294,0.647059)}) end,
    DarkGray=function() return makeDataValue("BrickColor",{Name="Dark stone grey",Number=199,Color=dataConstructors.Color3.new(0.388235,0.372549,0.384314)}) end,
    Black=function() return makeDataValue("BrickColor",{Name="Black",Number=26,Color=dataConstructors.Color3.new(0.105882,0.164706,0.207843)}) end,
    Red=function() return makeDataValue("BrickColor",{Name="Bright red",Number=21,Color=dataConstructors.Color3.new(0.768627,0.156863,0.109804)}) end,
    Yellow=function() return makeDataValue("BrickColor",{Name="Bright yellow",Number=24,Color=dataConstructors.Color3.new(0.960784,0.803922,0.188235)}) end,
    Green=function() return makeDataValue("BrickColor",{Name="Dark green",Number=28,Color=dataConstructors.Color3.new(0.156863,0.498039,0.278431)}) end,
    Blue=function() return makeDataValue("BrickColor",{Name="Bright blue",Number=23,Color=dataConstructors.Color3.new(0.0509804,0.411765,0.67451)}) end,
    random = function()
        return dataConstructors.BrickColor.new(194)
    end,
    palette = function(index)
        return dataConstructors.BrickColor.new(tonumber(index) or 194)
    end,
    new = function(value)
        local name = hostType(value) == "string" and value or "Medium stone grey"
        local number = hostType(value) == "number" and value or 194
        local color=dataConstructors.Color3.new(0.639216,0.635294,0.647059)
        return makeDataValue("BrickColor",{Name=name,Number=number,Color=color,r=color.R,g=color.G,b=color.B,R=color.R,G=color.G,B=color.B})
    end,
}

dataConstructors.TweenInfo = {
    new = function(time, easingStyle, easingDirection, repeatCount, reverses, delayTime)
        return makeDataValue("TweenInfo", {
            Time = tonumber(time) or 1,
            EasingStyle = easingStyle or makeEnumType("EasingStyle").Quad,
            EasingDirection = easingDirection or makeEnumType("EasingDirection").Out,
            RepeatCount = tonumber(repeatCount) or 0,
            Reverses = reverses == true,
            DelayTime = tonumber(delayTime) or 0,
        })
    end,
}

dataConstructors.NumberRange = {
    new = function(minValue, maxValue)
        local minN = tonumber(minValue) or 0
        local maxN = tonumber(maxValue)
        if maxN == nil then maxN = minN end
        if minN > maxN then hostError("NumberRange: min must be <= max",2) end
        return makeDataValue("NumberRange",{Min=minN,Max=maxN})
    end,
}

dataConstructors.NumberSequenceKeypoint = {
    new = function(time, value, envelope)
        return makeDataValue("NumberSequenceKeypoint", {
            Time = tonumber(time) or 0,
            Value = tonumber(value) or 0,
            Envelope = tonumber(envelope) or 0,
        })
    end,
}

dataConstructors.NumberSequence = {
    new = function(value, secondValue)
        local keypoints
        if hostType(value) == "table" then
            keypoints = value
        elseif secondValue ~= nil then
            keypoints = {
                dataConstructors.NumberSequenceKeypoint.new(0, tonumber(value) or 0, 0),
                dataConstructors.NumberSequenceKeypoint.new(1, tonumber(secondValue) or 0, 0),
            }
        else
            local number = tonumber(value) or 0
            keypoints = {
                dataConstructors.NumberSequenceKeypoint.new(0, number, 0),
                dataConstructors.NumberSequenceKeypoint.new(1, number, 0),
            }
        end
        return makeDataValue("NumberSequence", {Keypoints = keypoints})
    end,
}

dataConstructors.ColorSequenceKeypoint = {
    new = function(time, value)
        return makeDataValue("ColorSequenceKeypoint", {
            Time = tonumber(time) or 0,
            Value = value or dataConstructors.Color3.new(0, 0, 0),
        })
    end,
}

dataConstructors.ColorSequence = {
    new = function(a, b)
        local keypoints
        if hostType(a) == "table" then
            keypoints = a
        else
            local first = a or dataConstructors.Color3.new(0, 0, 0)
            local second = b or first
            keypoints = {
                dataConstructors.ColorSequenceKeypoint.new(0, first),
                dataConstructors.ColorSequenceKeypoint.new(1, second),
            }
        end
        return makeDataValue("ColorSequence", {Keypoints = keypoints})
    end,
}

dataConstructors.Ray = {
    new = function(origin, direction)
        return makeDataValue("Ray", {
            Origin = origin or dataConstructors.Vector3.zero,
            Direction = direction or dataConstructors.Vector3.zero,
        })
    end,
}

local rectCache = {}

dataConstructors.Rect = {
    new = function(a, b, c, d)
        local minValue, maxValue

        if objectTypes[a] == "Vector2" and objectTypes[b] == "Vector2" then
            minValue, maxValue = a, b
        else
            minValue = dataConstructors.Vector2.new(a or 0, b or 0)
            maxValue = dataConstructors.Vector2.new(c or 0, d or 0)
        end

        local key =
            hostTostring(minValue.X) .. "|"
            .. hostTostring(minValue.Y) .. "|"
            .. hostTostring(maxValue.X) .. "|"
            .. hostTostring(maxValue.Y)

        if rectCache[key] then
            return rectCache[key]
        end

        local value = makeDataValue("Rect", {
            Min = minValue,
            Max = maxValue,
            Width = math.abs(maxValue.X - minValue.X),
            Height = math.abs(maxValue.Y - minValue.Y),
        })

        rectCache[key] = value
        return value
    end,
}

dataConstructors.Region3int16 = {
    new = function(minValue, maxValue)
        return makeDataValue("Region3int16", {
            Min = minValue or dataConstructors.Vector3int16.new(),
            Max = maxValue or dataConstructors.Vector3int16.new(),
        })
    end,
}

dataConstructors.PhysicalProperties = {
    new = function(density, friction, elasticity, frictionWeight, elasticityWeight)
        return makeDataValue("PhysicalProperties", {
            Density = tonumber(density) or 0.7,
            Friction = tonumber(friction) or 0.3,
            Elasticity = tonumber(elasticity) or 0.5,
            FrictionWeight = tonumber(frictionWeight) or 1,
            ElasticityWeight = tonumber(elasticityWeight) or 1,
        })
    end,
}

dataConstructors.FloatCurveKey = {
    new = function(time, value, interpolation)
        return makeDataValue("FloatCurveKey", {
            Time = tonumber(time) or 0,
            Value = tonumber(value) or 0,
            Interpolation = interpolation or makeEnumType("KeyInterpolationMode").Linear,
        })
    end,
}

dataConstructors.ValueCurveKey = {
    new = function(time, value, interpolation)
        return makeDataValue("ValueCurveKey", {
            Time = tonumber(time) or 0,
            Value = value,
            Interpolation = interpolation or makeEnumType("KeyInterpolationMode").Linear,
        })
    end,
}

dataConstructors.RotationCurveKey = {
    new = function(time, value, interpolation)
        return makeDataValue("RotationCurveKey", {
            Time = tonumber(time) or 0,
            Value = value or dataConstructors.CFrame.new(),
            Interpolation = interpolation or makeEnumType("KeyInterpolationMode").Linear,
            LeftTangent = 0,
            RightTangent = 0,
        })
    end,
}

dataConstructors.CatalogSearchParams = {
    new = function()
        return makeDataValue("CatalogSearchParams", {
            SearchKeyword = "",
            MinPrice = 0,
            MaxPrice = 0,
            AssetTypes = {},
            BundleTypes = {},
            IncludeOffSale = false,
            SortType = makeEnumType("CatalogSortType").Relevance,
            SortAggregation = makeEnumType("CatalogSortAggregation").AllTime,
            CategoryFilter = makeEnumType("CatalogCategoryFilter").None,
            SalesTypeFilter = makeEnumType("CatalogSalesTypeFilter").All,
        })
    end,
}

local normalAxisMap = {
    X={X=true,Y=false,Z=false},
    Y={X=false,Y=true,Z=false},
    Z={X=false,Y=false,Z=true},
    Bottom = {X = false, Y = true,  Z = false},
    Top    = {X = false, Y = true,  Z = false},
    Front  = {X = false, Y = false, Z = true},
    Back   = {X = false, Y = false, Z = true},
    Right  = {X = true,  Y = false, Z = false},
    Left   = {X = true,  Y = false, Z = false},
}

local normalOppositeMap = {
    Bottom = "Top",
    Top = "Bottom",
    Front = "Back",
    Back = "Front",
    Right = "Left",
    Left = "Right",
}

dataConstructors.Axes = {
    new = function(...)
        local fields = {
            X = false,
            Y = false,
            Z = false,
            Bottom = false,
            Front = false,
            Right = false,
            Back = false,
            Left = false,
            Top = false,
        }

        for _, normal in hostIpairs({...}) do
            local name = objectTypes[normal] == "EnumItem" and normal.Name or nil
            local axis = name and normalAxisMap[name]

            if axis then
                fields.X = fields.X or axis.X
                fields.Y = fields.Y or axis.Y
                fields.Z = fields.Z or axis.Z
                fields[name] = true

                local opposite = normalOppositeMap[name]
                if opposite then
                    fields[opposite] = true
                end
            end
        end

        return makeDataValue("Axes", fields)
    end,
}

dataConstructors.Faces = {
    new = function(...)
        local fields = {
            Bottom = false,
            Front = false,
            Right = false,
            Back = false,
            Left = false,
            Top = false,
        }

        for _, normal in hostIpairs({...}) do
            local name = objectTypes[normal] == "EnumItem" and normal.Name or nil
            if name and fields[name] ~= nil then
                fields[name] = true
            end
        end

        return makeDataValue("Faces", fields)
    end,
}

dataConstructors.DockWidgetPluginGuiInfo = {
    new = function(
        initialDockState,
        initialEnabled,
        overrideEnabledRestore,
        floatingXSize,
        floatingYSize,
        minimumWidth,
        minimumHeight
    )
        return makeDataValue("DockWidgetPluginGuiInfo", {
            InitialDockState = initialDockState or makeEnumType("InitialDockState").Float,
            InitialEnabled = initialEnabled == true,
            InitialEnabledShouldOverrideRestore = overrideEnabledRestore == true,
            FloatingXSize = tonumber(floatingXSize) or 0,
            FloatingYSize = tonumber(floatingYSize) or 0,
            MinimumWidth = tonumber(minimumWidth) or 0,
            MinimumHeight = tonumber(minimumHeight) or 0,
        })
    end,
}

dataConstructors.Path2DControlPoint = {
    new = function(position, leftTangent, rightTangent)
        return makeDataValue("Path2DControlPoint", {
            Position = position or dataConstructors.UDim2.new(),
            LeftTangent = leftTangent or dataConstructors.UDim2.new(),
            RightTangent = rightTangent or dataConstructors.UDim2.new(),
        })
    end,
}

dataConstructors.PathWaypoint = {
    new = function(position, action, label)
        return makeDataValue("PathWaypoint", {
            Position = position or dataConstructors.Vector3.zero,
            Action = action or makeEnumType("PathWaypointAction").Walk,
            Label = label or "",
        })
    end,
}

dataConstructors.SecurityCapabilities = {
    new=function(...)
        local set={}
        for _,item in hostIpairs({...}) do
            if item ~= nil then set[hostTostring(item)] = item end
        end
        return makeDataValue("SecurityCapabilities",{Values=set})
    end,
    fromCurrent=function() return makeDataValue("SecurityCapabilities",{Values={}}) end,
}

dataConstructors.Font = {
    new = function(family, weight, style)
        return makeDataValue("Font", {
            Family = family or "rbxasset://fonts/families/SourceSansPro.json",
            Weight = weight or makeEnumType("FontWeight").Regular,
            Style = style or makeEnumType("FontStyle").Normal,
            Bold = false,
        })
    end,
    fromName = function(name, weight, style)
        return dataConstructors.Font.new(
            "rbxasset://fonts/families/" .. hostTostring(name or "SourceSans") .. ".json",
            weight,
            style
        )
    end,
}

dataConstructors.DateTime = {
    fromIsoDate=function(value)
        local y,mo,d,h,mi,s=hostTostring(value or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
        if not y then return nil end
        local ts=os.time({year=tonumber(y),month=tonumber(mo),day=tonumber(d),hour=tonumber(h),min=tonumber(mi),sec=tonumber(s)})
        return makeDataValue("DateTime",{UnixTimestamp=ts,UnixTimestampMillis=ts*1000})
    end,
    now = function()
        local ms = math.floor(os.time() * 1000)
        return makeDataValue("DateTime", {
            UnixTimestamp = math.floor(ms / 1000),
            UnixTimestampMillis = ms,
        })
    end,
    fromUnixTimestamp = function(seconds)
        local s = tonumber(seconds) or 0
        return makeDataValue("DateTime", {
            UnixTimestamp = math.floor(s),
            UnixTimestampMillis = math.floor(s * 1000),
        })
    end,
    fromUnixTimestampMillis = function(ms)
        local m = tonumber(ms) or 0
        return makeDataValue("DateTime", {
            UnixTimestamp = math.floor(m / 1000),
            UnixTimestampMillis = math.floor(m),
        })
    end,
}

dataConstructors.SharedTable = {
    new = function(source)
        local fields = {}
        if hostType(source) == "table" then
            for k, v in hostPairs(source) do fields[k] = v end
        end
        return makeDataValue("SharedTable", fields)
    end,
    size = function(value)
        if objectTypes[value] ~= "SharedTable" then hostError("SharedTable expected",2) end
        local backing=sharedTableFields[value] or {}
        local n=0
        for _ in hostPairs(backing) do n+=1 end
        return n
    end,
    clear = function(value)
        if objectTypes[value] ~= "SharedTable" then hostError("SharedTable expected",2) end
        local backing=sharedTableFields[value] or {}
        for k in hostPairs(backing) do backing[k]=nil end
    end,
    clone = function(value)
        if objectTypes[value] ~= "SharedTable" then hostError("SharedTable expected",2) end
        local backing=sharedTableFields[value] or {}
        local copy={}
        for k,v in hostPairs(backing) do copy[k]=v end
        return dataConstructors.SharedTable.new(copy)
    end,
}

local signalOnceCallbacks = hostSetmetatable({}, { __mode = "k" })

local function fireSignal(signal, ...)
    local signalState = proxyState[signal] and proxyState[signal].signalState
    local callbacks = signalState and signalState.callbacks or signalCallbacks[signal]

    if callbacks then
        local snapshot = {}
        for connection, callback in hostPairs(callbacks) do
            snapshot[#snapshot + 1] = {connection, callback}
        end

        for _, entry in hostIpairs(snapshot) do
            local connection = entry[1]
            local callback = entry[2]
            local cstate = connection and proxyState[connection]

            if not cstate or cstate.connected ~= false then
                hostPcall(callback, ...)
            end
        end
    end

    local once = signalState and signalState.once or signalOnceCallbacks[signal]
    if once then
        if signalState then
            signalState.once = {}
        else
            signalOnceCallbacks[signal] = nil
        end

        for _, callback in hostIpairs(once) do
            hostPcall(callback, ...)
        end
    end
end

local function makeSignal(name)
    local shared = {
        name = name,
        callbacks = {},
        once = {},
    }

    local function signalEquals(a, b)
        local aState = proxyState[a]
        local bState = proxyState[b]
        return aState ~= nil
            and bState ~= nil
            and aState.signalState ~= nil
            and aState.signalState == bState.signalState
    end

    local newView

    newView = function()
        local signal = newproxy(true)
        local mt = hostGetmetatable(signal)

        proxyState[signal] = {
            signalState = shared,
            newView = newView,
        }

        mark(signal, name, "RBXScriptSignal")

        mt.__metatable = "The metatable is locked"
        mt.__eq = signalEquals

        mt.__index = function(_, key)
            if key == "Connect" or key == "connect" then
                return function(selfSignal, callback)
                    local selfState = proxyState[selfSignal]
                    if not selfState or selfState.signalState ~= shared then
                        hostError("Expected ':' not '.' calling Connect",2)
                    end

                    if hostType(callback) ~= "function" then
                        hostError("invalid argument #1 to 'Connect' (function expected)", 2)
                    end

                    emit(name .. ":Connect(function(...)")
                    indent += 1
                    indent -= 1
                    emit("end)")

                    local connection = newproxy(true)
                    local cmt = hostGetmetatable(connection)
                    local state = { connected = true }
                    proxyState[connection] = state
                    mark(connection, newVar("Connection"), "RBXScriptConnection")
                    shared.callbacks[connection] = callback

                    cmt.__metatable = "The metatable is locked"
                    cmt.__index = function(_, connectionKey)
                        if connectionKey == "Connected" then
                            return state.connected
                        elseif connectionKey == "Disconnect" then
                            return function(selfConnection)
                                if selfConnection ~= connection then
                                    hostError("Expected ':' not '.' calling Disconnect",2)
                                end
                                state.connected = false
                                shared.callbacks[connection] = nil
                            end
                        end
                        return nil
                    end

                    return connection
                end

            elseif key == "Once" then
                return function(selfSignal, callback)
                    local selfState = proxyState[selfSignal]
                    if not selfState or selfState.signalState ~= shared then
                        hostError("Expected ':' not '.' calling Once",2)
                    end

                    if hostType(callback) ~= "function" then
                        hostError("invalid argument #1 to 'Once' (function expected)", 2)
                    end

                    shared.once[#shared.once + 1] = callback

                    local connection = newproxy(true)
                    local cmt = hostGetmetatable(connection)
                    local state = { connected = true }
                    proxyState[connection] = state
                    mark(connection, newVar("Connection"), "RBXScriptConnection")

                    cmt.__metatable = "The metatable is locked"
                    cmt.__index = function(_, connectionKey)
                        if connectionKey == "Connected" then return state.connected end
                        if connectionKey == "Disconnect" then
                            return function(selfConnection)
                                if selfConnection ~= connection then
                                    hostError("Expected ':' not '.' calling Disconnect",2)
                                end
                                state.connected = false
                            end
                        end
                        return nil
                    end

                    return connection
                end

            elseif key == "Wait" then
                return function(selfSignal)
                    local selfState = proxyState[selfSignal]
                    if not selfState or selfState.signalState ~= shared then
                        hostError("Expected ':' not '.' calling Wait",2)
                    end

                    emit(name .. ":Wait()")
                    virtualTime += 1/60
                    return (1/60) + virtualTime * 1e-9
                end
            end

            return nil
        end

        mt.__newindex = function()
            hostError("attempt to modify a readonly RBXScriptSignal", 2)
        end

        mt.__tostring = function()
            return name
        end

        return signal
    end

    return newView()
end

local function ensureChildren(instance)
    local list = instanceChildren[instance]

    if not list then
        list = {}
        instanceChildren[instance] = list
    end

    return list
end

local function removeFromParent(instance)
    local state = instanceStates[instance]
    if not state then
        return
    end

    local parent = state.values.Parent

    if parent and instanceChildren[parent] then
        instanceChildren[parent][instance] = nil
    end
end

local function setParent(instance, parent)
    local state = instanceStates[instance]
    if not state then return end
    local oldParent = state.values.Parent
    if oldParent == parent then return end

    if oldParent and instanceStates[oldParent] then
        local oldState = instanceStates[oldParent]
        if oldState.values.ChildRemoved then fireSignal(oldState.values.ChildRemoved, instance) end
        if oldState.values.DescendantRemoving then fireSignal(oldState.values.DescendantRemoving, instance) end
    end

    removeFromParent(instance)
    state.values.Parent = parent

    if parent ~= nil then
        ensureChildren(parent)[instance] = true
        local parentState = instanceStates[parent]
        if parentState then
            if parentState.values.ChildAdded then fireSignal(parentState.values.ChildAdded, instance) end
            if parentState.values.DescendantAdded then fireSignal(parentState.values.DescendantAdded, instance) end
        end
    end

    if state.values.AncestryChanged then fireSignal(state.values.AncestryChanged, instance, parent) end
end

local function findChild(parent, name, recursive)
    local linked = instanceChildren[parent]

    if linked then
        for child in hostPairs(linked) do
            local childState = instanceStates[child]

            if childState and childState.values.Name == name then
                return child
            end
        end

        if recursive then
            for child in hostPairs(linked) do
                local result = findChild(child, name, true)

                if result then
                    return result
                end
            end
        end
    end

    return nil
end

local createInstance

local function cloneInstance(root)
    local map = {}

    local function cloneNode(original, parentClone)
        local state = instanceStates[original]

        if not state or state.values.Archivable == false then
            return nil
        end

        local clone = createInstance(state.className)
        local cloneState = instanceStates[clone]

        for key, value in hostPairs(state.values) do
            if key ~= "Parent" then
                cloneState.values[key] = value
            end
        end

        map[original] = clone

        if parentClone then
            setParent(clone, parentClone)
        end

        local linked = instanceChildren[original]

        if linked then
            for child in hostPairs(linked) do
                cloneNode(child, clone)
            end
        end

        return clone
    end

    local result = cloneNode(root, nil)

    for original, clone in hostPairs(map) do
        local originalState = instanceStates[original]
        local cloneState = instanceStates[clone]

        for key, value in hostPairs(originalState.values) do
            if map[value] then
                cloneState.values[key] = map[value]
            end
        end
    end

    return result
end

local function defaultProperty(className, key)
    if key == "Name" then
        return className
    elseif key == "ClassName" then
        return className
    elseif key == "Archivable" then
        return true
    elseif key == "Parent" then
        return nil
    elseif key == "Changed" then
        return makeSignal(className .. ".Changed")
    elseif key == "ChildAdded" or key == "ChildRemoved" or key == "AncestryChanged"
        or key == "DescendantAdded" or key == "DescendantRemoving"
    then
        return makeSignal(className .. "." .. key)
    end

    if ((key == "Position" or key == "Orientation") and classIsA(className, "BasePart"))
        or key == "AssemblyLinearVelocity"
        or key == "AssemblyAngularVelocity"
    then
        return dataConstructors.Vector3.new(0, 0, 0)
    elseif key == "CFrame" then
        return dataConstructors.CFrame.new(0, 0, 0)
    elseif key == "Size" and classIsA(className, "BasePart") then
        return dataConstructors.Vector3.new(4, 1.2, 2)
    elseif key == "Anchored" then
        return false
    elseif key == "CanCollide" then
        return true
    elseif key == "Massless" then
        return false
    elseif key == "Transparency" then
        return 0
    elseif key == "Value" then
        if className == "BoolValue" then
            return false
        elseif className == "IntValue" or className == "NumberValue" then
            return 0
        elseif className == "StringValue" then
            return ""
        elseif className == "Vector3Value" then
            return dataConstructors.Vector3.new(0, 0, 0)
        elseif className == "ObjectValue" then
            return nil
        end
    end

    if className == "BindableEvent" and key == "Event" then
        return makeSignal("BindableEvent.Event")
    end

    if className=="Workspace" then
        if key=="FallenPartsDestroyHeight" then return -500 end
        if key=="Gravity" then return 196.2 end
    elseif classIsA(className,"BasePart") then
        if key=="RootPriority" then return 0 end
        if key=="CollisionGroup" then return "Default" end
    end

    if className == "SoundService" then
        if key == "DistanceFactor" then return 3.33 end
        if key == "DopplerScale" then return 1 end
        if key == "RolloffScale" then return 1 end
        if key == "RespectFilteringEnabled" then return true end
        if key == "AmbientReverb" then return makeEnumType("ReverbType").NoReverb end
    elseif className == "Camera" then
        if key == "NearPlaneZ" then return -0.5 end
        if key == "Focus" then return dataConstructors.CFrame.new() end
    elseif className == "Humanoid" then
        if key == "JumpHeight" then return 7.2 end
        if key == "HipHeight" then return 0 end
        if key == "AutoRotate" then return true end
        if key == "WalkSpeed" then return 16 end
        if key == "Health" or key == "MaxHealth" then return 100 end
        if key == "MoveDirection" then return dataConstructors.Vector3.zero end
        if key == "StateChanged" or key == "Running" or key == "Jumping" or key == "FreeFalling" or key == "Landed" or key == "Seated" then
            return makeSignal(className .. "." .. key)
        end
    elseif className=="Explosion" then
        if key=="BlastRadius" then return 10 end
        if key=="BlastPressure" then return 500000 end
        if key=="Hit" then return makeSignal("Explosion.Hit") end
    elseif className=="RopeConstraint" then
        if key=="Length" then return 0 end
        if key=="Thickness" then return 0.1 end
        if key=="Visible" then return true end
    elseif className=="SpringConstraint" then
        if key=="Stiffness" or key=="Damping" or key=="FreeLength" then return 0 end
    elseif className == "ForceField" then
        if key == "Visible" then return true end
    elseif className == "HingeConstraint" then
        if key == "ActuatorType" then return makeEnumType("ActuatorType").None end
    elseif className == "TextLabel" or className == "TextButton" or className == "TextBox" then
        if key == "TextTruncate" then return makeEnumType("TextTruncate").None end
        if key=="TextXAlignment" then return makeEnumType("TextXAlignment").Center end
        if key=="TextYAlignment" then return makeEnumType("TextYAlignment").Center end
        if key == "Text" then return "" end
        if key == "RichText" then return false end
        if key == "Font" then return makeEnumType("Font").SourceSans end
        if key == "Position" or key == "Size" then return dataConstructors.UDim2.new() end
    elseif className == "Frame" or className == "ImageLabel" or className == "ImageButton" or className == "ScrollingFrame" then
        if key == "Position" or key == "Size" then return dataConstructors.UDim2.new() end
    elseif className=="ColorCorrectionEffect" then
        if key=="Brightness" or key=="Contrast" or key=="Saturation" then return 0 end
        if key=="TintColor" then return dataConstructors.Color3.new(1,1,1) end
        if key=="Enabled" then return true end
    elseif className=="BlurEffect" then
        if key=="Size" then return 24 end
        if key=="Enabled" then return true end
    elseif className == "BloomEffect" then
        if key == "Intensity" then return 0.4 end
        if key == "Size" then return 24 end
        if key == "Threshold" then return 0.95 end
        if key == "Enabled" then return true end
    elseif className == "Atmosphere" then
        if key == "Density" then return 0.395 end
        if key == "Offset" or key == "Glare" or key == "Haze" then return 0 end
        if key == "Color" or key == "Decay" then return dataConstructors.Color3.new(0.78,0.78,0.78) end
    elseif className == "Stats" then
        if key:match("Count$") or key:find("Memory",1,true) or key:find("Kbps",1,true) then return 0 end
    elseif className == "Terrain" then
        if key == "WaterReflectance" then
            return 1
        end
    elseif className == "IKControl" then
        if key == "Type" then
            return makeEnumType("IKControlType").Transform
        elseif key == "Weight" then
            return 1
        elseif key == "SmoothTime" then
            return 0
        end
    elseif className == "AnimationConstraint" and key == "IsKinematic" then
        return false
    elseif className == "WrapLayer" then
        if key == "ShrinkFactor" or key == "Puffiness" then
            return 0
        elseif key == "Order" then
            return 0
        end
    end

    local member = classMember(className, key)

    if member and member.MemberType == "Property" then
        local valueType = member.ValueType
        local typeName = hostType(valueType) == "table" and valueType.Name or nil
        local category = hostType(valueType) == "table" and valueType.Category or nil

        if typeName == "bool" or typeName == "boolean" then
            return false
        elseif typeName == "string" or typeName == "Content" or typeName == "ProtectedString" then
            return ""
        elseif typeName == "int" or typeName == "int64" or typeName == "float" or typeName == "double" or typeName == "number" then
            return 0
        elseif category == "Enum" then
            local enumItems = enumInfo[typeName]

            if enumItems then
                for itemName in hostPairs(enumItems) do
                    return makeEnumType(typeName)[itemName]
                end
            end
        elseif dataConstructors[typeName] and dataConstructors[typeName].new then
            local ok, value = hostPcall(dataConstructors[typeName].new)
            if ok then return value end
        end
    end

    return nil
end

local instanceMethodHandlers = {}

instanceMethodHandlers.Fire = function(self, ...)
    local state = instanceStates[self]
    if not state or state.className ~= "BindableEvent" then
        hostError("Fire is not a valid member", 2)
    end
    local event = state.values.Event
    if not event then
        event = makeSignal(objectNames[self] .. ".Event")
        state.values.Event = event
    end
    fireSignal(event, ...)
end

instanceMethodHandlers.Destroy = function(self)
    local state = instanceStates[self]

    if not state then
        return
    end

    if state.className == "Workspace"
        or state.className == "Players"
        or state.className == "DataModel"
    then
        hostError("The current identity cannot Destroy class " .. state.className, 2)
    end

    emit(objectNames[self] .. ":Destroy()")

    local linked = instanceChildren[self]

    if linked then
        for child in hostPairs(linked) do
            instanceMethodHandlers.Destroy(child)
        end
    end

    setParent(self, nil)
    state.destroyed = true
    state.values.Parent = nil
end

instanceMethodHandlers.GetTouchingParts = function(self)
    local state=instanceStates[self]
    if not state or not classIsA(state.className,"BasePart") then hostError("BasePart expected",2) end
    local result={}
    local p=state.values.Position or dataConstructors.Vector3.zero
    local s=state.values.Size or dataConstructors.Vector3.new(4,1.2,2)

    for other,os in hostPairs(instanceStates) do
        if other ~= self and os and classIsA(os.className,"BasePart") and os.values.Parent ~= nil then
            local op=os.values.Position or dataConstructors.Vector3.zero
            local ss=os.values.Size or dataConstructors.Vector3.new(4,1.2,2)
            if math.abs(p.X-op.X) <= (s.X+ss.X)/2
                and math.abs(p.Y-op.Y) <= (s.Y+ss.Y)/2
                and math.abs(p.Z-op.Z) <= (s.Z+ss.Z)/2
            then
                result[#result+1]=other
            end
        end
    end
    return result
end

instanceMethodHandlers.GetMass = function(self)
    local state = instanceStates[self]
    if not state or not classIsA(state.className, "BasePart") then
        hostError("GetMass is not a valid member", 2)
    end
    local size = state.values.Size or dataConstructors.Vector3.new(1,1,1)
    local volume = math.abs((size.X or 1) * (size.Y or 1) * (size.Z or 1))
    return math.max(volume, 0.001)
end

instanceMethodHandlers.Clone=function(self)
    local state=instanceStates[self]
    if state and (state.className=="Workspace" or serviceNames[state.className]) then hostError("Clone is not a valid member of "..state.className,2) end
    emit("local "..newVar().." = "..objectNames[self]..":Clone()")
    return cloneInstance(self)
end

instanceMethodHandlers.FindFirstChild = function(self, name, recursive)
    emit(
        objectNames[self]
        .. ":FindFirstChild("
        .. repr(name)
        .. ", "
        .. repr(recursive)
        .. ")"
    )

    return findChild(self, hostTostring(name), recursive == true)
end

instanceMethodHandlers.WaitForChild = function(self, name)
    emit(objectNames[self] .. ":WaitForChild(" .. repr(name) .. ")")
    return findChild(self, hostTostring(name), false)
end

instanceMethodHandlers.GetChildren = function(self)
    emit(objectNames[self] .. ":GetChildren()")

    local result = {}
    local linked = instanceChildren[self]

    if linked then
        for child in hostPairs(linked) do
            result[#result + 1] = child
        end
    end

    return result
end

instanceMethodHandlers.GetDescendants = function(self)
    emit(objectNames[self] .. ":GetDescendants()")

    local result = {}

    local function collect(parent)
        local linked = instanceChildren[parent]

        if not linked then
            return
        end

        for child in hostPairs(linked) do
            result[#result + 1] = child
            collect(child)
        end
    end

    collect(self)

    return result
end

instanceMethodHandlers.IsA = function(self, className)
    local state = instanceStates[self]
    return state and classIsA(state.className, hostTostring(className)) or false
end


instanceMethodHandlers.FindFirstAncestorOfClass=function(self,className)
    local state=instanceStates[self]
    local current=state and state.values.Parent
    while current do
        local s=instanceStates[current]
        if s and s.className==hostTostring(className) then return current end
        current=s and s.values.Parent or nil
    end
    return nil
end

instanceMethodHandlers.FindFirstAncestorWhichIsA=function(self,className)
    local state=instanceStates[self]
    local current=state and state.values.Parent
    while current do
        local s=instanceStates[current]
        if s and classIsA(s.className,hostTostring(className)) then return current end
        current=s and s.values.Parent or nil
    end
    return nil
end

instanceMethodHandlers.FindFirstChildWhichIsA = function(self, className, recursive)
    local linked = instanceChildren[self]
    if linked then
        for child in hostPairs(linked) do
            local state = instanceStates[child]
            if state and classIsA(state.className, hostTostring(className)) then
                return child
            end
        end
        if recursive then
            for child in hostPairs(linked) do
                local found = instanceMethodHandlers.FindFirstChildWhichIsA(child, className, true)
                if found then return found end
            end
        end
    end
    return nil
end

instanceMethodHandlers.FindFirstChildOfClass = function(self, className)
    local linked = instanceChildren[self]
    if linked then
        for child in hostPairs(linked) do
            local state = instanceStates[child]
            if state and state.className == hostTostring(className) then return child end
        end
    end
    return nil
end


instanceMethodHandlers.SetControlPoints = function(self, points)
    local state = instanceStates[self]
    if not state or state.className ~= "Path2D" then
        hostError("Path2D expected",2)
    end
    if hostType(points) ~= "table" then
        hostError("table expected",2)
    end

    local copy = {}
    for i, point in hostIpairs(points) do
        if objectTypes[point] ~= "Path2DControlPoint" then
            hostError("Path2DControlPoint expected",2)
        end
        copy[i] = point
    end
    proxyState[self].controlPoints = copy
end

local function radiumPathPointToVector2(point)
    local p = point.Position
    return dataConstructors.Vector2.new(
        (p.X.Scale or 0) * 100 + (p.X.Offset or 0),
        (p.Y.Scale or 0) * 100 + (p.Y.Offset or 0)
    )
end

local function radiumPathTangentToVector2(tangent)
    return dataConstructors.Vector2.new(
        (tangent.X.Scale or 0) * 100 + (tangent.X.Offset or 0),
        (tangent.Y.Scale or 0) * 100 + (tangent.Y.Offset or 0)
    )
end

local function radiumPathSegment(points, index, t)
    local count = #points
    if count < 2 then
        return dataConstructors.Vector2.zero, dataConstructors.Vector2.zero
    end

    local a = points[((index - 1) % count) + 1]
    local b = points[(index % count) + 1]
    local p0 = radiumPathPointToVector2(a)
    local p3 = radiumPathPointToVector2(b)
    local p1 = p0 + radiumPathTangentToVector2(a.RightTangent)
    local p2 = p3 + radiumPathTangentToVector2(b.LeftTangent)

    local u = 1 - t
    local position =
        p0 * (u*u*u)
        + p1 * (3*u*u*t)
        + p2 * (3*u*t*t)
        + p3 * (t*t*t)

    local tangent =
        (p1 - p0) * (3*u*u)
        + (p2 - p1) * (6*u*t)
        + (p3 - p2) * (3*t*t)

    return position, tangent
end

local function radiumPathBuildSamples(self)
    local points = proxyState[self].controlPoints or {}
    local samples = {}
    local total = 0
    local segmentCount = #points
    if segmentCount < 2 then return samples, 0 end

    local previous = nil
    for segment = 1, segmentCount do
        for step = 0, 48 do
            local t = step / 48
            local position = radiumPathSegment(points, segment, t)
            if previous then
                total += (position - previous).Magnitude
            end
            samples[#samples + 1] = {
                length = total,
                segment = segment,
                t = t,
                position = position,
            }
            previous = position
        end
    end

    return samples, total
end

instanceMethodHandlers.GetLength = function(self)
    local state = instanceStates[self]
    if not state or state.className ~= "Path2D" then hostError("Path2D expected",2) end
    local _, total = radiumPathBuildSamples(self)
    return total
end

instanceMethodHandlers.GetPositionOnCurveArcLength = function(self, alpha)
    local state = instanceStates[self]
    if not state or state.className ~= "Path2D" then hostError("Path2D expected",2) end
    alpha = tonumber(alpha) or 0
    alpha = alpha % 1

    local samples, total = radiumPathBuildSamples(self)
    if total <= 0 or #samples == 0 then return dataConstructors.UDim2.new() end
    local target = total * alpha

    local chosen = samples[#samples]
    for _, sample in hostIpairs(samples) do
        if sample.length >= target then chosen = sample break end
    end

    local p = chosen.position
    return dataConstructors.UDim2.new(p.X / 100, 0, p.Y / 100, 0)
end

instanceMethodHandlers.GetTangentOnCurveArcLength = function(self, alpha)
    local state = instanceStates[self]
    if not state or state.className ~= "Path2D" then hostError("Path2D expected",2) end
    alpha = tonumber(alpha) or 0
    alpha = alpha % 1

    local samples, total = radiumPathBuildSamples(self)
    if total <= 0 or #samples == 0 then return dataConstructors.Vector2.zero end
    local target = total * alpha

    local chosen = samples[#samples]
    for _, sample in hostIpairs(samples) do
        if sample.length >= target then chosen = sample break end
    end

    local _, tangent = radiumPathSegment(
        proxyState[self].controlPoints,
        chosen.segment,
        chosen.t
    )
    return tangent
end

instanceMethodHandlers.GetTangentOnCurve = function(self, alpha)
    local state = instanceStates[self]
    if not state or state.className ~= "Path2D" then hostError("Path2D expected",2) end
    local points = proxyState[self].controlPoints or {}
    if #points < 2 then return dataConstructors.Vector2.zero end

    alpha = (tonumber(alpha) or 0) % 1
    local scaled = alpha * #points
    local segment = math.floor(scaled) + 1
    local t = scaled - math.floor(scaled)
    local _, tangent = radiumPathSegment(points, segment, t)
    return tangent
end

instanceMethodHandlers.ClearAllChildren = function(self)
    emit(objectNames[self] .. ":ClearAllChildren()")
    local linked = instanceChildren[self]
    if linked then
        local copy = {}
        for child in hostPairs(linked) do copy[#copy + 1] = child end
        for _, child in hostIpairs(copy) do
            instanceMethodHandlers.Destroy(child)
        end
    end
end

instanceMethodHandlers.IsDescendantOf = function(self, ancestor)
    local state = instanceStates[self]
    local current = state and state.values.Parent
    while current do
        if current == ancestor then return true end
        local parentState = instanceStates[current]
        current = parentState and parentState.values.Parent or nil
    end
    return false
end

instanceMethodHandlers.IsAncestorOf = function(self, descendant)
    return instanceMethodHandlers.IsDescendantOf(descendant, self)
end

instanceMethodHandlers.SetAttribute = function(self, name, value)
    local state = instanceStates[self]
    state.attributes = state.attributes or {}
    state.attributes[hostTostring(name)] = value
end

instanceMethodHandlers.GetAttribute = function(self, name)
    local state = instanceStates[self]
    return state.attributes and state.attributes[hostTostring(name)] or nil
end

instanceMethodHandlers.AddTag=function(self,tag)
    local tags=collectionTags[self] or {}
    collectionTags[self]=tags
    tags[hostTostring(tag)]=true
end
instanceMethodHandlers.RemoveTag=function(self,tag)
    local tags=collectionTags[self]
    if tags then tags[hostTostring(tag)]=nil end
end
instanceMethodHandlers.HasTag=function(self,tag)
    local tags=collectionTags[self]
    return tags and tags[hostTostring(tag)]==true or false
end
instanceMethodHandlers.GetTags=function(self)
    local out={}
    local tags=collectionTags[self]
    if tags then
        for tag in hostPairs(tags) do out[#out+1]=tag end
        table.sort(out)
    end
    return out
end

instanceMethodHandlers.GetAttributes = function(self)
    local state = instanceStates[self]
    local result = {}
    if state.attributes then
        for k, v in hostPairs(state.attributes) do result[k] = v end
    end
    return result
end

instanceMethodHandlers.GetFullName = function(self)
    local parts = {}
    local current = self

    while current do
        local state = instanceStates[current]

        if not state then
            break
        end

        table.insert(parts, 1, state.values.Name or state.className)
        current = state.values.Parent
    end

    return table.concat(parts, ".")
end

instanceMethodHandlers.GetPropertyChangedSignal=function(self,property)
    local state=instanceStates[self]
    local key="__PropertySignal_"..hostTostring(property)
    if not state.values[key] then state.values[key]=makeSignal(objectNames[self].."."..hostTostring(property).."Changed") end
    return state.values[key]
end

local function genericMethod(self, methodName, ...)
    local state = instanceStates[self]
    local args = {...}
    local rendered = {}

    for index, value in hostIpairs(args) do
        rendered[index] = repr(value)
    end

    emit(
        objectNames[self]
        .. ":"
        .. methodName
        .. "("
        .. table.concat(rendered, ", ")
        .. ")"
    )

    -- Only behavior that is actually modeled belongs here.
    if state and state.className == "Terrain" then
        if methodName == "WorldToCell"
            or methodName == "WorldToCellPreferSolid"
            or methodName == "WorldToCellPreferEmpty"
        then
            local position = args[1]
            return dataConstructors.Vector3int16.new(
                math.floor((position and position.X or 0) / 4),
                math.floor((position and position.Y or 0) / 4),
                math.floor((position and position.Z or 0) / 4)
            )
        elseif methodName == "CopyRegion" then
            local region = createInstance("TerrainRegion")
            proxyState[region] = {source = self}
            return region
        end
    elseif state and state.className == "Players" and methodName == "GetPlayers" then
        local result = {}
        local children = instanceChildren[self]

        if children then
            for child in hostPairs(children) do
                local childState = instanceStates[child]
                if childState and childState.className == "Player" then
                    result[#result + 1] = child
                end
            end
        end

        if state.values.LocalPlayer then
            local found = false
            for _, player in hostIpairs(result) do
                if player == state.values.LocalPlayer then found = true break end
            end
            if not found then result[#result + 1] = state.values.LocalPlayer end
        end

        return result
    elseif state and state.className == "RunService" then
        if methodName == "IsClient" then return true end
        if methodName == "IsServer" then return false end
        if methodName == "IsStudio" then return false end
        if methodName == "IsRunning" then return true end
    elseif state and state.className == "Lighting" and methodName == "GetMinutesAfterMidnight" then
        local clockTime = tonumber(state.values.ClockTime) or 0
        return (clockTime % 24) * 60
    elseif state and state.className == "PhysicsService" then
        local pstate = proxyState[self]
        if not pstate then
            pstate = {
                groups = {Default = 0},
                nextGroupId = 1,
                collidable = {},
            }
            proxyState[self] = pstate
        end

        if methodName == "RegisterCollisionGroup" then
            local name = hostTostring(args[1] or "")
            if name == "" then hostError("collision group name cannot be empty", 2) end
            if pstate.groups[name] == nil then
                pstate.groups[name] = pstate.nextGroupId
                pstate.nextGroupId += 1
            end
            return nil
        elseif methodName == "UnregisterCollisionGroup" then
            local name = hostTostring(args[1] or "")
            if name == "Default" then hostError("cannot unregister Default collision group", 2) end
            pstate.groups[name] = nil
            return nil
        elseif methodName == "GetCollisionGroupId" then
            local name = hostTostring(args[1] or "")
            local id = pstate.groups[name]
            if id == nil then hostError("collision group does not exist: " .. name, 2) end
            return id
        elseif methodName == "CollisionGroupSetCollidable" then
            local a = hostTostring(args[1] or "")
            local b = hostTostring(args[2] or "")
            if pstate.groups[a] == nil or pstate.groups[b] == nil then
                hostError("collision group does not exist", 2)
            end
            pstate.collidable[a .. "\0" .. b] = args[3] == true
            pstate.collidable[b .. "\0" .. a] = args[3] == true
            return nil
        elseif methodName == "CollisionGroupsAreCollidable" then
            local a = hostTostring(args[1] or "")
            local b = hostTostring(args[2] or "")
            local value = pstate.collidable[a .. "\0" .. b]
            if value == nil then return true end
            return value
        end
    end

    -- Do not invent an API-dump-shaped result for methods that are not modeled.
    hostError(
        (state and state.className or "Instance")
        .. ":"
        .. hostTostring(methodName)
        .. " is not implemented by Project Radium L3",
        2
    )
end

local function richTextToContentText(value)
    local textValue = hostTostring(value or "")

    -- Roblox ContentText is the visible/plain-text representation.
    -- Handle line-break tags before stripping the remaining markup.
    textValue = textValue:gsub("<[Bb][Rr]%s*/?>", "\n")

    -- Remove ordinary RichText tags while retaining their contents.
    textValue = textValue:gsub("<[^>]->", "")

    -- Minimal entity decoding commonly encountered in RichText.
    textValue = textValue:gsub("&lt;", "<")
    textValue = textValue:gsub("&gt;", ">")
    textValue = textValue:gsub("&quot;", '"')
    textValue = textValue:gsub("&apos;", "'")
    textValue = textValue:gsub("&amp;", "&")

    return textValue
end

createInstance = function(className, parent)
    proxyCount += 1

    if proxyCount > LIMITS.MAX_PROXIES then
        hostError("Project Radium L3 proxy limit reached", 0)
    end

    className = hostTostring(className or "")

    if className == "" then
        hostError("Unable to create an Instance of type \"\"", 2)
    end

    if next(classInfo) ~= nil and classInfo[className] == nil then
        hostError(
            'Unable to create an Instance of type "' .. className .. '"',
            2
        )
    end

    local obj = newproxy(true)
    local mt = hostGetmetatable(obj)
    local id = newVar(className)

    local state = {
        className = className,
        values = {
            Name = className,
            ClassName = className,
            Archivable = true,
            Parent = nil,
        },
        destroyed = false,
    }

    instanceStates[obj] = state
    objectNames[obj] = id
    objectTypes[obj] = "Instance"

    if className == "Path2D" then
        proxyState[obj] = {
            controlPoints = {},
        }
    end

    mt.__metatable = "The metatable is locked"

    mt.__index = function(self, key)
        checkRuntime()

        if hostType(key) ~= "string" then
            hostError("invalid argument #2 (string expected)", 2)
        end

        -- Destroy detaches the Instance and destroys descendants, but the Lua
        -- reference itself remains readable (Name, attributes, methods, etc.).
        if instanceMethodHandlers[key] then
            return instanceMethodHandlers[key]
        end

        if key == "ContentText"
            and (className == "TextLabel" or className == "TextButton" or className == "TextBox")
        then
            local rawText = state.values.Text or ""
            if state.values.RichText == true then
                return richTextToContentText(rawText)
            end
            return rawText
        end

        local value = state.values[key]

        if value ~= nil then
            if objectTypes[value] == "RBXScriptSignal" then
                local signalState = proxyState[value]
                if signalState and signalState.newView then
                    return signalState.newView()
                end
                return value
            end

            if hostType(value) ~= "function" then
                emit(id .. "." .. hostTostring(key))
            end
            return value
        end

        local member = classMember(className, hostTostring(key))

        if member then
            if member.MemberType == "Function" then
                return function(selfArg, ...)
                    return genericMethod(selfArg, hostTostring(key), ...)
                end
            elseif member.MemberType == "Event" then
                local signal = makeSignal(id .. "." .. hostTostring(key))
                state.values[key] = signal
                local signalState = proxyState[signal]
                return signalState and signalState.newView and signalState.newView() or signal
            elseif member.MemberType == "Property" then
                local default = defaultProperty(className, hostTostring(key))
                state.values[key] = default

                if default ~= nil then
                    emit(id .. "." .. hostTostring(key))
                end

                return default
            end
        end

        local fallback = defaultProperty(className, hostTostring(key))

        if fallback ~= nil then
            state.values[key] = fallback
            emit(id .. "." .. hostTostring(key))
            return fallback
        end

        -- Unknown Instance members are nil. Do not invent truthy children for
        -- arbitrary property accesses, because that breaks normal `a or b`
        -- fallback logic.
        return nil
    end

    mt.__newindex = function(self, key, value)
        checkRuntime()

        if hostType(key) ~= "string" then
            hostError("invalid argument #2 (string expected)", 2)
        end

        if state.className == "RunService"
            and (key == "Heartbeat" or key == "Stepped" or key == "RenderStepped")
        then
            hostError("Unable to assign property " .. key .. ". Property is read only", 2)
        end

        if key == "ClassName" then
            hostError("Unable to assign property ClassName. Property is read only", 2)
        end

        if key == "Color" and objectTypes[value] == "Color3" and value.__OutOfRange then
            hostError("Color3 value out of range",2)
        end

        if key == "Parent" then
            if value ~= nil and not instanceStates[value] and value ~= game then
                hostError("Unable to assign Parent. Instance expected, got " .. hostType(value), 2)
            end
            setParent(self, value)
        else
            if (key == "Orientation" or key == "Position" or key == "Size")
                and value ~= nil and objectTypes[value] ~= "Vector3"
            then
                hostError("Unable to assign property " .. key .. ". Vector3 expected", 2)
            end
            if key == "CFrame" and value ~= nil and objectTypes[value] ~= "CFrame" then
                hostError("Unable to assign property CFrame. CFrame expected", 2)
            end
            state.values[key] = value
        end
        local changed=state.values.Changed
        if changed and objectTypes[changed]=="RBXScriptSignal" then fireSignal(changed,key) end
        local ps=state.values["__PropertySignal_"..hostTostring(key)]
        if ps then fireSignal(ps) end
        emit(id .. "." .. hostTostring(key) .. " = " .. repr(value))
    end

    mt.__tostring = function()
        return state.values.Name or className
    end

    if parent ~= nil then
        setParent(obj, parent)
    end

    return obj
end

local serviceCache = {}

local function makeService(name)
    if serviceCache[name] then
        return serviceCache[name]
    end

    local service=createInstance(name)
    serviceCache[name]=service
    if gameServiceAddedSignal then fireSignal(gameServiceAddedSignal,service) end

    local state = instanceStates[service]
    state.values.Name = name
    state.values.ClassName = name

    return service
end

local workspace = makeService("Workspace")
objectNames[workspace] = "workspace"
proxyState[workspace] = proxyState[workspace] or {}
proxyState[workspace].serviceDeclared = true
local baseplate

local terrain = createInstance("Terrain", workspace)
instanceStates[terrain].values.Name = "Terrain"
instanceStates[workspace].values.Terrain = terrain
objectNames[terrain] = "workspace.Terrain"

local players = makeService("Players")
objectNames[players] = "Players"

local localPlayer = createInstance("Player", players)
local localPlayerState = instanceStates[localPlayer]
localPlayerState.values.Name = CONFIG.username
localPlayerState.values.DisplayName = CONFIG.displayName
localPlayerState.values.UserId = CONFIG.userId
localPlayerState.values.AccountAge = 365
localPlayerState.values.MembershipType = makeEnumType("MembershipType").None
objectNames[localPlayer] = "Players.LocalPlayer"
instanceStates[players].values.LocalPlayer = localPlayer

local character = createInstance("Model", workspace)
instanceStates[character].values.Name = CONFIG.username
localPlayerState.values.Character=character
localPlayerState.values.CharacterAdded=makeSignal("Players.LocalPlayer.CharacterAdded")
localPlayerState.values.CharacterRemoving=makeSignal("Players.LocalPlayer.CharacterRemoving")
objectNames[character]="Players.LocalPlayer.Character"

local humanoidRootPart = createInstance("Part", character)
instanceStates[humanoidRootPart].values.Name = "HumanoidRootPart"
instanceStates[humanoidRootPart].values.Size = dataConstructors.Vector3.new(2,2,1)
instanceStates[humanoidRootPart].values.Position = dataConstructors.Vector3.new(0,5,0)
instanceStates[humanoidRootPart].values.CFrame = dataConstructors.CFrame.new(0,5,0)
instanceStates[humanoidRootPart].values.Anchored = false
instanceStates[character].values.PrimaryPart = humanoidRootPart
objectNames[humanoidRootPart] = "Players.LocalPlayer.Character.HumanoidRootPart"

local playerMouse = createInstance("PlayerMouse")
instanceStates[playerMouse].values.X = 0
instanceStates[playerMouse].values.Y = 0
instanceStates[playerMouse].values.Hit = dataConstructors.CFrame.new()
instanceStates[playerMouse].values.Target = nil
localPlayerState.values.GetMouse = function() return playerMouse end

local function makeUser(id, domainType, domainId)
    local user = newproxy(true)
    local mt = hostGetmetatable(user)
    local values = {
        Id = id,
        DomainType = domainType,
        DomainId = domainId,
    }

    mark(user, "User", "User")

    local function encode()
        return string.format(
            "PRUSER1:%s:%d:%d",
            hostTostring(values.DomainType.Name or values.DomainType),
            values.DomainId,
            values.Id
        )
    end

    mt.__index = function(_, key)
        if values[key] ~= nil then
            return values[key]
        elseif key == "ToString" then
            return function()
                return encode()
            end
        end

        return nil
    end

    mt.__tostring = encode

    return user
end

local playerUser = makeUser(
    CONFIG.userId,
    makeEnumType("DomainType").EXPERIENCE,
    CONFIG.gameId + 1
)

localPlayerState.values.User = playerUser

local User = {
    fromString = function(value)
        local text = hostTostring(value)
        local domainName, domainId, id =
            text:match("^PRUSER1:([A-Z_]+):(-?%d+):(-?%d+)$")

        if not domainName then
            hostError("invalid User string", 2)
        end

        return makeUser(
            tonumber(id),
            makeEnumType("DomainType")[domainName],
            tonumber(domainId)
        )
    end,

    fromId = function(id)
        return makeUser(
            tonumber(id) or 0,
            makeEnumType("DomainType").EXPERIENCE,
            CONFIG.gameId
        )
    end,
}

local memStorageItems = {}

local memStorage = makeService("MemStorageService")
instanceStates[memStorage].values.SetItem = function(_, key, value)
    emit("MemStorageService:SetItem(" .. repr(key) .. ", " .. repr(value) .. ")")
    memStorageItems[hostTostring(key)] = hostTostring(value)
end
instanceStates[memStorage].values.GetItem = function(_, key)
    emit("MemStorageService:GetItem(" .. repr(key) .. ")")
    return memStorageItems[hostTostring(key)]
end
instanceStates[memStorage].values.RemoveItem = function(_, key)
    memStorageItems[hostTostring(key)] = nil
end

collectionTags = hostSetmetatable({}, { __mode = "k" })

local collection = makeService("CollectionService")
instanceStates[collection].values.AddTag = function(selfService, instance, tag)
    if selfService ~= collection then hostError("Expected ':' not '.' calling AddTag",2) end
    local tags = collectionTags[instance]
    if not tags then
        tags = {}
        collectionTags[instance] = tags
    end
    tags[hostTostring(tag)] = true
    emit("CollectionService:AddTag(" .. repr(instance) .. ", " .. repr(tag) .. ")")
end
instanceStates[collection].values.RemoveTag = function(_, instance, tag)
    local tags = collectionTags[instance]
    if tags then
        tags[hostTostring(tag)] = nil
    end
    emit("CollectionService:RemoveTag(" .. repr(instance) .. ", " .. repr(tag) .. ")")
end
instanceStates[collection].values.GetTagged = function(_, tag)
    local result = {}
    for instance, tags in hostPairs(collectionTags) do
        if tags[hostTostring(tag)] then
            result[#result + 1] = instance
        end
    end
    emit("CollectionService:GetTagged(" .. repr(tag) .. ")")
    return result
end
instanceStates[collection].values.HasTag = function(_, instance, tag)
    local tags = collectionTags[instance]
    return tags and tags[hostTostring(tag)] == true or false
end
instanceStates[collection].values.GetTags = function(_, instance)
    local out={}
    local tags=collectionTags[instance]
    if tags then
        for tag in hostPairs(tags) do out[#out+1]=tag end
        table.sort(out)
    end
    return out
end

local avatarEditor = makeService("AvatarEditorService")
instanceStates[avatarEditor].values.GetAvatarRulesAsync = function()
    hostError("AvatarEditorService:GetAvatarRulesAsync is not implemented by Project Radium L3",2)
end

local starterPlayer = makeService("StarterPlayer")
instanceStates[starterPlayer].values.EnableSLIMAvatars = nil

local function getPartsFilterAllows(params, instance)
    if objectTypes[params] ~= "OverlapParams" and objectTypes[params] ~= "RaycastParams" then
        return true
    end

    local filter = params.FilterDescendantsInstances
    local filterType = params.FilterType
    local include =
        filterType == makeEnumType("RaycastFilterType").Include
        or (filterType and filterType.Name == "Include")

    local found = false

    if hostType(filter) == "table" then
        for _, item in hostPairs(filter) do
            if item == instance then
                found = true
                break
            end
        end
    end

    return include and found or (not include and not found)
end

instanceStates[workspace].values.GetPartsInPart = function(_, queryPart, params)
    local result = {}

    if not instanceStates[queryPart] then
        return result
    end

    local queryCFrame = queryPart.CFrame or dataConstructors.CFrame.new()
    local querySize = queryPart.Size or dataConstructors.Vector3.new(4, 1.2, 2)
    local queryShape = queryPart.Shape
    local queryShapeName = queryShape and queryShape.Name or "Block"

    local linked = instanceChildren[workspace] or {}

    for instance in hostPairs(linked) do
        if instance ~= queryPart
            and instanceStates[instance]
            and classIsA(instanceStates[instance].className, "BasePart")
            and getPartsFilterAllows(params, instance)
        then
            local cf = instance.CFrame or dataConstructors.CFrame.new()
            local size = instance.Size or dataConstructors.Vector3.new(4, 1.2, 2)

            local dx = math.abs((cf.X or 0) - (queryCFrame.X or 0))
            local dy = math.abs((cf.Y or 0) - (queryCFrame.Y or 0))
            local dz = math.abs((cf.Z or 0) - (queryCFrame.Z or 0))
            local overlaps = false

            if queryShapeName == "Ball" then
                local radius = math.min(querySize.X, querySize.Y, querySize.Z) / 2
                local halfDiag = math.sqrt(
                    (size.X/2)^2
                    + (size.Y/2)^2
                    + (size.Z/2)^2
                )
                overlaps = math.sqrt(dx*dx + dy*dy + dz*dz) <= radius + halfDiag
            else
                overlaps =
                    dx <= (querySize.X + size.X) / 2
                    and dy <= (querySize.Y + size.Y) / 2
                    and dz <= (querySize.Z + size.Z) / 2
            end

            if overlaps then
                result[#result + 1] = instance
            end
        end
    end

    emit("workspace:GetPartsInPart(...)")
    return result
end

instanceStates[workspace].values.GetPartBoundsInBox = function(_, cframe, size, params)
    local temp = createInstance("Part")
    instanceStates[temp].values.CFrame = cframe
    instanceStates[temp].values.Size = size
    local result = instanceStates[workspace].values.GetPartsInPart(workspace, temp, params)
    instanceStates[temp].destroyed = true
    return result
end

instanceStates[workspace].values.GetPartBoundsInRadius=function(_,position,radius,params)
    return {}
end
instanceStates[workspace].values.GetPartBoundsInBox=function(_,cframe,size,params)
    return {}
end
instanceStates[workspace].values.Raycast=function(_,origin,direction,params)
    emit("workspace:Raycast(...)")
    origin=origin or dataConstructors.Vector3.zero
    direction=direction or dataConstructors.Vector3.new(0,-1,0)

    local best=nil
    local bestT=math.huge

    local function axisSlab(o,d,minv,maxv,tmin,tmax)
        if math.abs(d) < 1e-12 then
            if o < minv or o > maxv then return nil,nil end
            return tmin,tmax
        end
        local a=(minv-o)/d
        local b=(maxv-o)/d
        if a>b then a,b=b,a end
        tmin=math.max(tmin,a)
        tmax=math.min(tmax,b)
        if tmin>tmax then return nil,nil end
        return tmin,tmax
    end

    for inst,state in hostPairs(instanceStates) do
        if state and classIsA(state.className,"BasePart") and state.values.Parent ~= nil
            and getPartsFilterAllows(params,inst)
        then
            local p=state.values.Position or dataConstructors.Vector3.zero
            local s=state.values.Size or dataConstructors.Vector3.new(4,1.2,2)
            local tmin,tmax=0,1
            tmin,tmax=axisSlab(origin.X,direction.X,p.X-s.X/2,p.X+s.X/2,tmin,tmax)
            if tmin then tmin,tmax=axisSlab(origin.Y,direction.Y,p.Y-s.Y/2,p.Y+s.Y/2,tmin,tmax) end
            if tmin then tmin,tmax=axisSlab(origin.Z,direction.Z,p.Z-s.Z/2,p.Z+s.Z/2,tmin,tmax) end
            if tmin and tmin>=0 and tmin<=1 and tmin<bestT then
                bestT=tmin
                best=inst
            end
        end
    end

    if not best then return nil end

    local hitPos=origin+direction*bestT
    return makeDataValue("RaycastResult",{
        Position=hitPos,
        Normal=dataConstructors.Vector3.new(0,1,0),
        Distance=(direction*bestT).Magnitude,
        Instance=best,
        Material=makeEnumType("Material").Plastic,
    })
end

instanceStates[workspace].values.Shapecast = function()
    emit("workspace:Shapecast(...)")
    return nil
end

instanceStates[workspace].values.DistributedGameTime = 1000

local game = newproxy(true)

do
    local mt = hostGetmetatable(game)
    mark(game, "game", "Instance")
    mt.__metatable = "The metatable is locked"

    local methods={}
    gameServiceAddedSignal=makeSignal("game.ServiceAdded")

    methods.GetService = function(self, name)
        if self ~= game then
            hostError("Expected ':' not '.' calling GetService",2)
        end

        name = hostTostring(name)

        if name == "StudioService" then
            hostError("StudioService is not available in this runtime", 2)
        end

        if not serviceNames[name] then
            hostError("'"..name.."' is not a valid Service name",2)
        end

        local service = serviceCache[name]
        if not service then
            service = makeService(name)
        end

        proxyState[service] = proxyState[service] or {}

        -- Workspace already exists as the canonical Roblox global `workspace`.
        -- Do not invent a second local such as:
        -- local Workspace = game:GetService("Workspace")
        if name == "Workspace" then
            objectNames[service] = "workspace"
            proxyState[service].serviceDeclared = true
            return service
        end

        if not proxyState[service].serviceDeclared then
            local variableName = name:gsub("[^%w_]", "_")
            if variableName:match("^%d") then
                variableName = "_" .. variableName
            end

            objectNames[service] = variableName
            proxyState[service].serviceDeclared = true
            emit('local ' .. variableName .. ' = game:GetService("' .. name .. '")')
        end

        return service
    end

    methods.HttpGet = function(self, url, _useCache)
        if self ~= game then
            hostError("Expected ':' not '.' calling member function HttpGet", 2)
        end

        local source, err = requestUrl(url)

        if not source then
            hostError("HttpGet failed: " .. hostTostring(err or "unknown error"), 2)
        end

        emit("game:HttpGet(" .. repr(hostTostring(url)) .. ")")
        return source
    end

    methods.HttpGetAsync = methods.HttpGet

    methods.FindService = function(_, name)
        name = hostTostring(name)

        if serviceCache[name] then
            return serviceCache[name]
        end

        if serviceNames[name] then
            return methods.GetService(game, name)
        end

        return nil
    end

    methods.GetChildren = function()
        local list = {}
        for _, service in hostPairs(serviceCache) do
            list[#list + 1] = service
        end
        return list
    end

    methods.GetDescendants = methods.GetChildren

    mt.__index = function(_, key)
        if methods[key] then
            return methods[key]
        elseif key == "PlaceId" then
            emit("game.PlaceId")
            return CONFIG.placeId
        elseif key == "GameId" then
            emit("game.GameId")
            return CONFIG.gameId
        elseif key == "PlaceVersion" then
            return CONFIG.placeVersion
        elseif key == "CreatorType" then
            return makeEnumType("CreatorType").User
        elseif key == "CreatorId" then
            return CONFIG.userId
        elseif key == "ClassName" then
            return "DataModel"
        elseif key == "Name" then
            return "Game"
        elseif key == "Parent" then
            return nil
        elseif key=="ServiceAdded" then
            return gameServiceAddedSignal
        elseif key == "Workspace" or key == "workspace" then
            return workspace
        elseif key == "Players" then
            return players
        end

        local existingService = serviceCache[key]
        if existingService then
            return existingService
        end

        -- Unknown DataModel properties are nil.
        return nil
    end

    mt.__tostring = function()
        return "Game"
    end
end

instanceStates[workspace].values.Parent = game
instanceStates[players].values.Parent = game

local function regexEscape(value)
    local input = hostTostring(value or "")
    return (input:gsub("([\\%.%+%-%*%?%[%]%^%$%(%)%{%}%|])", "\\%1"))
end

local Regex = {
    Escape = regexEscape,
}

Regex.new = function(patternValue)
    local pattern = hostTostring(patternValue or "")
    local object = newproxy(true)
    local mt = hostGetmetatable(object)

    mark(object, "RegexObject", "RegexObject")

    mt.__index = function(_, key)
        if key == "Match" then
            return function(_, subject)
                local text = hostTostring(subject or "")
                local startPos, endPos = string.find(text, pattern, 1, true)

                if startPos == nil then
                    return nil
                end

                return string.sub(text, startPos, endPos)
            end
        elseif key == "MatchMany" then
            return function(_, subject)
                local text = hostTostring(subject or "")
                local result = {}
                local cursor = 1

                if pattern == "" then
                    return result
                end

                while cursor <= #text do
                    local startPos, endPos =
                        string.find(text, pattern, cursor, true)

                    if not startPos then
                        break
                    end

                    result[#result + 1] =
                        string.sub(text, startPos, endPos)

                    cursor = endPos + 1
                end

                return result
            end
        elseif key == "Replace" then
            return function(_, subject, replacement)
                local text = hostTostring(subject or "")
                local escaped = pattern:gsub("([^%w])", "%%%1")
                return (text:gsub(escaped, hostTostring(replacement or "")))
            end
        end

        return nil
    end

    return object
end

-- Common Roblox runtime objects / services used by ordinary scripts and
-- compatibility tests. These are concrete semantics, not anti-detection aliases.

local currentCamera = createInstance("Camera", workspace)
instanceStates[currentCamera].values.Name = "Camera"
instanceStates[currentCamera].values.CFrame = dataConstructors.CFrame.new()
instanceStates[currentCamera].values.Focus = dataConstructors.CFrame.new()
instanceStates[currentCamera].values.FieldOfView = 70
instanceStates[workspace].values.CurrentCamera = currentCamera
objectNames[currentCamera] = "workspace.CurrentCamera"

instanceStates[currentCamera].values.WorldToScreenPoint=function(_,point)
    point=point or dataConstructors.Vector3.zero
    return dataConstructors.Vector3.new(point.X,point.Y,point.Z),true
end
instanceStates[currentCamera].values.WorldToViewportPoint=instanceStates[currentCamera].values.WorldToScreenPoint
instanceStates[currentCamera].values.ScreenPointToRay=function(_,x,y,depth)
    return dataConstructors.Ray.new(
        dataConstructors.Vector3.new(tonumber(x) or 0, tonumber(y) or 0, tonumber(depth) or 0),
        dataConstructors.Vector3.new(0,0,-1)
    )
end
instanceStates[currentCamera].values.ViewportPointToRay=instanceStates[currentCamera].values.ScreenPointToRay

baseplate = createInstance("Part", workspace)
instanceStates[baseplate].values.Name = "Baseplate"
instanceStates[baseplate].values.Anchored = true
instanceStates[baseplate].values.Size = dataConstructors.Vector3.new(512, 1, 512)
objectNames[baseplate] = "workspace.Baseplate"

local humanoid = createInstance("Humanoid", character)
instanceStates[humanoid].values.Name = "Humanoid"
objectNames[humanoid] = "Players.LocalPlayer.Character.Humanoid"

local humanoidValues=instanceStates[humanoid].values
humanoidValues.ChangeState=function(_,newState)
    local old=humanoidValues.__State or makeEnumType("HumanoidStateType").Running
    humanoidValues.__State=newState
    humanoidValues.Jump=(newState==makeEnumType("HumanoidStateType").Jumping)
    if humanoidValues.Jump then
        local root=findChild(character,"HumanoidRootPart",false)
        if root then
            local rs=instanceStates[root]
            local p=rs.values.Position or dataConstructors.Vector3.zero
            rs.values.Position=dataConstructors.Vector3.new(p.X,p.Y+5,p.Z)
            rs.values.CFrame=dataConstructors.CFrame.new(rs.values.Position)
            rs.values.Velocity=dataConstructors.Vector3.new(0,50,0)
            rs.values.AssemblyLinearVelocity=rs.values.Velocity
        end
    end
    if humanoidValues.StateChanged then fireSignal(humanoidValues.StateChanged,old,newState) end
    if humanoidValues.Jump and humanoidValues.Jumping then fireSignal(humanoidValues.Jumping,true) end
end
humanoidValues.GetState=function() return humanoidValues.__State or makeEnumType("HumanoidStateType").Running end

local starterPlayerScripts = createInstance("StarterPlayerScripts", starterPlayer)
instanceStates[starterPlayerScripts].values.Name = "StarterPlayerScripts"
local starterCharacterScripts = createInstance("StarterCharacterScripts", starterPlayer)
instanceStates[starterCharacterScripts].values.Name = "StarterCharacterScripts"
instanceStates[starterPlayer].values.StarterPlayerScripts = starterPlayerScripts
instanceStates[starterPlayer].values.StarterCharacterScripts = starterCharacterScripts

local runService = makeService("RunService")
local runValues = instanceStates[runService].values
runValues.Heartbeat = makeSignal("RunService.Heartbeat")
runValues.Stepped = makeSignal("RunService.Stepped")
runValues.RenderStepped = makeSignal("RunService.RenderStepped")
runValues.ClientGitHash="Madium"
runValues.RunState=makeEnumType("RunState").Running
runValues.IsClient=function(self)
    if self ~= runService then hostError("Expected ':' not '.' calling IsClient",2) end
    return true
end
runValues.IsServer=function(self)
    if self ~= runService then hostError("Expected ':' not '.' calling IsServer",2) end
    return false
end
runValues.IsStudio=function(self)
    if self ~= runService then hostError("Expected ':' not '.' calling IsStudio",2) end
    return false
end
runValues.IsRunning=function(self)
    if self ~= runService then hostError("Expected ':' not '.' calling IsRunning",2) end
    return true
end

local lighting = makeService("Lighting")
local lightingValues = instanceStates[lighting].values
lightingValues.Ambient = dataConstructors.Color3.new(0.5, 0.5, 0.5)
lightingValues.OutdoorAmbient = dataConstructors.Color3.new(0.5, 0.5, 0.5)
lightingValues.Brightness=2
lightingValues.ClockTime=14
lightingValues.FogColor=dataConstructors.Color3.new(0.75,0.75,0.75)
lightingValues.FogStart=0
lightingValues.FogEnd=100000
lightingValues.GeographicLatitude=41.733

local httpService = makeService("HttpService")
local httpValues = instanceStates[httpService].values

httpValues.JSONDecode = function(_, source)
    if hostType(source) ~= "string" then
        hostError("invalid argument #1 to 'JSONDecode' (string expected)", 2)
    end

    local ok, result = hostPcall(serde.decode, "json", source)

    if not ok then
        hostError(hostTostring(result), 2)
    end

    return result
end

httpValues.JSONEncode = function(_, value)
    local ok, result = hostPcall(serde.encode, "json", value)

    if not ok then
        hostError(hostTostring(result), 2)
    end

    return result
end

httpValues.GetAsync = function(_, url, _nocache, _headers)
    local source, err = requestUrl(url)
    if not source then
        hostError("GetAsync failed: " .. hostTostring(err or "unknown error"), 2)
    end
    return source
end

httpValues.GetSecret=function(_,value)
    if hostType(value) ~= "string"
        or value == ""
        or value:find("%s")
        or value:find("://", 1, true)
        or #value > 128
    then
        hostError("invalid secret key",2)
    end
    return makeDataValue("Secret",{Value=value,Prefix="",Suffix=""})
end

httpValues.GenerateGUID = function(_, wrapInCurlyBraces)
    proxyState[httpService] = proxyState[httpService] or {guidCounter = 0}
    proxyState[httpService].guidCounter += 1

    local seed = math.floor((hostClock() * 1000000) + proxyState[httpService].guidCounter)
    local state = seed % 2147483647
    local function nibble()
        state = (state * 48271) % 2147483647
        return state % 16
    end

    local chars = {}
    for i = 1, 32 do
        local n = nibble()
        if i == 13 then n = 4 end
        if i == 17 then n = 8 + (n % 4) end
        chars[i] = string.format("%x", n)
    end

    local raw = table.concat(chars)
    local guid = raw:sub(1,8) .. "-" .. raw:sub(9,12) .. "-" .. raw:sub(13,16)
        .. "-" .. raw:sub(17,20) .. "-" .. raw:sub(21,32)

    if wrapInCurlyBraces == true then return "{" .. guid .. "}" end
    return guid
end

local encodingService=makeService("EncodingService")
local encodingValues=instanceStates[encodingService].values

encodingValues.CompressBuffer=function(self,input,algorithm,level)
    if self ~= encodingService then hostError("Expected ':' not '.' calling CompressBuffer",2) end
    if input == nil then hostError("buffer expected",2) end

    if hostType(serde.compress) == "function" then
        local source = buffer.tostring(input)
        local name = algorithm and algorithm.Name or "Zstd"
        local ok, compressed = hostPcall(serde.compress, name, source, level)
        if ok then
            if hostType(compressed) == "string" and hostType(buffer.fromstring) == "function" then
                return buffer.fromstring(compressed)
            end
            return compressed
        end
        hostError(hostTostring(compressed),2)
    end

    hostError("EncodingService compression is unavailable in this host",2)
end

encodingValues.DecompressBuffer=function(self,input,algorithm)
    if self ~= encodingService then hostError("Expected ':' not '.' calling DecompressBuffer",2) end
    if input == nil then hostError("buffer expected",2) end

    if hostType(serde.decompress) == "function" then
        local source = buffer.tostring(input)
        local name = algorithm and algorithm.Name or "Zstd"
        local ok, decompressed = hostPcall(serde.decompress, name, source)
        if ok then
            if hostType(decompressed) == "string" and hostType(buffer.fromstring) == "function" then
                return buffer.fromstring(decompressed)
            end
            return decompressed
        end
        hostError(hostTostring(decompressed),2)
    end

    hostError("EncodingService decompression is unavailable in this host",2)
end

local marketplace = makeService("MarketplaceService")
instanceStates[marketplace].values.GetProductInfo = function(self, assetId)
    if self ~= marketplace then hostError("Expected ':' not '.' calling GetProductInfo",2) end
    local id = tonumber(assetId)
    if not id or id <= 0 then hostError("invalid asset id",2) end

    local body, err = requestUrl(
        "https://economy.roblox.com/v2/assets/" .. hostTostring(math.floor(id)) .. "/details"
    )
    if not body then hostError("GetProductInfo request failed: " .. hostTostring(err),2) end

    local ok, decoded = hostPcall(serde.decode, "json", body)
    if not ok or hostType(decoded) ~= "table" then
        hostError("GetProductInfo returned invalid JSON",2)
    end

    -- Preserve the actual response and add the conventional AssetId field if absent.
    if decoded.AssetId == nil then decoded.AssetId = math.floor(id) end
    return decoded
end

local tweenService = makeService("TweenService")
instanceStates[tweenService].values.Create=function(_,target,tweenInfo,goals)
    if not instanceStates[target] then hostError("Instance expected",2) end
    if hostType(goals)~="table" then hostError("table expected",2) end
    for key,value in hostPairs(goals) do
        if (key=="Position" or key=="Size" or key=="Orientation") and objectTypes[value]~="Vector3" then hostError(key.." expects Vector3",2) end
        if key=="CFrame" and objectTypes[value]~="CFrame" then hostError("CFrame expects CFrame",2) end
        if key=="Color" and objectTypes[value]~="Color3" then hostError("Color expects Color3",2) end
        if key=="Transparency" and hostType(value)~="number" then hostError("Transparency expects number",2) end
    end
    local tween=createInstance("Tween")
    local values = instanceStates[tween].values
    values.Completed = makeSignal(objectNames[tween] .. ".Completed")
    values.Play = function()
        if hostType(goals) == "table" then
            for key, value in hostPairs(goals) do
                local state = instanceStates[target]
                if state then state.values[key] = value end
            end
        end
        fireSignal(values.Completed, makeEnumType("PlaybackState").Completed)
    end
    values.Cancel = function()
        fireSignal(values.Completed, makeEnumType("PlaybackState").Cancelled)
    end
    values.Pause = function() end
    return tween
end

local contextAction = makeService("ContextActionService")
local boundActions = {}
instanceStates[contextAction].values.BindAction = function(_, name, callback, createTouchButton, ...)
    boundActions[hostTostring(name)] = {
        callback = callback,
        createTouchButton = createTouchButton == true,
        inputs = {...},
    }
end
instanceStates[contextAction].values.UnbindAction = function(_, name)
    boundActions[hostTostring(name)] = nil
end
instanceStates[contextAction].values.GetAllBoundActionInfo = function()
    local out = {}
    for name in hostPairs(boundActions) do out[name] = {} end
    return out
end

local userInput = makeService("UserInputService")
local uiValues = instanceStates[userInput].values
uiValues.TouchEnabled=false
uiValues.AccelerometerEnabled=false
uiValues.GyroscopeEnabled=false
uiValues.VREnabled=false
uiValues.MouseIcon=""
uiValues.KeyboardEnabled=true
uiValues.MouseEnabled = true
uiValues.GamepadEnabled = false
uiValues.InputBegan = makeSignal("UserInputService.InputBegan")
uiValues.InputEnded = makeSignal("UserInputService.InputEnded")
uiValues.InputChanged = makeSignal("UserInputService.InputChanged")

local assetService = makeService("AssetService")

local function colorToBytes(color, transparency)
    local r = math.floor(math.max(0, math.min(1, color and color.R or 0)) * 255 + 0.5)
    local g = math.floor(math.max(0, math.min(1, color and color.G or 0)) * 255 + 0.5)
    local b = math.floor(math.max(0, math.min(1, color and color.B or 0)) * 255 + 0.5)
    local alpha = math.floor((1 - math.max(0, math.min(1, tonumber(transparency) or 0))) * 255 + 0.5)
    return r, g, b, alpha
end

local function editableImageIndex(width, x, y)
    return (y * width + x) * 4
end

local function makeEditableImage(size)
    size = size or dataConstructors.Vector2.new(1, 1)

    local width = math.max(1, math.floor(tonumber(size.X) or 1))
    local height = math.max(1, math.floor(tonumber(size.Y) or 1))

    local image = createInstance("EditableImage")
    local state = instanceStates[image]
    local values = state.values

    values.Size = dataConstructors.Vector2.new(width, height)

    local pixels = buffer.create(width * height * 4)

    local function inBounds(x, y)
        return x >= 0 and y >= 0 and x < width and y < height
    end

    local function setPixel(x, y, r, g, b, a)
        x = math.floor(x)
        y = math.floor(y)

        if not inBounds(x, y) then
            return
        end

        local offset = editableImageIndex(width, x, y)
        buffer.writeu8(pixels, offset, r)
        buffer.writeu8(pixels, offset + 1, g)
        buffer.writeu8(pixels, offset + 2, b)
        buffer.writeu8(pixels, offset + 3, a)
    end

    local function getPixel(x, y)
        x = math.floor(x)
        y = math.floor(y)

        if not inBounds(x, y) then
            return 0, 0, 0, 0
        end

        local offset = editableImageIndex(width, x, y)
        return
            buffer.readu8(pixels, offset),
            buffer.readu8(pixels, offset + 1),
            buffer.readu8(pixels, offset + 2),
            buffer.readu8(pixels, offset + 3)
    end

    values.ReadPixelsBuffer = function(_, position, readSize)
        local px = math.floor(tonumber(position and position.X) or 0)
        local py = math.floor(tonumber(position and position.Y) or 0)
        local rw = math.max(0, math.floor(tonumber(readSize and readSize.X) or 0))
        local rh = math.max(0, math.floor(tonumber(readSize and readSize.Y) or 0))

        local out = buffer.create(rw * rh * 4)
        local outOffset = 0

        for y = 0, rh - 1 do
            for x = 0, rw - 1 do
                local r, g, b, a = getPixel(px + x, py + y)
                buffer.writeu8(out, outOffset, r)
                buffer.writeu8(out, outOffset + 1, g)
                buffer.writeu8(out, outOffset + 2, b)
                buffer.writeu8(out, outOffset + 3, a)
                outOffset += 4
            end
        end

        return out
    end

    values.WritePixelsBuffer = function(_, position, writeSize, source)
        local px = math.floor(tonumber(position and position.X) or 0)
        local py = math.floor(tonumber(position and position.Y) or 0)
        local rw = math.max(0, math.floor(tonumber(writeSize and writeSize.X) or 0))
        local rh = math.max(0, math.floor(tonumber(writeSize and writeSize.Y) or 0))

        local expected = rw * rh * 4
        if buffer.len(source) < expected then
            hostError("buffer is too small for requested image region", 2)
        end

        local sourceOffset = 0

        for y = 0, rh - 1 do
            for x = 0, rw - 1 do
                setPixel(
                    px + x,
                    py + y,
                    buffer.readu8(source, sourceOffset),
                    buffer.readu8(source, sourceOffset + 1),
                    buffer.readu8(source, sourceOffset + 2),
                    buffer.readu8(source, sourceOffset + 3)
                )
                sourceOffset += 4
            end
        end
    end

    values.DrawRectangle = function(_, position, rectSize, color, transparency)
        local px = math.floor(tonumber(position and position.X) or 0)
        local py = math.floor(tonumber(position and position.Y) or 0)
        local rw = math.max(0, math.floor(tonumber(rectSize and rectSize.X) or 0))
        local rh = math.max(0, math.floor(tonumber(rectSize and rectSize.Y) or 0))
        local r, g, b, a = colorToBytes(color, transparency)

        for y = 0, rh - 1 do
            for x = 0, rw - 1 do
                setPixel(px + x, py + y, r, g, b, a)
            end
        end
    end

    values.DrawLine = function(_, fromPoint, toPoint, color, transparency)
        local x0 = math.floor(tonumber(fromPoint and fromPoint.X) or 0)
        local y0 = math.floor(tonumber(fromPoint and fromPoint.Y) or 0)
        local x1 = math.floor(tonumber(toPoint and toPoint.X) or 0)
        local y1 = math.floor(tonumber(toPoint and toPoint.Y) or 0)
        local r, g, b, a = colorToBytes(color, transparency)

        local dx = math.abs(x1 - x0)
        local sx = x0 < x1 and 1 or -1
        local dy = -math.abs(y1 - y0)
        local sy = y0 < y1 and 1 or -1
        local err = dx + dy

        while true do
            setPixel(x0, y0, r, g, b, a)

            if x0 == x1 and y0 == y1 then
                break
            end

            local e2 = 2 * err

            if e2 >= dy then
                err += dy
                x0 += sx
            end

            if e2 <= dx then
                err += dx
                y0 += sy
            end
        end
    end

    values.DrawCircle = function(_, center, radius, color, transparency)
        local cx = math.floor(tonumber(center and center.X) or 0)
        local cy = math.floor(tonumber(center and center.Y) or 0)
        local rr = math.max(0, tonumber(radius) or 0)
        local r, g, b, a = colorToBytes(color, transparency)

        local ir = math.ceil(rr)

        for y = -ir, ir do
            for x = -ir, ir do
                if x * x + y * y <= rr * rr then
                    setPixel(cx + x, cy + y, r, g, b, a)
                end
            end
        end
    end

    local function copyImageAt(position, sourceImage)
        local sourceState = instanceStates[sourceImage]
        if not sourceState or sourceState.className ~= "EditableImage" then
            hostError("EditableImage expected", 2)
        end

        local sourceSize = sourceState.values.Size
        local sw = math.floor(sourceSize.X)
        local sh = math.floor(sourceSize.Y)
        local sourceBuffer = sourceState.values.ReadPixelsBuffer(
            sourceImage,
            dataConstructors.Vector2.zero,
            sourceSize
        )

        values.WritePixelsBuffer(
            image,
            position or dataConstructors.Vector2.zero,
            sourceSize,
            sourceBuffer
        )
    end

    values.DrawImage = function(_, position, sourceImage)
        copyImageAt(position, sourceImage)
    end

    values.DrawImageTransformed = function(_, position, _scale, _rotation, sourceImage)
        copyImageAt(position, sourceImage)
    end

    values.DrawImageProjected = function()
        return nil
    end

    values.SampleImageProjected = function()
        return nil
    end

    values.__PixelBuffer = pixels

    return image
end

local function makeEditableMesh()
    local mesh = createInstance("EditableMesh")
    local state = instanceStates[mesh]
    local values = state.values

    local nextVertexId = 1
    local nextFaceId = 1
    local vertices = {}
    local triangles = {}

    values.AddVertex = function(_, position)
        local id = nextVertexId
        nextVertexId += 1
        vertices[id] = position or dataConstructors.Vector3.zero
        return id
    end

    values.AddTriangle = function(_, a, b, c)
        local id = nextFaceId
        nextFaceId += 1
        triangles[id] = {a, b, c}
        return id
    end

    values.GetVertices = function()
        local out = {}
        for id in hostPairs(vertices) do
            out[#out + 1] = id
        end
        return out
    end

    values.GetTriangles = function()
        local out = {}
        for id in hostPairs(triangles) do
            out[#out + 1] = id
        end
        return out
    end

    return mesh
end

local assetValues = instanceStates[assetService].values

assetValues.CreateEditableImage = function(_, options)
    local size = nil

    if hostType(options) == "table" then
        size = options.Size
    end

    return makeEditableImage(size or dataConstructors.Vector2.new(1, 1))
end

assetValues.CreateEditableMesh = function()
    return makeEditableMesh()
end

local contentProvider = makeService("ContentProvider")
local contentValues = instanceStates[contentProvider].values

proxyState[contentProvider] = {
    encryptedAssets = {},
}

contentValues.BaseUrl = "http://www.roblox.com/"
contentValues.RequestQueueSize = 0

contentValues.RegisterEncryptedAsset = function(self, assetId, key)
    if self ~= contentProvider then
        hostError("Expected ':' not '.' calling RegisterEncryptedAsset", 2)
    end

    if hostType(assetId) ~= "string" or assetId == "" then
        hostError("invalid argument #1 to 'RegisterEncryptedAsset' (string expected)", 2)
    end

    if hostType(key) ~= "string" or key == "" then
        hostError("invalid argument #2 to 'RegisterEncryptedAsset' (string expected)", 2)
    end

    proxyState[contentProvider].encryptedAssets[assetId] = key

    emit(
        objectNames[contentProvider]
        .. ":RegisterEncryptedAsset("
        .. repr(assetId)
        .. ", "
        .. repr(key)
        .. ")"
    )
end

contentValues.ListEncryptedAssets = function(self)
    if self ~= contentProvider then
        hostError("Expected ':' not '.' calling ListEncryptedAssets", 2)
    end

    local result = {}

    for assetId in hostPairs(proxyState[contentProvider].encryptedAssets) do
        result[#result + 1] = assetId
    end

    table.sort(result)

    emit(
        objectNames[contentProvider]
        .. ":ListEncryptedAssets()"
    )

    return result
end

contentValues.UnregisterEncryptedAsset = function(self, assetId)
    if self ~= contentProvider then
        hostError("Expected ':' not '.' calling UnregisterEncryptedAsset", 2)
    end

    if hostType(assetId) ~= "string" or assetId == "" then
        hostError("invalid argument #1 to 'UnregisterEncryptedAsset' (string expected)", 2)
    end

    proxyState[contentProvider].encryptedAssets[assetId] = nil

    emit(
        objectNames[contentProvider]
        .. ":UnregisterEncryptedAsset("
        .. repr(assetId)
        .. ")"
    )
end

contentValues.PreloadAsync = function(_, assets, callback)
    if hostType(callback) == "function" and hostType(assets) == "table" then
        for _, asset in hostIpairs(assets) do
            hostPcall(callback, hostTostring(asset), makeEnumType("AssetFetchStatus").Success)
        end
    end
    return nil
end

local guiService = makeService("GuiService")
local guiValues = instanceStates[guiService].values
local inspectMenuEnabled = true

guiValues.GetInspectMenuEnabled = function()
    return inspectMenuEnabled
end

guiValues.SetInspectMenuEnabled = function(_, value)
    if hostType(value) ~= "boolean" then
        hostError("invalid argument #1 to 'SetInspectMenuEnabled' (boolean expected)", 2)
    end
    inspectMenuEnabled = value
end

local pathfinding = makeService("PathfindingService")
instanceStates[pathfinding].values.CreatePath = function(self, agentParameters)
    if self ~= pathfinding then hostError("Expected ':' not '.' calling CreatePath",2) end

    local path = createInstance("Path")
    local values = instanceStates[path].values
    proxyState[path] = {
        agentParameters = hostType(agentParameters) == "table" and agentParameters or {},
        waypoints = {},
        computed = false,
    }

    values.Status = makeEnumType("PathStatus").NoPath
    values.Blocked = makeSignal(objectNames[path] .. ".Blocked")

    values.ComputeAsync = function(selfPath, startPosition, finishPosition)
        if selfPath ~= path then hostError("Expected ':' not '.' calling ComputeAsync",2) end
        if objectTypes[startPosition] ~= "Vector3" or objectTypes[finishPosition] ~= "Vector3" then
            hostError("Vector3 expected",2)
        end

        proxyState[path].waypoints = {
            dataConstructors.PathWaypoint.new(startPosition, makeEnumType("PathWaypointAction").Walk),
            dataConstructors.PathWaypoint.new(finishPosition, makeEnumType("PathWaypointAction").Walk),
        }
        proxyState[path].computed = true
        values.Status = makeEnumType("PathStatus").Success
    end

    values.GetWaypoints = function(selfPath)
        if selfPath ~= path then hostError("Expected ':' not '.' calling GetWaypoints",2) end
        local out = {}
        for i, waypoint in hostIpairs(proxyState[path].waypoints) do out[i] = waypoint end
        return out
    end

    return path
end

local logService = makeService("LogService")
proxyState[logService] = {history = {}}
instanceStates[logService].values.MessageOut = makeSignal("LogService.MessageOut")
instanceStates[logService].values.GetLogHistory = function(self)
    if self ~= logService then hostError("Expected ':' not '.' calling GetLogHistory",2) end
    local out = {}
    for i, record in hostIpairs(proxyState[logService].history) do
        out[i] = {
            message = record.message,
            messageType = record.messageType,
            timestamp = record.timestamp,
        }
    end
    return out
end

local teams = makeService("Teams")
instanceStates[teams].values.GetTeams = function()
    local out = {}
    local linked = instanceChildren[teams]
    if linked then
        for child in hostPairs(linked) do
            if instanceStates[child] and instanceStates[child].className == "Team" then
                out[#out + 1] = child
            end
        end
    end
    return out
end

instanceStates[players].values.GetPlayerFromCharacter = function(_, model)
    if model == character then
        return localPlayer
    end
    return nil
end

instanceStates[players].values.GetNameFromUserIdAsync=function(_,id)
    local n=tonumber(id)
    if not n or n<=0 or n~=math.floor(n) then hostError("Invalid userId",2) end
    if n==CONFIG.userId then return CONFIG.username end
    return "Player"..hostTostring(n)
end
instanceStates[players].values.GetUserIdFromNameAsync = function(_, name)
    if hostTostring(name) == CONFIG.username then return CONFIG.userId end
    return 0
end
instanceStates[players].values.GetPlayers = function()
    return {localPlayer}
end

instanceStates[collection].values.GetTags = function(_, instance)
    local out = {}
    local tags = collectionTags[instance]
    if tags then
        for tag in hostPairs(tags) do out[#out + 1] = tag end
    end
    return out
end

local statsService = makeService("Stats")
instanceStates[statsService].values.ContactsCount=0
instanceStates[statsService].values.FrameTime=1/60
instanceStates[statsService].values.HeartbeatTimeMs=16.6667
instanceStates[statsService].values.HeartbeatTime=1/60
instanceStates[statsService].values.MemoryTrackingEnabled=false


local function normalizeSandboxPath(path)
    path = hostTostring(path or "")
    path = path:gsub("\\", "/")
    path = path:gsub("^/+", "")
    path = path:gsub("/+", "/")

    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == "." or part == "" then
            -- skip
        elseif part == ".." then
            hostError("path traversal is not allowed", 2)
        else
            parts[#parts + 1] = part
        end
    end

    return table.concat(parts, "/")
end

local function sandboxPath(path)
    local rel = normalizeSandboxPath(path)
    if rel == "" then
        return CONFIG.sandboxRoot, ""
    end
    return CONFIG.sandboxRoot .. "/" .. rel, rel
end

local function ensureSandboxRoot()
    if not fs.isDir(CONFIG.sandboxRoot) then
        fs.writeDir(CONFIG.sandboxRoot)
    end
end

ensureSandboxRoot()

local function listSandbox(path)
    local full, rel = sandboxPath(path)
    if not fs.isDir(full) then
        hostError("folder does not exist: " .. rel, 2)
    end

    local ok, entries = hostPcall(fs.readDir, full)
    if not ok then
        hostError(hostTostring(entries), 2)
    end

    local out = {}
    for _, entry in hostIpairs(entries) do
        local name = entry
        if hostType(entry) == "table" then
            name = entry.name or entry.path or entry[1]
        end
        if name then
            local clean = hostTostring(name):gsub("\\", "/")
            clean = clean:match("([^/]+)$") or clean
            if rel == "" then
                out[#out + 1] = clean
            else
                out[#out + 1] = rel .. "/" .. clean
            end
        end
    end
    return out
end

local sandbox = {}
local dynamicLoader
local dynamicFunctionInfo=hostSetmetatable({}, {__mode="k"})
local activeDynamicEnv = nil

local settingsServices = {}

local physicsSettings = newproxy(true)
do
    local mt = hostGetmetatable(physicsSettings)
    mark(physicsSettings, "PhysicsSettings", "PhysicsSettings")

    local values = {
        PhysicsEnvironmentalThrottle = makeEnumType("EnviromentalPhysicsThrottle").DefaultAuto,
        AllowSleep = true,
        ShowDecompositionGeometry = false,
    }

    mt.__metatable = "The metatable is locked"

    mt.__index = function(_, key)
        return values[key]
    end

    mt.__newindex = function(_, key, value)
        values[key] = value
    end

    mt.__tostring = function()
        return "PhysicsSettings"
    end
end

settingsServices.PhysicsSettings = physicsSettings

local settingsObject = newproxy(true)
do
    local mt = hostGetmetatable(settingsObject)
    mark(settingsObject, "settings()", "Instance")
    mt.__metatable = "The metatable is locked"

    mt.__index = function(_, key)
        if key == "GetService" then
            return function(_, name)
                local service = settingsServices[hostTostring(name)]
                if service then
                    return service
                end

                hostError(hostTostring(name) .. " is not a valid settings service", 2)
            end
        end

        return nil
    end
end

local function sandboxType(value)
    if objectTypes[value] == "Instance" then
        return "userdata"
    elseif objectTypes[value] == "RegexObject" then
        return "userdata"
    end

    return hostType(value)
end

local function sandboxTypeof(value)
    return objectTypes[value] or hostTypeof(value)
end

local function sandboxGetmetatable(value)
    if hostType(value) == "string" then
        return {}
    end

    return hostGetmetatable(value)
end

local function runTask(callback, ...)
    if hostType(callback) ~= "function" then
        hostError("invalid argument #1 (function expected)", 2)
    end

    local co = coroutine.create(callback)
    local result = table.pack(coroutine.resume(co, ...))

    if not result[1] then
        hostError(result[2], 0)
    end

    return hostUnpack(result, 2, result.n)
end

local taskLib = {}
local pendingTasks = {}
local cancelledThreads = hostSetmetatable({}, { __mode = "k" })
local managedThreads = hostSetmetatable({}, { __mode = "k" })

local function scheduleTask(delaySeconds, callback, args)
    local thread = coroutine.create(callback)
    managedThreads[thread] = true
    pendingTasks[#pendingTasks + 1] = {
        due = virtualTime + math.max(0, tonumber(delaySeconds) or 0),
        thread = thread,
        args = args or {},
    }
    return thread
end

local function pumpTasks()
    while true do
        local selected=nil
        local due=nil

        for i,item in hostIpairs(pendingTasks) do
            if item and item.due<=virtualTime and (due==nil or item.due<due) then
                selected=i
                due=item.due
            end
        end

        if not selected then break end

        local item=table.remove(pendingTasks,selected)

        if item and not cancelledThreads[item.thread] then
            local result=table.pack(coroutine.resume(item.thread,hostUnpack(item.args)))

            if not result[1] then
                hostWarn("[Madium task] "..hostTostring(result[2]))
            elseif coroutine.status(item.thread) ~= "dead" then
                local yieldKind = result[2]
                local waitFor = tonumber(result[3]) or 0

                if yieldKind == "__madium_wait" then
                    pendingTasks[#pendingTasks+1] = {
                        due = virtualTime + math.max(waitFor, 1/60),
                        thread = item.thread,
                        args = {math.max(waitFor, 1/60)},
                    }
                else
                    pendingTasks[#pendingTasks+1] = {
                        due = virtualTime + 1/60,
                        thread = item.thread,
                        args = {},
                    }
                end
            end
        end
    end
end

local function fireRunServiceStep(dt)
    local runService = serviceCache.RunService
    if not runService then return end
    local values = instanceStates[runService] and instanceStates[runService].values
    if not values then return end
    if values.Heartbeat then fireSignal(values.Heartbeat, dt) end
    if values.Stepped then fireSignal(values.Stepped, virtualTime, dt) end
    if values.RenderStepped then fireSignal(values.RenderStepped, dt) end
end

local function advanceSimulation(requested)
    local wallStart=hostClock()
    while hostClock()-wallStart < requested do end

    virtualTime += requested

    local gravity=instanceStates[workspace].values.Gravity or 196.2
    for inst,state in hostPairs(instanceStates) do
        if state and classIsA(state.className,"BasePart") and state.values.Parent~=nil and state.values.Anchored~=true then
            local cf=state.values.CFrame or dataConstructors.CFrame.new()
            local oldVelocity=state.values.Velocity or state.values.AssemblyLinearVelocity or dataConstructors.Vector3.zero
            local newVelocity=dataConstructors.Vector3.new(oldVelocity.X,oldVelocity.Y-gravity*requested,oldVelocity.Z)
            state.values.Velocity=newVelocity
            state.values.AssemblyLinearVelocity=newVelocity
            state.values.CFrame=dataConstructors.CFrame.new(
                cf.X+newVelocity.X*requested,
                cf.Y+newVelocity.Y*requested,
                cf.Z+newVelocity.Z*requested
            )
            state.values.Position=state.values.CFrame.Position
        end
    end

    fireRunServiceStep(requested)
end

taskLib.wait = function(duration)
    local requested = tonumber(duration)
    if requested == nil or requested < 1/60 then requested = 1/60 end

    emit("task.wait(" .. repr(requested) .. ")")

    local running = coroutine.running()
    if running and managedThreads[running] then
        return coroutine.yield("__madium_wait", requested)
    end

    advanceSimulation(requested)
    pumpTasks()
    return requested
end

taskLib.spawn = function(callback, ...)
    emit("task.spawn(function(...) end)")
    local thread = coroutine.create(callback)
    managedThreads[thread] = true
    local result=table.pack(coroutine.resume(thread,...))

    if not result[1] then
        hostWarn("[Madium task] "..hostTostring(result[2]))
    elseif coroutine.status(thread) ~= "dead" then
        local waitFor = result[2] == "__madium_wait" and (tonumber(result[3]) or 1/60) or 1/60
        pendingTasks[#pendingTasks+1] = {
            due = virtualTime + math.max(waitFor, 1/60),
            thread = thread,
            args = {math.max(waitFor, 1/60)},
        }
    end

    return thread
end

taskLib.defer = function(callback, ...)
    emit("task.defer(function(...) end)")
    return scheduleTask(1 / 60, callback, {...})
end

taskLib.delay = function(delaySeconds, callback, ...)
    emit("task.delay(...)")
    return scheduleTask(tonumber(delaySeconds) or 0, callback, {...})
end

taskLib.cancel = function(thread)
    cancelledThreads[thread] = true
end

local function sandboxPrint(...)
    local rendered = {}
    local plain = {}
    local args = {...}

    for index, value in hostIpairs(args) do
        rendered[index] = repr(value)
        plain[index] = hostTostring(value)
    end

    local message = table.concat(plain, "	")
    emit("print(" .. table.concat(rendered, ", ") .. ")")

    local service = serviceCache.LogService
    if service and proxyState[service] and proxyState[service].history then
        proxyState[service].history[#proxyState[service].history + 1] = {
            message = message,
            messageType = makeEnumType("MessageType").MessageOutput,
            timestamp = tickEpochBase and (tickEpochBase + hostClock()) or os.time(),
        }
        local signal = instanceStates[service].values.MessageOut
        if signal then fireSignal(signal, message, makeEnumType("MessageType").MessageOutput) end
    end
end

local function sandboxWarn(...)
    local rendered = {}
    local plain = {}
    local args = {...}

    for index, value in hostIpairs(args) do
        rendered[index] = repr(value)
        plain[index] = hostTostring(value)
    end

    local message = table.concat(plain, "	")
    emit("warn(" .. table.concat(rendered, ", ") .. ")")

    local service = serviceCache.LogService
    if service and proxyState[service] and proxyState[service].history then
        proxyState[service].history[#proxyState[service].history + 1] = {
            message = message,
            messageType = makeEnumType("MessageType").MessageWarning,
            timestamp = os.time(),
        }
        local signal = instanceStates[service].values.MessageOut
        if signal then fireSignal(signal, message, makeEnumType("MessageType").MessageWarning) end
    end
end

local function sandboxRequire(module)
    if module == nil then
        hostError("invalid argument #1 to 'require' (ModuleScript expected)", 2)
    end

    if not instanceStates[module] or instanceStates[module].className ~= "ModuleScript" then
        hostError("Project Radium L3 require currently supports ModuleScript instances only", 2)
    end

    local state = instanceStates[module]
    proxyState[module] = proxyState[module] or {}

    if proxyState[module].required then
        return proxyState[module].result
    end
    if proxyState[module].requiring then
        hostError("Requested module experienced an error while loading", 2)
    end

    local source = state.values.Source
    if hostType(source) ~= "string" then
        hostError("ModuleScript.Source is unavailable", 2)
    end

    proxyState[module].requiring = true
    local fn, compileError = dynamicLoader(source, "=" .. (state.values.Name or "ModuleScript"))
    if not fn then
        proxyState[module].requiring = nil
        hostError(hostTostring(compileError), 2)
    end

    local results = table.pack(hostPcall(fn))
    proxyState[module].requiring = nil
    if not results[1] then
        hostError(hostTostring(results[2]), 2)
    end

    proxyState[module].result = results[2]
    proxyState[module].required = true
    return results[2]
end

local function safeRawget(value, key)
    if instanceStates[value] then
        hostError(
            "invalid argument #1 to 'rawget' (table expected, got Instance)",
            0
        )
    end

    return hostRawget(value, key)
end

local function safeRawset(value, key, newValue)
    if instanceStates[value] then
        hostError(
            "invalid argument #1 to 'rawset' (table expected, got Instance)",
            0
        )
    end

    return hostRawset(value, key, newValue)
end

local function safeGetfenv(target)
    if target == nil then return activeDynamicEnv or sandbox end
    if target == 0 then return activeDynamicEnv or sandbox end
    if hostType(target) == "number" then
        if target < 0 or target > 32 then hostError("invalid argument #1 to 'getfenv' (invalid level)",0) end
        return sandbox
    end
    if hostType(target) == "function" then
        local info=dynamicFunctionInfo[target]
        if info then return info.env end

        -- Runtime API functions live in the sandbox environment and are not
        -- user-mutable through setfenv.
        if sandbox.__isProtectedRuntimeFunction and sandbox.__isProtectedRuntimeFunction(target) then
            return sandbox
        end

        if hostType(hostGetfenv)=="function" then
            local ok,result=hostPcall(hostGetfenv,target)
            if ok and hostType(result)=="table" then return result end
        end
        return sandbox
    end
    hostError("invalid argument #1 to 'getfenv'",0)
end

sandbox.__isProtectedRuntimeFunction = function(target)
    if hostType(target) ~= "function" then
        return false
    end

    for _, constructor in hostPairs(dataConstructors) do
        if hostType(constructor) == "table" then
            for _, fn in hostPairs(constructor) do
                if fn == target then
                    return true
                end
            end
        elseif constructor == target then
            return true
        end
    end

    for _, fn in hostPairs(taskLib) do
        if fn == target then
            return true
        end
    end

    for _, fn in hostPairs(instanceMethodHandlers) do
        if fn == target then
            return true
        end
    end

    for _, fn in hostPairs(runValues) do
        if fn == target then
            return true
        end
    end

    if sandbox.Instance and sandbox.Instance.new == target then
        return true
    end

    return false
end

local function safeSetfenv(target,envValue)
    if hostType(envValue)~="table" then
        hostError("invalid argument #2 to 'setfenv' (table expected)",0)
    end

    if hostType(target)~="function" and hostType(target)~="number" then
        hostError("invalid argument #1 to 'setfenv'",0)
    end

    if hostType(target)=="function" and sandbox.__isProtectedRuntimeFunction(target) then
        hostError("cannot change environment of a Project Radium runtime API function",0)
    end

    if hostType(target)=="function" then
        local info=dynamicFunctionInfo[target]
        if info then
            info.env=envValue
            return target
        end
    end

    if hostType(target)=="function" and hostType(hostSetfenv)=="function" then
        local ok,result=hostPcall(hostSetfenv,target,envValue)
        if not ok then hostError(result,0) end
        return result
    end

    return target
end

dynamicLoader = function(source, chunkName)
    source=hostTostring(source or "")
    if #source > LIMITS.MAX_DYNAMIC_SOURCE then return nil,"dynamic source too large" end
    emit("loadstring("..repr(source)..")")

    local envRef=sandbox
    local nameRef=chunkName or "=ProjectRadiumL3"
    local okTest,testFn,testErr=hostPcall(luau.load,source,{environment=envRef,chunkName=nameRef})
    if not okTest then return nil,hostTostring(testFn) end
    if not testFn then return nil,hostTostring(testErr) end

    local wrapper
    wrapper=function(...)
        local info=dynamicFunctionInfo[wrapper]
        local activeEnv=info and info.env or envRef
        local okLoad,fnOrError,second=hostPcall(luau.load,source,{environment=activeEnv,chunkName=nameRef})
        if not okLoad then hostError(hostTostring(fnOrError),0) end
        if not fnOrError then hostError(hostTostring(second),0) end

        local previousEnv = activeDynamicEnv
        activeDynamicEnv = activeEnv
        local results = table.pack(hostPcall(fnOrError, ...))
        activeDynamicEnv = previousEnv

        if not results[1] then
            hostError(hostTostring(results[2]), 0)
        end

        return hostUnpack(results, 2, results.n)
    end
    dynamicFunctionInfo[wrapper]={env=envRef,source=source,chunkName=nameRef}
    return wrapper
end

sandbox.print = sandboxPrint
sandbox.warn = sandboxWarn
sandbox.error = error
sandbox.assert = assert
sandbox.pcall = pcall
sandbox.xpcall=xpcall
sandbox.ypcall=pcall
sandbox.select = select
sandbox.next = next
sandbox.pairs = pairs
sandbox.ipairs = ipairs
sandbox.tonumber = tonumber
sandbox.tostring = tostring
sandbox.rawequal = rawequal
sandbox.rawlen = rawlen
sandbox.rawget = safeRawget
sandbox.rawset = safeRawset
sandbox.type = sandboxType
sandbox.typeof = sandboxTypeof
sandbox.getmetatable = sandboxGetmetatable
sandbox.setmetatable = setmetatable
sandbox.getfenv = safeGetfenv
sandbox.setfenv = safeSetfenv
sandbox.unpack = table.unpack or unpack
sandbox._VERSION = "Luau"

sandbox.math = {}
for key, value in hostPairs(math) do
    sandbox.math[key] = value
end
sandbox.math.nan = 0 / 0

sandbox.string = {}
for key, value in hostPairs(string) do
    sandbox.string[key] = value
end

sandbox.table = {}
for key, value in hostPairs(table) do
    sandbox.table[key] = value
end

sandbox.utf8 = {}
for key, value in hostPairs(utf8) do
    sandbox.utf8[key] = value
end
if hostType(sandbox.utf8.graphemes) ~= "function" then
    sandbox.utf8.graphemes = function(value)
        local textValue = hostTostring(value or "")
        local starts = {}
        for byteIndex in utf8.codes(textValue) do
            starts[#starts + 1] = byteIndex
        end

        local index = 0
        return function()
            index += 1
            local first = starts[index]
            if not first then
                return nil
            end

            local last = (starts[index + 1] or (#textValue + 1)) - 1
            return first, last
        end
    end
end

sandbox.bit32 = {}
for key, value in hostPairs(bit32) do
    sandbox.bit32[key] = value
end

sandbox.coroutine = {}
for key, value in hostPairs(coroutine) do
    sandbox.coroutine[key] = value
end

sandbox.os = {}
for key, value in hostPairs(os) do
    sandbox.os[key] = value
end

sandbox.debug = {}
for key, value in hostPairs(debug) do
    sandbox.debug[key] = value
end
if hostType(sandbox.debug.getinfo) ~= "function" then
    sandbox.debug.getinfo = function(target)
        local result = {
            what = "Lua",
            source = "=[ProjectRadiumL3]",
            short_src = "[ProjectRadiumL3]",
            nups = 0,
        }

        if hostType(debug.info) == "function" and hostType(target) == "function" then
            local ok, source = hostPcall(debug.info, target, "s")
            if ok and source then
                result.source = source
                result.short_src = source
            end
        end

        return result
    end
end
sandbox.buffer = buffer

if hostType(table.freeze)=="function" then
    hostPcall(table.freeze,mathCompat)
    hostPcall(table.freeze,stringCompat)
    hostPcall(table.freeze,tableCompat)
    hostPcall(table.freeze,utf8Compat)
    hostPcall(table.freeze,debugCompat)
    hostPcall(table.freeze,coroutineCompat)
    hostPcall(table.freeze,bit32Compat)
    hostPcall(table.freeze,osCompat)
end

sandbox.task = taskLib
sandbox.wait = function(duration)
    local elapsed = taskLib.wait(duration)
    return elapsed, sandbox.tick and sandbox.tick() or (os.time() + virtualTime)
end
sandbox.spawn = function(callback, ...)
    return taskLib.spawn(callback, ...)
end
sandbox.delay = function(seconds, callback, ...)
    return taskLib.delay(seconds, callback, ...)
end
local tickEpochBase = os.time() - hostClock()
sandbox.tick = function()
    return tickEpochBase + hostClock()
end
sandbox.time = function()
    return virtualTime
end
sandbox.elapsedTime = function()
    return virtualTime
end

sandbox.game = game
sandbox.workspace = workspace
sandbox.Enum = Enum
sandbox.settings = function()
    return settingsObject
end
sandbox.Instance = {
    new = function(className, parent)
        local instance = createInstance(className, parent)
        emit(
            "local "
            .. objectNames[instance]
            .. " = Instance.new("
            .. repr(className)
            .. (parent and ", " .. repr(parent) or "")
            .. ")"
        )
        return instance
    end,
}

sandbox.Vector3 = dataConstructors.Vector3
sandbox.Vector2 = dataConstructors.Vector2
sandbox.vector = {
    create = function(x, y, z)
        return dataConstructors.Vector3.new(x, y, z)
    end,
}
sandbox.Vector3int16 = dataConstructors.Vector3int16
sandbox.CFrame = dataConstructors.CFrame
sandbox.Color3 = dataConstructors.Color3
sandbox.UDim = dataConstructors.UDim
sandbox.UDim2 = dataConstructors.UDim2
sandbox.Region3 = dataConstructors.Region3
sandbox.RaycastParams = dataConstructors.RaycastParams
sandbox.OverlapParams = dataConstructors.OverlapParams
sandbox.Random = dataConstructors.Random
sandbox.Vector2int16 = dataConstructors.Vector2int16
sandbox.BrickColor = dataConstructors.BrickColor
sandbox.TweenInfo = dataConstructors.TweenInfo
sandbox.NumberRange = dataConstructors.NumberRange
sandbox.NumberSequence = dataConstructors.NumberSequence
sandbox.NumberSequenceKeypoint = dataConstructors.NumberSequenceKeypoint
sandbox.ColorSequence = dataConstructors.ColorSequence
sandbox.ColorSequenceKeypoint = dataConstructors.ColorSequenceKeypoint
sandbox.Ray = dataConstructors.Ray
sandbox.Rect = dataConstructors.Rect
sandbox.Region3int16 = dataConstructors.Region3int16
sandbox.PhysicalProperties = dataConstructors.PhysicalProperties
sandbox.FloatCurveKey = dataConstructors.FloatCurveKey
sandbox.ValueCurveKey = dataConstructors.ValueCurveKey
sandbox.RotationCurveKey = dataConstructors.RotationCurveKey
sandbox.CatalogSearchParams = dataConstructors.CatalogSearchParams
sandbox.Axes = dataConstructors.Axes
sandbox.Faces = dataConstructors.Faces
sandbox.DockWidgetPluginGuiInfo = dataConstructors.DockWidgetPluginGuiInfo
sandbox.Path2DControlPoint = dataConstructors.Path2DControlPoint
sandbox.PathWaypoint = dataConstructors.PathWaypoint
sandbox.SecurityCapabilities = dataConstructors.SecurityCapabilities
sandbox.Font = dataConstructors.Font
sandbox.DateTime = dataConstructors.DateTime
sandbox.SharedTable = dataConstructors.SharedTable
sandbox.Regex = Regex
sandbox.User = User

sandbox.shared = {}

sandbox.SharedTable = dataConstructors.SharedTable

sandbox.gcinfo = function()
    local ok, value = hostPcall(collectgarbage, "count")
    if ok and hostType(value) == "number" and value > 0 then return value end
    return 1
end

sandbox.newproxy = newproxy

sandbox.identifyexecutor = function()
    return "Madium", "2.0.0"
end

sandbox.getexecutorname = function()
    return "Madium"
end

local function closureSource(fn)
    if hostType(fn) ~= "function" or hostType(debug.info) ~= "function" then return nil end
    local ok, source = hostPcall(debug.info, fn, "s")
    return ok and source or nil
end

sandbox.islclosure = function(fn)
    if hostType(fn) ~= "function" then return false end
    local source = closureSource(fn)
    return source ~= nil and source ~= "[C]"
end

sandbox.iscclosure = function(fn)
    if hostType(fn) ~= "function" then return false end
    return closureSource(fn) == "[C]"
end

sandbox.isexecutorclosure = function()
    return false
end

sandbox.getgenv = function()
    return sandbox
end

sandbox.getrenv = function()
    return sandbox
end

sandbox.require = sandboxRequire
sandbox.loadstring = dynamicLoader
sandbox.load = dynamicLoader

sandbox.loadfile = function(path)
    local full, rel = sandboxPath(path)

    if not fs.isFile(full) then
        hostError("cannot open " .. rel .. ": No such file", 2)
    end

    local okRead, source = hostPcall(fs.readFile, full)
    if not okRead then
        hostError(hostTostring(source), 2)
    end

    local fn, compileError = dynamicLoader(source, "@" .. rel)

    if not fn then
        return nil, compileError
    end

    return fn
end

sandbox.writefile = function(path, content)
    local full, rel = sandboxPath(path)
    local parent = full:match("^(.*)/[^/]+$")
    if parent and parent ~= "" and not fs.isDir(parent) then
        hostError("parent folder does not exist: " .. hostTostring(rel), 2)
    end
    local ok, err = hostPcall(fs.writeFile, full, hostTostring(content or ""))
    if not ok then
        hostError(hostTostring(err), 2)
    end
    emit("writefile(" .. repr(rel) .. ", " .. repr(content) .. ")")
end

sandbox.readfile = function(path)
    local full, rel = sandboxPath(path)
    local ok, result = hostPcall(fs.readFile, full)
    if not ok then
        hostError(hostTostring(result), 2)
    end
    emit("readfile(" .. repr(rel) .. ")")
    return result
end

sandbox.appendfile = function(path, content)
    local full, rel = sandboxPath(path)
    local existing = ""
    if fs.isFile(full) then
        local okRead, result = hostPcall(fs.readFile, full)
        if okRead then existing = result end
    end
    local ok, err = hostPcall(fs.writeFile, full, existing .. hostTostring(content or ""))
    if not ok then
        hostError(hostTostring(err), 2)
    end
    emit("appendfile(" .. repr(rel) .. ", " .. repr(content) .. ")")
end

sandbox.isfile = function(path)
    local full = sandboxPath(path)
    return fs.isFile(full)
end

sandbox.isfolder = function(path)
    local full = sandboxPath(path)
    return fs.isDir(full)
end

sandbox.makefolder = function(path)
    local full, rel = sandboxPath(path)
    if fs.isDir(full) then
        return nil
    end
    local ok, err = hostPcall(fs.writeDir, full)
    if not ok then
        hostError(hostTostring(err), 2)
    end
    emit("makefolder(" .. repr(rel) .. ")")
end

sandbox.listfiles = function(path)
    local result = listSandbox(path or "")
    emit("listfiles(" .. repr(path or "") .. ")")
    return result
end

sandbox.delfile = function(path)
    local full, rel = sandboxPath(path)
    if not fs.isFile(full) then
        return nil
    end
    local ok, err = hostPcall(fs.removeFile, full)
    if not ok then
        hostError(hostTostring(err), 2)
    end
    emit("delfile(" .. repr(rel) .. ")")
end

sandbox.delfolder = function(path)
    local full, rel = sandboxPath(path)
    if not fs.isDir(full) then
        return nil
    end
    local ok, err = hostPcall(fs.removeDir, full)
    if not ok then
        hostError(hostTostring(err), 2)
    end
    emit("delfolder(" .. repr(rel) .. ")")
end

sandbox.setclipboard = function(value)
    emit("setclipboard(" .. repr(value) .. ")")
end

-- identifyexecutor/getexecutorname intentionally remain exposed.
sandbox.request = nil
sandbox.http_request = nil
sandbox.syn = nil
sandbox.fs = nil
sandbox.process = nil
sandbox.net = nil

sandbox._G = table.clone(sandbox)
sandbox._G.__isProtectedRuntimeFunction = nil
sandbox._G._G = sandbox._G
sandbox._ENV = sandbox

hostSetmetatable(sandbox, {
    __index = function(_, key)
        local service = serviceCache[key]

        if service then
            return service
        end

        if serviceNames[key] then
            return makeService(key)
        end

        local constructor = dataConstructors[key]
        if constructor then
            return constructor
        end

        -- Unknown globals are nil instead of truthy synthetic proxies.
        emit("-- missing global: " .. hostTostring(key))
        return nil
    end,

    __newindex = function(target, key, value)
        hostRawset(target, key, value)
        emit(hostTostring(key) .. " = " .. repr(value))
    end,
})

-- Populate common services eagerly.
for _, serviceName in hostIpairs({
    "RunService",
    "HttpService",
    "Lighting",
    "SoundService",
    "TweenService",
    "MarketplaceService",
    "PhysicsService",
    "ContentProvider",
    "AnimationClipProvider",
    "ContextActionService",
    "UserInputService",
    "PathfindingService",
    "Teams",
    "Stats",
    "LogService",
}) do
    makeService(serviceName)
end

local function sanitizeRuntimeError(value)
    local text = hostTostring(value)
    text = text:gsub("C:\\Users\\[^\\]+", "C:\\ProjectRadium")
    text = text:gsub("C:\\\\Users\\\\[^\\\\]+", "C:\\\\ProjectRadium")
    text = text:gsub("C:/Users/[^/]+", "C:/ProjectRadium")
    text = text:gsub("temp\\input_%d+_%d+%.lua", "ProjectRadium\\script.lua")
    text = text:gsub("temp/input_%d+_%d+%.lua", "ProjectRadium/script.lua")
    return text
end

do
    local function ProjectRadiumRunTarget()
        local source = safeRead(CONFIG.input)

        if not source then
            hostError("Project Radium L3 could not read input: " .. hostTostring(CONFIG.input), 0)
        end

        -- Output header is initialized before runtime logging begins.

        local fn, compileError = luau.load(source, {
            environment = sandbox,
            chunkName = "=ProjectRadiumL3",
        })

        if not fn then
            output[#output + 1] = "-- compile error: " .. sanitizeRuntimeError(compileError)
        else
            runtimeStart = hostClock()
            local ok, runtimeError = hostPcall(fn)

            if not ok then
                output[#output + 1] = ""
                output[#output + 1] = "-- runtime: " .. sanitizeRuntimeError(runtimeError)
                hostWarn("[Project Radium L3 runtime] " .. sanitizeRuntimeError(runtimeError))
            end
        end

        safeWrite(CONFIG.output, table.concat(output, "\n"))

        hostPrint("")
        hostPrint("Project Radium L3 complete")
        hostPrint("input: " .. CONFIG.input)
        hostPrint("output: " .. CONFIG.output)
        hostPrint("api: " .. apiSource)
        hostPrint(
            string.format(
                "profile: %s (%s) userId=%d placeId=%d",
                CONFIG.displayName,
                CONFIG.username,
                CONFIG.userId,
                CONFIG.placeId
            )
        )
    end

    ProjectRadiumRunTarget()
end
