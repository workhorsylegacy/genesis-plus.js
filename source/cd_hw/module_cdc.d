/***************************************************************************************
 *  Genesis Plus
 *  CD data controller (LC89510 compatible)
 *
 *  Copyright (C) 2012  Eke-Eke (Genesis Plus GX)
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
import module_scd;

ref cdc_t cdc() { return scd.cdc_hw; }

/* CDC hardware */
struct cdc_t
{
  u8 ifstat;
  u8 ifctrl;
  reg16_t dbc;
  reg16_t dac;
  reg16_t pt;
  reg16_t wa;
  u8[2] ctrl;
  u8[2][4] head;
  u8[4] stat;
  s32 cycles;
  void function(u32 words) dma_w;  /* DMA transfer callback */
  u8[0x4000 + 2352] ram; /* 16K external RAM (with one block overhead to handle buffer overrun) */
}

/* IFSTAT register bitmasks */
const int BIT_DTEI  = 0x40;
const int BIT_DECI  = 0x20;
const int BIT_DTBSY = 0x08;
const int BIT_DTEN  = 0x02;

/* IFCTRL register bitmasks */
const int BIT_DTEIEN  = 0x40;
const int BIT_DECIEN  = 0x20;
const int BIT_DOUTEN  = 0x02;

/* CTRL0 register bitmasks */
const int BIT_DECEN   = 0x80;
const int BIT_E01RQ   = 0x20;
const int BIT_AUTORQ  = 0x10;
const int BIT_WRRQ    = 0x04;

/* CTRL1 register bitmasks */
const int BIT_MODRQ   = 0x08;
const int BIT_FORMRQ  = 0x04;
const int BIT_SHDREN  = 0x01;

/* CTRL2 register bitmask */
const int BIT_VALST   = 0x80;

/* TODO: figure exact DMA transfer rate */
const int DMA_BYTES_PER_LINE = 512;

void cdc_init()
{
  cdc = cdc_t.init;
}

void cdc_reset()
{
  /* reset CDC register index */
  scd.regs[0x04>>1].b.l = 0x00;

  /* reset CDC registers */
  cdc.ifstat  = 0xff;
  cdc.ifctrl  = 0x00;
  cdc.ctrl[0] = 0x00;
  cdc.ctrl[1] = 0x00;
  cdc.stat[0] = 0x00;
  cdc.stat[1] = 0x00;
  cdc.stat[2] = 0x00;
  cdc.stat[3] = 0x80;
  cdc.head[0][0] = 0x00;
  cdc.head[0][1] = 0x00;
  cdc.head[0][2] = 0x00;
  cdc.head[0][3] = 0x01;
  cdc.head[1][0] = 0x00;
  cdc.head[1][1] = 0x00;
  cdc.head[1][2] = 0x00;
  cdc.head[1][3] = 0x00;

  /* reset CDC cycle counter */
  cdc.cycles = 0;

  /* DMA transfer disabled */
  cdc.dma_w = 0;

  /* clear any pending IRQ */
  if (scd.pending & (1 << 5))
  {
    /* clear any pending interrupt level 5 */
    scd.pending &= ~(1 << 5);

    /* update IRQ level */
    s68k_update_irq((scd.pending & scd.regs[0x32>>1].b.l) >> 1);
  }
}

s32 cdc_context_save(u8 *state)
{
  u8 tmp8;
  s32 bufferptr = 0;

  if (cdc.dma_w == pcm_ram_dma_w)
  {
    tmp8 = 1;
  }
  else if (cdc.dma_w == prg_ram_dma_w)
  {
    tmp8 = 2;
  }
  else if (cdc.dma_w == word_ram_0_dma_w)
  {
    tmp8 = 3;
  }
  else if (cdc.dma_w == word_ram_1_dma_w)
  {
    tmp8 = 4;
  }
  else if (cdc.dma_w == word_ram_2M_dma_w)
  {
    tmp8 = 5;
  }
  else
  {
    tmp8 = 0;
  }

  save_param(&bufferptr, state, &cdc, sizeof(cdc));
  save_param(&bufferptr, state, &tmp8, 1);

  return bufferptr;
}

