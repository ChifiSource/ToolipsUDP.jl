module ToolipsUDP
using Toolips.Sockets
import Toolips.Sockets: send
import Toolips: ServerExtension, ToolipsServer, AbstractConnection, getip
import Base: show, read

mutable struct UDPConnection <: AbstractConnection
    data::String
    client::Dict{Symbol, String}
    server::Sockets.UDPSocket
    function UDPConnection(client::Dict{Symbol, Any}, server::Sockets.UDPSocket)
        new(String(recv(server)), client, server)::UDPConnection
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
        ms = methods(serve)
        exlist = [m.sig.parameters[3] for m in ms]
        data::Dict{Symbol, Any} = Dict{Symbol, Any}()
        start() = begin
            bind(server, parse(IPv4, host), port)
            @async while server.status == 3
                con::UDPConnection = UDPConnection(data, server)
                for ext in exlist
                    if ext != UDPExtension{<:Any}
                        serve(con, UDPExtension(ext.parameters[1]))
                    end
                end
                f(con)
            end
        end
        new(host, port, server, start)
    end
end

function serve(c::UDPConnection, ext::UDPExtension{<:Any})

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
