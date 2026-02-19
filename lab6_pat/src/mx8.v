////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 1995-2008 Xilinx, Inc.  All rights reserved.
////////////////////////////////////////////////////////////////////////////////
//   ____  ____ 
//  /   /\/   / 
// /___/  \  /    Vendor: Xilinx 
// \   \   \/     Version : 10.1
//  \   \         Application : sch2verilog
//  /   /         Filename : mx8.vf
// /___/   /\     Timestamp : 02/09/2026 21:07:52
// \   \  /  \ 
//  \___\/\___\ 
//
//Command: C:\Xilinx\10.1\ISE\bin\nt\unwrapped\sch2verilog.exe -intstyle ise -family virtex2p -w "C:/Documents and Settings/student/Syncadder_8bit_schematic/mx8.sch" mx8.vf
//Design Name: mx8
//Device: virtex2p
//Purpose:
//    This verilog netlist is translated from an ECS schematic.It can be 
//    synthesized and simulated, but it should not be modified. 
//
`timescale 1ns / 1ps

module mx8(I0, 
           I1, 
           I2, 
           I3, 
           S0, 
           S1, 
           S);

    input [7:0] I0;
    input [7:0] I1;
    input [7:0] I2;
    input [7:0] I3;
    input S0;
    input S1;
   output [7:0] S;
   
   
   mux4to1 XLXI_1 (.I0(I0[0]), 
                   .I1(I1[0]), 
                   .I2(I2[0]), 
                   .I3(I3[0]), 
                   .S0(S0), 
                   .S1(S1), 
                   .S(S[0]));
   mux4to1 XLXI_2 (.I0(I0[1]), 
                   .I1(I1[1]), 
                   .I2(I2[1]), 
                   .I3(I3[1]), 
                   .S0(S0), 
                   .S1(S1), 
                   .S(S[1]));
   mux4to1 XLXI_3 (.I0(I0[2]), 
                   .I1(I1[2]), 
                   .I2(I2[2]), 
                   .I3(I3[2]), 
                   .S0(S0), 
                   .S1(S1), 
                   .S(S[2]));
   mux4to1 XLXI_4 (.I0(I0[3]), 
                   .I1(I1[3]), 
                   .I2(I2[3]), 
                   .I3(I3[3]), 
                   .S0(S0), 
                   .S1(S1), 
                   .S(S[3]));
   mux4to1 XLXI_5 (.I0(I0[4]), 
                   .I1(I1[4]), 
                   .I2(I2[4]), 
                   .I3(I3[4]), 
                   .S0(S0), 
                   .S1(S1), 
                   .S(S[4]));
   mux4to1 XLXI_6 (.I0(I0[5]), 
                   .I1(I1[5]), 
                   .I2(I2[5]), 
                   .I3(I3[5]), 
                   .S0(S0), 
                   .S1(S1), 
                   .S(S[5]));
   mux4to1 XLXI_7 (.I0(I0[6]), 
                   .I1(I1[6]), 
                   .I2(I2[6]), 
                   .I3(I3[6]), 
                   .S0(S0), 
                   .S1(S1), 
                   .S(S[6]));
   mux4to1 XLXI_8 (.I0(I0[7]), 
                   .I1(I1[7]), 
                   .I2(I2[7]), 
                   .I3(I3[7]), 
                   .S0(S0), 
                   .S1(S1), 
                   .S(S[7]));
endmodule
