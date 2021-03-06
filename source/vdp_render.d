/***************************************************************************************
 *  Genesis Plus
 *  Video Display Processor (Modes 0, 1, 2, 3, 4 & 5 rendering)
 *
 *  Support for SG-1000, Master System (315-5124 & 315-5246), Game Gear & Mega Drive VDP
 *
 *  Copyright (C) 1998, 1999, 2000, 2001, 2002, 2003  Charles Mac Donald (original code)
 *  Copyright (C) 2007-2012  Eke-Eke (Genesis Plus GX)
 *
 *  Redistribution and use of this code or any derivative works are permitted
 *  provided that the following conditions are met:
 *
 *   - Redistributions may not be sold, nor may they be used in a commercial
 *     product or activity.
 *
 *   - Redistributions that are modified from the original source must include the
 *     complete source code, including the source code for all components used by a
 *     binary built from the modified sources. However, as a special exception, the
 *     source code distributed need not include anything that is normally distributed
 *     (in either source or binary form) with the major components (compiler, kernel,
 *     and so on) of the operating system on which the executable runs, unless that
 *     component itself accompanies the executable.
 *
 *   - Redistributions must reproduce the above copyright notice, this list of
 *     conditions and the following disclaimer in the documentation and/or other
 *     materials provided with the distribution.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 *  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 *  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 *  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 *  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 *  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 *  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 *  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 *  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 *  POSSIBILITY OF SUCH DAMAGE.
 *
 ****************************************************************************************/

import common;
import md_ntsc;
import sms_ntsc;


/* Output pixels type*/
alias u16 PIXEL_OUT_T;


/* Pixel priority look-up tables information */
const int LUT_MAX     = 6;
const int LUT_SIZE    = 0x10000;



/* Window & Plane A clipping */
static struct clip_t
{
  u8 left;
  u8 right;
  u8 enable;
}

clip_t[2] clip;

/* Pattern attribute (priority + palette bits) expansion table */
static const u32[] atex_table =
[
  0x00000000,
  0x10101010,
  0x20202020,
  0x30303030,
  0x40404040,
  0x50505050,
  0x60606060,
  0x70707070
];

/* fixed Master System palette for Modes 0,1,2,3 */
static const u8[16] tms_crom =
[
  0x00, 0x00, 0x08, 0x0C,
  0x10, 0x30, 0x01, 0x3C,
  0x02, 0x03, 0x05, 0x0F,
  0x04, 0x33, 0x15, 0x3F
];

/* original SG-1000 palette */
static const u16[16] tms_palette =
[
  0x0000, 0x0000, 0x2648, 0x5ECF,
  0x52BD, 0x7BBE, 0xD289, 0x475E,
  0xF2AA, 0xFBCF, 0xD60A, 0xE670,
  0x2567, 0xC2F7, 0xCE59, 0xFFFF
];

/* Cached and flipped patterns */
static u8[0x80000] bg_pattern_cache;

/* Sprite pattern name offset look-up table (Mode 5) */
static u8[0x400] name_lut;

/* Bitplane to packed pixel look-up table (Mode 4) */
static u32[0x10000] bp_lut;

/* Layer priority pixel look-up tables */
static u8[LUT_MAX][LUT_SIZE] lut;

/* Output pixel data look-up tables*/
static PIXEL_OUT_T[0x100] pixel;
static PIXEL_OUT_T[3][0x200] pixel_lut;
static PIXEL_OUT_T[0x40] pixel_lut_m4;

/* Background & Sprite line buffers */
static u8[2][0x200] linebuf;

/* Sprite limit flag */
static u8 spr_ovr;

/* Sprites parsing */
static struct object_info_t
{
  u16 ypos;
  u16 xpos;
  u16 attr;
  u16 size;
}

object_info_t[20] object_info;

/* Sprite Counter */
u8 object_count;

/* Sprite Collision Info */
u16 spr_col;

/* Function pointers */
void function(int line, int width) render_bg;
void function(int max_width) render_obj;
void function(int line) parse_satb;
void function(int index) update_bg_pattern_cache;


struct Mode5Data {
  u32 atex;
  u32 atbuf;
  u32* src;
  u32* dst;
  u32 shift;
  u32 index;
  u32 v_line;
  u32 xscroll;
  u32 yscroll;
  u8* lb;
  u8* table;
}

version(ALIGN_LONG) {

u32 READ_LONG(void *address)
{
  if (cast(u32)address & 3)
  {
version(LSB_FIRST) {  /* little endian version */
    return ( *(cast(u8 *)address) +
        (*(cast(u8 *)address+1) << 8)  +
        (*(cast(u8 *)address+2) << 16) +
        (*(cast(u8 *)address+3) << 24) );
} else {       /* big endian version */
    return ( *(cast(u8 *)address+3) +
        (*(cast(u8 *)address+2) << 8)  +
        (*(cast(u8 *)address+1) << 16) +
        (*(cast(u8 *)address)   << 24) );
}  /* LSB_FIRST */
  }
  else return *cast(u32 *)address;
}

void WRITE_LONG(void *address, u32 data)
{
  if (cast(u32)address & 3)
  {
version(LSB_FIRST) {
      *(cast(u8 *)address) =  data;
      *(cast(u8 *)address+1) = (data >> 8);
      *(cast(u8 *)address+2) = (data >> 16);
      *(cast(u8 *)address+3) = (data >> 24);
} else {
      *(cast(u8 *)address+3) =  data;
      *(cast(u8 *)address+2) = (data >> 8);
      *(cast(u8 *)address+1) = (data >> 16);
      *(cast(u8 *)address)   = (data >> 24);
} /* LSB_FIRST */
    return;
  }
  else *cast(u32 *)address = data;
}

}  /* ALIGN_LONG */


/* Draw 2-cell column (8-pixels high) */
/*
   Pattern cache base address: VHN NNNNNNNN NNYYYxxx
   with :
      x = Pattern Pixel (0-7)
      Y = Pattern Row (0-7)
      N = Pattern Number (0-2047) from pattern attribute
      H = Horizontal Flip bit from pattern attribute
      V = Vertical Flip bit from pattern attribute
*/
void GET_LSB_TILE(Mode5Data* mode_data) {
  mode_data.atex = atex_table[(mode_data.atbuf >> 13) & 7];
  mode_data.src = cast(u32 *)&bg_pattern_cache[(mode_data.atbuf & 0x00001FFF) << 6 | (mode_data.v_line)];
}
void GET_MSB_TILE(Mode5Data* mode_data) {
  mode_data.atex = atex_table[(mode_data.atbuf >> 29) & 7];
  mode_data.src = cast(u32 *)&bg_pattern_cache[(mode_data.atbuf & 0x1FFF0000) >> 10 | (mode_data.v_line)];
}

/* Draw 2-cell column (16 pixels high) */
/*
   Pattern cache base address: VHN NNNNNNNN NYYYYxxx
   with :
      x = Pattern Pixel (0-7)
      Y = Pattern Row (0-15)
      N = Pattern Number (0-1023)
      H = Horizontal Flip bit
      V = Vertical Flip bit
*/
void GET_LSB_TILE_IM2(Mode5Data* mode_data) {
  mode_data.atex = atex_table[(mode_data.atbuf >> 13) & 7];
  mode_data.src = cast(u32 *)&bg_pattern_cache[((mode_data.atbuf & 0x000003FF) << 7 | (mode_data.atbuf & 0x00001800) << 6 | (mode_data.v_line)) ^ ((mode_data.atbuf & 0x00001000) >> 6)];
}
void GET_MSB_TILE_IM2(Mode5Data* mode_data) {
  mode_data.atex = atex_table[(mode_data.atbuf >> 29) & 7];
  mode_data.src = cast(u32 *)&bg_pattern_cache[((mode_data.atbuf & 0x03FF0000) >> 9 | (mode_data.atbuf & 0x18000000) >> 10 | (mode_data.v_line)) ^ ((mode_data.atbuf & 0x10000000) >> 22)];
}
/*   
   One column = 2 tiles
   Two pattern attributes are written in VRAM as two consecutives 16-bit words:

   P = priority bit
   C = color palette (2 bits)
   V = Vertical Flip bit
   H = Horizontal Flip bit
   N = Pattern Number (11 bits)

   (MSB) PCCVHNNN NNNNNNNN (LSB) (MSB) PCCVHNNN NNNNNNNN (LSB)
              PATTERN1                      PATTERN2

   Both pattern attributes are read from VRAM as one 32-bit word:

   LIT_ENDIAN: (MSB) PCCVHNNN NNNNNNNN PCCVHNNN NNNNNNNN (LSB)
                          PATTERN2          PATTERN1

   BIG_ENDIAN: (MSB) PCCVHNNN NNNNNNNN PCCVHNNN NNNNNNNN (LSB)
                          PATTERN1          PATTERN2


   In line buffers, one pixel = one byte: (msb) 0Pppcccc (lsb)
   with:
      P = priority bit  (from pattern attribute)
      p = color palette (from pattern attribute)
      c = color data (from pattern cache)

   One pattern = 8 pixels = 8 bytes = two 32-bit writes per pattern
*/

version(ALIGN_LONG) {
version(LSB_FIRST) {
void DRAW_COLUMN(Mode5Data* mode_data) {
  GET_LSB_TILE(mode_data);
  WRITE_LONG(mode_data.dst, mode_data.src[0] | mode_data.atex);
  mode_data.dst++;
  WRITE_LONG(mode_data.dst, mode_data.src[1] | mode_data.atex);
  mode_data.dst++;
  GET_MSB_TILE(mode_data);
  WRITE_LONG(mode_data.dst, mode_data.src[0] | mode_data.atex);
  mode_data.dst++;
  WRITE_LONG(mode_data.dst, mode_data.src[1] | mode_data.atex);
  mode_data.dst++;
}
void DRAW_COLUMN_IM2(Mode5Data* mode_data) {
  GET_LSB_TILE_IM2(mode_data);
  WRITE_LONG(mode_data.dst, mode_data.src[0] | mode_data.atex);
  mode_data.dst++;
  WRITE_LONG(mode_data.dst, mode_data.src[1] | mode_data.atex);
  mode_data.dst++;
  GET_MSB_TILE_IM2(mode_data);
  WRITE_LONG(mode_data.dst, mode_data.src[0] | mode_data.atex);
  mode_data.dst++;
  WRITE_LONG(mode_data.dst, mode_data.src[1] | mode_data.atex);
  mode_data.dst++;
}
} else {
void DRAW_COLUMN(Mode5Data* mode_data) {
  GET_MSB_TILE(mode_data);
  WRITE_LONG(mode_data.dst, mode_data.src[0] | mode_data.atex);
  mode_data.dst++;
  WRITE_LONG(mode_data.dst, mode_data.src[1] | mode_data.atex);
  mode_data.dst++;
  GET_LSB_TILE(mode_data);
  WRITE_LONG(mode_data.dst, mode_data.src[0] | mode_data.atex);
  mode_data.dst++;
  WRITE_LONG(mode_data.dst, mode_data.src[1] | mode_data.atex);
  mode_data.dst++;
}
void DRAW_COLUMN_IM2(Mode5Data* mode_data) {
  GET_MSB_TILE_IM2(mode_data);
  WRITE_LONG(mode_data.dst, mode_data.src[0] | mode_data.atex);
  mode_data.dst++;
  WRITE_LONG(mode_data.dst, mode_data.src[1] | mode_data.atex);
  mode_data.dst++;
  GET_LSB_TILE_IM2(mode_data);
  WRITE_LONG(mode_data.dst, mode_data.src[0] | mode_data.atex);
  mode_data.dst++;
  WRITE_LONG(mode_data.dst, mode_data.src[1] | mode_data.atex);
  mode_data.dst++;
}
}
} else { /* NOT ALIGNED */
version(LSB_FIRST) {
void DRAW_COLUMN(Mode5Data* mode_data) {
  GET_LSB_TILE(mode_data);
  *mode_data.dst++ = (mode_data.src[0] | mode_data.atex);
  *mode_data.dst++ = (mode_data.src[1] | mode_data.atex);
  GET_MSB_TILE(mode_data);
  *mode_data.dst++ = (mode_data.src[0] | mode_data.atex);
  *mode_data.dst++ = (mode_data.src[1] | mode_data.atex);
}
void DRAW_COLUMN_IM2(Mode5Data* mode_data) {
  GET_LSB_TILE_IM2(mode_data);
  *mode_data.dst++ = (mode_data.src[0] | mode_data.atex);
  *mode_data.dst++ = (mode_data.src[1] | mode_data.atex);
  GET_MSB_TILE_IM2(mode_data);
  *mode_data.dst++ = (mode_data.src[0] | mode_data.atex);
  *mode_data.dst++ = (mode_data.src[1] | mode_data.atex);
}
} else {
void DRAW_COLUMN(Mode5Data* mode_data) {
  GET_MSB_TILE(mode_data);
  *mode_data.dst++ = (mode_data.src[0] | mode_data.atex);
  *mode_data.dst++ = (mode_data.src[1] | mode_data.atex);
  GET_LSB_TILE(mode_data);
  *mode_data.dst++ = (mode_data.src[0] | mode_data.atex);
  *mode_data.dst++ = (mode_data.src[1] | mode_data.atex);
}
void DRAW_COLUMN_IM2(Mode5Data* mode_data) {
  GET_MSB_TILE_IM2(mode_data);
  *mode_data.dst++ = (mode_data.src[0] | mode_data.atex);
  *mode_data.dst++ = (mode_data.src[1] | mode_data.atex);
  GET_LSB_TILE_IM2(mode_data);
  *mode_data.dst++ = (mode_data.src[0] | mode_data.atex);
  *mode_data.dst++ = (mode_data.src[1] | mode_data.atex);
}
}
} /* ALIGN_LONG */

