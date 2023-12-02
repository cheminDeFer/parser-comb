function readonlytable(table)
   return setmetatable({}, {
     __index = table,
     __newindex = function(table, key, value)
                    error('Attempt to modify read-only table')
                  end,
     __metatable = false
   });
end
local err_update = function (parserstate, errmsg)
  assert(parserstate,'something fishy in err_update')
  local newstate = {}

  newstate.iserror = true
  newstate.errormsg = errmsg
  newstate.result = nil
  newstate.index = parserstate.index

  return newstate
end

local update = function (parserstate, index, result)
    local newstate = {}
    newstate[1] = parserstate[1]
    newstate.index = index
    newstate.result = result
    newstate.iserror = false
    return newstate
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
    if not(nextstate.iserror)  then return nextstate  end
    return err_update(nextstate, fn(nextstate.errormsg, nextstate.index))
  end)
end

local string_parser = function (s)
  return Parser(function (parserstate)
    local targetstring = parserstate[1]
    local index = parserstate.index
    local iserror = parserstate.iserror
    if iserror then return parserstate end
    local sliced =targetstring:sub(index)
    if #sliced == 0 then return err_update(parserstate, string.format("unexpected eof at %d", index)) end

    if sliced:sub(1,s:len()) == s then
      return update(parserstate, index + #s, s)
    end
    local emsg =string.format('cannot match "%s" got "%s" at %d', s ,targetstring:sub(index) , index)
    return err_update ( parserstate, emsg )
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
    if #sliced == 0 then return err_update(parserstate, string.format("letters: unexpected eof at %d", index)) end
    local match =sliced:match('^%a+')
    if match then
      return update(parserstate, index + #match, match)
    end
    local emsg =string.format('cannot match "%s" got "%s" at %d', 'any letter' ,targetstring:sub(index) , index)
    return err_update ( parserstate, emsg )
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
    if #sliced == 0 then return err_update(parserstate, string.format("numbers: unexpected eof at %d", index)) end
    local match =sliced:match('^%d+')
    if match then
      return update(parserstate, index + #match, match)
    end
    local emsg =string.format('cannot match "%s" got "%s" at %d', 'any numbers' ,targetstring:sub(index) , index)
    return err_update ( parserstate, emsg )
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
    while true do
      nextstate = p.f(nextstate)
      table.insert(results,nextstate.result)
      if (nextstate.iserror) then break end
    end
    if #result == 0 then
        local emsg = string.format('many1: Unabke to match any input using parser @ index= %s',nextstate.index)
        return err_update(nextstate,emsg)
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

-- focus here
-- if there is an error somehow you should not proceed a state with error field set to true ?--
local choice = function (parsers)
  return Parser(function (parserstate)

    assert(parserstate, 'something ifshy in choice')
    if parserstate.iserror then
        return parserstate
    end
    --- how parserstate is  modified ???
    for i, p in ipairs(parsers) do
      local nextstate = p.f(parserstate)
      if not(nextstate.iserror) then
          return nextstate
      end
    end
    local emsg =string.format(
        'choice unable to match with any parser at %d',
        parserstate.index
    )
    return err_update(parserstate,emsg)
  end
  )
end


local run = function (parser, targetString)

  local initialState = {
    targetString,
    index = 1,
    result = {},
  }
  return parser(initialState)

end

local print_parser_state = function (state) --TODO: reconsider me for arrays etc
  local f;
  if state.iserror then
    f = string.format('{errormsg: %s}',state.errormsg)
  else
    f = string.format('{result:%s, index: %d } ', state.result, state.index)
  end
  print(f)
end
local alt_p =  many(choice({ letters, numbers}))
alt_p = alt_p:map(function (x)

  local res = ""
  for i,v in ipairs(x) do res = res .. v .. ','  end
  return '<' .. res:sub(1,#res-1) .. '>' end
)
alt_p = alt_p:errormap(function (msg, idx) return string.format("'%s' error @ index=%d",msg, idx)  end )
alt_a = alt_p:run('1234hellony1123')
