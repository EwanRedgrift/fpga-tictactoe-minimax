module uart_rx #(
    parameter int CLK_FREQ  = 125_000_000, 
    parameter int BAUD_RATE = 115_200
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       rx_pin,
    output logic [7:0] rx_byte, 
    output logic       rx_valid, 
    output logic       rx_busy 
);

    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    logic rx_sync_1;
    logic rx_sync;

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_sync_1 <= 1'b1;
            rx_sync   <= 1'b1;
        end else begin
            rx_sync_1 <= rx_pin;
            rx_sync   <= rx_sync_1;
        end
    end

    typedef enum logic [1:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT
    } state_t;

    state_t state;

    logic [$clog2(CLKS_PER_BIT)-1:0] clk_count;
    logic [2:0]                      bit_index;
    logic [7:0]                      rx_shift;

    assign rx_busy = (state != IDLE);

    always_ff @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            rx_valid  <= 1'b0;
            rx_byte   <= '0;
            clk_count <= '0;
            bit_index <= '0;
            rx_shift  <= '0;
        end else begin
            rx_valid <= 1'b0;

            case (state)
                IDLE: begin
                    clk_count <= '0;
                    bit_index <= '0;


                    if (rx_sync == 1'b0) begin
                        state <= START_BIT;
                    end
                end

                START_BIT: begin
                    // Sample at the middle of the start bit period
                    if (clk_count == (CLKS_PER_BIT - 1) / 2) begin
                        if (rx_sync == 1'b0) begin
                            clk_count <= '0;    
                            state     <= DATA_BITS;
                        end else begin
                            state     <= IDLE; 
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                DATA_BITS: begin
                    // Wait 1 full bit period to hit the middle of the current data bit
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= '0;
                        rx_shift[bit_index] <= rx_sync; // Shift in LSB first

                        if (bit_index < 3'd7) begin
                            bit_index <= bit_index + 1'b1;
                        end else begin
                            bit_index <= '0;
                            state     <= STOP_BIT;
                        end
                    end
                end

                STOP_BIT: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= '0;
                        
                        if (rx_sync == 1'b1) begin
                            rx_byte  <= rx_shift;
                            rx_valid <= 1'b1;
                        end
                        
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
