"""
Created in June, 2022 by
[chifi - an open source software dynasty.](https://github.com/orgs/ChifiSource)
by team
### ToolipsUDP
This module provides a high-level `Toolips` interface for UDP servers.
"""
module ToolipsUDP
using Toolips.Sockets
import Toolips: IP4, AbstractConnection, get_ip, write!, ip4_cli
import Toolips: route!, on_start, AbstractExtension, AbstractRoute, respond!
using Toolips.ParametricProcesses
using Toolips.Pkg: activate, add
import Toolips.Sockets: send
import Base: show, read, getindex, setindex!, push!

"""
```julia
UDPConnection <: Toolips.AbstractConnection
```
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

Typically, the `UDPConnection` is passed, as a singular positional argument, to a **handler**. A **handler** may 
be created by providing the `handler` function with a `name` and a `Function`. For instance...
##### example
```julia

```
---
##### constructors
- `UDPConnection(data::Dict{Symbol, Any}, server::Sockets.UDPSocket)`
"""
mutable struct UDPConnection <: AbstractConnection
    ip::IP4
    packet::String
    data::Dict{Symbol, Any}
    server::Sockets.UDPSocket
    function UDPConnection(data::Dict{Symbol, Any}, server::Sockets.UDPSocket)
        ip, rawdata = recvfrom(server)
        packet = String(rawdata)
        port = Int64(ip.port)
        ip = string(ip.host)
        new(ip:port, packet, data, server)::UDPConnection
    end
end

write!(c::UDPConnection, a::Any ...) = throw("write?")

getindex(c::UDPConnection, data::Symbol) = c.data[data]
setindex!(c::UDPConnection, a::Any, data::Symbol) = c.data[data] = a
push!(c::UDPConnection, dat::Any ...) = push!(c.data, dat...)

abstract type AbstractUDPExtension <: AbstractExtension end

struct UDPExtension{T <: Any} <: AbstractUDPExtension

end

function route!(c::UDPConnection, ext::AbstractUDPExtension)

end


function on_start(data::Dict{Symbol, Any}, ext::AbstractUDPExtension)

end

abstract type AbstractUDPHandler <: AbstractRoute end

struct UDPHandler <: AbstractUDPHandler
    f::Function
    name::String
end

handler = UDPHandler

default_handler = handler("default") do c::UDPConnection
    respond!(c, )
end

function start!(mod::Module = Toolips.server_cli(Main.ARGS), ip::IP4 = Toolips.ip4_cli(Main.ARGS); threads::Int64 = 1)
    data::Dict{Symbol, Any} = Dict{Symbol, Any}()
    server_ns::Vector{Symbol} = names(mod)
    loaded = []
    handler = default_handler
    for name in server_ns
        f = getfield(mod, name)
        T = typeof(f)
        if T <: AbstractUDPExtension
            push!(loaded, f)
        elseif T <: AbstractUDPHandler
            handler = f
        end
        T = nothing
    end
    [on_start(data, ext) for ext in loaded]
    allparams = (m.sig.parameters[3] for m in methods(route!, Any[AbstractConnection, AbstractExtension]))
    filter!(ext -> typeof(ext) in allparams, loaded)
    # server
    server = UDPSocket()
    bind(server, parse(IPv4, ip.ip), ip.port)
    mod.data = data
    mod.server = server
    t = while server.status > 2
        con::UDPConnection = UDPConnection(data, server)
        try
            [route!(con, UDPExtension(ext.parameters[1])) for ext in loaded]
        catch e
            throw(e)
        end
        try
            handler.f(con)
        catch e
            throw(e)
        end
    end
    w::Worker{Async} = Worker{Async}("$mod server", rand(1000:3000))
    w.active = true
    w.task = t
    ProcessManager(w)::ProcessManager
end

function new_app(name::String)
    new_app(name)
    activate(name)
    add("ToolipsUDP")
    open("$name/src/$name.jl", "w") do o::IO
        write(o, 
        """module $name
        using ToolipsUDP

        handler = route() do c::UDPConnection
            respond(c, "hello world!")
        end

        export handler
        end
        """)
    end
end

function send(data::String, to::IP4 = "127.0.0.1":2000; from::Int64 = to.port - 5)
    sock = UDPSocket()
    bind(sock, ip"127.0.0.1", from)
    send(sock, parse(IPv4, to.ip), to.port, data)
    close(sock)
end


function send(c::UDPConnection, data::String, to::IP4 = "127.0.0.1":2000)
    sock = c.server
    send(sock, parse(IPv4, to.ip), to.port, data)
end


respond!(c::UDPConnection, data::String) = send(c, data, c.ip)


function send(c::Module, data::String, to::IP4 = "127.0.0.1":2000)
    sock = c.server
    send(sock, parse(IPv4, to.ip), to.port, data)
end

export send, UDPServer, UDPConnection, respond!, start!, IP4, write!, handler, UDPExtension

end # module ToolipsUDP
