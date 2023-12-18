module ToolipsUDP
using Toolips
using Toolips.Sockets
import Toolips.Sockets: send, write!
using Toolips: ServerExtension, ToolipsServer, AbstractConnection
import Base: show, read

mutable struct UDPConnection <: AbstractConnection
    data::String
end

mutable struct UDPServer <: ToolipsServer
    host::String
    port::Int64
    server::Sockets.UDPSocket
    start::Function
    function UDPServer(f::Function, host::String = "127.0.0.1", port::Integer = 2000)
        server = UDPSocket()
        start() = begin
            bind(server, parse(IPv4, host), port)
            @async while server.status == 3
                con = UDPConnection(String(recv(server)))
                f(con)
            end
        end
        new(host, port, server, start)
    end
end

function show(io::IO, ts::UDPServer)
    status::String = string(ts.server.status)
    active::String = "inactive"
    if status == "3" || "4"
        active = active
    end
    print("""$(typeof(ts))
        UDP server: $(ts.host):$(ts.port)
        status: $status $active
        """)
end

function send(to::String = "127.0.0.1", port::Int64 = 2000, data::String; from::Int64 = port - 5)
    sock = UDPSocket()
    bind(sock, ip"127.0.0.1", from)
    send(sock, parse(IPv4, to), port, data)
    sock
end

function send(c::UDPConnection, port::Int64 = 2000, data::String)
    sock = UDPSocket()
    bind(sock, ip"127.0.0.1", from)
    send(sock, parse(IPv4, from), port, data)
end

end # module ToolipsUDP
