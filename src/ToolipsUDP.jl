module ToolipsUDP
using Toolips.Sockets
using Toolips.Pkg: activate, add
import Toolips.Sockets: send
import Toolips: ServerExtension, ToolipsServer, AbstractConnection, getip, write!, new_app
import Base: show, read

mutable struct UDPConnection <: AbstractConnection
    ip::String
    port::Int64
    data::String
    client::Dict{Symbol, String}
    server::Sockets.UDPSocket
    function UDPConnection(client::Dict{Symbol, Any}, server::Sockets.UDPSocket)
        ip, rawdata = recvfrom(server)
        data = String(rawdata)
        port = Int64(ip.port)
        ip = string(ip.host)
        new(ip, port, data, client, server)::UDPConnection
    end
end

mutable struct UDPExtension{T <: Any} <: ServerExtension
    type::Symbol
    UDPExtension(T::Symbol) = new{T}(:connection)
end

mutable struct UDPServer <: ToolipsServer
    host::String
    port::Int64
    server::Sockets.UDPSocket
    start::Function
    function UDPServer(f::Function, host::String = "127.0.0.1", port::Integer = 2000)
        server = UDPSocket()
        start() = begin
            ms = methods(serve)
            exlist = [m.sig.parameters[3] for m in ms]
            data::Dict{Symbol, Any} = Dict{Symbol, Any}()
            bind(server, parse(IPv4, host), port)
            Threads.@spawn while server.status == 3
                con::UDPConnection = UDPConnection(data, server)
                for ext in exlist
                    if ext != UDPExtension{<:Any}
                        serve(con, UDPExtension(ext.parameters[1]))
                    end
                end
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
                println(c.data)
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

function serve(c::UDPConnection, ext::UDPExtension{<:Any})

end

function start(c::UDPConnection, ext::UDPExtension{<:Any})


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

function send(data::String, to::String = "127.0.0.1", port::Int64 = 2000; from::Int64 = port - 5)
    sock = UDPSocket()
    bind(sock, ip"127.0.0.1", from)
    send(sock, parse(IPv4, to), port, data)
    close(sock)
    sock
end

function send(c::UDPConnection, data::String, to::String = "127.0.0.1", port::Int64 = 2000)
    sock = c.server
    send(sock, parse(IPv4, to), port, data)
end

function send(c::UDPServer, data::String, to::String = "127.0.0.1", port::Int64 = 2000)
    sock = c.server
    send(sock, parse(IPv4, to), port, data)
end

export send, UDPServer, UDPConnection

end # module ToolipsUDP
