//============================================================================
//
//  CBM-II PLL reconfiguration and recovery manager
//
//  Runs entirely from the stable 50 MHz reference clock. Reconfiguration
//  requests are serialized, followed by an explicit PLL reset and a qualified
//  lock interval. Any stalled operation is reset and retried indefinitely.
//
//============================================================================

module pll_reconfig_manager
#(
	parameter integer RESET_CYCLES       = 256,
	parameter integer LOCK_STABLE_CYCLES = 1024,
	parameter integer WATCHDOG_CYCLES    = 2_500_000
)
(
	input             clk_50,
	input             reset,

	input             request,
	input             target_model,
	input             target_ntsc,

	input             pll_locked,
	input             cfg_waitrequest,

	output reg        cfg_write,
	output reg  [5:0] cfg_address,
	output reg [31:0] cfg_writedata,

	output reg        pll_reset,
	output reg        cfg_reset,

	(* keep = "true" *) output reg       busy,
	output reg        done,
	(* keep = "true" *) output reg       fault_latched,
	(* keep = "true" *) output reg [7:0] recovery_count
);

localparam [4:0]
	ST_RESET_ASSERT    = 5'd0,
	ST_WAIT_READY      = 5'd1,
	ST_WRITE_MODE      = 5'd2,
	ST_GAP_MODE        = 5'd3,
	ST_WRITE_C1        = 5'd4,
	ST_GAP_C1          = 5'd5,
	ST_WRITE_C2        = 5'd6,
	ST_GAP_C2          = 5'd7,
	ST_WRITE_DSM       = 5'd8,
	ST_GAP_DSM         = 5'd9,
	ST_WRITE_START     = 5'd10,
	ST_WAIT_BUSY       = 5'd11,
	ST_WAIT_COMPLETE   = 5'd12,
	ST_POST_RESET      = 5'd13,
	ST_POST_LOCK       = 5'd14,
	ST_IDLE            = 5'd15;

(* keep = "true" *) reg [4:0] state = ST_RESET_ASSERT;

reg latched_model = 0;
reg latched_ntsc  = 0;
reg need_replay   = 0;

integer reset_counter = 0;
integer lock_counter = 0;
integer watchdog_counter = 0;

wire normalized_target_ntsc = target_ntsc & ~target_model;

wire watchdog_state =
	state == ST_WAIT_READY     ||
	state == ST_WRITE_MODE     ||
	state == ST_WRITE_C1       ||
	state == ST_WRITE_C2       ||
	state == ST_WRITE_DSM      ||
	state == ST_WRITE_START    ||
	state == ST_WAIT_BUSY      ||
	state == ST_WAIT_COMPLETE  ||
	state == ST_POST_LOCK;

wire watchdog_expired = watchdog_state &&
	(watchdog_counter >= WATCHDOG_CYCLES - 1);