/* Draw background tiles directly using priority look-up table */
/* SRC_A = layer A rendered pixel line (4 bytes = 4 pixels at once) */
/* SRC_B = layer B cached pixel line (4 bytes = 4 pixels at once) */
/* Note: cache address is always aligned so no need to use READ_LONG macro */
/* This might be faster or slower than original method, depending on  */
/* architecture (x86, PowerPC), cache size, memory access speed, etc...  */

version(LSB_FIRST) {
void DRAW_BG_TILE(Mode5Data* mode_data) {
  *mode_data.lb++ = mode_data.table[((mode_data.yscroll << 8) & 0xff00) | (mode_data.xscroll & 0xff)];
  *mode_data.lb++ = mode_data.table[(mode_data.yscroll & 0xff00) | ((mode_data.xscroll >> 8) & 0xff)];
  *mode_data.lb++ = mode_data.table[((mode_data.yscroll >> 8) & 0xff00) | ((mode_data.xscroll >> 16) & 0xff)];
  *mode_data.lb++ = mode_data.table[((mode_data.yscroll >> 16) & 0xff00) | ((mode_data.xscroll >> 24) & 0xff)];
}
} else {
void DRAW_BG_TILE(Mode5Data* mode_data) {
  *mode_data.lb++ = mode_data.table[((mode_data.yscroll >> 16) & 0xff00) | ((mode_data.xscroll >> 24) & 0xff)];
  *mode_data.lb++ = mode_data.table[((mode_data.yscroll >> 8) & 0xff00) | ((mode_data.xscroll >> 16) & 0xff)];
  *mode_data.lb++ = mode_data.table[(mode_data.yscroll & 0xff00) | ((mode_data.xscroll >> 8) & 0xff)];
  *mode_data.lb++ = mode_data.table[((mode_data.yscroll << 8) & 0xff00) | (mode_data.xscroll & 0xff)];
}
}

