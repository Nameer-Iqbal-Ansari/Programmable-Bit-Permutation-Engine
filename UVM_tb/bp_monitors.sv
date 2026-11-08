// -----------------------------------------------------------------------------
// bp_monitors.sv
// -----------------------------------------------------------------------------

class bp_cfg_monitor #(int N = 1024, int IDX_PER_WORD = 6) extends uvm_monitor;
  `uvm_component_param_utils(bp_cfg_monitor #(N, IDX_PER_WORD))

  virtual bit_permuter_if #(N, .IDX_PER_WORD(IDX_PER_WORD)).MONITOR vif;
  uvm_analysis_port #(bp_cfg_txn #(N, IDX_PER_WORD)) ap;

  localparam int IDX_WIDTH = $clog2(N);

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual bit_permuter_if #(N, .IDX_PER_WORD(IDX_PER_WORD)).MONITOR)::get(this, "", "mon_vif", vif))
      `uvm_fatal(get_type_name(), "mon_vif not set via uvm_config_db")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.cfg_valid_i && vif.mon_cb.cfg_ready_o) begin
        bp_cfg_txn #(N, IDX_PER_WORD) tr = bp_cfg_txn #(N, IDX_PER_WORD)::type_id::create("tr");
        for (int i = 0; i < IDX_PER_WORD; i++)
          tr.idx[i] = vif.mon_cb.cfg_data_i[i*IDX_WIDTH +: IDX_WIDTH];
        ap.write(tr);
      end
    end
  endtask

endclass

class bp_data_monitor #(int N = 1024) extends uvm_monitor;
  `uvm_component_param_utils(bp_data_monitor #(N))

  virtual bit_permuter_if #(N).MONITOR vif;
  uvm_analysis_port #(bp_data_txn #(N)) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual bit_permuter_if #(N).MONITOR)::get(this, "", "mon_vif", vif))
      `uvm_fatal(get_type_name(), "mon_vif not set via uvm_config_db")
  endfunction

  task run_phase(uvm_phase phase);
    bp_data_txn #(N) pending;
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.data_in_valid_i) begin
        pending          = bp_data_txn #(N)::type_id::create("pending");
        pending.data_in  = vif.mon_cb.data_in_i;
      end
      if (vif.mon_cb.data_out_valid_o && pending != null) begin
        pending.data_out = vif.mon_cb.data_out_o;
        ap.write(pending);
        pending = null;
      end
    end
  endtask

endclass
