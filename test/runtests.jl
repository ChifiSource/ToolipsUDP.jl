using Test
using ToolipsUDP
using test
@testset "ToolipsUDP tests" verbose = true begin
    @testset "handlers" begin
        basic_handler = handler(c -> respond!(c, "hi"))
        @test typeof(basic_handler) == ToolipsUDP.UDPHandler
        named_handler = handler("sample") do c
        end
        @test typeof(named_handler) == ToolipsUDP.NamedHandler
        @test named_handler.name == "sample"
    end
    @testset "start!" begin
        procs = start!(test, ip = "127.0.0.1":3005)
        @test typeof(procs) == ToolipsUDP.ParametricProcesses.ProcessManager
        @test length(procs.workers) == 1
        procs2 = start!(test.TestClient, ip = "127.0.0.1":3004)
        @test typeof(procs2) == ToolipsUDP.ParametricProcesses.ProcessManager
        @test length(procs2.workers) == 1
        send("hi", "127.0.0.1":3004)
        sleep(1)
        @test test.client_served
        @test TestClient.got_first
    end
    @testset "server send and receive" begin
        send(TestClient, "sendback", "127.0.0.1":3005)
        sleep(1)
        @test TestClient.received_response
        
    end
    @testset "extensions" begin
        
    end
    @testset "multi handler" begin

    end
    @testset "multi-threading" begin

    end
end