version(ALIGN_LONG) {
version(LSB_FIRST) {
void DRAW_BG_COLUMN(Mode5Data* mode_data) {
  GET_LSB_TILE(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  GET_MSB_TILE(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
}
void DRAW_BG_COLUMN_IM2(Mode5Data* mode_data) {
  GET_LSB_TILE_IM2(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  GET_MSB_TILE_IM2(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
}
} else {
void DRAW_BG_COLUMN(Mode5Data* mode_data) {
  GET_MSB_TILE(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  GET_LSB_TILE(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
}
void DRAW_BG_COLUMN_IM2(Mode5Data* mode_data) {
  GET_MSB_TILE_IM2(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  GET_LSB_TILE_IM2(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = READ_LONG(cast(u32 *)mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
}
}
} else { /* NOT ALIGNED */
version(LSB_FIRST) {
void DRAW_BG_COLUMN(Mode5Data* mode_data) {
  GET_LSB_TILE(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  GET_MSB_TILE(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
}
void DRAW_BG_COLUMN_IM2(Mode5Data* mode_data) {
  GET_LSB_TILE_IM2(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  GET_MSB_TILE_IM2(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
}
} else {
void DRAW_BG_COLUMN(Mode5Data* mode_data) {
  GET_MSB_TILE(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  GET_LSB_TILE(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
}
void DRAW_BG_COLUMN_IM2(Mode5Data* mode_data) {
  GET_MSB_TILE_IM2(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  GET_LSB_TILE_IM2(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[0] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
  mode_data.xscroll = *cast(u32 *)(mode_data.lb);
  mode_data.yscroll = (mode_data.src[1] | mode_data.atex);
  DRAW_BG_TILE(mode_data);
}
}
} /* ALIGN_LONG */

void DRAW_SPRITE_TILE(size_t WIDTH, u32 ATTR, u8* TABLE, u8* lb, u8* src) {
  u32 temp;
  for (size_t i=0; i<WIDTH; ++i) {
    temp = *src++;
    if (temp & 0x0f) {
      temp |= (lb[i] << 8);
      lb[i] = TABLE[temp | ATTR];
      status |= ((temp & 0x8000) >> 10);
    }
  }
}

void DRAW_SPRITE_TILE_ACCURATE(int WIDTH, u32 ATTR, u8* TABLE, int xpos, u8* lb, u8* src) {
  u32 temp;
  for (int i=0; i<WIDTH; ++i) {
    temp = *src++;
    if (temp & 0x0f) {
      temp |= (lb[i] << 8);
      lb[i] = TABLE[temp | ATTR];
      if ((temp & 0x8000) && !(status & 0x20)) {
        spr_col = (v_counter << 8) | ((xpos + i + 13) >> 1);
        status |= 0x20;
      }
    }
  }
}

void DRAW_SPRITE_TILE_ACCURATE_2X(int WIDTH, u32 ATTR, u8* TABLE, int xpos, u8* lb, u8* src) {
  u32 temp;
  for (int i=0; i<WIDTH; i+=2) {
    temp = *src++;
    if (temp & 0x0f) {
      temp |= (lb[i] << 8);
      lb[i] = TABLE[temp | ATTR];
      if ((temp & 0x8000) && !(status & 0x20)) {
        spr_col = (v_counter << 8) | ((xpos + i + 13) >> 1);
        status |= 0x20;
      }
      temp &= 0x00FF;
      temp |= (lb[i+1] << 8);
      lb[i+1] = TABLE[temp | ATTR];
      if ((temp & 0x8000) && !(status & 0x20)) {
        spr_col = (v_counter << 8) | ((xpos + i + 1 + 13) >> 1);
        status |= 0x20;
      }
    }
  }
}

/* Pixels conversion macro */
/* 4-bit color channels are either compressed to 2/3-bit or dithered to 5/6/8-bit equivalents */
/* 3:3:2 RGB */
int MAKE_PIXEL(int r, int g, int b) {
  return ((r) << 12 | ((r) >> 3) << 11 | (g) << 7 | ((g) >> 2) << 5 | (b) << 1 | (b) >> 3);
}


/*--------------------------------------------------------------------------*/
/* Sprite pattern name offset look-up table function (Mode 5)               */
/*--------------------------------------------------------------------------*/

static void make_name_lut()
{
  int vcol, vrow;
  int width, height;
  int flipx, flipy;
  int i;

  for (i = 0; i < 0x400; i += 1)
  {
    /* Sprite settings */
    vcol = i & 3;
    vrow = (i >> 2) & 3;
    height = (i >> 4) & 3;
    width  = (i >> 6) & 3;
    flipx  = (i >> 8) & 1;
    flipy  = (i >> 9) & 1;

    if ((vrow > height) || vcol > width)
    {
      /* Invalid settings (unused) */
      name_lut[i] = -1; 
    }
    else
    {
      /* Adjust column & row index if sprite is flipped */
      if(flipx) vcol = (width - vcol);
      if(flipy) vrow = (height - vrow);

      /* Pattern offset (pattern order is up->down->left->right) */
      name_lut[i] = vrow + (vcol * (height + 1));
    }
  }
}


/*--------------------------------------------------------------------------*/
/* Bitplane to packed pixel look-up table function (Mode 4)                 */
/*--------------------------------------------------------------------------*/

static void make_bp_lut()
{
  int x,i,j;
  u32 out_var;

  /* ---------------------- */
  /* Pattern color encoding */
  /* -------------------------------------------------------------------------*/
  /* 4 byteplanes are required to define one pattern line (8 pixels)          */
  /* A single pixel color is coded with 4 bits (c3 c2 c1 c0)                  */
  /* Each bit is coming from byteplane bits, as explained below:              */
  /* pixel 0: c3 = bp3 bit 7, c2 = bp2 bit 7, c1 = bp1 bit 7, c0 = bp0 bit 7  */
  /* pixel 1: c3 = bp3 bit 6, c2 = bp2 bit 6, c1 = bp1 bit 6, c0 = bp0 bit 6  */
  /* ...                                                                      */
  /* pixel 7: c3 = bp3 bit 0, c2 = bp2 bit 0, c1 = bp1 bit 0, c0 = bp0 bit 0  */
  /* -------------------------------------------------------------------------*/

  for(i = 0; i < 0x100; i++)
  for(j = 0; j < 0x100; j++)
  {
    out_var = 0;
    for(x = 0; x < 8; x++)
    {
      /* pixel line data = hh00gg00ff00ee00dd00cc00bb00aa00 (32-bit) */
      /* aa-hh = upper or lower 2-bit values of pixels 0-7 (shifted) */
      out_var |= (j & (0x80 >> x)) ? cast(u32)(8 << (x << 2)) : 0;
      out_var |= (i & (0x80 >> x)) ? cast(u32)(4 << (x << 2)) : 0;
    }

    /* i = low byte in VRAM  (bp0 or bp2) */
    /* j = high byte in VRAM (bp1 or bp3) */
version(LSB_FIRST) {
    bp_lut[(j << 8) | (i)] = out_var;
} else {
    bp_lut[(i << 8) | (j)] = out_var;
}
   }
}


/*--------------------------------------------------------------------------*/
/* Layers priority pixel look-up tables functions                           */
/*--------------------------------------------------------------------------*/

/* Input (bx):  d5-d0=color, d6=priority, d7=unused */
/* Input (ax):  d5-d0=color, d6=priority, d7=unused */
/* Output:    d5-d0=color, d6=priority, d7=zero */
static u32 make_lut_bg(u32 bx, u32 ax)
{
  int bf = (bx & 0x7F);
  int bp = (bx & 0x40);
  int b  = (bx & 0x0F);
  
  int af = (ax & 0x7F);   
  int ap = (ax & 0x40);
  int a  = (ax & 0x0F);

  int c = (ap ? (a ? af : bf) : (bp ? (b ? bf : af) : (a ? af : bf)));

  /* Strip palette & priority bits from transparent pixels */
  if((c & 0x0F) == 0x00) c &= 0x80;

  return (c);
}

/* Input (bx):  d5-d0=color, d6=priority, d7=unused */
/* Input (sx):  d5-d0=color, d6=priority, d7=unused */
/* Output:    d5-d0=color, d6=priority, d7=intensity select (0=half/1=normal) */
static u32 make_lut_bg_ste(u32 bx, u32 ax)
{
  int bf = (bx & 0x7F);
  int bp = (bx & 0x40);
  int b  = (bx & 0x0F);
  
  int af = (ax & 0x7F);   
  int ap = (ax & 0x40);
  int a  = (ax & 0x0F);

  int c = (ap ? (a ? af : bf) : (bp ? (b ? bf : af) : (a ? af : bf)));

  /* Half intensity when both pixels are low priority */
  c |= ((ap | bp) << 1);

  /* Strip palette & priority bits from transparent pixels */
  if((c & 0x0F) == 0x00) c &= 0x80;

  return (c);
}

/* Input (bx):  d5-d0=color, d6=priority/1, d7=sprite pixel marker */
/* Input (sx):  d5-d0=color, d6=priority, d7=unused */
/* Output:    d5-d0=color, d6=priority, d7=sprite pixel marker */
static u32 make_lut_obj(u32 bx, u32 sx)
{
  int c;

  int bf = (bx & 0x7F);
  int bs = (bx & 0x80);
  int sf = (sx & 0x7F);

  if((sx & 0x0F) == 0) return bx;

  c = (bs ? bf : sf);

  /* Strip palette bits from transparent pixels */
  if((c & 0x0F) == 0x00) c &= 0xC0;

  return (c | 0x80);
}


/* Input (bx):  d5-d0=color, d6=priority, d7=opaque sprite pixel marker */
/* Input (sx):  d5-d0=color, d6=priority, d7=unused */
/* Output:    d5-d0=color, d6=zero/priority, d7=opaque sprite pixel marker */
static u32 make_lut_bgobj(u32 bx, u32 sx)
{
  int c;

  int bf = (bx & 0x3F);
  int bs = (bx & 0x80);
  int bp = (bx & 0x40);
  int b  = (bx & 0x0F);
  
  int sf = (sx & 0x3F);
  int sp = (sx & 0x40);
  int s  = (sx & 0x0F);

  if(s == 0) return bx;

  /* Previous sprite has higher priority */
  if(bs) return bx;

  c = (sp ? sf : (bp ? (b ? bf : sf) : sf));

  /* Strip palette & priority bits from transparent pixels */
  if((c & 0x0F) == 0x00) c &= 0x80;

  return (c | 0x80);
}

/* Input (bx):  d5-d0=color, d6=priority, d7=intensity (half/normal) */
/* Input (sx):  d5-d0=color, d6=priority, d7=sprite marker */
/* Output:    d5-d0=color, d6=intensity (half/normal), d7=(double/invalid) */
static u32 make_lut_bgobj_ste(u32 bx, u32 sx)
{
  int c;

  int bf = (bx & 0x3F);
  int bp = (bx & 0x40);
  int b  = (bx & 0x0F);
  int bi = (bx & 0x80) >> 1;

  int sf = (sx & 0x3F);
  int sp = (sx & 0x40);
  int s  = (sx & 0x0F);
  int si = sp | bi;

  if(sp)
  {
    if(s)
    {
      if((sf & 0x3E) == 0x3E)
      {
        if(sf & 1)
        {
          c = (bf | 0x00);
        }
        else
        {
          c = (bx & 0x80) ? (bf | 0x80) : (bf | 0x40);
        }
      }
      else
      {
        if(sf == 0x0E || sf == 0x1E || sf == 0x2E)
        {
          c = (sf | 0x40);
        }
        else
        {
          c = (sf | si);
        }
      }
    }
    else
    {
      c = (bf | bi);
    }
  }
  else
  {
    if(bp)
    {
      if(b)
      {
        c = (bf | bi);
      }
      else
      {
        if(s)
        {
          if((sf & 0x3E) == 0x3E)
          {
            if(sf & 1)
            {
              c = (bf | 0x00);
            }
            else
            {
              c = (bx & 0x80) ? (bf | 0x80) : (bf | 0x40);
            }
          }
          else
          {
            if(sf == 0x0E || sf == 0x1E || sf == 0x2E)
            {
              c = (sf | 0x40);
            }
            else
            {
              c = (sf | si);
            }
          }
        }
        else
        {
          c = (bf | bi);
        }
      }
    }
    else
    {
      if(s)
      {
        if((sf & 0x3E) == 0x3E)
        {
          if(sf & 1)
          {
            c = (bf | 0x00);
          }
          else
          {
            c = (bx & 0x80) ? (bf | 0x80) : (bf | 0x40);
          }
        }
        else
        {
          if(sf == 0x0E || sf == 0x1E || sf == 0x2E)
          {
            c = (sf | 0x40);
          }
          else
          {
            c = (sf | si);
          }
        }
      }
      else
      {          
        c = (bf | bi);
      }
    }
  }

  if((c & 0x0f) == 0x00) c &= 0xC0;

  return (c);
}

/* Input (bx):  d3-d0=color, d4=palette, d5=priority, d6=zero, d7=sprite pixel marker */
/* Input (sx):  d3-d0=color, d7-d4=zero */
/* Output:      d3-d0=color, d4=palette, d5=zero/priority, d6=zero, d7=sprite pixel marker */
static u32 make_lut_bgobj_m4(u32 bx, u32 sx)
{
  int c;
  
  int bf = (bx & 0x3F);
  int bs = (bx & 0x80);
  int bp = (bx & 0x20);
  int b  = (bx & 0x0F);

  int s  = (sx & 0x0F);
  int sf = (s | 0x10); /* force palette bit */

  /* Transparent sprite pixel */
  if(s == 0) return bx;

  /* Previous sprite has higher priority */
  if(bs) return bx;

  /* note: priority bit is always 0 for Modes 0,1,2,3 */
  c = (bp ? (b ? bf : sf) : sf);

  return (c | 0x80);
}


/*--------------------------------------------------------------------------*/
/* Pixel layer merging function                                             */
/*--------------------------------------------------------------------------*/

void merge(u8 *srca, u8 *srcb, u8 *dst, u8 *table, int width)
{
  do
  {
    *dst++ = table[(*srcb++ << 8) | (*srca++)];
  }
  while (--width);
}


/*--------------------------------------------------------------------------*/
/* Pixel color lookup tables initialization                                 */
/*--------------------------------------------------------------------------*/

static void palette_init()
{
  int r, g, b, i;

  /************************************************/
  /* Each R,G,B color channel is 4-bit with a     */
  /* total of 15 different intensity levels.      */
  /*                                              */
  /* Color intensity depends on the mode:         */
  /*                                              */
  /*    normal   : xxx0     (0-14)                */
  /*    shadow   : 0xxx     (0-7)                 */
  /*    highlight: 1xxx - 1 (7-14)                */
  /*    mode4    : xx00 ?   (0-12)                */
  /*    GG mode  : xxxx     (0-16)                */
  /*                                              */
  /* with x = original CRAM value (2, 3 or 4-bit) */
  /************************************************/

  /* Initialize Mode 5 pixel color look-up tables */
  for (i = 0; i < 0x200; i++)
  {
    /* CRAM 9-bit value (BBBGGGRRR) */
    r = (i >> 0) & 7;
    g = (i >> 3) & 7;
    b = (i >> 6) & 7;

    /* Convert to output pixel format */
    pixel_lut[0][i] = MAKE_PIXEL(r,g,b);
    pixel_lut[1][i] = MAKE_PIXEL(r<<1,g<<1,b<<1);
    pixel_lut[2][i] = MAKE_PIXEL(r+7,g+7,b+7);
  }

  /* Initialize Mode 4 pixel color look-up table */
  for (i = 0; i < 0x40; i++)
  {
    /* CRAM 6-bit value (000BBGGRR) */
    r = (i >> 0) & 3;
    g = (i >> 2) & 3;
    b = (i >> 4) & 3;

    /* Convert to output pixel format (expand to 4-bit for brighter colors ?) */
    pixel_lut_m4[i] = MAKE_PIXEL(r << 2,g << 2,b<< 2);
  }
}


/*--------------------------------------------------------------------------*/
/* Color palette update functions                                           */
/*--------------------------------------------------------------------------*/

void color_update_m4(int index, u32 data)
{
  switch (system_hw)
  {
    case SYSTEM_GG:
    {
      /* CRAM value (BBBBGGGGRRRR) */
      int r = (data >> 0) & 0x0F;
      int g = (data >> 4) & 0x0F;
      int b = (data >> 8) & 0x0F;

      /* Convert to output pixel */
      data = MAKE_PIXEL(r,g,b);
      break;
    }

    case SYSTEM_SG:
    {
      /* Fixed TMS9918 palette */
      if (index & 0x0F)
      {
        /* Colors 1-15 */
        data = tms_palette[index & 0x0F];
      }
      else
      {
        /* Backdrop color */
        data = tms_palette[reg[7] & 0x0F];
      }
      break;
    }

    default:
    {
      /* Test M4 bit */
      if (!(reg[0] & 0x04))
      {
        if (system_hw & SYSTEM_MD)
        {
          /* Invalid Mode (black screen) */
          data = 0x00;
        }
        else if (system_hw != SYSTEM_GGMS)
        {
          /* Fixed CRAM palette */
          if (index & 0x0F)
          {
            /* Colors 1-15 */
            data = tms_crom[index & 0x0F];
          }
          else
          {
            /* Backdrop color */
            data = tms_crom[reg[7] & 0x0F];
          }
        }
      }

      /* Mode 4 palette */
      data = pixel_lut_m4[data & 0x3F];
      break;
    }
  }


  /* Input pixel: x0xiiiii (normal) or 01000000 (backdrop) */
  if (reg[0] & 0x04)
  {
    /* Mode 4 */
    pixel[0x00 | index] = data;
    pixel[0x20 | index] = data;
    pixel[0x80 | index] = data;
    pixel[0xA0 | index] = data;
  }
  else
  {
    /* TMS9918 modes (palette bit forced to 1 because Game Gear uses CRAM palette #1) */
    if ((index == 0x40) || (index == (0x10 | (reg[7] & 0x0F))))
    {
      /* Update backdrop color */
      pixel[0x40] = data;

      /* Update transparent color */
      pixel[0x10] = data;
      pixel[0x30] = data;
      pixel[0x90] = data;
      pixel[0xB0] = data;
    }

    if (index & 0x0F)
    {
      /* update non-transparent colors */
      pixel[0x00 | index] = data;
      pixel[0x20 | index] = data;
      pixel[0x80 | index] = data;
      pixel[0xA0 | index] = data;
    }
  }
}

void color_update_m5(int index, u32 data)
{
  /* Palette Mode */
  if (!(reg[0] & 0x04))
  {
    /* Color value is limited to 00X00X00X */
    data &= 0x49;
  }

  if(reg[12] & 0x08)
  {
    /* Mode 5 (Shadow/Normal/Highlight) */
    pixel[0x00 | index] = pixel_lut[0][data];
    pixel[0x40 | index] = pixel_lut[1][data];
    pixel[0x80 | index] = pixel_lut[2][data];
  }
  else
  {
    /* Mode 5 (Normal) */
    data = pixel_lut[1][data];

    /* Input pixel: xxiiiiii */
    pixel[0x00 | index] = data;
    pixel[0x40 | index] = data;
    pixel[0x80 | index] = data;
  }
}


/*--------------------------------------------------------------------------*/
/* Background layers rendering functions                                    */
/*--------------------------------------------------------------------------*/

/* Graphics I */
void render_bg_m0(int line, int width)
{
  u8 color, pattern;
  u16 name;

  u8 *lb = &linebuf[0][0x20];
  u8 *nt = &vram[((reg[2] << 10) & 0x3C00) + ((line & 0xF8) << 2)];
  u8 *ct = &vram[((reg[3] <<  6) & 0x3FC0)];
  u8 *pg = &vram[((reg[4] << 11) & 0x3800) + (line & 7)];

  /* 32 x 8 pixels */
  width = 32;

  do
  {
    name = *nt++;
    color = ct[name >> 3];
    pattern = pg[name << 3];

    *lb++ = 0x10 | ((color >> (((pattern >> 7) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 6) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 5) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 4) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 3) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 2) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 1) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 0) & 1) << 2)) & 0x0F);
  }
  while (--width);
}

/* Text */
void render_bg_m1(int line, int width)
{
  u8 pattern;
  u8 color = reg[7];

  u8 *lb = &linebuf[0][0x20];
  u8 *nt = &vram[((reg[2] << 10) & 0x3C00) + ((line >> 3) * 40)];
  u8 *pg = &vram[((reg[4] << 11) & 0x3800) + (line & 7)];

  /* Left border (8 pixels) */
  lb[0 .. 8] = 0x40;
  lb += 8;

  /* 40 x 6 pixels */
  width = 40;

  do
  {
    pattern = pg[*nt++];

    *lb++ = 0x10 | ((color >> (((pattern >> 7) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 6) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 5) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 4) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 3) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 2) & 1) << 2)) & 0x0F);
  }
  while (--width);

  /* Right borders (8 pixels) */
  lb[0 .. 8] = 0x40;
}

/* Text + extended PG */
void render_bg_m1x(int line, int width)
{
  u8 pattern;
  u8 *pg;

  u8 color = reg[7];

  u8 *lb = &linebuf[0][0x20];
  u8 *nt = &vram[((reg[2] << 10) & 0x3C00) + ((line >> 3) * 40)];

  u16 pg_mask = ~0x3800 ^ (reg[4] << 11);

  /* Unused bits used as a mask on TMS9918 & 315-5124 VDP only */
  if (system_hw > SYSTEM_SMS)
  {
    pg_mask |= 0x1800;
  }

  pg = &vram[((0x2000 + ((line & 0xC0) << 5)) & pg_mask) + (line & 7)];

  /* Left border (8 pixels) */
  lb[0 .. 8] = 0x40;
  lb += 8;

  /* 40 x 6 pixels */
  width = 40;

  do
  {
    pattern = pg[*nt++ << 3];

    *lb++ = 0x10 | ((color >> (((pattern >> 7) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 6) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 5) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 4) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 3) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 2) & 1) << 2)) & 0x0F);
  }
  while (--width);

  /* Right borders (8 pixels) */
  lb[0 .. 8] = 0x40;
}

