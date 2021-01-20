local functions = {}

local Results = {}

function getcallingscript() return false end -- Disabled because of detection
getrawmetatable = getrawmetatable or getmetatable
setreadonly = setreadonly or function() end
typeof = typeof or type

local function Push(str) -- Push string to table (10000000x faster than normal concat)
  Results[#Results+1] = str
end

local ResultsQuick = {}

local function PushOnScope(str) -- Push string to table but on a diff table 
  ResultsQuick[#ResultsQuick+1] = str
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

local ControlCharEscapes = {} -- \a => nil, \0 => \000, 31 => \031 -- from inspect.lua
for i=0, 31 do
  local ch = string.char(i)
  if not EscapedChars[ch] then
    EscapedChars[ch] = "\\"..i
    ControlCharEscapes[ch]  = string.format("\\%03d", i)
  end
end


local function FixStrings(str) -- String fixer

    if #str > 10000 then
        return "String was too big ("..#str.." chars)"
    end

    return (str:gsub("\\", "\\\\")
             :gsub("(%c)%f[0-9]", ControlCharEscapes)
             :gsub("%c", EscapedChars)
             :gsub("\"", "\\\""))
end



local ValidClasses = {}

if game then
  for i,v in pairs(game:GetChildren()) do
    ValidClasses[v.ClassName] = true
  end
end

function getPath(Instance) 
    -- Better implementation of :GetFullName
    -- We are not going to change from default concat here because a game would need to have like 10k parents on a object for it to lag
    if not Instance or typeof(Instance) ~= "Instance" then return "nil instance" end
    if Instance == game then
        return "game" 
    end
    if Instance.Parent == nil then
        return 'getnilinstance("'..FixStrings(Instance.Name)..'")' --[[Instance is on nil]]
    end
    local obj = Instance
    local Path = ""
    repeat obj = obj.Parent 
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
  end

  if Type == "string" then
    Push('"')
    Push(FixStrings(t))
    return Push('"')
  end

  if Type == "number" then
     return Push(t)
  end

  if Type == "table" then
    LoadedTables[t] = true
    return
  end
  
  if Type == "userdata" then
        return Push(FixUserdata(t))
  end
  if typeof(v) == "userdata" then -- only in luau
      Push("newproxy(true)") 
  end
  
  if Type == "function" then
        return Push("'"..tostring(t).."'")
  end
  
  if Type == "boolean" then
        return Push(tostring(t))
  end

  error(Type.." not detected")
end

function FixUserdata(u) -- Skidded from simplespy source, credits to him (made performance fixes btw) (roblox stuff)
    if typeof(u) == "TweenInfo" then
        -- TweenInfo
        return "TweenInfo.new(" ..tostring(u.Time) .. ", Enum.EasingStyle." .. tostring(u.EasingStyle) .. ", Enum.EasingDirection." .. tostring(u.EasingDirection) .. ", " .. tostring(u.RepeatCount) .. ", " .. tostring(u.Reverses) .. ", " .. tostring(u.DelayTime) .. ")"
    elseif typeof(u) == "Ray" then
        -- Ray
        return ("Ray.new(" .. FixUserdata(u.Origin) .. ", " .. FixUserdata(u.Direction) .. ")")
    elseif typeof(u) == "NumberSequence" then
        -- NumberSequence
        local ret = "NumberSequence.new("
        for i, v in pairs(u.KeyPoints) do
            ret = ret .. tostring(v)
            if i < #u.Keypoints then
                ret = ret .. ", "
            end
        end
        return (ret .. ")")
    elseif typeof(u) == "DockWidgetPluginGuiInfo" then
        -- DockWidgetPluginGuiInfo
        return ("DockWidgetPluginGuiInfo.new(Enum.InitialDockState" .. tostring(u) .. ")")
    elseif typeof(u) == "ColorSequence" then
        -- ColorSequence
        local ret = "ColorSequence.new("
        for i, v in pairs(u.KeyPoints) do
            ret = ret .. "Color3.new(" .. tostring(v) .. ")"
            if i < #u.Keypoints then
                ret = ret .. ", "
            end
        end
        return (ret .. ")")
    elseif typeof(u) == "BrickColor" then
        -- BrickColor
        return ("BrickColor.new(" .. tostring(u.Number) .. ")")
    elseif typeof(u) == "NumberRange" then
        -- NumberRange
        return ("NumberRange.new(" .. tostring(u.Min) .. ", " .. tostring(u.Max) .. ")")
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
        return "Faces.new("..table.concat(Res, ", ")..")" 
    elseif typeof(u) == "EnumItem" then
        return (tostring(u))
    elseif typeof(u) == "Enums" then
        return ("Enum")
    elseif typeof(u) == "Enum" then
        return ("Enum." .. tostring(u))
    elseif typeof(u) == "RBXScriptSignal" then
        return ("nil --[[RBXScriptSignal]]")
    elseif typeof(u) == "Vector3" then
        return (string.format("Vector3.new(%s, %s, %s)", tostring(u.X), tostring(u.Y), tostring(u.Z)))
    elseif typeof(u) == "CFrame" then
        return (string.format("CFrame.new(%s, %s)", tostring(u.Position), tostring(u.LookVector)))
    elseif typeof(u) == "DockWidgetPluginGuiInfo" then
        return (string.format("DockWidgetPluginGuiInfo(%s, %s, %s, %s, %s, %s, %s)", "Enum.InitialDockState.Right", tostring(u.InitialEnabled), tostring(u.InitialEnabledShouldOverrideRestore), tostring(u.FloatingXSize), tostring(u.FloatingYSize), tostring(u.MinWidth), tostring(u.MinHeight)))
    elseif typeof(u) == "RBXScriptConnection" then
        return ("nil --[[RBXScriptConnection " .. tostring(u) .. "]]")
    elseif typeof(u) == "RaycastResult" then
        return ("nil --[[RaycastResult " .. tostring(u) .. "]]")
    elseif typeof(u) == "PathWaypoint" then
        return (string.format("PathWaypoint.new(%s, %s)", tostring(u.Position), tostring(u.Action)))
    else
        return '"'..tostring(u)..'"'
    end
end

local METAT = {}

function Get(...) -- Removes __tostring metatable and saves it to a table
  for i, v in pairs({...}) do
          local MT = getrawmetatable(v)
          if MT then 
            setreadonly(MT, false)
            METAT[v] = getrawmetatable(v).__tostring
            getrawmetatable(v).__tostring = nil
      end
  end
end

function Bring(...) -- Sets the old __tostring metatable to the object
  for i, v in pairs({...}) do
      local MT = METAT[v]
      if MT then
          getrawmetatable(v).__tostring = MT
      end
  end
end

function GetMeaning(t) -- Gets table size till next hole
  local index = 0
  for i, v in pairs(t) do
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

    Get(i, v) -- Removes metatables
    
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
    
    Bring(i, v) -- Pushes metatables back to the object

    

  end
  Push("\n}")

  return table.concat(Results)
end

functions.parse = function(t)
  assert(type(t) == "string", "argument must be a string")
  return loadstring("return "..t)()
end

return functions
