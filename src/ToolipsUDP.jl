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

export new_handler, start!, UDP
end

using NewServer; start!(UDP, NewServer)
```
The API provides the obvious `get_ip` binding, as well as `send` and `respond!` for convenient 
peer-to-server communication.
"""
module ToolipsUDP
using Toolips.Sockets
import Toolips: IP4, AbstractConnection, get_ip, write!, ip4_cli, ProcessManager, assign!, AbstractIOConnection, Crayon, kill!
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
The `AbstractUDPConnection` fills the same role as the `Toolips.AbstractConnection` -- 
being a mutable type that is passed into a response handler.
- See also: `UDPConnection`, `UDPIOConnection`, `start!`
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
    server functionality. The `Function`is meant to be extended in order to change the functionality of 
    a handler on each " route" of a client.
```julia
# the route! dispatch for `MultiHandler`:
function route!(c::UDPConnection, mh::MultiHandler)
    ip = get_ip(c)
    if ip in keys(mh.clients)
        handler_name::String = mh.clients[ip]
        f = findfirst(r -> if typeof(r) == NamedHandler r.name == handler_name else false end, c.handlers)
        c.handlers[f].f(c)
        false
    end
end
```
"""
function route!(c::UDPConnection, ext::AbstractUDPExtension)

end

"""
```julia
on_start(data::Dict{Symbol, Any}, ext::AbstractUDPExtension)
```
This dispatch fills the same role `on_start` normally fills in base `Toolips`, 
just for `UDPExtensions`. Like in `Toolips`, this function can be extended to add 
    server functionality. The new `Function` will dictate what happens when a `UDP` server 
    starts with a certain extension.
```julia
import ToolipsUDP: on_start
mutable struct MyExtension
    name_pwd::Pair{Int64, String}
end

function on_start(data::Dict{Symbol, Any}, ext::AbstractUDPExtension)
    push!(data, :name => ext.name_pwd[1], :pwd => ext.name_pwd[2])
end
```
"""
function on_start(data::Dict{Symbol, Any}, ext::AbstractUDPExtension)
    
end

"""
```julia
start!(st::Type{ServerTemplate{:UDP}}, mod::Module; ip::IP4 = "127.0.0.1":2000, threads::UnitRange{Int64} = 1:1, 
    async::Bool = true)
```
Starts a Server Module as a `ToolipsUDPServer`. `UDP` is provided as a constant from `ToolipsUDP` and is provided to start 
the server as a UDPServer. If you were to call `start!` without this argument, you'd be trying to start a `Toolips` 
web-server -- this will result in a server with only a `default_404` route. `threads` determines how many threads to 
serve the `handler`(s) with.
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
**NOTE** that with multi-threading, you will want to annotate your handler's `Connection` as an 
`AbstractUDPConnection`, in order to facilitate the `IOConnection` that can actually be sent across threads.
"""
function start!(st::Type{ServerTemplate{:UDP}}, mod::Module; ip::IP4 = "127.0.0.1":2000, threads::UnitRange{Int64} = 1:1, 
    async::Bool = true)
    data::Dict{Symbol, Any} = Dict{Symbol, Any}()
    # server
    server = UDPSocket()
    bind(server, parse(IPv4, ip.ip), ip.port)
    mod.data = data
    mod.server = server
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
    allparams = (m.sig.parameters[3] for m in methods(route!, Any[AbstractUDPConnection, AbstractUDPExtension]))
    filter!(ext -> typeof(ext) in allparams, loaded)
 #   con::UDPConnection = UDPConnection(data, server, handlers)
    pm::ProcessManager = ProcessManager()
    push!(data, :procs => pm)
    GARBAGE = 0
    t = nothing
    if router_threads < 2 && async
        t = @async while server.status > 2
            GARBAGE += 1
            if GARBAGE > 150
                GC.gc()
            elseif GARBAGE > 500
                GC.gc(true)
                GARBAGE = 0
            end
            con = UDPConnection(data, server, handlers)
            stop = [route!(con, ext) for ext in loaded]
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
    elseif ~(async)
        t = while server.status > 2
            con = UDPConnection(data, server, handlers)
            stop = [route!(con, ext) for ext in loaded]
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
        iocon::UDPIOConnection = UDPIOConnection("":0, "", Vector{UDPHandler}(), data, "")
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
                return
            end
            try
                iocon.handlers[1].f(iocon)
            catch e
                throw(e)
            end
        end
        @async while server.status > 2
            GARBAGE += 1
            if GARBAGE > 150
                GC.gc()
            elseif GARBAGE > 500
                GC.gc(true)
                GARBAGE = 0
            end
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

"""
```julia
new_app(st::Type{ServerTemplate{:UDP}}, name::String) -> ::Nothing
```
This method creates a new `UDP` app.
```julia
using ToolipsUDP
ToolipsUDP.new_app(UDP, "SampleApp")

# Toolips 0.3.4+ we can provide symbols instead:
using Toolips; using ToolipsUDP
Toolips.new_app(:UDP, "SampleApp")
```
"""
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

get_ip(c::UDPConnection) = c.ip.ip::String

"""
```julia
get_ip4(c::UDPConnection) -> ::Toolips.IP4
```
A `get_ip` equivalent for the `Toolips.IP4` data-type, which holds both the 
    port and the IP address. This is provided exclusively by `ToolipsUDP` because the port 
with a `Toolips` HTTP server in production will always be 80 unless an absurdly specific case.
```julia

