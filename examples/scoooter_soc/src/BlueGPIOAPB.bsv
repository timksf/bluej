package BlueGPIOAPB;

import BlueCSR :: *;
import BlueGPIO :: *;
import BlueFabric :: *;

interface BlueGPIOAPB_ifc#(numeric type n);
    (* always_enabled *) method Action input_value(Bit#(n) value);
    (* always_ready *) method Bit#(n) output_value;
    (* always_ready *) method Bit#(n) output_enable;
    (* always_ready *) method Bool interrupt;
    interface ApbSlaveFabric_ifc#(32, 32, 0) s_apb;
endinterface

module [Module] mkBlueGPIOAPB(BlueGPIOAPB_ifc#(n)) provisos(Add#(n, unused, 32));
    BlueGPIO_ifc#(n, 32) i_gpio <- mkBlueGPIO;
    BlueCSR_APB_ifc#(32, 32, 0, n) i_apb <- mkBlueCSRAPBAdapter(i_gpio.csr, True);

    method input_value = i_gpio.pins.input_value;
    method output_value = i_gpio.pins.output_value;
    method output_enable = i_gpio.pins.output_enable;
    method interrupt = unpack(|i_gpio.irq.interrupts);
    interface s_apb = i_apb.s_apb;
endmodule

endpackage
