///////////////////////////////////////////////////////////////////////////////////////////
//
// Designer: Nameer Iqbal Ansari
// 
// Create Date: 06/06/2026
// Design Name: Block RAM Module
// Module Name: Block_RAM
// Target Devices: xc7z030ffg676-3 (Zynq-7000 series)
// Tool Versions: Vivado 2018.2
// 
/////////////////////////////////////////////////////////////////////////////////////////////
module Block_RAM #(
    parameter DATA_WIDTH = 60,
    parameter DEPTH      = 171
)(
    input  logic                        clk,
    input  logic                        we,
    input  logic [$clog2(DEPTH)-1:0]    waddr,
    input  logic [DATA_WIDTH-1:0]       wdata,
    input  logic [$clog2(DEPTH)-1:0]    raddr,
    output logic [DATA_WIDTH-1:0]       rdata
);
    logic [DATA_WIDTH-1:0] indice_map [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (we)
            indice_map[waddr] <= wdata;
    end

    always_ff @(posedge clk) begin
        rdata <= indice_map[raddr];  // registered read
    end

endmodule