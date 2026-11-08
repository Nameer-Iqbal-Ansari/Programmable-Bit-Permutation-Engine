// -----------------------------------------------------------------------------
// bp_env.sv
// -----------------------------------------------------------------------------
class bp_env #(int N = 1024, int IDX_PER_WORD = 6) extends uvm_env;
  `uvm_component_param_utils(bp_env #(N, IDX_PER_WORD))

  bp_cfg_agent  #(N, IDX_PER_WORD) cfg_agt;
  bp_data_agent #(N)               data_agt;
  bp_scoreboard #(N, IDX_PER_WORD) sb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg_agt  = bp_cfg_agent  #(N, IDX_PER_WORD)::type_id::create("cfg_agt", this);
    data_agt = bp_data_agent #(N)::type_id::create("data_agt", this);
    sb       = bp_scoreboard #(N, IDX_PER_WORD)::type_id::create("sb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    cfg_agt.mon.ap.connect(sb.cfg_imp);
    data_agt.mon.ap.connect(sb.data_imp);
  endfunction

endclass

// -----------------------------------------------------------------------------
// bp_test.sv
// -----------------------------------------------------------------------------

// Base test: no config load -> DUT stays in default identity mapping,
// scoreboard's table is also identity by default, so this alone validates
// the unprogrammed datapath + the 300-cycle latency assertion in the if.
class bp_identity_test extends uvm_test;
  `uvm_component_utils(bp_identity_test)

  bp_env #(1024, 6) env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = bp_env #(1024, 6)::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    bp_data_seq #(1024) dseq = bp_data_seq #(1024)::type_id::create("dseq");
    phase.raise_objection(this);
    dseq.num_txns = 10;
    dseq.start(env.data_agt.sqr);
    phase.drop_objection(this);
  endtask

endclass

// Programmed test: loads a full random permutation table (171 cfg words for
// N=1024), then streams data and checks against that same table.
class bp_programmed_test extends uvm_test;
  `uvm_component_utils(bp_programmed_test)

  bp_env #(1024, 6) env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = bp_env #(1024, 6)::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    bp_cfg_load_seq #(1024, 6) cseq = bp_cfg_load_seq #(1024, 6)::type_id::create("cseq");
    bp_data_seq #(1024)        dseq = bp_data_seq #(1024)::type_id::create("dseq");

    phase.raise_objection(this);
    cseq.start(env.cfg_agt.sqr);       // load table first (shadow buffering, README)
    dseq.num_txns = 20;
    dseq.start(env.data_agt.sqr);      // then stream data against it
    phase.drop_objection(this);
  endtask

endclass

// -----------------------------------------------------------------------------
// bp_pkg.sv
// -----------------------------------------------------------------------------
package bp_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "bp_txns.sv"
  `include "bp_sequences.sv"
  `include "bp_drivers.sv"
  `include "bp_monitors.sv"
  `include "bp_agents.sv"
  `include "bp_scoreboard.sv"
  `include "bp_env.sv"
  `include "bp_test.sv"
endpackage

// -----------------------------------------------------------------------------
// bp_tb_top.sv
// NOTE: DUT module name/port list assumed from README's I/O table
// (src/bit_permuter.sv). Adjust the instantiation if the real RTL differs.
// -----------------------------------------------------------------------------
import uvm_pkg::*;
`include "uvm_macros.svh"
import bp_pkg::*;

module bp_tb_top;

  localparam int N = 1024;

  logic clk_i = 0;
  logic rst_n_i = 0;

  always #1.667ns clk_i = ~clk_i;   // 300 MHz

  bit_permuter_if #(.N(N), .IDX_PER_WORD(6), .LATENCY_MAX(300))
    bp_if (.clk_i(clk_i), .rst_n_i(rst_n_i));

  bit_permuter #(.N(N)) dut (
    .clk_i             (clk_i),
    .rst_n_i           (rst_n_i),
    .cfg_data_i        (bp_if.cfg_data_i),
    .cfg_valid_i       (bp_if.cfg_valid_i),
    .cfg_ready_o       (bp_if.cfg_ready_o),
    .data_in_i         (bp_if.data_in_i),
    .data_in_valid_i   (bp_if.data_in_valid_i),
    .data_out_o        (bp_if.data_out_o),
    .data_out_valid_o  (bp_if.data_out_valid_o)
  );

  initial begin
    rst_n_i = 0;
    repeat (5) @(posedge clk_i);
    rst_n_i = 1;
  end

  initial begin
    uvm_config_db #(virtual bit_permuter_if #(N, .IDX_PER_WORD(6)).CFG_DRIVER)::set(null, "*", "cfg_vif", bp_if.CFG_DRIVER);
    uvm_config_db #(virtual bit_permuter_if #(N).DATA_DRIVER)::set(null, "*", "data_vif", bp_if.DATA_DRIVER);
    uvm_config_db #(virtual bit_permuter_if #(N, .IDX_PER_WORD(6)).MONITOR)::set(null, "*", "mon_vif", bp_if.MONITOR);
    run_test("bp_programmed_test");
  end

  initial begin
    #1ms;
    `uvm_fatal("TIMEOUT", "simulation watchdog expired")
  end

endmodule
