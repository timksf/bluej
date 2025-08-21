package JTAG_BDPI;

import "BDPI" function ActionValue#(Int#(32)) c_socket_init();
import "BDPI" function ActionValue#(Int#(32)) c_socket_accept(Int#(32) fd);
import "BDPI" function ActionValue#(Int#(32)) c_socket_process(Int#(32) fd, Bit#(1) tdo);

(* always_ready *)
interface JTAG_Driver_ifc;
    method Bit#(1) ext_trst();
    method Bit#(1) ext_tck();
    method Bit#(1) ext_tms();
    method Bit#(1) ext_tdi();
    method Action ext_tdo(Bit#(1) b);
endinterface

module mkJTAG_Driver_OOCD(JTAG_Driver_ifc);

    Reg#(Bit#(1)) tck <- mkWire; //mkRegA(0);
    Reg#(Bit#(1)) tms <- mkWire; //mkRegA(0);
    Reg#(Bit#(1)) tdi <- mkWire; //mkRegA(0);
    Reg#(Bit#(1)) tdo <- mkWire; //mkRegA(0);

    Reg#(Bool) rg_started <- mkReg(False);
    Reg#(Bool) rg_connected <- mkReg(False);
    Reg#(Int#(32)) rg_sock_fd <- mkRegU;
    Reg#(Int#(32)) rg_data_sock_fd <- mkRegU;

    //init listening socket
    rule r_init if(!rg_started);
        let socket_fd <- c_socket_init();
        if(socket_fd != -1) begin
            rg_sock_fd <= socket_fd;
            rg_started <= True;
        end
    endrule

    //accept incoming connections
    rule r_accept if(rg_started && !rg_connected);
        let r <- c_socket_accept(rg_sock_fd);
        if(r != -1) begin
            rg_connected <= True;
            rg_data_sock_fd <= r;
        end
    endrule

    //process incoming commands
    rule r_process if(rg_started && rg_connected);
        let cmd <- c_socket_process(rg_data_sock_fd, tdo);
        //disconnect if bdpi function reports -2
        if(cmd == -2) begin
            rg_connected <= False;
        end else if(cmd >= 0 && cmd <= 7)  begin
            $display("[%0t] CMD: %02x", $time, cmd);
            tck <= pack(cmd)[2];
            tms <= pack(cmd)[1];
            tdi <= pack(cmd)[0];
        end
    endrule

    method ext_trst = 1'b0;
    method ext_tck = tck;
    method ext_tms = tms;
    method ext_tdi = tdi;
    method ext_tdo = tdo._write;
    
endmodule

endpackage