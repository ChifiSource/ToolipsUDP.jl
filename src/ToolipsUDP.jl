"""
Created in June, 2022 by
[chifi - an open source software dynasty.](https://github.com/orgs/ChifiSource)
by team
### ToolipsUDP
This module provides a high-level `Toolips` interface for UDP servers.
"""
module ToolipsUDP
using Toolips.Sockets
using Toolips.Pkg: activate, add
import Toolips.Sockets: send
import Toolips: ServerExtension, ToolipsServer, AbstractConnection, getip, write!, new_app
import Base: show, read, getindex, setindex!, push!

"""
### UDPConnection <: Toolips.AbstractConnection
- ip**::String**
- port**::Int64**
- packet**::String**
- data**::Dict{Symbol, String}**
- server**::Sockets.UDPSocket**
---
The `UDPConnection` is provided as an argument to the `Function` provided 
to your `UDPServer` constructor. The `packet` field carries the data currently being transmitted. 
The `data` field holds indexable data, which may be indexed by indexing the `UDPConnection` with a 
`Symbol`. Finally, the `ip` and the `port` may be used to find more information on the server.
##### example
```
```
---
##### constructors
- `UDPConnection(data::Dict{Symbol, Any}, server::Sockets.UDPSocket)`
"""
mutable struct UDPConnection <: AbstractConnection
    ip::String
    port::Int64
    packet::String
    data::Dict{Symbol, String}
    server::Sockets.UDPSocket
    function UDPConnection(data::Dict{Symbol, Any}, server::Sockets.UDPSocket)
        ip, rawdata = recvfrom(server)
        packet = String(rawdata)
        port = Int64(ip.port)
        ip = string(ip.host)
        new(ip, port, packet, data, server)::UDPConnection
    end
end

getindex(c::UDPConnection, data::Symbol) = c.data[data]
setindex!(c::UDPConnection, a::Any, data::Symbol) = c.data[data] = a
push!(c::UDPConnection, dat::Any ...) = push!(c.data, dat...)

"""
### UDPExtension{T <: Any} <: Toolips.ServerExtension
- type::Symbol

The `UDPExtension` is a parametric type used to add functionality to a `UDPServer` from 
a given environment. Using the parameter of the `UDPExtension`, we are able to add 
new functionality to our `UDPServer` by extending `ToolipsUDP.serve` 
(runs an extension each time the server is called) or `ToolipsUDP.onstart` (runs an extension on server start)
##### example
```
```
---
##### constructors
- `UDPExtension(T::Symbol)`
"""
mutable struct UDPExtension{T <: Any} <: ServerExtension
    type::Symbol
    UDPExtension(T::Symbol) = new{T}(:connection)
end

"""
### UDPServer <: ToolipsServer
- host::String
- port::Int64
- server::Sockets.UDPSocket
- start::Function

The `UDPServer` creates a connection-less server ideal for parsing incoming 
packets of data quickly. The constructor is provided with a constructor that will 
retrieve and organize data from an incoming `Connection`.

This server may be extended using the `UDPExtension` 
type. (`?ToolipsUDP.UDPExtension`)
##### example
In most cases, (in cases where we are source, or need to respond to a sink), we will 
provide a `Function` to the `UDPServer` constructor.
```example
```
When working from a sink perspective, sending data to a server, it might make more sense to just 
provide the `host`.

The `Function` provided to `UDPServer` will take a `UDPServer.UDPConnection`. To be clear on terminology, 
`UDPConnection` is not a `Connection` in the traditional sense, but in the `Toolips` sense. (`?UDPConnection`)
---
##### constructors
- `UDPServer(f::Function, host::String = "127.0.0.1", port::Int64 = 2000)`
- `UDPServer(host::String, port::Int64)`
"""
mutable struct UDPServer <: ToolipsServer
    host::String
    port::Int64
    server::Sockets.UDPSocket
    start::Function
    function UDPServer(f::Function, host::String = "127.0.0.1", port::Integer = 2000)
        server = UDPSocket()
        start() = begin
            data::Dict{Symbol, Any} = Dict{Symbol, Any}()
            ms::Base.MethodList = methods(onstart)
            exlist = filter!(sig -> sig != UDPExtension, [m.sig.parameters[3] for m in ms])
            [onstart(data, UDPExtension(ext.parameters[1])) for ext in exlist]
            ms = methods(serve)
            exlist = filter!(sig -> sig != UDPExtension, [m.sig.parameters[3] for m in ms])
            bind(server, parse(IPv4, host), port)
            Threads.@spawn while server.status == 3
                con::UDPConnection = UDPConnection(data, server)
                [serve(con, UDPExtension(ext.parameters[1])) for ext in exlist]
                try
                    f(con)
                catch e
                    throw(e)
                end
            end
        end
        new(host, port, server, start)::UDPServer
    end
    UDPServer(host::String, port::Integer) = UDPServer(c::UDPConnection -> nothing, host, port)::UDPServer