/* Graphics II */
void render_bg_m2(int line, int width)
{
  u8 color, pattern;
  u16 name;
  u8* ct, pg;

  u8* lb = &linebuf[0][0x20];
  u8* nt = &vram[((reg[2] << 10) & 0x3C00) + ((line & 0xF8) << 2)];

  u16 ct_mask = ~0x3FC0 ^ (reg[3] << 6);
  u16 pg_mask = ~0x3800 ^ (reg[4] << 11);

  /* Unused bits used as a mask on TMS9918 & 315-5124 VDP only */
  if (system_hw > SYSTEM_SMS)
  {
    ct_mask |= 0x1FC0;
    pg_mask |= 0x1800;
  }

  ct = &vram[((0x2000 + ((line & 0xC0) << 5)) & ct_mask) + (line & 7)];
  pg = &vram[((0x2000 + ((line & 0xC0) << 5)) & pg_mask) + (line & 7)];

  /* 32 x 8 pixels */
  width = 32;

  do
  {
    name = *nt++ << 3 ;
    color = ct[name & ct_mask];
    pattern = pg[name];

    *lb++ = 0x10 | ((color >> (((pattern >> 7) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 6) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 5) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 4) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 3) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 2) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 1) & 1) << 2)) & 0x0F);
    *lb++ = 0x10 | ((color >> (((pattern >> 0) & 1) << 2)) & 0x0F);
  }
  while (--width);
}

/* Multicolor */
void render_bg_m3(int line, int width)
{
  u8 color;
  u16 name;

  u8 *lb = &linebuf[0][0x20];
  u8 *nt = &vram[((reg[2] << 10) & 0x3C00) + ((line & 0xF8) << 2)];
  u8 *pg = &vram[((reg[4] << 11) & 0x3800) + ((line >> 2) & 7)];

  /* 32 x 8 pixels */
  width = 32;

  do
  {
    name = *nt++;
    color = pg[name << 3];
    
    *lb++ = 0x10 | ((color >> 4) & 0x0F);
    *lb++ = 0x10 | ((color >> 4) & 0x0F);
    *lb++ = 0x10 | ((color >> 4) & 0x0F);
    *lb++ = 0x10 | ((color >> 4) & 0x0F);
    *lb++ = 0x10 | ((color >> 0) & 0x0F);
    *lb++ = 0x10 | ((color >> 0) & 0x0F);
    *lb++ = 0x10 | ((color >> 0) & 0x0F);
    *lb++ = 0x10 | ((color >> 0) & 0x0F);
  }
  while (--width);
}

/* Multicolor + extended PG */
void render_bg_m3x(int line, int width)
{
  u8 color;
  u16 name;
  u8 *pg;

  u8 *lb = &linebuf[0][0x20];
  u8 *nt = &vram[((reg[2] << 10) & 0x3C00) + ((line & 0xF8) << 2)];

  u16 pg_mask = ~0x3800 ^ (reg[4] << 11);

  /* Unused bits used as a mask on TMS9918 & 315-5124 VDP only */
  if (system_hw > SYSTEM_SMS)
  {
    pg_mask |= 0x1800;
  }

  pg = &vram[((0x2000 + ((line & 0xC0) << 5)) & pg_mask) + ((line >> 2) & 7)];

  /* 32 x 8 pixels */
  width = 32;

  do
  {
    name = *nt++;
    color = pg[name << 3];
    
    *lb++ = 0x10 | ((color >> 4) & 0x0F);
    *lb++ = 0x10 | ((color >> 4) & 0x0F);
    *lb++ = 0x10 | ((color >> 4) & 0x0F);
    *lb++ = 0x10 | ((color >> 4) & 0x0F);
    *lb++ = 0x10 | ((color >> 0) & 0x0F);
    *lb++ = 0x10 | ((color >> 0) & 0x0F);
    *lb++ = 0x10 | ((color >> 0) & 0x0F);
    *lb++ = 0x10 | ((color >> 0) & 0x0F);
  }
  while (--width);
}

/* Invalid (2+3/1+2+3) */
void render_bg_inv(int line, int width)
{
  assert(line == line);
  u8 color = reg[7];

  u8 *lb = &linebuf[0][0x20];

  /* Left border (8 pixels) */
  lb[0 .. 8] = 0x40;
  lb += 8;

  /* 40 x 6 pixels */
  width = 40;

  do
  {
    *lb++ = 0x10 | ((color >> 4) & 0x0F);
    *lb++ = 0x10 | ((color >> 4) & 0x0F);
    *lb++ = 0x10 | ((color >> 4) & 0x0F);
    *lb++ = 0x10 | ((color >> 4) & 0x0F);
    *lb++ = 0x10 | ((color >> 0) & 0x0F);
    *lb++ = 0x10 | ((color >> 0) & 0x0F);
  }
  while (--width);

  /* Right borders (8 pixels) */
  lb[0 .. 8] = 0x40;
}

/* Mode 4 */
void render_bg_m4(int line, int width)
{
  int column;
  u16* nt;
  u32 attr, atex;
  u32* src;
  
  /* Horizontal scrolling */
  int index = ((reg[0] & 0x40) && (line < 0x10)) ? 0x100 : reg[0x08];
  int shift = index & 7;

  /* Background line buffer */
  u32 *dst = cast(u32 *)&linebuf[0][0x20 + shift];

  /* Vertical scrolling */
  int v_line = line + vscroll;

  /* Pattern name table mask */
  u16 nt_mask = ~0x3C00 ^ (reg[2] << 10);

  /* Unused bits used as a mask on TMS9918 & 315-5124 VDP only */
  if (system_hw > SYSTEM_SMS)
  {
    nt_mask |= 0x400;
  }

  /* Test for extended modes (Master System II & Game gear VDP only) */
  if (bitmap.viewport.h > 192)
  {
    /* Vertical scroll mask */
    v_line = v_line % 256;
    
    /* Pattern name Table */
    nt = cast(u16 *)&vram[(0x3700 & nt_mask) + ((v_line >> 3) << 6)];
  }
  else
  {
    /* Vertical scroll mask */
    v_line = v_line % 224;

    /* Pattern name Table */
    nt = cast(u16 *)&vram[(0x3800 + ((v_line >> 3) << 6)) & nt_mask];
  }

  /* Pattern row index */
  v_line = (v_line & 7) << 3;

  /* Tile column index */
  index = (0x100 - index) >> 3;

  /* Clip left-most column if required */
  if (shift)
  {
    memset(&linebuf[0][0x20], 0, shift);
    index++;
  }

  /* Number of tiles to draw */
  width >>= 3;

  /* Draw tiles */
  for(column = 0; column < width; column++, index++)
  {
    /* Stop vertical scrolling for rightmost eight tiles */
    if((column == 24) && (reg[0] & 0x80))
    {
      /* Clear Pattern name table start address */
      if (bitmap.viewport.h > 192)
      {
        nt = cast(u16 *)&vram[(0x3700 & nt_mask) + ((line >> 3) << 6)];
      }
      else
      {
        nt = cast(u16 *)&vram[(0x3800 + ((line >> 3) << 6)) & nt_mask];
      }

      /* Clear Pattern row index */
      v_line = (line & 7) << 3;
    }

    /* Read name table attribute word */
    attr = nt[index % width];
version(LSB_FIRST) {
    attr = (((attr & 0xFF) << 8) | ((attr & 0xFF00) >> 8));
}

    /* Expand priority and palette bits */
    atex = atex_table[(attr >> 11) & 3];

    /* Cached pattern data line (4 bytes = 4 pixels at once) */
    src = cast(u32 *)&bg_pattern_cache[((attr & 0x7FF) << 6) | (v_line)];

    /* Copy left & right half, adding the attribute bits in */
version(ALIGN_DWORD) {
    WRITE_LONG(dst, src[0] | atex);
    dst++;
    WRITE_LONG(dst, src[1] | atex);
    dst++;
} else {
    *dst++ = (src[0] | atex);
    *dst++ = (src[1] | atex);
}
  }
}

/* Mode 5 */
void render_bg_m5(int line, int width)
{
  int column, start, end;
  Mode5Data mode_data;
  u32* nt;

  /* Scroll Planes common data */
  mode_data.xscroll      = *cast(u32 *)&vram[hscb + ((line & hscroll_mask) << 2)];
  mode_data.yscroll      = *cast(u32 *)&vsram[0];
  u32 pf_col_mask  = playfield_col_mask;
  u32 pf_row_mask  = playfield_row_mask;
  u32 pf_shift     = playfield_shift;

  /* Layer priority table */
  mode_data.table = lut[(reg[12] & 8) >> 2];

  /* Window vertical range (cell 0-31) */
  int a = (reg[18] & 0x1F) << 3;

  /* Window position (0=top, 1=bottom) */
  int w = (reg[18] >> 7) & 1;

  /* Test against current line */
  if (w == (line >= a))
  {
    /* Window takes up entire line */
    a = 0;
    w = 1;
  }
  else
  {
    /* Window and Plane A share the line */
    a = clip[0].enable;
    w = clip[1].enable;
  }

  /* Number of columns to draw */
  width >>= 4;

  /* Plane A */
  if (a)
  {
    /* Plane A width */
    start = clip[0].left;
    end   = clip[0].right;

    /* Plane A scroll */
version(LSB_FIRST) {
    mode_data.shift  = (mode_data.xscroll & 0x0F);
    mode_data.index  = pf_col_mask + start + 1 - ((mode_data.xscroll >> 4) & pf_col_mask);
    mode_data.v_line = (line + mode_data.yscroll) & pf_row_mask;
} else {
    mode_data.shift  = (mode_data.xscroll >> 16) & 0x0F;
    mode_data.index  = pf_col_mask + start + 1 - ((mode_data.xscroll >> 20) & pf_col_mask);
    mode_data.v_line = (line + (mode_data.yscroll >> 16)) & pf_row_mask;
}

    /* Background line buffer */
    mode_data.dst = cast(u32 *)&linebuf[0][0x20 + (start << 4) + mode_data.shift];

    /* Plane A name table */
    nt = cast(u32 *)&vram[ntab + (((mode_data.v_line >> 3) << pf_shift) & 0x1FC0)];

    /* Pattern row index */
    mode_data.v_line = (mode_data.v_line & 7) << 3;

    if(mode_data.shift)
    {
      /* Left-most column is partially shown */
      mode_data.dst -= 4;

      /* Window bug */
      if (start)
      {
        mode_data.atbuf = nt[mode_data.index & pf_col_mask];
      }
      else
      {
        mode_data.atbuf = nt[(mode_data.index-1) & pf_col_mask];
      }

      DRAW_COLUMN(&mode_data);
    }

    for(column = start; column < end; column++, mode_data.index++)
    {
      mode_data.atbuf = nt[mode_data.index & pf_col_mask];
      DRAW_COLUMN(&mode_data);
    }

    /* Window width */
    start = clip[1].left;
    end   = clip[1].right;
  }
  else
  {
    /* Window width */
    start = 0;
    end = width;
  }

  /* Window Plane */
  if (w)
  {
    /* Background line buffer */
    mode_data.dst = cast(u32 *)&linebuf[0][0x20 + (start << 4)];

    /* Window name table */
    nt = cast(u32 *)&vram[ntwb | ((line >> 3) << (6 + (reg[12] & 1)))];

    /* Pattern row index */
    mode_data.v_line = (line & 7) << 3;

    for(column = start; column < end; column++)
    {
      mode_data.atbuf = nt[column];
      DRAW_COLUMN(&mode_data);
    }
  }

  /* Plane B scroll */
version(LSB_FIRST) {
  mode_data.shift  = (mode_data.xscroll >> 16) & 0x0F;
  mode_data.index  = pf_col_mask + 1 - ((mode_data.xscroll >> 20) & pf_col_mask);
  mode_data.v_line = (line + (mode_data.yscroll >> 16)) & pf_row_mask;
} else {
  mode_data.shift  = (mode_data.xscroll & 0x0F);
  mode_data.index  = pf_col_mask + 1 - ((mode_data.xscroll >> 4) & pf_col_mask);
  mode_data.v_line = (line + mode_data.yscroll) & pf_row_mask;
}

  /* Plane B name table */
  nt = cast(u32 *)&vram[ntbb + (((mode_data.v_line >> 3) << pf_shift) & 0x1FC0)];
  
  /* Pattern row index */
  mode_data.v_line = (mode_data.v_line & 7) << 3;

  /* Background line buffer */
  mode_data.lb = &linebuf[0][0x20];

  if(mode_data.shift)
  {
    /* Left-most column is partially shown */
    mode_data.lb -= (0x10 - mode_data.shift);

    mode_data.atbuf = nt[(mode_data.index-1) & pf_col_mask];
    DRAW_BG_COLUMN(&mode_data);
  }
 
  for(column = 0; column < width; column++, mode_data.index++)
  {
    mode_data.atbuf = nt[mode_data.index & pf_col_mask];
    DRAW_BG_COLUMN(&mode_data);
  }
}

