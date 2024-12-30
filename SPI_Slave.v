`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/31/2024 12:14:46 AM
// Design Name: 
// Module Name: SPI_Slave
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

/*==============================================================================*/

/////////////////////////////////////////////////////////////////////////////////
// Description: SPI (Serial Peripheral Interface) Slave
//              Creates slave based on input configuration.
//              Receives a byte one bit at a time on MOSI
//              Will also push out byte data one bit at a time on MISO.  
//              Any data on input byte will be shipped out on MISO.
//              Supports multiple bytes per transaction when CS_n is kept 
//              low during the transaction.
//
// Note:        i_Clk must be at least 4x faster than i_SPI_Clk
//              MISO is tri-stated when not communicating.  Allows for multiple
//              SPI Slaves on the same interface.
//
// Parameters:  SPI_MODE, can be 0, 1, 2, or 3.  See above.
//              Can be configured in one of 4 modes:
//              Mode | Clock Polarity (CPOL/CKP) | Clock Phase (CPHA)
//               0   |             0             |        0
//               1   |             0             |        1
//               2   |             1             |        0
//               3   |             1             |        1
//              More info: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface_Bus#Mode_numbers
//////////////////////////////////////////////////////////////////////////////////

/*==============================================================================*/

module SPI_Slave
    #(
        parameter SPI_MODE = 0
    )(
        // Control/Data Signals
        input       i_Rst_L,    // FPGA Reset, active low
        input       i_Clk,      // FPGA Clock
        output reg  o_MISO_DV,  // data valid pulse (1 clock cycle)
        output reg [7:0] o_MISO_Byte, // byte received on MOSI
        input       i_MOSI_DV,  // data valid pulse to register i_MOSI_Byte
        input [7:0] i_MOSI_Byte,// Byte to serialize to MISO
        
        // SPI Interface
        input       i_SPI_Clk,
        output reg  o_SPI_MISO, 
        input       i_SPI_MOSI,
        input       i_SPI_CS_n // active low
    );
    
    // signal declaration
    wire w_CPOL;    // clock polarity
    wire w_CPHA;    // clock phase
    wire w_SPI_Clk; // inverted/non-inverted depending on settings
    wire w_SPI_MISO_Mux;
    
    reg [2:0] r_MISO_Bit_Count;
    reg [2:0] r_MOSI_Bit_Count;
    reg [7:0] r_Temp_MISO_Byte;
    reg [7:0] r_MISO_Byte;
    reg r_MISO_Done, r2_MISO_Done, r3_MISO_Done;
    reg [7:0] r_MOSI_Byte;
    reg r_SPI_MISO_Bit, r_Preload_MISO;
    
    // CPOL: Clock polarity
    // CPOL = 0 means clock idles at 0, leading edge is rising edge
    // CPOL = 1 means clock idles at 1, leading edge is falling edge
    assign w_CPOL = (SPI_MODE == 2)|(SPI_MODE == 3);
    
    // CPHA: clock phase
    // CPHA = 0 means the "out" side changes the data on trailing edge of clock
    //                the "in" side captures the data on leading edge of clock
    // CPHA = 1 means the "out" side changes the data on leading edge of clock
    //                the "in" side captures data on the trailing edge of clock
    assign w_CPHA = (SPI_MODE == 1)|(SPI_MODE == 3);
    
    assign w_SPI_Clk = w_CPHA ? ~i_SPI_Clk : i_SPI_Clk;
    
    // purpose: recover SPI byte in SPI clock domain
    // samples line on correct edge of SPI clock
    always @(posedge w_SPI_Clk or posedge i_SPI_CS_n)
        begin
            if(i_SPI_CS_n)
                begin
                    r_MISO_Bit_Count <= 0;
                    r_MISO_Done <= 0;
                end
            else
                begin
                    r_MISO_Bit_Count <= r_MISO_Bit_Count + 1;
                    
                    // receive in LSB, shift up to MSB
                    r_Temp_MISO_Byte <= {r_Temp_MISO_Byte[6:0], i_SPI_MOSI};
                    
                    if(r_MISO_Bit_Count == 3'b111)
                        begin
                            r_MISO_Done <= 1'b1;
                            r_MISO_Byte <= {r_Temp_MISO_Byte[6:0], i_SPI_MOSI};
                        end
                    else if(r_MISO_Bit_Count == 3'b010)
                        begin
                            r_MISO_Done <= 1'b0;
                        end
                end
        end
        
    // purpose: cross from SPI clock domain to main FPGA clock domain
    // assert o_MISO_DV for  clock cycle when o_MISO_Byte has valid data
    always @(posedge i_Clk or negedge i_Rst_L)
        begin
            if(i_Rst_L)
                begin
                    r2_MISO_Done <= 1'b0;
                    r3_MISO_Done <= 1'b0;
                    o_MISO_DV <= 1'b0;
                    o_MISO_Byte <= 8'h00;
                end
            else
                begin
                    // here is where clock domain are crossed
                    // this will require timing constraint created, can set up long path
                    r2_MISO_Done <= r_MISO_Done;
                    r3_MISO_Done <= r2_MISO_Done;
                    
                    if(r3_MISO_Done == 1'b0 && r2_MISO_Done == 1'b1)  // rising edge
                        begin
                            o_MISO_DV <= 1'b1; // pulse data alid 1 clock cycle
                            o_MISO_Byte <= r_MISO_Byte;
                        end
                    else
                        begin
                            o_MISO_DV <= 1'b0;
                        end
                end
        end
        
    // control preload signal. should be 1 when CS id high but as soon as
    // first clock edge is seen it goes low.
    always @(posedge w_SPI_Clk or posedge i_SPI_CS_n)
        begin
            if(i_SPI_CS_n)
                begin
                    r_Preload_MISO = 1'b1;
                end
            else
                begin
                    r_Preload_MISO = 1'b0;
                end
        end
    
    // purpose: transmit 1 SPI byte whenever SPI clock is toggling
    // will transmit read data back to SW over MISO time
    // want to put data on the line immediately when CS goes low.
    always @(posedge w_SPI_Clk or posedge i_SPI_CS_n)
        begin
            if(i_SPI_CS_n)
                begin
                    r_MOSI_Bit_Count = 3'b111; // send MSB first
                    r_SPI_MISO_Bit <= r_MOSI_Byte[3'b111]; // reset to MSB
                end
            else
                begin
                    r_MOSI_Bit_Count <= r_MOSI_Bit_Count - 1;
                    
                    // here is where data crosses clock domains from i_Clk to w_SPI_Clk
                    // can set up a timing constraint with wide margin for data path
                    r_SPI_MISO_Bit <= r_MOSI_Byte[r_MOSI_Bit_Count];
                end
        end
        
    // purpose: register MOSI Bte when DV pulse comes. Keeps registed bte in
    // this module to get serialized and sent back to master
    always @(posedge i_Clk or negedge i_Rst_L)
        begin
            if(~i_Rst_L)
                begin
                    r_MOSI_Byte <= 8'h00;
                end
            else
                begin
                    if(i_MOSI_DV)
                        begin
                            r_MOSI_Byte <= i_MOSI_Byte;
                        end
                end
        end
        
    // preload MISO with top bit of send data when preload selector is high
    // otherwise just send the normal MISO data
    assign w_SPI_MISO_Mux = r_Preload_MISO ? r_MOSI_Byte[3'b111] : r_SPI_MISO_Bit;
    
    // tri-state MISO when CS is high. Allows for multiple slaves to talk
    assign o_SPI_MISO = i_SPI_CS_n ? 1'bZ : w_SPI_MISO_Mux;
    
endmodule
