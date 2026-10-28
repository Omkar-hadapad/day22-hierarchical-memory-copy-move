`timescale 1ns/1ps

// ============================================================
// DAY 22: HIERARCHICAL MEMORY COPY / MOVE TESTBENCH
// Compatible with day22_design_cadence_fixed.v
// Runs COPY and MOVE concurrently on independent DUT instances.
// ============================================================
module day22_tb;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg start_copy = 1'b0;
    reg start_move = 1'b0;

    wire busy_c, done_c, pass_c, error_c;
    wire [6:0] a_used_c, a_free_c, b_used_c, b_free_c;
    wire [13:0] a_util_c, b_util_c;
    wire [2:0] state_c;

    wire busy_m, done_m, pass_m, error_m;
    wire [6:0] a_used_m, a_free_m, b_used_m, b_free_m;
    wire [13:0] a_util_m, b_util_m;
    wire [2:0] state_m;

    integer i;
    integer init_i;
    integer errors = 0;
    integer wait_cycles;
    reg copy_completed = 1'b0;
    reg move_completed = 1'b0;
    reg test_finished = 1'b0;
    reg [7:0] display_data;

    // Independent COPY instance (mode=0).
    day22_top copy_dut (
        .clk(clk), .reset(reset), .start(start_copy), .mode(1'b0),
        .busy(busy_c), .done(done_c), .pass_fail(pass_c),
        .transfer_error(error_c),
        .a_used(a_used_c), .a_free(a_free_c),
        .a_utilization_x100(a_util_c),
        .b_used(b_used_c), .b_free(b_free_c),
        .b_utilization_x100(b_util_c), .state_debug(state_c)
    );

    // Independent MOVE instance (mode=1).
    day22_top move_dut (
        .clk(clk), .reset(reset), .start(start_move), .mode(1'b1),
        .busy(busy_m), .done(done_m), .pass_fail(pass_m),
        .transfer_error(error_m),
        .a_used(a_used_m), .a_free(a_free_m),
        .a_utilization_x100(a_util_m),
        .b_used(b_used_m), .b_free(b_free_m),
        .b_utilization_x100(b_util_m), .state_debug(state_m)
    );

    always #5 clk = ~clk;

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (condition === 1'b1)
                $display("[PASS] %0s", message);
            else begin
                $display("[FAIL] %0s (condition=%b)", message, condition);
                errors = errors + 1;
            end
        end
    endtask

    task display_slot;
        input [5:0] address;
        input [7:0] data;
        begin
            if (data === 8'h00)
                $display("  Address[0x%02h] HEX=0x%02h EMPTY", address, data);
            else if (^data === 1'bx)
                $display("  Address[0x%02h] HEX=0x%02h UNKNOWN", address, data);
            else
                $display("  Address[0x%02h] HEX=0x%02h CHAR='%c'", address, data, data);
        end
    endtask

    task display_copy_bank_a_slot;
        input [5:0] address;
        begin
            display_slot(address, copy_dut.u_subsystem.u_bank_a.u_mem.mem[address]);
        end
    endtask

    task display_move_bank_a_slot;
        input [5:0] address;
        begin
            display_slot(address, move_dut.u_subsystem.u_bank_a.u_mem.mem[address]);
        end
    endtask

    // Record completion independently of the main stimulus process.
    always @(posedge clk) begin
        if (done_m === 1'b1) move_completed <= 1'b1;
        if (done_c === 1'b1) copy_completed <= 1'b1;
    end

    // Print initialized source memory after time-zero initial blocks settle.
    initial begin
        #1;
        $display("\n===============================================================");
        $display(" DAY 22: HIERARCHICAL MEMORY COPY / MOVE TESTBENCH");
        $display("===============================================================");
        $display("\n[INITIAL COPY DUT - STORAGE A]");
        $display(" ADDRESS | HEX BYTE | CHARACTER");
        for (init_i = 0; init_i < 64; init_i = init_i + 1) begin
            display_data = copy_dut.u_subsystem.u_bank_a.u_mem.mem[init_i];
            if (display_data === 8'h00)
                $display("  0x%02h | 0x%02h | EMPTY", init_i, display_data);
            else if (^display_data === 1'bx)
                $display("  0x%02h | 0x%02h | UNKNOWN", init_i, display_data);
            else
                $display("  0x%02h | 0x%02h | '%c'", init_i, display_data, display_data);
        end
        $display("Storage A: Z..A at addresses 0..25, z..a at 26..51; remaining bytes empty.");
        $display("Storage B starts empty in both DUT instances.\n");
    end

    // Main stimulus and self-checks.
    initial begin
        // Keep reset asserted across at least one rising edge.
        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        @(posedge clk);
        #1;

        $display("\n[INITIAL STATUS]");
        $display(" COPY | A used=%0d free=%0d util=%0d.%02d%% | B used=%0d free=%0d util=%0d.%02d%%",
                 a_used_c, a_free_c, a_util_c/100, a_util_c%100,
                 b_used_c, b_free_c, b_util_c/100, b_util_c%100);
        $display(" MOVE | A used=%0d free=%0d util=%0d.%02d%% | B used=%0d free=%0d util=%0d.%02d%%",
                 a_used_m, a_free_m, a_util_m/100, a_util_m%100,
                 b_used_m, b_free_m, b_util_m/100, b_util_m%100);

        check(a_used_c == 52, "COPY initial Storage A has 52 occupied bytes");
        check(b_used_c == 0, "COPY initial Storage B is empty");
        check(a_free_c == 12, "COPY initial Storage A has 12 free bytes");
        check(a_util_c == 14'd8125, "COPY initial Storage A utilization is 81.25%");
        check((a_used_m == 52) && (b_used_m == 0), "MOVE DUT has independent initialized memories");
        check((a_free_m == 12) && (b_free_m == 64), "MOVE initial free-space counters are correct");

        $display("\n===============================================================");
        $display(" CONCURRENT OPERATIONS: MOVE + COPY");
        $display("===============================================================");
        @(negedge clk);
        start_move = 1'b1;
        start_copy = 1'b1;
        $display("[START] MOVE and COPY asserted together at %0t", $time);
        @(negedge clk);
        start_move = 1'b0;
        start_copy = 1'b0;
        $display("[START] Both start signals deasserted; operations run independently.");

        // Wait for MOVE, with a bounded watchdog in clock cycles.
        wait_cycles = 0;
        while ((move_completed !== 1'b1) && (wait_cycles < 200)) begin
            @(posedge clk);
            #1;
            wait_cycles = wait_cycles + 1;
        end
        check(move_completed === 1'b1, "MOVE completed before the cycle timeout");
        if (move_completed !== 1'b1)
            $display("[MOVE DEBUG] done=%b busy=%b state=%b error=%b", done_m, busy_m, state_m, error_m);

        $display("\n[MOVE TRANSFER LOG: SOURCE -> DESTINATION]");
        $display(" SOURCE ADDRESS | EXPECTED BYTE | DESTINATION ADDRESS | STORED BYTE");
        for (i = 0; i < 26; i = i + 1)
            $display(" A[0x%02h] | 0x%02h '%c' | B[0x%02h] | 0x%02h '%c'",
                     25-i, 8'h41+i, 8'h41+i, i,
                     move_dut.u_subsystem.u_bank_b.u_mem.mem[i],
                     move_dut.u_subsystem.u_bank_b.u_mem.mem[i]);

        $display("\n[MOVE FINAL STATUS]");
        $display(" Storage A: used=%0d free=%0d utilization=%0d.%02d%%",
                 a_used_m, a_free_m, a_util_m/100, a_util_m%100);
        $display(" Storage B: used=%0d free=%0d utilization=%0d.%02d%%",
                 b_used_m, b_free_m, b_util_m/100, b_util_m%100);
        check(move_completed && (pass_m === 1'b1) && (error_m === 1'b0), "MOVE completed without transfer error");
        check((a_used_m == 26) && (a_free_m == 38), "MOVE cleared 26 uppercase source bytes from Storage A");
        check((b_used_m == 26) && (b_free_m == 38), "MOVE wrote 26 bytes into Storage B");
        check(a_util_m == 14'd4062, "MOVE Storage A utilization is 40.62% truncated");
        check(b_util_m == 14'd4062, "MOVE Storage B utilization is 40.62% truncated");
        for (i = 0; i < 26; i = i + 1) begin
            check(move_dut.u_subsystem.u_bank_b.u_mem.mem[i] == (8'h41+i), "MOVE destination contains uppercase A-Z");
            check(move_dut.u_subsystem.u_bank_a.u_mem.mem[i] == 8'h00, "MOVE cleared uppercase source byte");
            check(move_dut.u_subsystem.u_bank_a.u_mem.mem[i+26] == (8'h7A-i), "MOVE retained lowercase source byte");
        end

        $display("\n[MOVE STORAGE A SAMPLE SLOTS]");
        display_move_bank_a_slot(0);
        display_move_bank_a_slot(10);
        display_move_bank_a_slot(25);
        display_move_bank_a_slot(26);
        display_move_bank_a_slot(51);
        display_move_bank_a_slot(52);
        display_move_bank_a_slot(63);
        $display("[MOVE STORAGE B SAMPLE SLOTS]");
        display_slot(0, move_dut.u_subsystem.u_bank_b.u_mem.mem[0]);
        display_slot(10, move_dut.u_subsystem.u_bank_b.u_mem.mem[10]);
        display_slot(25, move_dut.u_subsystem.u_bank_b.u_mem.mem[25]);
        display_slot(26, move_dut.u_subsystem.u_bank_b.u_mem.mem[26]);
        display_slot(63, move_dut.u_subsystem.u_bank_b.u_mem.mem[63]);

        // COPY was started concurrently above; do not start it a second time.
        wait_cycles = 0;
        while ((copy_completed !== 1'b1) && (wait_cycles < 200)) begin
            @(posedge clk);
            #1;
            wait_cycles = wait_cycles + 1;
        end
        check(copy_completed === 1'b1, "COPY completed before the cycle timeout");
        if (copy_completed !== 1'b1)
            $display("[COPY DEBUG] done=%b busy=%b state=%b error=%b", done_c, busy_c, state_c, error_c);

        $display("\n[COPY TRANSFER LOG: SOURCE -> DESTINATION]");
        $display(" SOURCE ADDRESS | STORED SOURCE BYTE | DESTINATION ADDRESS | STORED BYTE");
        for (i = 0; i < 26; i = i + 1)
            $display(" A[0x%02h] | 0x%02h '%c' | B[0x%02h] | 0x%02h '%c'",
                     25-i,
                     copy_dut.u_subsystem.u_bank_a.u_mem.mem[25-i],
                     copy_dut.u_subsystem.u_bank_a.u_mem.mem[25-i],
                     i,
                     copy_dut.u_subsystem.u_bank_b.u_mem.mem[i],
                     copy_dut.u_subsystem.u_bank_b.u_mem.mem[i]);

        $display("\n[COPY FINAL STATUS]");
        $display(" Storage A: used=%0d free=%0d utilization=%0d.%02d%%",
                 a_used_c, a_free_c, a_util_c/100, a_util_c%100);
        $display(" Storage B: used=%0d free=%0d utilization=%0d.%02d%%",
                 b_used_c, b_free_c, b_util_c/100, b_util_c%100);
        $write(" Storage B ASCII: ");
        for (i = 0; i < 26; i = i + 1)
            $write("%c", copy_dut.u_subsystem.u_bank_b.u_mem.mem[i]);
        $display("");

        check(copy_completed && (pass_c === 1'b1) && (error_c === 1'b0), "COPY completed without transfer error");
        check((a_used_c == 52) && (a_free_c == 12), "COPY retained all source data in Storage A");
        check((b_used_c == 26) && (b_free_c == 38), "COPY wrote 26 bytes into Storage B");
        check(a_util_c == 14'd8125, "COPY Storage A utilization is 81.25%");
        check(b_util_c == 14'd4062, "COPY Storage B utilization is 40.62% truncated");
        for (i = 0; i < 26; i = i + 1) begin
            check(copy_dut.u_subsystem.u_bank_b.u_mem.mem[i] == (8'h41+i), "COPY destination contains uppercase A-Z");
            check(copy_dut.u_subsystem.u_bank_a.u_mem.mem[i] == (8'h5A-i), "COPY retained uppercase source byte");
            check(copy_dut.u_subsystem.u_bank_a.u_mem.mem[i+26] == (8'h7A-i), "COPY retained lowercase source byte");
        end

        $display("\n[COPY STORAGE A SAMPLE SLOTS]");
        display_copy_bank_a_slot(0);
        display_copy_bank_a_slot(10);
        display_copy_bank_a_slot(25);
        display_copy_bank_a_slot(26);
        display_copy_bank_a_slot(51);
        display_copy_bank_a_slot(52);
        display_copy_bank_a_slot(63);

        // Full final memory readback for both independent DUTs.
        $display("\n===============================================================");
        $display(" FINAL MEMORY READBACK: COPY DUT - STORAGE A");
        $display(" ADDRESS | HEX BYTE | CHARACTER");
        for (init_i = 0; init_i < 64; init_i = init_i + 1) begin
            display_data = copy_dut.u_subsystem.u_bank_a.u_mem.mem[init_i];
            if (display_data === 8'h00) $display("  0x%02h | 0x%02h | EMPTY", init_i, display_data);
            else if (^display_data === 1'bx) $display("  0x%02h | 0x%02h | UNKNOWN", init_i, display_data);
            else $display("  0x%02h | 0x%02h | '%c'", init_i, display_data, display_data);
        end

        $display("\n FINAL MEMORY READBACK: COPY DUT - STORAGE B");
        for (init_i = 0; init_i < 64; init_i = init_i + 1) begin
            display_data = copy_dut.u_subsystem.u_bank_b.u_mem.mem[init_i];
            if (display_data === 8'h00) $display("  0x%02h | 0x%02h | EMPTY", init_i, display_data);
            else if (^display_data === 1'bx) $display("  0x%02h | 0x%02h | UNKNOWN", init_i, display_data);
            else $display("  0x%02h | 0x%02h | '%c'", init_i, display_data, display_data);
        end

        $display("\n FINAL MEMORY READBACK: MOVE DUT - STORAGE A");
        for (init_i = 0; init_i < 64; init_i = init_i + 1) begin
            display_data = move_dut.u_subsystem.u_bank_a.u_mem.mem[init_i];
            if (display_data === 8'h00) $display("  0x%02h | 0x%02h | EMPTY", init_i, display_data);
            else if (^display_data === 1'bx) $display("  0x%02h | 0x%02h | UNKNOWN", init_i, display_data);
            else $display("  0x%02h | 0x%02h | '%c'", init_i, display_data, display_data);
        end

        $display("\n FINAL MEMORY READBACK: MOVE DUT - STORAGE B");
        for (init_i = 0; init_i < 64; init_i = init_i + 1) begin
            display_data = move_dut.u_subsystem.u_bank_b.u_mem.mem[init_i];
            if (display_data === 8'h00) $display("  0x%02h | 0x%02h | EMPTY", init_i, display_data);
            else if (^display_data === 1'bx) $display("  0x%02h | 0x%02h | UNKNOWN", init_i, display_data);
            else $display("  0x%02h | 0x%02h | '%c'", init_i, display_data, display_data);
        end

        $display("\n===============================================================");
        $display(" SELF-CHECK SUMMARY: errors=%0d", errors);
        if ((errors == 0) && copy_completed && (pass_c === 1'b1) && (error_c === 1'b0) &&
            move_completed && (pass_m === 1'b1) && (error_m === 1'b0))
            $display(" FINAL RESULT: PASS - COPY AND MOVE VERIFIED");
        else
            $display(" FINAL RESULT: FAIL - errors=%0d, COPY pass=%b error=%b, MOVE pass=%b error=%b",
                     errors, pass_c, error_c, pass_m, error_m);
        $display("===============================================================");

        // IMPORTANT: finish normal simulation here so the watchdog cannot
        // print a false timeout after a successful test.
        test_finished = 1'b1;
       $finish;
    end

    // Safety watchdog: only reports timeout if the main test did not finish.
    initial begin
      #1000;
        if (test_finished !== 1'b1) begin
            $display("[FAIL] Simulation timeout: testbench did not finish in time.");
            $finish;
        end
    end
endmodule
