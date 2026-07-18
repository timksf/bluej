package RISCV_DM;

import DReg :: *;
import FIFOF :: *;
import GetPut :: *;
import ClientServer :: *;

import BlueCSRCore :: *;
import BlueCSRAXI4LiteAdapter :: *;

import AXI4_Lite_Types :: *;
import AXI4_Lite_Master :: *;
import AXI4_Lite_Slave :: *;

typedef struct {
    Bool halted;
    Bool running;
    Bool unavailable;
} DMHartStatus_t deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(16) regno;
    Bool     write;
    Bit#(32) data;
    Bit#(8)  epoch;
} DMHartRegRequest_t deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(32) data;
    Bit#(3)  error;
    Bit#(8)  epoch;
} DMHartRegResponse_t deriving(Bits, Eq, FShow);

typedef enum {
    SBA_IDLE,
    SBA_READ,
    SBA_WRITE
} SBA_State_t deriving(Bits, Eq, FShow);

interface RISCVDMRegisterState_ifc;
    method Bool data0_read;
    method Bool data0_write;
    method Bool sbdata0_read;
    method Bool dmcontrol_write;
    method Bool abstractcs_write;
    method Bool command_write;
    method Bool sbaddress0_write;
    method Bool sbdata0_write;

    method Bit#(32) data0;
    method Action set_data0(Bit#(32) value);

    method Bool haltreq;
    method Bool resumereq;
    method Bool ackhavereset;
    method Bool dmactive;
    method Action set_dmactive(Bool value);
    method Bool ndmreset;
    method Action set_ndmreset(Bool value);

    method Action set_hart_status(DMHartStatus_t value);
    method Action set_resume_ack(Bool value);
    method Action set_havereset(Bool value);

    method Bool abstract_busy;
    method Action set_abstract_busy(Bool value);
    method Bit#(3) cmderr;
    method Action set_cmderr(Bit#(3) value);

    method Bit#(32) command;
    method Bit#(3) sbaccess;
    method Action set_sbaccess(Bit#(3) value);
    method Bool sbautoincrement;
    method Action set_sbautoincrement(Bool value);
    method Bool sbreadonaddr;
    method Action set_sbreadonaddr(Bool value);
    method Bool sbreadondata;
    method Action set_sbreadondata(Bool value);
    method Bool sbbusyerror;
    method Action set_sbbusyerror(Bool value);
    method Bit#(3) sberror;
    method Action set_sberror(Bit#(3) value);
    method Action set_sbbusy(Bool value);

    method Bit#(32) sbaddress0;
    method Action set_sbaddress0(Bit#(32) value);
    method Bit#(32) sbdata0;
    method Action set_sbdata0(Bit#(32) value);

endinterface

module [BlueCSRCtx_t#(32, 32)] riscv_dm_register_map(RISCVDMRegisterState_ifc);

    Wire#(Maybe#(Bit#(32))) w_data0_upd <- mkDWire(tagged Invalid);

    Wire#(Maybe#(Bool)) w_ndmreset_upd <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool)) w_dmactive_upd <- mkDWire(tagged Invalid);

    Wire#(Maybe#(Bool)) w_allhavereset_upd <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool)) w_anyhavereset_upd <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool)) w_allresumeack_upd <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool)) w_anyresumeack_upd <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool)) w_allunavail_upd   <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool)) w_anyunavail_upd   <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool)) w_allrunning_upd   <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool)) w_anyrunning_upd   <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool)) w_allhalted_upd    <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool)) w_anyhalted_upd    <- mkDWire(tagged Invalid);

    Wire#(Maybe#(Bool))    w_abstract_busy_upd <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bit#(3))) w_cmderr_upd        <- mkDWire(tagged Invalid);

    Wire#(Maybe#(Bool))    w_sbbusyerror_upd     <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool))    w_sbbusy_upd          <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool))    w_sbreadonaddr_upd    <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bit#(3))) w_sbaccess_upd        <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool))    w_sbautoincrement_upd <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool))    w_sbreadondata_upd    <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bit#(3))) w_sberror_upd         <- mkDWire(tagged Invalid);

    Wire#(Maybe#(Bit#(32))) w_sbaddress0_upd <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bit#(32))) w_sbdata0_upd    <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool))     w_haltsum0_upd   <- mkDWire(tagged Invalid);

    ReadOnly#(Bit#(32)) rg_data0;
    Reg#(Bit#(1)) rg_data0_read;
    Reg#(Bit#(1)) rg_data0_write;

    ReadOnly#(Bool) rg_haltreq;
    ReadOnly#(Bool) rg_resumereq;
    ReadOnly#(Bool) rg_ackhavereset;
    ReadOnly#(Bool) rg_ndmreset;
    ReadOnly#(Bool) rg_dmactive;
    Reg#(Bit#(1)) rg_dmcontrol_write;

    ReadOnly#(Bool) rg_allhavereset;
    ReadOnly#(Bool) rg_anyhavereset;
    ReadOnly#(Bool) rg_allresumeack;
    ReadOnly#(Bool) rg_anyresumeack;
    ReadOnly#(Bool) rg_allunavail;
    ReadOnly#(Bool) rg_anyunavail;
    ReadOnly#(Bool) rg_allrunning;
    ReadOnly#(Bool) rg_anyrunning;
    ReadOnly#(Bool) rg_allhalted;
    ReadOnly#(Bool) rg_anyhalted;

    ReadOnly#(Bool) rg_abstract_busy;
    ReadOnly#(Bit#(3)) rg_cmderr;
    Reg#(Bit#(1)) rg_abstractcs_write;

    ReadOnly#(Bit#(32)) rg_command;
    Reg#(Bit#(1)) rg_command_write;

    ReadOnly#(Bool) rg_sbbusyerror;
    ReadOnly#(Bool) rg_sbbusy;
    ReadOnly#(Bool) rg_sbreadonaddr;
    ReadOnly#(Bit#(3)) rg_sbaccess;
    ReadOnly#(Bool) rg_sbautoincrement;
    ReadOnly#(Bool) rg_sbreadondata;
    ReadOnly#(Bit#(3)) rg_sberror;

    ReadOnly#(Bit#(32)) rg_sbaddress0;
    Reg#(Bit#(1)) rg_sbaddress0_write;

    ReadOnly#(Bit#(32)) rg_sbdata0;
    Reg#(Bit#(1)) rg_sbdata0_read;
    Reg#(Bit#(1)) rg_sbdata0_write;

    ReadOnly#(Bool) rg_haltsum0;

    csr_regmap_def("riscvDM", "RISC-V Debug Module registers");

    // DMI 0x04, byte offset 0x010.
    csr_reg_def('h010, "DATA0", "Abstract command argument and result");
    rg_data0          <- csr_reg_hu   ('h010,     0, 0, w_data0_upd, "DATA",  "Data",  "Abstract command argument zero.");
    rg_data0_read     <- csr_reg_trigr('h010, False,                 "READ",  "Read",  "DATA0 was read.");
    rg_data0_write    <- csr_reg_trigw('h010, True,                  "WRITE", "Write", "DATA0 was written.");

    // DMI 0x10, byte offset 0x040.
    csr_reg_def('h040, "DMCONTROL", "Debug Module control");
    rg_haltreq          <- csr_reg_wo   ('h040, False, 31,                 "HALTREQ",      "Halt Request",      "Requests that the selected hart halt.");
    rg_resumereq        <- csr_reg_wo   ('h040, False, 30,                 "RESUMEREQ",    "Resume Request",    "Requests that the selected hart resume.");
    rg_ackhavereset     <- csr_reg_wo   ('h040, False, 28,                 "ACKHAVERESET", "Acknowledge Reset", "Clears the selected hart's reset indication.");
    rg_ndmreset         <- csr_reg_hu   ('h040, False,  1, w_ndmreset_upd, "NDMRESET",     "Non-DM Reset",      "Resets the platform outside the Debug Module.");
    rg_dmactive         <- csr_reg_hu   ('h040, False,  0, w_dmactive_upd, "DMACTIVE",     "DM Active",         "Enables Debug Module operation.");
    rg_dmcontrol_write  <- csr_reg_trigw('h040, True,                      "WRITE",        "Write",             "DMCONTROL was written.");

    // DMI 0x11, byte offset 0x044.
    csr_reg_def('h044, "DMSTATUS", "Debug Module status");
    rg_allhavereset    <- csr_reg_ho ('h044,       False, 19, w_allhavereset_upd, "ALLHAVERESET",  "All Have Reset",         "All selected harts have reset.");
    rg_anyhavereset    <- csr_reg_ho ('h044,       False, 18, w_anyhavereset_upd, "ANYHAVERESET",  "Any Have Reset",         "Any selected hart has reset.");
    rg_allresumeack    <- csr_reg_ho ('h044,       False, 17, w_allresumeack_upd, "ALLRESUMEACK",  "All Resume Acknowledge", "All selected harts acknowledged resume.");
    rg_anyresumeack    <- csr_reg_ho ('h044,       False, 16, w_anyresumeack_upd, "ANYRESUMEACK",  "Any Resume Acknowledge", "Any selected hart acknowledged resume.");
    rg_allunavail      <- csr_reg_ho ('h044,        True, 13, w_allunavail_upd,   "ALLUNAVAIL",    "All Unavailable",        "All selected harts are unavailable.");
    rg_anyunavail      <- csr_reg_ho ('h044,        True, 12, w_anyunavail_upd,   "ANYUNAVAIL",    "Any Unavailable",        "Any selected harts are unavailable.");
    rg_allrunning      <- csr_reg_ho ('h044,       False, 11, w_allrunning_upd,   "ALLRUNNING",    "All Running",            "All selected harts are running.");
    rg_anyrunning      <- csr_reg_ho ('h044,       False, 10, w_anyrunning_upd,   "ANYRUNNING",    "Any Running",            "Any selected harts are running.");
    rg_allhalted       <- csr_reg_ho ('h044,       False,  9, w_allhalted_upd,    "ALLHALTED",     "All Halted",             "All selected harts are halted.");
    rg_anyhalted       <- csr_reg_ho ('h044,       False,  8, w_anyhalted_upd,    "ANYHALTED",     "Any Halted",             "Any selected hart is halted.");
    Empty _dmstat_auth <- csr_reg_rc ('h044, Bit#(1)'(1),  7,                     "AUTHENTICATED", "Authenticated",          "Authentication is not implemented and access is permitted.");
    Empty _dmstat_ver  <- csr_reg_rc ('h044, Bit#(4)'(2),  0,                     "VERSION",       "Version",                "RISC-V Debug Specification version 0.13.");

    // DMI 0x16, byte offset 0x058.
    csr_reg_def  ('h058, "ABSTRACTCS", "Abstract command status");
    Empty _abst_data      <- csr_reg_rc   ('h058, Bit#(4)'(1),  0,                      "DATACOUNT",   "Data Count",          "One data register is implemented.");
    rg_cmderr             <- csr_reg_w1c  ('h058,           0,  8, w_cmderr_upd,        "CMDERR",      "Command Error",       "Sticky abstract command error.");
    rg_abstract_busy      <- csr_reg_ho   ('h058,       False, 12, w_abstract_busy_upd, "BUSY",        "Busy",                "An abstract command is executing.");
    Empty _abst_pbuf      <- csr_reg_rc   ('h058, Bit#(5)'(0), 24,                      "PROGBUFSIZE", "Program Buffer Size", "No Program Buffer is implemented.");
    rg_abstractcs_write   <- csr_reg_trigw('h058,        True,                          "WRITE",       "Write",               "ABSTRACTCS was written.");

    // DMI 0x17, byte offset 0x05c.
    csr_reg_def('h05c, "COMMAND", "Abstract command");
    rg_command       <- csr_reg_wo   ('h05c,    0, 0, "CONTROL", "Command Control", "Access Register command encoding.");
    rg_command_write <- csr_reg_trigw('h05c, True,    "WRITE",   "Write",           "COMMAND was written.");

    // DMI 0x38, byte offset 0x0e0.
    csr_reg_def('h0e0, "SBCS", "System Bus Access control and status");
    Empty _sbcs_ver     <- csr_reg_rc ('h0e0, Bit#(3)'(1), 29,                          "SBVERSION",       "SBA Version",     "System Bus Access version 1.");
    rg_sbbusyerror      <- csr_reg_w1c('h0e0,       False, 22, w_sbbusyerror_upd,       "SBBUSYERROR",     "SBA Busy Error",  "An access was attempted while busy.");
    rg_sbbusy           <- csr_reg_ho ('h0e0,       False, 21, w_sbbusy_upd,            "SBBUSY",          "SBA Busy",        "A system bus transaction is outstanding.");
    rg_sbreadonaddr     <- csr_reg_hu ('h0e0,       False, 20, w_sbreadonaddr_upd,      "SBREADONADDR",    "Read On Address", "Writing SBADDRESS0 starts a read.");
    rg_sbaccess         <- csr_reg_hu ('h0e0,           2, 17, w_sbaccess_upd,          "SBACCESS",        "Access Size",     "System bus access size.");
    rg_sbautoincrement  <- csr_reg_hu ('h0e0,       False, 16, w_sbautoincrement_upd,   "SBAUTOINCREMENT", "Auto Increment",  "Increment the address after a successful access.");
    rg_sbreadondata     <- csr_reg_hu ('h0e0,       False, 15, w_sbreadondata_upd,      "SBREADONDATA",    "Read On Data",    "Reading SBDATA0 starts another read.");
    rg_sberror          <- csr_reg_w1c('h0e0,           0, 12, w_sberror_upd,           "SBERROR",         "SBA Error",       "Sticky system bus access error.");
    Empty _sbcs_asize   <- csr_reg_rc ('h0e0,Bit#(7)'(32),  5,                          "SBASIZE",         "Address Size",    "System bus address width.");
    Empty _sbcs_access  <- csr_reg_rc ('h0e0, Bit#(1)'(1),  2,                          "SBACCESS32",      "32-bit Access",   "32-bit system bus access is supported.");

    // DMI 0x39, byte offset 0x0e4.
    csr_reg_def('h0e4, "SBADDRESS0", "System Bus Access address");
    rg_sbaddress0       <- csr_reg_hu   ('h0e4,    0, 0, w_sbaddress0_upd,  "ADDRESS", "Address", "System bus byte address.");
    rg_sbaddress0_write <- csr_reg_trigw('h0e4, True,                       "WRITE",   "Write",   "SBADDRESS0 was written.");

    // DMI 0x3c, byte offset 0x0f0.
    csr_reg_def('h0f0, "SBDATA0", "System Bus Access data");
    rg_sbdata0         <- csr_reg_hu   ('h0f0,     0, 0, w_sbdata0_upd, "DATA",  "Data",  "System bus access data.");
    rg_sbdata0_read    <- csr_reg_trigr('h0f0, False,                   "READ",  "Read",  "SBDATA0 was read.");
    rg_sbdata0_write   <- csr_reg_trigw('h0f0, True,                    "WRITE", "Write", "SBDATA0 was written.");

    // DMI 0x40, byte offset 0x100.
    csr_reg_def('h100, "HALTSUM0", "Halted hart summary");
    rg_haltsum0        <- csr_reg_ho ('h100, False, 0, w_haltsum0_upd, "HART0", "Hart 0 Halted", "Hart zero is halted.");

    method data0_read       = rg_data0_read         == 1;
    method data0_write      = rg_data0_write        == 1;
    method sbdata0_read     = rg_sbdata0_read       == 1;
    method dmcontrol_write  = rg_dmcontrol_write    == 1;
    method abstractcs_write = rg_abstractcs_write   == 1;
    method command_write    = rg_command_write      == 1;
    method sbaddress0_write = rg_sbaddress0_write   == 1;
    method sbdata0_write    = rg_sbdata0_write      == 1;

    method data0 = rg_data0;
    method Action set_data0(Bit#(32) value);
        w_data0_upd <= tagged Valid value;
    endmethod
    method haltreq = rg_haltreq;
    method resumereq = rg_resumereq;
    method ackhavereset = rg_ackhavereset;
    method dmactive = rg_dmactive;
    method Action set_dmactive(Bool value);
        w_dmactive_upd <= tagged Valid value;
    endmethod
    method ndmreset = rg_ndmreset;
    method Action set_ndmreset(Bool value);
        w_ndmreset_upd <= tagged Valid value;
    endmethod

    method Action set_hart_status(DMHartStatus_t value);
        Bool available  = !value.unavailable;
        Bool halted     = available && value.halted;
        Bool running    = available && value.running;

        w_allunavail_upd <= tagged Valid value.unavailable;
        w_anyunavail_upd <= tagged Valid value.unavailable;
        w_allrunning_upd <= tagged Valid running;
        w_anyrunning_upd <= tagged Valid running;
        w_allhalted_upd  <= tagged Valid halted;
        w_anyhalted_upd  <= tagged Valid halted;
        w_haltsum0_upd   <= tagged Valid halted;
    endmethod

    method Action set_resume_ack(Bool value);
        w_allresumeack_upd <= tagged Valid value;
        w_anyresumeack_upd <= tagged Valid value;
    endmethod

    method Action set_havereset(Bool value);
        w_allhavereset_upd <= tagged Valid value;
        w_anyhavereset_upd <= tagged Valid value;
    endmethod

    method abstract_busy = rg_abstract_busy;
    method Action set_abstract_busy(Bool value);
        w_abstract_busy_upd <= tagged Valid value;
    endmethod
    method cmderr = rg_cmderr;
    method Action set_cmderr(Bit#(3) value);
        w_cmderr_upd <= tagged Valid value;
    endmethod

    method command = rg_command;
    method sbaccess = rg_sbaccess;
    method Action set_sbaccess(Bit#(3) value);
        w_sbaccess_upd <= tagged Valid value;
    endmethod
    method sbautoincrement = rg_sbautoincrement;
    method Action set_sbautoincrement(Bool value);
        w_sbautoincrement_upd <= tagged Valid value;
    endmethod
    method sbreadonaddr = rg_sbreadonaddr;
    method Action set_sbreadonaddr(Bool value);
        w_sbreadonaddr_upd <= tagged Valid value;
    endmethod
    method sbreadondata = rg_sbreadondata;
    method Action set_sbreadondata(Bool value);
        w_sbreadondata_upd <= tagged Valid value;
    endmethod
    method sbbusyerror = rg_sbbusyerror;
    method Action set_sbbusyerror(Bool value);
        w_sbbusyerror_upd <= tagged Valid value;
    endmethod
    method sberror = rg_sberror;
    method Action set_sberror(Bit#(3) value);
        w_sberror_upd <= tagged Valid value;
    endmethod
    method Action set_sbbusy(Bool value);
        w_sbbusy_upd <= tagged Valid value;
    endmethod
    method sbaddress0 = rg_sbaddress0;
    method Action set_sbaddress0(Bit#(32) value);
        w_sbaddress0_upd <= tagged Valid value;
    endmethod
    method sbdata0 = rg_sbdata0;
    method Action set_sbdata0(Bit#(32) value);
        w_sbdata0_upd <= tagged Valid value;
    endmethod

endmodule

interface RISCVDMHartPort_ifc;
    method Action status(DMHartStatus_t value);
    method Action reset_seen;

    method Bool halt_request;
    method Bool resume_request;
    method Bool acknowledge_reset;

    interface Client#(DMHartRegRequest_t, DMHartRegResponse_t) registers;
endinterface

interface RISCVDM_ifc;
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_dmi_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_dmi_wr;

    interface AXI4_Lite_Master_Rd_Fab#(32, 32) m_system_rd;
    interface AXI4_Lite_Master_Wr_Fab#(32, 32) m_system_wr;

    interface RISCVDMHartPort_ifc hart;

    method Bool ndmreset;
    method Bool dmactive;
endinterface

function Bool axi_response_success(AXI4_Lite_Response response);
    return response == OKAY || response == EXOKAY;
endfunction

function Bool abstract_register_supported(Bit#(16) regno);
    Bool gpr = regno >= 16'h1000 && regno <= 16'h101f;
    Bool required_csr = regno == 16'h07b0 || regno == 16'h07b1;
    return gpr || required_csr;
endfunction

module [Module] mkRISCVDM(RISCVDM_ifc);

    BlueCSRAccess_ifc#(32, 32, 0, RISCVDMRegisterState_ifc) i_csr <-
        create_blue_csr_with_default_response(riscv_dm_register_map, False, CSR_OKAY);
    BlueCSR_AXI4Lite_ifc#(32, 32, 0) i_dmi_axi <-
        mkBlueCSRAXI4LiteAdapter(i_csr.external, 2, 2);
    RISCVDMRegisterState_ifc i_registers = i_csr.internal;

    AXI4_Lite_Master_Rd#(32, 32) i_system_rd <- mkAXI4_Lite_Master_Rd(2);
    AXI4_Lite_Master_Wr#(32, 32) i_system_wr <- mkAXI4_Lite_Master_Wr(2);

    FIFOF#(DMHartRegRequest_t)  f_hart_request  <- mkFIFOF;
    FIFOF#(DMHartRegResponse_t) f_hart_response <- mkFIFOF;

    DMHartStatus_t default_hart_status = DMHartStatus_t {
        halted:     False,
        running:    False,
        unavailable: True
    };
    Wire#(DMHartStatus_t) w_hart_status <- mkDWire(default_hart_status);
    Wire#(Bool) w_hart_reset_seen <- mkDWire(False);

    Reg#(Bool) rg_halt_request   <- mkReg(False);
    Reg#(Bool) rg_resume_request <- mkReg(False);
    Reg#(Bool) rg_ack_reset      <- mkDReg(False);
    Reg#(Bool) rg_dmactive_applied <- mkReg(False);

    Reg#(Bool)     rg_abstract_write <- mkReg(False);
    Reg#(Bit#(3))  rg_abstract_size  <- mkReg(2);
    Reg#(Bit#(8))  rg_abstract_epoch <- mkReg(0);

    Reg#(SBA_State_t) rg_sba_state       <- mkReg(SBA_IDLE);
    Reg#(Bool)        rg_sba_discard     <- mkReg(False);
    function Action set_cmderr_if_clear(Bit#(3) error);
        action
            if(i_registers.cmderr == 0) begin
                i_registers.set_cmderr(error);
            end
        endaction
    endfunction

    function Action start_sba_read(Bit#(32) address);
        action
            if(rg_sba_state != SBA_IDLE) begin
                i_registers.set_sbbusyerror(True);
            end
            else if(i_registers.sbbusyerror || i_registers.sberror != 0) begin
                noAction;
            end
            else if(i_registers.sbaccess != 2) begin
                i_registers.set_sberror(4);
            end
            else if(address[1:0] != 0) begin
                i_registers.set_sberror(3);
            end
            else begin
                i_system_rd.request.put(AXI4_Lite_Read_Rq_Pkg {
                    addr: address,
                    prot: UNPRIV_SECURE_DATA
                });
                rg_sba_state <= SBA_READ;
                i_registers.set_sbbusy(True);
            end
        endaction
    endfunction

    function Action start_sba_write(Bit#(32) address, Bit#(32) data);
        action
            if(rg_sba_state != SBA_IDLE) begin
                i_registers.set_sbbusyerror(True);
            end
            else if(i_registers.sbbusyerror || i_registers.sberror != 0) begin
                noAction;
            end
            else if(i_registers.sbaccess != 2) begin
                i_registers.set_sberror(4);
            end
            else if(address[1:0] != 0) begin
                i_registers.set_sberror(3);
            end
            else begin
                i_system_wr.request.put(AXI4_Lite_Write_Rq_Pkg {
                    addr: address,
                    data: data,
                    strb: 4'hf,
                    prot: UNPRIV_SECURE_DATA
                });
                rg_sba_state <= SBA_WRITE;
                i_registers.set_sbbusy(True);
            end
        endaction
    endfunction

    function Action reset_dm_state(Bool next_active);
        action
            i_registers.set_dmactive(next_active);
            rg_dmactive_applied <= next_active;
            i_registers.set_ndmreset(False);
            rg_halt_request <= False;
            rg_resume_request <= False;
            i_registers.set_resume_ack(False);
            i_registers.set_havereset(False);
            i_registers.set_data0(0);
            i_registers.set_abstract_busy(False);
            f_hart_request.clear;
            f_hart_response.clear;
            rg_abstract_write <= False;
            rg_abstract_size <= 2;
            i_registers.set_cmderr(0);
            rg_abstract_epoch <= rg_abstract_epoch + 1;
            if(rg_sba_state == SBA_IDLE) begin
                rg_sba_discard <= False;
            end
            else begin
                rg_sba_discard <= True;
            end
            i_registers.set_sbbusy(False);
            i_registers.set_sbaddress0(0);
            i_registers.set_sbdata0(0);
            i_registers.set_sbaccess(2);
            i_registers.set_sbautoincrement(False);
            i_registers.set_sbreadonaddr(False);
            i_registers.set_sbreadondata(False);
            i_registers.set_sbbusyerror(False);
            i_registers.set_sberror(0);
        endaction
    endfunction

    function Action execute_abstract_command(Bit#(32) command);
        action
            Bit#(8) cmdtype = command[31:24];
            Bit#(3) aarsize = command[22:20];
            Bool aarpostincrement = unpack(command[19]);
            Bool postexec = unpack(command[18]);
            Bool transfer = unpack(command[17]);
            Bool write = unpack(command[16]);
            Bit#(16) regno = command[15:0];

            if(i_registers.abstract_busy) begin
                set_cmderr_if_clear(1);
            end
            else if(i_registers.cmderr != 0) begin
                noAction;
            end
            else if(cmdtype != 0 || aarpostincrement || postexec) begin
                i_registers.set_cmderr(2);
            end
            else if(!transfer) begin
                noAction;
            end
            else if((write && aarsize != 2) || (!write && aarsize > 2)) begin
                i_registers.set_cmderr(2);
            end
            else if(!abstract_register_supported(regno)) begin
                i_registers.set_cmderr(2);
            end
            else if(w_hart_status.unavailable || !w_hart_status.halted) begin
                i_registers.set_cmderr(4);
            end
            else begin
                f_hart_request.enq(DMHartRegRequest_t {
                    regno: regno,
                    write: write,
                    data:  i_registers.data0,
                    epoch: rg_abstract_epoch
                });
                i_registers.set_abstract_busy(True);
                rg_abstract_write <= write;
                rg_abstract_size <= aarsize;
            end
        endaction
    endfunction

    (* descending_urgency = "r_dmcontrol, r_data0_read, r_data0_write, r_abstractcs_write, r_command_write, r_hart_response, r_sbdata0_read, r_sbaddress0_write, r_sbdata0_write, r_system_read_response, r_system_write_response" *)

    rule r_hart_response if(!i_registers.dmcontrol_write);
        let response = f_hart_response.first;
        f_hart_response.deq;
        if(i_registers.abstract_busy && response.epoch == rg_abstract_epoch) begin
            if(response.error == 0) begin
                if(!rg_abstract_write) begin
                    Bit#(32) data = response.data;
                    if(rg_abstract_size == 0) begin
                        data = zeroExtend(response.data[7:0]);
                    end
                    else if(rg_abstract_size == 1) begin
                        data = zeroExtend(response.data[15:0]);
                    end
                    i_registers.set_data0(data);
                end
            end
            else begin
                set_cmderr_if_clear(response.error);
            end
            i_registers.set_abstract_busy(False);
        end
    endrule

    rule r_system_read_response if(rg_sba_state == SBA_READ);
        let response <- i_system_rd.response.get;
        if(rg_sba_discard) begin
            rg_sba_discard <= False;
        end
        else if(axi_response_success(response.resp)) begin
            i_registers.set_sbdata0(response.data);
            if(i_registers.sbautoincrement) begin
                i_registers.set_sbaddress0(i_registers.sbaddress0 + 4);
            end
        end
        else begin
            i_registers.set_sberror(7);
        end
        rg_sba_state <= SBA_IDLE;
        i_registers.set_sbbusy(False);
    endrule

    rule r_system_write_response if(rg_sba_state == SBA_WRITE);
        let response <- i_system_wr.response.get;
        if(rg_sba_discard) begin
            rg_sba_discard <= False;
        end
        else if(axi_response_success(response.resp)) begin
            if(i_registers.sbautoincrement) begin
                i_registers.set_sbaddress0(i_registers.sbaddress0 + 4);
            end
        end
        else begin
            i_registers.set_sberror(7);
        end
        rg_sba_state <= SBA_IDLE;
        i_registers.set_sbbusy(False);
    endrule

    rule r_data0_read if(i_registers.data0_read && !i_registers.dmcontrol_write);
        if(i_registers.dmactive && i_registers.abstract_busy) begin
            set_cmderr_if_clear(1);
        end
    endrule

    rule r_sbdata0_read if(i_registers.sbdata0_read && !i_registers.dmcontrol_write);
        if(i_registers.dmactive) begin
            if(rg_sba_state != SBA_IDLE) begin
                i_registers.set_sbbusyerror(True);
            end
            else if(!i_registers.sbbusyerror && i_registers.sberror == 0 && i_registers.sbreadondata) begin
                start_sba_read(i_registers.sbaddress0);
            end
        end
    endrule

    rule r_data0_write if(i_registers.data0_write);
        if(i_registers.dmactive) begin
            if(i_registers.abstract_busy) begin
                set_cmderr_if_clear(1);
            end
        end
    endrule

    rule r_abstractcs_write if(i_registers.abstractcs_write);
        if(i_registers.dmactive) begin
            if(i_registers.abstract_busy) begin
                set_cmderr_if_clear(1);
            end
        end
    endrule

    rule r_command_write if(i_registers.command_write);
        if(i_registers.dmactive) begin
            execute_abstract_command(i_registers.command);
        end
    endrule

    rule r_sbaddress0_write if(i_registers.sbaddress0_write);
        if(i_registers.dmactive) begin
            if(rg_sba_state != SBA_IDLE) begin
                i_registers.set_sbbusyerror(True);
            end
            else if(i_registers.sbreadonaddr) begin
                start_sba_read(i_registers.sbaddress0);
            end
        end
    endrule

    rule r_sbdata0_write if(i_registers.sbdata0_write);
        if(i_registers.dmactive) begin
            if(rg_sba_state != SBA_IDLE) begin
                i_registers.set_sbbusyerror(True);
            end
            else if(!i_registers.sbbusyerror && i_registers.sberror == 0) begin
                start_sba_write(i_registers.sbaddress0, i_registers.sbdata0);
            end
        end
    endrule

    rule r_dmcontrol if(i_registers.dmcontrol_write);
        if(!i_registers.dmactive) begin
            reset_dm_state(False);
        end
        else if(!rg_dmactive_applied) begin
            reset_dm_state(True);
        end
        else begin
            i_registers.set_ndmreset(i_registers.ndmreset);
            rg_halt_request <= i_registers.haltreq;

            if(i_registers.ackhavereset) begin
                rg_ack_reset <= True;
            end
            if(i_registers.resumereq && !i_registers.haltreq && w_hart_status.halted) begin
                rg_resume_request <= True;
                i_registers.set_resume_ack(False);
            end
            else if(!i_registers.resumereq) begin
                rg_resume_request <= False;
                i_registers.set_resume_ack(False);
            end

            if(w_hart_reset_seen) begin
                i_registers.set_havereset(True);
            end
            else if(i_registers.ackhavereset) begin
                i_registers.set_havereset(False);
            end
        end
    endrule

    rule r_track_hart_state if(!i_registers.dmcontrol_write);
        i_registers.set_hart_status(w_hart_status);
        if(!i_registers.dmactive) begin
            rg_resume_request <= False;
            i_registers.set_resume_ack(False);
            i_registers.set_havereset(False);
        end
        else begin
            if(rg_resume_request && w_hart_status.running) begin
                rg_resume_request <= False;
                i_registers.set_resume_ack(True);
            end
            if(w_hart_reset_seen) begin
                i_registers.set_havereset(True);
            end
        end
    endrule

    interface s_dmi_rd = i_dmi_axi.s_rd;
    interface s_dmi_wr = i_dmi_axi.s_wr;
    interface m_system_rd = i_system_rd.fab;
    interface m_system_wr = i_system_wr.fab;

    interface RISCVDMHartPort_ifc hart;
        method status = w_hart_status._write;
        method reset_seen = w_hart_reset_seen._write(True);

        method halt_request = i_registers.dmactive && rg_halt_request;
        method resume_request = i_registers.dmactive && rg_resume_request;
        method acknowledge_reset = rg_ack_reset;

        interface Client registers;
            interface request = toGet(f_hart_request);
            interface response = toPut(f_hart_response);
        endinterface
    endinterface

    method ndmreset = i_registers.dmactive && i_registers.ndmreset;
    method dmactive = i_registers.dmactive;

endmodule

endpackage