void render_bg_m5_vs(int line, int width)
{
  int column, start, end;
  Mode5Data mode_data;
  u32 shift, index;
  u32* nt;

  /* Scroll Planes common data */
  mode_data.xscroll      = *cast(u32 *)&vram[hscb + ((line & hscroll_mask) << 2)];
  mode_data.yscroll      = 0;
  u32 pf_col_mask  = playfield_col_mask;
  u32 pf_row_mask  = playfield_row_mask;
  u32 pf_shift     = playfield_shift;
  u32 *vs          = cast(u32 *)&vsram[0];

  /* Layer priority table */
  mode_data.table = lut[(reg[12] & 8) >> 2];

  /* Window vertical range (cell 0-31) */
  int a = (reg[18] & 0x1F) << 3;

  /* Window position (0=top, 1=bottom) */
  int w = (reg[18] >> 7) & 1;

  /* Test against current line */
  if (w == (line >= a))
  {
    /* Window takes up entire line */
    a = 0;
    w = 1;
  }
  else
  {
    /* Window and Plane A share the line */
    a = clip[0].enable;
    w = clip[1].enable;
  }

  /* Left-most column vertical scrolling when partially shown horizontally */
  /* Same value for both planes, only in 40-cell mode, verified on PAL MD2 */
  /* See Gynoug, Cutie Suzuki no Ringside Angel, Formula One, Kawasaki Superbike Challenge */
  if (reg[12] & 1)
  {
    mode_data.yscroll = vs[19] & (vs[19] >> 16);
  }

  /* Number of columns to draw */
  width >>= 4;

  /* Plane A*/
  if (a)
  {
    /* Plane A width */
    start = clip[0].left;
    end   = clip[0].right;

    /* Plane A horizontal scroll */
version(LSB_FIRST) {
    shift = (mode_data.xscroll & 0x0F);
    index = pf_col_mask + start + 1 - ((mode_data.xscroll >> 4) & pf_col_mask);
} else {
    shift = (mode_data.xscroll >> 16) & 0x0F;
    index = pf_col_mask + start + 1 - ((mode_data.xscroll >> 20) & pf_col_mask);
}

    /* Background line buffer */
    mode_data.dst = cast(u32 *)&linebuf[0][0x20 + (start << 4) + shift];

    if(shift)
    {
      /* Left-most column is partially shown */
      mode_data.dst -= 4;

      /* Plane A vertical scroll */
      mode_data.v_line = (line + mode_data.yscroll) & pf_row_mask;

      /* Plane A name table */
      nt = cast(u32 *)&vram[ntab + (((mode_data.v_line >> 3) << pf_shift) & 0x1FC0)];

      /* Pattern row index */
      mode_data.v_line = (mode_data.v_line & 7) << 3;

      /* Window bug */
      if (start)
      {
        mode_data.atbuf = nt[index & pf_col_mask];
      }
      else
      {
        mode_data.atbuf = nt[(index-1) & pf_col_mask];
      }

      DRAW_COLUMN(&mode_data);
    }

    for(column = start; column < end; column++, index++)
    {
      /* Plane A vertical scroll */
version(LSB_FIRST) {
      mode_data.v_line = (line + vs[column]) & pf_row_mask;
} else {
      mode_data.v_line = (line + (vs[column] >> 16)) & pf_row_mask;
}

      /* Plane A name table */
      nt = cast(u32 *)&vram[ntab + (((mode_data.v_line >> 3) << pf_shift) & 0x1FC0)];

      /* Pattern row index */
      mode_data.v_line = (mode_data.v_line & 7) << 3;

      mode_data.atbuf = nt[index & pf_col_mask];
      DRAW_COLUMN(&mode_data);
    }

    /* Window width */
    start = clip[1].left;
    end   = clip[1].right;
  }
  else
  {
    /* Window width */
    start = 0;
    end   = width;
  }

  /* Window Plane */
  if (w)
  {
    /* Background line buffer */
    mode_data.dst = cast(u32 *)&linebuf[0][0x20 + (start << 4)];

    /* Window name table */
    nt = cast(u32 *)&vram[ntwb | ((line >> 3) << (6 + (reg[12] & 1)))];

    /* Pattern row index */
    mode_data.v_line = (line & 7) << 3;

    for(column = start; column < end; column++)
    {
      mode_data.atbuf = nt[column];
      DRAW_COLUMN(&mode_data);
    }
  }

  /* Plane B horizontal scroll */
version(LSB_FIRST) {
  shift = (mode_data.xscroll >> 16) & 0x0F;
  index = pf_col_mask + 1 - ((mode_data.xscroll >> 20) & pf_col_mask);
} else {
  shift = (mode_data.xscroll & 0x0F);
  index = pf_col_mask + 1 - ((mode_data.xscroll >> 4) & pf_col_mask);
}

  /* Background line buffer */
  mode_data.lb = &linebuf[0][0x20];

  if(shift)
  {
    /* Left-most column is partially shown */
    mode_data.lb -= (0x10 - shift);

    /* Plane B vertical scroll */
    mode_data.v_line = (line + mode_data.yscroll) & pf_row_mask;

    /* Plane B name table */
    nt = cast(u32 *)&vram[ntbb + (((mode_data.v_line >> 3) << pf_shift) & 0x1FC0)];

    /* Pattern row index */
    mode_data.v_line = (mode_data.v_line & 7) << 3;

    mode_data.atbuf = nt[(index-1) & pf_col_mask];
    DRAW_BG_COLUMN(&mode_data);
  }

  for(column = 0; column < width; column++, index++)
  {
    /* Plane B vertical scroll */
version(LSB_FIRST) {
    mode_data.v_line = (line + (vs[column] >> 16)) & pf_row_mask;
} else {
    mode_data.v_line = (line + vs[column]) & pf_row_mask;
}

    /* Plane B name table */
    nt = cast(u32 *)&vram[ntbb + (((mode_data.v_line >> 3) << pf_shift) & 0x1FC0)];

    /* Pattern row index */
    mode_data.v_line = (mode_data.v_line & 7) << 3;

    mode_data.atbuf = nt[index & pf_col_mask];
    DRAW_BG_COLUMN(&mode_data);
  }
}

void render_bg_m5_im2(int line, int width)
{
  int column, start, end;
  Mode5Data mode_data;
  u32 shift, index;
  u32* nt;

  /* Scroll Planes common data */
  int odd = odd_frame;
  mode_data.xscroll      = *cast(u32 *)&vram[hscb + ((line & hscroll_mask) << 2)];
  mode_data.yscroll      = *cast(u32 *)&vsram[0];
  u32 pf_col_mask  = playfield_col_mask;
  u32 pf_row_mask  = playfield_row_mask;
  u32 pf_shift     = playfield_shift;

  /* Layer priority table */
  mode_data.table = lut[(reg[12] & 8) >> 2];

  /* Window vertical range (cell 0-31) */
  int a = (reg[18] & 0x1F) << 3;
  
  /* Window position (0=top, 1=bottom) */
  int w = (reg[18] >> 7) & 1;

  /* Test against current line */
  if (w == (line >= a))
  {
    /* Window takes up entire line */
    a = 0;
    w = 1;
  }
  else
  {
    /* Window and Plane A share the line */
    a = clip[0].enable;
    w = clip[1].enable;
  }

  /* Number of columns to draw */
  width >>= 4;

  /* Plane A */
  if (a)
  {
    /* Plane A width */
    start = clip[0].left;
    end   = clip[0].right;

    /* Plane A scroll */
version(LSB_FIRST) {
    shift  = (mode_data.xscroll & 0x0F);
    index  = pf_col_mask + start + 1 - ((mode_data.xscroll >> 4) & pf_col_mask);
    mode_data.v_line = (line + (mode_data.yscroll >> 1)) & pf_row_mask;
} else {
    shift  = (mode_data.xscroll >> 16) & 0x0F;
    index  = pf_col_mask + start + 1 - ((mode_data.xscroll >> 20) & pf_col_mask);
    mode_data.v_line = (line + (mode_data.yscroll >> 17)) & pf_row_mask;
}

    /* Background line buffer */
    mode_data.dst = cast(u32 *)&linebuf[0][0x20 + (start << 4) + shift];

    /* Plane A name table */
    nt = cast(u32 *)&vram[ntab + (((mode_data.v_line >> 3) << pf_shift) & 0x1FC0)];

    /* Pattern row index */
    mode_data.v_line = (((mode_data.v_line & 7) << 1) | odd) << 3;

    if(shift)
    {
      /* Left-most column is partially shown */
      mode_data.dst -= 4;

      /* Window bug */
      if (start)
      {
        mode_data.atbuf = nt[index & pf_col_mask];
      }
      else
      {
        mode_data.atbuf = nt[(index-1) & pf_col_mask];
      }

      DRAW_COLUMN_IM2(&mode_data);
    }

    for(column = start; column < end; column++, index++)
    {
      mode_data.atbuf = nt[index & pf_col_mask];
      DRAW_COLUMN_IM2(&mode_data);
    }

    /* Window width */
    start = clip[1].left;
    end   = clip[1].right;
  }
  else
  {
    /* Window width */
    start = 0;
    end   = width;
  }

  /* Window Plane */
  if (w)
  {
    /* Background line buffer */
    mode_data.dst = cast(u32 *)&linebuf[0][0x20 + (start << 4)];

    /* Window name table */
    nt = cast(u32 *)&vram[ntwb | ((line >> 3) << (6 + (reg[12] & 1)))];

    /* Pattern row index */
    mode_data.v_line = ((line & 7) << 1 | odd) << 3;

    for(column = start; column < end; column++)
    {
      mode_data.atbuf = nt[column];
      DRAW_COLUMN_IM2(&mode_data);
    }
  }

  /* Plane B scroll */
version(LSB_FIRST) {
  shift  = (mode_data.xscroll >> 16) & 0x0F;
  index  = pf_col_mask + 1 - ((mode_data.xscroll >> 20) & pf_col_mask);
  mode_data.v_line = (line + (mode_data.yscroll >> 17)) & pf_row_mask;
} else {
  shift  = (mode_data.xscroll & 0x0F);
  index  = pf_col_mask + 1 - ((mode_data.xscroll >> 4) & pf_col_mask);
  mode_data.v_line = (line + (mode_data.yscroll >> 1)) & pf_row_mask;
}

  /* Plane B name table */
  nt = cast(u32 *)&vram[ntbb + (((mode_data.v_line >> 3) << pf_shift) & 0x1FC0)];

  /* Pattern row index */
  mode_data.v_line = (((mode_data.v_line & 7) << 1) | odd) << 3;

  /* Background line buffer */
  mode_data.lb = &linebuf[0][0x20];

  if(shift)
  {
    /* Left-most column is partially shown */
    mode_data.lb -= (0x10 - shift);

    mode_data.atbuf = nt[(index-1) & pf_col_mask];
    DRAW_BG_COLUMN_IM2(&mode_data);
  }

  for(column = 0; column < width; column++, index++)
  {
    mode_data.atbuf = nt[index & pf_col_mask];
    DRAW_BG_COLUMN_IM2(&mode_data);
  }
}

