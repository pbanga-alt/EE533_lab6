///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
// $Id: module_template 2008-03-13 gac1 $
//
// Module: ids.v
// Project: NF2.1
// Description: Defines a simple ids module for the user data path.  The
// modules reads a 64-bit register that contains a pattern to match and
// counts how many packets match.  The register contents are 7 bytes of
// pattern and one byte of mask.  The mask bits are set to one for each
// byte of the pattern that should be included in the mask -- zero bits
// mean "don't care".
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module ids 
   #(
      parameter DATA_WIDTH = 64,
      parameter CTRL_WIDTH = DATA_WIDTH/8,
      parameter UDP_REG_SRC_WIDTH = 2
   )
   (
      input  [DATA_WIDTH-1:0]             in_data,
      input  [CTRL_WIDTH-1:0]             in_ctrl,
      input                               in_wr,
      output                              in_rdy,

      output [DATA_WIDTH-1:0]             out_data,
      output [CTRL_WIDTH-1:0]             out_ctrl,
      output                              out_wr,
      input                               out_rdy,
      
      // --- Register interface
      input                               reg_req_in,
      input                               reg_ack_in,
      input                               reg_rd_wr_L_in,
      input  [`UDP_REG_ADDR_WIDTH-1:0]    reg_addr_in,
      input  [`CPCI_NF2_DATA_WIDTH-1:0]   reg_data_in,
      input  [UDP_REG_SRC_WIDTH-1:0]      reg_src_in,

      output                              reg_req_out,
      output                              reg_ack_out,
      output                              reg_rd_wr_L_out,
      output  [`UDP_REG_ADDR_WIDTH-1:0]   reg_addr_out,
      output  [`CPCI_NF2_DATA_WIDTH-1:0]  reg_data_out,
      output  [UDP_REG_SRC_WIDTH-1:0]     reg_src_out,

      // misc
      input                                reset,
      input                                clk
   );

// bypass assignments
assign out_data      =     in_data;
assign in_rdy        =     out_rdy;                      //I have bypassed the connections for router
assign out_ctrl      =     in_ctrl;
assign out_wr        =     in_wr;

//--------------------------------------------------------------------------------------------------------------------------------------------------------------------//

//debug wires
wire           debug, imem_we_debug, dmem_web;                 //The address and data-in signals are common for register, imem and dmem interfaces. Write enable and dout are separate for each.
wire [31:0]    mem_addr_debug, command_reg, dpu_status;        //The imem and register port1 is muxed using debug to enter debug mode. Ddmem has dedicated portb for debug
wire [63:0]    mem_din_debug, dmem_doutb;  

//Debug assignments
assign imem_we_debug    =     command_reg[1];                           // This means we write 0x0a for imem write (include debug signal for muxing)
assign dmem_web         =     command_reg[2];                           // This means we write 0x0c for dmem write (debug mode not strictly required due to dedicated debug port)
assign debug            =     command_reg[3];                           // This means we write 0x08 for debug enable


// Logic Analyzer Signals
wire [63:0] 	la_monitor_sig0, la_monitor_sig1, la_monitor_sig2, la_monitor_sig3;     // We can monitor 256 bit with 64 depth. la_status==0(idle), 1(armed) 2(capturing), 4(done) 
wire [31:0] 	la_read_addr;                                                           // Current trigger is one hot coded with Instruction
wire [2:0] 	   la_status;
wire [255:0] 	la_dout;
wire 		      la_arm, la_reset, la_trigger;

//--------------------------------------------------------------------------------------------------------------------------------------------------------------------//
// Pipeline Registers
// IF Stage
reg [8:0]      pc_reg0;                                                      // The code progression is like a data path along the signal route: origin to destination. Just follow the trail to troubleshoot.
reg [8:0]      pc_reg1;
reg [8:0]      pc_reg2;
reg [8:0]      pc_reg3;
reg [1:0]      thread_en;
reg [10:0]     pc_in;

// IF stage wires
wire [31:0]    imem_dout;                                            
wire [10:0]    imem_addr; //, if_pc_plus_1;  // FIX INCREASE FOR 2048 IMEM
wire [8:0]     pc_next;
wire [31:0]    if_imem_dout_B;

