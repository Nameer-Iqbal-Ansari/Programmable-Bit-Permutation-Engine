// -----------------------------------------------------------------------------
// bp_cfg_txn.sv / bp_data_txn.sv
// Two transaction types since cfg and data are independent streamed channels.
// -----------------------------------------------------------------------------

// One 64-bit config word: up to IDX_PER_WORD packed indices.
// valid_count handles the last word of a load, which is only partially
// filled (README: 1024 indices / 6 per word = 171 words, last word has
// 1024 - 170*6 = 4 valid indices).
class bp_cfg_txn #(int N = 1024, int IDX_PER_WORD = 6) extends uvm_sequence_item;

  localparam int IDX_WIDTH = $clog2(N);

  rand bit [IDX_WIDTH-1:0] idx [IDX_PER_WORD];
  rand int unsigned         valid_count;   // how many entries in idx[] are meaningful

  constraint c_valid_count {
    valid_count inside {[1:IDX_PER_WORD]};
  }

  constraint c_idx_range {
    foreach (idx[i]) idx[i] < N;
  }

  `uvm_object_param_utils_begin(bp_cfg_txn #(N, IDX_PER_WORD))
    `uvm_field_sarray_int(idx,         UVM_ALL_ON)
    `uvm_field_int(valid_count,        UVM_ALL_ON)
  `uvm_object_param_utils_end

  function new(string name = "bp_cfg_txn");
    super.new(name);
  endfunction

  // packs idx[] into a single 64-bit cfg word, matching
  // cfg_data_i = { idx5, idx4, idx3, idx2, idx1, idx0 }
  function bit [63:0] pack_word();
    pack_word = '0;
    for (int i = 0; i < IDX_PER_WORD; i++)
      pack_word |= (bit[63:0]'(idx[i]) << (i * IDX_WIDTH));
  endfunction

endclass

// One data-plane transaction: request fields randomized by the sequence,
// response field filled in by the monitor once data_out_valid_o fires.
class bp_data_txn #(int N = 1024) extends uvm_sequence_item;

  rand bit [N-1:0] data_in;
  bit     [N-1:0] data_out;   // response - not randomized

  `uvm_object_param_utils_begin(bp_data_txn #(N))
    `uvm_field_int(data_in,  UVM_ALL_ON)
    `uvm_field_int(data_out, UVM_ALL_ON | UVM_NOCOMPARE)
  `uvm_object_param_utils_end

  function new(string name = "bp_data_txn");
    super.new(name);
  endfunction

endclass
