package BlueUartAPB;

import GetPut :: *;

import BlueCSR :: *;
import BlueFabric :: *;
import UartRegs :: *;
import UartRx :: *;
import UartTx :: *;

interface BlueUartAPB_ifc;
    (* always_enabled *) method Action rx(Bit#(1) value);
    (* always_ready *) method Bit#(1) tx;
    interface ApbSlaveFabric_ifc#(32, 32, 0) s_apb;
endinterface

module [Module] mkBlueUartAPB#(Integer rx_buffer, Integer tx_buffer)(BlueUartAPB_ifc);
    BlueCSRAccess_ifc#(32, 32, 0, UartRegs) i_csrs <- create_blue_csr(uart_csrs(True), False);
    BlueCSR_APB_ifc#(32, 32, 0, 0) i_apb <- mkBlueCSRAPBAdapter(i_csrs.external, True);
    Bit#(2) stop_bits = i_csrs.internal.ctrl_s2 ? 2 : 1;
    UartTx#(8) i_tx <- mkUartTxBuffered(stop_bits, i_csrs.internal.prescaler, tx_buffer);
    UartRx#(8) i_rx <- mkUartRxBuffered(stop_bits, i_csrs.internal.prescaler, rx_buffer);

    rule r_errors;
        i_csrs.internal.frame_error(i_rx.frame_error);
        i_csrs.internal.ovflw_error(i_rx.ovflw_error);
    endrule

    rule r_status;
        i_csrs.internal.tx_busy(i_tx.busy);
        i_csrs.internal.rx_busy(i_rx.busy);
        i_csrs.internal.tx_ready(i_csrs.internal.tx_data_ready);
        i_csrs.internal.rx_valid(i_csrs.internal.rx_data_valid);
    endrule

    rule r_transmit if(i_csrs.internal.ctrl_en && i_csrs.internal.tx_data_valid);
        i_tx.transmit.put(i_csrs.internal.tx_data_first);
        i_csrs.internal.tx_data_deq;
    endrule

    rule r_receive if(i_csrs.internal.rx_data_ready);
        let data <- i_rx.receive.get;
        i_csrs.internal.rx_data_enq(data);
    endrule

    method Action rx(Bit#(1) value);
        i_rx.rx(i_csrs.internal.ctrl_en ? value : 1);
    endmethod

    method tx = i_tx.tx;
    interface s_apb = i_apb.s_apb;
endmodule

endpackage
