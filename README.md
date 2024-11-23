<div align="center"><img src="https://github.com/ChifiSource/image_dump/raw/main/toolips/toolipsudp.png"></img></div>

### this is ToolipsUDP 0.1, compatible with Toolips 0.2

`ToolipsUDP` provides high-level [toolips](https://github.com/ChifiSource/Toolips.jl)-style functionality to UDP networking projects. This functionality is facilitated via the `UDPServer` and `UDPConnection` types. 

###### creating a UDP server
Whereas a `Toolips` `WebServer` typically comes with a router, the `UDPServer` takes a `Function` directly and provides this function with a `UDPConnection`. To create a UDP server, we provide a connection handler function. Use the UDPServer constructor with a `do` block to specify the behavior when a connection is received. Here's an example:
```julia
using ToolipsUDP

# Define a connection handler function
function my_connection_handler(c::UDPConnection)
    println("Received packet: ", c.packet)
    println("From IP: ", c.ip)
    println("On port: ", c.port)
end

# Create and start a UDPServer with the connection handler using do block
UDPServer("127.0.0.1", 2000) do c::UDPConnection
    my_connection_handler(c)
end
```
A `UDPServer` may also be constructed without a handler `Function`, and this might be ideal for sending data.
###### sending data
ToolipsUDP provides convenient functions for sending data to UDP servers. Packets may be sent from
- A `UDPServer`
- A `UDPConnection`
- or just sent once with a quick socket binding.

The dispatches for these are:
- `send(c::UDPServer, data::String, to::String = "127.0.0.1", port::Int64 = 2000)`
- `send(c::UDPConnection, data::String, to::String = "127.0.0.1", port::Int64 = 2000)`
- and `send(data::String, to::String = "127.0.0.1", port::Int64 = 2000; from::Int64 = port - 5)` respectively.


###### extending server functionality
Like toolips, `ToolipsUDP` provides an extensible server infastructure which allows for the addition of new, reproducible features to a server. In `ToolipsUDP`, these extensions are facilitated using multiple dispatch, the `UDPExtension` type, and the functions `serve` and `onstart`. To add an extension, first import one of these functions. For this example, we will import *both*.
```julia
import ToolipsUDP: serve, onstart
```
The `serve` function is called on our `UDPConnection` each time we recieve an incoming packet. The `onstart` function is called on our `Connection` data on start.
```julia
using ToolipsUDP
import ToolipsUDP: serve, onstart

onstart(data::Dict{Symbol, Any}, ue::UDPExtension{:loaddata}) = push!(data, :mydata => "hello world!")

serve(c::UDPConnection, ue::UDPExtension{:printdata}) = println(c[:mydata])
```