void render_bg_m5_im2_vs(int line, int width)
{
  int column, start, end;
  Mode5Data mode_data;
  u32 shift, index;
 u32* nt;

  /* common data */
  int odd = odd_frame;
  mode_data.xscroll      = *cast(u32 *)&vram[hscb + ((line & hscroll_mask) << 2)];
  mode_data.yscroll      = 0;
  u32 pf_col_mask  = playfield_col_mask;
  u32 pf_row_mask  = playfield_row_mask;
  u32 pf_shift     = playfield_shift;
  u32 *vs          = cast(u32 *)&vsram[0];

  /* Layer priority table */
  mode_data.table = lut[(reg[12] & 8) >> 2];

  /* Window vertical range (cell 0-31) */
  u32 a = (reg[18] & 0x1F) << 3;
  
  /* Window position (0=top, 1=bottom) */
  u32 w = (reg[18] >> 7) & 1;

  /* Test against current line */
  if (w == (line >= a))
  {
    /* Window takes up entire line */
    a = 0;
    w = 1;
  }
  else
  {
    /* Window and Plane A share the line */
    a = clip[0].enable;
    w = clip[1].enable;
  }

  /* Left-most column vertical scrolling when partially shown horizontally */
  /* Same value for both planes, only in 40-cell mode, verified on PAL MD2 */
  /* See Gynoug, Cutie Suzuki no Ringside Angel, Formula One, Kawasaki Superbike Challenge */
  if (reg[12] & 1)
  {
    /* only in 40-cell mode, verified on MD2 */
    mode_data.yscroll = (vs[19] >> 1) & (vs[19] >> 17);
  }

  /* Number of columns to draw */
  width >>= 4;

  /* Plane A */
  if (a)
  {
    /* Plane A width */
    start = clip[0].left;
    end   = clip[0].right;

    /* Plane A horizontal scroll */
version(LSB_FIRST) {
    shift = (mode_data.xscroll & 0x0F);
    index = pf_col_mask + start + 1 - ((mode_data.xscroll >> 4) & pf_col_mask);
} else {
    shift = (mode_data.xscroll >> 16) & 0x0F;
    index = pf_col_mask + start + 1 - ((mode_data.xscroll >> 20) & pf_col_mask);
}

    /* Background line buffer */
    mode_data.dst = cast(u32 *)&linebuf[0][0x20 + (start << 4) + shift];

    if(shift)
    {
      /* Left-most column is partially shown */
      mode_data.dst -= 4;

      /* Plane A vertical scroll */
      mode_data.v_line = (line + mode_data.yscroll) & pf_row_mask;

      /* Plane A name table */
      nt = cast(u32 *)&vram[ntab + (((mode_data.v_line >> 3) << pf_shift) & 0x1FC0)];

      /* Pattern row index */
      mode_data.v_line = (((mode_data.v_line & 7) << 1) | odd) << 3;

      /* Window bug */
      if (start)
      {
        mode_data.atbuf = nt[index & pf_col_mask];
      }
      else
      {
        mode_data.atbuf = nt[(index-1) & pf_col_mask];
      }

      DRAW_COLUMN_IM2(&mode_data);
    }

    for(column = start; column < end; column++, index++)
    {
      /* Plane A vertical scroll */
version(LSB_FIRST) {
      mode_data.v_line = (line + (vs[column] >> 1)) & pf_row_mask;
} else {
      mode_data.v_line = (line + (vs[column] >> 17)) & pf_row_mask;
}

      /* Plane A name table */
      nt = cast(u32 *)&vram[ntab + (((mode_data.v_line >> 3) << pf_shift) & 0x1FC0)];

      /* Pattern row index */
      mode_data.v_line = (((mode_data.v_line & 7) << 1) | odd) << 3;

      mode_data.atbuf = nt[index & pf_col_mask];
      DRAW_COLUMN_IM2(&mode_data);
    }

    /* Window width */
    start = clip[1].left;
    end   = clip[1].right;
  }
  else
  {
    /* Window width */
    start = 0;
    end   = width;
  }

  /* Window Plane */
  if (w)
  {
    /* Background line buffer */
    mode_data.dst = cast(u32 *)&linebuf[0][0x20 + (start << 4)];

    /* Window name table */
    nt = cast(u32 *)&vram[ntwb | ((line >> 3) << (6 + (reg[12] & 1)))];

    /* Pattern row index */
    mode_data.v_line = ((line & 7) << 1 | odd) << 3;

    for(column = start; column < end; column++)
    {
      mode_data.atbuf = nt[column];
      DRAW_COLUMN_IM2(&mode_data);
    }
  }

  /* Plane B horizontal scroll */
version(LSB_FIRST) {
  shift = (mode_data.xscroll >> 16) & 0x0F;
  index = pf_col_mask + 1 - ((mode_data.xscroll >> 20) & pf_col_mask);
} else {
  shift = (mode_data.xscroll & 0x0F);
  index = pf_col_mask + 1 - ((mode_data.xscroll >> 4) & pf_col_mask);
}

  /* Background line buffer */
  mode_data.lb = &linebuf[0][0x20];

  if(shift)
  {
    /* Left-most column is partially shown */
    mode_data.lb -= (0x10 - shift);

    /* Plane B vertical scroll */
    mode_data.v_line = (line + mode_data.yscroll) & pf_row_mask;

    /* Plane B name table */
    nt = cast(u32 *)&vram[ntbb + (((mode_data.v_line >> 3) << pf_shift) & 0x1FC0)];

    /* Pattern row index */
    mode_data.v_line = (((mode_data.v_line & 7) << 1) | odd) << 3;

    mode_data.atbuf = nt[(index-1) & pf_col_mask];
    DRAW_BG_COLUMN_IM2(&mode_data);
  }

  for(column = 0; column < width; column++, index++)
  {
    /* Plane B vertical scroll */
version(LSB_FIRST) {
    mode_data.v_line = (line + (vs[column] >> 17)) & pf_row_mask;
} else {
    mode_data.v_line = (line + (vs[column] >> 1)) & pf_row_mask;
}

    /* Plane B name table */
    nt = cast(u32 *)&vram[ntbb + (((mode_data.v_line >> 3) << pf_shift) & 0x1FC0)];

    /* Pattern row index */
    mode_data.v_line = (((mode_data.v_line & 7) << 1) | odd) << 3;

    mode_data.atbuf = nt[index & pf_col_mask];
    DRAW_BG_COLUMN_IM2(&mode_data);
  }
}


/*--------------------------------------------------------------------------*/
/* Sprite layer rendering functions                                         */
/*--------------------------------------------------------------------------*/

void render_obj_tms(int max_width)
{
  int x, count, start, end;
  u8* lb, sg;
  u8 color;
  u8[2] pattern;
  u16 temp;

  /* Default sprite width (8 pixels) */
  int width = 8;

  /* Adjust width for 16x16 sprites */
  width <<= ((reg[1] & 0x02) >> 1);

  /* Adjust width for zoomed sprites */
  width <<= (reg[1] & 0x01);

  /* Set SOVR flag */
  status |= spr_ovr;
  spr_ovr = 0;

  /* Draw sprites in front-to-back order */
  for (count = 0; count < object_count; count++)
  {
    /* Sprite X position */
    start = object_info[count].xpos;

    /* Sprite Color + Early Clock bit */
    color = object_info[count].size;

    /* X position shift (32 pixels) */
    start -= ((color & 0x80) >> 2);

    /* Pointer to line buffer */
    lb = &linebuf[0][0x20 + start];

    if ((start + width) > 256)
    {
      /* Clip sprites on right edge */
      end = 256 - start;

      start = 0;
    }
    else
    {
      end = width;

      if (start < 0)
      {
        /* Clip sprites on left edge */
        start = 0 - start;
      }
      else
      {
        start = 0;
      }
    }

    /* Sprite Color (0-15) */
    color &= 0x0F;

    /* Sprite Pattern Name */
    temp = object_info[count].attr;

    /* Mask two LSB for 16x16 sprites */
    temp &= ~((reg[1] & 0x02) >> 0);
    temp &= ~((reg[1] & 0x02) >> 1);

    /* Pointer to sprite generator table */
    sg = cast(u8 *)&vram[((reg[6] << 11) & 0x3800) | (temp << 3) | object_info[count].ypos];

    /* Sprite Pattern data (2 x 8 pixels) */
    pattern[0] = sg[0x00];
    pattern[1] = sg[0x10];

    if (reg[1] & 0x01)
    {
      /* Zoomed sprites are rendered at half speed */
      for (x=start; x<end; x+=2)
      {
        temp = pattern[(x >> 4) & 1];
        temp = (temp >> (7 - ((x >> 1) & 7))) & 0x01;
        temp = temp * color;
        temp |= (lb[x] << 8);
        lb[x] = lut[5][temp];
        status |= ((temp & 0x8000) >> 10);
        temp &= 0x00FF;
        temp |= (lb[x+1] << 8);
        lb[x+1] = lut[5][temp];
        status |= ((temp & 0x8000) >> 10);
      }
    }
    else
    {
      /* Normal sprites */
      for (x=start; x<end; x++)
      {
        temp = pattern[(x >> 3) & 1];
        temp = (temp >> (7 - (x & 7))) & 0x01;
        temp = temp * color;
        temp |= (lb[x] << 8);
        lb[x] = lut[5][temp];
        status |= ((temp & 0x8000) >> 10);
      }
    }
  }

  /* handle Game Gear reduced screen (160x144) */
  if ((system_hw == SYSTEM_GG) && !config.gg_extra && (v_counter < bitmap.viewport.h))
  {
    int line = v_counter - (bitmap.viewport.h - 144) / 2;
    if ((line < 0) || (line >= 144))
    {
      memset(&linebuf[0][0x20], 0x40, max_width);
    }
    else
    {
      if (bitmap.viewport.x > 0)
      {
        memset(&linebuf[0][0x20], 0x40, 48);
        memset(&linebuf[0][0x20+48+160], 0x40, 48);
      }
    }
  }
}

void render_obj_m4(int max_width)
{
  int count, xpos, end;
  u8* src, lb;
  u16 temp;

  /* Default sprite width */
  int width = 8;
  
  /* Sprite Generator address mask (LSB is masked for 8x16 sprites) */
  u16 sg_mask = (~0x1C0 ^ (reg[6] << 6)) & (~((reg[1] & 0x02) >> 1));

  /* Zoomed sprites (not working on Genesis VDP) */
  if (system_hw < SYSTEM_MD)
  {
    width <<= (reg[1] & 0x01);
  }

  /* Unused bits used as a mask on 315-5124 VDP only */
  if (system_hw > SYSTEM_SMS)
  {
    sg_mask |= 0xC0;
  }

  /* Set SOVR flag */
  status |= spr_ovr;
  spr_ovr = 0;

  /* Draw sprites in front-to-back order */
  for (count = 0; count < object_count; count++)
  {
    /* 315-5124 VDP specific */
    if (count == 4)
    {
      if (system_hw < SYSTEM_SMS2)
      {
        /* Only 4 first sprites can be zoomed */
        width = 8;
      }
    }

    /* Sprite pattern index */
    temp = (object_info[count].attr | 0x100) & sg_mask;

    /* Pointer to pattern cache line */
    src = cast(u8 *)&bg_pattern_cache[(temp << 6) | (object_info[count].ypos << 3)];

    /* Sprite X position */
    xpos = object_info[count].xpos;

    /* X position shift */
    xpos -= (reg[0] & 0x08);

    if (xpos < 0)
    {
      /* Clip sprites on left edge */
      src = src - xpos;
      end = xpos + width;
      xpos = 0;
    }
    else if ((xpos + width) > max_width)
    {
      /* Clip sprites on right edge */
      end = max_width - xpos;
    }
    else
    {
      /* Sprite maximal width */
      end = width;
    }

    /* Pointer to line buffer */
    lb = &linebuf[0][0x20 + xpos];

    if (width > 8)
    {
      /* Draw sprite pattern (zoomed sprites are rendered at half speed) */
      DRAW_SPRITE_TILE_ACCURATE_2X(end, 0, lut[5], xpos, lb, src);
    }
    else
    {
      /* Draw sprite pattern */
      DRAW_SPRITE_TILE_ACCURATE(end, 0, lut[5], xpos, lb, src);
    }
  }

  /* handle Game Gear reduced screen (160x144) */
  if ((system_hw == SYSTEM_GG) && !config.gg_extra && (v_counter < bitmap.viewport.h))
  {
    int line = v_counter - (bitmap.viewport.h - 144) / 2;
    if ((line < 0) || (line >= 144))
    {
      memset(&linebuf[0][0x20], 0x40, max_width);
    }
    else
    {
      if (bitmap.viewport.x > 0)
      {
        memset(&linebuf[0][0x20], 0x40, 48);
        memset(&linebuf[0][0x20+48+160], 0x40, 48);
      }
    }
  }
}

void render_obj_m5(int max_width)
{
  int count, column;
  int xpos, width;
  int pixelcount = 0;
  int masked = 0;

  u8* src, s, lb;
  u32 temp, v_line;
  u32 attr, name, atex;

  /* Draw sprites in front-to-back order */
  for (count = 0; count < object_count; count++)
  {
    /* Sprite X position */
    xpos = object_info[count].xpos;

    /* Sprite masking  */
    if (xpos)
    {
      /* Requires at least one sprite with xpos > 0 */
      spr_ovr = 1;
    }
    else if (spr_ovr)
    {
      /* Remaining sprites are not drawn */
      masked = 1;
    }

    /* Display area offset */
    xpos = xpos - 0x80;

    /* Sprite size */
    temp = object_info[count].size;

    /* Sprite width */
    width = 8 + ((temp & 0x0C) << 1);

    /* Update pixel count (off-screen sprites are included) */
    pixelcount += width;

    /* Is sprite across visible area ? */
    if (((xpos + width) > 0) && (xpos < max_width) && !masked)
    {
      /* Sprite attributes */
      attr = object_info[count].attr;

      /* Sprite vertical offset */
      v_line = object_info[count].ypos;

      /* Sprite priority + palette bits */
      atex = (attr >> 9) & 0x70;

      /* Pattern name base */
      name = attr & 0x07FF;

      /* Mask vflip/hflip */
      attr &= 0x1800;

      /* Pointer into pattern name offset look-up table */
      s = &name_lut[((attr >> 3) & 0x300) | (temp << 4) | ((v_line & 0x18) >> 1)];

      /* Pointer into line buffer */
      lb = &linebuf[0][0x20 + xpos];

      /* Adjust number of pixels to draw for sprite limit */
      if (pixelcount > max_width)
      {
        width = width - pixelcount + max_width;
      }

      /* Number of tiles to draw */
      width = width >> 3;

      /* Pattern row index */
      v_line = (v_line & 7) << 3;

      /* Draw sprite patterns */
      for(column = 0; column < width; column++, lb+=8)
      {
        temp = attr | ((name + s[column]) & 0x07FF);
        src = &bg_pattern_cache[(temp << 6) | (v_line)];
        DRAW_SPRITE_TILE(8, atex, lut[1], lb, src);
      }
    }

    /* Sprite limit */
    if (pixelcount >= max_width)
    {
      /* Sprite masking will be effective on next line  */
      spr_ovr = 1;

      /* Stop sprite rendering */
      return;
    }
  }

  /* Clear sprite masking for next line  */
  spr_ovr = 0;
}

