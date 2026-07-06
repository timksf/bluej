package JTAG_BDPI;

import DReg :: *;
import Vector :: *;

import JTAG_Types :: *;

import "BDPI" function ActionValue#(Int#(32)) c_socket_init(Bit#(32) dummy);
import "BDPI" function ActionValue#(Int#(32)) c_socket_accept(Int#(32) fd);
import "BDPI" function ActionValue#(Int#(32)) c_socket_process(Int#(32) fd, Bit#(1) tdo);
import "BDPI" function ActionValue#(Int#(32)) c_send_tdo(Int#(32) fd, Bit#(1) tdo);
import "BDPI" function Action c_print_status();

(* always_ready *)
interface JTAG_Driver_ifc;
    method Bit#(1) ext_trst();
    method Bit#(1) ext_tck();
    method Bit#(1) ext_tms();
    method Bit#(1) ext_tdi();
    method Action ext_tdo(Bit#(1) b);

    method Bool connected();
endinterface

module mkJTAG_Driver_OOCD#(JTAG_TDO_Delay#(n) _unused)(JTAG_Driver_ifc);

    Reg#(Bit#(1)) tck <- mkWire;
    Reg#(Bit#(1)) tms <- mkWire;
    Reg#(Bit#(1)) tdi <- mkWire;
    Reg#(Bit#(1)) tdo <- mkWire;

    Reg#(Bool) rg_started <- mkReg(False);
    Reg#(Bool) rg_connected <- mkReg(False);
    Reg#(Int#(32)) rg_sock_fd <- mkRegU;
    Reg#(Int#(32)) rg_data_sock_fd <- mkRegU;
    Reg#(Bit#(32)) rg_tdo_req_count <- mkReg(0);
    Reg#(Bit#(32)) rg_tdo_resp_count <- mkReg(0);

    //init listening socket
    rule r_init if(!rg_started);
        let socket_fd <- c_socket_init(0);
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

    if(valueof(n) == 0) begin
        //process incoming commands and respond to TDO reads immediately
        rule r_process_no_delay if(rg_started && rg_connected);
            let cmd <- c_socket_process(rg_data_sock_fd, tdo);
            Bool disconnect = cmd == -2;
            Bool tdo_req = cmd >= 0 && unpack(pack(cmd)[16]);

            if(!disconnect && tdo_req) begin
                let ret <- c_send_tdo(rg_data_sock_fd, tdo);
                // if(ret == 0)
                //     c_print_status();
                rg_tdo_resp_count <= rg_tdo_resp_count + 1;
            end

            //disconnect if bdpi function reports -2
            if(disconnect) begin
                rg_connected <= False;
            end else if(cmd >= 0 && cmd <= 7)  begin
                // $display("[%0t] CMD: %02x", $time, cmd);
                tck <= pack(cmd)[2];
                tms <= pack(cmd)[1];
                tdi <= pack(cmd)[0];
            end

            if(tdo_req)
                rg_tdo_req_count <= rg_tdo_req_count + 1;
        endrule
    end else begin
        //TDO arrives delayed based on the TAP/shim implementation
        Vector#(n, Reg#(Bool)) v_rg_send_tdo <- replicateM(mkReg(False));

        //process incoming commands and delay TDO read responses by n cycles
        rule r_process_delayed if(rg_started && rg_connected);
            let cmd <- c_socket_process(rg_data_sock_fd, tdo);
            Bool disconnect = cmd == -2;
            Bool tdo_req = cmd >= 0 && unpack(pack(cmd)[16]);

            if(!disconnect && v_rg_send_tdo[0]) begin
                let ret <- c_send_tdo(rg_data_sock_fd, tdo);
                // if(ret == 0)
                //     c_print_status();
                rg_tdo_resp_count <= rg_tdo_resp_count + 1;
            end

            //disconnect if bdpi function reports -2
            if(disconnect) begin
                rg_connected <= False;
            end else if(cmd >= 0 && cmd <= 7)  begin
                // $display("[%0t] CMD: %02x", $time, cmd);
                tck <= pack(cmd)[2];
                tms <= pack(cmd)[1];
                tdi <= pack(cmd)[0];
            end

            if(tdo_req)
                rg_tdo_req_count <= rg_tdo_req_count + 1;

            for(Integer i = 1; i < valueof(n); i = i + 1)
                v_rg_send_tdo[valueof(n)-1-i] <= !disconnect && v_rg_send_tdo[valueof(n)-i];
            v_rg_send_tdo[valueof(n)-1] <= !disconnect && tdo_req;
        endrule
    end

    method ext_trst = 1'b0;
    method ext_tck = tck;
    method ext_tms = tms;
    method ext_tdi = tdi;
    method ext_tdo = tdo._write;
    
    method connected = rg_connected;

endmodule

endpackage
