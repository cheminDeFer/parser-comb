function readonlytable(table)
   return setmetatable({}, {
     __index = table,
     __newindex = function(table, key, value)
                    error('Attempt to modify read-only table')
                  end,
     __metatable = false,
     __len = function(o)
        local i = 1
        while o[i] ~= nil do
            i = i+1
        end
        return i-1
     end
   });
end
local errorupdate = function (parserstate, errmsg)
  assert(parserstate,'something fishy in errorupdate')
  local newstate = {}

  newstate.iserror = true
  newstate.errormsg = errmsg
  newstate.result = nil
  newstate.index = parserstate.index

  return readonlytable(newstate)
end

local update = function (parserstate, index, result)
    assert(index,'index should not be nil in update')
    assert(index > 0, index)
    assert(result,'result should not be nil in update')
    local newstate = {}
    newstate[1] = parserstate[1]
    newstate.index = index
    newstate.result = result
    newstate.iserror = false
    return readonlytable(newstate)
end
local Parser = {}
Parser.__index = Parser
setmetatable(Parser, {
   __call = function (cls, ...)
      return cls.new(...)
   end,
})
function Parser.new(f)
  local self = setmetatable({}, Parser)
  self.f =  f
  return self
end
function Parser:run(targetstring)
  assert(targetstring, 'run got nil targetstring')
  local initialstate =  readonlytable{
  targetstring,
  index = 1,
  result = {},
  error = false,
  }
  return self.f(initialstate)
end

function Parser:map(fn)
  return self.new(function (parserstate)
    local nextstate = self.f(parserstate)
    if nextstate.iserror  then return nextstate  end
    return update(nextstate,nextstate.index , fn(nextstate.result))
  end)
end

function Parser:errormap(fn)
  return self.new(function (parserstate)
    local nextstate = self.f(parserstate)
    if not(nextstate.iserror) then
        return nextstate
    end
    return errorupdate(nextstate, fn(nextstate.errormsg, nextstate.index))
  end)
end

function Parser:chain(fn)
  return self.new(function (parserstate)
    local nextstate = self.f(parserstate)
    if(nextstate.iserror)  then return nextstate  end
    local parser = fn(nextstate.result)
    return parser.f(nextstate)
  end)
end

