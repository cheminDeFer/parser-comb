local Parser = require 'parser'
local choice = Parser.choice
local many = Parser.many
local many1 = Parser.many1
local letters = Parser.letters
local numbers = Parser.numbers
local sepby = Parser.sepby
local string_parser = Parser.string_parser
local sequenceof = Parser.sequenceof
local between = Parser.between
local lazy = Parser.lazy
local bitparser = Parser.bitparser
local zero = Parser.zero
print_parser_state = Parser.print_parser_state

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
print_parser_state(a)

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

b = p2:run('string:hello')
print_parser_state(b)
c = p2:run('number:42')
print_parser_state(c)
d = p2:run('diceroll:2d10')
print_parser_state(d)

local betweensquarebrackets = between(string_parser('['), string_parser(']'))
local commaseperated= sepby(string_parser(','))
local p3 = (commaseperated(numbers))
local exampletarget = '1,2,3,4'
e = p3:run(exampletarget)
print_parser_state(e)

local p4 =  betweensquarebrackets(commaseperated(letters))
e = p4:run(exampletarget)
print_parser_state(e)
local p5 = betweensquarebrackets(commaseperated(letters))
p5 = p5:map(function (x) return x[2] end)
exampletarget = '[a,b,c,d]'
d = p5:run(exampletarget)
print_parser_state(d)

local p5 =  betweensquarebrackets((letters))
exampletarget = '[abcd]'
e = p5:run(exampletarget)
print_parser_state(e)

local arrayparser
local elems = lazy(function() return choice({numbers, arrayparser}) end )
arrayparser = betweensquarebrackets(commaseperated(elems))

f = arrayparser:run('[1,2,[3,4],5]')
print_parser_state(f)

local p6 = sequenceof { bitparser, bitparser, bitparser, bitparser, bitparser, bitparser, bitparser, zero,}
p6 = p6:map(function (res) return '0b' .. string.reverse(table.concat(res)) end)

local binary_string = string.char(0x7f, 0x33)
for i=1,string.len(binary_string),1 do
    print(string.format('0x%02X',string.byte(binary_string, i)))
end
print('----------------------------------------------------')
g = p6:run(binary_string)
print_parser_state(g)
print('----------------------------------------------------')



local binary_string2 = string.char(234, 235)

local bitparsers = {}
for i=1,16 do table.insert(bitparsers,bitparser)  end
local pbinaryshow = sequenceof( bitparsers)
pbinaryshow = pbinaryshow:map(function (res) return '0b' .. (table.concat(res)) end)
z = pbinaryshow:run(binary_string2)
print_parser_state(z)

local p8 = Parser.uint(2,">")
ii = p8:run(binary_string2)
print_parser_state(ii)
print('----------------------------------------------------')
local p9 = Parser.uint(2, "<")
lol = p9:run(binary_string2)
print_parser_state(lol)
print('----------------------------------------------------')

local binary_string3 = "abc"
local compare = string.char(0x61,0x62,0x64)
local p9 = Parser.binary_str(compare)
kat = p9:run(binary_string3)
print_parser_state(kat)
