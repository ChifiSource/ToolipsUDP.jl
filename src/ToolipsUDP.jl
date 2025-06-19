"""
Created in June, 2022 by
[chifi - an open source software dynasty.](https://github.com/orgs/ChifiSource)
by team
### ToolipsUDP
`ToolipsUDP` brings `Toolips` web-development conventions to the format of UDP. This package allows for 
the creation of extensible and versatile UDP servers for Julia.
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
##### provides
- `UDP` (`ServerTemplate{:UDP}`)
- `AbstractHandler`
- `Handler`
- `NamedHandler`
- `handler`
- `AbstractUDPConnection`
- `UDPConnection`
- `UDPIOConnection`
- `SocketServerExtension`
- `UDPExtension{T <: Any}`
- `Toolips.route!(c::UDPConnection, ext::SocketServerExtension)`
- `Toolips.on_start(data::Dict{Symbol, Any}, ext::SocketServerExtension)`
- `Toolips.start!(st::Type{ServerTemplate{:UDP}}, mod::Module; ip::IP4 = "127.0.0.1":2000, threads::UnitRange{Int64} = 1:1, async::Bool = true)`
- `Toolips.new_app(st::Type{ServerTemplate{:UDP}}, name::String)`
- `Toolips.get_ip(c::UDPConnection)`
- `get_ip4`
- `send`
- `respond!`
- `MultiHandler`
- `set_handler!`
- `remove_handler!`
- `Toolips.route!(c::UDPConnection, mh::MultiHandler)`
"""
module ToolipsUDP
using Toolips
using Toolips.Sockets
import Toolips: IP4, AbstractConnection, get_ip, write!, ip4_cli, ProcessManager, assign!, AbstractIOConnection, Crayon, kill!, get_ip4, handler
using Toolips: SocketServerExtension
import Toolips: route!, on_start, AbstractExtension, AbstractRoute, respond!, start!, ServerTemplate, new_app, @everywhere, AbstractHandler
using Toolips.ParametricProcesses
using Toolips.Pkg: activate, add, generate
import Toolips.Sockets: send, bind
import Base: show, read, getindex, setindex!, push!

const UDP = ServerTemplate{:UDP}

