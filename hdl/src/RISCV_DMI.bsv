package RISCV_DMI;

typedef enum {
    DMI_NOP      = 2'b00,
    DMI_READ     = 2'b01,
    DMI_WRITE    = 2'b10,
    DMI_RESERVED = 2'b11
} DMI_Op_t deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(abits) address;
    Bit#(32)    data;
    DMI_Op_t    op;
} DMI_Scan_t#(numeric type abits) deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(abits) address;
    Bit#(32)    data;
    DMI_Op_t    op;
    Bit#(1)     epoch;
} DMI_Request_t#(numeric type abits) deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(abits) address;
    Bit#(32)    data;
    Bool        error;
    Bit#(1)     epoch;
} DMI_Response_t#(numeric type abits) deriving(Bits, Eq, FShow);

endpackage
