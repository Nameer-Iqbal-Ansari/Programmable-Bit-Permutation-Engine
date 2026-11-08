// -----------------------------------------------------------------------------
// bp_agents.sv
// -----------------------------------------------------------------------------

typedef uvm_sequencer #(bp_cfg_txn #(1024, 6))  bp_cfg_sequencer_t;
typedef uvm_sequencer #(bp_data_txn #(1024))    bp_data_sequencer_t;

class bp_cfg_agent #(int N = 1024, int IDX_PER_WORD = 6) extends uvm_agent;
  `uvm_component_param_utils(bp_cfg_agent #(N, IDX_PER_WORD))

  uvm_sequencer #(bp_cfg_txn #(N, IDX_PER_WORD)) sqr;
  bp_cfg_driver  #(N, IDX_PER_WORD)              drv;
  bp_cfg_monitor #(N, IDX_PER_WORD)              mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = bp_cfg_monitor #(N, IDX_PER_WORD)::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sqr = uvm_sequencer #(bp_cfg_txn #(N, IDX_PER_WORD))::type_id::create("sqr", this);
      drv = bp_cfg_driver #(N, IDX_PER_WORD)::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass

class bp_data_agent #(int N = 1024) extends uvm_agent;
  `uvm_component_param_utils(bp_data_agent #(N))

  uvm_sequencer #(bp_data_txn #(N)) sqr;
  bp_data_driver  #(N)              drv;
  bp_data_monitor #(N)              mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = bp_data_monitor #(N)::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sqr = uvm_sequencer #(bp_data_txn #(N))::type_id::create("sqr", this);
      drv = bp_data_driver #(N)::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass
