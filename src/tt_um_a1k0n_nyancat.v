/*
 * Copyright (c) 2024 Andy Sloane
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_a1k0n_nyancat(
  input  wire [7:0] ui_in,    // Dedicated inputs
  output wire [7:0] uo_out,   // Dedicated outputs
  input  wire [7:0] uio_in,   // IOs: Input path
  output wire [7:0] uio_out,  // IOs: Output path
  output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
  input  wire       ena,      // always 1 when the design is powered, so you can ignore it
  input  wire       clk,      // clock
  input  wire       rst_n     // reset_n - low to reset
);

  // VGA signals
  wire hsync;
  wire vsync;
  reg [1:0] R;
  reg [1:0] G;
  reg [1:0] B;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;

  // TinyVGA PMOD
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  // Unused outputs assigned to 0.
  assign uio_out[7] = audio_pwm;
  assign uio_out[6:0] = 0;
  assign uio_oe[7] = 1;
  assign uio_oe[6:0] = 0;

  // Suppress unused signals warning
  wire _unused_ok = &{ena, ui_in, uio_in, r[2:0]};

  // ------ VIDEO ------

  reg [4:0] frame_count;
  reg [2:0] nyanframe;
  /*
  reg [6:0] line_lfsr;
  wire [6:0] line_lfsr_next = {line_lfsr[0], line_lfsr[0]^line_lfsr[6], line_lfsr[5:1]};
  */

  hvsync_generator hvsync_gen(
    .clk(clk),
    .reset(~rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .display_on(video_active),
    .hpos(pix_x),
    .vpos(pix_y)
  );
  
  wire [6:0] moving_x = pix_x + (frame_count<<2);

  reg [3:0] palette_r[0:7];
  reg [3:0] palette_g[0:7];
  reg [3:0] palette_b[0:7];
  initial begin
    $readmemh("../data/palette_r.hex", palette_r);
    $readmemh("../data/palette_g.hex", palette_g);
    $readmemh("../data/palette_b.hex", palette_b);
  end

  reg [3:0] rainbow_r[0:7];
  reg [3:0] rainbow_g[0:7];
  reg [3:0] rainbow_b[0:7];
  initial begin
    $readmemh("../data/rainbow_r.hex", rainbow_r);  
    $readmemh("../data/rainbow_g.hex", rainbow_g);
    $readmemh("../data/rainbow_b.hex", rainbow_b);
  end
  reg [2:0] nyan[0:16383];
  initial begin
    $readmemh("../data/nyan.hex", nyan);
  end

  wire bi = pix_x[0:0] ^ {1{frame_count[0]}};
  wire bj = pix_y[0:0] ^ {1{frame_count[0]}};
  wire bx = bi ^ bj;
  wire [1:0] bayer = {bx, bi};

  reg signed [5:0] cos;
  reg signed [5:0] sin;

  wire signed [5:0] cos_ = cos - (sin>>>3);
  wire signed [5:0] sin_ = sin + (cos_>>>3);

  wire [5:0] nyan_x_offset = sin^6'h20;
  wire [9:0] nyan_x = pix_x - 222 + {3'b0, nyan_x_offset};
  wire [7:0] nyan_y = (pix_y - 152) >> 3;

  wire [2:0] idx = ((nyan_x < 272) && (nyan_y < 21)) ? nyan[{nyanframe, nyan_y[4:0], nyan_x[8:3]}] : 0;
  wire rainbow_on = (idx == 0 || nyan_x > 272) && (pix_x < 300) && (nyan_y < 18);

  wire [3:0] rainbow_off = pix_y[6:3] - 5 + {3'b0, moving_x[6]};

/*
  wire star = idx == 0 && (moving_x[9:3] == line_lfsr);

  wire [5:0] r = rainbow_on ? rainbow_r[rainbow_off[3:1]] : star ? 48 : palette_r[idx];
  wire [5:0] g = rainbow_on ? rainbow_g[rainbow_off[3:1]] : star ? 48 : palette_g[idx];
  wire [5:0] b = rainbow_on ? rainbow_b[rainbow_off[3:1]] : star ? 48 : palette_b[idx];
*/
  wire [3:0] r = rainbow_on ? rainbow_r[rainbow_off[3:1]] : palette_r[idx];
  wire [3:0] g = rainbow_on ? rainbow_g[rainbow_off[3:1]] : palette_g[idx];
  wire [3:0] b = rainbow_on ? rainbow_b[rainbow_off[3:1]] : palette_b[idx];

  wire [3:0] dr = r + {2'b0, bayer};
  wire [3:0] dg = g + {2'b0, bayer};
  wire [3:0] db = b + {2'b0, bayer};

  // ------ AUDIO ------

  reg [1:0] melody_oct [0:511];
  reg [2:0] melody_note [0:511];
  reg melody_trigger [0:511];
  reg [1:0] bass_oct [0:511];
  reg [2:0] bass_note [0:511];
  reg bass_trigger [0:511];
  initial begin
    $readmemh("../data/melodyoct.hex", melody_oct);
    $readmemh("../data/melodynote.hex", melody_note);
    $readmemh("../data/melodytrigger.hex", melody_trigger);
    $readmemh("../data/bassoct.hex", bass_oct);
    $readmemh("../data/bassnote.hex", bass_note);
    $readmemh("../data/basstrigger.hex", bass_trigger);
  end

  reg [7:0] noteinctable [0:7];
  reg [7:0] noteinctable2 [0:7];
  initial begin
    $readmemh("../data/noteinc.hex", noteinctable);
    $readmemh("../data/noteinc.hex", noteinctable2);
  end

  reg [15:0] bass_pha;
  wire [2:0] cur_bass_note = bass_note[songpos];
  wire [1:0] cur_bass_oct = bass_oct[songpos];
  wire [7:0] bass_inc = noteinctable[cur_bass_note];
  wire bass_on = 
    cur_bass_oct == 3 ? bass_pha[12] :
    cur_bass_oct == 2 ? bass_pha[13] :
    cur_bass_oct == 1 ? bass_pha[14] :
    bass_pha[15];
  wire [5:0] bass_sample = bass_on ? bass_vol : 6'd0;
  reg [5:0] bass_vol;

  reg [12:0] sqr_pha;
  wire [2:0] cur_melody_note = melody_note[songpos];
  wire [1:0] cur_melody_oct = melody_oct[songpos];
  wire [7:0] sqr_inc = noteinctable2[cur_melody_note];
  wire sqr_on =
   cur_melody_oct == 2 ? sqr_pha[10] :
   cur_melody_oct == 1 ? sqr_pha[11] : sqr_pha[12];
  wire [5:0] sqr_sample = sqr_on ? sqr_vol : 6'd0;
  reg [5:0] sqr_vol;

  wire [6:0] audio_sample = sqr_sample + bass_sample;

  reg [6:0] audio_pwm_accum;
  wire [7:0] audio_pwm_accum_next = audio_pwm_accum + audio_sample;
  wire audio_pwm = audio_pwm_accum_next[7];

  reg [2:0] sample_beat_ctr;
  wire [2:0] sample_beat_ctr_next = sample_beat_ctr + 1;

  // song loops from 0..287
  reg [8:0] songpos;
  wire [8:0] songpos_next = songpos == 287 ? 0 : songpos + 1;

  task new_beat;
    begin
      songpos <= songpos_next;
      if (melody_trigger[songpos_next]) begin
        sqr_vol <= 63;
      end
      if (bass_trigger[songpos_next]) begin
        bass_vol <= 63;
      end
    end
  endtask

  task new_tick;
    begin
      if (sample_beat_ctr_next == 6) begin
        sample_beat_ctr <= 0;
        new_beat;
      end else begin
        sample_beat_ctr <= sample_beat_ctr_next;
        sqr_vol <= sqr_vol - (sqr_vol>>3);
        bass_vol <= bass_vol - (bass_vol>>2);
      end
    end
  endtask

  task new_sample;
    begin
      sqr_pha <= sqr_pha + {4'b0, sqr_inc};
      bass_pha <= bass_pha + {7'b0, bass_inc};

      if (pix_y == 0) begin
        new_tick;
      end
    end
  endtask

  always @(posedge vsync or negedge rst_n) begin
    if (~rst_n) begin
      frame_count <= 0;
      nyanframe <= 0;
      cos <= 31;
      sin <= 0;
    end else begin
      frame_count <= frame_count + 1;
      if (frame_count[1:0] == 0) begin
        if (nyanframe == 5) begin
          nyanframe <= 0;
        end else begin
          nyanframe <= nyanframe + 1;
        end
      end
      cos <= cos_;
      sin <= sin_;
    end
  end

  always @(posedge hsync or negedge rst_n) begin
    if (~rst_n) begin
      sqr_pha <= 0;
      bass_pha <= 0;
      songpos <= 287;
      sample_beat_ctr <= 0;
      sqr_vol <= 0;
      bass_vol <= 0;
    end else begin
      new_sample;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      audio_pwm_accum <= 0;
      R <= 0;
      G <= 0;
      B <= 0;
    end else begin
      audio_pwm_accum <= audio_pwm_accum_next[6:0];

      R <= video_active ? dr[3:2] : 2'b0;
      G <= video_active ? dg[3:2] : 2'b0;
      B <= video_active ? db[3:2] : 2'b0;
    end
  end

endmodule
