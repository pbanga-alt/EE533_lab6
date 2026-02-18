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
   ex_flush                     // [0]     flush signal (branch or jump)
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
   ex_flush,                    // [6]     flush active
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
   ex_flush,                    // [7]     flush active
   3'b0,                        // [6:4]   spare
   carry_flag,                  // [3]     carry flag
   overflow_flag,               // [2]     overflow flag
   negative_flag,               // [1]     negative flag
   zero_flag                    // [0]     zero flag
};
