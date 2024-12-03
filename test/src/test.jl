module test
using ToolipsUDP
client_served::Bool = false

main_handler = handler() do c::UDPConnection
    packet::String = c.packet
    if packet == "ctest"
        global client_served = true
        return
    elseif packet == "sendback"
        respond!(c, "sent")
    elseif packet == "changehandler"
        set_handler!(c, "other")
    end
end

other_handler = handler("other") do c::UDPConnection
    respond!(c, "other")
    remove_handler!(c)
end
# begin TestClient
module TestClient
using test.ToolipsUDP
expect_other::Bool = false
received_response::Bool = false
got_other::Bool = false

got_first::Bool = false

main_handler = handler() do c::UDPConnection
    if c.packet == "sent"
        global received_response = true
        return
    end
    if expect_other && c.packet == "other"
        global got_other = true
        return
    end
    send(c, "ctest", "127.0.0.1":3005)
    global got_first = true
    return
end

export main_handler
end # module TestClient

module MultiThreadedServer
using ToolipsUDP
count = 0

main = handler() do c::AbstractUDPConnection
    global count += 1
end

export main
end # module MultiThreadedServer

m_hand = ToolipsUDP.MultiHandler(main_handler)

export main_handler, other_handler, m_hand
end # module test
