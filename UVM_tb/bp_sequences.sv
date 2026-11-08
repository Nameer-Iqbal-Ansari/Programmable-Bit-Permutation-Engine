// -----------------------------------------------------------------------------
// bp_sequences.sv
// -----------------------------------------------------------------------------

// Loads one full random permutation of N indices (a bijection, so the
// scoreboard model is a clean permute rather than a lossy many-to-one map).
// Splits it into ceil(N/IDX_PER_WORD) cfg words - 171 for the N=1024 default,
// matching the README exactly.
class bp_cfg_load_seq #(int N = 1024, int IDX_PER_WORD = 6)
  extends uvm_sequence #(bp_cfg_txn #(N, IDX_PER_WORD));

  `uvm_object_param_utils(bp_cfg_load_seq #(N, IDX_PER_WORD))

  // exposed so the test/scoreboard can grab the same table that was sent
  int unsigned perm_table [N];

  function new(string name = "bp_cfg_load_seq");
    super.new(name);
  endfunction

  // Fisher-Yates shuffle for a true permutation (no repeats)
  function void build_random_permutation();
    int unsigned tmp;
    int unsigned j;
    for (int i = 0; i < N; i++) perm_table[i] = i;
    for (int i = N - 1; i > 0; i--) begin
      j = $urandom_range(i, 0);
      tmp            = perm_table[i];
      perm_table[i]  = perm_table[j];
      perm_table[j]  = tmp;
    end
  endfunction

  task body();
    bp_cfg_txn #(N, IDX_PER_WORD) tr;
    int unsigned sent = 0;

    build_random_permutation();

    while (sent < N) begin
      int unsigned remaining = N - sent;
      int unsigned this_word_count = (remaining < IDX_PER_WORD) ? remaining : IDX_PER_WORD;

      tr = bp_cfg_txn #(N, IDX_PER_WORD)::type_id::create("tr");
      start_item(tr);
      tr.valid_count = this_word_count;
      for (int i = 0; i < IDX_PER_WORD; i++)
        tr.idx[i] = (i < this_word_count) ? perm_table[sent + i] : '0;
      finish_item(tr);

      sent += this_word_count;
    end
  endtask

endclass

// Sends num_txns random data words. Spaced ~LATENCY_MAX/2 cycles apart by
// default to respect the documented 1-permutation-per-1us throughput bound
// rather than flooding the DUT faster than it can drain the pipeline.
class bp_data_seq #(int N = 1024) extends uvm_sequence #(bp_data_txn #(N));
  `uvm_object_param_utils(bp_data_seq #(N))

  int num_txns = 10;

  function new(string name = "bp_data_seq");
    super.new(name);
  endfunction

  task body();
    bp_data_txn #(N) tr;
    repeat (num_txns) begin
      tr = bp_data_txn #(N)::type_id::create("tr");
      start_item(tr);
      assert(tr.randomize())
        else `uvm_error(get_type_name(), "randomize() failed")
      finish_item(tr);
    end
  endtask

endclass
