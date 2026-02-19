////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 1995-2008 Xilinx, Inc.  All rights reserved.
////////////////////////////////////////////////////////////////////////////////
//   ____  ____ 
//  /   /\/   / 
// /___/  \  /    Vendor: Xilinx 
// \   \   \/     Version : 10.1
//  \   \         Application : sch2verilog
//  /   /         Filename : regfile_64bit.vf
// /___/   /\     Timestamp : 02/12/2026 17:35:27
// \   \  /  \ 
//  \___\/\___\ 
//
//Command: C:\Xilinx\10.1\ISE\bin\nt\unwrapped\sch2verilog.exe -intstyle ise -family virtex2p -w "C:/Documents and Settings/student/registerfile/regfile_64bit.sch" regfile_64bit.vf
//Design Name: regfile_64bit
//Device: virtex2p
//Purpose:
//    This verilog netlist is translated from an ECS schematic.It can be 
//    synthesized and simulated, but it should not be modified. 
//
`timescale 1ns / 1ps

module D2_4E_MXILINX_regfile_64bit(A0, 
                                   A1, 
                                   E, 
                                   D0, 
                                   D1, 
                                   D2, 
                                   D3);

    input A0;
    input A1;
    input E;
   output D0;
   output D1;
   output D2;
   output D3;
   
   
   AND3 I_36_30 (.I0(A1), 
                 .I1(A0), 
                 .I2(E), 
                 .O(D3));
   AND3B1 I_36_31 (.I0(A0), 
                   .I1(A1), 
                   .I2(E), 
                   .O(D2));
   AND3B1 I_36_32 (.I0(A1), 
                   .I1(A0), 
                   .I2(E), 
                   .O(D1));
   AND3B2 I_36_33 (.I0(A0), 
                   .I1(A1), 
                   .I2(E), 
                   .O(D0));
endmodule
`timescale 1ns / 1ps

module regfile_64bit(clk, 
                     clr, 
                     raddr0, 
                     raddr1, 
                     waddr, 
                     wdata, 
                     wea, 
                     rdata0, 
                     rdata1);

    input clk;
    input clr;
    input [1:0] raddr0;
    input [1:0] raddr1;
    input [1:0] waddr;
    input [63:0] wdata;
    input wea;
   output [63:0] rdata0;
   output [63:0] rdata1;
   
   wire XLXN_1;
   wire XLXN_2;
   wire [63:0] XLXN_5;
   wire XLXN_6;
   wire [63:0] XLXN_10;
   wire [63:0] XLXN_11;
   wire [63:0] XLXN_12;
   wire XLXN_35;
   
   D2_4E_MXILINX_regfile_64bit XLXI_5 (.A0(waddr[0]), 
                                       .A1(waddr[1]), 
                                       .E(wea), 
                                       .D0(XLXN_1), 
                                       .D1(XLXN_2), 
                                       .D2(XLXN_35), 
                                       .D3(XLXN_6));
   // synthesis attribute HU_SET of XLXI_5 is "XLXI_5_0"
   reg64 XLXI_9 (.ce(XLXN_6), 
                 .clk(clk), 
                 .clr(clr), 
                 .d(wdata[63:0]), 
                 .q(XLXN_12[63:0]));
   reg64 XLXI_10 (.ce(XLXN_35), 
                  .clk(clk), 
                  .clr(clr), 
                  .d(wdata[63:0]), 
                  .q(XLXN_11[63:0]));
   reg64 XLXI_11 (.ce(XLXN_2), 
                  .clk(clk), 
                  .clr(clr), 
                  .d(wdata[63:0]), 
                  .q(XLXN_10[63:0]));
   reg64 XLXI_12 (.ce(XLXN_1), 
                  .clk(clk), 
                  .clr(clr), 
                  .d(wdata[63:0]), 
                  .q(XLXN_5[63:0]));
   mux4to1_64bit XLXI_13 (.I0(XLXN_5[63:0]), 
                          .I1(XLXN_10[63:0]), 
                          .I2(XLXN_11[63:0]), 
                          .I3(XLXN_12[63:0]), 
                          .S0(raddr0[0]), 
                          .S1(raddr0[1]), 
                          .S(rdata0[63:0]));
   mux4to1_64bit XLXI_14 (.I0(XLXN_5[63:0]), 
                          .I1(XLXN_10[63:0]), 
                          .I2(XLXN_11[63:0]), 
                          .I3(XLXN_12[63:0]), 
                          .S0(raddr1[0]), 
                          .S1(raddr1[1]), 
                          .S(rdata1[63:0]));
endmodule
