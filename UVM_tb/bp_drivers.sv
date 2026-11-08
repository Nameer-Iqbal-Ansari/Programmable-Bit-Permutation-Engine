// -----------------------------------------------------------------------------
// bp_drivers.sv
// Two drivers for the two independent channels. Both hold a handle into the
// same physical interface, but each only touches its own disjoint signal set.
// -----------------------------------------------------------------------------

class bp_cfg_driver #(int N = 1024, int IDX_PER_WORD = 6) extends uvm_driver #(bp_cfg_txn #(N, IDX_PER_WORD));
  `uvm_component_param_utils(bp_cfg_driver #(N, IDX_PER_WORD))

  virtual bit_permuter_if #(N, .IDX_PER_WORD(IDX_PER_WORD)).CFG_DRIVER vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual bit_permuter_if #(N, .IDX_PER_WORD(IDX_PER_WORD)).CFG_DRIVER)::get(this, "", "cfg_vif", vif))
      `uvm_fatal(get_type_name(), "cfg_vif not set via uvm_config_db")
  endfunction

  task reset_phase(uvm_phase phase);
    phase.raise_objection(this);
    vif.cfg_drv_cb.cfg_valid_i <= 1'b0;
    vif.cfg_drv_cb.cfg_data_i  <= '0;
    repeat (3) @(vif.cfg_drv_cb);
    phase.drop_objection(this);
  endtask

  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      drive(req);
      seq_item_port.item_done();
    end
  endtask

  // respects cfg_ready_o backpressure (README: "uses cfg_ready_o backpressure control")
  task drive(bp_cfg_txn #(N, IDX_PER_WORD) tr);
    vif.cfg_drv_cb.cfg_data_i  <= tr.pack_word();
    vif.cfg_drv_cb.cfg_valid_i <= 1'b1;
    do begin
      @(vif.cfg_drv_cb);
    end while (!vif.cfg_drv_cb.cfg_ready_o);
    vif.cfg_drv_cb.cfg_valid_i <= 1'b0;
  endtask

endclass

class bp_data_driver #(int N = 1024) extends uvm_driver #(bp_data_txn #(N));
  `uvm_component_param_utils(bp_data_driver #(N))

  virtual bit_permuter_if #(N).DATA_DRIVER vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual bit_permuter_if #(N).DATA_DRIVER)::get(this, "", "data_vif", vif))
      `uvm_fatal(get_type_name(), "data_vif not set via uvm_config_db")
  endfunction

  task reset_phase(uvm_phase phase);
    phase.raise_objection(this);
    vif.data_drv_cb.data_in_valid_i <= 1'b0;
    vif.data_drv_cb.data_in_i       <= '0;
    repeat (3) @(vif.data_drv_cb);
    phase.drop_objection(this);
  endtask

  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      drive(req);
      seq_item_port.item_done();
    end
  endtask

  task drive(bp_data_txn #(N) tr);
    vif.data_drv_cb.data_in_i       <= tr.data_in;
    vif.data_drv_cb.data_in_valid_i <= 1'b1;
    @(vif.data_drv_cb);
    vif.data_drv_cb.data_in_valid_i <= 1'b0;

    // throughput-aware: wait for this permutation's result before letting
    // the sequencer send the next item, per the 1-per-1us spec
    do begin
      @(vif.data_drv_cb);
    end while (!vif.data_drv_cb.data_out_valid_o);
  endtask

endclass
