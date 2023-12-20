import os
if os.path.exists("./main.lua"):
    os.rename("./main.lua", "./_main.lua")
    os.rename("./_main.xml", "./main.xml")
else:
    os.rename("./_main.lua", "./main.lua")
    os.rename("./main.xml", "./_main.xml")
