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

new_handler = handler() do c::UDPConnection
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

"""
### abstract type AbstractUDPHandler <: AbstractRoute
An `AbstractUDPHandler` is a structure containing a `Function` 
that responds to a UDP request. `ToolipsUDP` provides two types of 
UDP handlers; the `UDPHandler` and the `NamedHandler`. The only consistency 
is having an `AbstractUDPHandler.f` `Function` that takes an 
`AbstractUDPConnection`.
"""
abstract type AbstractUDPHandler <: AbstractRoute end

"""
```julia
UDPHandler <: AbstractUDPHandler
```
- f**::Function*

A UDPHandler is the most basic form of handler for UDP. 
    These handlers are exported from your server and 
    will handle incoming requests from clients. A 
    `UDPHandler` is created by calling the `handler` 
    function without providing any arguments. Providing a 
        `String` will create a `NamedHandler`.

- See also: `handler`, `UDPConnection`, `start!`, `ToolipsUDP`, `respond!`, `send`, `NamedHandler`
```julia
UDPHandler(f::Function)
```
---
```example
module NewUDPServer
using ToolipsUDP

# creating a handler
                               # v make `AbstractUDPConnection` for multi-threading
main_handler = handler() do c::UDPConnection
   user_ip4 = get_ip4(c) # <- IP + port as `IP4`
   user_ip = get_ip(c) # <- just IP as `String`
   user_packet::String = c.packet # <- sent packet
   respond!(c, "thanks for connecting") # <- `respond!` and `send` used to communicate.
end

# exports

export start!, UDP, main_handler
end
#                      vvvvvv make sure to provide `UDP`
using NewUDPServer; start!(UDP, NewUDPServer)
```
"""
struct UDPHandler <: AbstractUDPHandler
    f::Function
end

"""
```julia
NamedHandler <: AbstractUDPHandler
```
- f**::Function*
- name**::String**

A `NamedHandler` is a named version of a `UDPHandler`. This naming allows 
for handlers to be set. We create this by providing a `String` as an 
    argument to the `handler` `Function`. This is primarily intended to be 
used with the `MultiHandler` extension, where we are able to 
set the current handler for a future incoming request.

- See also: `handler`, `UDPConnection`, `start!`, `respond!`, `UDPHandler`, `set_handler!`, `remove_handler!`, `MultiHandler`
```julia
NamedHandler(f::Function, name::String)
```
---
```example
module NewUDPServer
using ToolipsUDP
password = "123"

main_handler = handler() do c::AbstractUDPConnection
    if c.packet == password
        set_handler!(c, "private_message")
        respond!(c, "you are confirmed")
        return
    end
    respond!(c, "you are denied")
end

 #  vvv NamedHandler
private_msg = handler("private_message") do c::AbstractUDPConnection
    respond!(c, "this is my private message")
    set_handler!(c, "sendback")
end

welcome_message = handler("sendback") do c::AbstractUDPConnection
    respond!(c, "ok, you're locked out again.")
    remove_handler!(c)
end

new_handler = MultiHandler()

export start!, UDP, main_handler, new_handler
export private_msg
end
```
"""
struct NamedHandler <: AbstractUDPHandler
    f::Function
    name::String
end

"""
```julia
handler(f::Function, ...) -> ::AbstractUDPHandler
```
The `handler` `Function` creates a `UDPHandler` that handles 
incoming packets and responds to them. If a `Function` is provided, 
we will get a `UDPHandler`. If a `Function` and a `String` are provided, we 
get a `NamedHandler` in return.
```julia
handler(f::Function) -> ::UDPHandler
handler(f::Function, name::String) -> ::NamedHandler
```
---
```example
module SampleServer

sample_handler = handler() do c::UDPConnection
                           # ^ ::AbstractUDPConnection when multi-threading.
    println("handled a client")
end

export sample_handler
end
```
"""
function handler end

handler(f::Function) = UDPHandler(f)

handler(f::Function, name::String) = NamedHandler(f, name)

