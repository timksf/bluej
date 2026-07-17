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

typedef union tagged {
    Bit#(32) DATA0Write;
    Bit#(32) DMControlWrite;
    Bit#(32) AbstractCSWrite;
    Bit#(32) CommandWrite;
    Bit#(32) SBCSWrite;
    Bit#(32) SBAddress0Write;
    Bit#(32) SBData0Write;
} DMRegisterWrite_t deriving(Bits, Eq, FShow);

interface RISCVDMRegisterState_ifc;
    method Bool write_pending;
    method DMRegisterWrite_t first_write;
    method Action deq_write;
    method Bool dmcontrol_write_pending;
    method Bool data0_read;
    method Bool sbdata0_read;

    method Bit#(32) data0;
    method Action set_data0(Bit#(32) value);

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

    FIFOF#(DMRegisterWrite_t) f_write <- mkFIFOF;

    function Bool can_write(Bit#(32) data, Bit#(4) strobe);
        return strobe != 4'hf || f_write.notFull;
    endfunction

    function ActionValue#(BlueCSRResponse_t) enqueue_write(DMRegisterWrite_t value, Bit#(4) strobe);
        actionvalue
            if(strobe == 4'hf) begin
                f_write.enq(value);
            end
            return CSR_OKAY;
        endactionvalue
    endfunction

    function ActionValue#(BlueCSRResponse_t) write_data0(Bit#(32) data, Bit#(4) strobe);
        return enqueue_write(tagged DATA0Write data, strobe);
    endfunction

    function ActionValue#(BlueCSRResponse_t) write_dmcontrol(Bit#(32) data, Bit#(4) strobe);
        return enqueue_write(tagged DMControlWrite data, strobe);
    endfunction

    function ActionValue#(BlueCSRResponse_t) write_abstractcs(Bit#(32) data, Bit#(4) strobe);
        return enqueue_write(tagged AbstractCSWrite data, strobe);
    endfunction

    function ActionValue#(BlueCSRResponse_t) write_command(Bit#(32) data, Bit#(4) strobe);
        return enqueue_write(tagged CommandWrite data, strobe);
    endfunction

    function ActionValue#(BlueCSRResponse_t) write_sbcs(Bit#(32) data, Bit#(4) strobe);
        return enqueue_write(tagged SBCSWrite data, strobe);
    endfunction

    function ActionValue#(BlueCSRResponse_t) write_sbaddress0(Bit#(32) data, Bit#(4) strobe);
        return enqueue_write(tagged SBAddress0Write data, strobe);
    endfunction

    function ActionValue#(BlueCSRResponse_t) write_sbdata0(Bit#(32) data, Bit#(4) strobe);
        return enqueue_write(tagged SBData0Write data, strobe);
    endfunction

    csr_regmap_def("riscvDM", "RISC-V Debug Module registers");

    csr_reg_def('h010, "DATA0", "Abstract command argument and result");
    Reg#(Bit#(32)) rg_data0 <- csr_reg_hw(CSR_RW, 'h010, 0, 0, "DATA", "Data", "Abstract command argument zero.");
    csr_reg_action_write('h010, can_write, CSR_SLVERR, write_data0);
    Reg#(Bit#(1)) rg_data0_read <- csr_reg_trigr('h010, False, "READ", "Read", "DATA0 was read.");

    csr_reg_def('h040, "DMCONTROL", "Debug Module control");
    csr_reg_field_def(CSR_WO, 'h040, Bit#(1)'(0), 31, "HALTREQ", "Halt Request", "Requests that the selected hart halt.");
    csr_reg_field_def(CSR_WO, 'h040, Bit#(1)'(0), 30, "RESUMEREQ", "Resume Request", "Requests that the selected hart resume.");
    csr_reg_field_def(CSR_WO, 'h040, Bit#(1)'(0), 28, "ACKHAVERESET", "Acknowledge Reset", "Clears the selected hart's reset indication.");
    Reg#(Bool) rg_ndmreset <- csr_reg_hw(CSR_RW, 'h040, False, 1, "NDMRESET", "Non-DM Reset", "Resets the platform outside the Debug Module.");
    Reg#(Bool) rg_dmactive <- csr_reg_hw(CSR_RW, 'h040, False, 0, "DMACTIVE", "DM Active", "Enables Debug Module operation.");
    csr_reg_action_write('h040, can_write, CSR_SLVERR, write_dmcontrol);

    csr_reg_def('h044, "DMSTATUS", "Debug Module status");
    Reg#(Bool) rg_allhavereset <- csr_reg_ro('h044, False, 19, "ALLHAVERESET", "All Have Reset", "All selected harts have reset.");
    Reg#(Bool) rg_anyhavereset <- csr_reg_ro('h044, False, 18, "ANYHAVERESET", "Any Have Reset", "Any selected hart has reset.");
    Reg#(Bool) rg_allresumeack <- csr_reg_ro('h044, False, 17, "ALLRESUMEACK", "All Resume Acknowledge", "All selected harts acknowledged resume.");
    Reg#(Bool) rg_anyresumeack <- csr_reg_ro('h044, False, 16, "ANYRESUMEACK", "Any Resume Acknowledge", "Any selected hart acknowledged resume.");
    Reg#(Bool) rg_allunavail <- csr_reg_ro('h044, True, 13, "ALLUNAVAIL", "All Unavailable", "All selected harts are unavailable.");
    Reg#(Bool) rg_anyunavail <- csr_reg_ro('h044, True, 12, "ANYUNAVAIL", "Any Unavailable", "Any selected hart is unavailable.");
    Reg#(Bool) rg_allrunning <- csr_reg_ro('h044, False, 11, "ALLRUNNING", "All Running", "All selected harts are running.");
    Reg#(Bool) rg_anyrunning <- csr_reg_ro('h044, False, 10, "ANYRUNNING", "Any Running", "Any selected hart is running.");
    Reg#(Bool) rg_allhalted <- csr_reg_ro('h044, False, 9, "ALLHALTED", "All Halted", "All selected harts are halted.");
    Reg#(Bool) rg_anyhalted <- csr_reg_ro('h044, False, 8, "ANYHALTED", "Any Halted", "Any selected hart is halted.");
    csr_reg_rc('h044, Bit#(1)'(1), 7, "AUTHENTICATED", "Authenticated", "Authentication is not implemented and access is permitted.");
    csr_reg_rc('h044, Bit#(4)'(2), 0, "VERSION", "Version", "RISC-V Debug Specification version 0.13.");
    csr_reg_write_noop('h044);

    csr_reg_def('h058, "ABSTRACTCS", "Abstract command status");
    csr_reg_rc('h058, Bit#(5)'(0), 24, "PROGBUFSIZE", "Program Buffer Size", "No Program Buffer is implemented.");
    Reg#(Bool) rg_abstract_busy <- csr_reg_ro('h058, False, 12, "BUSY", "Busy", "An abstract command is executing.");
    Reg#(Bit#(3)) rg_cmderr <- csr_reg_hw(CSR_W1C, 'h058, 0, 8, "CMDERR", "Command Error", "Sticky abstract command error.");
    csr_reg_rc('h058, Bit#(4)'(1), 0, "DATACOUNT", "Data Count", "One data register is implemented.");
    csr_reg_action_write('h058, can_write, CSR_SLVERR, write_abstractcs);

    csr_reg_def('h05c, "COMMAND", "Abstract command");
    csr_reg_field_def(CSR_WO, 'h05c, Bit#(32)'(0), 0, "CONTROL", "Command Control", "Access Register command encoding.");
    csr_reg_read_value('h05c, 0);
    csr_reg_action_write('h05c, can_write, CSR_SLVERR, write_command);

    csr_reg_def('h0e0, "SBCS", "System Bus Access control and status");
    csr_reg_rc('h0e0, Bit#(3)'(1), 29, "SBVERSION", "SBA Version", "System Bus Access version 1.");
    Reg#(Bool) rg_sbbusyerror <- csr_reg_hw(CSR_W1C, 'h0e0, False, 22, "SBBUSYERROR", "SBA Busy Error", "An access was attempted while busy.");
    Reg#(Bool) rg_sbbusy <- csr_reg_ro('h0e0, False, 21, "SBBUSY", "SBA Busy", "A system bus transaction is outstanding.");
    Reg#(Bool) rg_sbreadonaddr <- csr_reg_hw(CSR_RW, 'h0e0, False, 20, "SBREADONADDR", "Read On Address", "Writing SBADDRESS0 starts a read.");
    Reg#(Bit#(3)) rg_sbaccess <- csr_reg_hw(CSR_RW, 'h0e0, 2, 17, "SBACCESS", "Access Size", "System bus access size.");
    Reg#(Bool) rg_sbautoincrement <- csr_reg_hw(CSR_RW, 'h0e0, False, 16, "SBAUTOINCREMENT", "Auto Increment", "Increment the address after a successful access.");
    Reg#(Bool) rg_sbreadondata <- csr_reg_hw(CSR_RW, 'h0e0, False, 15, "SBREADONDATA", "Read On Data", "Reading SBDATA0 starts another read.");
    Reg#(Bit#(3)) rg_sberror <- csr_reg_hw(CSR_W1C, 'h0e0, 0, 12, "SBERROR", "SBA Error", "Sticky system bus access error.");
    csr_reg_rc('h0e0, Bit#(7)'(32), 5, "SBASIZE", "Address Size", "System bus address width.");
    csr_reg_rc('h0e0, Bit#(1)'(1), 2, "SBACCESS32", "32-bit Access", "32-bit system bus access is supported.");
    csr_reg_action_write('h0e0, can_write, CSR_SLVERR, write_sbcs);

    csr_reg_def('h0e4, "SBADDRESS0", "System Bus Access address");
    Reg#(Bit#(32)) rg_sbaddress0 <- csr_reg_hw(CSR_RW, 'h0e4, 0, 0, "ADDRESS", "Address", "System bus byte address.");
    csr_reg_action_write('h0e4, can_write, CSR_SLVERR, write_sbaddress0);

    csr_reg_def('h0f0, "SBDATA0", "System Bus Access data");
    Reg#(Bit#(32)) rg_sbdata0 <- csr_reg_hw(CSR_RW, 'h0f0, 0, 0, "DATA", "Data", "System bus access data.");
    csr_reg_action_write('h0f0, can_write, CSR_SLVERR, write_sbdata0);
    Reg#(Bit#(1)) rg_sbdata0_read <- csr_reg_trigr('h0f0, False, "READ", "Read", "SBDATA0 was read.");

    csr_reg_def('h100, "HALTSUM0", "Halted hart summary");
    Reg#(Bool) rg_haltsum0 <- csr_reg_ro('h100, False, 0, "HART0", "Hart 0 Halted", "Hart zero is halted.");
    csr_reg_write_noop('h100);

    method write_pending = f_write.notEmpty;
    method first_write = f_write.first;
    method deq_write = f_write.deq;
    method Bool dmcontrol_write_pending;
        Bool pending = False;
        if(f_write.notEmpty) begin
            case(f_write.first) matches
                tagged DMControlWrite .data: pending = True;
                default: pending = False;
            endcase
        end
        return pending;
    endmethod
    method data0_read = rg_data0_read == 1;
    method sbdata0_read = rg_sbdata0_read == 1;

    method data0 = rg_data0;
    method set_data0 = rg_data0._write;
    method dmactive = rg_dmactive;
    method set_dmactive = rg_dmactive._write;
    method ndmreset = rg_ndmreset;
    method set_ndmreset = rg_ndmreset._write;

    method Action set_hart_status(DMHartStatus_t value);
        Bool available = !value.unavailable;
        Bool halted = available && value.halted;
        Bool running = available && value.running;
        rg_allunavail <= value.unavailable;
        rg_anyunavail <= value.unavailable;
        rg_allrunning <= running;
        rg_anyrunning <= running;
        rg_allhalted <= halted;
        rg_anyhalted <= halted;
        rg_haltsum0 <= halted;
    endmethod

    method Action set_resume_ack(Bool value);
        rg_allresumeack <= value;
        rg_anyresumeack <= value;
    endmethod

    method Action set_havereset(Bool value);
        rg_allhavereset <= value;
        rg_anyhavereset <= value;
    endmethod

    method abstract_busy = rg_abstract_busy;
    method set_abstract_busy = rg_abstract_busy._write;
    method cmderr = rg_cmderr;
    method set_cmderr = rg_cmderr._write;

    method sbaccess = rg_sbaccess;
    method set_sbaccess = rg_sbaccess._write;
    method sbautoincrement = rg_sbautoincrement;
    method set_sbautoincrement = rg_sbautoincrement._write;
    method sbreadonaddr = rg_sbreadonaddr;
    method set_sbreadonaddr = rg_sbreadonaddr._write;
    method sbreadondata = rg_sbreadondata;
    method set_sbreadondata = rg_sbreadondata._write;
    method sbbusyerror = rg_sbbusyerror;
    method set_sbbusyerror = rg_sbbusyerror._write;
    method sberror = rg_sberror;
    method set_sberror = rg_sberror._write;
    method set_sbbusy = rg_sbbusy._write;
    method sbaddress0 = rg_sbaddress0;
    method set_sbaddress0 = rg_sbaddress0._write;
    method sbdata0 = rg_sbdata0;
    method set_sbdata0 = rg_sbdata0._write;

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

    (* descending_urgency = "r_dmcontrol, r_data0_read, r_data0_write, r_abstractcs_write, r_command_write, r_hart_response, r_sbdata0_read, r_sbcs_write, r_sbaddress0_write, r_sbdata0_write, r_system_read_response, r_system_write_response" *)
    (* mutually_exclusive = "r_dmcontrol, r_data0_write, r_abstractcs_write, r_command_write, r_sbcs_write, r_sbaddress0_write, r_sbdata0_write" *)

    rule r_hart_response if(!i_registers.dmcontrol_write_pending);
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

    rule r_data0_read if(i_registers.data0_read && !i_registers.dmcontrol_write_pending);
        if(i_registers.dmactive && i_registers.abstract_busy) begin
            set_cmderr_if_clear(1);
        end
    endrule

    rule r_sbdata0_read if(i_registers.sbdata0_read && !i_registers.dmcontrol_write_pending);
        if(i_registers.dmactive) begin
            if(rg_sba_state != SBA_IDLE) begin
                i_registers.set_sbbusyerror(True);
            end
            else if(!i_registers.sbbusyerror && i_registers.sberror == 0 && i_registers.sbreadondata) begin
                start_sba_read(i_registers.sbaddress0);
            end
        end
    endrule

    rule r_data0_write if(i_registers.first_write matches tagged DATA0Write .data);
        i_registers.deq_write;
        if(i_registers.dmactive) begin
            if(i_registers.abstract_busy) begin
                set_cmderr_if_clear(1);
            end
            else begin
                i_registers.set_data0(data);
            end
        end
    endrule

    rule r_abstractcs_write if(i_registers.first_write matches tagged AbstractCSWrite .data);
        i_registers.deq_write;
        if(i_registers.dmactive) begin
            if(i_registers.abstract_busy) begin
                set_cmderr_if_clear(1);
            end
            else begin
                i_registers.set_cmderr(i_registers.cmderr & ~data[10:8]);
            end
        end
    endrule

    rule r_command_write if(i_registers.first_write matches tagged CommandWrite .data);
        i_registers.deq_write;
        if(i_registers.dmactive) begin
            execute_abstract_command(data);
        end
    endrule

    rule r_sbcs_write if(i_registers.first_write matches tagged SBCSWrite .data);
        i_registers.deq_write;
        if(i_registers.dmactive && rg_sba_state == SBA_IDLE) begin
            i_registers.set_sbreadonaddr(unpack(data[20]));
            i_registers.set_sbaccess(data[19:17]);
            i_registers.set_sbautoincrement(unpack(data[16]));
            i_registers.set_sbreadondata(unpack(data[15]));
            if(data[22] == 1'b1) begin
                i_registers.set_sbbusyerror(False);
            end
            i_registers.set_sberror(i_registers.sberror & ~data[14:12]);
        end
    endrule

    rule r_sbaddress0_write if(i_registers.first_write matches tagged SBAddress0Write .data);
        i_registers.deq_write;
        if(i_registers.dmactive) begin
            if(rg_sba_state != SBA_IDLE) begin
                i_registers.set_sbbusyerror(True);
            end
            else begin
                i_registers.set_sbaddress0(data);
                if(i_registers.sbreadonaddr) begin
                    start_sba_read(data);
                end
            end
        end
    endrule

    rule r_sbdata0_write if(i_registers.first_write matches tagged SBData0Write .data);
        i_registers.deq_write;
        if(i_registers.dmactive) begin
            if(rg_sba_state != SBA_IDLE) begin
                i_registers.set_sbbusyerror(True);
            end
            else if(!i_registers.sbbusyerror && i_registers.sberror == 0) begin
                i_registers.set_sbdata0(data);
                start_sba_write(i_registers.sbaddress0, data);
            end
        end
    endrule

    rule r_dmcontrol if(i_registers.first_write matches tagged DMControlWrite .control);
        i_registers.deq_write;
        Bool next_active = unpack(control[0]);
        if(!next_active) begin
            reset_dm_state(False);
        end
        else if(!i_registers.dmactive) begin
            reset_dm_state(True);
        end
        else begin
            i_registers.set_ndmreset(unpack(control[1]));
            rg_halt_request <= unpack(control[31]);

            if(control[28] == 1'b1) begin
                rg_ack_reset <= True;
            end
            if(control[30] == 1'b1 && control[31] == 1'b0 && w_hart_status.halted) begin
                rg_resume_request <= True;
                i_registers.set_resume_ack(False);
            end
            else if(control[30] == 1'b0) begin
                rg_resume_request <= False;
                i_registers.set_resume_ack(False);
            end

            if(w_hart_reset_seen) begin
                i_registers.set_havereset(True);
            end
            else if(control[28] == 1'b1) begin
                i_registers.set_havereset(False);
            end
        end
    endrule

    rule r_track_hart_state if(!i_registers.dmcontrol_write_pending);
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
