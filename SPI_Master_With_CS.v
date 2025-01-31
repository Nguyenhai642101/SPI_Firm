`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/28/2024 11:49:21 PM
// Design Name: 
// Module Name: SPI_Master_With_CS
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

/*=============================================================================*/

/////////////////////////////////////////////////////////////////////////////////
// Description: SPI (Serial Peripheral Interface) Master
//              With single chip-select (AKA Slave Select) capability
//
//              Supports arbitrary length byte transfers.
// 
//              Instantiates a SPI Master and adds single CS.
//              If multiple CS signals are needed, will need to use different
//              module, OR multiplex the CS from this at a higher level.
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
//
//              CLKS_PER_HALF_BIT - Sets frequency of o_SPI_Clk.  o_SPI_Clk is
//              derived from i_Clk.  Set to integer number of clocks for each
//              half-bit of SPI data.  E.g. 100 MHz i_Clk, CLKS_PER_HALF_BIT = 2
//              would create o_SPI_CLK of 25 MHz.  Must be >= 2
//
//              MAX_BYTES_PER_CS - Set to the maximum number of bytes that
//              will be sent during a single CS-low pulse.
// 
//              CS_INACTIVE_CLKS - Sets the amount of time in clock cycles to
//              hold the state of Chip-Selct high (inactive) before next 
//              command is allowed on the line.  Useful if chip requires some
//              time when CS is high between trasnfers.
///////////////////////////////////////////////////////////////////////////////

/*=============================================================================*/

module SPI_Master_With_CS
    #(
        parameter SPI_MODE = 0,
        parameter CLKS_PER_HALF_BIT = 2,
        parameter MAX_BYTES_PER_CS = 2,
        parameter CS_INACTIVE_CLKS = 1
    )(
        // Control/Data Signals
        input       i_Rst_L,        // FPGA Reset
        input       i_Clk,          // FPGA Clock
        
        // MOSI Signal (like TX)
        input [$clog2(MAX_BYTES_PER_CS+1)-1:0] i_MOSI_Count,  // # Bytes per CS low
        input [7:0] i_MOSI_Byte,    // Byte to transmit on MOSI
        input       i_MOSI_DV,      // Data Valid Pulse with i_MOSI_Byte
        output      o_MOSI_Ready,   // Transmit Ready for next byte
        
        // MISO Signal (like RX)
        output reg [$clog2(MAX_BYTES_PER_CS+1)-1:0] o_MISO_Count,// Index MISO byte
        output      o_MISO_DV,      // Data Valid pulse (1 clock cycle)
        output [7:0] o_MISO_Byte,   // Byte received on MISO
        
        // SPI Interface
        output      o_SPI_Clk,
        input       i_SPI_MISO,
        output      o_SPI_MOSI,
        output      o_SPI_CS_n
    );
    
    // local parameter
    localparam IDLE        = 2'b00;
    localparam TRANSFER    = 2'b01;
    localparam CS_INACTIVE = 2'b10;
    
    // Declaration Signal
    reg [1:0] r_SM_CS;
    reg       r_CS_n;
    reg [$clog2(CS_INACTIVE_CLKS)-1:0] r_CS_Inactive_Count;
    reg [$clog2(MAX_BYTES_PER_CS+1)-1:0] r_MOSI_Count;
    wire      w_Master_Ready;
    
    // Instantiate Master
    SPI_Master
    #(
        .SPI_MODE           (SPI_MODE),
        .CLKS_PER_HALF_BIT  (CLKS_PER_HALF_BIT)
    ) SPI_Master_Inst (
        // control/data signals
        .i_Rst_L            (i_Rst_L),      // reset of FPGA
        .i_Clk              (i_Clk),        // clock of FPGA
        
        // MOSI signals
        .i_MOSI_Byte        (i_MOSI_Byte),  // byte to transmit
        .i_MOSI_DV          (i_MOSI_DV),    // data valid pulse
        .o_MOSI_Ready       (w_Master_Ready), // transmit ready for byte
        
        // MISO signals
        .o_MISO_DV          (o_MISO_DV),    // data valid pulse (1 clock cycle)
        .o_MISO_Byte        (o_MISO_Byte),  // byte received on MISO
        
        // SPI interface
        .o_SPI_Clk          (o_SPI_Clk),
        .i_SPI_MISO         (i_SPI_MISO),
        .o_SPI_MOSI         (o_SPI_MOSI)
    );
    
    // Control CS line using state machine
    always @(posedge i_Clk or negedge i_Rst_L)
        begin
            if(~i_Rst_L)
                begin
                    r_SM_CS <= IDLE;
                    r_CS_n <= 1'b1;     // reset to high
                    r_MOSI_Count <= 0;
                    r_CS_Inactive_Count <= CS_INACTIVE_CLKS;
                end
            else
                begin
                    case (r_SM_CS)
                    
                        IDLE:
                            begin
                                if(r_CS_n & i_MOSI_DV)  // start of transmisson
                                    begin
                                        r_MOSI_Count <= i_MOSI_Count - 1'b1; // register MOSI count
                                        r_CS_n <= 1'b0; // drive CS low
                                        r_SM_CS <= TRANSFER; // transfer bytes
                                    end
                            end
                            
                        TRANSFER:
                            begin
                                // wait until SPI is done transferring do next thing
                                if(w_Master_Ready)
                                    begin
                                        if(r_MOSI_Count > 0)
                                            begin
                                                if(i_MOSI_DV)
                                                    begin
                                                        r_MOSI_Count <= r_MOSI_Count - 1'b1;
                                                    end
                                            end
                                        else
                                            begin
                                                r_CS_n <= 1'b1; // done so set CS is high
                                                r_CS_Inactive_Count <= CS_INACTIVE_CLKS;
                                                r_SM_CS <= CS_INACTIVE;
                                            end
                                    end
                            end
                            
                        CS_INACTIVE_CLKS:
                            begin
                                if(r_CS_Inactive_Count > 0)
                                    begin
                                        r_CS_Inactive_Count <= r_CS_Inactive_Count - 1'b1;
                                    end
                                else
                                    begin
                                        r_SM_CS <= IDLE;
                                    end
                            end
                            
                        default:
                            begin
                                r_CS_n <= 1'b1; // done so set CS is high
                                r_SM_CS <= IDLE;
                            end
                    endcase
                end
        end
        
    // Keep track of MISO_Count
    always @(posedge i_Clk)
        begin
            if(r_CS_n)
                begin
                    o_MISO_Count <= 0;
                end
            else if(o_MISO_DV)
                begin
                    o_MISO_Count <= o_MISO_Count + 1'b1;
                end
        end
        
    // output
    assign o_SPI_CS_n = r_CS_n;
    
    assign o_MOSI_Ready = ((r_SM_CS == IDLE) | (r_SM_CS == TRANSFER && w_Master_Ready == 1'b1 && r_MOSI_Count > 0)) & ~i_MOSI_DV;
    
endmodule
