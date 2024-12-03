<div align="center"><img src="https://github.com/ChifiSource/image_dump/raw/main/toolips/toolipsudp.png"></img></div>

`ToolipsUDP` provides high-level [toolips](https://github.com/ChifiSource/Toolips.jl)-style functionality to UDP networking projects.
- Follows `Toolips` `0.3` conventions.
- Servers are modules.
- Extensible server framework.
- Streamlined UDP API.
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
###### map
- [get started](#get-started)
- [getters](#getters)
- [responding](#responding)
- [extensions](#extensions)
- [multi-threading](#multi-threading)
###### get started
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
 The `AbstractUDPConnection` fills the same role as the `Toolips.AbstractConnection` -- 
being a mutable type that is passed into a response handler.
- See also: `UDPConnection`, `UDPIOConnection`, `start!`
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
UDP extensions are handled nearly identically to regular `Toolips` extensions. First, we create a new type that is a `<:` of `AbstractUDPExtension`.
```julia
pages = Dict("page1" => "once upon a time", "page2" => "there was a person")

mutable struct MySampleExtension <: ToolipsUDP.UDPExtension
     client_page::Dict{IP4,  String}
     config_path::String
    MySampleExtension(uri::String) = new(Dict{IP4, String}(), uri)::MySampleExtension
end
```
Next, this extension may be bound to `route!` and `on_start`:
```julia
import ToolipsUDP: on_start, route!

function on_start(data::Dict{Symbol, Any}, ext::MySampleExtension)
    raw_config = read(ext.config_path, String)
    for client in split(raw_config, ";")
        value_splits = split(client, "|")
        ip4_splits = split(ip4_str[1], ":")
        ip4 = string(ip4_splits[1]):parse(Int64, ip4_splits[2])
        push!(ext.client_page, ip4 => string(value_splits[2]))
   end
end
# use `false` to stop routing
function route!(c::UDPConnection, ext::MySampleExtension)
    if get_ip4(c) in keys(ext.client_page)
       respond!(c, "you're loaded on page " * ext.client_page[get_ip4(c)])
       return(false)
    end
end
```
#### multi-threading
Multi-threading is done by simply adding a **range** of threads to utilize. In this range, `1` represents your base thread -- anything about `1` will be served on an additional thread. Anything below `1` provided as the `minimum` will perform an extra response on the base thread. In other words, `0:3` would serve twice on the base thread, `0` and `1`, before serving `2` and `3` on workers and returning to `0` and the base thread. Note that both a `UDPIOConnection` and a `UDPConnection` will be sent through a multi-threaded server's handlers, so this must be annotated as an `AbstractUDPConnection`.
```julia
module MultiThreadedServer
using ToolipsUDP
count = 0

main = handler() do c::AbstractUDPConnection
    global count += 1
end

export main, UDP, start!
end # module MultiThreadedServer

using MultiThreadedServer
start!(UDP, MultiThreadedServer, threads = -1:5)
```
The `ProcessManager` is also, like `Toolips`, the return of `start!`. Considering this, we could feasibly add workers and distribute our tasks -- though `threads` and `router_threads` aren't *both* available as they are in `Toolips`. 
While this aspect of multi-threading is relatively straightforward, not all servers will be compatible with this form of multi-threading. For starters, your handlers will need to be annotated as `AbstractUDPConnection`, rather than a regular `UDPConnection` -- as a different `Connection` type is used when not on the base thread.

Downsides to multi-threading with `ToolipsUDP`:
- You cannot use `send` -- in the future, there might be a place to store sent data inside of a `UDPIOConnection`, for now this is not a reality and the `UDPIOConnection` is relegated exclusively to `respond!` for sending data. In other words, we can send data back to the client but not really anywhere else.
- A multi-threaded project **MUST BE** an established project with its own environment, modules created under `Main` or in the REPL will not be able to load on additional threads.
- Inevitably, loading your server across several threads leads to a higher memory cost. The `threads` argument allows you to balance the performance of the threads with the loss in performance that occurs from translating data into each thread.
- Every `Handler` function argument must be annotated as an `AbstractUDPConnection`, or have no annotation at all.
### contributing
You can help out with this project by...
- using `ToolipsUDP` in your own project 🌷
- creating extensions for the toolips ecosystem 💐
- forking this project [contributing guidelines](#guidelines)
- submitting issues
- contributing to other [chifi](https://github.com/ChifiSource) projects
- supporting chifi creators

I thank you for all of your help with our project, or just for considering contributing! I want to stress further that we are not picky -- allowing us all to express ourselves in different ways is part of the key methodology behind the entire [chifi](https://github.com/ChifiSource) ecosystem. Feel free to contribute, we would **love** to see your art! Issues marked with `good first issue` might be a great place to start!
#### guidelines
We are not super strict, but making sure of these few things will be helpful for maintainers!
1. You have replicated the issue on **Unstable**
2. The issue does not currently exist... or does not have a planned implementation different to your own. In these cases, please collaborate on the issue, express your idea and we will select the best choice.
3. **Pull Request TO UNSTABLE**
4. Be **specific** about your issue -- if you are experiencing multiple issues, open multiple issues. It is better to have a high quantity of issues that specifically describe things than a low quantity of issues that describe multiple things.
5. If you have a new issue, **open a new issue**. It is not best to comment your issue under an unrelated issue; even a case where you are experiencing that issue, if you want to mention **another issue**, open a **new issue**.
6. Questions are fine, but preferably **not** questions answered inside of this `README`.


