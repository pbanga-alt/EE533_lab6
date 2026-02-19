
module M32bitwide (input [63:0] D0,
	     input [63:0] D1,
	     input S0,
	     output [63:0] O);

assign O = S0?D1:D0;

endmodule
