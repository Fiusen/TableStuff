local functions = {}

local Results = {}

local getrawmetatable = getrawmetatable or getmetatable
local setreadonly = setreadonly or function() end
local typeof = typeof or type
local tableconcat = table.concat
local stringf = string.format
local pairs = pairs
local gsub = string.gsub
local tostring = tostring
local type = type
local rawget = rawget
local rawset = rawset
local stringchar = string.char

local tostr = function(str) -- safe tostring
    local mt = getrawmetatable(str)
    if mt then 
        setreadonly(mt, false)
        local Copy = rawget(mt, "__tostring")
        rawset(mt, "__tostring", nil)
        local r = tostring(str)
        rawset(mt, "__tostring", Copy)
        setreadonly(mt, true)
        return r
    else
        return tostring(str)
    end
end

local function Push(str) -- Push string to table (10000000x faster than normal concat)
  Results[#Results+1] = str
end

local EscapedChars = { -- List of common escaped chars
    ['\n'] = '\\n',
    ['\a'] = '\\a',
    ['\f'] = '\\f',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
    ['\0'] = '\\0',
    ["\\"] = '\\\\',
    ["/"] = '/',
    ["'"] = "\\'",
}

local ControlCharEscapes = {} -- \a => nil, \0 => \000, 31 => \031 
-- from https://github.com/kikito/inspect.lua
for i=0, 31 do
  local ch = stringchar(i)
  if not EscapedChars[ch] then
    EscapedChars[ch] = "\\"..i
    ControlCharEscapes[ch]  = stringf("\\%03d", i)
  end
end


local function FixStrings(str) -- String fixer

    if #str > 10000 then
        return "String was too big ("..#str.." chars)"
    end

    return gsub(gsub(gsub(gsub(str, "\\", "\\\\"), "(%c)%f[0-9]", ControlCharEscapes), "%c", EscapedChars), "\"", "\\\"")
end



local ValidClasses = {}

if game then -- roblox stuff
  for i,v in pairs(game:GetChildren()) do
    ValidClasses[v.ClassName] = true
  end
end

local function getPath(Instance) -- roblox stuff
    -- Better implementation of :GetFullName
    -- We are not going to change from default concat here because a game would need to have like 10k parents on a object for it to lag
    if not Instance or typeof(Instance) ~= "Instance" then return "nil instance" end
    if Instance == game then
        return "game" 
    end
    if Instance.Parent == nil then
        return "getnilinstance('"..FixStrings(Instance.Name).."')" --Instance is on nil
    end
    local obj = Instance
    local Path = ""
    repeat 
        obj = obj.Parent 
        if obj then
            if not ValidClasses[obj.ClassName] then
                if obj ~= game and obj then
                    Path = '["'..obj.Name..'"]'..Path 
                end
                elseif obj then
                    Path = 'game:GetService("'..obj.ClassName..'")'..Path                
                end
        else
            Path = "game"..Path
        end
    until not obj or obj.Parent == game
    return FixStrings(Path..'["'..Instance.Name..'"]') -- Path could have weird symbols
end

local LoadedTables = {}
 
local function analise(t) -- Type analiser for table.stringify

  if LoadedTables[t] then Push("{} --[[Already defined table]]") return end
  
  local Type = type(t)

  if typeof(t) == "Instance" then
      return Push(getPath(t))
  elseif Type == "string" then
    return Push('"'..FixStrings(t)..'"')
  elseif Type == "number" then
     return Push(t)
  elseif Type == "table" then
    LoadedTables[t] = true
    return functions.stringify(t, true)
  elseif Type == "userdata" then
        return Push(FixUserdata(t))
  elseif typeof(v) == "userdata" then -- only for luau
      Push("newproxy(true)") 
  elseif Type == "function" then
        return Push('"'..tostr(t)..'" --[[Actual function, tostringed to avoid errors]]')
  elseif Type == "boolean" then
        return Push(tostr(t))
  elseif Type == "nil" then
        return Push("nil")
  end

  error(Type.." not detected")
end

function FixUserdata(u) -- Skidded from simplespy source, credits to him (made performance fixes btw) (roblox stuff)
    -- (https://github.com/exxtremestuffs/SimpleSpySource/blob/master/SimpleSpy.lua)
    if typeof(u) == "TweenInfo" then
        -- TweenInfo
        return "TweenInfo.new(" ..tostr(u.Time) .. ", Enum.EasingStyle." .. tostr(u.EasingStyle) .. ", Enum.EasingDirection." .. tostr(u.EasingDirection) .. ", " .. tostr(u.RepeatCount) .. ", " .. tostr(u.Reverses) .. ", " .. tostr(u.DelayTime) .. ")"
    elseif typeof(u) == "Ray" then
        -- Ray
        return ("Ray.new(" .. FixUserdata(u.Origin) .. ", " .. FixUserdata(u.Direction) .. ")")
    elseif typeof(u) == "NumberSequence" then
        -- NumberSequence
        local ret = "NumberSequence.new("
        for i, v in pairs(u.KeyPoints) do
            ret = ret .. tostr(v)
            if i < #u.Keypoints then
                ret = ret .. ", "
            end
        end
        return (ret .. ")")
    elseif typeof(u) == "DockWidgetPluginGuiInfo" then
        -- DockWidgetPluginGuiInfo
        return ("DockWidgetPluginGuiInfo.new(Enum.InitialDockState" .. tostr(u) .. ")")
    elseif typeof(u) == "ColorSequence" then
        -- ColorSequence
        local ret = "ColorSequence.new("
        for i, v in pairs(u.KeyPoints) do
            ret = ret .. "Color3.new(" .. tostr(v) .. ")"
            if i < #u.Keypoints then
                ret = ret .. ", "
            end
        end
        return (ret .. ")")
    elseif typeof(u) == "BrickColor" then
        -- BrickColor
        return ("BrickColor.new(" .. tostr(u.Number) .. ")")
    elseif typeof(u) == "NumberRange" then
        -- NumberRange
        return ("NumberRange.new(" .. tostr(u.Min) .. ", " .. tostr(u.Max) .. ")")
    elseif typeof(u) == "Region3" then
        -- Region3
        local center = u.CFrame.Position
        local size = u.CFrame.Size
        local vector1 = center - size / 2
        local vector2 = center + size / 2
        return ("Region3.new(" .. FixUserdata(vector1) .. ", " .. FixUserdata(vector2) .. ")")
    elseif typeof(u) == "Faces" then
        -- Faces
        local ValidFaces = {
            "Top",
            "Bottom",
            "Back",
            "Left",
            "Right",
            "Back",
            "Front"
        }
        local Res = {}
        for i, v in pairs(ValidFaces) do
            if u[v] then
                 Res[#Res+1] = "Enum.NormalId."..v
            end
        end
        return "Faces.new("..tableconcat(Res, ", ")..")" 
    elseif typeof(u) == "EnumItem" then
        return (tostr(u))
    elseif typeof(u) == "Enums" then
        return ("Enum")
    elseif typeof(u) == "Enum" then
        return ("Enum." .. tostr(u))
    elseif typeof(u) == "RBXScriptSignal" then
        return ("nil --[[RBXScriptSignal]]")
    elseif typeof(u) == "Vector3" then
        return (stringf("Vector3.new(%s, %s, %s)", tostr(u.X), tostr(u.Y), tostr(u.Z)))
    elseif typeof(u) == "CFrame" then
        return (stringf("CFrame.new(%s, %s)", tostr(u.Position), tostr(u.LookVector)))
    elseif typeof(u) == "DockWidgetPluginGuiInfo" then
        return (stringf("DockWidgetPluginGuiInfo(%s, %s, %s, %s, %s, %s, %s)", "Enum.InitialDockState.Right", tostr(u.InitialEnabled), tostr(u.InitialEnabledShouldOverrideRestore), tostr(u.FloatingXSize), tostr(u.FloatingYSize), tostr(u.MinWidth), tostr(u.MinHeight)))
    elseif typeof(u) == "RBXScriptConnection" then
        return ("nil --[[RBXScriptConnection " .. tostr(u) .. "]]")
    elseif typeof(u) == "RaycastResult" then
        return ("nil --[[RaycastResult " .. tostr(u) .. "]]")
    elseif typeof(u) == "PathWaypoint" then
        return (stringf("PathWaypoint.new(%s, %s)", tostr(u.Position), tostr(u.Action)))
    else
        return '"'..tostr(u)..'" --[[Actual userdata, tostringed to avoid errors]]'
    end
end


local function GetMeaning(t) -- Gets table size till next hole
  -- Lua isnt good enough so even if you parse the stringified table
  -- and outputed its size it would throw different results (from non-str to stringified)
  -- bc tables with holes are undefined behavior
  -- this will work fine if the index number (w/ hole) is defined inside the table and not outside it
  local index = 0
  for i, v in pairs(t) do -- I need pairs here
    if typeof(i) == "number" and i-1 == index then
      index = index + 1
    else
      return index
    end
  end
  return index
end

functions.stringify = function(t, bool) -- stringifies the given table
  assert(type(t) == "table", "argument must be a table")

  if not bool then
    Results = {}
    LoadedTables = {}
  end

  local TableList = GetMeaning(t)

  Push("{")
  for i, v in pairs(t) do  
    if typeof(i) == "number" and i <= TableList then
      -- This is so it wont format tables like:
      -- [1] = ""
      -- [2] = ""
      -- But will actually do it when a hole is found on the table
      Push("\n")
      analise(v)
      -- formats to: v;
    else
      Push("\n[")
      analise(i)
      Push("] = ")
      analise(v)
      -- formats to: [i] = v;
    end
    Push(";") 
  end
  Push("\n}")

  return tableconcat(Results)
end

functions.parse = function(t)
  assert(type(t) == "string", "argument must be a string")
  return loadstring("return "..t)()
end

local Indexed;

local function GrabIndex(t, idx)
  for i = 1, #t do
      local v = t[i]
      if i == idx then
          return i
      end
      if typeof(v) == "table" and not LoadedTables[v] then
        LoadedTables[v] = true
        Indexed[#Indexed+1] = i
        GrabIndex(v, idx)
        return Indexed
      end
  end
end

functions.rfind = function(t, idx) 
    -- Recursive finding on a table, returns a table if there are multiple indexes
    LoadedTables = {}
    Indexed = {}
    return GrabIndex(t, idx)
end

return functions
