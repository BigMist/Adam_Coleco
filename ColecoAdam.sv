//============================================================================
//  ColecoVision
//
//  Port to MiSTer
//  Copyright (C) 2017-2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================
`default_nettype none

module guest_top
#
(
   parameter  NUM_DISKS = 2,
   parameter  NUM_TAPES = 2,
   parameter  USE_REQ   = 1,
   parameter  TOT_DISKS = NUM_DISKS + NUM_TAPES
)
(
	input         CLOCK_27,
`ifdef USE_CLOCK_50
	input         CLOCK_50,
`endif

	output        LED,
	output [VGA_BITS-1:0] VGA_R,
	output [VGA_BITS-1:0] VGA_G,
	output [VGA_BITS-1:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,

`ifdef USE_HDMI
	output        HDMI_RST,
	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_PCLK,
	output        HDMI_DE,
	inout         HDMI_SDA,
	inout         HDMI_SCL,
	input         HDMI_INT,
`endif

	input         SPI_SCK,
	inout         SPI_DO,
	input         SPI_DI,
	input         SPI_SS2,    // data_io
	input         SPI_SS3,    // OSD
	input         CONF_DATA0, // SPI_SS for user_io

`ifdef USE_QSPI
	input         QSCK,
	input         QCSn,
	inout   [3:0] QDAT,
`endif
`ifndef NO_DIRECT_UPLOAD
	input         SPI_SS4,
`endif

	output [12:0] SDRAM_A,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nWE,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nCS,
	output  [1:0] SDRAM_BA,
	output        SDRAM_CLK,
	output        SDRAM_CKE,

`ifdef DUAL_SDRAM
	output [12:0] SDRAM2_A,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_DQML,
	output        SDRAM2_DQMH,
	output        SDRAM2_nWE,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nCS,
	output  [1:0] SDRAM2_BA,
	output        SDRAM2_CLK,
	output        SDRAM2_CKE,
`endif

	output        AUDIO_L,
	output        AUDIO_R,
`ifdef I2S_AUDIO
	output        I2S_BCK,
	output        I2S_LRCK,
	output        I2S_DATA,
`endif
`ifdef I2S_AUDIO_HDMI
	output        HDMI_MCLK,
	output        HDMI_BCK,
	output        HDMI_LRCK,
	output        HDMI_SDATA,
`endif
`ifdef SPDIF_AUDIO
	output        SPDIF,
`endif
`ifdef USE_AUDIO_IN
	input         AUDIO_IN,
`endif
	input         UART_RX,
	output        UART_TX

);

`ifdef NO_DIRECT_UPLOAD
localparam bit DIRECT_UPLOAD = 0;
wire SPI_SS4 = 1;
`else
localparam bit DIRECT_UPLOAD = 1;
`endif

`ifdef USE_QSPI
localparam bit QSPI = 1;
assign QDAT = 4'hZ;
`else
localparam bit QSPI = 0;
`endif

`ifdef VGA_8BIT
localparam VGA_BITS = 8;
`else
localparam VGA_BITS = 6;
`endif

`ifdef USE_HDMI
localparam bit HDMI = 1;
assign HDMI_RST = 1'b1;
`else
localparam bit HDMI = 0;
`endif

`ifdef BIG_OSD
localparam bit BIG_OSD = 1;
`define SEP "-;",
`else
localparam bit BIG_OSD = 0;
`define SEP
`endif

`ifdef USE_AUDIO_IN
localparam bit USE_AUDIO_IN = 1;
wire TAPE_SOUND=AUDIO_IN;
`else
localparam bit USE_AUDIO_IN = 0;
wire TAPE_SOUND=UART_RX;
`endif


assign LED   = ~(|sd_rd || ioctl_download); 


`include "build_id.v"
parameter CONF_STR = {
        "Adam;;",
        "F1,COLBINROM,Load CART;",
		  `SEP
        "S0U,DSK,Load Floppy 1;",
        "S1U,DSK,Load Floppy 2;",
	     "S2U,DDP,Load Tape 1;",
        "S3U,DDP,Load Tape 2;",
 		  `SEP
        "O3,Joysticks swap,No,Yes;",
        "OC,Mode,Computer,Console;",
		  `SEP
		  "OD,F18A Max Sprites,4,32;",
        "OE,F18A Scanlines,Off,On;",
        "-;",
        "T0,Reset;",
        "V,v",`BUILD_DATE
};

