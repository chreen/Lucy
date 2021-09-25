-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

-- lucy.lua - Lua C emulator
-- Parses Lua C "scripts" into an intermediate
-- representation for execution

local opcodes = {}

local opC = 0
local function addOpcode(name, ...)
  if (name == "pushbool") then -- alias for pushboolean
    opC -= 1
  end

  opcodes[name] = {
    op = opC,     -- opcode index
    args = {...}  -- argument types for parsing
  }
  opC += 1
end

do -- add opcode definitions
  addOpcode("getglobal", "string")
  addOpcode("getfield", "number", "string")
  addOpcode("setfield", "number", "string")
  addOpcode("pushvalue", "number")
  addOpcode("pcall", "number", "number", "number")
  addOpcode("call", "number", "number")
  addOpcode("pushnumber", "number")
  addOpcode("pushboolean", "bool")
  addOpcode("pushbool", "bool")
  addOpcode("pushnil")
  addOpcode("pushstring", "string")
  addOpcode("settop", "number")
  addOpcode("remove", "number")
  addOpcode("pop", "number")
  addOpcode("emptystack")
end

local function errorHandler(line, msg, ...)
  error(string.format("line %d: " .. msg, line, ...), 0)
end

local function stringAfter(parts, after)
  local buff = {}
  table.move(parts, after, #parts, 1, buff) -- move words after an index to buffer

  return table.concat(buff, " ") -- concatenate buffer with spaces
end

--- Parses a Lua C script into an array of instructions
---@param scr string Lua C script to parse
---@return table code Array of parsed instructions
local function parse(scr)
  if (string.sub(scr, -1) ~= "\n") then -- pad with newline
    scr ..= "\n"
  end

  local code = {} -- instruction table
  local lc = 0    -- line counter, used in error messages

  for line in string.gmatch(scr, "(.-)\n") do
    lc += 1 -- increment line counter

    if (not string.match(line, "%S+")) then -- skip empty lines
      continue
    end

    local op          -- opcode name
    local blocks = {} -- words in this line

    for block in string.gmatch(line, "%S+") do
      if (not op) then -- first word is opcode
        op = block
        continue -- do not add to list
      end

      table.insert(blocks, block)
    end

    if (not opcodes[op]) then -- make sure opcode is valid
      errorHandler(lc, "invalid opcode `%s`", op)
    end

    local opcode = opcodes[op]
    local inst = {
      op = opcode.op,
      args = {}
    }

    for idx, type in ipairs(opcode.args) do -- check argument types
      local block = blocks[idx]

      if (type == "string") then
        inst.args[idx] = stringAfter(blocks, idx)
      elseif (type == "number") then
        local num = assert(tonumber(block), string.format("line %d: invalid number `%s`", lc, block or "<eol>"))
        inst.args[idx] = num
      elseif (type == "bool") then
        local lower = string.lower(block)

        if (lower == "true") then
          inst.args[idx] = true
        elseif (lower == "false") then
          inst.args[idx] = false
        else
          errorHandler(lc, "invalid boolean `%s`", block)
        end
      end
    end

    table.insert(code, inst)
  end

  return code
end

local function getIdx(idx, size) -- handles negative indices
  return (idx < 0) and size + 1 + idx or idx
end

local stack = {}
stack.__index = stack

do
  function stack.new() -- new stack
    local self = setmetatable({}, stack)
    self.stack = {}
    self.size = -1
    return self
  end

  function stack:push(val) -- push `val` to top
    self.size += 1
    self.stack[self.size] = val
  end

  function stack:pop(idx) -- pop value at `idx`
    idx = getIdx(idx, self.size)
    local val = self.stack[idx]
    self.stack[idx] = nil
    table.move(self.stack, idx + 1, self.size, idx, self.stack)
    self.stack[self.size] = nil
    self.size -= 1
    return val
  end

  function stack:get(idx) -- get value at `idx`
    return self.stack[getIdx(idx, self.size)]
  end

  function stack:clear() -- clear stack
    self.stack = {}
    self.size = 0
  end

  function stack:size() -- size of stack
    return self.size
  end

  function stack:setsize(size) -- set stack size
    self.size = getIdx(size, self.size)
  end
end

local opFuncs = {
  [0] = function(inst, stk, env) -- getglobal
    stk:push(env[inst.args[1]])
  end,
  [1] = function(inst, stk) -- getfield
    stk:push(stk:get(inst.args[1])[inst.args[2]])
  end,
  [2] = function(inst, stk) -- setfield
    stk:get(inst.args[1])[inst.args[2]] = stk:pop(-1)
  end,
  [3] = function(inst, stk) -- pushvalue
    stk:push(stk:get(inst.args[1]))
  end,
  [4] = function(inst, stk) -- pcall
    local nargs = inst.args[1]
    local nresults = inst.args[2]
    local errfunc = inst.args[3]

    local func = stk:get(-nargs - 1)
    local args = table.create(nargs)

    for i = nargs, 1, -1 do
      table.insert(args, stk:pop(-i))
    end

    local res = table.pack(pcall(func, table.unpack(args)))

    if (res[1]) then
      for i = 1, nresults do
        stk:push(res[i + 1])
      end
    else
      local msg = res[2]
      if (errfunc == 0) then
        stk:push(msg)
      else
        stk:push(stk:get(errfunc)(msg))
      end
    end
  end,
  [5] = function(inst, stk) -- call
    local nargs = inst.args[1]
    local nresults = inst.args[2]

    local func = stk:get(-nargs - 1)
    local args = table.create(nargs)

    for i = nargs, 1, -1 do
      table.insert(args, stk:pop(-i))
    end

    local res = table.pack(func(table.unpack(args)))

    for i = 1, nresults do
      stk:push(res[i])
    end
  end,
  [6] = function(inst, stk) -- pushnumber
    stk:push(inst.args[1])
  end,
  [7] = function(inst, stk) -- pushboolean
    stk:push(inst.args[1])
  end,
  [8] = function(_, stk) -- pushnil
    stk:push(nil)
  end,
  [9] = function(inst, stk) -- pushstring
    stk:push(inst.args[1])
  end,
  [10] = function(inst, stk) -- settop
    local top = inst.args[1]

    if (top == 0) then
      stk:clear()
    else
      stk:setsize(top)
    end
  end,
  [11] = function(inst, stk) -- remove
    stk:pop(inst.args[1])
  end,
  [12] = function(inst, stk) -- pop
    for _ = 1, inst.args[1] do
      stk:pop(-1)
    end
  end,
  [13] = function() -- emptystack
    stack:clear()
  end,
}

--- Wraps an array of instructions into a function
--- to execute it
---@param code table List of instructions
---@param env table Environment table
---@return function execute Function to execute code
local function wrap(code, env)
  env = env or {}
  return function(...)
    local stk = stack.new()

    -- push args to the stack
    for _, arg in pairs({...}) do
      stk:push(arg)
    end

    -- iterate over instructions and execute
    for line, inst in ipairs(code) do
      local op = inst.op

      local func = opFuncs[op]

      if (not func) then
        errorHandler(line, "no opcode handler found")
      end

      local res = table.pack(pcall(func, inst, stk, env))

      if (not res[1]) then
        errorHandler(line, "execution error: %s", res[2])
      end
    end
  end
end

return {
  wrap = wrap,
  parse = parse
}