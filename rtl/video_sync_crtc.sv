//============================================================================
//
//  CBM-II CRTC Video sync adjust
//  Copyright (C) 2025 Erik Scheffers
//
//============================================================================

module video_sync_crtc
(
	input        clk,
	input        reset,

	input        hsync,
	input        vsync,
	input        hblank,
	input        vblank,

	output reg   hsync_out,
	output reg   vsync_out,
	output reg   hblank_out,
	output reg   vblank_out
);

localparam HBLANK_DELAY = 7;

always @(posedge clk) begin
	integer hblank_delay;

	if (reset) begin
		hsync_out <= 0;
		vsync_out <= 0;
		hblank_out <= 1;
		vblank_out <= 1;
		hblank_delay <= HBLANK_DELAY;
	end
	else begin
		hsync_out <= hsync;
		vsync_out <= vsync;
		vblank_out <= vblank;

		if (hblank != hblank_out) begin
			hblank_delay <= hblank_delay - 1;
			if (hblank_delay == 1)
				hblank_out <= hblank;
		end
		else
			hblank_delay <= HBLANK_DELAY;
	end
end

endmodule