/////////////////  CLOCKS  ////////////////////////

wire clk_sys,clk_25,clk_100;
wire pll_locked;

pll pll
(
        .inclk0(CLOCK_50),
        .areset(0),
        .c0(clk_sys),
        .locked(pll_locked)
);

pll_vdp pll_vdp
(
        .inclk0(CLOCK_50),
        .areset(0),
        .c0(clk_100),
		  .c1(clk_25)
);
reg ce_10m7 = 0;
reg ce_5m3 = 0;
always @(posedge clk_sys) begin
        reg [2:0] div;

        div <= div+1'd1;
        ce_10m7 <= !div[1:0];
        ce_5m3  <= !div[2:0];
end

/////////////////  HPS  ///////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire [31:0] joy0, joy1;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        forced_scandoubler;

wire [31:0] sd_lba[TOT_DISKS];
wire [31:0] sd_lba_mux;
reg   [TOT_DISKS-1:0] sd_rd;
reg   [TOT_DISKS-1:0] sd_wr;
wire  [TOT_DISKS-1:0] sd_ack;
wire        sd_ack_mux;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din[TOT_DISKS];
wire  [7:0] sd_buff_din_mux;
wire        sd_buff_wr;

wire  [TOT_DISKS-1:0] img_mounted;
wire        img_readonly;

wire [63:0] img_size;

wire ypbpr;
wire [31:0] img_ext;


// multiplexing by hand the mister images.

always @(posedge clk_sys) begin
    if (sd_rd[0] || sd_wr[0]) begin
			sd_lba_mux     <= sd_lba[0];
			sd_buff_din_mux<= sd_buff_din[0];
			sd_ack[0]      <= sd_ack_mux; 
	 end
    if (sd_rd[1] || sd_wr[1]) begin
			sd_lba_mux     <= sd_lba[1];
			sd_buff_din_mux<= sd_buff_din[1];
			sd_ack[1]      <= sd_ack_mux; 
	 end
   
	if (sd_rd[2] || sd_wr[2]) begin
			sd_lba_mux     <= sd_lba[2];
			sd_buff_din_mux<= sd_buff_din[2];
			sd_ack[2]      <= sd_ack_mux; 
	 end
    if (sd_rd[3] || sd_wr[3]) begin
			sd_lba_mux     <= sd_lba[3];
			sd_buff_din_mux<= sd_buff_din[3];
			sd_ack[3]      <= sd_ack_mux; 
	 end	 
//	 if (sd_rd[4] || sd_wr[4]) begin
//    	 sd_lba_mux     <= sd_lba[4];
//		 sd_buff_din_mux<= sd_buff_din[4];
//		 sd_ack[4]      <= sd_ack_mux; 
//    end
//	 
//    if (sd_rd[5] || sd_wr[5]) begin
//		 sd_lba_mux     <= sd_lba[5];
//		 sd_buff_din_mux<= sd_buff_din[5];
//		 sd_ack[5]      <= sd_ack_mux; 
//	 end
//   if (sd_rd[6] || sd_wr[6]) begin
//			sd_lba_mux     <= sd_lba[6];
//			sd_buff_din_mux<= sd_buff_din[6];
//			sd_ack[6]      <= sd_ack_mux; 
//	 end
//    if (sd_rd[7] || sd_wr[7]) begin
//			sd_lba_mux     <= sd_lba[7];
//			sd_buff_din_mux<= sd_buff_din[7];
//			sd_ack[7]      <= sd_ack_mux; 
//	 end
end

// [8] - extended, [9] - pressed, [10] - toggles with every press/release
wire [10:0] ps2_key; 
wire        key_pressed;
wire [7:0]  key_code;
wire        key_strobe;
wire        key_extended;


assign ps2_key = {key_strobe,key_pressed,key_extended,key_code}; 


