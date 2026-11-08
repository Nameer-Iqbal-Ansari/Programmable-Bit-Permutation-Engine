// -----------------------------------------------------------------------------
// bp_scoreboard.sv
// Maintains its own copy of the permutation table by observing cfg words
// (mirrors what the DUT's shadow-buffer + BRAM does), then checks every
// data_out against permute(data_in, table). Defaults to identity mapping
// per README ("Default state: Identity mapping (unprogrammed)").
// -----------------------------------------------------------------------------

`uvm_analysis_imp_decl(_cfg)
`uvm_analysis_imp_decl(_data)

class bp_scoreboard #(int N = 1024, int IDX_PER_WORD = 6) extends uvm_scoreboard;
  `uvm_component_param_utils(bp_scoreboard #(N, IDX_PER_WORD))

  uvm_analysis_imp_cfg  #(bp_cfg_txn #(N, IDX_PER_WORD), bp_scoreboard #(N, IDX_PER_WORD)) cfg_imp;
  uvm_analysis_imp_data #(bp_data_txn #(N),              bp_scoreboard #(N, IDX_PER_WORD)) data_imp;

  int unsigned perm_table [N];
  int unsigned load_ptr;   // tracks which output index the next cfg word fills

  int pass_cnt, fail_cnt;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cfg_imp  = new("cfg_imp",  this);
    data_imp = new("data_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    for (int i = 0; i < N; i++) perm_table[i] = i;   // identity default
    load_ptr = 0;
  endfunction

  // called on every accepted cfg word
  function void write_cfg(bp_cfg_txn #(N, IDX_PER_WORD) tr);
    for (int i = 0; i < IDX_PER_WORD; i++) begin
      if (i < tr.valid_count) begin
        if (load_ptr < N) perm_table[load_ptr] = tr.idx[i];
        load_ptr++;
      end
    end
  endfunction

  // called on every completed data permutation
  function void write_data(bp_data_txn #(N) tr);
    bit [N-1:0] expected;
    for (int i = 0; i < N; i++)
      expected[i] = tr.data_in[perm_table[i]];   // output_bit[i] = input_bit[index[i]]

    if (tr.data_out === expected) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      `uvm_error(get_type_name(),
        $sformatf("RESULT >>\nEXPECTED = %0h\nACTUAL   = %0h\nFatal: DATA MISMATCH",
                   expected, tr.data_out))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    if (fail_cnt == 0 && pass_cnt > 0)
      `uvm_info(get_type_name(), "================\nALL TESTS PASSED\n================", UVM_LOW)
    `uvm_info(get_type_name(), $sformatf("pass=%0d fail=%0d", pass_cnt, fail_cnt), UVM_LOW)
  endfunction

endclass
