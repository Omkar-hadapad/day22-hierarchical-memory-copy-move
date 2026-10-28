`timescale 1ns/1ps

// ============================================================
// DAY 22: HIERARCHICAL COPY/MOVE STORAGE SIMULATOR
// Bank A: 64 bytes; addresses 0..25 = Z..A, 26..51 = z..a
// Bank B: 64 bytes, initially empty
// mode=0: COPY A..Z into B[0..25], retaining Bank A
// mode=1: MOVE A..Z into B[0..25], then clear Bank A[0..25]
// ============================================================

// ---------------- BASIC LOGIC -------------------------------
module not_gate(input wire a, output wire y);
    assign y = ~a;
endmodule

module and_gate(input wire a, input wire b, output wire y);
    assign y = a & b;
endmodule

module or_gate(input wire a, input wire b, output wire y);
    assign y = a | b;
endmodule

module xor_gate(input wire a, input wire b, output wire y);
    assign y = a ^ b;
endmodule

module mux2to1(input wire a, b, sel, output wire y);
    wire nsel, t0, t1;
    not_gate u0(.a(sel), .y(nsel));
    and_gate u1(.a(a), .b(nsel), .y(t0));
    and_gate u2(.a(b), .b(sel), .y(t1));
    or_gate  u3(.a(t0), .b(t1), .y(y));
endmodule


// mux2to1_tb removed from RTL file; keep testbenches in a separate testbench file.


// ---------------- ADDRESS LOGIC -----------------------------
module address_counter(
    input wire clk, reset, clear, enable,
    output reg [5:0] count
);
    always @(posedge clk or posedge reset) begin
        if (reset)       count <= 6'd0;
        else if (clear)  count <= 6'd0;
        else if (enable) count <= count + 1'b1;
    end
endmodule

module address_decoder(
    input wire enable,
    input wire [5:0] address,
    output reg [63:0] select
);
    always @* begin
        select = 64'b0;
        if (enable) select[address] = 1'b1;
    end
endmodule

module address_selector(
    input wire [5:0] index,
    output wire [5:0] source_address,
    output wire [5:0] destination_address
);
    // index 0 reads A at address 25 (character A).
    // index 25 reads A at address 0 (character Z).
    assign source_address      = 6'd25 - index;
    assign destination_address = index;
endmodule

// ---------------- STORAGE BUILDING BLOCKS ------------------
module d_flip_flop(input wire clk, reset, d, output reg q);
    always @(posedge clk or posedge reset) begin
        if (reset) q <= 1'b0;
        else       q <= d;
    end
endmodule

module register_8bit(
    input wire clk, reset, enable,
    input wire [7:0] d,
    output reg [7:0] q
);
    always @(posedge clk or posedge reset) begin
        if (reset)       q <= 8'h00;
        else if (enable) q <= d;
    end
endmodule

// Asynchronous read, synchronous write. Initial contents are for simulation.
module memory_array #(parameter BANK_A = 0)(
    input wire clk,
    input wire write_enable,
    input wire [5:0] write_address,
    input wire [7:0] write_data,
    input wire [5:0] read_address,
    output wire [7:0] read_data,
    output reg [6:0] used_count
);
    reg [7:0] mem [0:63];
    integer init_i;

    // Simulation memory initialization and its matching occupancy count.
    // BANK_A starts with 52 nonzero bytes; BANK_B starts empty.
    initial begin
        used_count = 7'd0;
        for (init_i = 0; init_i < 64; init_i = init_i + 1)
            mem[init_i] = 8'h00;

        if (BANK_A != 0) begin
            for (init_i = 0; init_i < 26; init_i = init_i + 1)
                mem[init_i] = 8'h5A - init_i; // Z..A
            for (init_i = 0; init_i < 26; init_i = init_i + 1)
                mem[init_i + 26] = 8'h7A - init_i; // z..a
            used_count = 7'd52;
        end
    end

    // Update occupancy only when a write changes a byte between zero
    // and nonzero. This avoids hierarchical memory scanning in the parent.
    always @(posedge clk) begin
        if (write_enable) begin
            if ((mem[write_address] == 8'h00) && (write_data != 8'h00))
                used_count <= used_count + 1'b1;
            else if ((mem[write_address] != 8'h00) && (write_data == 8'h00))
                used_count <= used_count - 1'b1;

            mem[write_address] <= write_data;
        end
    end

    assign read_data = mem[read_address];
endmodule

module storage_bank_A(
    input wire clk, write_enable,
    input wire [5:0] write_address,
    input wire [7:0] write_data,
    input wire [5:0] read_address,
    output wire [7:0] read_data,
    output wire [6:0] used_count
);
    memory_array #(.BANK_A(1)) u_mem(
        .clk(clk), .write_enable(write_enable),
        .write_address(write_address), .write_data(write_data),
        .read_address(read_address), .read_data(read_data),
        .used_count(used_count)
    );
endmodule

module storage_bank_B(
    input wire clk, write_enable,
    input wire [5:0] write_address,
    input wire [7:0] write_data,
    input wire [5:0] read_address,
    output wire [7:0] read_data,
    output wire [6:0] used_count
);
    memory_array #(.BANK_A(0)) u_mem(
        .clk(clk), .write_enable(write_enable),
        .write_address(write_address), .write_data(write_data),
        .read_address(read_address), .read_data(read_data),
        .used_count(used_count)
    );
endmodule

// ---------------- TRANSFER FSM -----------------------------
module transfer_fsm(
    input wire [2:0] state,
    input wire start,
    input wire verify_match,
    input wire last_index,
    input wire mode,
    output reg [2:0] next_state
);
    localparam IDLE=3'd0, READ=3'd1, WRITE=3'd2,
               VERIFY=3'd3, CLEAR=3'd4, DONE=3'd5, ERROR=3'd6;

    always @* begin
        next_state = state;
        case (state)
            IDLE:   if (start) next_state = READ;
            READ:   next_state = WRITE;
            WRITE:  next_state = VERIFY;
            VERIFY: begin
                if (!verify_match) next_state = ERROR;
                else if (last_index) next_state = mode ? CLEAR : DONE;
                else next_state = READ;
            end
            CLEAR:  if (last_index) next_state = DONE;
            DONE:   next_state = DONE;
            ERROR:  next_state = ERROR;
            default: next_state = ERROR;
        endcase
    end
endmodule

// ---------------- TRANSFER CONTROLLER ----------------------
module copy_move_controller(
    input wire clk, reset, start, mode,
    input wire [7:0] source_data,
    input wire [7:0] destination_data,
    output wire [5:0] source_read_address,
    output wire [5:0] destination_read_address,
    output wire [5:0] source_write_address,
    output wire [5:0] destination_write_address,
    output wire source_write_enable,
    output wire destination_write_enable,
    output wire [7:0] source_write_data,
    output wire [7:0] destination_write_data,
    output wire busy, done, transfer_error,
    output wire [2:0] state_debug
);
    localparam IDLE=3'd0, READ=3'd1, WRITE=3'd2,
               VERIFY=3'd3, CLEAR=3'd4, DONE=3'd5, ERROR=3'd6;

    reg [2:0] state;
    reg [7:0] data_register;
    reg error_latched;
    wire [2:0] next_state;
    wire [5:0] index;
    wire [5:0] selected_source, selected_destination;
    wire verify_match, last_index, counter_clear, counter_enable;

    assign last_index = (index == 6'd25);

    // Check read-back AND expected byte for this transfer index.
    assign verify_match = (destination_data == data_register) &&
                          (data_register == (8'h41 + index));

    // Reset index at transfer start. For MOVE, reset it before the clear pass.
    assign counter_clear = ((state == IDLE) && start) ||
                           ((state == VERIFY) && verify_match && last_index && mode);

    assign counter_enable = ((state == VERIFY) && verify_match && !last_index) ||
                            ((state == CLEAR) && !last_index);

    address_counter u_counter(
        .clk(clk), .reset(reset), .clear(counter_clear),
        .enable(counter_enable), .count(index)
    );

    address_selector u_selector(
        .index(index), .source_address(selected_source),
        .destination_address(selected_destination)
    );

    transfer_fsm u_fsm(
        .state(state), .start(start), .verify_match(verify_match),
        .last_index(last_index), .mode(mode), .next_state(next_state)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            data_register <= 8'h00;
            error_latched <= 1'b0;
        end else begin
            state <= next_state;
            if ((state == IDLE) && start)
                error_latched <= 1'b0;
            if (state == READ)
                data_register <= source_data;
            if ((state == VERIFY) && !verify_match)
                error_latched <= 1'b1;
        end
    end

    assign source_read_address      = selected_source;
    assign destination_read_address = selected_destination;
    assign source_write_address     = selected_source;
    assign destination_write_address= selected_destination;

    assign destination_write_enable = (state == WRITE);
    assign destination_write_data   = data_register;

    // MOVE clear pass: zero source addresses 25 down to 0 after verification.
    assign source_write_enable = (state == CLEAR);
    assign source_write_data   = 8'h00;

    assign busy = (state != IDLE) && (state != DONE) && (state != ERROR);
    assign done = (state == DONE);
    assign transfer_error = error_latched || (state == ERROR);
    assign state_debug = state;
endmodule

// ---------------- STATUS LOGIC -----------------------------
module free_space_calculator(
    input wire [6:0] used,
    output wire [6:0] free_space
);
    assign free_space = 7'd64 - used;
endmodule

// Utilization is percentage * 100; integer division truncates fractions.
module utilization_calculator(
    input wire [6:0] used,
    output wire [13:0] utilization_x100
);
    wire [20:0] scaled_product;
    assign scaled_product = {14'd0, used} * 21'd10000;
    assign utilization_x100 = scaled_product / 21'd64;
endmodule

module verification_controller(
    input wire done, mode, transfer_error,
    input wire [6:0] a_used, b_used,
    output wire pass
);
    wire a_count_ok;
    assign a_count_ok = mode ? (a_used == 7'd26) : (a_used == 7'd52);
    assign pass = done && !transfer_error && a_count_ok && (b_used == 7'd26);
endmodule

// ---------------- MEMORY SUBSYSTEM -------------------------
module day22_memory_subsystem(
    input wire clk, reset, start, mode,
    output wire busy, done, pass_fail, transfer_error,
    output wire [6:0] a_used, a_free,
    output wire [13:0] a_utilization_x100,
    output wire [6:0] b_used, b_free,
    output wire [13:0] b_utilization_x100,
    output wire [2:0] state_debug
);
    wire [5:0] a_read_address, b_read_address;
    wire [5:0] a_write_address, b_write_address;
    wire a_write_enable, b_write_enable;
    wire [7:0] a_write_data, b_write_data;
    wire [7:0] a_read_data, b_read_data;
    wire [6:0] a_occupancy_count, b_occupancy_count;

    storage_bank_A u_bank_a(
        .clk(clk), .write_enable(a_write_enable),
        .write_address(a_write_address), .write_data(a_write_data),
        .read_address(a_read_address), .read_data(a_read_data),
        .used_count(a_occupancy_count)
    );

    storage_bank_B u_bank_b(
        .clk(clk), .write_enable(b_write_enable),
        .write_address(b_write_address), .write_data(b_write_data),
        .read_address(b_read_address), .read_data(b_read_data),
        .used_count(b_occupancy_count)
    );

    copy_move_controller u_controller(
        .clk(clk), .reset(reset), .start(start), .mode(mode),
        .source_data(a_read_data), .destination_data(b_read_data),
        .source_read_address(a_read_address),
        .destination_read_address(b_read_address),
        .source_write_address(a_write_address),
        .destination_write_address(b_write_address),
        .source_write_enable(a_write_enable),
        .destination_write_enable(b_write_enable),
        .source_write_data(a_write_data),
        .destination_write_data(b_write_data),
        .busy(busy), .done(done), .transfer_error(transfer_error),
        .state_debug(state_debug)
    );

    // Occupancy is maintained inside each memory bank, avoiding a
    // hierarchical scan of internal memory arrays in this subsystem.
    assign a_used = a_occupancy_count;
    assign b_used = b_occupancy_count;

    free_space_calculator u_a_free(.used(a_used), .free_space(a_free));
    free_space_calculator u_b_free(.used(b_used), .free_space(b_free));

    utilization_calculator u_a_util(
        .used(a_used), .utilization_x100(a_utilization_x100)
    );
    utilization_calculator u_b_util(
        .used(b_used), .utilization_x100(b_utilization_x100)
    );

    verification_controller u_verify(
        .done(done), .mode(mode), .transfer_error(transfer_error),
        .a_used(a_used), .b_used(b_used), .pass(pass_fail)
    );
endmodule

// Optional simulation/hardware-style pass-through slot reader.
module character_slot_reader(
    input wire [5:0] address,
    input wire [7:0] character_data,
    output wire [5:0] selected_address,
    output wire [7:0] selected_character
);
    assign selected_address = address;
    assign selected_character = character_data;
endmodule

// ---------------- TOP MODULE -------------------------------
module day22_top(
    input wire clk, reset, start, mode,
    output wire busy, done, pass_fail, transfer_error,
    output wire [6:0] a_used, a_free,
    output wire [13:0] a_utilization_x100,
    output wire [6:0] b_used, b_free,
    output wire [13:0] b_utilization_x100,
    output wire [2:0] state_debug
);
    day22_memory_subsystem u_subsystem(
        .clk(clk), .reset(reset), .start(start), .mode(mode),
        .busy(busy), .done(done), .pass_fail(pass_fail),
        .transfer_error(transfer_error),
        .a_used(a_used), .a_free(a_free),
        .a_utilization_x100(a_utilization_x100),
        .b_used(b_used), .b_free(b_free),
        .b_utilization_x100(b_utilization_x100),
        .state_debug(state_debug)
    );
endmodule
