package RISCV_DTM;

import Clocks :: *;
import DReg :: *;
import FIFOF :: *;
import GetPut :: *;
import ClientServer :: *;
import ModuleContext :: *;

import AXI4_Lite_Master :: *;

import JTAG_Reg :: *;
import JTAG_System :: *;
import JTAG_Types :: *;
import RISCV_DMI :: *;

interface RISCVDTMDevice_ifc#(numeric type abits);
    method Bool hard_reset;
    interface AXI4_Lite_Master_Rd_Fab#(32, 32) m_axi_rd;
    interface AXI4_Lite_Master_Wr_Fab#(32, 32) m_axi_wr;
endinterface

module [JTAGSystem#(2, 5)] riscv_dtm#(
    Clock axi_clk,
    Reset axi_rst
)(RISCVDTMDevice_ifc#(abits))
    provisos(
        Add#(7, abits_extra, abits),
        Add#(abits, abits_unused, 32),
        Add#(abits, 34, dmi_width)
    );

    Reg#(Bit#(2))               rg_dmistat    <- mkReg(0);
    Reg#(DMI_Scan_t#(abits))    rg_dmi        <- mkReg(unpack(0));
    Reg#(Bool)                  rg_outstanding <- mkReg(False);
    Reg#(Bit#(1))               rg_epoch       <- mkReg(0);

    FIFOF#(DMI_Request_t#(abits))  f_request  <- mkFIFOF;
    FIFOF#(DMI_Response_t#(abits)) f_response <- mkFIFOF;

    Reg#(Maybe#(Bit#(32)))           rg_dtmcs_update <- mkDReg(tagged Invalid);
    Reg#(Maybe#(DMI_Scan_t#(abits))) rg_dmi_update   <- mkDReg(tagged Invalid);
    Reg#(Bool)                       rg_dmi_capture  <- mkDReg(False);
    Reg#(Bool)                       rg_hard_reset   <- mkDReg(False);

    function Bit#(32) dtmcs_value(Bit#(2) dmistat);
        Bit#(32) value = 0;
        value[3:0]   = 1;
        value[9:4]   = fromInteger(valueOf(abits));
        value[11:10] = dmistat;
        value[14:12] = 0;
        return value;
    endfunction

    function DMI_Scan_t#(abits) dmi_value();
        DMI_Scan_t#(abits) value = rg_dmi;
        if(rg_dmistat != 0) begin
            value.op = unpack(rg_dmistat);
        end
        else if(rg_outstanding) begin
            value.op = DMI_RESERVED;
        end
        return value;
    endfunction

    JTAG_Reg_ifc#(Bit#(32)) i_dtmcs_jtag <- mkJTAGReg(dtmcs_value(rg_dmistat));
    JTAGRegAccess_ifc#(Bit#(32)) i_dtmcs_access <- jtag_endpoint(i_dtmcs_jtag, 5'h10);

    JTAG_Reg_ifc#(DMI_Scan_t#(abits)) i_dmi_jtag <- mkJTAGReg(dmi_value);
    JTAGRegAccess_ifc#(DMI_Scan_t#(abits)) i_dmi_access <- jtag_endpoint(i_dmi_jtag, 5'h11);

    SyncFIFOIfc#(DMI_Request_t#(abits))  f_dmi_request  <- mkSyncFIFOFromCC(2, axi_clk);
    SyncFIFOIfc#(DMI_Response_t#(abits)) f_dmi_response <- mkSyncFIFOToCC(2, axi_clk, axi_rst);
    SyncPulseIfc p_hard_reset <- mkSyncPulseFromCC(axi_clk);

    RISCVDMIAXI4Lite_ifc#(abits) i_dmi_axi <- mkRISCVDMIAXI4Lite(clocked_by axi_clk, reset_by axi_rst);

    rule r_update_dtmcs;
        let value <- i_dtmcs_access.updated;
        rg_dtmcs_update <= tagged Valid value;
    endrule

    rule r_update_dmi;
        let value <- i_dmi_access.updated;
        rg_dmi_update <= tagged Valid value;
    endrule

    rule r_capture_dmi if(i_dmi_jtag.cap_o);
        rg_dmi_capture <= True;
    endrule

    rule r_update_state;
        Bit#(2) status = rg_dmistat;
        Bool outstanding = rg_outstanding;
        Bit#(1) epoch = rg_epoch;
        DMI_Scan_t#(abits) scan = rg_dmi;

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

        if(rg_dtmcs_update matches tagged Valid .dtmcs) begin
            if(dtmcs[17] == 1'b1) begin
                epoch = ~epoch;
                outstanding = False;
                status = 0;
                scan = unpack(0);
                rg_hard_reset <= True;
            end
            else if(dtmcs[16] == 1'b1) begin
                status = 0;
            end
        end

        if(rg_dmi_update matches tagged Valid .request_scan) begin
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

        if(rg_dmi_capture && status == 0 && outstanding) begin
            status = 3;
        end

        rg_dmistat <= status;
        rg_dmi <= scan;
        rg_outstanding <= outstanding;
        rg_epoch <= epoch;
    endrule

    rule r_send_request;
        let request <- toGet(f_request).get;
        f_dmi_request.enq(request);
    endrule

    rule r_receive_response;
        toPut(f_response).put(f_dmi_response.first);
        f_dmi_response.deq;
    endrule

    rule r_cross_hard_reset if(rg_hard_reset);
        p_hard_reset.send;
    endrule

    rule r_axi_request;
        i_dmi_axi.dmi.request.put(f_dmi_request.first);
        f_dmi_request.deq;
    endrule

    rule r_axi_response;
        let response <- i_dmi_axi.dmi.response.get;
        f_dmi_response.enq(response);
    endrule

    method hard_reset = p_hard_reset.pulse;
    interface m_axi_rd = i_dmi_axi.m_rd;
    interface m_axi_wr = i_dmi_axi.m_wr;

endmodule

module [JTAGSystem#(2, 5)] riscv_dtm_system#(
    JTAG_TAP_Meta_Config_t tap_meta,
    Clock axi_clk,
    Reset axi_rst
)(RISCVDTMDevice_ifc#(abits))
    provisos(
        Add#(7, abits_extra, abits),
        Add#(abits, abits_unused, 32),
        Add#(abits, 34, dmi_width)
    );

    jtag_meta_config(tap_meta.idcode_ver, tap_meta.idcode_man, tap_meta.idcode_part);
    jtag_set_reg_tdo(True);
    jtag_set_idcode_instr(5'h01);
    jtag_rst_to_idcode;

    let i_dtm <- riscv_dtm(axi_clk, axi_rst);
    return i_dtm;

endmodule

module [Module] mkRISCVDTMAXI4Lite#(
    JTAG_TAP_Meta_Config_t tap_meta,
    Clock tdo_clk,
    Reset tdo_rst,
    Clock axi_clk,
    Reset axi_rst
)(JTAGSystem_ifc#(RISCVDTMDevice_ifc#(abits)))
    provisos(
        Add#(7, abits_extra, abits),
        Add#(abits, abits_unused, 32),
        Add#(abits, 34, dmi_width)
    );

    let system <- build_jtag_system(
        riscv_dtm_system(tap_meta, axi_clk, axi_rst),
        tdo_clk,
        tdo_rst
    );
    return system;

endmodule

endpackage
