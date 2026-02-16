`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    16:23:46 02/13/2026 
// Design Name: 
// Module Name:    decoder 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//


//////////////////////////////////////////////////////////////////////////////////
module decoder( input[31:0] instr,
					 output reg [2:0] aluctrl,
					 output alusrc,
					 output reg branch,
					 output reg regwrite,
					 output reg dmemwrite,
					 output reg jump,
					 output[3:0] passcond,
					 output reg memtoreg,
					 output trigger_debug,
					 output stall_pipeline,
					 output update_flags
					 //output[15:0] immediate_num
					 //output 
					 
    );

/*
Instruction format
opcode = instr[4:0]
cond = instr[8:5]
register source or immediate field = instr[9]
Source register 1 = instr[12:10]
Source register 2 = instr[15:13]
Destination register = instr[18:16]
Immediate number/offset field = [27:19]
Add/Sub offset = instr[28]
Update flags = instr[29]
Trigger_debug = instr[30]
Stall = instr[31]
*/

assign alusrc = instr[9];
assign passcond = instr[8:5];
assign trigger_debug = instr[30];
assign stall_pipeline = instr[31];
assign update_flags = instr[29];

always@(*)
	begin
		case(instr[4:0])
			5'd1: //ldr
					begin
						regwrite = 1;
						branch = 0;
						dmemwrite = 0;
						jump = 0;
						memtoreg = 1;
						aluctrl = {2'b00,instr[28]};
						//compare_flags = 0;			
					end
			5'd2: //str
					begin
						dmemwrite = 1;
						regwrite = 0;
						branch = 0;
						jump = 0;
						memtoreg = 0;
						aluctrl = {2'b00,instr[28]};
						//compare_flags = 0;
					end
			5'd3: //add
					begin
					   dmemwrite = 0;
						regwrite = 1;
						branch = 0;
						jump = 0;
						memtoreg = 0;
						aluctrl = 3'b000;
						end
			5'd4: //sub
					begin
					   dmemwrite = 0;
						regwrite = 1;
						branch = 0;
						jump = 0;
						memtoreg = 0;
						aluctrl = 3'b001;					
					end
			5'd5: //lsl
					begin
					   dmemwrite = 0;
						regwrite = 1;
						jump = 0;
						branch = 0;
						memtoreg = 0;
						aluctrl = 3'b010; // need to implement barrel shifter							
					end
			5'd6: //mov - implemented as an add I=1 immediate number = 0
					begin
					   dmemwrite = 0;
						regwrite = 1;
						branch = 0;
						jump = 0;
						memtoreg = 0;
						aluctrl = 3'b000;		
					end
			5'd7: //cmp
					begin
					   dmemwrite = 0;
						regwrite = 0;
						jump = 0;
						branch = 0;
						memtoreg = 0;
						aluctrl = 3'b001;					
					end
			5'd8: //branch
					begin
					   dmemwrite = 0;
						regwrite = 0;
						branch = 1;
						jump = 0;
						memtoreg = 0;
						aluctrl = 3'b000;								
					end
			5'd9: //jump
					begin
					   dmemwrite = 0;
						regwrite = 0;
						branch = 0;
						jump = 1;
						memtoreg = 0;
						aluctrl = 3'b000;								
					end
			default: 
					begin
					   dmemwrite = 0;
						regwrite = 0;
						branch = 0;
						jump = 0;
						memtoreg = 0;
						aluctrl = 3'b000;								
					end
		endcase
	end

endmodule