local string_parser = function (s)
  return Parser(function (parserstate)
    local targetstring = parserstate[1]
    local index = parserstate.index
    local iserror = parserstate.iserror
    if iserror then return parserstate end
    assert(targetstring, 'targetstring should not be nil in string parser')
    local sliced =targetstring:sub(index)
    if #sliced == 0 then return errorupdate(parserstate, string.format("unexpected eof at %d", index)) end

    if sliced:sub(1,s:len()) == s then
      return update(parserstate, index + #s, s)
    end
    local emsg =string.format('cannot match "%s" got "%s" at %d', s ,targetstring:sub(index) , index)
    return errorupdate ( parserstate, emsg )
  end
  )
end

local letters =
  Parser(function (parserstate)
    local targetstring = parserstate[1]
    local index = parserstate.index
    local iserror = parserstate.iserror
    if iserror then return parserstate end
    assert(targetstring, 'targetstring should not be nil in numbers parser')
    local sliced =targetstring:sub(index)
    if #sliced == 0 then return errorupdate(parserstate, string.format("letters: unexpected eof at %d", index)) end
    local match =sliced:match('^%a+')
    if match then
      return update(parserstate, index + #match, match)
    end
    local emsg =string.format('cannot match "%s" got "%s" at %d', 'any letter' ,targetstring:sub(index) , index)
    return errorupdate ( parserstate, emsg )
  end
  )

local numbers = Parser(function (parserstate)
    local targetstring = parserstate[1]
    local index = parserstate.index
    local iserror = parserstate.iserror
    assert(targetstring, 'targetstring should not be nil in numbers parser')
    if iserror then
        return parserstate
    end
    local sliced =targetstring:sub(index)
    if #sliced == 0 then return errorupdate(parserstate, string.format("numbers: unexpected eof at %d", index)) end
    local match =sliced:match('^%d+')
    if match then
      return update(parserstate, index + #match, match)
    end
    local emsg =string.format('cannot match "%s" got "%s" at %d', 'any numbers' ,targetstring:sub(index) , index)
    return errorupdate ( parserstate, emsg )
  end
  )

local sequenceof = function (parsers)
  assert(#parsers >= 1, 'sequenceof should have at least one parser')
  return Parser(function (parserstate)
    if parserstate.iserror then return parserstate end
    local results = {}
    local nextstate = parserstate
    for i, p in ipairs(parsers) do
      assert(p~=nil, string.format('xth parser in sequence of is nil x = %d',i))
      nextstate = p.f(nextstate)
      table.insert(results,nextstate.result)
    end
    return {
      nextstate[1],
      index = nextstate.index,
      iserror = nextstate.iserror,
      errormsg = nextstate.errormsg,
      result = results,
    }
  end
  )
end

local many = function (parser)
  return Parser(function (parserstate)
    if parserstate.iserror then return parserstate end
    local results = {}
    local nextstate = parserstate
    local done = false
    local it = 0
    while not(done) do
      local teststate = parser.f(nextstate)
      if not(teststate.iserror) then
          table.insert(results,teststate.result)
          nextstate = teststate
      else
          done = true
      end
    end
    return update(nextstate, nextstate.index,   results)
  end
  )
end

local many1 = function (parser)
  return Parser(function (parserstate)
    if parserstate.iserror then return parserstate end
    local results = {}
    local nextstate = parserstate
    local done = false
    while not(done) do
      local teststate = parser.f(nextstate)
      if not(teststate.iserror) then
          table.insert(results,teststate.result)
          nextstate = teststate
      else
          done = true
      end
    end
    if #results == 0 then
        local emsg = string.format('many1: Unable to match any input using parser @ index= %d',nextstate.index)
        return errorupdate(nextstate,emsg)
    end
    return update( nextstate,  nextstate.index, results)
  end
  )
end

local choice = function (parsers)
  return Parser(function (parserstate)

    assert(parserstate, 'something ifshy in choice')
    if parserstate.iserror then
        return parserstate
    end
    for i, p in ipairs(parsers) do
      assert(p, 'parser nil in choice')
      local nextstate = p.f(parserstate)
      if not(nextstate.iserror) then
          return nextstate
      end
    end
    local emsg =string.format(
        'choice: Unable to match with any parser at %d',
        parserstate.index
    )
    return errorupdate(parserstate,emsg)
  end
  )
end

local gettableresult
gettableresult = function(t)
  local res = "{"
  for k,v in pairs(t) do
    if type(v) == "table" then
        res = res .. k .. ' : ' .. gettableresult(v) .. ', '
    else
        res = res .. k .. ' : ' .. tostring(v) .. ', '
    end
  end
  res = res ..  '}'
  return res
end

local print_parser_state = function (state)

  local f;
  if state.iserror then
    f = string.format('{errormsg: %s}',state.errormsg)
  else
    local r
    if type(state.result) == "table" then
       r = gettableresult(state.result)
    else
       r = state.result
    end
    f = string.format('{targetstring "%s" result:%s, index: %d } ',state[1] , r , state.index)
  end
  print(f)
end

local between = function (left, right)
    return function (content)
        local s = sequenceof ( { left, content , right} )
        return s:map(function (x) return x[2] end )
    end
end

local p =  many1(choice({ letters, numbers}))
p = p:map(function (x)
  local res = ""
  for i,v in ipairs(x) do res = res .. v .. ','  end
  return '<' .. res:sub(1,#res-1) .. '>'
  end
)

local sepby = function (seperatorparser)
  return function(valueparser)
    return Parser(function (parserstate)
        if parserstate.iserror then return parserstate end
        local results = {}
        local nextstate = parserstate
        while true do
          local thethingwewant = valueparser.f(nextstate)
          if thethingwewant.iserror then
              break
          end
          table.insert(results,thethingwewant.result)
          nextstate = thethingwewant
          local sepstate = seperatorparser.f(nextstate)
          if sepstate.iserror then
              break
          end
          nextstate = sepstate

        end
        return update(nextstate,nextstate.index, results)
    end)
  end
end

local sepby1 = function (seperatorparser)
  return function(valueparser)
    return Parser(function (parserstate)
        if parserstate.iserror then return parserstate end
        local results = {}
        local nextstate = parserstate
        while true do
          local thethingwewant = valueparser.f(nextstate)
          if thethingwewant.iserror then
              break
          end
          table.insert(result,thethingwewant.result)
          nextstate = thethingwewant
          local sepstate = seperatorparser.f(nextstate)
          if sepstate.iserror then
              break
          end
          nextstate = sepstate

        end
        if #results == 0 then
          local emsg = string.format('sepby1: Unable to match any input using parser @ index= %d',nextstate.index)
          return errorupdate(nextstate,emsg)
        end
        return update(nextstate,nextstate.index, results)
    end)
  end
end


local sparser = letters:map(function (x) return {typeof='string' , value = x} end)
local numberparser = numbers:map(function (x) return {typeof='number' , value = tonumber(x)} end)
local dicehelper =sequenceof { numbers, string_parser('d'), numbers}
local diceparser = dicehelper:map(function (x) return {typeof='diceroll' , value = {x[1], x[3]}} end)

local betweenparens = between(string_parser('('), string_parser(')'))




local p = betweenparens(letters)
p = p:map(function (x) return x:upper() end)
p = p:errormap(function (msg, idx) return string.format("'%s' error @ index=%d",msg, idx)  end )
a = p:run('(hello)')



local p2 =  sequenceof {letters, string_parser(':')}
local p2 = p2:map( function (x) return x[1] end )
p2 = p2:chain( function (typeof)
    if typeof == 'string' then
        return sparser
    elseif typeof == 'number' then
        return numberparser
    else
        return diceparser
    end
end)

-- print('a.result =' .. a.result)
-- print('a.iserror =' .. tostring(a.iserror))
-- print_parser_state(a)

-- b = p2:run('string:hello')
-- print_parser_state(b)
-- c = p2:run('number:42')
-- print_parser_state(c)
-- d = p2:run('diceroll:2d10')
-- print_parser_state(d)

local betweensquarebrackets = between(string_parser('['), string_parser(']'))
local commaseperated= sepby(string_parser(','))
-- local p3 = (commaseperated(numbers))
-- local exampletarget = '1,2,3,4'
-- e = p3:run(exampletarget)
-- print_parser_state(e)


-- local p4 =  betweensquarebrackets(commaseperated(letters))
-- e = p4:run(exampletarget)
-- print_parser_state(e)
local p5 = betweensquarebrackets(commaseperated(letters))
-- p5 = p5:map(function (x) return x[2] end)
exampletarget = '[a,b,c,d]'
d = p5:run(exampletarget)
print_parser_state(d)

-- local p5 =  betweensquarebrackets((letters))
-- exampletarget = '[abcd]'
-- e = p5:run(exampletarget)
-- print_parser_state(e)

local lazy = function (thunk)
    local f = function()
        -- TODO: consider one time evaluation for parser
        while true do coroutine.yield( thunk()) end
    end
    local thread = coroutine.create(f)
    return Parser(
        function (parserstate)
            local s,v = coroutine.resume(thread)
            return v.f(parserstate)
        end
    )
end

local arrayparser
local elems = lazy(function() return choice({numbers, arrayparser}) end )
arrayparser = betweensquarebrackets(commaseperated(elems))

f = arrayparser:run('[1,2,[3,4],5]')
print_parser_state(f)

local bitparser = Parser (function(parserstate)
  if parserstate.iserror then return parserstate end
  local byteoffset= math.floor(parserstate.index / 8)
  local bitoffset = (parserstate.index - 1) % 8
  assert(bitoffset,"bitoffset should be non nil")
  local byte = string.byte(parserstate[1],index)
  assert(byte,"byte should be non nil")
  local result = bit32.rshift(
    bit32.band(byte,
      bit32.lshift(1, bitoffset)
    )
  , bitoffset
  )
  return update(parserstate,parserstate.index + 1, result)
end)

local one = Parser (function(parserstate)
  if parserstate.iserror then return parserstate end
  local byteoffset= math.floor(parserstate.index / 8)
  local bitoffset = (parserstate.index - 1) % 8
  assert(bitoffset,"bitoffset should be non nil")
  local byte = string.byte(parserstate[1],index)
  assert(byte,"byte should be non nil")
  local result = bit32.rshift(
    bit32.band(byte,
      bit32.lshift(1, bitoffset)
    )
  , bitoffset
  )
  if result ~= 1 then
      local emsg = string.format("expected one but got 0 @ index %d",parserstate.index)
      return errorupdate(parserstate,emsg)
  end
  return update(parserstate,parserstate.index + 1, result)
end)


local zero = Parser (function(parserstate)
  if parserstate.iserror then return parserstate end
  local byteoffset= math.floor(parserstate.index / 8)
  local bitoffset = (parserstate.index - 1) % 8
  assert(bitoffset,"bitoffset should be non nil")
  local byte = string.byte(parserstate[1],index)
  assert(byte,"byte should be non nil")
  local result = bit32.rshift(
    bit32.band(byte,
      bit32.lshift(1, bitoffset)
    )
  , bitoffset
  )
  if result ~= 0 then
      local emsg = string.format("expected zero but got 1 @ index %d",parserstate.index)
      return errorupdate(parserstate,emsg)
  end
  return update(parserstate,parserstate.index + 1, result)
end)

local p6 = sequenceof { bitparser, bitparser, bitparser, bitparser, bitparser, bitparser, bitparser, zero,}

p6 = p6:map(function (res) return '0b' .. string.reverse(table.concat(res)) end)
local binary_string = string.char(0x7f, 0x33)
for i=1,string.len(binary_string),1 do
    print(string.format('0x%02X',string.byte(binary_string, i)))
end
print('----------------------------------------------------')
g = p6:run(binary_string)
print('----------------------------------------------------')
print_parser_state(g)