void render_obj_m5_ste(int max_width)
{
  int count, column;
  int xpos, width;
  int pixelcount = 0;
  int masked = 0;

  u8* src, s, lb;
  u32 temp, v_line;
  u32 attr, name, atex;

  /* Clear sprite line buffer */
  memset(&linebuf[1][0], 0, max_width + 0x40);

  /* Draw sprites in front-to-back order */
  for (count = 0; count < object_count; count++)
  {
    /* Sprite X position */
    xpos = object_info[count].xpos;

    /* Sprite masking  */
    if (xpos)
    {
      /* Requires at least one sprite with xpos > 0 */
      spr_ovr = 1;
    }
    else if (spr_ovr)
    {
      /* Remaining sprites are not drawn */
      masked = 1;
    }

    /* Display area offset */
    xpos = xpos - 0x80;

    /* Sprite size */
    temp = object_info[count].size;

    /* Sprite width */
    width = 8 + ((temp & 0x0C) << 1);

    /* Update pixel count (off-screen sprites are included) */
    pixelcount += width;

    /* Is sprite across visible area ? */
    if (((xpos + width) > 0) && (xpos < max_width) && !masked)
    {
      /* Sprite attributes */
      attr = object_info[count].attr;

      /* Sprite vertical offset */
      v_line = object_info[count].ypos;

      /* Sprite priority + palette bits */
      atex = (attr >> 9) & 0x70;

      /* Pattern name base */
      name = attr & 0x07FF;

      /* Mask vflip/hflip */
      attr &= 0x1800;

      /* Pointer into pattern name offset look-up table */
      s = &name_lut[((attr >> 3) & 0x300) | (temp << 4) | ((v_line & 0x18) >> 1)];

      /* Pointer into line buffer */
      lb = &linebuf[1][0x20 + xpos];

      /* Adjust number of pixels to draw for sprite limit */
      if (pixelcount > max_width)
      {
        width = width - pixelcount + max_width;
      }

      /* Number of tiles to draw */
      width = width >> 3;

      /* Pattern row index */
      v_line = (v_line & 7) << 3;

      /* Draw sprite patterns */
      for(column = 0; column < width; column++, lb+=8)
      {
        temp = attr | ((name + s[column]) & 0x07FF);
        src = &bg_pattern_cache[(temp << 6) | (v_line)];
        DRAW_SPRITE_TILE(8, atex, lut[3], lb, src);
      }
    }

    /* Sprite limit */
    if (pixelcount >= max_width)
    {
      /* Sprite masking will be effective on next line  */
      spr_ovr = 1;

      /* Merge background & sprite layers */
      merge(&linebuf[1][0x20],&linebuf[0][0x20],&linebuf[0][0x20],lut[4], max_width);

      /* Stop sprite rendering */
      return;
    }
  }

  /* Clear sprite masking for next line  */
  spr_ovr = 0;

  /* Merge background & sprite layers */
  merge(&linebuf[1][0x20],&linebuf[0][0x20],&linebuf[0][0x20],lut[4], max_width);
}

void render_obj_m5_im2(int max_width)
{
  int count, column;
  int xpos, width;
  int pixelcount = 0;
  int masked = 0;
  int odd = odd_frame;

  u8* src, s, lb;
  u32 temp, v_line;
  u32 attr, name, atex;

  /* Draw sprites in front-to-back order */
  for (count = 0; count < object_count; count++)
  {
    /* Sprite X position */
    xpos = object_info[count].xpos;

    /* Sprite masking  */
    if (xpos)
    {
      /* Requires at least one sprite with xpos > 0 */
      spr_ovr = 1;
    }
    else if (spr_ovr)
    {
      /* Remaining sprites are not drawn */
      masked = 1;
    }

    /* Display area offset */
    xpos = xpos - 0x80;

    /* Sprite size */
    temp = object_info[count].size;

    /* Sprite width */
    width = 8 + ((temp & 0x0C) << 1);

    /* Update pixel count (off-screen sprites are included) */
    pixelcount += width;

    /* Is sprite across visible area ? */
    if (((xpos + width) > 0) && (xpos < max_width) && !masked)
    {
      /* Sprite attributes */
      attr = object_info[count].attr;

      /* Sprite y offset */
      v_line = object_info[count].ypos;

      /* Sprite priority + palette bits */
      atex = (attr >> 9) & 0x70;

      /* Pattern name base */
      name = attr & 0x03FF;

      /* Mask vflip/hflip */
      attr &= 0x1800;

      /* Pattern name offset lookup table */
      s = &name_lut[((attr >> 3) & 0x300) | (temp << 4) | ((v_line & 0x18) >> 1)];

      /* Pointer into line buffer */
      lb = &linebuf[0][0x20 + xpos];

      /* Adjust width for sprite limit */
      if (pixelcount > max_width)
      {
        width = width - pixelcount + max_width;
      }

      /* Number of tiles to draw */
      width = width >> 3;

      /* Pattern row index */
      v_line = (((v_line & 7) << 1) | odd) << 3;

      /* Render sprite patterns */
      for(column = 0; column < width; column ++, lb+=8)
      {
        temp = attr | (((name + s[column]) & 0x3ff) << 1);
        src = &bg_pattern_cache[((temp << 6) | (v_line)) ^ ((attr & 0x1000) >> 6)];
        DRAW_SPRITE_TILE(8, atex, lut[1], lb, src);
      }
    }

    /* Sprite Limit */
    if (pixelcount >= max_width)
    {
      /* Enable sprite masking for next line */
      spr_ovr = 1;

      /* Stop sprite rendering */
      return;
    }
  }

  /* Clear sprite masking for next line */
  spr_ovr = 0;
}

void render_obj_m5_im2_ste(int max_width)
{
  int count, column;
  int xpos, width;
  int pixelcount = 0;
  int masked = 0;
  int odd = odd_frame;

  u8* src, s, lb;
  u32 temp, v_line;
  u32 attr, name, atex;

  /* Clear sprite line buffer */
  memset(&linebuf[1][0], 0, max_width + 0x40);

  /* Draw sprites in front-to-back order */
  for (count = 0; count < object_count; count++)
  {
    /* Sprite X position */
    xpos = object_info[count].xpos;

    /* Sprite masking  */
    if (xpos)
    {
      /* Requires at least one sprite with xpos > 0 */
      spr_ovr = 1;
    }
    else if (spr_ovr)
    {
      /* Remaining sprites are not drawn */
      masked = 1;
    }

    /* Display area offset */
    xpos = xpos - 0x80;

    /* Sprite size */
    temp = object_info[count].size;

    /* Sprite width */
    width = 8 + ((temp & 0x0C) << 1);

    /* Update pixel count (off-screen sprites are included) */
    pixelcount += width;

    /* Is sprite across visible area ? */
    if (((xpos + width) > 0) && (xpos < max_width) && !masked)
    {
      /* Sprite attributes */
      attr = object_info[count].attr;

      /* Sprite y offset */
      v_line = object_info[count].ypos;

      /* Sprite priority + palette bits */
      atex = (attr >> 9) & 0x70;

      /* Pattern name base */
      name = attr & 0x03FF;

      /* Mask vflip/hflip */
      attr &= 0x1800;

      /* Pattern name offset lookup table */
      s = &name_lut[((attr >> 3) & 0x300) | (temp << 4) | ((v_line & 0x18) >> 1)];

      /* Pointer into line buffer */
      lb = &linebuf[1][0x20 + xpos];

      /* Adjust width for sprite limit */
      if (pixelcount > max_width)
      {
        width = width - pixelcount + max_width;
      }

      /* Number of tiles to draw */
      width = width >> 3;

      /* Pattern row index */
      v_line = (((v_line & 7) << 1) | odd) << 3;

      /* Render sprite patterns */
      for(column = 0; column < width; column ++, lb+=8)
      {
        temp = attr | (((name + s[column]) & 0x3ff) << 1);
        src = &bg_pattern_cache[((temp << 6) | (v_line)) ^ ((attr & 0x1000) >> 6)];
        DRAW_SPRITE_TILE(8, atex, lut[3], lb, src);
      }
    }

    /* Sprite Limit */
    if (pixelcount >= max_width)
    {
      /* Enable sprite masking for next line */
      spr_ovr = 1;

      /* Merge background & sprite layers */
      merge(&linebuf[1][0x20],&linebuf[0][0x20],&linebuf[0][0x20],lut[4], max_width);

      /* Stop sprite rendering */
      return;
    }
  }

  /* Clear sprite masking for next line */
  spr_ovr = 0;

  /* Merge background & sprite layers */
  merge(&linebuf[1][0x20],&linebuf[0][0x20],&linebuf[0][0x20],lut[4], max_width);
}


/*--------------------------------------------------------------------------*/
/* Sprites Parsing functions                                                */
/*--------------------------------------------------------------------------*/

void parse_satb_tms(int line)
{
  int i = 0;

  /* Sprite counter (4 max. per line) */
  int count = 0;

  /* no sprites in Text modes */
  if (!(reg[1] & 0x10))
  {
    /* Pointer to sprite attribute table */
    u8 *st = &vram[(reg[5] << 7) & 0x3F80];

    /* Y position */
    int ypos;

    /* Sprite height (8 pixels by default) */
    int height = 8;

    /* Adjust height for 16x16 sprites */
    height <<= ((reg[1] & 0x02) >> 1);

    /* Adjust height for zoomed sprites */
    height <<= (reg[1] & 0x01);

    /* Parse Sprite Table (32 entries) */
    do
    {
      /* Sprite Y position */
      ypos = st[i << 2];

      /* Check end of sprite list marker */
      if (ypos == 0xD0)
      {
        break;
      }

      /* Wrap Y coordinate for sprites > 256-32 */
      if (ypos >= 224)
      {
        ypos -= 256;
      }

      /* Y range */
      ypos = line - ypos;

      /* Sprite is visble on this line ? */
      if ((ypos >= 0) && (ypos < height))
      {
        /* Sprite overflow */
        if (count == 4)
        {
          /* Flag is set only during active area */
          if (line < bitmap.viewport.h)
          {
            spr_ovr = 0x40;
          }
          break;
        }

        /* Adjust Y range back for zoomed sprites */
        ypos >>= (reg[1] & 0x01);

        /* Store sprite attributes for later processing */
        object_info[count].ypos = ypos;
        object_info[count].xpos = st[(i << 2) + 1];
        object_info[count].attr = st[(i << 2) + 2];
        object_info[count].size = st[(i << 2) + 3];

        /* Increment Sprite count */
        ++count;
      }
    }
    while (++i < 32);
  }

  /* Update sprite count for next line */
  object_count = count;

  /* Insert number of last sprite entry processed */
  status = (status & 0xE0) | (i & 0x1F);
}

void parse_satb_m4(int line)
{
  int i = 0;
  u8 *st;

  /* Sprite counter (8 max. per line) */
  int count = 0;

  /* Y position */
  int ypos;

  /* Sprite height (8x8 or 8x16) */
  int height = 8 + ((reg[1] & 0x02) << 2);

  /* Sprite attribute table address mask */
  u16 st_mask = ~0x3F80 ^ (reg[5] << 7);

  /* Unused bits used as a mask on 315-5124 VDP only */
  if (system_hw > SYSTEM_SMS)
  {
    st_mask |= 0x80;
  }

  /* Pointer to sprite attribute table */
  st = &vram[st_mask & 0x3F00];

  /* Parse Sprite Table (64 entries) */
  do
  {
    /* Sprite Y position */
    ypos = st[i];

    /* Check end of sprite list marker */
    if (ypos == (bitmap.viewport.h + 16))
    {
      break;
    }

    /* Wrap Y coordinate for sprites > 256-16 */
    if (ypos >= 240)
    {
      ypos -= 256;
    }

    /* Y range */
    ypos = line - ypos;

    /* Adjust Y range for zoomed sprites (not working on Mega Drive VDP) */
    if (system_hw < SYSTEM_MD)
    {
      ypos >>= (reg[1] & 0x01);
    }

    /* Check if sprite is visible on this line */
    if ((ypos >= 0) && (ypos < height))
    {
      /* Sprite overflow */
      if (count == 8)
      {
        /* Flag is set only during active area */
        if ((line >= 0) && (line < bitmap.viewport.h))
        {
          spr_ovr = 0x40;
        }
        break;
      }

      /* Store sprite attributes for later processing */
      object_info[count].ypos = ypos;
      object_info[count].xpos = st[(0x80 + (i << 1)) & st_mask];
      object_info[count].attr = st[(0x81 + (i << 1)) & st_mask];

      /* Increment Sprite count */
      ++count;
    }
  }
  while (++i < 64);

  /* Update sprite count for next line */
  object_count = count;
}