always @(posedge clk_50) begin
	cfg_write <= 0;
	done <= 0;

	if (reset) begin
		state <= ST_RESET_ASSERT;
		latched_model <= 0;
		latched_ntsc <= 0;
		// A core reset does not necessarily reload the FPGA, so the PLL may
		// still contain a previously selected Business configuration. Always
		// restore the known Professional PAL baseline before going idle.
		need_replay <= 1;
		reset_counter <= 0;
		lock_counter <= 0;
		watchdog_counter <= 0;
		pll_reset <= 1;
		cfg_reset <= 1;
		busy <= 1;
		fault_latched <= 0;
		recovery_count <= 0;
	end
	else if (watchdog_expired) begin
		// Return both pieces of PLL IP to a known management state, then
		// replay the complete target configuration.
		state <= ST_RESET_ASSERT;
		need_replay <= 1;
		reset_counter <= 0;
		lock_counter <= 0;
		watchdog_counter <= 0;
		pll_reset <= 1;
		cfg_reset <= 1;
		busy <= 1;
		fault_latched <= 1;
		if (!(&recovery_count)) recovery_count <= recovery_count + 1'd1;
	end
	else begin
		case (state)
			ST_RESET_ASSERT: begin
				busy <= 1;
				pll_reset <= 1;
				cfg_reset <= 1;
				lock_counter <= 0;
				watchdog_counter <= 0;

				if (reset_counter >= RESET_CYCLES - 1) begin
					reset_counter <= 0;
					pll_reset <= 0;
					cfg_reset <= 0;
					state <= ST_WAIT_READY;
				end
				else begin
					reset_counter <= reset_counter + 1;
				end
			end

			ST_WAIT_READY: begin
				pll_reset <= 0;
				cfg_reset <= 0;
				watchdog_counter <= watchdog_counter + 1;

				if (pll_locked && !cfg_waitrequest) begin
					if (lock_counter >= LOCK_STABLE_CYCLES - 1) begin
						lock_counter <= 0;
						watchdog_counter <= 0;
						if (need_replay) begin
							state <= ST_WRITE_MODE;
						end
						else begin
							busy <= 0;
							done <= 1;
							state <= ST_IDLE;
						end
					end
					else begin
						lock_counter <= lock_counter + 1;
					end
				end
				else begin
					lock_counter <= 0;
				end
			end

			ST_WRITE_MODE: begin
				if (!cfg_waitrequest) begin
					cfg_address <= 0;
					cfg_writedata <= 0;
					cfg_write <= 1;
					watchdog_counter <= 0;
					state <= ST_GAP_MODE;
				end
				else watchdog_counter <= watchdog_counter + 1;
			end

			ST_GAP_MODE: state <= ST_WRITE_C1;

			ST_WRITE_C1: begin
				if (!cfg_waitrequest) begin
					cfg_address <= 5;
					cfg_writedata <= latched_model ? 32'h00040404 : 32'h00060504;
					cfg_write <= 1;
					watchdog_counter <= 0;
					state <= ST_GAP_C1;
				end
				else watchdog_counter <= watchdog_counter + 1;
			end

			ST_GAP_C1: state <= ST_WRITE_C2;

			ST_WRITE_C2: begin
				if (!cfg_waitrequest) begin
					cfg_address <= 5;
					cfg_writedata <= latched_model ? 32'h00080808 : 32'h00080909;
					cfg_write <= 1;
					watchdog_counter <= 0;
					state <= ST_GAP_C2;
				end
				else watchdog_counter <= watchdog_counter + 1;
			end

			ST_GAP_C2: state <= ST_WRITE_DSM;

			ST_WRITE_DSM: begin
				if (!cfg_waitrequest) begin
					cfg_address <= 7;
					cfg_writedata <= latched_model ? 32'd2233382994 :
						(latched_ntsc ? 32'd3357876127 : 32'd1503512573);
					cfg_write <= 1;
					watchdog_counter <= 0;
					state <= ST_GAP_DSM;
				end
				else watchdog_counter <= watchdog_counter + 1;
			end

			ST_GAP_DSM: state <= ST_WRITE_START;

			ST_WRITE_START: begin
				if (!cfg_waitrequest) begin
					cfg_address <= 2;
					cfg_writedata <= 0;
					cfg_write <= 1;
					watchdog_counter <= 0;
					state <= ST_WAIT_BUSY;
				end
				else watchdog_counter <= watchdog_counter + 1;
			end

			ST_WAIT_BUSY: begin
				watchdog_counter <= watchdog_counter + 1;
				if (cfg_waitrequest) begin
					watchdog_counter <= 0;
					state <= ST_WAIT_COMPLETE;
				end
			end

			ST_WAIT_COMPLETE: begin
				watchdog_counter <= watchdog_counter + 1;
				if (!cfg_waitrequest) begin
					reset_counter <= 0;
					watchdog_counter <= 0;
					pll_reset <= 1;
					state <= ST_POST_RESET;
				end
			end

			ST_POST_RESET: begin
				pll_reset <= 1;
				cfg_reset <= 0;
				lock_counter <= 0;

				if (reset_counter >= RESET_CYCLES - 1) begin
					reset_counter <= 0;
					pll_reset <= 0;
					watchdog_counter <= 0;
					state <= ST_POST_LOCK;
				end
				else begin
					reset_counter <= reset_counter + 1;
				end
			end

			ST_POST_LOCK: begin
				pll_reset <= 0;
				watchdog_counter <= watchdog_counter + 1;

				if (pll_locked && !cfg_waitrequest) begin
					if (lock_counter >= LOCK_STABLE_CYCLES - 1) begin
						lock_counter <= 0;
						watchdog_counter <= 0;
						need_replay <= 0;
						busy <= 0;
						done <= 1;
						state <= ST_IDLE;
					end
					else begin
						lock_counter <= lock_counter + 1;
					end
				end
				else begin
					lock_counter <= 0;
				end
			end

			default: begin // ST_IDLE
				pll_reset <= 0;
				cfg_reset <= 0;
				watchdog_counter <= 0;
				lock_counter <= 0;

				if (request) begin
					latched_model <= target_model;
					latched_ntsc <= normalized_target_ntsc;
					need_replay <= 1;
					busy <= 1;
					state <= ST_WAIT_READY;
				end
				else if (!pll_locked) begin
					// Lock disappeared outside a requested transaction.
					// Freeze/reset is handled by the top-level busy path.
					need_replay <= 1;
					busy <= 1;
					fault_latched <= 1;
					if (!(&recovery_count)) recovery_count <= recovery_count + 1'd1;
					reset_counter <= 0;
					pll_reset <= 1;
					cfg_reset <= 1;
					state <= ST_RESET_ASSERT;
				end
			end
		endcase
	end
end

endmodule