```
"""
get_ip4(c::UDPConnection) = c.ip::IP4

"""
```julia
ToolipsUDP.send -> ::Nothing/::Sockets.UDPSocket
```
`send` is used to send data from and to a variety of sources using a variety of arguments.
"""
function send end

"""
```julia
send(data::String, to::IP4 = "127.0.0.1":2000; from::Int64 = to.port - 5, keep_open::Bool = false) -> ::Nothing/::Sockets.UDPSocket
```
Sends `data` to the `IP4` `to` from the port `from` on the current computer. In this case, we will 
quickly create a client server, send the packet, and then cancel the server. Note that that after sending 
this server will not receive responses, as it is closed. This changes with the `keep_open` argument.
```julia

```
"""
function send(data::String, to::IP4 = "127.0.0.1":2000; from::Int64 = to.port - 5, keep_open::Bool = false)
    sock = UDPSocket()
    bind(sock, ip"127.0.0.1", from)
    send(sock, parse(IPv4, to.ip), to.port, data)
    if keep_open
        return(sock)
    end
    close(sock)
end


"""
```julia
send(c::UDPConnection, data::String, to::IP4 = "127.0.0.1":2000) -> ::Nothing
```
Sends `data` from a `UDPConnection` to any other endpoint. This is useful for 
data we want to send inside of a `UDPHandler`. To respond to the current client, we could provide 
the `c.ip` as `to`, but we could also use `respond!` to simplify the process.
Note that this can only happen from the base thread, as well. In the future, we might have 
a way to translate this data but this is not currently supported. Please try to understand that 
every addition to multi-threading data-wise is not only a head-ache, but also stressful for 
others who might not use it -- as we are replicating it on multiple threads.
```julia

```
"""
function send(c::UDPConnection, data::String, to::IP4 = "127.0.0.1":2000)
    sock = c.server
    send(sock, parse(IPv4, to.ip), to.port, data)
end

"""
```julia
send(c::Module, data::String, to::IP4 = "127.0.0.1":2000) -> ::Nothing
```
Sends a packet of data to `to` using an actively running server `Module`.
```julia

```
"""
function send(c::Module, data::String, to::IP4 = "127.0.0.1":2000)
    sock = c.server
    send(sock, parse(IPv4, to.ip), to.port, data)
end

"""
```julia
respond!(c::AbstractUDPConnection, data::String) -> ::Nothing
```
The quintessential way to return data to a client; `respond!` takes the place of 
`write!` in conventional `Toolips`, allowing us to write data directly onto an incoming 
packet.
```julia

```
"""
respond!(c::UDPConnection, data::String) = send(c, data, c.ip)

respond!(c::UDPIOConnection, data::String) = c.stream = c.stream * data

"""
```julia
MultiHandler <: AbstractUDPExtension
```
- `main_handler`**::UDPHandler**
- `clients`**::Dict{IP4, String}**

The `MultiHandler` is a type created to route a client to multiple 
named handlers using `set_handler!`. We provide our `MultiHandler` 
with a main handler. This main handler acts as the first response, 
subsequent responses can then be done through `NamedHandler`s.

- See also: `set_handler!`, `NamedHandler`, `remove_handler!`
```julia
MultiHandler(hand::UDPHandler)
MultiHandler(f::Function)
```
```example
module NewServer
using ToolipsUDP

end
```
"""
mutable struct MultiHandler <: AbstractUDPExtension
    main_handler::UDPHandler
    clients::Dict{IP4, String}
    MultiHandler(hand::UDPHandler) = new(hand, Dict{IP4, String}())
    MultiHandler(f::Function) = new(UDPHandler(f), Dict{IP4, String}())
end

"""
```julia
set_handler!(c::UDPConnection, args ...) -> ::Nothing
```
Sets a `NamedHandler` for a `MultiHandler` for the client 
    currently being served by `c`.
```julia
# for current client
set_handler!(c::UDPConnection, name::String)
# for other clients
set_handler!(c::UDPConnection, ip4::IP4, name::String)
```
```example

```
"""
function set_handler!(c::UDPConnection, name::String)
    c[:MultiHandler].clients[get_ip4(c)] = name
end

function set_handler!(c::UDPConnection, ip4::IP4, name::String)
    c[:MultiHandler].clients[ip4] = name
end

"""
```julia
remove_handler!(c::UDPConnection) -> ::Nothing
```
Removes a currently selected `NamedHandler`, returning the client 
to the `main_handler` provided to the `MultiHandler`.
```julia
# for current client
set_handler!(c::UDPConnection, name::String)
# for other clients
set_handler!(c::UDPConnection, ip4::IP4, name::String)
```
```example

```
"""
remove_handler!(c::UDPConnection) = delete!(c[:MultiHandler].clients, get_ip4(c))

function route!(c::UDPConnection, mh::MultiHandler)
    ip = get_ip4(c)
    if ip in keys(mh.clients)
        handler_name::String = mh.clients[ip]
        f = findfirst(r -> typeof(r) == NamedHandler && r.name == handler_name, c.handlers)
        c.handlers[f].f(c)
        return(false)::Bool
    else
        mh.main_handler.f(c)
        return(false)
    end
end


export send, UDPConnection, respond!, start!, IP4, write!, handler, UDPExtension, set_handler!, UDP, AbstractUDPConnection
export remove_handler!, get_ip4, get_ip, kill!
end # module ToolipsUDP
