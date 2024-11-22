"""
Created in June, 2022 by
[chifi - an open source software dynasty.](https://github.com/orgs/ChifiSource)
by team
### ToolipsUDP
This module provides a high-level `Toolips` interface for UDP servers. As with regular `Toolips` 
TCP web-severs, servers are modules and started with `start!` -- distinctly, `ToolipsUDP.start!`. 
Rather than `Routes` being used via `route`, the `UDPHandler` is used via `handler`.
```julia
module NewServer
using ToolipsUDP

new_handler = handler("new") do c::UDPConnection
    respond!(c, "hello")
end

export new_handler, start!
end
```
The API provides the obvious `get_ip` binding, as well as `send` and `respond!` for convenient 
peer-to-server communication.
"""
module ToolipsUDP
using Toolips.Sockets
import Toolips: IP4, AbstractConnection, get_ip, write!, ip4_cli, ProcessManager, assign!, server_cli
import Toolips: route!, on_start, AbstractExtension, AbstractRoute, respond!, start!, ServerTemplate, new_app
using Toolips.ParametricProcesses
using Toolips.Pkg: activate, add
import Toolips.Sockets: send
import Base: show, read, getindex, setindex!, push!


abstract type AbstractUDPHandler <: AbstractRoute end

struct UDPHandler <: AbstractUDPHandler
    f::Function
end

struct NamedHandler <: AbstractUDPHandler
    f::Function
    name::String
end

handler(f::Function) = UDPHandler(f)

handler(f::Function, name::String) = NamedHandler(f, name)

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
be created by providing the `handler` function with a `name` and a `Function`.
```julia
module MyNewServer
using ToolipsUDP

mainhandler = handler() do c::UDPConnection
    respond!(c, "hello")
end

export start!, mainhandler
end
```
Like in `Toolips`, a `UDPConnection` can be indexed with a `Symbol` to get data, 
and pushed to directly.
##### constructors
- `UDPConnection(data::Dict{Symbol, Any}, server::Sockets.UDPSocket)`
"""
mutable struct UDPConnection <: AbstractConnection
    ip::IP4
    packet::String
    handlers::Vector{AbstractUDPHandler}
    data::Dict{Symbol, Any}
    server::Sockets.UDPSocket
    function UDPConnection(data::Dict{Symbol, Any}, server::Sockets.UDPSocket, handlers::Vector{AbstractUDPHandler})
        ip, rawdata = recvfrom(server)
        packet = String(rawdata)
        port = Int64(ip.port)
        ip = string(ip.host)
        new(ip:port, packet, handlers, data, server)::UDPConnection
    end
end

write!(c::UDPConnection, a::Any ...) = throw("`respond!` should be used in place of `write!` for a `UDPHandler`.")

getindex(c::UDPConnection, data::Symbol) = c.data[data]
setindex!(c::UDPConnection, a::Any, data::Symbol) = c.data[data] = a
push!(c::UDPConnection, dat::Any ...) = push!(c.data, dat...)

"""
### abstract type AbstractUDPExtension <: Toolips.AbstractExtension
An `AbstractUDPExtension` is a `Toolips` extension (`<:AbstractExtension`) 
that is meant to be loaded in a `UDPServer`. Like regular extensions, these 
are binded to `on_start` and `route!`.

- See also: `UDPExtension{<:Any}`, `AbstractUDPHandler`, `UDPHandler`, `ToolipsUDP`
"""
abstract type AbstractUDPExtension <: AbstractExtension end

"""
```julia
UDPExtension{T <: Any} <: AbstractUDPExtension
```
This is a blank `UDPExtension` to be used parametrically with multiple 
dispatch for " quick extensions". For example, we could write an `on_start` dispatch 
    for a `UDPExtension{:cr}` and export a `UDPExtension{:cr}` to load some data into the server.
```julia
module NewServer
using ToolipsUDP
import ToolipsUDP: on_start, route!, UDPExtension

# called on each response
function route!(c::UDPConnection, ext::UDPExtension{:cr})

end

# called when the server starts
function on_start(data:::Dict{Symbol, Any}, ext::UDPExtension{:cr})
    push!(data, :count => 5)
end

mainhandler = handler("counter") do c::UDPConnection
    c[:count] += 5
end

data_ext = UDPExtension{:cr}()
export mainhandler, data_ext
end
```
- See also: `handler`, `UDPConnection`, `on_start`, `route!`, `AbstractUDPExtension`
```julia
UDPExtension{T <: Any}()
```
"""
struct UDPExtension{T <: Any} <: AbstractUDPExtension

end

"""
```julia
route!(c::UDPConnection, ext::AbstractUDPExtension)
```
This dispatch fills the same role `route!` normally fills in base `Toolips`, 
just for `UDPExtensions`. Like in `Toolips`, this function can be extended to add 
    server functionality.
