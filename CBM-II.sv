/*
 * CBM-II FPGA implementation
 *
 * Copyright (C) 2024, Erik Scheffers (https://github.com/eriks5)
 *
 * This file is part of CBM-II_MiSTer.
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 2.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS = 'Z;
assign {USER_OUT[6], USER_OUT[1:0]} = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign LED_USER = |drive_led | ioctl_download;
assign BUTTONS = 0;
assign VGA_DISABLE = 0;
assign VGA_SCALER = 0;

//////////////////////////////////////////////////////////////////

localparam NDRIVES=2;

// Status Bit Map:
//              Upper                          Lower
// 0         1         2         3          4         5         6
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// XXXXXXX  XXXXXXXXXXXXXXXXXXXXXXX XXXXXXXXXX  XXXXXXXX

`include "build_id.v"
localparam CONF_STR = {
	"CBM-II;;",
	"HAO[50],Drive #8 Type,8250,4040;",
	"HAHCS0,D80D82, Mount #8.0;",
	"HAHCS1,D80D82, Mount #8.1;",
	"HAhCS0,D64, Mount #8.0;",
	"HAhCS1,D64, Mount #8.1;",
	"HA-;",
	"HBO[51],Drive #9 Type,8250,4040;",
	"HBHDS2,D80D82, Mount #9.0;",
	"HBHDS3,D80D82, Mount #9.1;",
	"HBhDS2,D64, Mount #9.0;",
	"HBhDS3,D64, Mount #9.1;",
	"HB-;",
	"F9,PRG;",
	"-;",

	"P1,Hardware;",
	"P1O[4:2],System,P500,B610,B620,B710,B720,Custom;",
	"h0P1-;",
	"h0P1O[6:5],Model,Professional,Business LP,Business HP;",
	"h0H1P1O[11],CPU Clock,1 MHz,2 MHz;",
	"h0P1O[10:9],RAM,128K,256K,896K;",
	"h0h1P1-;H1h6P1-;",
	"h0h1P1O[37],Enable Joysticks,No,Yes;",
	"h6P1O[33:32],Pot 1/2,Joy 1 Fire 2/3,Mouse,Paddles 1/2;",
	"h6P1O[35:34],Pot 3/4,Joy 2 Fire 2/3,Mouse,Paddles 3/4;",
	"h6P1O[36],Swap Joysticks,No,Yes;",
	"P1-;",
	"P1O[47:46],Enable Drive #8,If Mounted,Always,Never;",
	"P1O[49:48],Enable Drive #9,If Mounted,Always,Never;",
	"P1O[45],Enable External IEC,No,Yes;",
	"P1R[44],Reset Drives;",
	"P1-;",
	"P1O[13],Release Keys on Reset,Yes,No;",
	"P1O[14],Clear All RAM on Reset,Yes,No;",
	"P1O[15],Pause When OSD is Open,No,Yes;",

	"P2,Audio & Video;",
	"H2P2O[12],TV System,PAL,NTSC;",
	"H1P2O[25],VIC-II Revision,Early,Later;",
	"H2P2-;",
	"P2O[17:16],Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P2O[20:18],Scandoubler Fx,None,HQ2x-320,HQ2x-160,CRT 25%,CRT 50%,CRT 75%;",
	"d3P2O[21],Vertical Crop,No,Yes;",
	"P2O[23:22],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P2-;",
	"P2O[28:26],SID Filter,Default,Custom 1,Custom 2,Custom 3,Adjustable;",
	"D5P2O[31:29],Fc Offset,0,1,2,3,4,5;",

	"P3,ROM/RAM Configuration;",
	"P3-,System ROM;",
	"P3FC1,ROMBIN, P500            ;",
	"P3FC2,ROMBIN, B6x0            ;",
	"P3FC3,ROMBIN, B7x0            ;",
	"P3-;",
	"P3-,External ROM/RAM (Seg 15);",
	"P3O[38], $0800-1FFF,Disabled,RAM;",
	"P3O[39], $2000-3FFF,ROM,RAM;",
	"D7P3FC4,ROMBIN,  Load;",
	"P3O[40], $4000-5FFF,ROM,RAM;",
	"D8P3FC5,ROMBIN,  Load;",
	"P3O[41], $6000-7FFF,ROM,RAM;",
	"D9P3FC6,ROMBIN,  Load;",
	"P3-;",
	// "P3-,Drive ROM;",
	// "P3FC7,ROMBIN, 4040            ;",
	// "P3FC8,ROMBIN, 8250            ;",
	// "P3-;",
	"P3-,Load options;",
	"P3O[24], Ignore PRG start,Yes,No;",

	"-;",
 	"R[0],Hard reset;",
	"R[1],Soft reset;",
	"J,Fire 1,Fire 2,Fire 3,Paddle Btn;",
	"jn,A,B,Y,X|P;",
	"jp,A,B,Y,X|P;",
	"v,0;",
	"V,v",`BUILD_DATE
};

(* keep = "true" *) wire pll_locked;
wire clk_sys;
wire clk_vid;
wire clk_sdr;

wire pll_reset;
wire pll_cfg_reset;

pll pll
(
	.refclk(CLK_50M),
	.rst(pll_reset),
	.outclk_0(clk_sdr),
	.outclk_1(clk_vid),
	.outclk_2(clk_sys),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(pll_locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
wire        cfg_write;
wire  [5:0] cfg_address;
wire [31:0] cfg_data;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(pll_cfg_reset),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(1'b0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

// Requested menu configuration is synchronized into the stable 50 MHz
// reference domain. Business systems have a single PLL configuration, so
// NTSC is normalized away for that model.
reg model_req_50d = 0, model_req_50 = 0;
reg ntsc_req_50d = 0, ntsc_req_50 = 0;
always @(posedge CLK_50M) begin
	model_req_50d <= model_requested;
	model_req_50 <= model_req_50d;
	ntsc_req_50d <= ntsc_requested;
	ntsc_req_50 <= ntsc_req_50d;
end

wire normalized_ntsc_req_50 = ntsc_req_50 & ~model_req_50;

// model_active changes in the emulated system domain only after the old frame
// is frozen and the machine has entered transition reset.
reg model_command_50 = 0;
reg ntsc_command_50 = 0;
reg model_command_toggle_50 = 0;
reg model_command_50d = 0, model_command_sys = 0;
reg ntsc_command_50d = 0, ntsc_command_sys = 0;
reg model_toggle_sysd = 0, model_toggle_sys = 0;
reg model_ack_toggle_sys = 0;
reg model_active = 0;
reg ntsc_pll_active = 0;

always @(posedge clk_sys) begin
	model_command_50d <= model_command_50;
	model_command_sys <= model_command_50d;
	ntsc_command_50d <= ntsc_command_50;
	ntsc_command_sys <= ntsc_command_50d;
	model_toggle_sysd <= model_command_toggle_50;
	model_toggle_sys <= model_toggle_sysd;

	if (model_toggle_sys != model_ack_toggle_sys) begin
		model_active <= model_command_sys;
		ntsc_pll_active <= ntsc_command_sys;
		model_ack_toggle_sys <= model_toggle_sys;
	end
end

// Business systems retain their model-specific NTSC flag, but it does not
// select a different PLL configuration. Professional video uses the applied
// frame-synchronous TV-system value.
wire ntsc_active = model_active ? ntsc_requested : ntsc_pll_active;

reg model_ack_50d = 0, model_ack_50 = 0;
always @(posedge CLK_50M) begin
	model_ack_50d <= model_ack_toggle_sys;
	model_ack_50 <= model_ack_50d;
end

wire pll_manager_busy;
wire pll_manager_done;
wire pll_fault_latched;
wire [7:0] pll_recovery_count;
reg pll_manager_request = 0;
reg pll_target_model = 0;
reg pll_target_ntsc = 0;

pll_reconfig_manager pll_manager
(
	.clk_50(CLK_50M),
	.reset(RESET),
	.request(pll_manager_request),
	.target_model(pll_target_model),
	.target_ntsc(pll_target_ntsc),
	.pll_locked(pll_locked),
	.cfg_waitrequest(cfg_waitrequest),
	.cfg_write(cfg_write),
	.cfg_address(cfg_address),
	.cfg_writedata(cfg_data),
	.pll_reset(pll_reset),
	.cfg_reset(pll_cfg_reset),
	.busy(pll_manager_busy),
	.done(pll_manager_done),
	.fault_latched(pll_fault_latched),
	.recovery_count(pll_recovery_count)
);

// The transition freeze is changed only at a frame edge. The emergency path
// is asynchronous by design: when lock is already lost there may be no frame
// edge left on which to freeze the scaler.
reg transition_freeze_request_50 = 0;
reg transition_freeze_req_vd = 0, transition_freeze_req_v = 0;
reg transition_freeze = 0;
reg transition_vsync_d = 0;

always @(posedge clk_vid) begin
	transition_freeze_req_vd <= transition_freeze_request_50;
	transition_freeze_req_v <= transition_freeze_req_vd;
	transition_vsync_d <= vsync_out;

	if (!transition_vsync_d && vsync_out)
		transition_freeze <= transition_freeze_req_v;
end

reg transition_freeze_50d = 0, transition_freeze_50 = 0;
reg selected_vsync_50d = 0, selected_vsync_50 = 0, selected_vsync_50q = 0;
always @(posedge CLK_50M) begin
	transition_freeze_50d <= transition_freeze;
	transition_freeze_50 <= transition_freeze_50d;
	selected_vsync_50d <= vsync_out;
	selected_vsync_50 <= selected_vsync_50d;
	selected_vsync_50q <= selected_vsync_50;
end

wire selected_vsync_rise_50 = selected_vsync_50 & ~selected_vsync_50q;

localparam [3:0]
	TR_IDLE          = 4'd0,
	TR_WAIT_FREEZE   = 4'd1,
	TR_RESET_HOLD    = 4'd2,
	TR_WAIT_MODEL    = 4'd3,
	TR_WAIT_PLL      = 4'd4,
	TR_WAIT_VIDEO    = 4'd5,
	TR_RELEASE       = 4'd6;

(* keep = "true" *) reg [3:0] transition_state = TR_IDLE;
reg transition_reset_50 = 0;
reg emergency_pll_freeze = 0;
reg transition_target_model = 0;
reg transition_target_ntsc = 0;
reg applied_model_50 = 0;
reg applied_ntsc_50 = 0;
reg model_change_needed_50 = 0;
integer transition_counter = 0;
reg [1:0] new_frame_count = 0;

wire requested_config_changed =
	(model_req_50 != applied_model_50) ||
	(normalized_ntsc_req_50 != applied_ntsc_50);

wire transition_active = transition_state != TR_IDLE;

always @(posedge CLK_50M) begin
	pll_manager_request <= 0;

	if (RESET) begin
		transition_state <= TR_IDLE;
		transition_freeze_request_50 <= 0;
		transition_reset_50 <= 0;
		emergency_pll_freeze <= 0;
		transition_target_model <= 0;
		transition_target_ntsc <= 0;
		applied_model_50 <= 0;
		applied_ntsc_50 <= 0;
		model_command_50 <= 0;
		ntsc_command_50 <= 0;
		model_command_toggle_50 <= 0;
		model_change_needed_50 <= 0;
		pll_target_model <= 0;
		pll_target_ntsc <= 0;
		transition_counter <= 0;
		new_frame_count <= 0;
	end
	else begin
		case (transition_state)
			TR_IDLE: begin
				transition_reset_50 <= 0;
				transition_counter <= 0;
				new_frame_count <= 0;

				if (pll_manager_busy || !pll_locked) begin
					// Startup or an unexpected loss of lock has no reliable
					// old-frame boundary. Freeze immediately and let the PLL
					// manager recover its last configuration.
					transition_target_model <= applied_model_50;
					transition_target_ntsc <= applied_ntsc_50;
					transition_freeze_request_50 <= 1;
					emergency_pll_freeze <= 1;
					transition_reset_50 <= 1;
					transition_state <= TR_WAIT_PLL;
				end
				else if (requested_config_changed) begin
					transition_target_model <= model_req_50;
					transition_target_ntsc <= normalized_ntsc_req_50;
					transition_freeze_request_50 <= 1;
					transition_state <= TR_WAIT_FREEZE;
				end
			end

			TR_WAIT_FREEZE: begin
				transition_target_model <= model_req_50;
				transition_target_ntsc <= normalized_ntsc_req_50;
				transition_counter <= transition_counter + 1;

				if (transition_freeze_50 || !pll_locked ||
				    transition_counter >= 5_000_000 - 1) begin
					if (!transition_freeze_50) emergency_pll_freeze <= 1;
					transition_reset_50 <= 1;
					transition_counter <= 0;
					transition_state <= TR_RESET_HOLD;
				end
			end

			TR_RESET_HOLD: begin
				transition_counter <= transition_counter + 1;

				if (!transition_counter) begin
					// Place the data bit first and leave it stable for the
					// entire reset hold before sending the CDC toggle.
					model_change_needed_50 <=
						(transition_target_model != model_command_50) ||
						(transition_target_ntsc != ntsc_command_50);
					model_command_50 <= transition_target_model;
					ntsc_command_50 <= transition_target_ntsc;
				end

				if (transition_counter >= 500 - 1) begin
					transition_counter <= 0;
					if (model_change_needed_50)
						model_command_toggle_50 <= ~model_command_toggle_50;
					transition_state <= TR_WAIT_MODEL;
				end
			end

			TR_WAIT_MODEL: begin
				if ((model_ack_50 == model_command_toggle_50) &&
				    !pll_manager_busy) begin
					pll_target_model <= transition_target_model;
					pll_target_ntsc <= transition_target_ntsc;
					pll_manager_request <= 1;
					transition_state <= TR_WAIT_PLL;
				end
			end

			TR_WAIT_PLL: begin
				if (!pll_locked) emergency_pll_freeze <= 1;

				if (pll_manager_done && !pll_manager_busy && pll_locked) begin
					applied_model_50 <= transition_target_model;
					applied_ntsc_50 <= transition_target_ntsc;
					transition_reset_50 <= 0;
					transition_counter <= 0;
					new_frame_count <= 0;
					transition_state <= TR_WAIT_VIDEO;
				end
			end

			TR_WAIT_VIDEO: begin
				transition_counter <= transition_counter + 1;

				if (selected_vsync_rise_50) begin
					if (new_frame_count == 1) begin
						new_frame_count <= 0;
						transition_counter <= 0;

						if ((model_req_50 != transition_target_model) ||
						    (normalized_ntsc_req_50 != transition_target_ntsc)) begin
							// Coalesce rapid menu changes without exposing an
							// intermediate model to the scaler.
							transition_target_model <= model_req_50;
							transition_target_ntsc <= normalized_ntsc_req_50;
							transition_reset_50 <= 1;
							transition_state <= TR_RESET_HOLD;
						end
						else begin
							transition_freeze_request_50 <= 0;
							transition_state <= TR_RELEASE;
						end
					end
					else begin
						new_frame_count <= new_frame_count + 1'd1;
					end
				end
				else if (transition_counter >= 25_000_000 - 1) begin
					// Locked but no usable video: retain the frozen frame and
					// re-run the complete model/PLL transition.
					transition_counter <= 0;
					transition_reset_50 <= 1;
					emergency_pll_freeze <= 1;
					transition_state <= TR_RESET_HOLD;
				end
			end

			default: begin // TR_RELEASE
				if (pll_manager_busy || !pll_locked) begin
					transition_target_model <= applied_model_50;
					transition_target_ntsc <= applied_ntsc_50;
					transition_freeze_request_50 <= 1;
					emergency_pll_freeze <= 1;
					transition_reset_50 <= 1;
					transition_state <= TR_WAIT_PLL;
				end
				else if ((model_req_50 != applied_model_50) ||
				    (normalized_ntsc_req_50 != applied_ntsc_50)) begin
					transition_target_model <= model_req_50;
					transition_target_ntsc <= normalized_ntsc_req_50;
					transition_freeze_request_50 <= 1;
					transition_reset_50 <= 1;
					transition_counter <= 0;
					transition_state <= TR_RESET_HOLD;
				end
				else if (!transition_freeze_50) begin
					emergency_pll_freeze <= 0;
					transition_state <= TR_IDLE;
				end
			end
		endcase
	end
end

wire [31:0] CLK = model_active ? 36_000_000
					 : ntsc_active  ? 32_727_266
					 :                31_527_954;

// Synchronous reset release in each reconfigured clock domain. Assertion is
// given a 10 us head start by the transition FSM before any PLL write.
reg [1:0] transition_reset_sys = 0;
reg [1:0] transition_reset_vid = 0;
always @(posedge clk_sys) begin
	if (transition_reset_50 || !pll_locked)
		transition_reset_sys <= 2'b11;
	else
		transition_reset_sys <= {transition_reset_sys[0], 1'b0};
end

always @(posedge clk_vid) begin
	if (transition_reset_50 || !pll_locked)
		transition_reset_vid <= 2'b11;
	else
		transition_reset_vid <= {transition_reset_vid[0], 1'b0};
end

wire video_path_reset_sys = |transition_reset_sys;
wire video_path_reset_vid = |transition_reset_vid;

reg base_reset_n;
wire reset_n = base_reset_n & ~video_path_reset_sys;
reg cancel_erase;
reg reset_wait = 0;
always @(posedge clk_sys) begin
	integer   reset_counter;
	reg [8:0] cfg_r;
	reg [1:0] do_erase = 2; // 0 - no, 1 - only sram seg 15 bank0+vidram, 2 - all ram

	// Preserve the old machine long enough to freeze it on a frame edge.
	// Once model_active catches up, consume the complete configuration change
	// and perform the same RAM clearing/reset sequence as before.
	if (model_requested == model_active)
		cfg_r <= status[10:2];

	base_reset_n <= !reset_counter;
	cancel_erase <= reset_counter > 100;

	if (RESET ||
	    ((model_requested == model_active) && (cfg_r != status[10:2])) ||
	    status[0] || !pll_locked) begin
		do_erase <= (status[14] && !RESET) ? 2'd1 : 2'd2;
		reset_counter <= 100000;
	end
	else if (status[1] || buttons[1] || (ioctl_download && load_rom)) begin
		do_erase <= (ioctl_download && load_rom) ? (status[14] ? 2'd1 : 2'd2) : 2'd0;
		force_erase <= 0;
		reset_counter <= 255;
	end
	else if (erasing) force_erase <= 0;
	else if (!reset_counter) begin
		do_erase <= 0;
	end
	else if (reset_counter) begin
		reset_counter <= reset_counter - 1;
		if (reset_counter == 100) begin
			force_erase <= do_erase;
		end
	end
end

localparam NDU = NDRIVES*2;

wire   [127:0] status;

wire           forced_scandoubler;

wire           ioctl_wr;
wire    [24:0] ioctl_addr;
wire     [7:0] ioctl_data;
wire     [7:0] ioctl_index;
wire           ioctl_download;

wire    [31:0] sd_lba[NDU];
wire     [5:0] sd_blk_cnt[NDU];
wire [NDU-1:0] sd_rd;
wire [NDU-1:0] sd_wr;
wire [NDU-1:0] sd_ack;
wire    [12:0] sd_buff_addr;
wire     [7:0] sd_buff_dout;
wire     [7:0] sd_buff_din[NDU];
wire           sd_buff_wr;
wire [NDU-1:0] img_mounted;
wire    [31:0] img_size;
wire           img_readonly;

wire    [24:0] ps2_mouse;
wire    [10:0] ps2_key;
wire     [2:0] ps2_kbd_led_status = {2'b00, sftlk_sense};
wire     [2:0] ps2_kbd_led_use = 3'b001;

wire     [1:0] buttons;
wire           sftlk_sense;

wire    [21:0] gamma_bus;

wire           joy_en = ~model_active | (cfgcust & status[37]);
wire    [15:0] joyA, joyB, joyC, joyD;
wire     [7:0] pd1, pd2,pd3, pd4;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(NDU), .BLKSZ(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),

	.status(status),
	.status_menumask({
		/* D */ status[51], // drive #9 type
		/* C */ status[50], // drive #8 type
		/* B */ status[49], // drive #9 enabled
		/* A */ status[47], // drive #8 enabled
		/* 9 */ status[41],
		/* 8 */ status[40],
		/* 7 */ status[39],
		/* 6 */ joy_en,
		/* 5 */ ~status[28],
		/* 4 */ 1'b0,
		/* 3 */ |vcrop,
		/* 2 */ model7x0,
		/* 1 */ model_active,
		/* 0 */ cfgcust
	}),
	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),

	.sd_lba(sd_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_readonly(img_readonly),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.ps2_kbd_led_status(ps2_kbd_led_status),
	.ps2_kbd_led_use(ps2_kbd_led_use),

	.joystick_0(joyA),
	.joystick_1(joyB),
	.joystick_2(joyC),
	.joystick_3(joyD),

	.paddle_0(pd1),
	.paddle_1(pd2),
	.paddle_2(pd3),
	.paddle_3(pd4),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),
	.ioctl_wait(ioctl_req_wr|reset_wait)
);

