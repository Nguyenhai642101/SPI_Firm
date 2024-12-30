`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/28/2024 09:36:07 AM
// Design Name: 
// Module Name: SPI_Master
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

/*===============================================================================*/

/////////////////////////////////////////////////////////////////////////////////
// Description: SPI (Serial Peripheral Interface) Master
//              Creates master based on input configuration.
//              Sends a byte one bit at a time on MOSI
//              Will also receive byte data one bit at a time on MISO.
//              Any data on input byte will be shipped out on MOSI.
//
//              To kick-off transaction, user must pulse i_MOSI_DV.
//              This module supports multi-byte transmissions by pulsing
//              i_MOSI_DV and loading up i_MOSI_Byte when o_MOSI_Ready is high.
//
//              This module is only responsible for controlling Clk, MOSI, 
//              and MISO.  If the SPI peripheral requires a chip-select, 
//              this must be done at a higher level.
//
// Note:        i_Clk must be at least 2x faster than i_SPI_Clk
//
// Parameters:  SPI_MODE, can be 0, 1, 2, or 3.  See above.
//              Can be configured in one of 4 modes:
//              Mode | Clock Polarity (CPOL/CKP) | Clock Phase (CPHA)
//               0   |             0             |        0
//               1   |             0             |        1
//               2   |             1             |        0
//               3   |             1             |        1
//              More: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface_Bus#Mode_numbers
//              CLKS_PER_HALF_BIT - Sets frequency of o_SPI_Clk.  o_SPI_Clk is
//              derived from i_Clk.  Set to integer number of clocks for each
//              half-bit of SPI data.  E.g. 100 MHz i_Clk, CLKS_PER_HALF_BIT = 2
//              would create o_SPI_CLK of 25 MHz.  Must be >= 2
//
///////////////////////////////////////////////////////////////////////////////

module SPI_Master #(
        parameter SPI_MODE = 0,
        parameter CLKS_PER_HALF_BIT = 2
    )(
        // Control/Data signals
        input       i_Clk,          // FPGA Clock
        input       i_Rst_L,        // FPGA Reset
        
        // MOSI Signal (like TX)
        input [7:0] i_MOSI_Byte,    // Byte to transmit on MOSI
        input       i_MOSI_DV,      // Data Valid Pulse with i_MOSI_Byte
        output reg  o_MOSI_Ready,   // Transmit Ready for next Byte
        
        // MISO Signal (like RX)
        output reg  o_MISO_DV,        // Data Valid Pulse ( 1 clock cycle)
        output reg  [7:0] o_MISO_Byte,// Byte received on MISO
        
        // SPI Interface
        output reg  o_SPI_Clk,      
        input       i_SPI_MISO,
        output reg  o_SPI_MOSI
    );
    
    // SPI Interface (All runs at SPI Clock Domain)
    wire w_CPOL;    // Clock polarity
    wire w_CPHA;    // Clock phase
    
    reg [$clog2(CLKS_PER_HALF_BIT*2)-1:0] r_SPI_Clk_Count;
    reg r_SPI_Clk;
    reg [4:0] r_SPI_Clk_Edges;
    reg r_Leading_Edge;
    reg r_Trailing_Edge;
    reg r_MOSI_DV;
    reg [7:0] r_MOSI_Byte;
    
    reg [2:0] r_MISO_Bit_Count;
    reg [2:0] r_MOSI_Bit_Count;
    
    // CPOL: Clock Polarity
    // CPOL = 0 means clock idles at 0, leading edge is rising edge
    // CPOL = 1 means clock idles at 1, leading edge is falling edge
    assign w_CPOL = (SPI_MODE == 2) | (SPI_MODE == 3);
    
    // CPHA: Clock Phase
    // CPHA = 0 means the "out" side changes the data on trailing edge of clock
    //                the "in" side captures data on leading edge of clock
    // CPHA = 1 means the "out" side changes the data on leading edge of clock
    //                the "in" side captures data on the trailinh edge of clock
    assign w_CPHA = (SPI_MODE == 1)|(SPI_MODE == 3);
    
    // Generate SPI Clock correct number of times when DV pulse comes
    always @(posedge i_Clk or negedge i_Rst_L)
        begin
            if(i_Rst_L == 0)
                begin
                    o_MOSI_Ready <= 1'b0;
                    r_SPI_Clk_Edges <= 0;
                    r_Leading_Edge <= 1'b0;
                    r_Trailing_Edge <= 1'b0;
                    r_SPI_Clk <= w_CPOL; // assign ddefault state to idle state
                    r_SPI_Clk_Count <= 0;
                end
            else
                begin
                    // Default assignment
                    r_Leading_Edge <= 1'b0;
                    r_Trailing_Edge <= 1'b0;
                    
                    if(i_MOSI_DV)
                        begin
                            o_MOSI_Ready <= 1'b0;
                            r_SPI_Clk_Edges <= 16; // Total # edges in one byte always 16
                        end
                    else if(r_SPI_Clk_Edges > 0)
                        begin
                            o_MOSI_Ready <= 1'b0;
                            
                            if(r_SPI_Clk_Count == CLKS_PER_HALF_BIT * 2-1)
                                begin
                                    r_SPI_Clk_Edges <= r_SPI_Clk_Edges - 1'b1;
                                    r_Trailing_Edge <= 1'b1;
                                    r_SPI_Clk_Count <= 0;
                                    r_SPI_Clk <= ~r_SPI_Clk;
                                end
                            else if(r_SPI_Clk_Count == CLKS_PER_HALF_BIT - 1)
                                begin
                                    r_SPI_Clk_Edges <= r_SPI_Clk_Edges - 1'b1;
                                    r_Leading_Edge <= 1'b1;
                                    r_SPI_Clk_Count <= r_SPI_Clk_Count + 1'b1;
                                    r_SPI_Clk <= r_SPI_Clk;
                                end
                            else
                                begin
                                    r_SPI_Clk_Count <= r_SPI_Clk_Count + 1'b1;
                                end
                        end
                    else
                        begin
                            o_MOSI_Ready <= 1'b1;
                        end
                end
        end
        
    // Register i_MOSI_Byte when Data Valid id pulsed
    // Keep local storage of byte in case higher level module changes the data
    always @(posedge i_Clk or negedge i_Rst_L)
        begin
            if(~i_Rst_L)
                begin
                    r_MOSI_Byte <= 8'h00;
                    r_MOSI_DV <= 1'b0;
                end
            else
                begin
                    r_MOSI_DV <= i_MOSI_DV; // delay 1 clock cycle
                    if(i_MOSI_DV)
                        begin
                            r_MOSI_Byte <= i_MOSI_Byte;
                        end
                end
        end
        
    // Generate MOSI data
    // Work with both CPHA = 0 and CPHA = 1
    always @(posedge i_Clk or negedge i_Rst_L)
        begin
            if (~i_Rst_L)
                begin
                  o_SPI_MOSI     <= 1'b0;
                  r_MOSI_Bit_Count <= 3'b111; // send MSB first
                end
            else
                begin
                    // If ready high, reset bit counts to default
                    if(o_MOSI_Ready)
                        begin
                            r_MOSI_Bit_Count <= 3'b111;
                        end
                    else if(r_MOSI_DV & ~w_CPHA) 
                    // catch the case where start transaction and CPHA = 0
                        begin
                            o_SPI_MOSI <= r_MOSI_Byte[3'b111];
                            r_MOSI_Bit_Count <= 3'b110;
                        end
                    else if((r_Leading_Edge & w_CPHA) | (r_Trailing_Edge & ~w_CPHA))
                        begin
                            r_MOSI_Bit_Count <= r_MOSI_Bit_Count - 1'b1;
                            o_SPI_MOSI <= r_MOSI_Byte[r_MOSI_Bit_Count];
                        end
                end
        end
        
    // Read in MISO data
    always @(posedge i_Clk or negedge i_Rst_L)
        begin
            if(~i_Rst_L)
                begin
                    o_MISO_Byte <= 8'h00;
                    o_MISO_DV <= 1'b0;
                    r_MISO_Bit_Count <= 3'b111;
                end
            else
                begin
                    // default assignment
                    o_MISO_DV <= 1'b0;
                    
                    // check if ready is high, if so reset bit count to default
                    if(o_MOSI_Ready)
                        begin
                            r_MISO_Bit_Count <= 3'b111;
                        end
                    else if((r_Leading_Edge & ~w_CPHA)|(r_Trailing_Edge & w_CPHA))
                        begin
                            o_MISO_Byte[r_MISO_Bit_Count] <= i_SPI_MISO; // sample data
                            r_MISO_Bit_Count <= r_MISO_Bit_Count - 1'b1;
                            if(r_MISO_Bit_Count == 3'b000)
                                begin
                                    o_MISO_DV <= 1'b1; // Byte done, pulse Data Valid
                                end
                        end
                end
        end
        
    // Add clock delay to signals for alignment
    always @(posedge i_Clk or negedge i_Rst_L)
        begin
            if(~i_Rst_L)
                begin
                    o_SPI_Clk <= w_CPOL;
                end
            else
                begin
                    o_SPI_Clk <= r_SPI_Clk;
                end
        end
    
endmodule
