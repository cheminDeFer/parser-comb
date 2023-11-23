local err_update = function (parserstate, errmsg)
    parserstate.iserror = true
    parserstate.errormsg = errmsg
    return parserstate
end

local update = function (parserstate, index, result)
    parserstate.index = index
    parserstate.result = result
    return parserstate
end

local parser = function (s)
  return function (parserstate)
    local targetstring = parserstate[1]
    local index = parserstate.index
    local iserror = parserstate.iserror
    if iserror then return parserstate end
    local sliced =targetstring:sub(index)
    if #sliced == 0 then return err_update(parserstate, string.format("unexpected eof at %d", index)) end
    if sliced:match('^' .. s)then
      return update(parserstate, index + #s, s)
    end
    local emsg =string.format('cannot match "%s" got "%s" at %d', s ,targetstring:sub(index) , index)
    return err_update ( parserstate, emsg )
  end
end

local sequenceof = function (parsers)
    return function (parserstate)
        local results = {}
        local nextstate = parserstate
        for _, p in ipairs(parsers) do
            nextstate = p(nextstate)
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
end


local run = function (parser, targetString)

  local initialState = {
    targetString,
    index = 1,
    result = {},
  }
  return parser(initialState)

end


print_parser_state = function (state) --TODO: reconsider me for arrays etc
  local f;
  if state.iserror then
    f = string.format('{errormsg: %s}',state.errormsg)
  else
    f = string.format('{result:%s, index: %d } ', state.result, state.index)
  end
  print(f)
end
local p = sequenceof ( { parser('hello'), parser('world'), parser('wworld')})
a = run(p, 'hello')


