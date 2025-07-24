package JTAG_Types;

import Vector :: *;

typedef Bit#(w) JTAGInstruction_t#(numeric type w);

typedef Vector#(n, JTAGInstruction_t#(w)) JTAG_TAP_Config_t#(numeric type n, numeric type w);

endpackage