s32 cdc_context_load(u8 *state)
{
  u8 tmp8;
  s32 bufferptr = 0;

  load_param(&bufferptr, state, &cdc, sizeof(cdc));
  load_param(&bufferptr, state, &tmp8, 1);

  switch (tmp8)
  {
    case 1:
      cdc.dma_w = pcm_ram_dma_w;
      break;
    case 2:
      cdc.dma_w = prg_ram_dma_w;
      break;
    case 3:
      cdc.dma_w = word_ram_0_dma_w;
      break;
    case 4:
      cdc.dma_w = word_ram_1_dma_w;
      break;
    case 5:
      cdc.dma_w = word_ram_2M_dma_w;
      break;
    default:
      cdc.dma_w = 0;
      break;
  }

  return bufferptr;
}

void cdc_dma_update()
{
  /* maximal transfer length */
  s32 length = DMA_BYTES_PER_LINE;

  /* end of DMA transfer ? */
  if (cdc.dbc.w < DMA_BYTES_PER_LINE)
  {
    /* transfer remaining words using 16-bit DMA */
    cdc.dma_w((cdc.dbc.w + 1) >> 1);

    /* reset data byte counter (DBCH bits 4-7 should be set to 1) */
    cdc.dbc.w = 0xf000;

    /* clear !DTEN and !DTBSY */
    cdc.ifstat |= (BIT_DTBSY | BIT_DTEN);

    /* pending Data Transfer End interrupt */
    cdc.ifstat &= ~BIT_DTEI;

    /* Data Transfer End interrupt enabled ? */
    if (cdc.ifctrl & BIT_DTEIEN)
    {
      /* pending level 5 interrupt */
      scd.pending |= (1 << 5);

      /* level 5 interrupt enabled ? */
      if (scd.regs[0x32>>1].b.l & 0x20)
      {
        /* update IRQ level */
        s68k_update_irq((scd.pending & scd.regs[0x32>>1].b.l) >> 1);
      }
    }

    /* clear DSR bit & set EDT bit (SCD register $04) */
    scd.regs[0x04>>1].b.h = (scd.regs[0x04>>1].b.h & 0x07) | 0x80;

    /* disable DMA transfer */
    cdc.dma_w = 0;
  }
  else
  {
    /* transfer all words using 16-bit DMA */
    cdc.dma_w(DMA_BYTES_PER_LINE >> 1);

    /* decrement data byte counter */
    cdc.dbc.w -= length;
  }
}

s32 cdc_decoder_update(u32 header)
{
  /* data decoding enabled ? */
  if (cdc.ctrl[0] & BIT_DECEN)
  {
    /* update HEAD registers */
    *cast(u32 *)(cdc.head[0]) = header;

    /* set !VALST */
    cdc.stat[3] = 0x00;

    /* pending decoder interrupt */
    cdc.ifstat &= ~BIT_DECI;

    /* decoder interrupt enabled ? */
    if (cdc.ifctrl & BIT_DECIEN)
    {
      /* pending level 5 interrupt */
      scd.pending |= (1 << 5);

      /* level 5 interrupt enabled ? */
      if (scd.regs[0x32>>1].b.l & 0x20)
      {
        /* update IRQ level */
        s68k_update_irq((scd.pending & scd.regs[0x32>>1].b.l) >> 1);
      }
    }

    /* buffer RAM write enabled ? */
    if (cdc.ctrl[0] & BIT_WRRQ)
    {
      u16 offset;

      /* increment block pointer  */
      cdc.pt.w += 2352;

      /* increment write address */
      cdc.wa.w += 2352;

      /* CDC buffer address */
      offset = cdc.pt.w & 0x3fff;

      /* write CDD block header (4 bytes) */
      *cast(u32 *)(cdc.ram + offset) = header;

      /* write CDD block data (2048 bytes) */
      cdd_read_data(cdc.ram + 4 + offset);

      /* take care of buffer overrun */
      if (offset > (0x4000 - 2048 - 4))
      {
        /* data should be written at the start of buffer */
        core.stdc.string.memcpy(cdc.ram, cdc.ram + 0x4000, offset + 2048 + 4 - 0x4000);
      }

      /* read next data block */
      return 1;
    }
  }
  
  /* keep decoding same data block if Buffer Write is disabled */
  return 0;
}

