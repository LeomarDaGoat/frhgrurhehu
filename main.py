import argparse, asyncio
from pathlib import Path
from deobfuscators.router import deobfuscate_script
async def run(k,s): return await deobfuscate_script(k,s)
def main():
    p=argparse.ArgumentParser(); p.add_argument("input",type=Path); p.add_argument("-o","--output",type=Path,default=Path("deobfuscated.lua")); p.add_argument("--kind",default="auto")
    a=p.parse_args(); r,d=asyncio.run(run(a.kind,a.input.read_text(errors="replace")))
    a.output.write_text(r,encoding="utf-8"); print(f"[+] {d.name} -> {a.output}")
if __name__=="__main__": main()