assign         imem_addr = debug? mem_addr_debug[10:0] : pc_in;             //debug mux
assign         pc_next = pc_in[8:0] + 1;
// assign         pc_next = (ex_jump) ? idex_offset_reg : ((ex_branch_taken) ? ex_alu_dout[8:0] : pc_reg+1);  // Determine next pc

//--------------------------------------------------------------------------------------------------------------------------------------------------------------------//
// IF-ID Stage
reg [8:0]      ifid_pc_reg;
reg [1:0]      ifid_thread_id;

// ID Stage wires
wire [63:0]    id_r2_data0, id_r1_data0, id_r2_data1, id_r1_data1, id_r2_data2, id_r1_data2, id_r2_data3, id_r1_data3;
reg  [63:0]    id_r1_data_out, id_r2_data_out;
wire [8:0]     id_offset;
wire [3:0]     id_alu_op, id_passcond;                                       // Have to confirm the ALU opcode width with redesign
wire [2:0]     id_r1, id_r2, id_r3, id_reg1_addr;                            // Connected to register file
wire           id_regwe, id_memwe, id_user_stall, id_m2r, id_trigger;                         // Control Signals
wire           id_alusrc_A, id_alusrc_B, id_branch, id_jump, id_noop, id_update_flags;
reg  [63:0]    id_r1_data_out_latched, id_r2_data_out_latched; 

assign id_r1            =     imem_dout[12:10];
assign id_r2            =     imem_dout[15:13];
assign id_r3            =     imem_dout[18:16];                      // no reg_dst signal in the design as we use dedicated bits for destination register
assign id_offset        =     imem_dout[27:19];                      // 9 bit offset used for both branch, jump and immediate instructions
assign id_user_stall    =     imem_dout[30];
assign id_trigger       =     imem_dout[31];

assign id_reg1_addr     =  debug? mem_addr_debug[2:0] : id_r1;             //debug mux

//--------------------------------------------------------------------------------------------------------------------------------------------------------------------//

// ID-EX Stage Register
reg [63:0]     idex_r2_data_reg, idex_r1_data_reg;                                                       
reg [8:0]      idex_offset_reg; //idex_pc_plus_1_reg,
reg [8:0]      idex_pc_reg;
reg [1:0]      idex_thread_id;
reg [31:0]     idex_inst;
reg [3:0]      idex_passcond_reg, idex_alu_op_reg;                                   //check its width
reg [2:0]      idex_r3_reg;  
reg            idex_regwe_reg, idex_memwe_reg, idex_user_stall_reg, idex_m2r_reg, idex_noop_reg; 
reg            idex_alusrc_A_reg, idex_alusrc_B_reg, idex_branch_reg, idex_jump_reg, idex_update_flags_reg;

// Ex stage wires and Flags
reg            carry_flag0, zero_flag0, negative_flag0, overflow_flag0;                                  // FLAG Registers
reg            carry_flag1, zero_flag1, negative_flag1, overflow_flag1; 
reg            carry_flag2, zero_flag2, negative_flag2, overflow_flag2;
reg            carry_flag3, zero_flag3, negative_flag3, overflow_flag3;
reg            carry_flag_in, zero_flag_in, negative_flag_in, overflow_flag_in;                          // Input to pass decoder
wire           alu_carry, alu_zero, alu_negative, alu_overflow;
wire[63:0]     ex_alu_input2, ex_alu_input1, ex_alu_dout;                //connect with ALU and pass decoder
wire           ex_branch_taken, ex_pass, ex_jump;                                                                                                 


