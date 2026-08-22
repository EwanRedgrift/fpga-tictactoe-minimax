package tictactoe_pkg;
    typedef struct packed {
        logic [8:0] x_bitboard;         // board state
        logic [8:0] o_bitboard;
        logic       player_to_move;      // 1 = Max (X), 0 = Min (O)
        logic [8:0] remaining_moves; 
        logic signed [1:0] best_score;  // Current minimax evaluation (-1, 0, +1)
        logic [3:0] bestmove_index; 
        logic [3:0] parent_move_index;
    } node_frame_t;
endpackage

import tictactoe_pkg::*;

module tictactoe (
    input  logic       clk,
    input  logic       rst,
    input  logic       start,
    input  logic [8:0] x_bitboard,  
    input  logic [8:0] o_bitboard,  
    input  logic       max,

    output logic       done,
    output logic       busy,
    output logic [3:0] best_move_index,
    output logic signed [1:0] best_score
);

    typedef enum logic [3:0] {
      IDLE, WAIT_ROOT, EXPAND, CHECK_TERM, WAIT_TERM,
      PUSH_CHILD, WAIT_PUSH, SCORE_LEAF, 
      BACKPROP, WAIT_POP, UPDATE_PARENT, DONE
    } state_t;

    state_t state;

    logic [8:0] live_move_bit;
    logic [3:0] live_move_index;
    logic       live_move_valid;

    logic [8:0] first_root_move_bit;
    logic [3:0] first_root_move_index;
    
    logic [8:0] first_child_move_bit;
    logic [3:0] first_child_move_index;

    // Latched registers
    logic [8:0] latched_move_bit;
    logic [3:0] latched_move_index;

    logic x_wins, o_wins, is_draw, is_terminal;

    logic       stack_push;
    logic       stack_pop;
    logic       stack_update;
    node_frame_t stack_push_data;
    node_frame_t stack_update_data;
    node_frame_t topData;
    logic [3:0] stack_pointer;
    logic       stack_full;
    logic       stack_empty;

    node_frame_t popped_frame; 
    logic signed [1:0] leaf_score;

    logic [8:0] root_legal_moves;
    logic [8:0] child_legal_moves;
    logic [8:0] next_x_bitboard;
    logic [8:0] next_o_bitboard;

    assign busy = (state != IDLE) && (state != DONE);
    assign done = (state == DONE);
    assign best_move_index = popped_frame.bestmove_index;
    assign best_score      = popped_frame.best_score;
  
    localparam logic signed [1:0] SCORE_POS1 = 2'sb01; //  +1
    localparam logic signed [1:0] SCORE_ZERO = 2'sb00; //   0
    localparam logic signed [1:0] SCORE_NEG1 = 2'sb11; //  -1

    logic [8:0] latched_next_x_bitboard;
    logic [8:0] latched_next_o_bitboard;

    always_comb begin
        if (topData.player_to_move) begin // Max's turn (X)
            next_x_bitboard = topData.x_bitboard | latched_move_bit;
            next_o_bitboard = topData.o_bitboard;
        end else begin                  // Min's turn (O)
            next_x_bitboard = topData.x_bitboard;
            next_o_bitboard = topData.o_bitboard | latched_move_bit;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state             <= IDLE;
            stack_push        <= '0;
            stack_pop         <= '0;
            stack_update      <= '0;
            popped_frame      <= '0;
            leaf_score        <= '0;
            latched_move_bit   <= '0;
            latched_move_index <= '0;
            stack_push_data    <= '0;
            stack_update_data  <= '0;
        end else begin
            stack_push   <= '0;
            stack_pop    <= '0;
            stack_update <= '0;

            case (state)
                IDLE: begin
                    if (start) begin
                        stack_push_data.x_bitboard       <= x_bitboard;
                        stack_push_data.o_bitboard       <= o_bitboard;
                        stack_push_data.player_to_move    <= max; 
                        stack_push_data.remaining_moves  <= root_legal_moves;
                        // Max starts with worst score -1; Min starts with worst score +1
                        stack_push_data.best_score       <= max ? SCORE_NEG1 : SCORE_POS1; 
                        stack_push_data.bestmove_index   <= first_root_move_index;  
                        stack_push_data.parent_move_index <= 4'd15;                 
                        
                        stack_push                     <= '1;
                        state                          <= WAIT_ROOT;
                    end
                end

                WAIT_ROOT: begin
                    state <= EXPAND; 
                end

                EXPAND: begin
                    if (topData.remaining_moves != 0) begin
                        latched_move_bit   <= live_move_bit;
                        latched_move_index <= live_move_index;
                        state             <= CHECK_TERM;
                    end else begin
                        state <= BACKPROP; 
                    end
                end

                CHECK_TERM: begin
                    latched_next_x_bitboard <= next_x_bitboard;
                    latched_next_o_bitboard <= next_o_bitboard;
                    state                  <= WAIT_TERM;
                end

                WAIT_TERM: begin
                    if (is_terminal) begin
                        if (x_wins)       leaf_score <= SCORE_POS1;  // +1
                        else if (o_wins)  leaf_score <= SCORE_NEG1;  // -1
                        else             leaf_score <= SCORE_ZERO;  //  0
                        state <= SCORE_LEAF;
                    end else begin
                        stack_update_data                <= topData;
                        stack_update_data.remaining_moves <= topData.remaining_moves & ~latched_move_bit;
                        stack_update                    <= '1;
                        state                            <= PUSH_CHILD;
                    end
                end

                PUSH_CHILD: begin
                    stack_push_data.x_bitboard       <= latched_next_x_bitboard;
                    stack_push_data.o_bitboard       <= latched_next_o_bitboard;
                    stack_push_data.player_to_move    <= ~topData.player_to_move; 
                    stack_push_data.remaining_moves  <= child_legal_moves;
                    // Child player initialization
                    stack_push_data.best_score       <= (~topData.player_to_move) ? SCORE_NEG1 : SCORE_POS1; 
                    stack_push_data.bestmove_index   <= first_child_move_index; 
                    stack_push_data.parent_move_index <= latched_move_index;     
                    
                    stack_push                     <= '1;
                    state                          <= WAIT_PUSH; 
                end

                WAIT_PUSH: begin
                    state <= EXPAND; 
                end

                SCORE_LEAF: begin
                    stack_update_data                <= topData;
                    stack_update_data.remaining_moves <= topData.remaining_moves & ~latched_move_bit;

                    if (topData.player_to_move) begin // max maximizing
                        if ($signed(leaf_score) > $signed(topData.best_score)) begin
                            stack_update_data.best_score     <= leaf_score;
                            stack_update_data.bestmove_index <= latched_move_index;
                        end
                    end else begin                  // max minimizing
                        if ($signed(leaf_score) < $signed(topData.best_score)) begin
                            stack_update_data.best_score     <= leaf_score;
                            stack_update_data.bestmove_index <= latched_move_index;
                        end
                    end
                    stack_update <= '1;
                    state        <= EXPAND; 
                end

                BACKPROP: begin
                    popped_frame <= topData; 
                    stack_pop    <= '1;
                    
                    if (stack_pointer == 4'd1) begin
                        state <= DONE; 
                    end else begin
                        state <= WAIT_POP;
                    end
                end

                WAIT_POP: begin
                    state <= UPDATE_PARENT; 
                end

                UPDATE_PARENT: begin
                    stack_update_data <= topData;
                    stack_update     <= '1;

                    if (topData.player_to_move) begin // Parent is max maximizing
                        if ($signed(popped_frame.best_score) > $signed(topData.best_score)) begin
                            stack_update_data.best_score     <= popped_frame.best_score;
                            stack_update_data.bestmove_index <= popped_frame.parent_move_index; 
                        end
                    end else begin                  // Parent is min minimizing
                        if ($signed(popped_frame.best_score) < $signed(topData.best_score)) begin
                            stack_update_data.best_score     <= popped_frame.best_score;
                            stack_update_data.bestmove_index <= popped_frame.parent_move_index;
                        end
                    end
                    
                    state <= EXPAND; 
                end

                DONE: begin
                    // Done
                end
                
                default: state <= IDLE;
            endcase
        end
    end

    mask root_mask_inst ( 
        .x_bitboard(x_bitboard), .o_bitboard(o_bitboard),
        .occupied(), .legal_moves(root_legal_moves), .invalid()
    );  

    mask child_mask_inst ( 
        .x_bitboard(latched_next_x_bitboard), .o_bitboard(latched_next_o_bitboard),
        .occupied(), .legal_moves(child_legal_moves), .invalid()
    );  

    move_extractor main_move_extractor (
        .remaining_moves(topData.remaining_moves),
        .move_bit(live_move_bit), .move_index(live_move_index), .valid(live_move_valid)
    );

    move_extractor root_seeder (
        .remaining_moves(root_legal_moves),
        .move_bit(first_root_move_bit), .move_index(first_root_move_index), .valid()
    );

    move_extractor child_seeder (
        .remaining_moves(child_legal_moves),
        .move_bit(first_child_move_bit), .move_index(first_child_move_index), .valid()
    );

    terminal_state terminal_state_inst (
        .x_bitboard(latched_next_x_bitboard), .o_bitboard(latched_next_o_bitboard),
        .x_wins(x_wins), .o_wins(o_wins), .is_draw(is_draw), .is_terminal(is_terminal)
    );

    search_stack search_stack_inst (
        .clk(clk), .rst(rst),
        .push(stack_push), .pop(stack_pop), .update(stack_update),
        .pushData(stack_push_data), .updateData(stack_update_data),
        .topData(topData), .stack_pointer(stack_pointer),
        .full(stack_full), .empty(stack_empty)
    );

endmodule

module mask (
    input logic [8:0] x_bitboard,
    input logic [8:0] o_bitboard,
    output logic [8:0] occupied,
    output logic [8:0] legal_moves,
    output logic invalid
);
    assign occupied = x_bitboard | o_bitboard;
    assign legal_moves = ~occupied;
    assign invalid = |(x_bitboard & o_bitboard);
endmodule

module win_check (
    input logic [8:0] board,
    output logic win
);
    localparam logic [8:0] R1 = 9'b111000000;
    localparam logic [8:0] R2 = 9'b000111000;
    localparam logic [8:0] R3 = 9'b000000111;

    localparam logic [8:0] C1 = 9'b100100100;
    localparam logic [8:0] C2 = 9'b010010010;
    localparam logic [8:0] C3 = 9'b001001001;

    localparam logic [8:0] D1 = 9'b100010001;
    localparam logic [8:0] D2 = 9'b001010100;

    assign win = 
        ((board & R1) == R1) ||
        ((board & R2) == R2) ||
        ((board & R3) == R3) ||
        ((board & C1) == C1) ||
        ((board & C2) == C2) ||
        ((board & C3) == C3) ||
        ((board & D1) == D1) ||
        ((board & D2) == D2);
endmodule

module terminal_state (
    input  logic [8:0] x_bitboard,
    input  logic [8:0] o_bitboard,
    output logic       x_wins,
    output logic       o_wins,
    output logic       is_draw,
    output logic       is_terminal
);
    logic [8:0] occupied;

    win_check x_win_inst (.board(x_bitboard), .win(x_wins));
    win_check o_win_inst (.board(o_bitboard), .win(o_wins));
    mask mask_inst (.x_bitboard(x_bitboard), .o_bitboard(o_bitboard), .occupied(occupied), .legal_moves(), .invalid());

    assign is_draw = (~(x_wins | o_wins) && (occupied == 9'b111111111));
    assign is_terminal = x_wins | o_wins | is_draw;
endmodule

module move_extractor (
    input  logic [8:0] remaining_moves,
    output logic [8:0] move_bit,      
    output logic [3:0] move_index,    
    output logic       valid         
);
    logic [8:0] lsb_bit;
    assign lsb_bit = remaining_moves & (~remaining_moves + 1'b1);


    always_comb begin
        move_bit   = lsb_bit;
        valid = |remaining_moves;

        case (lsb_bit)
                9'b000000001: move_index = 4'd0;
                9'b000000010: move_index = 4'd1;
                9'b000000100: move_index = 4'd2;
                9'b000001000: move_index = 4'd3;
                9'b000010000: move_index = 4'd4;
                9'b000100000: move_index = 4'd5;
                9'b001000000: move_index = 4'd6;
                9'b010000000: move_index = 4'd7;
                9'b100000000: move_index = 4'd8;
                default:      move_index = 4'd0;
        endcase
    end
endmodule

module search_stack #(
    parameter int MAX_DEPTH = 10
)(
    input  logic        clk,
    input  logic        rst,
    input  logic        push,
    input  logic        pop,
    input  logic        update,       
    input  node_frame_t  pushData,
    input  node_frame_t  updateData,   
    output node_frame_t  topData,
    output logic [3:0]  stack_pointer, 
    output logic        full,
    output logic        empty
);
    import tictactoe_pkg::*;

    node_frame_t stack_mem [0:MAX_DEPTH-1];

    assign empty = (stack_pointer == 4'd0);
    assign full  = (stack_pointer == MAX_DEPTH);
    assign topData = (empty) ? '0 : stack_mem[stack_pointer - 1];

    always_ff @(posedge clk) begin
        if (rst) begin
            stack_pointer <= '0;
        end else begin
            if (push && !pop && !update && !full) begin
                stack_mem[stack_pointer] <= pushData;
                stack_pointer            <= stack_pointer + 1;
            end 
            else if (pop && !push && !update && !empty) begin
                stack_pointer            <= stack_pointer - 1;
            end 
            else if (update && !push && !pop && !empty) begin
                stack_mem[stack_pointer - 1] <= updateData;
            end
        end
    end
endmodule
