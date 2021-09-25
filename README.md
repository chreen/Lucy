Lucy
====
![GitHub](https://img.shields.io/github/license/chreen/Lucy) 

**Lucy** is an emulator for the now defunct "Lua C" format used in many old Roblox exploits. It roughly translates to Lua's internal C API and was used as a substitute for traditional Lua script execution.

This implementation, unlike others, emulates the specific instructions instead of the entire Lua C API through a parser and custom interpreter.

It is also written to be expandable, so adding more opcodes shouldn't require much work.


## Usage
Below is an example of a Hello world script being ran with Lucy. Exposed functions are documented in [lucy.lua](https://github.com/chreen/Lucy/blob/main/lucy.lua).

```lua
local lucy = loadstring(game:HttpGet("https://raw.githubusercontent.com/chreen/Lucy/main/lucy.lua"))()

lucy.wrap(lucy.parse([[
getglobal print
pushstring Hello world!
call 1 0
emptystack]]), getfenv(0))()
```
