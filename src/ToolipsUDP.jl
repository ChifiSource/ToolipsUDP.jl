"""
Created in February, 2022 by
[chifi - an open source software dynasty.](https://github.com/orgs/ChifiSource)
by team
[toolips](https://github.com/orgs/ChifiSource/teams/toolips)
This software is MIT-licensed.
### ToolipsUDP
ToolipsUDP provides a simple `UDPServer` which works with toolips infastructure.
##### Module Composition
- [**Toolips**](https://github.com/ChifiSource/Toolips.jl)
"""
module ToolipsUDP
using Sockets
using Sockets: UDPSocket, recv
import Sockets: send
using Toolips
import Toolips: ToolipsServer, AbstractConnection

"""
### UDPServer <: Toolips.ToolipsServer
- ip::String
- port::Int64
- extensions::Vector{ServerExtension}
- start::Function
- server::Any\n
The UDPServer is not a traditional webserver; it is focused
on serving clients a lot faster and is typically used for bigger data transfer
    scenarios, such as a video game. That being said, that is exactly the kind
    of thing that this module is for.
##### example
```
using Toolips
using ToolipsUDP
myserver = UDPServer("127.0.0.1", 8000) do c::Connection
myserver.start()
```
------------------
##### constructors
- UDPServer(f::Function)
"""
mutable struct UDPServer <: ToolipsServer
    ip::String
    PORT::Int64
    extensions::Vector{ServerExtension}
    start::Function
    server::Any
    f::Function
    function UDPServer(f::Function, ip::String = "128.0.0.1", port::Int64 = 8000;
        extensions = Vector{ServerExtension}([Logger()]))
        server::Any = []
        start() = begin
            task = @async begin
                sock::UDPSocket = UDPSocket()
                bind(sock, Sockets.IPv4(ip), port)
                while true
                    mydata::String = String(read(sock))
                    f(mydata)
                end
                close(sock)
            end
            push!(server, task)
        end
        new(ip, port, extensions, start, server, f)::UDPServer
    end
end

function send(s::String, ip::String = "127.0.0.1", port::Int64 = 8000)
     soc = UDPSocket()
     send(soc, Sockets.IPv4(ip), port, s)
end
export send, UDPServer
end # module