void cdc_reg_w(u8 data)
{
version(LOG_CDC) {
  error("CDC register %X write 0x%04x (%X)\n", scd.regs[0x04>>1].b.l & 0x0F, data, s68k.pc);
}
  switch (scd.regs[0x04>>1].b.l & 0x0F)
  {
    case 0x01:  /* IFCTRL */
    {
      /* pending interrupts ? */
      if (((data & BIT_DTEIEN) && !(cdc.ifstat & BIT_DTEI)) ||
          ((data & BIT_DECIEN) && !(cdc.ifstat & BIT_DECI)))
      {
        /* pending level 5 interrupt */
        scd.pending |= (1 << 5);

        /* level 5 interrupt enabled ? */
        if (scd.regs[0x32>>1].b.l & 0x20)
        {
          /* update IRQ level */
          s68k_update_irq((scd.pending & scd.regs[0x32>>1].b.l) >> 1);
        }
      }
      else if (scd.pending & (1 << 5))
      {
        /* clear pending level 5 interrupts */
        scd.pending &= ~(1 << 5);

        /* update IRQ level */
        s68k_update_irq((scd.pending & scd.regs[0x32>>1].b.l) >> 1);
      }

      /* abort any data transfer if data output is disabled */
      if (!(data & BIT_DOUTEN))
      {
        /* clear !DTBSY and !DTEN */
        cdc.ifstat |= (BIT_DTBSY | BIT_DTEN);
      }

      cdc.ifctrl = data;
      scd.regs[0x04>>1].b.l = 0x02;
      break;
    }

    case 0x02:  /* DBCL */
      cdc.dbc.b.l = data;
      scd.regs[0x04>>1].b.l = 0x03;
      break;

    case 0x03:  /* DBCH */
      cdc.dbc.b.h = data;
      scd.regs[0x04>>1].b.l = 0x04;
      break;

    case 0x04:  /* DACL */
      cdc.dac.b.l = data;
      scd.regs[0x04>>1].b.l = 0x05;
      break;

    case 0x05:  /* DACH */
      cdc.dac.b.h = data;
      scd.regs[0x04>>1].b.l = 0x06;
      break;

    case 0x06:  /* DTRG */
    {
      /* start data transfer if data output is enabled */
      if (cdc.ifctrl & BIT_DOUTEN)
      {
        /* set !DTBSY */
        cdc.ifstat &= ~BIT_DTBSY;

        /* clear DBCH bits 4-7 */
        cdc.dbc.b.h &= 0x0f;

        /* clear EDT & DSR bits (SCD register $04) */
        scd.regs[0x04>>1].b.h &= 0x07;

        /* setup data transfer destination */
        switch (scd.regs[0x04>>1].b.h & 0x07)
        {
          case 2: /* MAIN-CPU host read */
          case 3: /* SUB-CPU host read */
          {
            /* set !DTEN */
            cdc.ifstat &= ~BIT_DTEN;

            /* set DSR bit (register $04) */
            scd.regs[0x04>>1].b.h |= 0x40;
            break;
          }

          case 4: /* PCM RAM DMA */
          {
            cdc.dma_w = pcm_ram_dma_w;
            break;
          }

          case 5: /* PRG-RAM DMA */
          {
            cdc.dma_w = prg_ram_dma_w;
            break;
          }

          case 7: /* WORD-RAM DMA */
          {
            /* check memory mode */
            if (scd.regs[0x02 >> 1].b.l & 0x04)
            {
              /* 1M mode */
              if (scd.regs[0x02 >> 1].b.l & 0x01)
              {
                /* Word-RAM bank 0 is assigned to SUB-CPU */
                cdc.dma_w = word_ram_0_dma_w;
              }
              else
              {
                /* Word-RAM bank 1 is assigned to SUB-CPU */
                cdc.dma_w = word_ram_1_dma_w;
              }
            }
            else
            {
              /* 2M mode */
              if (scd.regs[0x02 >> 1].b.l & 0x02)
              {
                /* only process DMA if Word-RAM is assigned to SUB-CPU */
                cdc.dma_w = word_ram_2M_dma_w;
              }
            }
            break;
          }

          default: /* invalid */
          {
    version(LOG_CDC) {
            error("invalid CDC tranfer destination (%d)\n", scd.regs[0x04>>1].b.h & 0x07);
    }
            break;
          }
        }
      }

      scd.regs[0x04>>1].b.l = 0x07;
      break;
    }

    case 0x07:  /* DTACK */
    {
      /* clear pending data transfer end interrupt */
      cdc.ifstat |= BIT_DTEI;

      /* clear DBCH bits 4-7 */
      cdc.dbc.b.h &= 0x0f;

      scd.regs[0x04>>1].b.l = 0x08;
      break;
    }

    case 0x08:  /* WAL */
      cdc.wa.b.l = data;
      scd.regs[0x04>>1].b.l = 0x09;
      break;

    case 0x09:  /* WAH */
      cdc.wa.b.h = data;
      scd.regs[0x04>>1].b.l = 0x0a;
      break;

    case 0x0a:  /* CTRL0 */
    {
      /* set CRCOK bit only if decoding is enabled */
      cdc.stat[0] = data & BIT_DECEN;

      /* update decoding mode */
      if (data & BIT_AUTORQ)
      {
        /* set MODE bit according to CTRL1 register & clear FORM bit */
        cdc.stat[2] = cdc.ctrl[1] & BIT_MODRQ;
      }
      else 
      {
        /* set MODE & FORM bits according to CTRL1 register */
        cdc.stat[2] = cdc.ctrl[1] & (BIT_MODRQ | BIT_FORMRQ);
      }

      cdc.ctrl[0] = data;
      scd.regs[0x04>>1].b.l = 0x0b;
      break;
    }

    case 0x0b:  /* CTRL1 */
    {
      /* update decoding mode */
      if (cdc.ctrl[0] & BIT_AUTORQ)
      {
        /* set MODE bit according to CTRL1 register & clear FORM bit */
        cdc.stat[2] = data & BIT_MODRQ;
      }
      else 
      {
        /* set MODE & FORM bits according to CTRL1 register */
        cdc.stat[2] = data & (BIT_MODRQ | BIT_FORMRQ);
      }

      cdc.ctrl[1] = data;
      scd.regs[0x04>>1].b.l = 0x0c;
      break;
    }

    case 0x0c:  /* PTL */
      cdc.pt.b.l = data;
      scd.regs[0x04>>1].b.l = 0x0d;
      break;
  
    case 0x0d:  /* PTH */
      cdc.pt.b.h = data;
      scd.regs[0x04>>1].b.l = 0x0e;
      break;

    case 0x0e:  /* CTRL2 (unused) */
      scd.regs[0x04>>1].b.l = 0x0f;
      break;

    case 0x0f:  /* RESET */
      cdc_reset();
      break;

    default:  /* by default, SBOUT is not used */
      break;
  }
}

