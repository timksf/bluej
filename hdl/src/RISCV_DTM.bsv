package RISCV_DTM;

import DReg :: *;
import FIFOF :: *;
import GetPut :: *;
import ClientServer :: *;
import ModuleCollect :: *;

import BlueCSRCore :: *;

import JTAG_Reg :: *;
import JTAG_Types :: *;
import RISCV_DMI :: *;

interface RISCVDTMRegisterState_ifc#(numeric type abits);
    method Bit#(2) dmistat;
    method Action set_dmistat(Bit#(2) value);

    method DMI_Scan_t#(abits) dmi;
    method Action set_dmi(DMI_Scan_t#(abits) value);
endinterface

module [BlueCSRCtx_t#(8, 72)] riscv_dtm_register_map(RISCVDTMRegisterState_ifc#(abits))
    provisos(
        Add#(abits, 34, dmi_width),
        Add#(dmi_width, dmi_padding, 72),
        Add#(abits, register_padding, 72)
    );

    csr_regmap_def("riscvJTAGDTM", "RISC-V Debug Transport Module registers");

    csr_reg_def('h00, "DTMCS", "DTM Control and Status");
    csr_reg_rc('h00, Bit#(4)'(1),                 0, "VERSION",      "Version",        "RISC-V Debug Specification version 0.13.");
    csr_reg_rc('h00, Bit#(6)'(fromInteger(valueOf(abits))), 4, "ABITS", "Address Bits", "DMI address width.");
    Reg#(Bit#(2)) rg_dmistat <- csr_reg_ro('h00, 0, 10, "DMISTAT", "DMI Status",     "Sticky DMI transaction status.");
    csr_reg_rc('h00, Bit#(3)'(0),                12, "IDLE",         "Idle Hint",      "No additional Run-Test/Idle cycles requested.");
    csr_reg_wo('h00, Bit#(1)'(0),                16, "DMIRESET",     "DMI Reset",      "Write-one command decoded by the DTM.");
    csr_reg_wo('h00, Bit#(1)'(0),                17, "DMIHARDRESET", "DMI Hard Reset", "Write-one command decoded by the DTM.");

    csr_reg_def('h09, "DMI", "Debug Module Interface Access");
    Reg#(DMI_Op_t)    rg_dmi_op      <- csr_reg_rw('h09, DMI_NOP, 0,  "OP",      "Operation", "DMI request or response operation.");
    Reg#(Bit#(32))    rg_dmi_data    <- csr_reg_rw('h09, 0,       2,  "DATA",    "Data",      "DMI request or response data.");
    Reg#(Bit#(abits)) rg_dmi_address <- csr_reg_rw('h09, 0,       34, "ADDRESS", "Address",   "DMI word address.");

    method dmistat = rg_dmistat;
    method Action set_dmistat(Bit#(2) value);
        rg_dmistat <= value;
    endmethod

    method DMI_Scan_t#(abits) dmi;
        return DMI_Scan_t {
            address: rg_dmi_address,
            data:    rg_dmi_data,
            op:      rg_dmi_op
        };
    endmethod

    method Action set_dmi(DMI_Scan_t#(abits) value);
        rg_dmi_address <= value.address;
        rg_dmi_data    <= value.data;
        rg_dmi_op      <= value.op;
    endmethod

endmodule

module [Module] mkRISCVDTMRegisters(RISCVDTMRegisterState_ifc#(abits))
    provisos(
        Add#(abits, 34, dmi_width),
        Add#(dmi_width, dmi_padding, 72),
        Add#(abits, register_padding, 72)
    );

    let {registers, _entries} <- getCollection(riscv_dtm_register_map);
    return registers;

endmodule

interface RISCVDTM_ifc#(numeric type abits);
    method Bit#(32) dtmcs;
    method DMI_Scan_t#(abits) dmi;

    method Action update_dtmcs(Bit#(32) value);
    method Action update_dmi(DMI_Scan_t#(abits) value);
    method Action capture_dmi;

    method Bool hard_reset;
    interface Client#(DMI_Request_t#(abits), DMI_Response_t#(abits)) dmi_bus;
endinterface

module [Module] mkRISCVDTM(RISCVDTM_ifc#(abits))
    provisos(
        Add#(7, abits_extra, abits),
        Add#(abits, abits_unused, 32),
        Add#(abits, 34, dmi_width),
        Add#(dmi_width, dmi_padding, 72),
        Add#(abits, register_padding, 72)
    );

    RISCVDTMRegisterState_ifc#(abits) i_registers <- mkRISCVDTMRegisters;

    FIFOF#(DMI_Request_t#(abits))  f_request  <- mkFIFOF;
    FIFOF#(DMI_Response_t#(abits)) f_response <- mkFIFOF;

    Reg#(Bool)    rg_outstanding <- mkReg(False);
    Reg#(Bit#(1)) rg_epoch       <- mkReg(0);

    Wire#(Maybe#(Bit#(32)))             w_dtmcs_update <- mkDWire(tagged Invalid);
    Wire#(Maybe#(DMI_Scan_t#(abits)))   w_dmi_update   <- mkDWire(tagged Invalid);
    Wire#(Bool)                         w_dmi_capture  <- mkDWire(False);
    Wire#(Bool)                         w_hard_reset   <- mkDWire(False);

    rule r_update_state;
        Bit#(2) status = i_registers.dmistat;
        Bool outstanding = rg_outstanding;
        Bit#(1) epoch = rg_epoch;
        DMI_Scan_t#(abits) scan = i_registers.dmi;

        if(f_response.notEmpty) begin
            let response = f_response.first;
            f_response.deq;
            if(response.epoch == epoch) begin
                outstanding = False;
                scan.address = response.address;
                scan.data = response.data;
                scan.op = response.error ? DMI_WRITE : DMI_NOP;
                if(response.error) begin
                    status = 2;
                end
            end
        end

        if(w_dtmcs_update matches tagged Valid .dtmcs_value) begin
            if(dtmcs_value[17] == 1'b1) begin
                epoch = ~epoch;
                outstanding = False;
                status = 0;
                scan = unpack(0);
                w_hard_reset <= True;
            end
            else if(dtmcs_value[16] == 1'b1) begin
                status = 0;
            end
        end

        if(w_dmi_update matches tagged Valid .request_scan) begin
            if(status == 0) begin
                if(request_scan.op == DMI_READ || request_scan.op == DMI_WRITE) begin
                    if(outstanding || !f_request.notFull) begin
                        status = 3;
                    end
                    else begin
                        f_request.enq(DMI_Request_t {
                            address: request_scan.address,
                            data:    request_scan.data,
                            op:      request_scan.op,
                            epoch:   epoch
                        });
                        outstanding = True;
                        scan = request_scan;
                    end
                end
            end
        end

        if(w_dmi_capture && status == 0 && outstanding) begin
            status = 3;
        end

        rg_outstanding <= outstanding;
        rg_epoch <= epoch;
        i_registers.set_dmistat(status);
        i_registers.set_dmi(scan);
    endrule

    method Bit#(32) dtmcs;
        Bit#(32) value = 0;
        value[3:0]   = 1;
        value[9:4]   = fromInteger(valueOf(abits));
        value[11:10] = i_registers.dmistat;
        value[14:12] = 0;
        return value;
    endmethod

    method DMI_Scan_t#(abits) dmi;
        let value = i_registers.dmi;
        if(i_registers.dmistat != 0) begin
            value.op = unpack(i_registers.dmistat);
        end
        else if(rg_outstanding) begin
            value.op = DMI_RESERVED;
        end
        return value;
    endmethod

    method Action update_dtmcs(Bit#(32) value);
        w_dtmcs_update <= tagged Valid value;
    endmethod

    method Action update_dmi(DMI_Scan_t#(abits) value);
        w_dmi_update <= tagged Valid value;
    endmethod
    method capture_dmi = w_dmi_capture._write(True);

    method hard_reset = w_hard_reset;

    interface Client dmi_bus;
        interface request  = toGet(f_request);
        interface response = toPut(f_response);
    endinterface

endmodule

module mkRISCVDMIScanReg#(RISCVDTM_ifc#(abits) dtm)(JTAG_Reg_ifc#(DMI_Scan_t#(abits)))
    provisos(Add#(abits, 34, dmi_width));

    Reg#(Bit#(dmi_width)) rg_shift <- mkReg(0);
    Reg#(DMI_Scan_t#(abits)) rg_hold <- mkReg(unpack(0));
    Reg#(Bool) rg_written <- mkDReg(False);

    Wire#(Bit#(1)) w_tdi     <- mkBypassWire;
    Wire#(Bool)    w_capture <- mkBypassWire;
    Wire#(Bool)    w_shift   <- mkBypassWire;
    Wire#(Bool)    w_update  <- mkBypassWire;
    Wire#(Bool)    w_select  <- mkBypassWire;

    (* mutually_exclusive = "r_capture, r_shift, r_update" *)
    rule r_capture if(w_capture && w_select);
        rg_shift <= pack(dtm.dmi);
        dtm.capture_dmi;
    endrule

    rule r_shift if(w_shift && w_select);
        Bit#(dmi_width) tdi_msb = w_tdi == 1'b1 ? (1 << (valueOf(dmi_width) - 1)) : 0;
        rg_shift <= (rg_shift >> 1) | tdi_msb;
    endrule

    rule r_update if(w_update && w_select);
        let value = unpack(rg_shift);
        rg_hold <= value;
        rg_written <= True;
        dtm.update_dmi(value);
    endrule

    method reg_o = rg_hold;
    method wr_o = rg_written;
    method Action load(DMI_Scan_t#(abits) value);
        rg_hold <= value;
    endmethod

    method tdo = rg_shift[0];
    method tdi = w_tdi._write;

    interface JTAG_Ctrl_Dn_ifc ctrl;
        method capture = w_capture._write;
        method shift   = w_shift._write;
        method update  = w_update._write;
        method sel     = w_select._write;
    endinterface

endmodule

endpackage
