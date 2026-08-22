module tictactoe_top #(
    parameter int CLK_FREQ  = 125_000_000,
    parameter int BAUD_RATE = 115_200
)(
    input  logic clk,
    input  logic rst,
    input  logic rx_pin,
    output logic tx_out
);

    // Uart rx
    logic [7:0] rx_byte;
    logic       rx_valid;
    logic       rx_busy;

    uart_rx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_rx_inst (
        .clk     (clk),
        .rst     (rst),
        .rx_pin  (rx_pin),
        .rx_byte (rx_byte),
        .rx_valid(rx_valid),
        .rx_busy (rx_busy)
    );

    // Uart tx
    logic       tx_start;
    logic [7:0] tx_data;
    logic       tx_busy;
    logic       tx_done;

    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_tx_inst (
        .clk     (clk),
        .rst     (rst),
        .tx_start(tx_start),
        .tx_data (tx_data),
        .tx_out  (tx_out),
        .tx_busy (tx_busy),
        .tx_done (tx_done)
    );

    // ttt search
    logic ttt_rst_local;
    logic ttt_rst;

    assign ttt_rst = rst | ttt_rst_local;

    logic [8:0] x_bitboard;
    logic [8:0] o_bitboard;
    logic       max;

    logic       ttt_start;
    logic       ttt_done;
    logic       ttt_busy;

    logic [3:0] best_move_index;
    logic signed [1:0] best_score;

    tictactoe tictactoe_inst (
        .clk             (clk),
        .rst             (ttt_rst),
        .start           (ttt_start),

        .x_bitboard       (x_bitboard),
        .o_bitboard       (o_bitboard),
        .max             (max),

        .done            (ttt_done),
        .busy            (ttt_busy),
        .best_move_index (best_move_index),
        .best_score      (best_score)
    );

    // Watchdog
    typedef enum logic [3:0] {
        RX_BYTE0,
        RX_BYTE1,
        RX_BYTE2,
        RESET_ENGINE,
        RUN_SEARCH,
        WAIT_SEARCH_DONE,
        TX_SEND,
        WAIT_TX_DONE
    } state_t;

    state_t state;

    logic [7:0] rx_byte0_reg;
    logic [7:0] rx_byte1_reg;

    logic [1:0] reset_hold_count;

    localparam int TIMEOUT_CYCLES = CLK_FREQ / 10;
    logic [$clog2(TIMEOUT_CYCLES)-1:0] timeout_count;

    //Controller

    always_ff @(posedge clk) begin
        if (rst) begin
            state            <= RX_BYTE0;

            x_bitboard        <= '0;
            o_bitboard        <= '0;
            max              <= 1'b1;

            rx_byte0_reg     <= '0;
            rx_byte1_reg     <= '0;

            ttt_start        <= 1'b0;
            ttt_rst_local    <= 1'b0;
            reset_hold_count <= '0;

            tx_start         <= 1'b0;
            tx_data          <= '0;
            timeout_count    <= '0;
        end else begin
            ttt_start     <= 1'b0;
            ttt_rst_local <= 1'b0;
            tx_start      <= 1'b0;

            if (state == RX_BYTE0 || state == RX_BYTE1 || state == RX_BYTE2) begin
                if (rx_valid) begin
                    timeout_count <= '0;
                end else if (timeout_count == TIMEOUT_CYCLES - 1) begin
                    timeout_count <= '0;
                    state         <= RX_BYTE0;
                end else begin
                    timeout_count <= timeout_count + 1'b1;
                end
            end else begin
                timeout_count <= '0;
            end

            case (state)
                RX_BYTE0: begin
                    if (rx_valid) begin
                        rx_byte0_reg <= rx_byte;
                        state <= RX_BYTE1;
                    end
                end

                RX_BYTE1: begin
                    if (rx_valid) begin
                        rx_byte1_reg <= rx_byte;
                        state <= RX_BYTE2;
                    end
                end

                RX_BYTE2: begin
                    if (rx_valid) begin
                        x_bitboard <= {
                            rx_byte[0],
                            rx_byte0_reg
                        };

                        o_bitboard <= {
                            rx_byte[1],
                            rx_byte1_reg
                        };

                        max <= rx_byte[2];

                        reset_hold_count <= '0;

                        state <= RESET_ENGINE;
                    end
                end


                RESET_ENGINE: begin

                    ttt_rst_local <= 1'b1;

                    if (reset_hold_count == 2'd1) begin
                        reset_hold_count <= '0;
                        state <= RUN_SEARCH;
                    end else begin
                        reset_hold_count <= reset_hold_count + 1'b1;
                    end

                end

                RUN_SEARCH: begin

                    ttt_start <= 1'b1;

                    state <= WAIT_SEARCH_DONE;

                end

                WAIT_SEARCH_DONE: begin
                    if (ttt_done) begin
                        tx_data <= {
                            2'b00,
                            best_score,
                            best_move_index
                        };
                        state <= TX_SEND;
                    end

                end

                TX_SEND: begin
                    if (!tx_busy) begin
                        tx_start <= 1'b1;
                        state <= WAIT_TX_DONE;
                    end

                end

                WAIT_TX_DONE: begin
                    if (tx_done) begin
                        state <= RX_BYTE0;
                    end

                end

                default: begin
                    state <= RX_BYTE0;
                end

            endcase
        end
    end

endmodule