assign ex_alu_input1             =        idex_alusrc_A_reg?      ({{55{1'b0}}, idex_pc_reg} + 1'b1)                        :       idex_r1_data_reg;         
assign ex_alu_input2             =        idex_alusrc_B_reg?      {{55{idex_offset_reg[8]}}, idex_offset_reg}      :       idex_r2_data_reg;                         
assign ex_branch_taken           =        idex_branch_reg      &&    ex_pass;
assign ex_jump                   =        idex_jump_reg;

assign ex_alu_dout[63:32]        =        32'b0;                     // remove it later for extension to 64bit designs.

//--------------------------------------------------------------------------------------------------------------------------------------------------------------------//

// Ex-Mem Stage Registers
reg [63:0]     exmem_r2_data_reg, exmem_r1_data_reg;                                                       
reg [8:0]      exmem_offset_reg; //exmem_pc_plus_1_reg,
reg [8:0]      exmem_pc_reg;
reg [1:0]      exmem_thread_id;
reg [31:0]     exmem_inst;
reg [3:0]      exmem_passcond_reg, exmem_alu_op_reg;                                   //check its width
reg [2:0]      exmem_r3_reg;  
reg            exmem_regwe_reg, exmem_memwe_reg, exmem_user_stall_reg, exmem_m2r_reg, exmem_noop_reg; 
reg            exmem_alusrc_A_reg, exmem_alusrc_B_reg, exmem_branch_reg, exmem_jump_reg, exmem_update_flags_reg;

reg [63:0]     exmem_alu_dout_reg;                               


//Mem stage wires
wire [63:0]    mem_dout;                  

//--------------------------------------------------------------------------------------------------------------------------------------------------------------------//

// Mem-WB Stage

reg [63:0]     memwb_r2_data_reg, memwb_r1_data_reg;                                                       
reg [8:0]      memwb_pc_plus_1_reg, memwb_offset_reg;
reg [3:0]      memwb_passcond_reg, memwb_alu_op_reg;                                   //check its width
reg [8:0]      memwb_pc_reg;
reg [1:0]      memwb_thread_id;
reg [31:0]     memwb_inst;
reg [2:0]      memwb_r3_reg;  
reg            memwb_regwe_reg, memwb_memwe_reg, memwb_user_stall_reg, memwb_m2r_reg, memwb_noop_reg; 
reg            memwb_alusrc_A_reg, memwb_alusrc_B_reg, memwb_branch_reg, memwb_jump_reg, memwb_update_flags_reg;
reg [63:0]     memwb_alu_dout_reg;

reg [63:0]     memwb_mem_dout_reg;                  // wb_alu_data_reg not done 


// WB Stage Wires
wire [63:0]    wb_writeback_data;
               
assign wb_writeback_data      =     memwb_m2r_reg? memwb_mem_dout_reg   :   memwb_alu_dout_reg;
//PP COMMIT -BEGIN
wire[31:0] alu_flags ;

assign alu_flags = {16'b0, carry_flag3, overflow_flag3, zero_flag3, negative_flag3, carry_flag2, overflow_flag2, zero_flag2, negative_flag2, carry_flag1, overflow_flag1, zero_flag1, negative_flag1, carry_flag0, overflow_flag0, zero_flag0, negative_flag0};
//PP COMMIT -END
//--------------------------------------------------------------------------------------------------------------------------------------------------------------------//


//User stalling and break pointing logic
reg            user_pipe_overide_prev_reg;              
wire           pipe_en, user_pipe_en, user_pipe_overide_pulse, user_pipe_overide;                  //stalling logic for both user and instruction control of pipeline

assign user_pipe_en                 =        command_reg[0];                                                               // Enable when user wants to run the pipeline
assign user_pipe_overide            =        command_reg[30];                                                              // Enable when user wants to overide and enable a stalled pipeline
assign user_pipe_overide_pulse      =        user_pipe_overide && !user_pipe_overide_prev_reg;        // this pulse is produced every time command_reg[30] is pushed from 0 to 1
assign pipe_en                      =        user_pipe_overide_pulse || (user_pipe_en && !memwb_user_stall_reg);                // pulse is used to continue instruction stalled pipeline or single stepping instructions.

//--------------------------------------------------------------------------------------------------------------------------------------------------------------------//

//logic analyser assignments
assign la_arm                       =        command_reg[4];                           // command_reg=0x10 to arm LA
assign la_reset                     =        command_reg[5] | reset;                   // command_reg=0x20 to reset LA
assign la_trigger                   =        id_trigger;                         // instruction[31] bit is one hot coded for LA trigger

// IDK connected to REG int
wire [31:0] ctrl_status_0 = 32'b0;
wire [31:0] ctrl_status_1 = 32'b0;
wire [31:0] ctrl_status_2 = 32'b0;
wire [31:0] ctrl_status_3 = 32'b0;
wire [31:0] ctrl_status_4 = 32'b0;
wire [31:0] ctrl_status_5 = 32'b0;
wire [31:0] ctrl_status_6 = 32'b0;
wire [31:0] ctrl_status_7 = 32'b0;

/*                                                                      // Connect the wires to monitor when required
// LA monitor signals 
assign la_monitor_sig0     =     {mem_dout, imem_we, 25'b0, mem_addr[5:0]};                          
assign la_monitor_sig1     =     {3'b0, dmem_wea, 3'b0, dmem_web, la_trigger, 7'b0, dmem_addra[7:0], dmem_addrb[7:0], imem_din};
assign la_monitor_sig2     =     command_reg[7]? dmem_dinb : dmem_dina;                                
assign la_monitor_sig3     =     command_reg[7]? dmem_doutb : dmem_douta; 
*/      
                          
assign dpu_status          =     {7'b0, pc_in[8:0], 3'b0, pipe_en, 8'b0, 1'b0, la_status};   // status info - [24:16] - pc_reg | [12] - pipe_en | [2:0] - LA status - can add more status info in future

  
// Instantiate Logic Analyzer
logic_analyzer_bram la_inst (
   .monitor_sig0(la_monitor_sig0),
   .monitor_sig1(la_monitor_sig1),
   .monitor_sig2(la_monitor_sig2),
   .monitor_sig3(la_monitor_sig3),
   .trigger(la_trigger),
   .arm(la_arm),
   .la_read_addr(la_read_addr[5:0]),
   .la_status(la_status),
   .la_dout(la_dout),
   .clk(clk),
   .reset(la_reset)
);

// Instantiate the Instruction Memory
	// imem_32x512_v1 uut_imem (
	// 	.clk(clk), 
	// 	.din(mem_din_debug[31:0]),    	//controlled by debug
	// 	.addr(imem_addr),        	      //muxed for debug
	// 	.we(imem_we_debug),      	      //controlled by debug
	// 	.dout(imem_dout)         	      //tapped by debug
	// );

imem_multithread uut_imem_multithread(
	.addra(imem_addr),
	.addrb(ex_alu_dout[10:0]),
	.clka(clk),
	.clkb(clk),
	.dina(mem_din_debug[31:0]),
	.dinb(32'b0),
	.douta(imem_dout),
	.doutb(if_imem_dout_B),
	.wea(imem_we_debug),
	.web(1'b0)
);


// Instantiation of instruction decoder
decoder_dpu_v1 uut_decoder(
.instr(imem_dout),
.alusrc_A(id_alusrc_A),
.alusrc_B(id_alusrc_B),
.aluctrl(id_alu_op),
.branch(id_branch),
.regwrite(id_regwe),
.dmemwrite(id_memwe),
.jump(id_jump),
.passcond(id_passcond),
.memtoreg(id_m2r),
.noop(id_noop),
.update_flags(id_update_flags)
);


regfile_8 register_file0 (
    .clk(clk),
    .clr(reset),
    .raddr0(id_reg1_addr),             // muxed for debug
    .raddr1(id_r2),
    .waddr(memwb_r3_reg),
    .wdata(wb_writeback_data),
    .wea(memwb_regwe_reg && (memwb_thread_id == 2'd0)),
    .rdata0(id_r1_data0),
    .rdata1(id_r2_data0)
);

regfile_8 register_file1 (
    .clk(clk),
    .clr(reset),
    .raddr0(id_reg1_addr),             // muxed for debug
    .raddr1(id_r2),
    .waddr(memwb_r3_reg),
    .wdata(wb_writeback_data),
    .wea(memwb_regwe_reg && (memwb_thread_id == 2'd1)),
    .rdata0(id_r1_data1),
    .rdata1(id_r2_data1)
);

regfile_8 register_file2 (
    .clk(clk),
    .clr(reset),
    .raddr0(id_reg1_addr),             // muxed for debug
    .raddr1(id_r2),
    .waddr(memwb_r3_reg),
    .wdata(wb_writeback_data),
    .wea(memwb_regwe_reg && (memwb_thread_id == 2'd2)),
    .rdata0(id_r1_data2),
    .rdata1(id_r2_data2)
);

regfile_8 register_file3 (
    .clk(clk),
    .clr(reset),
    .raddr0(id_reg1_addr),             // muxed for debug
    .raddr1(id_r2),
    .waddr(memwb_r3_reg),
    .wdata(wb_writeback_data),
    .wea(memwb_regwe_reg && (memwb_thread_id == 2'd3)),
    .rdata0(id_r1_data3),
    .rdata1(id_r2_data3)
);


// Instantiate the ALU
alu_32bit alu_uut(
   .a(ex_alu_input1[31:0]),
   .b(ex_alu_input2[31:0]),
   .alu_ctrl(idex_alu_op_reg),
   .alu_out(ex_alu_dout[31:0]),
   .v_flag(alu_overflow),
   .c_flag(alu_carry),
   .n_flag(alu_negative),
   .z_flag(alu_zero)
);


// Instantiating passdecoder 
passdecoder uut_passdecode(
   .compbits(idex_passcond_reg),
   .N(negative_flag_in),
   .Z(zero_flag_in),
   .V(overflow_flag_in),
   .C(carry_flag_in),
   .pass(ex_pass)
);


// Instantiate the dmem	
	dmem_64x256_v1 uut_dmem(
	.addra(ex_alu_dout[7:0]),
	.addrb(mem_addr_debug[7:0]),     //controlled by debug - Port B is for debug
	.clka(clk),
	.clkb(clk),
	.dina(idex_r2_data_reg),
	.dinb(mem_din_debug),      //controlled by debug
	.douta(mem_dout),
	.doutb(dmem_doutb),    //controlled by debug
	.wea(idex_memwe_reg),
	.web(dmem_web)         //controlled by debug
	);

//--------------------------------------------------------------------------------------------------------------------------------------------------------------------//

// Multithreading PC selection logic
always @(*) begin
   case (thread_en)
      2'd0 : pc_in = {{2'b00}, pc_reg0};
      2'd1 : pc_in = {{2'b01}, pc_reg1};
      2'd2 : pc_in = {{2'b10}, pc_reg2};
      2'd3 : pc_in = {{2'b11}, pc_reg3};
      default : pc_in = {{2'b00}, pc_reg0};
   endcase
end

// Regfile rs1 and rs2 data output selection logic
always @(*) begin
   if (!debug) begin
      case (ifid_thread_id)
         2'd0 : begin
            id_r1_data_out = id_r1_data0;
            id_r2_data_out = id_r2_data0;
         end
         2'd1 : begin
            id_r1_data_out = id_r1_data1;
            id_r2_data_out = id_r2_data1;
         end
         2'd2 : begin
            id_r1_data_out = id_r1_data2;
            id_r2_data_out = id_r2_data2;
         end
         2'd3 : begin
            id_r1_data_out = id_r1_data3;
            id_r2_data_out = id_r2_data3;
         end
         default : begin
            id_r1_data_out = id_r1_data0;
            id_r2_data_out = id_r2_data0;
         end
      endcase
   end else begin
      case (mem_addr_debug[4:3])
         2'd0 : begin
            id_r1_data_out = id_r1_data0;
            id_r2_data_out = id_r2_data0;
         end
         2'd1 : begin
            id_r1_data_out = id_r1_data1;
            id_r2_data_out = id_r2_data1;
         end
         2'd2 : begin
            id_r1_data_out =  id_r1_data2;
            id_r2_data_out = id_r2_data2;
         end
         2'd3 : begin
            id_r1_data_out = id_r1_data3;
            id_r2_data_out = id_r2_data3;
         end
         default : begin
            id_r1_data_out = id_r1_data0;
            id_r2_data_out = id_r2_data0;
         end
      endcase
   end
end

// Passdecoder input selection logic
always @(*) begin
   case (idex_thread_id)
      2'd0 : begin
         carry_flag_in = carry_flag0;
         zero_flag_in = zero_flag0;
         negative_flag_in = negative_flag0;
         overflow_flag_in = overflow_flag0;
      end
      2'd1 : begin
         carry_flag_in = carry_flag1;
         zero_flag_in = zero_flag1;
         negative_flag_in = negative_flag1;
         overflow_flag_in = overflow_flag1;
      end
      2'd2 : begin
         carry_flag_in = carry_flag2;
         zero_flag_in = zero_flag2;
         negative_flag_in = negative_flag2;
         overflow_flag_in = overflow_flag2;
      end
      2'd3 : begin
         carry_flag_in = carry_flag3;
         zero_flag_in = zero_flag3;
         negative_flag_in = negative_flag3;
         overflow_flag_in = overflow_flag3;
      end
      default : begin
         carry_flag_in = carry_flag0;
         zero_flag_in = zero_flag0;
         negative_flag_in = negative_flag0;
         overflow_flag_in = overflow_flag0;
      end
   endcase
end


always @(posedge clk) begin   
   if (reset) begin         
      user_pipe_overide_prev_reg    <=          0;
      pc_reg0                       <=          0;
      pc_reg1                       <=          0;
      pc_reg2                       <=          0;
      pc_reg3                       <=          0;
      thread_en                     <=          0;

      ifid_pc_reg                   <=          0;
      ifid_thread_id                <=          0;

      id_r1_data_out_latched        <=          0;
      id_r2_data_out_latched        <=          0;

      idex_pc_reg                   <=          0;
      idex_thread_id                <=          0;
      idex_inst                     <=          0;
      idex_offset_reg               <=          0;
      idex_user_stall_reg           <=          0;
	   idex_r1_data_reg              <=          0; 
      idex_r2_data_reg              <=          0;          
      idex_r3_reg                   <=          0;
      idex_regwe_reg                <=          0;
      idex_memwe_reg                <=          0;
      idex_m2r_reg                  <=          0;
      idex_alusrc_A_reg             <=          0;
      idex_alusrc_B_reg             <=          0;
      idex_branch_reg               <=          0;
      idex_jump_reg                 <=          0;
      idex_alu_op_reg               <=          0;
      idex_passcond_reg             <=          0;
      idex_noop_reg                 <=          0;
      idex_update_flags_reg         <=          0;

      carry_flag0                    <=          0; 
      zero_flag0                     <=          0;
      negative_flag0                 <=          0;
      overflow_flag0                 <=          0;
      carry_flag1                    <=          0; 
      zero_flag1                     <=          0;
      negative_flag1                 <=          0;
      overflow_flag1                 <=          0;
      carry_flag2                    <=          0; 
      zero_flag2                     <=          0;
      negative_flag2                 <=          0;
      overflow_flag2                 <=          0;
      carry_flag3                    <=          0; 
      zero_flag3                     <=          0;
      negative_flag3                 <=          0;
      overflow_flag3                 <=          0;

      exmem_pc_reg                  <=          0;
      exmem_thread_id               <=          0;
      exmem_inst                    <=          0;
      exmem_user_stall_reg          <=          0;
	   exmem_r2_data_reg             <=          0;
      exmem_alu_dout_reg            <=          0;
      exmem_r3_reg                  <=          0;
      exmem_regwe_reg               <=          0;
      exmem_memwe_reg               <=          0;
      exmem_m2r_reg                 <=          0;
      exmem_noop_reg                <=          0;

      memwb_pc_reg                  <=          0;
      memwb_thread_id               <=          0;
      memwb_inst                    <=          0;
      memwb_user_stall_reg          <=          0;
	   memwb_regwe_reg               <=          0;
      memwb_r3_reg                  <=          0;
      memwb_mem_dout_reg            <=          0;
      memwb_m2r_reg                 <=          0;
      memwb_alu_dout_reg            <=          0;
      memwb_noop_reg                <=          0;

      // Add all other registers in the module so they get reset
   end 
   else begin       
      user_pipe_overide_prev_reg    <=          user_pipe_overide;            // these are control registers which update above the pipeline - used to enable or stall pipeline

      id_r1_data_out_latched     <=          id_r1_data_out;
      id_r2_data_out_latched     <=          id_r2_data_out;

      if(pipe_en) begin                                                       // this segment updates the pipeline registers
         pc_reg0 <= (thread_en == 2'd0) ? pc_next : pc_reg0;
         pc_reg1 <= (thread_en == 2'd1) ? pc_next : pc_reg1;
         pc_reg2 <= (thread_en == 2'd2) ? pc_next : pc_reg2;
         pc_reg3 <= (thread_en == 2'd3) ? pc_next : pc_reg3;
         thread_en <= (thread_en == 2'd3) ? 2'd0 : thread_en + 1;

         // Branch logic
         if (ex_jump || ex_branch_taken) begin
            case (idex_thread_id)
               2'd0 : pc_reg0 <= (ex_jump) ? idex_offset_reg : ex_alu_dout[8:0]; // if not jump, then must be branch
               2'd1 : pc_reg1 <= (ex_jump) ? idex_offset_reg : ex_alu_dout[8:0];
               2'd2 : pc_reg2 <= (ex_jump) ? idex_offset_reg : ex_alu_dout[8:0];
               2'd3 : pc_reg3 <= (ex_jump) ? idex_offset_reg : ex_alu_dout[8:0];
            endcase
         end
         
         ifid_pc_reg                <=          pc_in[8:0];
         ifid_thread_id             <=          thread_en;

         idex_pc_reg                <=          ifid_pc_reg;
         idex_thread_id             <=          ifid_thread_id;
         idex_inst                  <=          imem_dout;
         idex_r1_data_reg           <=          id_r1_data_out;
         idex_r2_data_reg           <=          id_r2_data_out;
         idex_r3_reg                <=          id_r3;
         idex_offset_reg            <=          id_offset;                    // ID-EX stage logic updates
         idex_m2r_reg               <=          id_m2r;
         idex_alusrc_A_reg          <=          id_alusrc_A;
         idex_alusrc_B_reg          <=          id_alusrc_B;
         idex_alu_op_reg            <=          id_alu_op;
         idex_passcond_reg          <=          id_passcond;                           
         idex_user_stall_reg        <=          id_user_stall;      
         idex_regwe_reg             <=          id_regwe; 
         idex_memwe_reg             <=          id_memwe; 
         idex_branch_reg            <=          id_branch; 
         idex_jump_reg              <=          id_jump;
         idex_noop_reg              <=          id_noop; 
         idex_update_flags_reg      <=          id_update_flags;

         if((!idex_noop_reg)&&(idex_update_flags_reg)) begin
            case (idex_thread_id)
               2'd0 : begin
                  carry_flag0              <=          alu_carry; 
                  zero_flag0               <=          alu_zero;                            // FLAG registers updates
                  negative_flag0           <=          alu_negative;
                  overflow_flag0           <=          alu_overflow;
               end
               2'd1 : begin
                  carry_flag1              <=          alu_carry; 
                  zero_flag1               <=          alu_zero;                            // FLAG registers updates
                  negative_flag1           <=          alu_negative;
                  overflow_flag1           <=          alu_overflow;
               end
               2'd2 : begin
                  carry_flag2              <=          alu_carry; 
                  zero_flag2               <=          alu_zero;                            // FLAG registers updates
                  negative_flag2           <=          alu_negative;
                  overflow_flag2           <=          alu_overflow;
               end
               2'd3 : begin
                  carry_flag3              <=          alu_carry; 
                  zero_flag3               <=          alu_zero;                            // FLAG registers updates
                  negative_flag3           <=          alu_negative;
                  overflow_flag3           <=          alu_overflow;
               end
            endcase
         end

         exmem_pc_reg               <=          idex_pc_reg;
         exmem_thread_id            <=          idex_thread_id;
         exmem_inst                 <=          idex_inst;
         exmem_r2_data_reg          <=          idex_r2_data_reg; //connect directly no latch
         exmem_alu_dout_reg         <=          ex_alu_dout;
         exmem_r3_reg               <=          idex_r3_reg;
         exmem_m2r_reg              <=          idex_m2r_reg;
         exmem_user_stall_reg       <=          idex_user_stall_reg;
         exmem_regwe_reg            <=          idex_regwe_reg        &&    ex_pass;
         exmem_memwe_reg            <=          idex_memwe_reg        &&    ex_pass;              
         exmem_noop_reg             <=          idex_noop_reg;                            // EX-Mem stage logic updates

         memwb_pc_reg               <=          exmem_pc_reg;
         memwb_thread_id            <=          exmem_thread_id;
         memwb_inst                 <=          exmem_inst;
         memwb_m2r_reg              <=          exmem_m2r_reg;
         memwb_alu_dout_reg         <=          exmem_alu_dout_reg;
         memwb_user_stall_reg       <=          exmem_user_stall_reg;
         memwb_regwe_reg            <=          exmem_regwe_reg;
         memwb_r3_reg               <=          exmem_r3_reg;
         memwb_mem_dout_reg         <=          mem_dout;                     // Mem-WB stage logic updates
         memwb_noop_reg             <=          exmem_noop_reg;

         // add all the registers to be updated only if pipe_en active, else values will be held same. 
      end
   end
end


// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------//


 generic_regs
   #( 
      .UDP_REG_SRC_WIDTH   (UDP_REG_SRC_WIDTH),
      .TAG                 (`IDS_BLOCK_ADDR),          // Tag -- eg. MODULE_TAG
      .REG_ADDR_WIDTH      (`IDS_REG_ADDR_WIDTH),     // Width of block addresses -- eg. MODULE_REG_ADDR_WIDTH
      .NUM_COUNTERS        (0),                 // Number of counters
      .NUM_SOFTWARE_REGS   (5),                 // Number of sw regs
      .NUM_HARDWARE_REGS   (16)                  // Number of hw regs
   ) module_regs (
      .reg_req_in       (reg_req_in),
      .reg_ack_in       (reg_ack_in),
      .reg_rd_wr_L_in   (reg_rd_wr_L_in),
      .reg_addr_in      (reg_addr_in),
      .reg_data_in      (reg_data_in),
      .reg_src_in       (reg_src_in),

      .reg_req_out      (reg_req_out),
      .reg_ack_out      (reg_ack_out),
      .reg_rd_wr_L_out  (reg_rd_wr_L_out),
      .reg_addr_out     (reg_addr_out),
      .reg_data_out     (reg_data_out),
      .reg_src_out      (reg_src_out),

      // --- counters interface
      .counter_updates  (),
      .counter_decrement(),

      // --- SW regs interface
      .software_regs    ({ 
                           la_read_addr,   
                           mem_din_debug[63:32], 
                           mem_din_debug[31:0], 
                           mem_addr_debug, 
                           command_reg
                           }),

      // --- HW regs interface
      .hardware_regs    ({ alu_flags,
                           ctrl_status_7,              // HW REG 15 - Pipeline health + flags
                           ctrl_status_6,              // HW REG 14 - MEM/WB control
                           ctrl_status_5,              // HW REG 13 - EX/MEM data
                           ctrl_status_4,              // HW REG 12 - EX/MEM control
                           ctrl_status_3,              // HW REG 11 - ID/EX data
                           ctrl_status_2,              // HW REG 10 - ID/EX control
                           ctrl_status_1,              // HW REG  9 - ID stage control
                           ctrl_status_0,              // HW REG  8 - IF/ID stage
                           wb_writeback_data[31:0],    // HW REG  7 - WB writeback data
                           ex_alu_dout[31:0],          // HW REG  6 - EX ALU output
                           dpu_status,                 // HW REG  5 - status info - [24:16] - pc_reg | [12] - pipe_en | [2:0] - LA status - can add more status info in future
                           id_r2_data_out_latched[31:0],           // HW REG  4 - ID stage R2 data
                           id_r1_data_out_latched[31:0],           // HW REG  3 - ID stage R1 data
                           mem_dout[31:0],             // HW REG  2 - MEM stage data out
                           dmem_doutb[31:0],           // HW REG  1 - DMEM debug port B
                           imem_dout                   // HW REG  0 - IF stage instruction
                        }),

      .clk              (clk),
      .reset            (reset)
    );

endmodule