user_io #(
          .STRLEN($size(CONF_STR)>>3),
			 .SD_IMAGES(TOT_DISKS),
			 .FEATURES(32'h8 | (BIG_OSD << 13) | (HDMI << 14))) user_io
(
	.clk_sys             (clk_sys          ),
   .clk_sd              (clk_sys          ),
	.SPI_SS_IO           (CONF_DATA0),
	.SPI_CLK             (SPI_SCK),
	.SPI_MOSI            (SPI_DI),
	.SPI_MISO            (SPI_DO),

	.conf_str            (CONF_STR),
	.status              (status),
	.scandoubler_disable (forced_scandoubler),
	.ypbpr               (ypbpr),
	.no_csync            (),
	.buttons             (buttons),
	
    .key_strobe(key_strobe),
    .key_code(key_code),
    .key_pressed(key_pressed),
    .key_extended(key_extended),
	 
`ifdef USE_HDMI
	.i2c_start      (i2c_start      ),
	.i2c_read       (i2c_read       ),
	.i2c_addr       (i2c_addr       ),
	.i2c_subaddr    (i2c_subaddr    ),
	.i2c_dout       (i2c_dout       ),
	.i2c_din        (i2c_din        ),
	.i2c_ack        (i2c_ack        ),
	.i2c_end        (i2c_end        ),
`endif
	 
	.sd_sdhc             (1),
	.sd_lba              (sd_lba_mux),
	.sd_rd               (sd_rd),
	.sd_wr               (sd_wr),
	.sd_ack              (sd_ack_mux),
	.sd_buff_addr        (sd_buff_addr),
	.sd_dout             (sd_buff_dout),
	.sd_din              (sd_buff_din_mux),
	.sd_dout_strobe      (sd_buff_wr),
	
	.img_mounted(img_mounted),
	.img_size(img_size),
	//.img_readonly(img_readonly),

	.joystick_0          (joy0          ),
	.joystick_1          (joy1          )
);

`ifdef USE_HDMI
wire        i2c_start;
wire        i2c_read;
wire  [6:0] i2c_addr;
wire  [7:0] i2c_subaddr;
wire  [7:0] i2c_dout;
wire  [7:0] i2c_din;
wire        i2c_ack;
wire        i2c_end;
`endif


data_io  data_io(
	.clk_sys       ( clk_sys      ),
	.SPI_SCK       ( SPI_SCK      ),
	.SPI_SS2       ( SPI_SS2      ),
`ifdef USE_QSPI
	.QSCK          ( QSCK         ),
	.QCSn          ( QCSn         ),
	.QDAT          ( QDAT         ),
`endif
`ifdef NO_DIRECT_UPLOAD
	.SPI_SS4       ( 1'b1         ),
`else
	.SPI_SS4       ( SPI_SS4      ),
`endif
	.SPI_DI        ( SPI_DI       ),
	.SPI_DO        ( SPI_DO       ),
	//.clkref_n      ( ~clkref      ),
	.ioctl_fileext       (img_ext),
	.ioctl_download( ioctl_download  ),
	.ioctl_index   ( ioctl_index  ),
	.ioctl_wr      ( ioctl_wr     ),
	.ioctl_addr    ( ioctl_addr   ),
	.ioctl_dout    ( ioctl_dout   )
);




/////////////////  RESET  /////////////////////////

reg old_mode;
reg mode;
assign mode = ~status[12];

always @(posedge clk_sys) begin
        old_mode <= mode ;
end

wire reset =  status[0] | buttons[1] | old_mode != mode | ioctl_download | ~pll_locked;


/////////////////  Memory  ////////////////////////

wire [12:0] bios_a;
wire  [7:0] bios_d;



spramv #(13,8,"../rtl/bios.hex") rom0
(
        .clock(clk_sys),
        .address(bios_a),
        .q(bios_d)
);


wire [14:0] writer_a;
wire  [7:0] writer_d;
rom #(15,8,"../rtl/writer.hex") rom2
(
        .clock(clk_sys),
        .address(writer_a),
        .enable(1'b1),
        .q(writer_d)
);


wire [13:0] eos_a;
wire  [7:0] eos_d;

rom #(14,8,"../rtl/eos.hex") rom3
(
        .clock(clk_sys),
        .address(eos_a),
        .enable(1'b1),
        .q(eos_d)
);


wire [14:0] cpu_ram_a;
wire        ram_we_n, ram_ce_n;
wire  [7:0] ram_di;
wire  [7:0] ram_do;
wire [14:0] ram_a = cpu_ram_a;



														
  logic [15:0] ramb_addr;
  logic        ramb_wr;
  logic        ramb_rd;
  logic [7:0]  ramb_dout;
  logic [7:0]  int_ramb_din[2];
  logic [7:0]  ramb_din;
  logic        ramb_wr_ack;
  logic        ramb_rd_ack;

dpramv #(8, 15) ram
(
        .clock_a(clk_sys),
        .address_a(ram_a),
        .wren_a(ce_10m7 & ~(ram_we_n | ram_ce_n)),
        .data_a(ram_do),
        .q_a(ram_di),
        .clock_b(clk_sys),
        .address_b(ramb_addr[14:0]),
        .wren_b(ramb_wr & ~ramb_addr[15]),
        .data_b(ramb_dout),
        .q_b(int_ramb_din[0]),

        .enable_b(1'b1),
        .ce_a(1'b1)
);

  always @(posedge clk_sys) begin
    ramb_wr_ack <= ramb_wr;
    ramb_rd_ack <= ramb_rd;
  end

assign ramb_din = ~ramb_addr[15] ? int_ramb_din[0] : int_ramb_din[1];

wire [14:0]         lowerexpansion_ram_a;
wire lowerexpansion_ram_ce_n;
wire lowerexpansion_ram_rd_n;
wire lowerexpansion_ram_we_n;
wire [7:0] lowerexpansion_ram_di;
wire [7:0] lowerexpansion_ram_do;

spramv #(15) lowerexpansion_ram
    (
     .clock(clk_sys),
     .address(lowerexpansion_ram_a),
     .wren(ce_10m7 & ~(lowerexpansion_ram_we_n | lowerexpansion_ram_ce_n)),
     .data(lowerexpansion_ram_do),
     .q(lowerexpansion_ram_di),
     .cs(1'b1)
     );

wire [14:0] upper_ram_a;
wire        upper_ram_we_n, upper_ram_ce_n;
wire  [7:0] upper_ram_di;
wire  [7:0] upper_ram_do;
  dpramv #(8, 15) upper_ram
    (
     .clock_a(clk_sys),
     .address_a(upper_ram_a),
     .wren_a(ce_10m7 & ~(upper_ram_we_n | upper_ram_ce_n)),
     .data_a(upper_ram_do),
     .q_a(upper_ram_di),

     .clock_b(clk_sys),
     .address_b(ramb_addr[14:0]),
     .wren_b(ramb_wr & ramb_addr[15]),
     .data_b(ramb_dout),
     .q_b(int_ramb_din[1]),

     .enable_b(1'b1),
     .ce_a(1'b1)
     );


wire [19:0] cart_a;
wire  [7:0] cart_d;
wire cart_rd;

reg [5:0] cart_pages = 6'b0;
always @(posedge clk_sys) if(ioctl_wr) cart_pages <= ioctl_addr[19:14];

assign SDRAM_CLK = ~clk_sys;
sdram sdram
(
   .*,
   .init(~pll_locked),
   .clk(clk_sys),

   .wtbt(0),
   .addr(ioctl_download ? ioctl_addr : cart_a),
   .rd(cart_rd),
   .dout(cart_d),
   .din(ioctl_dout),
   .we(ioctl_wr),
   .ready()
);

wire [19:0] ext_rom_a;
wire  [7:0] ext_rom_d=8'hff;


////////////////  Console  ////////////////////////

wire [13:0] audio;
wire [15:0] DAC_L = {~audio[13],audio[12:0],2'b0};
wire [15:0] DAC_R = {~audio[13],audio[12:0],2'b0};


wire CLK_VIDEO = clk_sys;

wire [1:0] ctrl_p1;
wire [1:0] ctrl_p2;
wire [1:0] ctrl_p3;
wire [1:0] ctrl_p4;
wire [1:0] ctrl_p5;
wire [1:0] ctrl_p6;
wire [1:0] ctrl_p7 = 2'b11;
wire [1:0] ctrl_p8;
wire [1:0] ctrl_p9 = 2'b11;

wire [7:0] R,G,B;
wire hblank, vblank;
wire hsync, vsync;

wire [31:0] joya = status[3] ? joy1 : joy0;
wire [31:0] joyb = status[3] ? joy0 : joy1;


  logic [TOT_DISKS-1:0] disk_present;
  logic [31:0]          disk_sector; // sector
  logic [TOT_DISKS-1:0] disk_load; // load the 512 byte sector
  logic [TOT_DISKS-1:0] disk_sector_loaded; // set high when sector ready
  logic [8:0]           disk_addr; // Byte to read or write from sector
  logic [TOT_DISKS-1:0] disk_wr; // Write data into sector (read when low)
  logic [TOT_DISKS-1:0] disk_flush; // sector access done, so flush (hint)
  logic [TOT_DISKS-1:0] disk_flushed; // sector access done, so flush (hint)
  logic [TOT_DISKS-1:0] disk_error; // out of bounds (?)
  logic [7:0]           disk_data[TOT_DISKS];
  logic [7:0]           disk_din;

cv_console
    #
    (
     .NUM_DISKS (NUM_DISKS),
     .NUM_TAPES (NUM_TAPES),
     .USE_REQ   (USE_REQ)
     )
  console
    (
        .clk_i(clk_sys),
		  .clk_100_i (clk_100),
		  .clk_25_i  (clk_25),
        .clk_en_10m7_i(ce_10m7),
        .reset_n_i(~reset),
		  .sprite_max_i(~status[13]),
        .scan_lines_i(status[14]),
        .por_n_o(),
        .mode(~mode),
        .ctrl_p1_i(ctrl_p1),
        .ctrl_p2_i(ctrl_p2),
        .ctrl_p3_i(ctrl_p3),
        .ctrl_p4_i(ctrl_p4),
        .ctrl_p5_o(ctrl_p5),
        .ctrl_p6_i(ctrl_p6),
        .ctrl_p7_i(ctrl_p7),
        .ctrl_p8_o(ctrl_p8),
        .ctrl_p9_i(ctrl_p9),
        .joy0_i(~{|joya[19:6], 1'b0, joya[5:0]}),
        .joy1_i(~{|joyb[19:6], 1'b0, joyb[5:0]}),

        .bios_rom_a_o(bios_a),
        .bios_rom_d_i(bios_d),
  
        .eos_rom_a_o(eos_a),
        .eos_rom_d_i(eos_d),

        .writer_rom_a_o(writer_a),
        .writer_rom_d_i(writer_d),

        .cpu_ram_a_o(cpu_ram_a),
        .cpu_ram_we_n_o(ram_we_n),
        .cpu_ram_ce_n_o(ram_ce_n),
        .cpu_ram_d_i(ram_di),
        .cpu_ram_d_o(ram_do),

        .cpu_lowerexpansion_ram_a_o(lowerexpansion_ram_a),
        .cpu_lowerexpansion_ram_we_n_o(lowerexpansion_ram_we_n),
        .cpu_lowerexpansion_ram_ce_n_o(lowerexpansion_ram_ce_n),
        .cpu_lowerexpansion_ram_d_i(lowerexpansion_ram_di),
        .cpu_lowerexpansion_ram_d_o(lowerexpansion_ram_do),

        .cpu_upper_ram_a_o(upper_ram_a),
        .cpu_upper_ram_we_n_o(upper_ram_we_n),
        .cpu_upper_ram_ce_n_o(upper_ram_ce_n),
        .cpu_upper_ram_d_i(upper_ram_di),
        .cpu_upper_ram_d_o(upper_ram_do),

//        .ramb_addr(ramb_addr),
//        .ramb_wr(ramb_wr),
//        .ramb_rd(ramb_rd),
//        .ramb_dout(ramb_dout),
//        .ramb_wr_ack(ramb_wr_ack),
//        .ramb_rd_ack(ramb_rd_ack),
		  
        .ramb_addr(ramb_addr),
        .ramb_wr(ramb_wr),
        .ramb_rd(ramb_rd),
        .ramb_din(ramb_din),
        .ramb_dout(ramb_dout),
        .ramb_wr_ack(ramb_wr_ack),
        .ramb_rd_ack(ramb_rd_ack),
		  
        .cart_a_o(cart_a),
        .cart_d_i(cart_d),
		  .cart_rd(cart_rd),
		  .cart_pages_i(cart_pages),
		  
		  .ext_rom_a_o(ext_rom_a),
		  .ext_rom_d_i(ext_rom_d),

        .border_i(status[6]),
        .rgb_r_o(R),
        .rgb_g_o(G),
        .rgb_b_o(B),
        .hsync_n_o(hsync),
        .vsync_n_o(vsync),
        .hblank_o(hblank),
        .vblank_o(vblank),

        .audio_o(audio),
        .disk_present(disk_present),
        .disk_sector(disk_sector),
        .disk_load(disk_load),
        .disk_sector_loaded(disk_sector_loaded),
        .disk_addr(disk_addr),
        .disk_wr(disk_wr),
        .disk_flush(disk_flush),
		  .disk_flushed(disk_flushed),
        .disk_error(disk_error),
        .disk_data(disk_data),
        .disk_din(disk_din),
        .ps2_key     (ps2_key)
);
  genvar                tla_i;
  generate
    for (tla_i = 0; tla_i < TOT_DISKS; tla_i++) begin : g_TL
      track_loader_adam
        #
        (
        .drive_num      (tla_i)
        )
      track_loader_a
        (
        .clk            (clk_sys),
        .reset          (reset),
        .img_mounted    (img_mounted[tla_i]),
        .img_size       (img_size),
        .lba_fdd        (sd_lba[tla_i]),
        .sd_ack         (sd_ack[tla_i]),
        .sd_rd          (sd_rd[tla_i]),
        .sd_wr          (sd_wr[tla_i]),
        .sd_buff_addr   (sd_buff_addr),
        .sd_buff_wr     (sd_buff_wr),
        .sd_buff_dout   (sd_buff_dout),
        .sd_buff_din    (sd_buff_din[tla_i]),

        // Disk interface
        .disk_present   (disk_present[tla_i]),
        .disk_sector    (disk_sector),
        .disk_load      (disk_load[tla_i]),
        .disk_sector_loaded (disk_sector_loaded[tla_i]),
        .disk_addr          (disk_addr),
        .disk_wr            (disk_wr[tla_i]),
        .disk_flush         (disk_flush[tla_i]),
        .disk_flushed       (disk_flushed[tla_i]),
        .disk_error         (disk_error[tla_i]),
        .disk_din           (disk_din),
        .disk_data          (disk_data[tla_i])
        );
    end // block: g_TL
  endgenerate




reg hs_o, vs_o;
always @(posedge CLK_VIDEO) begin
        hs_o <= ~hsync;
        if(~hs_o & ~hsync) vs_o <= ~vsync;
end


`ifdef I2S_AUDIO
i2s i2s (
	.reset(1'b0),
	.clk(clk_sys),
	.clk_rate(32'd42_660_000),

	.sclk(I2S_BCK),
	.lrclk(I2S_LRCK),
	.sdata(I2S_DATA),

	.left_chan(DAC_L),
	.right_chan(DAC_R)
);
`ifdef I2S_AUDIO_HDMI
assign HDMI_MCLK = 0;
always @(posedge clk_sys) begin
	HDMI_BCK <= I2S_BCK;
	HDMI_LRCK <= I2S_LRCK;
	HDMI_SDATA <= I2S_DATA;
end
`endif
`endif

`ifdef SPDIF_AUDIO
spdif spdif
(
	.clk_i(clk_sys),
	.rst_i(reset),
	.clk_rate_i(32'd42_660_000),
	.spdif_o(SPDIF),
	.sample_i({DAC_R, DAC_L})
);
`endif

`ifdef USE_HDMI
i2c_master #(100_000_000) i2c_master (
	.CLK         (clk_100),
	.I2C_START   (i2c_start),
	.I2C_READ    (i2c_read),
	.I2C_ADDR    (i2c_addr),
	.I2C_SUBADDR (i2c_subaddr),
	.I2C_WDATA   (i2c_dout),
	.I2C_RDATA   (i2c_din),
	.I2C_END     (i2c_end),
	.I2C_ACK     (i2c_ack),

	//I2C bus
	.I2C_SCL     (HDMI_SCL),
	.I2C_SDA     (HDMI_SDA)
);

mist_video #(.COLOR_DEPTH(8), .SD_HCNT_WIDTH(9), .USE_BLANKS(1), .OUT_COLOR_DEPTH(8), .BIG_OSD(BIG_OSD), .VIDEO_CLEANER(1)) hdmi_video(
	.clk_sys        ( clk_25          ),
	.SPI_SCK        ( SPI_SCK          ),
	.SPI_SS3        ( SPI_SS3          ),
	.SPI_DI         ( SPI_DI           ),
	.R              ( R                ),
	.G              ( G                ),
	.B              ( B                ),
	.HBlank         ( hblank           ),
	.VBlank         ( vblank           ),
	.HSync          ( hsync            ),
	.VSync          ( vsync            ),
	.VGA_R          ( HDMI_R           ),
	.VGA_G          ( HDMI_G           ),
	.VGA_B          ( HDMI_B           ),
	.VGA_VS         ( HDMI_VS          ),
	.VGA_HS         ( HDMI_HS          ),
	.VGA_DE         ( HDMI_DE          ),
	.ce_divider     ( 3'd7             ),
	.scandoubler_disable( 1'b1         ),
	.scanlines      ( ),
	.ypbpr          ( 1'b0             ),
	.no_csync       ( 1'b1             )
	);

assign HDMI_PCLK = clk_25;

`endif

mist_video #(.COLOR_DEPTH(8), .SD_HCNT_WIDTH(9), .USE_BLANKS(1'b1), .OUT_COLOR_DEPTH(VGA_BITS), .BIG_OSD(BIG_OSD)) mist_video(
	.clk_sys        ( clk_25           ),
	.SPI_SCK        ( SPI_SCK          ),
	.SPI_SS3        ( SPI_SS3          ),
	.SPI_DI         ( SPI_DI           ),
	.R              ( R                ),
	.G              ( G                ),
	.B              ( B                ),
	.HBlank         ( hblank           ),
	.VBlank         ( vblank           ),
	.HSync          ( hsync            ),
	.VSync          ( vsync            ),
	.VGA_R          ( VGA_R            ),
	.VGA_G          ( VGA_G            ),
	.VGA_B          ( VGA_B            ),
	.VGA_VS         ( VGA_VS           ),
	.VGA_HS         ( VGA_HS           ),
	.ce_divider     ( 3'd7             ),
	.scandoubler_disable( 1'b1 ),
	.no_csync(1'b1),
	.scanlines      ( ),
	.ypbpr          ( ypbpr            )
);



dac #(14) dac_l (
   .clk_i        (clk_sys),
   .res_n_i      (1      ),
   .dac_i        (audio  ),
   .dac_o        (AUDIO_L)
);

dac #(16) dac_r (
   .clk_i        (clk_sys),
   .res_n_i      (1      ),
   .dac_i        (audio  ),
   .dac_o        (AUDIO_R)
);

//////////////// Keypad emulation (by Alan Steremberg) ///////

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];

	if(old_state != ps2_key[10]) begin
		casex(code)

			'hX16: btn_1     <= pressed; // 1
			'hX1E: btn_2     <= pressed; // 2
			'hX26: btn_3     <= pressed; // 3
			'hX25: btn_4     <= pressed; // 4
			'hX2E: btn_5     <= pressed; // 5
			'hX36: btn_6     <= pressed; // 6
			'hX3D: btn_7     <= pressed; // 7
			'hX3E: btn_8     <= pressed; // 8
			'hX46: btn_9     <= pressed; // 9
			'hX45: btn_0     <= pressed; // 0

			'hX69: btn_1     <= pressed; // 1
			'hX72: btn_2     <= pressed; // 2
			'hX7A: btn_3     <= pressed; // 3
			'hX6B: btn_4     <= pressed; // 4
			'hX73: btn_5     <= pressed; // 5
			'hX74: btn_6     <= pressed; // 6
			'hX6C: btn_7     <= pressed; // 7
			'hX75: btn_8     <= pressed; // 8
			'hX7D: btn_9     <= pressed; // 9
			'hX70: btn_0     <= pressed; // 0

			'hX7C: btn_star  <= pressed; // *
			'hX59: btn_shift <= pressed; // Right Shift
			'hX12: btn_shift <= pressed; // Left Shift
			'hX7B: btn_minus <= pressed; // - on keypad


		endcase
	end
end

reg btn_1 = 0;
reg btn_2 = 0;
reg btn_3 = 0;
reg btn_4 = 0;
reg btn_5 = 0;
reg btn_6 = 0;
reg btn_7 = 0;
reg btn_8 = 0;
reg btn_9 = 0;
reg btn_0 = 0;

reg btn_star = 0;
reg btn_shift = 0;
reg btn_minus = 0;


////////////////  Control  ////////////////////////
//	"J1,dir,dir,dir,dir,Fire 1,Fire 2,*,#,[8]0,1,2,3,4,5,6,7,8,9,Purple Tr,Blue Tr;",
//        0   1   2   3   4      5     6 7 8 9 10 11 12 


wire [0:19] keypad0 = {joya[8],joya[9],joya[10],joya[11],joya[12],joya[13],joya[14],joya[15],joya[16],joya[17],joya[6],joya[7],joya[18],joya[19],joya[3],joya[2],joya[1],joya[0],joya[4],joya[5]};
wire [0:19] keypad1 = {joyb[8],joyb[9],joyb[10],joyb[11],joyb[12],joyb[13],joyb[14],joyb[15],joyb[16],joyb[17],joyb[6],joyb[7],joyb[18],joyb[19],joyb[3],joyb[2],joyb[1],joyb[0],joyb[4],joyb[5]};
wire [0:19] keyboardemu = { btn_0, btn_1, btn_2, btn_3, btn_4, btn_5, btn_6, btn_7, btn_8, btn_9, btn_star | (btn_8&btn_shift), btn_minus | (btn_shift & btn_3), 8'b0};
wire [0:19] keypad[2] = '{keypad0|keyboardemu,keypad1|keyboardemu};

reg [3:0] ctrl1[2] = '{'0,'0};
assign {ctrl_p1[0],ctrl_p2[0],ctrl_p3[0],ctrl_p4[0]} = ctrl1[0];
assign {ctrl_p1[1],ctrl_p2[1],ctrl_p3[1],ctrl_p4[1]} = ctrl1[1];

localparam cv_key_0_c        = 4'b0011;
localparam cv_key_1_c        = 4'b1110;
localparam cv_key_2_c        = 4'b1101;
localparam cv_key_3_c        = 4'b0110;
localparam cv_key_4_c        = 4'b0001;
localparam cv_key_5_c        = 4'b1001;
localparam cv_key_6_c        = 4'b0111;
localparam cv_key_7_c        = 4'b1100;
localparam cv_key_8_c        = 4'b1000;
localparam cv_key_9_c        = 4'b1011;
localparam cv_key_asterisk_c = 4'b1010;
localparam cv_key_number_c   = 4'b0101;
localparam cv_key_pt_c       = 4'b0100;
localparam cv_key_bt_c       = 4'b0010;
localparam cv_key_none_c     = 4'b1111;

generate
        genvar i;
        for (i = 0; i <= 1; i++) begin : ctl
                always_comb begin
                        reg [3:0] ctl1, ctl2;
                        reg p61,p62;

                        ctl1 = 4'b1111;
                        ctl2 = 4'b1111;
                        p61 = 1;
                        p62 = 1;

                        if (~ctrl_p5[i]) begin
                                casex(keypad[i][0:13])
                                        'b1xxxxxxxxxxxxx: ctl1 = cv_key_0_c;
                                        'b01xxxxxxxxxxxx: ctl1 = cv_key_1_c;
                                        'b001xxxxxxxxxxx: ctl1 = cv_key_2_c;
                                        'b0001xxxxxxxxxx: ctl1 = cv_key_3_c;
                                        'b00001xxxxxxxxx: ctl1 = cv_key_4_c;
                                        'b000001xxxxxxxx: ctl1 = cv_key_5_c;
                                        'b0000001xxxxxxx: ctl1 = cv_key_6_c;
                                        'b00000001xxxxxx: ctl1 = cv_key_7_c;
                                        'b000000001xxxxx: ctl1 = cv_key_8_c;
                                        'b0000000001xxxx: ctl1 = cv_key_9_c;
                                        'b00000000001xxx: ctl1 = cv_key_asterisk_c;
                                        'b000000000001xx: ctl1 = cv_key_number_c;
                                        'b0000000000001x: ctl1 = cv_key_pt_c;
                                        'b00000000000001: ctl1 = cv_key_bt_c;
                                        'b00000000000000: ctl1 = cv_key_none_c;
                                endcase
                                p61 = ~keypad[i][19]; // button 2
                        end

                        if (~ctrl_p8[i]) begin
                                ctl2 = ~keypad[i][14:17];
                                p62 = ~keypad[i][18];  // button 1
                        end

                        ctrl1[i] = ctl1 & ctl2;
                        ctrl_p6[i] = p61 & p62;
                end
        end
endgenerate


endmodule
