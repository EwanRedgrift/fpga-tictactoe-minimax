# FPGA Tic-Tac-Toe Minimax AI

A Tic-Tac-Toe AI implemented in SystemVerilog and running on a PYNQ-Z2 FPGA. The AI uses minimax with a depth-first search (DFS) implementation and an explicit stack instead of recursion. A Python program communicates with the FPGA over UART and provides the interface for playing against the hardware AI.

## Demo

[![AI winning playing as X](https://img.youtube.com/vi/ZjctwWpLDHU/maxresdefault.jpg)](https://youtu.be/ZjctwWpLDHU)
AI winning playing as X.


[![AI winning playing as X](https://img.youtube.com/vi/tpSMH_JPTNU/maxresdefault.jpg)](https://youtu.be/tpSMH_JPTNU)
Draw with AI playing as O.

## Implementation

The board is represented using two 9-bit bitboards, one for X and one for O. Legal moves are generated using bitwise operations, and the eight possible winning combinations are checked using predefined bit masks.

The minimax algorithm is implemented as an iterative depth-first search (DFS). Instead of using recursive function calls, the FPGA maintains an explicit stack of search nodes.

Each stack entry stores the information needed to pause and resume a position in the search:

* X and O board states
* Player to move
* Remaining unexplored moves
* Best score found so far
* Best move found so far
* Move used to reach the node

When a position has an unexplored legal move, the move is removed from the current node's `remaining_moves` mask and a new child position is created. If the position is not terminal, the child is pushed onto the stack and becomes the current node.

This continues until a terminal position is reached. The terminal position is assigned a score of `+1` for a maximizing player win, `0` for a draw, or `-1` for a minimizing player win. The result is then propagated back up the stack. Maximizing nodes keep the highest child score, while minimizing nodes keep the lowest.

Once all moves at a node have been evaluated, the node is popped and its result is passed to its parent. This continues until the root node has been evaluated, at which point its best move is returned.

### Why Minimax Works for Tic-Tac-Toe

Tic-Tac-Toe is a finite, deterministic game with a small enough game tree to search exhaustively. There is no hidden information or randomness, so from any valid board position the outcome of every possible sequence of moves can be evaluated.

Because this implementation searches the game tree using minimax, the FPGA can determine whether a position leads to a win, draw, or loss assuming optimal play from both players.

With optimal play from both sides, Tic-Tac-Toe always ends in a draw. Therefore, the AI is guaranteed to never lose when playing against an optimal opponent. Against an opponent that makes a suboptimal move, the minimax search can instead select a winning line when one exists.

The move ordering is deterministic because the move extractor always selects the lowest-index available move first. When multiple moves have the same minimax score, the lowest-index move is therefore selected.

## FPGA and UART Interface

The FPGA receives the current X and O bitboards and the player to move through UART. It then runs the minimax search and returns the selected move and its score.

The Python frontend maintains the game state, handles human input, communicates with the FPGA using PySerial, and displays the game in the terminal.

## Hardware Results

The design was implemented in Vivado 2025.2 and tested on a PYNQ-Z2 at 125 MHz.

| Resource   | Usage |
| ---------- | ----: |
| LUTs       |   387 |
| Flip-flops |   647 |
| BRAM       |     0 |

### Timing

| Metric |     Slack |
| ------ | --------: |
| WNS    | +1.518 ns |
| WHS    | +0.064 ns |
| WPWS   | +3.500 ns |

All reported timing checks passed at the 125 MHz system clock.

## Tools

* SystemVerilog
* Vivado 2025.2
* PYNQ-Z2
* Python
* PySerial