"""
### abstract type AbstractUDPConnection <: Toolips.AbstractConnection
The `AbstractUDPConnection` fills the same role as the `Toolips.AbstractConnection` -- 
being a mutable type that is passed into a response handler. The `Connection` is then 
used alongside `respond!`, `send`, and its `packet` field to create and send data to handle the 
response.
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
UDPConnection <: AbstractUDPConnection
```
- ip**::String**
- port**::Int64**
- packet**::String**
- data**::Dict{Symbol, Any}**
- server**::Sockets.UDPSocket**
---
The `UDPConnection` is passed into your `Handler`'s function. This is essentially the in and out stream 
in `ToolipsUDP`. We respond using `send` and `respond!` and we get the incoming packet by calling the 
`c.packet` field.
##### constructors
- `UDPConnection(data::Dict{Symbol, Any}, server::Sockets.UDPSocket)`
"""
mutable struct UDPConnection <: Toolips.AbstractSocketConnection
    ip::IP4
    packet::String
    handlers::Vector{AbstractHandler}
    data::Dict{Symbol, Any}
    server::Sockets.UDPSocket
    function UDPConnection(data::Dict{Symbol, Any}, server::Sockets.UDPSocket, handlers::Vector{AbstractHandler})
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
- stream**::String**
---
The `UDPIOConnection` is passed into your `Handler`'s function in much the same way the `UDPConnection` is. 
This is specifically, like the `IOConnection`, created for the context of multi-threading -- as the server's 
streams cannot be written to by any other thread than the base. 
##### constructors
- `UDPConnection(data::Dict{Symbol, Any}, server::Sockets.UDPSocket)`
"""
mutable struct UDPIOConnection <: AbstractUDPConnection
    ip::IP4
    packet::String
    handlers::Vector{AbstractHandler}
    data::Dict{Symbol, Any}
    stream::String
end

write!(c::AbstractUDPConnection, a::Any ...) = throw("`respond!` should be used in place of `write!` for a `Handler`.")

getindex(c::AbstractUDPConnection, data::Symbol) = c.data[data]
setindex!(c::AbstractUDPConnection, a::Any, data::Symbol) = c.data[data] = a
push!(c::AbstractUDPConnection, dat::Any ...) = push!(c.data, dat...)

"""
```julia
UDPExtension{T <: Any} <: Toolips.SocketServerExtension
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
- See also: `handler`, `UDPConnection`, `on_start`, `route!`, `SocketServerExtension`
```julia
UDPExtension{T <: Any}()
```
"""
struct UDPExtension{T <: Any} <: Toolips.SocketServerExtension

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
    mod.eval(Meta.parse("data = nothing; server = nothing"))
    data::Dict{Symbol, Any} = Dict{Symbol, Any}()
    # server
    server = UDPSocket()
    bind(server, parse(IPv4, ip.ip), ip.port)
    mod.data = data
    mod.server = server
    router_threads = maximum(threads)
    server_ns::Vector{Symbol} = names(mod)
    loaded = []
    handlers = Vector{Toolips.AbstractHandler}()
    for name in server_ns
        f = getfield(mod, name)
        T = typeof(f)
        if T <: Toolips.SocketServerExtension
            push!(loaded, f)
        elseif T <: Toolips.AbstractHandler
            push!(handlers, f)
        end
        T = nothing
    end
    for ext in loaded
        on_start(data, ext)
        T = string(typeof(ext))
        if contains(T, ".")
            splits = split(T, ".")
            T = string(splits[length(splits)])
        end
        push!(data, Symbol(T) => ext)
    end
    allparams = (m.sig.parameters[3] for m in methods(route!, Any[AbstractUDPConnection, SocketServerExtension]))
    filter!(ext -> typeof(ext) in allparams, loaded)
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
        iocon::UDPIOConnection = UDPIOConnection("":0, "", Vector{AbstractHandler}(), data, "")
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
module HelloWorld
using ToolipsUDP

main_handler = handler() do c::UDPConnection
    println("new client sent us... " * c.packet)
end

export main_handler, UDP, start!
end

start!(UDP, HelloWorld, ip = "127.0.0.1":3001)

using ToolipsUDP; send("hello friend", "127.0.0.1":3001)

# output: new client sent us... hello friend
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
data we want to send inside of a `Handler`. To respond to the current client, we could provide 
the `c.ip` as `to`, but we could also use `respond!` to simplify the process.
Note that this can only happen from the base thread, as well. In the future, we might have 
a way to translate this data but this is not currently supported. Please try to understand that 
every addition to multi-threading data-wise is not only a head-ache, but also stressful for 
others who might not use it -- as we are replicating it on multiple threads.
```julia
module UserTracker
using ToolipsUDP

users = Dict{IP4, String}()

main_handler = handler() do c::UDPConnection
    if contains(c.packet, " ") || c.packet == ""
        respond!(c, "please provide a name to name yourself")
        return
    end
    push!(users, get_ip4(c) => c.packet)
    # everyone gets a join message.
    [send(c, "\$(c.packet) joined", user_ip) for user_ip in keys(users)]
end

export main_handler, UDP, start!
end
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
Sends a packet of data to `to` using an actively running server `Module`. This allows us to send data 
from outside of the server.
```julia
module HelloWorld
using ToolipsUDP

main_handler = handler() do c::UDPConnection
    respond!(c, "hello server")
end

export main_handler, UDP, start!
end

start!(UDP, HelloWorld)

using ToolipsUDP; send(HelloWorld, "hello to another server", "127.0.0.1":8000)
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
module HelloWorld
using ToolipsUDP


main_handler = handler() do c::UDPConnection
    respond!(c, "hello world!")
end

export main_handler
end

# a multi-handler can also be passed a `Function` to automatically make the main handler.
multi_handler = MultiHandler() do c::AbstractUDPConnection

end
```
"""
respond!(c::UDPConnection, data::String) = send(c, data, c.ip)

respond!(c::UDPIOConnection, data::String) = c.stream = c.stream * data

export send, UDPConnection, respond!, start!, IP4, write!, handler, UDPExtension, set_handler!, UDP, AbstractUDPConnection
export remove_handler!, get_ip4, get_ip, kill!
end # module ToolipsUDP
