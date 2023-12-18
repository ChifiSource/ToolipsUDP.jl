module ToolipsUDP
using Toolips
using Toolips.Sockets
import Toolips.Sockets: send
using Toolips: ServerExtension, ToolipsServer, AbstractConnection
import Base: show, read

mutable struct UDPConnection <: AbstractConnection
    data::String
    server::Sockets.UDPSocket
end

mutable struct UDPExtension{T <: Any} <: ServerExtension
    type::Symbol
    UDPExtension(T::String) = new{Symbol(T)}(:connection)
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
                data::String = String(recv(server))
                con = UDPConnection(data, server)
                if contains(con.data, "?CM:")

                else
                    f(con)
                end
            end
        end
        new(host, port, server, start)
    end
end


function route(c::UDPConnection, ext::UDPExtension{<:Any})

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


end # module ToolipsUDP
