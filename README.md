<div align="center"><img src="https://github.com/ChifiSource/image_dump/raw/main/toolips/toolipsudp.png"></img></div>

`ToolipsUDP` provides high-level [toolips](https://github.com/ChifiSource/Toolips.jl)-style functionality to UDP networking projects.
- Follows `Toolips` `0.3` conventions.
- Servers are modules.
- Extensible server framework.
```julia
using Pkg; Pkg.add("ToolipsUDP")
```
```julia
# create a new project from template:
using ToolipsUDP; ToolipsUDP.new_app(UDP, "MyApp")
```
```julia
module MyUDPExample

main = handler() do c::AbstractUDPConnection
    if contains(c.packet, "emmy")
         respond!(c, "you are indeed me!")
         return
    end
    respond!(c, "you aren't me... ? How are you on my network? Who are you ?!")
end

# routes and extensions are loaded by exporting them. We will need `start!` and `UDP` to start the server.
export start!, UDP, main
end
```
```julia
# start your server
using MyUDPExample; start!(UDP, MyUDPExample)

# start with threads. Any minimum below `1` will recurring select the main-thread, allowing for more requests to be distributed to the main thread than the accompanying threads.
#                                                                                             (*similar to the router_threads argument from `Toolips`*)
                                      #     serves once on main thread, then 4 times on other threads before returning.
using MyUDPExample; start!(UDP, MyUDPExample, threads = 1:5)
                                                     # serves on the main thread 7 times, -5-1,then serves 7 times on threads before returning to -5.
using MyUDPExample; start!(UDP, MyUDPExample, threads = -5:8)
```
Note that for multi-threading you will want to alias your functions as an `AbstractConnection` -- this also will not work with certain forms of `send`.
```julia
# client
using ToolipsUDP
# send with no response.
send("127.0.0.1":7009, "hello, my name is emmy")
# send with response.
sock = send("127.0.0.1":7009, "hello, my name is emmy", keep_open = true)
close(sock)
```
###### UDP servers
The intention with `ToolipsUDP` is to replicate the typical `Toolips` web-development format in `UDP`. The server system closely mirrors that of `Toolips` itself:
```julia
# hello world in toolips (TCP HTTP Server)
module HelloWorld
using Toolips

home = route("/") do c::Connection
    write!(c, "hello world!")
end

export start!, home
end # module

using HelloWorld: start!(HelloWorld)

# hello world in toolipsUDP (UDP Server)
module HelloUDP
using ToolipsUDP

home = handler() do c::UDPConnection
    respond!(c, "hello world!")
end
end # module


using HelloUDP; start!(UDP, HelloUDP)
# toolips 0.3.4 +:
using HelloUDP; start!(UDP, HelloUDP)
```
**note that we will provide `UDP` to both `start!` and `new_app`**
The `Toolips.Route` is replaced with the `ToolipsUDP.handler`. To write a `handler`, we use the `handler` function as seen above. We can also provide a `String` to this function to make a `NamedHandler`, which is used by some extensions. The `handler`(s) are stored in the `AbstractUDPConnection.handlers` field. There is also the `packet` and an `ip` field. 
```julia
?UDPConnection
```
### abstract type AbstractUDPConnection <: Toolips.AbstractConnection
 
##### consistencies
- `ip`**::String**
- `port`**::Int64**
- `packet`**::String**
- `data`**::Dict{Symbol, Any}**

`ToolipsUDP` is also a bit more simplified; there is no 'default header' to process, and the only data we can receive is the packet itself and the IP of the client, so things are a bit more simplified. 
#### getters
The following functions are used to retrieve data from an `AstractUDPConnection`.
- `Toolips.get_ip(c::UDPConnection)`
- `ToolipsUDP.get_ip4(c::UDPConnection)`

For accessing the data in the incoming packet, we simply utilize the `c.packet` field.
#### responding
We are able to respond, as well as send data, using the `send` and `respond` functions.
- `respond!(c::UDPConnection, data::String)` is the most essential, as it instantly sends `data` back to the client.
- `send(data::String, to::IP4 = "127.0.0.1":2000; from::Int64 = to.port - 5)` For sending a packet through a 'cursor', useful to test an initial response via a temporary server on the port in `from`, but note that it will not get a response as the server is immediately stopped after sending.
- `send(c::UDPConnection, data::String, to::IP4 = "127.0.0.1":2000)` allows us to send data to any server, regardless as to whether or not it has sent to us or not or it is the current client, from a `handler`. A use-case for this would be multi-user chat, for example, where we want to call a `Function` on a certain client and not another. We store the IP of all clients alongside their names, when a client elects to send a user to the name we retrieve the associated IP and send the data.
- `send(c::Module, data::String, to::IP4 = "127.0.0.1":2000)` is similar to sending data from a `handler`, but it allows us to send data from the REPL using the server.
#### extensions

#### multi-threading