void parse_satb_m5(int line)
{
  /* Y position */
  int ypos;

  /* Sprite height (8,16,24,32 pixels)*/
  int height;

  /* Sprite size data */
  int size;

  /* Sprite link data */
  int link = 0;

  /* Sprite counter */
  int count = 0;

  /* 16 or 20 sprites max. per line */
  int max = 16 + ((reg[12] & 1) << 2);

  /* 64 or 80 sprites max. */
  int total = max << 2;

  /* Pointer to sprite attribute table */
  u16* p = cast(u16 *) &vram[satb];

  /* Pointer to internal RAM */
  u16* q = cast(u16 *) &sat[0];

  /* Adjust line offset */
  line += 0x81;

  do
  {
    /* Read Y position & size from internal SAT */
    ypos = (q[link] >> im2_flag) & 0x1FF;
    size = q[link + 1] >> 8;

    /* Sprite height */
    height = 8 + ((size & 3) << 3);

    /* Y range */
    ypos = line - ypos;

    /* Sprite is visble on this line ? */
    if ((ypos >= 0) && (ypos < height))
    {
      /* Sprite overflow */
      if (count == max)
      {
        status |= 0x40;
        break;
      }

      /* Update sprite list */
      /* name, attribute & xpos are parsed from VRAM */ 
      object_info[count].attr  = p[link + 2];
      object_info[count].xpos  = p[link + 3] & 0x1ff;
      object_info[count].ypos  = ypos;
      object_info[count].size  = size & 0x0f;
      ++count;
    }

    /* Read link data from internal SAT */ 
    link = (q[link + 1] & 0x7F) << 2;

    /* Last sprite */
    if (link == 0) break;
  }
  while (--total);

  /* Update sprite count for next line */
  object_count = count;
}


/*--------------------------------------------------------------------------*/
/* Pattern cache update function                                            */
/*--------------------------------------------------------------------------*/

void update_bg_pattern_cache_m4(int index)
{
  int i;
  u8 x, y, c;
  u8 *dst;
  u16 name, bp01, bp23;
  u32 bp;

  for(i = 0; i < index; i++)
  {
    /* Get modified pattern name index */
    name = bg_name_list[i];

    /* Check modified lines */
    for(y = 0; y < 8; y++)
    {
      if(bg_name_dirty[name] & (1 << y))
      {
        /* Pattern cache base address */
        dst = &bg_pattern_cache[name << 6];

        /* Byteplane data */
        bp01 = *cast(u16 *)&vram[(name << 5) | (y << 2) | (0)];
        bp23 = *cast(u16 *)&vram[(name << 5) | (y << 2) | (2)];

        /* Convert to pixel line data (4 bytes = 8 pixels)*/
        /* (msb) p7p6 p5p4 p3p2 p1p0 (lsb) */
        bp = (bp_lut[bp01] >> 2) | (bp_lut[bp23]);

        /* Update cached line (8 pixels = 8 bytes) */
        for(x = 0; x < 8; x++)
        {
          /* Extract pixel data */
          c = bp & 0x0F;

          /* Pattern cache data (one pattern = 8 bytes) */
          /* byte0 <-> p0 p1 p2 p3 p4 p5 p6 p7 <-> byte7 (hflip = 0) */
          /* byte0 <-> p7 p6 p5 p4 p3 p2 p1 p0 <-> byte7 (hflip = 1) */
          dst[0x00000 | (y << 3) | (x)] = (c);            /* vflip=0 & hflip=0 */
          dst[0x08000 | (y << 3) | (x ^ 7)] = (c);        /* vflip=0 & hflip=1 */
          dst[0x10000 | ((y ^ 7) << 3) | (x)] = (c);      /* vflip=1 & hflip=0 */
          dst[0x18000 | ((y ^ 7) << 3) | (x ^ 7)] = (c);  /* vflip=1 & hflip=1 */

          /* Next pixel */
          bp = bp >> 4;
        }
      }
    }

    /* Clear modified pattern flag */
    bg_name_dirty[name] = 0;
  }
}

void update_bg_pattern_cache_m5(int index)
{
  int i;
  u8 x, y, c;
  u8 *dst;
  u16 name;
  u32 bp;

  for(i = 0; i < index; i++)
  {
    /* Get modified pattern name index */
    name = bg_name_list[i];

    /* Check modified lines */
    for(y = 0; y < 8; y ++)
    {
      if(bg_name_dirty[name] & (1 << y))
      {
        /* Pattern cache base address */
        dst = &bg_pattern_cache[name << 6];

        /* Byteplane data (one pattern = 4 bytes) */
        /* LIT_ENDIAN: byte0 (lsb) p2p3 p0p1 p6p7 p4p5 (msb) byte3 */
        /* BIG_ENDIAN: byte0 (msb) p0p1 p2p3 p4p5 p6p7 (lsb) byte3 */
        bp = *cast(u32 *)&vram[(name << 5) | (y << 2)];

        /* Update cached line (8 pixels = 8 bytes) */
        for(x = 0; x < 8; x ++)
        {
          /* Extract pixel data */
          c = bp & 0x0F;

          /* Pattern cache data (one pattern = 8 bytes) */
          /* byte0 <-> p0 p1 p2 p3 p4 p5 p6 p7 <-> byte7 (hflip = 0) */
          /* byte0 <-> p7 p6 p5 p4 p3 p2 p1 p0 <-> byte7 (hflip = 1) */
version(LSB_FIRST) {
          /* Byteplane data = (msb) p4p5 p6p7 p0p1 p2p3 (lsb) */
          dst[0x00000 | (y << 3) | (x ^ 3)] = (c);        /* vflip=0, hflip=0 */
          dst[0x20000 | (y << 3) | (x ^ 4)] = (c);        /* vflip=0, hflip=1 */
          dst[0x40000 | ((y ^ 7) << 3) | (x ^ 3)] = (c);  /* vflip=1, hflip=0 */
          dst[0x60000 | ((y ^ 7) << 3) | (x ^ 4)] = (c);  /* vflip=1, hflip=1 */
} else {
          /* Byteplane data = (msb) p0p1 p2p3 p4p5 p6p7 (lsb) */
          dst[0x00000 | (y << 3) | (x ^ 7)] = (c);        /* vflip=0, hflip=0 */
          dst[0x20000 | (y << 3) | (x)] = (c);            /* vflip=0, hflip=1 */
          dst[0x40000 | ((y ^ 7) << 3) | (x ^ 7)] = (c);  /* vflip=1, hflip=0 */
          dst[0x60000 | ((y ^ 7) << 3) | (x)] = (c);      /* vflip=1, hflip=1 */
}
          /* Next pixel */
          bp = bp >> 4;
        }
      }
    }

    /* Clear modified pattern flag */
    bg_name_dirty[name] = 0;
  }
}


/*--------------------------------------------------------------------------*/
/* Window & Plane A clipping update function (Mode 5)                       */
/*--------------------------------------------------------------------------*/

void window_clip(u32 data, u32 sw)
{
  /* Window size and invert flags */
  u32 hp = (data & 0x1f);
  u32 hf = (data >> 7) & 1;

  /* Perform horizontal clipping; the results are applied in reverse
     if the horizontal inversion flag is set
   */
  u32 a = hf;
  u32 w = hf ^ 1;

  /* Display width (16 or 20 columns) */
  sw = 16 + (sw << 2);

  if(hp)
  {
    if(hp > sw)
    {
      /* Plane W takes up entire line */
      clip[w].left = 0;
      clip[w].right = sw;
      clip[w].enable = 1;
      clip[a].enable = 0;
    }
    else
    {
      /* Plane W takes left side, Plane A takes right side */
      clip[w].left = 0;
      clip[a].right = sw;
      clip[a].left = clip[w].right = hp;
      clip[0].enable = clip[1].enable = 1;
    }
  }
  else
  {
    /* Plane A takes up entire line */
    clip[a].left = 0;
    clip[a].right = sw;
    clip[a].enable = 1;
    clip[w].enable = 0;
  }
}


/*--------------------------------------------------------------------------*/
/* Init, reset routines                                                     */
/*--------------------------------------------------------------------------*/

void render_init()
{
  int bx, ax;

  /* Initialize layers priority pixel look-up tables */
  u16 index;
  for (bx = 0; bx < 0x100; bx++)
  {
    for (ax = 0; ax < 0x100; ax++)
    {
      index = (bx << 8) | (ax);

      lut[0][index] = make_lut_bg(bx, ax);
      lut[1][index] = make_lut_bgobj(bx, ax);
      lut[2][index] = make_lut_bg_ste(bx, ax);
      lut[3][index] = make_lut_obj(bx, ax);
      lut[4][index] = make_lut_bgobj_ste(bx, ax);
      lut[5][index] = make_lut_bgobj_m4(bx,ax);
    }
  }

  /* Initialize pixel color look-up tables */
  palette_init();

  /* Make sprite pattern name index look-up table (Mode 5) */
  make_name_lut();

  /* Make bitplane to pixel look-up table (Mode 4) */
  make_bp_lut();
}

void render_reset()
{
  /* Clear display bitmap */
  bitmap.data[0 .. bitmap.pitch * bitmap.height] = 0;

  /* Clear line buffers */
  memset(linebuf, 0, sizeof(linebuf));

  /* Clear color palettes */
  memset(pixel, 0, sizeof(pixel));

  /* Clear pattern cache */
  memset (cast(char *) bg_pattern_cache, 0, sizeof (bg_pattern_cache));

  /* Reset Sprite infos */
  spr_ovr = spr_col = object_count = 0;
}


/*--------------------------------------------------------------------------*/
/* Line rendering functions                                                 */
/*--------------------------------------------------------------------------*/

void render_line(int line)
{
  int width = bitmap.viewport.w;
  int x_offset;

  /* Check display status */
  if (reg[1] & 0x40)
  {
    /* Update pattern cache */
    if (bg_list_index)
    {
      update_bg_pattern_cache(bg_list_index);
      bg_list_index = 0;
    }

    /* Render BG layer(s) */
    render_bg(line, width);

    /* Render sprite layer */
    render_obj(width);

    /* Left-most column blanking */
    if (reg[0] & 0x20)
    {
      if (system_hw > SYSTEM_SG)
      {
        memset(&linebuf[0][0x20], 0x40, 8);
      }
    }

    /* Parse sprites for next line */
    if (line < (bitmap.viewport.h - 1))
    {
      parse_satb(line);
    }
  }
  else
  {
    /* Master System & Game Gear VDP specific */
    if (system_hw < SYSTEM_MD)
    {
      /* Update SOVR flag */
      status |= spr_ovr;
      spr_ovr = 0;

      /* Sprites are still parsed when display is disabled */
      parse_satb(line);
    }

    /* Blanked line */
    memset(&linebuf[0][0x20], 0x40, width);
  }

  /* Horizontal borders */
  x_offset = bitmap.viewport.x;
  if (x_offset > 0)
  {
    memset(&linebuf[0][0x20 - x_offset], 0x40, x_offset);
    memset(&linebuf[0][0x20 + width], 0x40, x_offset);
  }

  /* Pixel color remapping */
  remap_line(line);
}

void blank_line(int line, int offset, int width)
{
  memset(&linebuf[0][0x20 + offset], 0x40, width);
  remap_line(line);
}

void remap_line(int line)
{
  /* Line width */
  int width = bitmap.viewport.w + (bitmap.viewport.x * 2);

  /* Pixel line buffer */
  u8 *src = &linebuf[0][0x20 - bitmap.viewport.x];

  /* Adjust line offset in framebuffer */
  line = (line + bitmap.viewport.y) % lines_per_frame;

  /* Take care of Game Gear reduced screen when overscan is disabled */
  if (line < 0) return;

  /* Adjust for interlaced output */
  if (interlaced && config.render)
  {
    line = (line * 2) + odd_frame;
  }

  /* NTSC Filter (only supported for 15 or 16-bit pixels rendering) */
  if (config.ntsc)
  {
    if (reg[12] & 0x01)
    {
      md_ntsc_blit(md_ntsc, cast(const MD_NTSC_IN_T*)pixel, src, width, line);
    }
    else
    {
      sms_ntsc_blit(sms_ntsc, cast(const SMS_NTSC_IN_T*)pixel, src, width, line);
    }
  }
  else
  {
    /* Convert VDP pixel data to output pixel format */
version(CUSTOM_BLITTER) {
    CUSTOM_BLITTER(line, width, pixel, src);
} else {
    PIXEL_OUT_T* dst = (cast(PIXEL_OUT_T *)&bitmap.data[(line * bitmap.pitch)]);
    do
    {
      *dst++ = pixel[*src++];
    }
    while (--width);
}
  }
}
