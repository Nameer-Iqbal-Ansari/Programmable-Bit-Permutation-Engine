`timescale 1ns/1ps
///////////////////////////////////////////////////////////////////////////////////////////
//
// Designer: Nameer Iqbal Ansari
// 
// Create Date: 06/06/2026
// Design Name: Bit permuter testbench
// Module Name: bit_permuter_tb
// Tool Versions: Vivado 2018.2
// 
/////////////////////////////////////////////////////////////////////////////////////////////
module tb;

localparam int N               = 1024;
localparam int CFG_WIDTH       = 64;
localparam int NUM_IDC_PER_CFG = 6;
localparam int IDX_W           = $clog2(N);
localparam int CFG_DEPTH       = N/NUM_IDC_PER_CFG + ((N%NUM_IDC_PER_CFG)!=0);

////////////////////////////////////////////////////////////
// CLOCK : 300 MHz
////////////////////////////////////////////////////////////

logic clk;

initial clk = 0;
always #1.6665 clk = ~clk; // 300MHz

////////////////////////////////////////////////////////////
// DUT I/O
////////////////////////////////////////////////////////////

logic rst_n_i;

logic [CFG_WIDTH-1:0] cfg_data_i;
logic                 cfg_valid_i;
logic                 cfg_ready_o;

logic [N-1:0] data_in_i;
logic         data_in_valid_i;

logic [N-1:0] data_out_o;
logic         data_out_valid_o;

////////////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////////////

bit_permuter #(
    .N(N),
    .CFG_WIDTH(CFG_WIDTH),
    .NUM_IDC_PER_CFG(NUM_IDC_PER_CFG)
)
dut (
    .clk_i(clk),
    .rst_n_i(rst_n_i),

    .cfg_data_i(cfg_data_i),
    .cfg_valid_i(cfg_valid_i),
    .cfg_ready_o(cfg_ready_o),

    .data_in_i(data_in_i),
    .data_in_valid_i(data_in_valid_i),

    .data_out_o(data_out_o),
    .data_out_valid_o(data_out_valid_o)
);

////////////////////////////////////////////////////////////
// GLOBALS
////////////////////////////////////////////////////////////

int perm [0:N-1];

logic [N-1:0] expected;
logic [N-1:0] din;

integer cycle_cnt;
integer start_cycle;
integer end_cycle;
integer latency;

always @(posedge clk)
    cycle_cnt++;

////////////////////////////////////////////////////////////
// GOLDEN MODEL
////////////////////////////////////////////////////////////

function automatic logic [N-1:0]
golden_perm
(
    input logic [N-1:0] din_f,
    input int perm_f [0:N-1]
);

    logic [N-1:0] tmp;

    begin
        for(int i=0;i<N;i++)
            tmp[i] = din_f[perm_f[i]];

        return tmp;
    end

endfunction

////////////////////////////////////////////////////////////
// TASKS
////////////////////////////////////////////////////////////

task automatic send_cfg_word
(
    input logic [63:0] cfg_word
);
begin

    @(posedge clk);

    cfg_data_i  <= cfg_word;
    cfg_valid_i <= 1'b1;

    @(posedge clk);

    cfg_valid_i <= 1'b0;
    cfg_data_i  <= '0;

end
endtask

////////////////////////////////////////////////////////////

task automatic load_permutation
(
    input int perm_local [0:N-1]
);

    logic [63:0] cfg_word;
    int idx;

begin

    idx = 0;

    for(int w=0; w<CFG_DEPTH; w++) begin

        cfg_word = '0;

        for(int k=0;k<6;k++) begin

            if(idx < N)
                cfg_word[k*10 +: 10] = perm_local[idx];
            else
                cfg_word[k*10 +: 10] = 0;

            idx++;
        end

        send_cfg_word(cfg_word);

    end

end
endtask

////////////////////////////////////////////////////////////
task automatic wait_input_gap; // data_in_valid_i after 1us
begin
    repeat(300) @(posedge clk);
end
endtask
task automatic send_input
(
    input logic [N-1:0] data
);

begin

    @(posedge clk);

    data_in_i       <= data;
    data_in_valid_i <= 1'b1;
    @(posedge clk);

    data_in_valid_i <= 1'b0;
    data_in_i       <= '0;

end
endtask

////////////////////////////////////////////////////////////

task automatic wait_and_check;

begin
    start_cycle = cycle_cnt+1;
    wait(data_out_valid_o);

    end_cycle = cycle_cnt;
    latency   = end_cycle - start_cycle;

    $display("[%0t] latency = %0d cycles",
             $time, latency);

    if(data_out_o !== expected) begin

        $display("EXPECTED = %h", expected);
        $display("ACTUAL   = %h", data_out_o);

        $fatal(1,"DATA MISMATCH");

    end

end
endtask

////////////////////////////////////////////////////////////
// RESET
////////////////////////////////////////////////////////////

task automatic do_reset;
begin

    rst_n_i         = 0;
    cfg_valid_i     = 0;
    data_in_valid_i = 0;
    cfg_data_i      = 0;
    data_in_i       = 0;

    repeat(10)
        @(posedge clk);

    rst_n_i = 1;

    repeat(10)
        @(posedge clk);

end
endtask

////////////////////////////////////////////////////////////
// TEST1 RESET
////////////////////////////////////////////////////////////

task automatic test1_reset;

begin

    $display("\nTEST1 RESET");

    do_reset();

    assert(dut.busy==0) else $error("system BUSY on Reset");
    assert(dut.wr_ptr_cfg==0) else $error("wr_ptr_cfg not initialized on Reset");
    assert(dut.rd_ptr_cfg==0) else $error("rd_ptr_cfg not initialized on Reset");
    assert(dut.program_ld_cnt==0) else $error("program_ld_cnt not initialized on Reset");
    assert(dut.program_st_cnt==0) else $error("program_st_cnt not initialized on Reset");
    $display("TEST1 PASS");

end
endtask

////////////////////////////////////////////////////////////
// TEST2 DEFAULT CONFIG (NO PROGRAMMING)
////////////////////////////////////////////////////////////

task automatic test2_default_config;

begin

    $display("\nTEST2 DEFAULT CONFIG");

    assert(dut.programmed == 0)
    else $fatal("DUT unexpectedly programmed");

    for(int i=0;i<N;i++)
        din[i] = $urandom;

    expected = din;
    wait_input_gap();
    send_input(din);
    wait_and_check();

    $display("TEST2 DEFAULT CONFIG PASS");

end
endtask
////////////////////////////////////////////////////////////
// TEST3 IDENTITY
////////////////////////////////////////////////////////////

task automatic test3_identity;

begin

    $display("\nTEST3 IDENTITY");

    for(int i=0;i<N;i++)
        perm[i]=i;

    load_permutation(perm);

    wait(dut.programmed);

    repeat(50) @(posedge clk);

    for(int i=0;i<N;i++)
        din[i] = $urandom;

    expected = golden_perm(din,perm);
    wait_input_gap();
    send_input(din);
    wait_and_check();

    $display("TEST3 PASS");

end
endtask

////////////////////////////////////////////////////////////
// TEST4 REVERSE
////////////////////////////////////////////////////////////

task automatic test4_reverse;

begin

    $display("\nTEST4 REVERSE");

    for(int i=0;i<N;i++)
        perm[i] = N-1-i;

    load_permutation(perm);

    repeat(50) @(posedge clk);

    for(int i=0;i<N;i++)
        din[i] = $urandom;

    expected = golden_perm(din,perm);

    wait_input_gap();
    send_input(din);
    wait_and_check();

    $display("TEST4 PASS");

end
endtask

////////////////////////////////////////////////////////////
// TEST5 Randome Stress test
////////////////////////////////////////////////////////////

task automatic test5_random_stress;

    int j;
    int tmp;

begin

    $display("\nTEST5 RANDOM STRESS");

    for(int i=0;i<N;i++)
        perm[i]=i;

    for(int i=N-1;i>0;i--) begin

        j = $urandom_range(0,i);

        tmp     = perm[i];
        perm[i] = perm[j];
        perm[j] = tmp;

    end

    load_permutation(perm);

    repeat(100) @(posedge clk);

    repeat(100) begin

        for(int i=0;i<N;i++)
            din[i] = $urandom;

        expected = golden_perm(din,perm);

        wait_input_gap();
        send_input(din);
        wait_and_check();

    end

    $display("TEST5 PASS");

end
endtask

////////////////////////////////////////////////////////////
// TEST6 LAST WORD
////////////////////////////////////////////////////////////

task automatic test6_last_word;

begin

    $display("\nTEST6 LAST WORD");

    for(int i=0;i<N;i++)
        perm[i]=0;

    for(int i=1014;i<=1023;i++)
        perm[i]=i;

    load_permutation(perm);

    repeat(100) @(posedge clk);

    din='0;

    for(int i=1014;i<=1023;i++)
        din[i]=1'b1;

    expected = golden_perm(din,perm);

    wait_input_gap();
    send_input(din);
    wait_and_check();

    $display("TEST6 PASS");

end
endtask

////////////////////////////////////////////////////////////
// TEST7 BUSY READY
////////////////////////////////////////////////////////////

task automatic test7_busy_ready;

begin

    $display("\nTEST7 BUSY READY");

    for(int i=0;i<N;i++)
        perm[i]=i;

    load_permutation(perm);

    wait(dut.programmed);

    wait_input_gap();

    for(int i=0;i<N;i++)
        din[i]=$urandom;

    send_input(din);

    @(posedge clk);

    assert(cfg_ready_o==0)
    else $fatal("cfg_ready_o should deassert while busy");

    wait(data_out_valid_o);

    @(posedge clk);

    assert(cfg_ready_o==1)
    else $fatal("cfg_ready_o should reassert after completion");

    $display("TEST7 BUSY READY PASS");

end
endtask
////////////////////////////////////////////////////////////
// TEST8 configuration boundary check
////////////////////////////////////////////////////////////

task automatic test8_cfg_boundary_perm;

begin

    $display("\nTEST8 CFG BOUNDARY");

    for(int i=0;i<N;i++)
        perm[i]=i;

    perm[1018]=1023;
    perm[1019]=1022;
    perm[1020]=1021;
    perm[1021]=1020;
    perm[1022]=1019;
    perm[1023]=1018;

    load_permutation(perm);

    repeat(100) @(posedge clk);

    for(int i=0;i<N;i++)
        din[i]=$urandom;

    expected = golden_perm(din,perm);

    wait_input_gap();
    send_input(din);

    wait_and_check();
    $display("TEST8 configuration boundary check PASS");

end
endtask
////////////////////////////////////////////////////////////
// TEST9 PROGRAMMING COMPLETE -> IMMEDIATE USE
////////////////////////////////////////////////////////////

task automatic test9_programming_complete_immediate_use;

begin

    $display("\nTEST9 PROGRAMMING COMPLETE IMMEDIATE USE");

    // Reverse permutation
    for(int i=0;i<N;i++)
        perm[i] = N-1-i;

    load_permutation(perm);

    for(int i=0;i<N;i++)
        din[i] = $urandom;

    expected = golden_perm(din,perm);

    //    wait_input_gap(); // exeption edge case breaking data_in_valid_i 1us requirement
    send_input(din);

    wait_and_check();

    $display("TEST9 PASS");

end
endtask
////////////////////////////////////////////////////////////
// TEST10 MID PROGRAMMING REQUEST
////////////////////////////////////////////////////////////

task automatic test10_mid_programming_request;

    int new_perm [0:N-1];
    logic [63:0] cfg_word;
    int idx;

begin

    $display("\nTEST10 MID PROGRAMMING REQUEST");

    // Program initial IDENTITY permutation
    for(int i=0;i<N;i++)
        perm[i] = i;

    load_permutation(perm);

    repeat(50) @(posedge clk);

    // Build new REVERSE permutation
    for(int i=0;i<N;i++)
        new_perm[i] = N-1-i;

    // Start programming ONLY PART OF IT
    idx = 0;

    for(int w=0; w<166; w++) begin // busy should start

        cfg_word = '0;

        for(int k=0;k<6;k++) begin
            cfg_word[k*10 +:10] = new_perm[idx];
            idx++;
        end

        send_cfg_word(cfg_word);
    end

    // Request permutation before programming completes
    for(int i=0;i<N;i++)
        din[i] = $urandom;

    // EXPECT OLD IDENTITY PERMUTATION
    expected = golden_perm(din,perm);

    send_input(din);

    wait_and_check();

    // Finish remaining configuration
    for(int w=166; w<CFG_DEPTH; w++) begin

        cfg_word = '0;

        for(int k=0;k<6;k++) begin
            if(idx < N)
                cfg_word[k*10 +:10] = new_perm[idx];
            idx++;
        end

        send_cfg_word(cfg_word);
    end

    // Verify NEW permutation now active
    repeat(50) @(posedge clk);

    for(int i=0;i<N;i++)
        din[i] = $urandom;

    expected = golden_perm(din,new_perm);

    wait_input_gap();
    send_input(din);

    wait_and_check();

    $display("TEST10 PASS");

end
endtask

////////////////////////////////////////////////////////////
// MAIN
////////////////////////////////////////////////////////////

initial begin

    cycle_cnt = 0;

    test1_reset();
    test2_default_config();
    test3_identity();
    test4_reverse();
    test5_random_stress();
    test6_last_word();
    test7_busy_ready();    
    test8_cfg_boundary_perm();
    test9_programming_complete_immediate_use();
    test10_mid_programming_request();
    $display("================");
    $display("ALL TESTS PASSED");
    $display("================");

    #100;
    $finish;

end

endmodule