"""
function route!(c::UDPConnection, ext::AbstractUDPExtension)

end

"""
```julia
on_start(data::Dict{Symbol, Any}, ext::AbstractUDPExtension)
```
This dispatch fills the same role `on_start` normally fills in base `Toolips`, 
just for `UDPExtensions`. Like in `Toolips`, this function can be extended to add 
    server functionality.
"""
function on_start(data::Dict{Symbol, Any}, ext::AbstractUDPExtension)

end

abstract type UDP <: ServerTemplate end

"""
```julia
ToolipsUDP.start!(st::Type{ServerTemplate{:UDP}}, mod::Module = Toolips.server_cli(Main.ARGS), ip::IP4 = Toolips.ip4_cli(Main.ARGS); threads::Int64 = 1)
```
Starts a Server Module as a `ToolipsUDPServer`. `UDP` is provided as a constant from `ToolipsUDP`.
```julia
module MyServer
using ToolipsUDP

responder = handler() do c::UDPConnection
    data = c.packet
    println(c.packet)
end

export responder
end

using ToolipsUDP; start!(UDP, MyServer)
```
"""
function start!(st::Type{UDP}, mod::Module = server_cli(Main.ARGS);ip::IP4 = ip4_cli(Main.ARGS), threads::Int64 = 1)
    data::Dict{Symbol, Any} = Dict{Symbol, Any}()
    server_ns::Vector{Symbol} = names(mod)
    loaded = []
    handlers = Vector{AbstractUDPHandler}()
    for name in server_ns
        f = getfield(mod, name)
        T = typeof(f)
        if T <: AbstractUDPExtension
            push!(loaded, f)
        elseif T <: AbstractUDPHandler
            push!(handlers, f)
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
    if threads < 2
        t = @async while server.status > 2
            con::UDPConnection = UDPConnection(data, server, handlers)
            try
                [route!(con, UDPExtension(ext.parameters[1])) for ext in loaded]
            catch e
                throw(e)
            end
            try
                handlers[1].f(con)
            catch e
                throw(e)
            end
        end
    else
        add_workers!(pm, threads)
        pids::Vector{Int64} = [work.pid for work in filter(w -> typeof(w) != Worker{ParametricProcesses.Async}, pm.workers)]
        put!(pm, pids, data)
        selected::Int64 = 1
        put!(pm, pids, server)
        put!(pm, pids, handlers)
        t = @async while server.status > 2
            con::UDPConnection = UDPConnection(data, server, handlers)
            @sync selected += 1
            if selected > threads
                @sync selected = minimum(router_threads[1])
            end
            if selected < 1
                
            end
            try
                [route!(con, UDPExtension(ext.parameters[1])) for ext in loaded]
            catch e
                throw(e)
            end
            try
                handlers[1].f(con)
            catch e
                throw(e)
            end
        end
    end
    w::Worker{Async} = Worker{Async}("$mod server", rand(1000:3000))
    w.active = true
    w.task = t
    ProcessManager(w)::ProcessManager
end

function route_server(pm::ProcessManager, selected::Int64)

end

function new_app(st::UDP, name::String)
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

get_ip(c::UDPConnection) = c.ip::String

function send(c::UDPConnection, data::String, to::IP4 = "127.0.0.1":2000)
    sock = c.server
    send(sock, parse(IPv4, to.ip), to.port, data)
end


respond!(c::UDPConnection, data::String) = send(c, data, c.ip)


function send(c::Module, data::String, to::IP4 = "127.0.0.1":2000)
    sock = c.server
    send(sock, parse(IPv4, to.ip), to.port, data)
end

mutable struct MultiHandler
    dct::Dict{IP4, String}
end

function set_handler!(c::UDPConnection, name::String)

end

export send, UDPServer, UDPConnection, respond!, start!, IP4, write!, handler, UDPExtension

end # module ToolipsUDP