u8 cdc_reg_r()
{
  switch (scd.regs[0x04>>1].b.l & 0x0F)
  {
    case 0x01:  /* IFSTAT */
      scd.regs[0x04>>1].b.l = 0x02;
      return cdc.ifstat;

    case 0x02:  /* DBCL */
      scd.regs[0x04>>1].b.l = 0x03;
      return cdc.dbc.b.l;

    case 0x03:  /* DBCH */
      scd.regs[0x04>>1].b.l = 0x04;
      return cdc.dbc.b.h;

    case 0x04:  /* HEAD0 */
      scd.regs[0x04>>1].b.l = 0x05;
      return cdc.head[cdc.ctrl[1] & BIT_SHDREN][0];

    case 0x05:  /* HEAD1 */
      scd.regs[0x04>>1].b.l = 0x06;
      return cdc.head[cdc.ctrl[1] & BIT_SHDREN][1];

    case 0x06:  /* HEAD2 */
      scd.regs[0x04>>1].b.l = 0x07;
      return cdc.head[cdc.ctrl[1] & BIT_SHDREN][2];

    case 0x07:  /* HEAD3 */
      scd.regs[0x04>>1].b.l = 0x08;
      return cdc.head[cdc.ctrl[1] & BIT_SHDREN][3];

    case 0x08:  /* PTL */
      scd.regs[0x04>>1].b.l = 0x09;
      return cdc.pt.b.l;

    case 0x09:  /* PTH */
      scd.regs[0x04>>1].b.l = 0x0a;
      return cdc.pt.b.h;

    case 0x0a:  /* WAL */
      scd.regs[0x04>>1].b.l = 0x0b;
      return cdc.wa.b.l;

    case 0x0b:  /* WAH */
      scd.regs[0x04>>1].b.l = 0x0c;
      return cdc.wa.b.h;

    case 0x0c: /* STAT0 */
      scd.regs[0x04>>1].b.l = 0x0d;
      return cdc.stat[0];

    case 0x0d: /* STAT1 (always return 0) */
      scd.regs[0x04>>1].b.l = 0x0e;
      return 0x00;

    case 0x0e:  /* STAT2 */
      scd.regs[0x04>>1].b.l = 0x0f;
      return cdc.stat[2];

    case 0x0f:  /* STAT3 */
    {
      u8 data = cdc.stat[3];

      /* clear !VALST (note: this is not 100% correct but BIOS do not seem to care) */
      cdc.stat[3] = BIT_VALST;

      /* clear pending decoder interrupt */
      cdc.ifstat |= BIT_DECI;

      scd.regs[0x04>>1].b.l = 0x00;
      return data;
    }

    default:  /* by default, COMIN is always empty */
      return 0xff;
  }
}

