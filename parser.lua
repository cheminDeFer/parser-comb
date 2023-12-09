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
  assert(errmsg, 'errmsg is nil in errorupdate')
  assert(type(errmsg) == 'string', string.format('errmsg is not a string in errorupdate type: <%s>', type(errmsg)))
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
  assert(f, 'f is nil in Parser.new')
  assert(type(f) == 'function', 'f is not a function in Parser.new')
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

Parser.string_parser = function (s)
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

Parser.letters =
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

Parser.numbers = Parser(function (parserstate)
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

Parser.sequenceof = function (parsers)
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

Parser.many = function (parser)
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

Parser.many1 = function (parser)
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

Parser.choice = function (parsers)
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

Parser.print_parser_state = function (state)

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

Parser.between = function (left, right)
    return function (content)
        local s = Parser.sequenceof ( { left, content , right} )
        return s:map(function (x) return x[2] end )
    end
end

Parser.sepby = function (seperatorparser)
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

Parser.sepby1 = function (seperatorparser)
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


Parser.lazy = function (thunk)
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


Parser.bitparser = Parser (function(parserstate)
  if parserstate.iserror then return parserstate end
  local byteoffset= math.floor((parserstate.index - 1) / 8)
  local bitoffset = (parserstate.index - 1) % 8
  assert(bitoffset,"bitoffset should be non nil")
  local byte = string.byte(parserstate[1],byteoffset + 1)
  assert(byte,"byte should be non nil")
  local result = bit32.rshift(
    bit32.band(byte,
      bit32.lshift(1, bitoffset)
    )
  , bitoffset
  )
  return update(parserstate,parserstate.index + 1, result)
end)

Parser.one = Parser (function(parserstate)
  if parserstate.iserror then return parserstate end
  local byteoffset= math.floor( (parserstate.index - 1) / 8)
  local bitoffset = (parserstate.index - 1) % 8
  assert(bitoffset,"bitoffset should be non nil")
  local byte = string.byte(parserstate[1],byteoffset + 1)
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


Parser.zero = Parser (function(parserstate)
  if parserstate.iserror then return parserstate end
  local byteoffset= math.floor( (parserstate.index - 1) / 8)
  local bitoffset = (parserstate.index - 1) % 8
  assert(bitoffset,"bitoffset should be non nil")
  local byte = string.byte(parserstate[1],byteoffset + 1)
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

Parser.uint = function (n)
  local bitparsers = {}
  for i=1,n do
    table.insert(bitparsers, Parser.bitparser)
  end
  local bp = Parser.sequenceof(bitparsers)
  bp = bp:map( function (x)
    local res = 0
    for i,v in pairs(x) do
      res = res + 2^(i-1) * v
    end
    return res
  end
  )
  return bp
end

Parser.uint_he = function (n)
  local bitparsers = {}
  for i=1,n do
    table.insert(bitparsers, Parser.bitparser)
  end
  local bp = Parser.sequenceof(bitparsers)
  bp = bp:map( function (x)
    local res = 0
    for i,v in pairs(x) do
      res = res + 2^(i-1) * v
    end
    return res
  end
  )
  return bp
end

Parser.int = function (n)
  local bitparsers = {}
  for i=1,n do
    table.insert(bitparsers, Parser.bitparser)
  end
  local bp = Parser.sequenceof(bitparsers)
  bp = bp:map( function (x)
    local res = 0
    local sign = 0
    for i,v in pairs(x) do
      if (i == n) then
        -- sign = v == 1 and -1  or 1
        res = res - 2^(n-1) * v
      else
        res = res + 2^(i-1) * v
      end
    end
    return res
  end
  )
  return bp
end

return Parser
