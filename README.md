# Updated Deobfuscator Bot

Drop-in extension. Put this folder's files beside your existing `bot.py`.

```python
from deobf_bot_extension import setup_deobf_commands
setup_deobf_commands(bot)
```

No token or `bot.run()` is included.

Supports:
- Auto-Detect
- IronBrew 1 (`ib1 all input -o output`)
- IronBrew 2 / AztupBrew adapter
- IronBrew 3 local parser
- LuaObfuscator adapter
- URL, Discord markdown URL, file, reply, codeblock, raw text
- manual failure fallback to <#1550879929019662406>

Build terrorlua fingerprints:
```powershell
py tools/build_terrorlua_fingerprints.py --out deobfuscators/fingerprints/terrorlua.json
```
