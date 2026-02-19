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
reg [8:0]      pc_reg;                                                      // The code progression is like a data path along the signal route: origin to destination. Just follow the trail to troubleshoot.

// IF stage wires
wire [31:0]    imem_dout;                                            
wire [8:0]     imem_addr, if_pc_plus_1;

assign         if_pc_plus_1   =  pc_reg + 1;
assign         imem_addr = debug? mem_addr_debug[8:0] : pc_reg;             //debug mux

//--------------------------------------------------------------------------------------------------------------------------------------------------------------------//
// IF-ID Stage
reg [31:0]     ifid_instruc_reg;
reg [8:0]      ifid_pc_plus_1_reg;                                          // carrying the pc+1 to compute the branch address in ex                                             


// ID Stage wires
wire [63:0]    id_r2_data, id_r1_data;
wire [8:0]     id_offset;
wire [3:0]     id_alu_op, id_passcond;                                       // Have to confirm the ALU opcode width with redesign
wire [2:0]     id_r1, id_r2, id_r3, id_reg1_addr;                            //Connected with register module 
wire           id_regwe, id_memwe, id_user_stall, id_m2r, id_trigger;                         // Control Signals
wire           id_alusrc_A, id_alusrc_B, id_branch, id_jump, id_noop, id_update_flags;

assign id_r1            =     ifid_instruc_reg[12:10];
assign id_r2            =     ifid_instruc_reg[15:13];
assign id_r3            =     ifid_instruc_reg[18:16];                      // no reg_dst signal in the design as we use dedicated bits for destination register
assign id_offset        =     ifid_instruc_reg[27:19];                      // 9 bit offset used for both branch, jump and immediate instructions
assign id_user_stall    =     ifid_instruc_reg[30];
assign id_trigger       =     ifid_instruc_reg[31];

assign id_reg1_addr     =  debug? mem_addr_debug[2:0] : id_r1;             //debug mux

//--------------------------------------------------------------------------------------------------------------------------------------------------------------------//

// ID-EX Stage Register
reg [63:0]     idex_r2_data_reg, idex_r1_data_reg;                                                       
reg [8:0]      idex_pc_plus_1_reg, idex_offset_reg;
reg [3:0]      idex_passcond_reg, idex_alu_op_reg;                                   //check its width
reg [2:0]      idex_r3_reg;  
reg            idex_regwe_reg, idex_memwe_reg, idex_user_stall_reg, idex_m2r_reg, idex_noop_reg; 
reg            idex_alusrc_A_reg, idex_alusrc_B_reg, idex_branch_reg, idex_jump_reg, idex_update_flags_reg;

// Ex stage wires and Flags
reg            carry_flag, zero_flag, negative_flag, overflow_flag;                                      // FLAG Registers
wire           alu_carry, alu_zero, alu_negative, alu_overflow;                                          // output of alu feeding into FLAG registers
wire[63:0]     ex_alu_input2, ex_alu_input1, ex_alu_dout;                //connect with ALU and pass decoder
wire           ex_branch_taken, ex_pass, ex_jump;                                                                                                 


