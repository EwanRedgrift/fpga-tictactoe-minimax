import sys
import time
import serial
from serial.tools import list_ports

def find_fpga_port():
    ports = list_ports.comports()

    if not ports:
        print("No serial device found.")
        print("Ensure FPGA is connected.")
        sys.exit(1)

    for i, port in enumerate(ports, start=1):
        print(f"{i}. {port.device}")

    while True:
        try:
            selection = int(input("Select port number: "))

            if 1 <= selection <= len(ports):
                return ports[selection - 1].device
            
            print("Invalid port number.")
        
        except ValueError:
            print("Please enter a number.")

def query_fpga(ser, x_board, o_board, x_turn):
    b0 = x_board & 0xFF
    b1 = o_board & 0xFF
    b2 = ((x_board >> 8) & 0x01) | (((o_board >> 8) & 0x01) << 1) | ((1 if x_turn else 0) << 2)

    payload = bytes([b0, b1, b2])

    # Flush buffers to avoid desynchronization
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    
    # print(f"\n[UART TX] Sending 3 bytes -> Hex: {[hex(b) for b in payload]} | Bin: {[bin(b) for b in payload]}")

    ser.write(payload)

    # 1.5s timeout
    rx = ser.read(1)
    if not rx:
        print("\nHardware timeout: No response received from FPGA.")
        return None, None

    raw_val = rx[0]
    #print(f"[UART RX] Received 1 byte  -> Hex: {hex(raw_val)} | Bin: {bin(raw_val)}")

    move_idx = raw_val & 0x0F

    # Decode 2-bit two's complement score (-1, 0, +1)
    raw_score = (val_score := (raw_val >> 4) & 0x03)
    score = raw_score - 4 if raw_score >= 2 else raw_score

    return move_idx, score

def print_board(x_board, o_board):
    grid = []
    for i in range(9):
        if (x_board >> i) & 1:
            grid.append(" X ")
        elif (o_board >> i) & 1:
            grid.append(" O ")
        else:
            grid.append(f" {i} ")

    print("\n" + "---+---+---".join([
        f"\n{grid[0]}|{grid[1]}|{grid[2]}\n",
        f"\n{grid[3]}|{grid[4]}|{grid[5]}\n",
        f"\n{grid[6]}|{grid[7]}|{grid[8]}\n"
    ]))

def check_terminal(x_board, o_board):
    wins = [0x7, 0x38, 0x1C0, 0x49, 0x92, 0x124, 0x111, 0x54] # win masks
    for w in wins:
        if (x_board & w) == w: return "X"
        if (o_board & w) == w: return "O"
    if (x_board | o_board) == 0x1FF: return "Draw"
    return None

def main():
    port = find_fpga_port()
    print(f"Connecting to FPGA on {port} at 115200 baud...")
    
    try:
        ser = serial.Serial(port, 115200, timeout=1.5)
    except Exception as e:
        print(f"Failed to open port: {e}")
        sys.exit(1)

    time.sleep(0.2)
    x_board = 0
    o_board = 0

    print("\n--- Play Tic-Tac-Toe ---")
    human_side = input("Play as X or O? (X goes first): ").strip().upper()
    while human_side not in ['X', 'O']:
        human_side = input("Invalid choice. Enter X or O: ").strip().upper()
    
    human_is_x = (human_side == 'X')

    while True:
        print_board(x_board, o_board)
        res = check_terminal(x_board, o_board)
        if res:
            if res == "Draw": 
                print("\nGame Over: It's a draw!")
            else: 
                print(f"\nGame Over: Player {res} wins!")
            break

        x_cnt = bin(x_board).count('1')
        o_cnt = bin(o_board).count('1')
        x_turn = (x_cnt == o_cnt)

        if (x_turn and human_is_x) or (not x_turn and not human_is_x):
            while True:
                try:
                    move = int(input("\nEnter your move cell index (0-8): "))
                    if move < 0 or move > 8:
                        print("Out of bounds! Choose a number between 0 and 8.")
                        continue
                    if ((x_board | o_board) & (1 << move)):
                        print("Cell already occupied! Choose an empty cell.")
                        continue
                    break
                except ValueError:
                    print("Please enter a valid integer between 0 and 8.")

            if human_is_x: 
                x_board |= (1 << move)
            else: 
                o_board |= (1 << move)
        else:
            #print("\nQuerying FPGA Minimax Engine over UART...")
            fpga_move, score = query_fpga(ser, x_board, o_board, x_turn)
            if fpga_move is None:
                print("Communication failed. Exiting.")
                break

            print(f"-> Decoded FPGA Move: Index {fpga_move}, Score: {score}")
            if x_turn: 
                x_board |= (1 << fpga_move)
            else: 
                o_board |= (1 << fpga_move)

    ser.close()

if __name__ == "__main__":
    main()