"""
### abstract type AbstractUDPConnection <: Toolips.AbstractConnection

- See also: 
##### consistencies
- `ip`**::String**
- `port`**::Int64**
- `packet`**::String**
- `data`**::Dict{Symbol, Any}**
"""
abstract type AbstractUDPConnection <: AbstractConnection end

"""
```julia
UDPConnection <: Toolips.AbstractUDPConnection
```
- ip**::String**
- port**::Int64**
- packet**::String**
- data**::Dict{Symbol, Any}**
- server**::Sockets.UDPSocket**
---

##### constructors
- `UDPConnection(data::Dict{Symbol, Any}, server::Sockets.UDPSocket)`
"""
mutable struct UDPConnection <: AbstractUDPConnection
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

"""
```julia
UDPIOConnection <: Toolips.AbstractUDPConnection
```
- ip**::String**
- port**::Int64**
- packet**::String**
- data**::Dict{Symbol, Any}**
- server**::Sockets.UDPSocket**
---

##### constructors
- `UDPConnection(data::Dict{Symbol, Any}, server::Sockets.UDPSocket)`
"""
mutable struct UDPIOConnection <: AbstractUDPConnection
    ip::IP4
    packet::String
    handlers::Vector{AbstractUDPHandler}
    data::Dict{Symbol, Any}
    stream::String
end

write!(c::AbstractUDPConnection, a::Any ...) = throw("`respond!` should be used in place of `write!` for a `UDPHandler`.")

getindex(c::AbstractUDPConnection, data::Symbol) = c.data[data]
setindex!(c::AbstractUDPConnection, a::Any, data::Symbol) = c.data[data] = a
push!(c::AbstractUDPConnection, dat::Any ...) = push!(c.data, dat...)

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
    t = nothing
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
        iocon::UDPIOConnection = UDPIOConnection(con.ip, con.packet, con.handlers, con.data, "")
        add_workers!(pm, router_threads)
        pids::Vector{Int64} = [work.pid for work in filter(w -> typeof(w) != Worker{ParametricProcesses.Async}, pm.workers)]
        Main.eval(Meta.parse("""using ToolipsUDP: @everywhere; @everywhere begin
            using ToolipsUDP
            using $mod
        end"""))
        put!(pm, pids, loaded)
        put!(pm, pids, iocon)
        selected::Int64 = minimum(threads) - 1
        stop = nothing
        job = new_job() do
            try
                stop = [route!(iocon, UDPExtension(ext.parameters[1])) for ext in loaded]
            catch e
                throw(e)
            end
            f = findfirst(x -> x == false, stop)
            if ~(isnothing(f))
                continue
            end
            try
                iocon.handlers[1].f(iocon)
            catch e
                throw(e)
            end
        end
        while server.status > 2
            selected += 1
            con = UDPConnection(data, server, handlers)
            if selected > router_threads
                selected = minimum(threads)
            end
            if selected > 1
                assign!(pm, selected, job)
                waitfor(pm, selected)
                respond!(con, iocon.stream)
                iocon.stream = ""
                continue
            end
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
            println("served a client")
            respond!(c, "hello world!")
        end

        export default_handler, start!, UDP
        # using $name; start!(UDP, name, ip = "127.0.0.1":2000)
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

function send(c::UDPIOConnection, data::String)
    sock = c.server
    c.stream = c.stream * data
end


respond!(c::UDPConnection, data::String) = send(c, data, c.ip)


respond!(c::UDPIOConnection, data::String) = c.stream = c.stream * data

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

remove_handler!(c::UDPConnection, name::String) = delete!(c[:MultiHandler].clients, get_ip(c))

function route!(c::UDPConnection, mh::MultiHandler)
    ip = get_ip(c)
    if ip in keys(mh.clients)
        handler_name::String = mh.clients[ip]
        f = findfirst(r -> if typeof(r) == NamedHandler r.name == handler_name else false end, c.handlers)
        c.handlers[f].f(c)
        false
    end
end

export send, UDPConnection, respond!, start!, IP4, write!, handler, UDPExtension, set_handler!, UDP, AbstractUDPConnection
export remove_handler!
end # module ToolipsUDP
