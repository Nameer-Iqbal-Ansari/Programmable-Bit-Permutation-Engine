`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////
//
// Designer: Nameer Iqbal Ansari
// 
// Create Date: 06/06/2026
// Design Name: Programmable Bit Permutation Engine
// Module Name: bit_permuter
// Target Devices: xc7z030ffg676-3 (Zynq-7000 series)
// Tool Versions: Vivado 2018.2
//
// Description: A configurable N-bit programmable permutation engine designed for FPGA
// The design supports runtime reconfiguration of bit ordering using a streamed configuration 
// interface and a BRAM-backed index storage architecture.
// 
// Dependencies: BRAM_code.sv
// 
/////////////////////////////////////////////////////////////////////////////////////////////
module bit_permuter #(
    parameter N               = 1024,
    parameter CFG_WIDTH       = 64,         // Config bus width
    parameter NUM_IDC_PER_CFG = 6           // indices per cfg word
)(
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic [CFG_WIDTH-1:0] cfg_data_i,
    input  logic                 cfg_valid_i,
    output logic                 cfg_ready_o,
    input  logic [N-1:0]         data_in_i,
    input  logic                 data_in_valid_i,
    output logic [N-1:0]         data_out_o,
    output logic                 data_out_valid_o
);

//////////////////////////////////////////////////////////////////////
// LOCAL PARAMETERS  
//////////////////////////////////////////////////////////////////////

localparam IDX_W       = $clog2(N);                                    // bit width of index
localparam CFG_DEPTH   = N/NUM_IDC_PER_CFG + (N%NUM_IDC_PER_CFG != 0); // Number of configuration transactions
localparam PGM_DEPTH   = 9;                                            // Depth of programed memory
localparam NUM_IDC_PER_PGM = CFG_DEPTH/PGM_DEPTH;                      // Number of indexes per PGM mem

//////////////////////////////////////////////////////////////////////
// SIGNALS DECLERATION
//////////////////////////////////////////////////////////////////////

// Shadow + BRAM storage
(* ram_style = "block" *)
logic [IDX_W-1:0]                                 cur_idx [0:NUM_IDC_PER_PGM*NUM_IDC_PER_CFG-1];

(* ram_style = "block" *)
logic [IDX_W*NUM_IDC_PER_CFG*NUM_IDC_PER_PGM-1:0] program_st_data[0:PGM_DEPTH-1];

logic [N/32-1:0]                                  input_buf [0:N/32-1]; // input buffering (word split)

logic [IDX_W*NUM_IDC_PER_CFG*NUM_IDC_PER_PGM-1:0] program_rdata;

logic [$clog2(NUM_IDC_PER_PGM)-1:0]               wr_ptr_cfg;       // program cfg pointer (cfg)
logic [$clog2(PGM_DEPTH)-1:0]                     rd_ptr_cfg;       // prgoram page point (cfg)

logic [$clog2(PGM_DEPTH)-1:0]                     program_ld_cnt;                     // read pointer (program pages)
logic [$clog2(PGM_DEPTH)-1:0]                     ld_cnt_d, ld_cnt_d_d, ld_cnt_d_d_d; // pipelined program pages addresses

logic [NUM_IDC_PER_PGM*NUM_IDC_PER_CFG-1:0]       result_shift;

logic [$clog2(PGM_DEPTH)-1:0]                     program_st_cnt;

logic                                             store_program; // trigger BRAM write
logic                                             read_program;  // trigger BRAM read

logic                                             busy;
logic                                             programmed;    // 1 time indicator for default config overwrite 
logic                                             done, done_d, done_dd;

//////////////////////////////////////////////////////////////////////
// CONFIGURATION DATAPATH
//////////////////////////////////////////////////////////////////////

/////// ready when not busy or output stage finishing ///////////////////
assign cfg_ready_o = !busy || data_out_valid_o;

////////////////////////// CFG LOAD /////////////////////////////////////
always_ff @(posedge clk_i) begin
    if (!rst_n_i) begin
        wr_ptr_cfg <= '0;
        rd_ptr_cfg <= '0;
    end else if (cfg_valid_i && cfg_ready_o) begin
        if (wr_ptr_cfg + 1 == NUM_IDC_PER_PGM) begin
            wr_ptr_cfg <= '0;
            rd_ptr_cfg <= (rd_ptr_cfg + 1 == PGM_DEPTH) ? '0 : 
                                                                  rd_ptr_cfg + 1; // increment per last cfg per program page
        end else begin
            wr_ptr_cfg <= wr_ptr_cfg + 1;
        end
    end
end

//////// program write condition (page complete) ////////////////////////
assign store_program = ((rd_ptr_cfg == PGM_DEPTH-1)         && // last program page
                        (wr_ptr_cfg == NUM_IDC_PER_PGM-1)   && // last cfg per program page
                         cfg_valid_i && cfg_ready_o)        || 
                       !(program_st_cnt == 0);                 // keep until all program pages stored

//////////////////////// PROGRAM STORE ///////////////////////
always_ff @(posedge clk_i) begin
    if (!rst_n_i) begin
        programmed <= 0;
        program_st_cnt <= '0;
    end else begin
        if (store_program) begin
            programmed <= 1;
            program_st_cnt <= (program_st_cnt + 1 == PGM_DEPTH) ? '0 : 
                                                                  program_st_cnt + 1;
        end
    end
end

////////// pack cfg stream into shift register (temperary storage) //////
always_ff @(posedge clk_i) begin
    if (cfg_valid_i && cfg_ready_o)
        program_st_data[rd_ptr_cfg] <= {cfg_data_i[59:0],
                                        program_st_data[rd_ptr_cfg][IDX_W*NUM_IDC_PER_CFG*NUM_IDC_PER_PGM-1:60]};
end

//////////////////////////////////////////////////////////////////////
// BLOCK RAM FOR PROGRAM MAIN STORAGE
//////////////////////////////////////////////////////////////////////

Block_RAM #(
    .DATA_WIDTH (IDX_W*NUM_IDC_PER_CFG*NUM_IDC_PER_PGM), // 10*6*19
    .DEPTH      (PGM_DEPTH                             ) // 9
) pgm_bram_1 (
    .clk   (clk_i                          ),
    .we    (store_program                  ),
    .waddr (program_st_cnt                 ),
    .wdata (program_st_data[program_st_cnt]),
    .raddr (program_ld_cnt                 ),
    .rdata (program_rdata                  )
);

//////////////////////////////////////////////////////////////////////
// PERMUTATION DATAPATH
//////////////////////////////////////////////////////////////////////

/////// read enable when program being loaded for permutation ///////////
assign read_program = !(program_ld_cnt == 0);

////////////////////////// DATA INPUT ///////////////////////////////////
always_ff @(posedge clk_i) begin
    if (!rst_n_i) begin
        program_ld_cnt <= '0;
        busy <= 0;
    end else begin
        if (data_in_valid_i) begin
            busy <= 1;

            // split 32-bit words
            for (int i = 0; i < N/32; i++)
                input_buf[i] <= data_in_i[i*32 +: 32];

            program_ld_cnt <= program_ld_cnt + 1;
        end

        if (data_out_valid_o)
            busy <= 0;

        if (read_program)
            program_ld_cnt <= (program_ld_cnt == PGM_DEPTH-1) ? '0 : program_ld_cnt + 1;
    end
end

////////////////////////// pipeline read pointer ////////////////////////
always_ff @(posedge clk_i) ld_cnt_d     <= program_ld_cnt;
always_ff @(posedge clk_i) ld_cnt_d_d   <= ld_cnt_d;
always_ff @(posedge clk_i) ld_cnt_d_d_d <= ld_cnt_d_d;

////////////////////////// INDEX GENERATION /////////////////////////////
always_ff @(posedge clk_i) begin
    if (busy) begin
        // calculation for all the indexs per program page (114 indexes per program page)
        for (int i = 0; i < NUM_IDC_PER_PGM*NUM_IDC_PER_CFG; i++) begin
            cur_idx[i] <= programmed ?
                          program_rdata[i*IDX_W +: IDX_W] :
                          IDX_W'((ld_cnt_d*NUM_IDC_PER_PGM*NUM_IDC_PER_CFG)+i); // Default config when not programmed for once
        end
    end
end

////////////////////////// PERMUTATION //////////////////////////////////
always_ff @(posedge clk_i) begin
    if (!rst_n_i)
        result_shift <= '0;
    else begin
        for (int i = 0; i < NUM_IDC_PER_PGM*NUM_IDC_PER_CFG; i++) begin
            result_shift[i] <= input_buf[cur_idx[i][9:5]][cur_idx[i][4:0]]; //32x32 bit selection
        end
    end
end

///////////////////////// OUTPUT PACKING ////////////////////////////////
always_ff @(posedge clk_i) begin
    if (!rst_n_i)
        data_out_o <= '0;
    else begin
        // setting all 114 permuted bits into out
        case (ld_cnt_d_d_d)
            0: data_out_o[113:0]    <= result_shift;
            1: data_out_o[227:114]  <= result_shift;
            2: data_out_o[341:228]  <= result_shift;
            3: data_out_o[455:342]  <= result_shift;
            4: data_out_o[569:456]  <= result_shift;
            5: data_out_o[683:570]  <= result_shift;
            6: data_out_o[797:684]  <= result_shift;
            7: data_out_o[911:798]  <= result_shift;
            8: data_out_o[1023:912] <= result_shift;
            default: data_out_o[113:0] <= result_shift;
        endcase
    end
end

////////////////////////// DONE FLAG ////////////////////////////////////
always_ff @(posedge clk_i) begin
    if (!rst_n_i)
        done <= 1'b0;
    else
        done <= (busy && program_ld_cnt == PGM_DEPTH-1);
end

////////////////////////// output valid pipeline ////////////////////////
always_ff @(posedge clk_i) begin
    if (!rst_n_i)
        data_out_valid_o <= 1'b0;
    else begin
        done_d  <= done;
        done_dd <= done_d;
        data_out_valid_o <= done_dd;
    end
end

endmodule