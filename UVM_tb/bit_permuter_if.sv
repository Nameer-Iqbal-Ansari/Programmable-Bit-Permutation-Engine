// -----------------------------------------------------------------------------
// bit_permuter_if.sv
// N            : data width (default 1024 per README)
// CFG_WIDTH    : config word width (64, fixed by protocol)
// IDX_PER_WORD : indices packed per config word (default 6)
// LATENCY_MAX  : watchdog bound in cycles for data_in_valid -> data_out_valid.
//                README documents ~12-cycle typical latency (T+12) but a
//                1 permutation/1us throughput spec at 300MHz = 300 cycles,
//                so 300 is used here as a generous upper-bound timeout,
//                not the expected-case latency.
// -----------------------------------------------------------------------------
interface bit_permuter_if #(
  int N            = 1024,
  int CFG_WIDTH    = 64,
  int IDX_PER_WORD = 6,
  int LATENCY_MAX  = 300
) (input logic clk_i, input logic rst_n_i);

  logic [CFG_WIDTH-1:0] cfg_data_i;
  logic                 cfg_valid_i;
  logic                 cfg_ready_o;

  logic [N-1:0]         data_in_i;
  logic                 data_in_valid_i;
  logic [N-1:0]         data_out_o;
  logic                 data_out_valid_o;

  clocking cfg_drv_cb @(posedge clk_i);
    output cfg_data_i, cfg_valid_i;
    input  cfg_ready_o;
  endclocking

  clocking data_drv_cb @(posedge clk_i);
    output data_in_i, data_in_valid_i;
    input  data_out_o, data_out_valid_o;
  endclocking

  clocking mon_cb @(posedge clk_i);
    input cfg_data_i, cfg_valid_i, cfg_ready_o,
          data_in_i, data_in_valid_i, data_out_o, data_out_valid_o;
  endclocking

  modport CFG_DRIVER  (clocking cfg_drv_cb,  input clk_i, rst_n_i);
  modport DATA_DRIVER (clocking data_drv_cb, input clk_i, rst_n_i);
  modport MONITOR     (clocking mon_cb,      input clk_i, rst_n_i);

  // ---------------------------------------------------------------------
  // Latency watchdog: data_out_valid_o must arrive within LATENCY_MAX
  // cycles of data_in_valid_i. This is the assertion the user asked for.
  // ---------------------------------------------------------------------
  property p_latency_bound;
    @(posedge clk_i) disable iff (!rst_n_i)
    data_in_valid_i |-> ##[1:LATENCY_MAX] data_out_valid_o;
  endproperty

  assert property (p_latency_bound)
    else $error("LATENCY VIOLATION: data_out_valid_o not seen within %0d cycles of data_in_valid_i", LATENCY_MAX);

  // ---------------------------------------------------------------------
  // Bonus checks straight from the README's "Recommended assertions"
  // section, now actually wired into the interface instead of left as
  // pseudocode.
  // ---------------------------------------------------------------------
  property p_cfg_handshake_safety;
    @(posedge clk_i) disable iff (!rst_n_i)
    (cfg_valid_i && !cfg_ready_o) |=> cfg_valid_i;   // held until accepted
  endproperty
  assert property (p_cfg_handshake_safety)
    else $error("cfg_valid_i dropped before cfg_ready_o accepted it");

  property p_no_x_on_output;
    @(posedge clk_i) disable iff (!rst_n_i)
    data_out_valid_o |-> !$isunknown(data_out_o);
  endproperty
  assert property (p_no_x_on_output)
    else $error("data_out_o is X/Z while data_out_valid_o is asserted");

endinterface