wire load_rom      = ioctl_index[5:0] < 7;
wire load_rom_p500 = ioctl_index[5:0] == 1 || ioctl_index == {2'd0, 6'd0};
wire load_rom_b6x0 = ioctl_index[5:0] == 2 || ioctl_index == {2'd1, 6'd0};
wire load_rom_b7x0 = ioctl_index[5:0] == 3 || ioctl_index == {2'd2, 6'd0};
wire load_rom_2000 = ioctl_index[5:0] == 4;
wire load_rom_4000 = ioctl_index[5:0] == 5;
wire load_rom_6000 = ioctl_index[5:0] == 6;
// wire load_drv_4040 = ioctl_index == 7;
// wire load_drv_8250 = ioctl_index == 8;
wire load_prg      = ioctl_index == 9;

// System configuration
wire       model500 = status[4:2] == 0;
// wire    model6x0 = status[4:2] == 1 || status[4:2] == 2;
wire       model7x0 = status[4:2] == 3 || status[4:2] == 4;
wire       modelx10 = status[4:2] == 0 || status[4:2] == 1 || status[4:2] == 3;
// wire    modelx20 = status[4:2] == 2 || status[4:2] == 4;
wire       cfgcust  = status[4:2] == 5;

wire       model_requested = cfgcust ? |status[6:5] : ~model500;  // 0=P, 1=B
wire       profile = cfgcust ? status[6]    : model7x0;           // 0=P/L, 1=H
wire [1:0] ramsize = cfgcust ? status[10:9] : {1'b0, ~modelx10};  // 0=128k, 1=256k, 2=896k
wire       cpu2MHz = cfgcust ? status[11]   : model_active;       // 0=1MHz, 1=2MHz
wire       ntsc_requested = status[12] | model7x0;                // 0=PAL/50, 1=NTSC/60
wire       newVic  = status[25];                                  // 0=early, 1=modern

// ========================================================================
// I/O
// ========================================================================

reg  [1:0] erasing, force_erase;

reg [24:0] ioctl_load_addr;
reg        ioctl_req_wr;

reg        inj_meminit = 0;

wire       io_cycle;
reg        io_cycle_ce;
reg        io_cycle_we;
reg [24:0] io_cycle_addr;
reg  [7:0] io_cycle_data;

reg        chrgen_wr;
reg  [2:0] extbankrom = 0;
reg        prg_freeze;

always @(posedge clk_sys) begin
	reg  [4:0] erase_to;
	reg        old_download;
	reg        io_cycleD;
	reg [15:0] inj_start, inj_end;
	reg  [7:0] inj_meminit_data;

	old_download <= ioctl_download;
	io_cycleD <= io_cycle;
	chrgen_wr <= 0;

	if (~io_cycle & io_cycleD) begin
		io_cycle_ce <= 1;
		io_cycle_we <= 0;
		if (ioctl_req_wr && ((!load_prg && !inj_meminit) || freeze)) begin
			ioctl_req_wr <= 0;
			io_cycle_we <= 1;
			io_cycle_addr <= ioctl_load_addr;
			ioctl_load_addr <= ioctl_load_addr + 1'b1;

			if (erasing)
				io_cycle_data <= {8{ioctl_load_addr[14]^ioctl_load_addr[3]^ioctl_load_addr[2]}};
			else if (inj_meminit)
				io_cycle_data <= inj_meminit_data;
			else
				io_cycle_data <= ioctl_data;
		end
	end

	if (io_cycle & ~io_cycleD) io_cycle_ce <= 0;

	if (ioctl_wr && !erasing && !force_erase) begin
		if (load_rom_2000) begin
			// Allow a combined image to fill $2000-$7FFF.
			if (ioctl_addr < 'h6000) begin
				extbankrom[ioctl_addr[14:13]] <= 1;
				if (ioctl_addr == 0)
					ioctl_load_addr <= 25'h103_2000;
				ioctl_req_wr <= 1;
			end
		end
		else if (load_rom_4000) begin
			// Allow a combined image to fill $4000-$7FFF.
			if (ioctl_addr < 'h4000) begin
				extbankrom[ioctl_addr[13] ? 2 : 1] <= 1;
				if (ioctl_addr == 0)
					ioctl_load_addr <= 25'h103_4000;
				ioctl_req_wr <= 1;
			end
		end
		else if (load_rom_6000) begin
			extbankrom[2] <= 1;
			if (ioctl_addr == 0)
				ioctl_load_addr <= 25'h103_6000;
			if (ioctl_addr < 'h2000)
				ioctl_req_wr <= 1;
		end
		else if (load_rom_p500) begin
			if (ioctl_addr == 0)
				ioctl_load_addr <= 25'h102_0000;
			if (ioctl_addr < 'hB000)
				ioctl_req_wr <= 1;
		end
		else if (load_rom_b6x0) begin
			if (ioctl_addr == 0)
				ioctl_load_addr <= 25'h100_0000;
			if (ioctl_addr < 'hB000) begin
				ioctl_req_wr <= 1;
				if (ioctl_addr[15:12] == 'hA) chrgen_wr <= 1;
			end
		end
		else if (load_rom_b7x0) begin
			if (ioctl_addr == 0)
				ioctl_load_addr <= 25'h101_0000;
			if (ioctl_addr < 'hB000) begin
				ioctl_req_wr <= 1;
				if (ioctl_addr[15:12] == 'hA) chrgen_wr <= 1;
			end
		end
		else if (load_prg) begin
			if (ioctl_addr == 0) begin
				prg_freeze <= 1;
				ioctl_load_addr[7:0]  <= status[24] ? ioctl_data : 8'h03;
				inj_start[7:0]        <= status[24] ? ioctl_data : 8'h03;
				inj_end[7:0]          <= status[24] ? ioctl_data : 8'h03;
			end
			else if (ioctl_addr == 1) begin
				ioctl_load_addr[24:16]<= model_active ? 9'd1 : 9'd0;
				ioctl_load_addr[15:8] <= status[24] ? ioctl_data : 8'h00;
				inj_start[15:8]       <= status[24] ? ioctl_data : 8'h00;
				inj_end[15:8]         <= status[24] ? ioctl_data : 8'h00;
			end
			else begin
				ioctl_req_wr <= 1;
				inj_end <= inj_end + 1'b1;
			end
		end
	end

	// meminit for RAM injection
	if (old_download && !ioctl_download && load_prg && !inj_meminit) begin
		inj_meminit <= 1;
		ioctl_load_addr <= 25'h00F_0000;
	end

	if (inj_meminit && !ioctl_req_wr) begin
		if (ioctl_load_addr[8]) begin
			inj_meminit <= 0;
			prg_freeze <= 0;
		end
		else begin
			ioctl_req_wr <= 1;

			// Initialize BASIC pointers to simulate the BASIC LOAD command
			case(ioctl_load_addr[7:0])
				// TXTTAB (2D-2E), BUFFPT (99-9B)
				'h2D, 'h99: inj_meminit_data <= inj_start[7:0];
				'h2E, 'h9A: inj_meminit_data <= inj_start[15:8];

				// TXTEND (2F-30), TXTPTR (96-98)
				'h2F, 'h96: inj_meminit_data <= inj_end[7:0];
				'h30, 'h97: inj_meminit_data <= inj_end[15:8];

				// BUFFPT/TXTPTR bank 
				'h98, 'h9B: inj_meminit_data <= model_active ? 8'd1 : 8'd0;

				default: begin
					ioctl_req_wr <= 0;
					ioctl_load_addr <= ioctl_load_addr + 1'b1;
				end
			endcase
		end
	end

	if (!erasing && force_erase && !cancel_erase) begin
		erase_to <= 0;
		erasing <= force_erase;
		if (force_erase == 2)
			ioctl_load_addr <= model_active ? 25'h01_0000 : 25'h00_0000;
		else
			ioctl_load_addr <= 25'h0F_0000;
	end

	if (erasing && !ioctl_req_wr) begin
		erase_to <= erase_to + 1'b1;
		if (&erase_to) begin
			ioctl_req_wr <= 1;
			if ((ramsize == 0 && model_active == 0 && ioctl_load_addr == 'h01_FFFF) // 128k P
			  ||(ramsize == 0 && model_active == 1 && ioctl_load_addr == 'h02_FFFF) // 128k B
			  ||(ramsize == 1 && model_active == 0 && ioctl_load_addr == 'h03_FFFF) // 256k P
			  ||(ramsize == 1 && model_active == 1 && ioctl_load_addr == 'h04_FFFF) // 256k B
			) begin
				ioctl_load_addr <= 'h0F_0000;
			end
			else if (erasing == 1 && ioctl_load_addr == 'h0F_0FFF) begin
				ioctl_load_addr <= 'h0F_D000;
			end
			else if (ioctl_load_addr == 'h0F_D7FF) begin
				erasing <= 0;
				ioctl_req_wr <= 0;
			end
		end
	end

	if (erasing && cancel_erase) begin
		erasing <= 0;
		ioctl_req_wr <= 0;
	end
end

// ========================================================================
// SDRAM
// ========================================================================

assign SDRAM_CKE  = 1;

wire [7:0]  sdram_data;

sdram sdram
(
	.sd_addr(SDRAM_A),
	.sd_data(SDRAM_DQ),
	.sd_ba(SDRAM_BA),
	.sd_cs(SDRAM_nCS),
	.sd_we(SDRAM_nWE),
	.sd_ras(SDRAM_nRAS),
	.sd_cas(SDRAM_nCAS),
	.sd_clk(SDRAM_CLK),
	.sd_dqm({SDRAM_DQMH,SDRAM_DQML}),

	.clk(clk_sdr),
	.init(~pll_locked),
	.refresh(refresh),
	.addr(io_cycle ? io_cycle_addr : cpu_addr),
	.ce  (io_cycle ? io_cycle_ce   : cpu_ce),
	.we  (io_cycle ? io_cycle_we   : cpu_we),
	.din (io_cycle ? io_cycle_data : cpu_out),
	.dout(sdram_data)
);

// ========================================================================
// Joystick/paddles/mouse
// ========================================================================

wire [7:0] mouse_x;
wire [7:0] mouse_y;
wire [1:0] mouse_btn;

c1351 mouse
(
	.clk_sys(clk_sys),
	.reset(~reset_n),

	.ps2_mouse(ps2_mouse),

	.potX(mouse_x),
	.potY(mouse_y),
	.button(mouse_btn)
);

wire  [1:0] pd12_mode = status[33:32];
wire  [1:0] pd34_mode = status[35:34];

wire  [6:0] joyA_int = {joyA[6:4], joyA[0], joyA[1], joyA[2], joyA[3]};
wire  [6:0] joyB_int = {joyB[6:4], joyB[0], joyB[1], joyB[2], joyB[3]};
wire  [6:0] joyA_cbm = status[36] ? joyB_int : joyA_int;
wire  [6:0] joyB_cbm = status[36] ? joyA_int : joyB_int;

wire  [7:0] paddle_1 = status[36] ? pd3 : pd1;
wire  [7:0] paddle_2 = status[36] ? pd4 : pd2;
wire  [7:0] paddle_3 = status[36] ? pd1 : pd3;
wire  [7:0] paddle_4 = status[36] ? pd2 : pd4;

wire        paddle_1_btn = status[36] ? joyC[7] : joyA[7];
wire        paddle_2_btn = status[36] ? joyD[7] : joyB[7];
wire        paddle_3_btn = status[36] ? joyA[7] : joyC[7];
wire        paddle_4_btn = status[36] ? joyB[7] : joyD[7];

// ========================================================================
// CBM-II Main
// ========================================================================

wire [24:0] cpu_addr;
wire        cpu_ce;
wire  [7:0] cpu_out;
wire        cpu_we;

wire        pause;

wire        refresh;
wire  [7:0] r, g, b;
wire        hsync, vsync;
wire        hblank, vblank;

wire [17:0] audio;

st_ieee_bus ieee_bus_te;
st_ieee_bus ieee_bus_dc;

cbm2_main main (
	.CLK(CLK),

	.model(model_active),
	.profile(profile),
	.ntsc(ntsc_active),
	.newVic(newVic),
	.cpu2MHz(cpu2MHz),
	.ramSize(ramsize),
	.copro(2'b00),
	.extbankrom(extbankrom),
	.extbankram(status[41:38]),

	.pause(freeze & ~transition_active),
	.pause_out(pause),

	.clk_sys(clk_sys),
	.reset_n(reset_n),

	.kbd_reset(~reset_n & ~status[13]),
	.ps2_key(ps2_key),

	.joy_en(joy_en),
	.joya({joyA_cbm[4:0] | {1'b0, pd12_mode[1] & paddle_2_btn, pd12_mode[1] & paddle_1_btn, 2'b00} | {pd12_mode[0] & mouse_btn[0], 3'b000, pd12_mode[0] & mouse_btn[1]}}),
	.joyb({joyB_cbm[4:0] | {1'b0, pd34_mode[1] & paddle_4_btn, pd34_mode[1] & paddle_3_btn, 2'b00} | {pd34_mode[0] & mouse_btn[0], 3'b000, pd34_mode[0] & mouse_btn[1]}}),

	.pot1(pd12_mode[1] ? paddle_1 : pd12_mode[0] ? mouse_x : {8{joyA_cbm[5]}}),
	.pot2(pd12_mode[1] ? paddle_2 : pd12_mode[0] ? mouse_y : {8{joyA_cbm[6]}}),
	.pot3(pd34_mode[1] ? paddle_3 : pd34_mode[0] ? mouse_x : {8{joyB_cbm[5]}}),
	.pot4(pd34_mode[1] ? paddle_4 : pd34_mode[0] ? mouse_y : {8{joyB_cbm[6]}}),

	.sid_ld_clk(clk_sys),
	.sid_ld_addr(12'd0),
	.sid_ld_data(16'd0),
	.sid_ld_wr(1'b0),
	.sid_cfg(status[27:26]),
	.sid_fc_off(status[28] ? (13'h600 - {status[31:29],7'd0}) : 13'd0),

	.ieee_i(ieee_bus_te),
	.ieee_o(ieee_bus_dc),

	.iec_atn_o(cbm_iec_atn),
	.iec_clk_o(cbm_iec_clk),
	.iec_clk_i(ext_iec_clk),
	.iec_data_o(cbm_iec_data),
	.iec_data_i(ext_iec_data),

	.ramAddr(cpu_addr),
	.ramData(sdram_data),
	.ramOut(cpu_out),
	.ramCE(cpu_ce),
	.ramWE(cpu_we),
	.refresh(refresh),

	.io_cycle(io_cycle),

	.hsync(hsync),
	.vsync(vsync),
	.hblank(hblank),
	.vblank(vblank),
	.r(r),
	.g(g),
	.b(b),

	.audio(audio),

	.sftlk_sense(sftlk_sense),

	.erase_colram(erasing && ioctl_load_addr[24:12] == 'h00F_D4 && ioctl_load_addr[11:10] == 0),
	.erase_colram_addr(ioctl_load_addr[9:0]),

	.chrgen_wr(chrgen_wr),
	.chrgen_addr({ioctl_load_addr[16], ioctl_load_addr[12:0]}),
	.chrgen_data(ioctl_data)
);

// ========================================================================
// IEEE
// ========================================================================

wire drive_reset = ~reset_n | status[44];
wire [1:0] drive_led;

reg [3:0] drive_mounted = 0;
always @(posedge clk_sys) begin 
	if(img_mounted[0]) drive_mounted[0] <= |img_size;
	if(img_mounted[1]) drive_mounted[1] <= |img_size;
	if(img_mounted[2]) drive_mounted[2] <= |img_size;
	if(img_mounted[3]) drive_mounted[3] <= |img_size;
end

ieee_drive #(.DRIVES(NDRIVES)) ieee_drive
(
	.CLK(CLK),

	.clk_sys(clk_sys),
	.reset({drive_reset | ((!status[49:48]) ? !drive_mounted[3:2] : status[49]),
			  drive_reset | ((!status[47:46]) ? !drive_mounted[1:0] : status[47])}),

	.pause(pause),

	.led(drive_led),

	.bus_i(ieee_bus_dc),
	.bus_o(ieee_bus_te),

	.sd_lba(sd_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.drv_type({status[51], status[50]}),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),

	// Runtime drive-ROM loading is intentionally disabled.
	.rom_wr(1'b0),
	.rom_sel(1'b0),
	.rom_addr(15'd0),
	.rom_data(8'd0)
);

// ========================================================================
// External IEC
// ========================================================================

wire cbm_iec_atn;
wire cbm_iec_clk;
wire cbm_iec_data;

wire ext_iec_en   = status[45];
wire ext_iec_clk  = USER_IN[2] | ~ext_iec_en;
wire ext_iec_data = USER_IN[4] | ~ext_iec_en;

assign USER_OUT[2] = cbm_iec_clk | ~ext_iec_en;
assign USER_OUT[3] = (reset_n & ~status[44]) | ~ext_iec_en;
assign USER_OUT[4] = cbm_iec_data | ~ext_iec_en;
assign USER_OUT[5] = cbm_iec_atn | ~ext_iec_en;

// ========================================================================
// Video
// ========================================================================

wire hsync_vic;
wire vsync_vic;
wire hblank_vic;
wire vblank_vic;

video_sync_vic sync_vic
(
	.clk32(clk_sys),
	.reset(video_path_reset_sys),
	.pause(pause | model_active),
	.hsync(hsync),
	.vsync(vsync),
	.ntsc(ntsc_active & newVic),
	.ntscOld(ntsc_active & ~newVic),
	.wide(wide),
	.hsync_out(hsync_vic),
	.vsync_out(vsync_vic),
	.hblank(hblank_vic),
	.vblank(vblank_vic)
);

wire hsync_crtc;
wire vsync_crtc;
wire hblank_crtc;
wire vblank_crtc;

video_sync_crtc sync_crtc
(
	.clk(clk_sys),
	.reset(video_path_reset_sys),
	.hsync(hsync),
	.vsync(vsync),
	.hblank(hblank),
	.vblank(vblank),
	.hsync_out(hsync_crtc),
	.vsync_out(vsync_crtc),
	.hblank_out(hblank_crtc),
	.vblank_out(vblank_crtc)
);

wire vsync_out  = model_active ? vsync_crtc  : vsync_vic;
wire hsync_out  = model_active ? hsync_crtc  : hsync_vic;
wire vblank_out = model_active ? vblank_crtc : vblank_vic;
wire hblank_out = model_active ? hblank_crtc : hblank_vic;

reg hq2x320, hq2x160;
reg ce_pix;
always @(posedge CLK_VIDEO) begin
	reg [1:0] vsync_r;
	reg [1:0] div;
	reg [1:0] lores;

	if (video_path_reset_vid) begin
		vsync_r <= 0;
		div <= 0;
		lores <= 0;
		hq2x320 <= 0;
		hq2x160 <= 0;
		ce_pix <= 0;
	end
	else begin
		vsync_r <= {vsync_r[0], vsync};
		if (vsync_r == 'b01) begin
			hq2x320 <= (status[20:18] == 1) || !model_active;
			hq2x160 <= (status[20:18] == 2);
			div <= 2'd2;
			lores <= 0;
		end
		else
			div <= div + 1'd1;

		if (&div)
			lores <= lores + 1'd1;

		ce_pix <= (~|lores | ~hq2x160) && (~lores[0] | ~hq2x320) && !div;
	end
end

wire scandoubler = status[20:18] || forced_scandoubler;

assign CLK_VIDEO = clk_vid;
assign VGA_SL    = (status[20:18] > 2) ? status[19:18] - 2'd2 : 2'd0;
assign VGA_F1    = 0;

wire [7:0] rc, gc, bc;
wire vsc,hsc,hblc,vblc,vdec;
video_cleaner video_cleaner
(
	.clk_vid(CLK_VIDEO),
	.ce_pix(ce_pix),

	.R(r),
	.G(g),
	.B(b),
	.HSync(hsync_out),
	.VSync(vsync_out),
	.HBlank(hblank_out),
	.VBlank(vblank_out),
	.DE_in(vga_de),
	.interlace(1'b0),
	.f1(1'b0),

	.VGA_R(rc),
	.VGA_G(gc),
	.VGA_B(bc),
	.VGA_VS(vsc),
	.VGA_HS(hsc),
	.VGA_DE(),
	.HBlank_out(hblc),
	.VBlank_out(vblc),
	.DE_out(vdec)
);

reg [9:0] vcrop;
reg wide;
always @(posedge CLK_VIDEO) begin
	vcrop <= 0;
	wide <= 0;
	if (!model_active) begin
		if(HDMI_WIDTH >= (HDMI_HEIGHT + HDMI_HEIGHT[11:1]) && !scandoubler) begin
			if(HDMI_HEIGHT == 480)  vcrop <= 10'd240;
			if(HDMI_HEIGHT == 600)  begin vcrop <= 10'd200; wide <= vcrop_en; end
			if(HDMI_HEIGHT == 720)  vcrop <= 10'd240;
			if(HDMI_HEIGHT == 768)  vcrop <= 10'd256; // NTSC mode has 250 visible lines only!
			if(HDMI_HEIGHT == 800)  begin vcrop <= 10'd200; wide <= vcrop_en; end
			if(HDMI_HEIGHT == 1080) vcrop <= 10'd216;
			if(HDMI_HEIGHT == 1200) vcrop <= 10'd240;
		end
		else if(HDMI_WIDTH >= 1440 && !scandoubler) begin
			// 1920x1440 and 2048x1536 are 4:3 resolutions and won't fit in the previous if statement ( width > height * 1.5 )
			if(HDMI_HEIGHT == 1440) vcrop <= 10'd240;
			if(HDMI_HEIGHT == 1536) vcrop <= 10'd256;
		end
	end
end

wire [1:0] ar = status[17:16];
wire vcrop_en = status[21];
wire vga_de;
video_freak video_freak
(
	.*,
	.VGA_DE_IN(vdec),
	.ARX((!ar) ? (wide ? 12'd340 : 12'd400) : (ar - 1'd1)),
	.ARY((!ar) ? 12'd300 : 12'd0),
	.CROP_SIZE(vcrop_en ? vcrop : 10'd0),
	.CROP_OFF(0),
	.SCALE(status[23:22])
);

wire freeze_sync;
reg freeze;
always @(posedge clk_sys) begin
	reg old_sync;

	old_sync <= freeze_sync;
	if(old_sync ^ freeze_sync) freeze <= (OSD_STATUS & status[15]) | prg_freeze;
end

assign HDMI_FREEZE = freeze | transition_freeze | emergency_pll_freeze;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

video_mixer #(.GAMMA(1)) video_mixer
(
	.CLK_VIDEO(CLK_VIDEO),

	.hq2x(~status[20] & (status[19] ^ status[18])),
	.scandoubler(scandoubler),
	.gamma_bus(gamma_bus),

	.ce_pix(ce_pix),
	.R(rc),
	.G(gc),
	.B(bc),
	.HSync(hsc),
	.VSync(vsc),
	.HBlank(hblc),
	.VBlank(vblc),

	.HDMI_FREEZE(HDMI_FREEZE),
	.freeze_sync(freeze_sync),

	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(vga_de)
);

// ========================================================================
// Audio
// ========================================================================

assign AUDIO_S = 1;
assign AUDIO_L = audio[17:2];
assign AUDIO_R = audio[17:2];
assign AUDIO_MIX = 0;

endmodule