assign ex_alu_input1             =        idex_alusrc_A_reg?      {{55{1'b0}}, idex_pc_plus_1_reg}                 :       idex_r1_data_reg;         
assign ex_alu_input2             =        idex_alusrc_B_reg?      {{55{idex_offset_reg[8]}}, idex_offset_reg}      :       idex_r2_data_reg;                         
assign ex_branch_taken           =        idex_branch_reg      &&    ex_pass;
assign ex_jump                   =        idex_jump_reg;

assign ex_alu_dout[63:32]        =        32'b0;                     // remove it later for extension to 64bit designs.

//--------------------------------------------------------------------------------------------------------------------------------------------------------------------//

// Ex-Mem Stage Registers
reg [63:0]     exmem_r2_data_reg, exmem_r1_data_reg;                                                       
reg [8:0]      exmem_pc_plus_1_reg, exmem_offset_reg;
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
reg [2:0]      memwb_r3_reg;  
reg            memwb_regwe_reg, memwb_memwe_reg, memwb_user_stall_reg, memwb_m2r_reg, memwb_noop_reg; 
reg            memwb_alusrc_A_reg, memwb_alusrc_B_reg, memwb_branch_reg, memwb_jump_reg, memwb_update_flags_reg;
reg [63:0]     memwb_alu_dout_reg;

reg [63:0]     memwb_mem_dout_reg;                  // wb_alu_data_reg not done 


// WB Stage Wires
wire [63:0]    wb_writeback_data;
               
assign wb_writeback_data      =     memwb_m2r_reg? memwb_mem_dout_reg   :   memwb_alu_dout_reg;

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

/*                                                                      // Connect the wires to monitor when required
// LA monitor signals 
assign la_monitor_sig0     =     {mem_dout, imem_we, 25'b0, mem_addr[5:0]};                          
assign la_monitor_sig1     =     {3'b0, dmem_wea, 3'b0, dmem_web, la_trigger, 7'b0, dmem_addra[7:0], dmem_addrb[7:0], imem_din};
assign la_monitor_sig2     =     command_reg[7]? dmem_dinb : dmem_dina;                                
assign la_monitor_sig3     =     command_reg[7]? dmem_doutb : dmem_douta; 
*/      
                          
assign dpu_status          =     {7'b0, pc_reg, 3'b0, pipe_en, 8'b0, 1'b0, la_status};   // status info - [24:16] - pc_reg | [12] - pipe_en | [2:0] - LA status - can add more status info in future

  
//--------------------------------------------------------------------------------------------------------------------------------------------------------------------//
/*
///////////////////////////////////////////////////////////////////////////////
// Control Signal Monitor - Wire Assignments
///////////////////////////////////////////////////////////////////////////////

// Control status monitor wires
wire [31:0]  ctrl_status_0, ctrl_status_1, ctrl_status_2, ctrl_status_3;
wire [31:0]  ctrl_status_4, ctrl_status_5, ctrl_status_6, ctrl_status_7;

// HW REG 8 - IF/ID Stage
assign ctrl_status_0 = {
   id_trigger,                  // [31]    LA trigger
   id_user_stall,               // [30]    User stall bit
   ifid_instruc_reg[29],        // [29]    S bit (update flags)
   5'b0,                        // [28:24] spare
   id_r3,                       // [23:21] destination register
   id_r2,                       // [20:18] source register 2
   5'b0,                        // [17:13] spare
   id_r1,                       // [12:10] source register 1
   id_noop,                     // [9]     noop flag
   id_passcond,                 // [8:5]   condition code
   ifid_instruc_reg[4:0]        // [4:0]   opcode
};

// HW REG 9 - ID Stage Control Signals
assign ctrl_status_1 = {
   22'b0,                       // [31:10] spare
   id_alusrc_B,                 // [9]     ALU src B select (I-bit)
   id_alusrc_A,                 // [8]     ALU src A select
   id_branch,                   // [7]     branch signal
   id_jump,                     // [6]     jump signal
   id_m2r,                      // [5]     memory to register
   id_memwe,                    // [4]     data memory write enable
   id_regwe,                    // [3]     register file write enable
   id_noop,                     // [2]     noop flag
   id_user_stall,               // [1]     user stall
   id_trigger                   // [0]     LA trigger
};

// HW REG 10 - ID/EX Stage Control Signals
assign ctrl_status_2 = {
   22'b0,                       // [31:10] spare
   idex_alusrc_B_reg,           // [9]     ALU src B carried to EX
   idex_alusrc_A_reg,           // [8]     ALU src A carried to EX
   idex_branch_reg,             // [7]     branch in EX stage
   idex_jump_reg,               // [6]     jump in EX stage
   idex_m2r_reg,                // [5]     load select in EX stage
   idex_memwe_reg,              // [4]     mem write enable in EX
   idex_regwe_reg,              // [3]     reg write enable in EX
   idex_noop_reg,               // [2]     noop flag in EX
   idex_user_stall_reg,         // [1]     user stall in EX
   1'b0                    // [0]     flush signal (branch or jump)
};

// HW REG 11 - ID/EX Stage Data
// Total: 9+3+2+9+4+4+1 = 32 bits exactly
assign ctrl_status_3 = {
   idex_offset_reg,             // [31:23] 9-bit sign-extended immediate
   idex_r3_reg,                 // [22:20] destination register in EX
   2'b0,                        // [19:18] spare
   idex_pc_plus_1_reg,          // [17:9]  full 9-bit PC+1
   idex_alu_op_reg,             // [8:5]   ALU control opcode
   idex_passcond_reg,            // [4:1]   condition code in EX
   1'b0                         // [0]     spare
};

// HW REG 12 - EX/MEM Stage Control Signals
assign ctrl_status_4 = {
   23'b0,                       // [31:9]  spare
   ex_branch_taken,             // [8]     branch resolved and taken
   ex_jump,                     // [7]     jump active
   1'b0,                    // [6]     flush active
   exmem_m2r_reg,               // [5]     load select in MEM
   exmem_memwe_reg,             // [4]     mem write enable in MEM
   exmem_regwe_reg,             // [3]     reg write enable in MEM
   exmem_noop_reg,              // [2]     noop flag in MEM
   exmem_user_stall_reg,        // [1]     user stall in MEM
   ex_pass                      // [0]     pass decoder output
};

// HW REG 13 - EX/MEM Stage Data
assign ctrl_status_5 = {
   exmem_r3_reg,                // [31:29] destination register in MEM
   21'b0,                       // [28:8]  spare
   exmem_alu_dout_reg[7:0]      // [7:0]   lower 8 bits = dmem address
};

// HW REG 14 - MEM/WB Stage Control Signals
assign ctrl_status_6 = {
   24'b0,                       // [31:8]  spare
   memwb_m2r_reg,               // [7]     load select in WB
   1'b0,                        // [6]     spare
   memwb_regwe_reg,             // [5]     reg write enable in WB
   memwb_noop_reg,              // [4]     noop flag in WB
   memwb_user_stall_reg,        // [3]     user stall in WB - gates pipe_en
   memwb_r3_reg                 // [2:0]   destination register in WB
};

// HW REG 15 - Pipeline Health + Flags
assign ctrl_status_7 = {
   pipe_en,                     // [31]    pipeline enable
   user_pipe_overide,           // [30]    user override
   user_pipe_en,                // [29]    user pipeline enable
   user_pipe_overide_pulse,     // [28]    one-shot override pulse
   pc_reg,                      // [27:19] full 9-bit PC
   3'b0,                        // [18:16] spare
   3'b0,                        // [15:13] spare
   3'b0,                        // [12:10] spare
   ex_branch_taken,             // [9]     branch taken
   ex_jump,                     // [8]     jump active
   1'b0,                    // [7]     flush active
   3'b0,                        // [6:4]   spare
   carry_flag,                  // [3]     carry flag
   overflow_flag,               // [2]     overflow flag
   negative_flag,               // [1]     negative flag
   zero_flag                    // [0]     zero flag
};


*/

//--------------------------------------------------------------------------------------------------------------------------------------------------------------------//

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
	imem_32x512_v1 uut_imem (
		.clk(clk), 
		.din(mem_din_debug[31:0]),    	//controlled by debug
		.addr(imem_addr),        	      //muxed for debug
		.we(imem_we_debug),      	      //controlled by debug
		.dout(imem_dout)         	      //tapped by debug
	);


// Instantiation of instruction decoder
decoder_dpu_v1 uut_decoder(
.instr(ifid_instruc_reg),
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


regfile_64bit register_file (
    .clk(clk),
    .clr(reset),
    .raddr0(id_reg1_addr),             // muxed for debug
    .raddr1(id_r2),
    .waddr(memwb_r3_reg),
    .wdata(wb_writeback_data),
    .wea(memwb_regwe_reg),
    .rdata0(id_r1_data),
    .rdata1(id_r2_data)
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
   .N(negative_flag),
   .Z(zero_flag),
   .V(overflow_flag),
   .C(carry_flag),
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

always @(posedge clk) begin   
   if (reset) begin         
      user_pipe_overide_prev_reg    <=          0;
      pc_reg                        <=          0;
      ifid_pc_plus_1_reg            <=          0;
	   ifid_instruc_reg              <=          0;

      idex_pc_plus_1_reg            <=          0;
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

      carry_flag                    <=          0; 
      zero_flag                     <=          0;
      negative_flag                 <=          0;
      overflow_flag                 <=          0;

      exmem_user_stall_reg          <=          0;
	   exmem_r2_data_reg             <=          0;
      exmem_alu_dout_reg            <=          0;
      exmem_r3_reg                  <=          0;
      exmem_regwe_reg               <=          0;
      exmem_memwe_reg               <=          0;
      exmem_m2r_reg                 <=          0;
      exmem_noop_reg                <=          0;


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

      if(pipe_en) begin                                                       // this segment updates the pipeline registers
         if(ex_jump)
            pc_reg                  <=          idex_offset_reg;
         else if(ex_branch_taken)
            pc_reg                  <=          ex_alu_dout[8:0];
         else
            pc_reg                  <=          if_pc_plus_1;                 // Program counter update and branching logic with higher priority to jump

         
         
         ifid_instruc_reg           <=          imem_dout;                    // IF-ID stage logic updates
         ifid_pc_plus_1_reg         <=          if_pc_plus_1;

         //idex_pc_plus_1_reg         <=          ifid_pc_plus_1_reg;
         idex_r1_data_reg           <=          id_r1_data;
         idex_r2_data_reg           <=          id_r2_data;   
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
            carry_flag              <=          alu_carry; 
            zero_flag               <=          alu_zero;                            // FLAG registers updates
            negative_flag           <=          alu_negative;
            overflow_flag           <=          alu_overflow;
         end

         exmem_r2_data_reg          <=          idex_r2_data_reg; //connect directly no latch
         exmem_alu_dout_reg         <=          ex_alu_dout;
         exmem_r3_reg               <=          idex_r3_reg;
         exmem_m2r_reg              <=          idex_m2r_reg;
         exmem_user_stall_reg       <=          idex_user_stall_reg;
         exmem_regwe_reg            <=          idex_regwe_reg        &&    ex_pass;
         exmem_memwe_reg            <=          idex_memwe_reg        &&    ex_pass;              
         exmem_noop_reg             <=          idex_noop_reg;                            // EX-Mem stage logic updates

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
      .hardware_regs    ({
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
                           id_r2_data[31:0],           // HW REG  4 - ID stage R2 data
                           id_r1_data[31:0],           // HW REG  3 - ID stage R1 data
                           mem_dout[31:0],             // HW REG  2 - MEM stage data out
                           dmem_doutb[31:0],           // HW REG  1 - DMEM debug port B
                           imem_dout                   // HW REG  0 - IF stage instruction
                        }),

      .clk              (clk),
      .reset            (reset)
    );

endmodule
