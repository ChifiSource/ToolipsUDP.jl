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
import Toolips: IP4, AbstractConnection, get_ip, write!, ip4_cli, ProcessManager, assign!, AbstractIOConnection
import Toolips: route!, on_start, AbstractExtension, AbstractRoute, respond!, start!, ServerTemplate, new_app, @everywhere
using Toolips.ParametricProcesses
using Toolips.Pkg: activate, add, generate
import Toolips.Sockets: send, bind
import Base: show, read, getindex, setindex!, push!

const UDP = ServerTemplate{:UDP}

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

mutable struct UDPIOConnection <: AbstractIOConnection
    ip::IP4
    packet::String
    handlers::Vector{AbstractUDPHandler}
    data::Dict{Symbol, Any}
    stream::String
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

"""
```julia
ToolipsUDP.start!(st::Type{ServerTemplate{:UDP}}, mod::Module, ip::IP4 = Toolips.ip4_cli(Main.ARGS); threads::Int64 = 1)
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
function start!(st::Type{ServerTemplate{:UDP}}, mod::Module; ip::IP4 = "127.0.0.1":2000, threads::UnitRange{Int64} = 1:1)
    data::Dict{Symbol, Any} = Dict{Symbol, Any}()
    router_threads = maximum(threads)
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
    [begin
        on_start(data, ext)
        T = string(typeof(ext))
        if contains(T, ".")
            splits = split(T, ".")
            T = string(splits[length(splits)])
        end
        push!(data, Symbol(T) => ext)
    end for ext in loaded]
    allparams = (m.sig.parameters[3] for m in methods(route!, Any[AbstractConnection, AbstractExtension]))
    filter!(ext -> typeof(ext) in allparams, loaded)
    # server
    server = UDPSocket()
    bind(server, parse(IPv4, ip.ip), ip.port)
    mod.data = data
    con::UDPConnection = UDPConnection(data, server, handlers)
    mod.server = server
    pm::ProcessManager = ProcessManager()
    if router_threads < 2
        t = @async while server.status > 2
            con = UDPConnection(data, server, handlers)
            stop = nothing
            try
                stop = [route!(con, ext) for ext in loaded]
            catch e
                throw(e)
            end
            f = findfirst(x -> x == false, stop)
            if ~(isnothing(f))
                continue
            end
            try
                handlers[1].f(con)
            catch e
                throw(e)
            end
        end
    else
        add_workers!(pm, router_threads)
        pids::Vector{Int64} = [work.pid for work in filter(w -> typeof(w) != Worker{ParametricProcesses.Async}, pm.workers)]
        Main.eval(Meta.parse("""using ToolipsUDP: @everywhere; @everywhere begin
            using ToolipsUDP
            using $mod
        end"""))
        put!(pm, pids, Main.mod)
        put!(pm, pids, data)
        selected::Int64 = 1
        put!(pm, pids, server)
        put!(pm, pids, handlers)
        put!(pm, pids, con)
        while server.status > 2
            @sync selected += 1
            if selected > router_threads
                @sync selected = minimum(threads)
            end
            if selected < 2
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
                return
            end
            job = new_job() do
                try
                    [route!(con, UDPExtension(ext.parameters[1])) for ext in loaded]
                catch e
                    throw(e)
                end
                try
                    con.handlers[1].f(con)
                catch e
                    throw(e)
                end
                return
            end
            assign!(pm, selected, job)
        end
    end
    w::Worker{Async} = Worker{Async}("$mod server", rand(1000:3000))
    w.active = true
    w.task = t
    push!(pm.workers, w)
    pm::ProcessManager
end


function new_app(st::Type{ServerTemplate{:UDP}}, name::String)
    generate(name)
    activate(name)
    add("ToolipsUDP")
    open("$name/src/$name.jl", "w") do o::IO
        write(o, 
        """module $name
        using ToolipsUDP

        default_handler = handler() do c::UDPConnection
            respond!(c, "hello world!")
        end

        export default_handler, start!
        end
        """)
    end
    return
end

function send(data::String, to::IP4 = "127.0.0.1":2000; from::Int64 = to.port - 5)
    sock = UDPSocket()
    bind(sock, ip"127.0.0.1", from)
    send(sock, parse(IPv4, to.ip), to.port, data)
    close(sock)
end

get_ip(c::UDPConnection) = c.ip.ip::String

get_ip4(c::UDPConnection) = c.ip::IP4

function send(c::UDPConnection, data::String, to::IP4 = "127.0.0.1":2000)
    sock = c.server
    send(sock, parse(IPv4, to.ip), to.port, data)
end


respond!(c::UDPConnection, data::String) = send(c, data, c.ip)


function send(c::Module, data::String, to::IP4 = "127.0.0.1":2000)
    sock = c.server
    send(sock, parse(IPv4, to.ip), to.port, data)
end

mutable struct MultiHandler <: AbstractUDPExtension
    clients::Dict{String, String}
    MultiHandler() = new(Dict{String, String}())
end

function set_handler!(c::UDPConnection, name::String)
    c[:MultiHandler].clients[get_ip(c)] = name
end

function route!(c::UDPConnection, mh::MultiHandler)
    ip = get_ip(c)
    if ip in keys(mh.clients)
        handler_name::String = mh.clients[ip]
        f = findfirst(r -> if typeof(r) == NamedHandler r.name == handler_name else false end, c.handlers)
        c.handlers[f].f(c)
        false
    end
end

export send, UDPConnection, respond!, start!, IP4, write!, handler, UDPExtension, set_handler!, UDP

end # module ToolipsUDP
