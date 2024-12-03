using Test
using ToolipsUDP
using test
using test: TestClient
using test: MultiThreadedServer

@info "starting test servers (it will take a second to start additional threads)"
procs = start!(UDP, test, ip = "127.0.0.1":3005)
procs2 = start!(UDP, test.TestClient, ip = "127.0.0.1":3004)
mtserver_procs = start!(UDP, MultiThreadedServer, ip = "127.0.0.1":5004, threads = 1:4)

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
        
        @test typeof(procs) == ToolipsUDP.ParametricProcesses.ProcessManager
        @test length(procs.workers) == 1
        
        @test typeof(procs2) == ToolipsUDP.ParametricProcesses.ProcessManager
        @test length(procs2.workers) == 1
        send("hi", "127.0.0.1":3004)
        sleep(1)
        @test test.client_served == true
        if test.client_served == false
            println("CLIENT NOT SERVED?")
        end
        @test TestClient.got_first
    end
    @testset "server send and receive" begin
        send(TestClient, "sendback", "127.0.0.1":3005)
        sleep(1)
        @test TestClient.received_response
    end
    @testset "multi handler" begin
        TestClient.expect_other = true
        send(TestClient, "changehandler", "127.0.0.1":3005)
        send(TestClient, "other", "127.0.0.1":3005)
        sleep(1)
        @test TestClient.got_other
        test.client_served = false
        send(TestClient, "ctest", "127.0.0.1":3005)
        sleep(1)
        @test test.client_served
    end
    @testset "kill!" begin
        test.client_served = false
        kill!(test)
        send(TestClient, "ctest", "127.0.0.1":3005)
        @test test.client_served == false
        kill!(TestClient)
    end
    @testset "multi-threading" begin
        @test length(mtserver_procs.workers) == 5
        send("hi", "127.0.0.1":5004)
        @test MultiThreadedServer.count == 1
    end
    @info "finishing!"
    kill!(MultiThreadedServer)
end
