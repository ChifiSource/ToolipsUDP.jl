<div align="center"><img src="https://github.com/ChifiSource/image_dump/raw/main/toolips/toolipsudp.png"></img></div>

`ToolipsUDP` provides high-level `Toolips`-style functionality to UDP networking projects. This functionality is facilitated via the `UDPServer` and `UDPConnection` types. Whereas a `Toolips` `WebServer` typically comes with a router, the `UDPServer` takes a `Function` directly and provides this function with a `UDPConnection`.
```julia
using ToolipsUDP
newserver = UDPServer("127.0.0.1", 2000) do c::UDPConnection
    println(c.data)
end

newserver.start()
```
