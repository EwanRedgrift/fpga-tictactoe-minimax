module uart_tx #(
    parameter int CLK_FREQ = 125_000_000,
    parameter int BAUD_RATE   = 115_200
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       tx_start,
    input  logic [7:0] tx_data,   // 8-bit byte to send
    output logic       tx_out,
    output logic       tx_busy,   // High while sending data
    output logic       tx_done 
);

    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    typedef enum logic [1:0] {
        IDLE, START_BIT, DATA_BITS, STOP_BIT
    } state_t;
    
    state_t state;

    logic[$clog2(CLKS_PER_BIT)-1:0] clk_count;
    logic [2:0] bit_index;
    logic [7:0] tx_shift;

    assign tx_busy = (state != IDLE);

    always_ff @(posedge clk) begin

        if (rst) begin
            state <= IDLE;
            tx_out <= 1'b1;
            tx_done <= 1'b0;
            clk_count <= '0;
            bit_index <= '0;
            tx_shift <= '0;
        end else begin
            tx_done <= 1'b0;

            case (state)
                IDLE: begin
                    tx_out    <= 1'b1;
                    clk_count <= '0;
                    bit_index <= '0;

                    if (tx_start) begin
                        tx_shift <= tx_data;
                        state <= START_BIT;
                    end
                end

                START_BIT: begin
                    tx_out <= 1'b0;

                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end
                    else begin
                        clk_count <= '0;
                        state <= DATA_BITS;
                    end
                end

                DATA_BITS: begin
                    tx_out <= tx_shift[bit_index];

                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= '0;

                        if (bit_index < 3'd7) begin
                            bit_index <= bit_index + 1'b1;
                        end else begin
                            bit_index <= '0;
                            state <= STOP_BIT;
                        end
                    end
                end

                STOP_BIT: begin
                    tx_out <= 1'b1;

                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= '0;
                        tx_done <= 1'b1;
                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                    tx_out <= 1'b1;
                    clk_count <= '0;
                    bit_index <= '0;
                end
            endcase
        end 
    end
endmodule
