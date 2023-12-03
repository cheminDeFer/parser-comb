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
    if(nextstate.iserror)  then return nextstate  end
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
  return Parser(function (parserstate)
    local results = {}
    local nextstate = parserstate
    for _, p in ipairs(parsers) do
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
-- TODO inspect
local many1 = function (parser)
  return Parser(function (parserstate)
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
        res = res .. k .. ':' .. gettableresult(v) .. ','
    else
        res = res .. k .. ':' .. tostring(v) .. ','
    end
  end
  res = res ..  '}'
  return res
end

local print_parser_state = function (state) --TODO: reconsider me for arrays etc

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
    print('chain is called')
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
d = p2:run('diceroll:2d10')
print_parser_state(d)