u16 cdc_host_r()
{
  /* check if data is available */
  if (!(cdc.ifstat & BIT_DTEN))
  {
    /* read data word from CDC RAM buffer */
    u16 data = *cast(u16 *)(cdc.ram + (cdc.dac.w & 0x3ffe));

version(LSB_FIRST) {
    /* source data is stored in big endian format */
    data = ((data >> 8) | (data << 8)) & 0xffff;
}

version(LOG_CDC) {
    error("CDC host read 0x%04x -> 0x%04x (dbc=0x%x) (%X)\n", cdc.dac.w, data, cdc.dbc.w, s68k.pc);
}
 
    /* increment data address counter */
    cdc.dac.w += 2;

    /* decrement data byte counter */
    cdc.dbc.w -= 2;

    /* end of transfer ? */
    if (cast(s16)cdc.dbc.w <= 0)
    {
      /* reset data byte counter (DBCH bits 4-7 should be set to 1) */
      cdc.dbc.w = 0xf000;

      /* clear !DTEN and !DTBSY */
      cdc.ifstat |= (BIT_DTBSY | BIT_DTEN);

      /* pending Data Transfer End interrupt */
      cdc.ifstat &= ~BIT_DTEI;

      /* Data Transfer End interrupt enabled ? */
      if (cdc.ifctrl & BIT_DTEIEN)
      {
        /* pending level 5 interrupt */
        scd.pending |= (1 << 5);

        /* level 5 interrupt enabled ? */
        if (scd.regs[0x32>>1].b.l & 0x20)
        {
          /* update IRQ level */
          s68k_update_irq((scd.pending & scd.regs[0x32>>1].b.l) >> 1);
        }
      }

      /* clear DSR bit & set EDT bit (SCD register $04) */
      scd.regs[0x04>>1].b.h = (scd.regs[0x04>>1].b.h & 0x07) | 0x80;
    }

    return data;
  }

version(LOG_CDC) {
  error("error reading CDC host (data transfer disabled)\n");
}
  return 0xffff;
}
