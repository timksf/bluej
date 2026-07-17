package TestRISCVDMIAXI4Lite;

import Connectable :: *;
import GetPut :: *;
import ClientServer :: *;
import StmtFSM :: *;

import TestHelper :: *;

import AXI4_Lite_Types :: *;
import AXI4_Lite_Master :: *;
import AXI4_Lite_Slave :: *;
import RISCV_DMI :: *;

typedef 7 TestABits;

module [Module] mkTestRISCVDMIAXI4Lite(TestHandler);

    RISCVDMIAXI4Lite_ifc#(TestABits) dut <- mkRISCVDMIAXI4Lite;
    AXI4_Lite_Slave_Rd#(32, 32) i_axi_rd <- mkAXI4_Lite_Slave_Rd(2);
    AXI4_Lite_Slave_Wr#(32, 32) i_axi_wr <- mkAXI4_Lite_Slave_Wr(2);

    mkConnection(dut.m_rd, i_axi_rd.fab);
    mkConnection(dut.m_wr, i_axi_wr.fab);

    Reg#(Bool) rg_started <- mkReg(False);

    Stmt test = seq
        dut.dmi.request.put(DMI_Request_t {
            address: 7'h11,
            data:    0,
            op:      DMI_READ,
            epoch:   0
        });
        action
            let request <- i_axi_rd.request.get;
            if(request.addr != 32'h44) begin
                $display("DMI read address was not converted to AXI byte address: %08x", request.addr);
                $finish(1);
            end
            i_axi_rd.response.put(AXI4_Lite_Read_Rs_Pkg {
                data: 32'h12345678,
                resp: OKAY
            });
        endaction
        action
            let response <- dut.dmi.response.get;
            if(response.address != 7'h11 || response.data != 32'h12345678 || response.error || response.epoch != 0) begin
                $display("DMI read response mismatch: ", fshow(response));
                $finish(1);
            end
        endaction

        dut.dmi.request.put(DMI_Request_t {
            address: 7'h10,
            data:    32'hdeadbeef,
            op:      DMI_WRITE,
            epoch:   1
        });
        action
            let request <- i_axi_wr.request.get;
            if(request.addr != 32'h40 || request.data != 32'hdeadbeef || request.strb != 4'hf) begin
                $display("DMI write request mismatch: ", fshow(request));
                $finish(1);
            end
            i_axi_wr.response.put(AXI4_Lite_Write_Rs_Pkg { resp: SLVERR });
        endaction
        action
            let response <- dut.dmi.response.get;
            if(response.address != 7'h10 || !response.error || response.epoch != 1) begin
                $display("AXI error was not mapped to DMI failure: ", fshow(response));
                $finish(1);
            end
        endaction

        $display("RISC-V DMI AXI4-Lite adapter test passed");
    endseq;

    FSM f_test <- mkFSM(test);

    method Action go if(!rg_started);
        rg_started <= True;
        f_test.start;
    endmethod

    method done = rg_started && f_test.done;

endmodule

endpackage