end

"""
**ToolipsUDP**
```julia
new_app(name::String, T::Type{UDPServer}) -> ::Nothing
```
------------------
Generates a new `Toolips` app and then converts the project to a `ToolipsUDP` `UDPServer` 
project.
#### example
```example
using ToolipsUDP

ToolipsUDP.new_app("Example", UDPServer)
```
(**note** that not providing the type creates a regular `Toolips` app.)
"""
function new_app(name::String, T::Type{UDPServer})
    Toolips.new_app(name)
    activate(name)
    add("ToolipsUDP")
    open("$name/src/$name.jl", "w") do o::IO
        write(o, 
        """module $name
        using ToolipsUDP

        function start(ip::String = "127.0.0.1", port::Int64 = 2000)
            myserver = UDPServer() do c::UDPConnection
                println(c.packet)
                println(c.ip)
                println(c.port)
            end
            myserver.start()
            myserver
        end

        function send_to_my_server(data::String)
            server2 = UDPServer("127.0.0.1", 2005)
            server2.start()
            ToolipsUDP.send(server2, "test", myserver.host, myserver.port)
        end
        ==#
        """)
    end
end

"""
**ToolipsUDP**
```julia
serve(c::UDPConnection, ext::UDPExtension{<:Any}) -> ::Nothing
```
------------------
This is an extensible `Function` which may be used to extend a `UDPServer`. 
This is done by simply adding new methods to this type. Each `Method` is ran everytime 
the server responds.
#### example
```example
import ToolipsUDP: serve

function serve(c::UDPConnection, ext::UDPExtension{:printstuff})
    println(c.ip * ":" * c.port)
    println(c.packet)
end
```
"""
function serve(c::UDPConnection, ext::UDPExtension{<:Any})

end

"""
**ToolipsUDP**
```julia
onstart(data::Dict{Symbol, Any}, ext::UDPExtension{<:Any}) -> ::Nothing
```
---
This is an extensible `Function` which may be used to extend a `UDPServer`. 
This is done by simply adding new methods to this type. Each `Method` is ran with the server's data when the server starts.
#### example
```example
import ToolipsUDP: onstart

function onstart(data::Dict{Symbol, Any}, ext::UDPExtension{:lognames})
    push!(data, :people => Dict{String, Any}())
end
```
"""
function onstart(data::Dict{Symbol, Any}, ext::UDPExtension{<:Any})

end

function show(io::IO, ts::UDPServer)
    st = ts.server.status
    active::String = "inactive"
    if st == 3 || st == 4
        active = "active"
    end
    print("""$(typeof(ts))
        UDP server: $(ts.host):$(ts.port)
        status: $active ($(st))
        """)
end

"""
**ToolipsUDP**
```julia
send(data::String, to::String = "127.0.0.1", port::Int64; from::Int64 = port - 5) -> ::Nothings
```
---
Creates a `UDPServer` and then sends `data` to `to`:`port` from 127.0.0.1:`from`.
#### example
```

```
"""
function send(data::String, to::String = "127.0.0.1", port::Int64 = 2000; from::Int64 = port - 5)
    sock = UDPSocket()
    bind(sock, ip"127.0.0.1", from)
    send(sock, parse(IPv4, to), port, data)
    close(sock)
    nothing
end

"""
**ToolipsUDP**
```julia
send(c::UDPConnection, data::String, to::String = "127.0.0.1", port::Int64; from::Int64 = port - 5) -> ::Nothing
```
---
Sends `data`` from the `UDPServer` associated with `c`, the `UDPConnection`.
#### example
```

```
"""
function send(c::UDPConnection, data::String, to::String = "127.0.0.1", port::Int64 = 2000)
    sock = c.server
    send(sock, parse(IPv4, to), port, data)
    nothing
end

"""
**ToolipsUDP**
```julia
send(c::UDPServer, data::String, to::String = "127.0.0.1", port::Int64; from::Int64 = port - 5) -> ::Nothing
```
---
Sends `data` to `to` from `c`.
#### example
```example
myserver = UDPServer() do c::UDPConnection
    println(c.ip)
end

myserver.start()

server2 = UDPServer("127.0.0.1", 2005)
server2.start()

ToolipsUDP.send(server2, "test", myserver.host, myserver.port)
```
"""
function send(c::UDPServer, data::String, to::String = "127.0.0.1", port::Int64 = 2000)
    sock = c.server
    send(sock, parse(IPv4, to), port, data)
    nothing
end

export send, UDPServer, UDPConnection

end # module ToolipsUDP
