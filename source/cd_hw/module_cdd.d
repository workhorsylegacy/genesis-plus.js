/***************************************************************************************
 *  Genesis Plus
 *  CD drive processor & CD-DA fader
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
import blip_buf;
import module_scd;

ref cdd_t cdd() { return scd.cdd_hw; }

/* CDD status */
const int NO_DISC  = 0x00;
const int CD_PLAY  = 0x01;
const int CD_SEEK  = 0x02;
const int CD_SCAN  = 0x03;
const int CD_READY = 0x04;
const int CD_OPEN  = 0x05; /* similar to 0x0E ? */
const int CD_STOP  = 0x09;
const int CD_END   = 0x0C;

/* CD blocks scanning speed */
const int CD_SCAN_SPEED = 30;

const int CD_MAX_TRACKS = 100;

/* CD track */
struct track_t
{
  FILE *fd;
  s32 offset;
  s32 start;
  s32 end;
}

/* CD TOC */
struct toc_t
{
  s32 end;
  s32 last;
  track_t tracks[CD_MAX_TRACKS];
}

/* CDD hardware */
struct cdd_t
{
  u32 cycles;
  u32 latency;
  s32 loaded;
  s32 index;
  s32 lba;
  s32 scanOffset;
  s32 volume;
  u8 status;
  u16 sectorSize;
  toc_t toc;
  s16 audio[2];
}

/* BCD conversion lookup tables */
static const u8[100] lut_BCD_8 =
[
  0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 
  0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 
  0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 
  0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 
  0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 
  0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 
  0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 
  0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 
  0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 
  0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 
];

static const u16[100] lut_BCD_16 =
[
  0x0000, 0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0x0008, 0x0009, 
  0x0100, 0x0101, 0x0102, 0x0103, 0x0104, 0x0105, 0x0106, 0x0107, 0x0108, 0x0109, 
  0x0200, 0x0201, 0x0202, 0x0203, 0x0204, 0x0205, 0x0206, 0x0207, 0x0208, 0x0209, 
  0x0300, 0x0301, 0x0302, 0x0303, 0x0304, 0x0305, 0x0306, 0x0307, 0x0308, 0x0309, 
  0x0400, 0x0401, 0x0402, 0x0403, 0x0404, 0x0405, 0x0406, 0x0407, 0x0408, 0x0409, 
  0x0500, 0x0501, 0x0502, 0x0503, 0x0504, 0x0505, 0x0506, 0x0507, 0x0508, 0x0509, 
  0x0600, 0x0601, 0x0602, 0x0603, 0x0604, 0x0605, 0x0606, 0x0607, 0x0608, 0x0609, 
  0x0700, 0x0701, 0x0702, 0x0703, 0x0704, 0x0705, 0x0706, 0x0707, 0x0708, 0x0709, 
  0x0800, 0x0801, 0x0802, 0x0803, 0x0804, 0x0805, 0x0806, 0x0807, 0x0808, 0x0809, 
  0x0900, 0x0901, 0x0902, 0x0903, 0x0904, 0x0905, 0x0906, 0x0907, 0x0908, 0x0909, 
];

/* pre-build TOC */
static const u16[21] toc_snatcher =
[
  56014,   495, 10120, 20555, 1580, 5417, 12502, 16090,  6553, 9681,
   8148, 20228,  8622,  6142, 5858, 1287,  7424,  3535, 31697, 2485,
  31380
];

static const u16[52] toc_lunar =
[
  5422, 1057, 7932, 5401, 6380, 6592, 5862,  5937, 5478, 5870,
  6673, 6613, 6429, 4996, 4977, 5657, 3720,  5892, 3140, 3263,
  6351, 5187, 3249, 1464, 1596, 1750, 1751,  6599, 4578, 5205,
  1550, 1827, 2328, 1346, 1569, 1613, 7199,  4928, 1656, 2549,
  1875, 3901, 1850, 2399, 2028, 1724, 4889, 14551, 1184, 2132,
  685, 3167
];

static const u32[15] toc_shadow =
[
  10226, 70054, 11100, 12532, 12444, 11923, 10059, 10167, 10138, 13792,
  11637,  2547,  2521,  3856, 900
];

static const u32[13] toc_dungeon =
[
  2250, 22950, 16350, 24900, 13875, 19950, 13800, 15375, 17400, 17100,
  3325,  6825, 25275
];

static const u32[26] toc_ffight =
[
  11994, 9742, 10136, 9685, 9553, 14588, 9430, 8721, 9975, 9764,
  9704, 12796, 585, 754, 951, 624, 9047, 1068, 817, 9191, 1024,
  14562, 10320, 8627, 3795, 3047
];

static const u32[29] toc_ffightj =
[
  11994, 9752, 10119, 9690, 9567, 14575, 9431, 8731, 9965, 9763,
  9716, 12791, 579, 751, 958, 630, 9050, 1052, 825, 9193, 1026,
  14553, 9834, 10542, 1699, 1792, 1781, 3783, 3052
];

/* supported WAVE file header (16-bit stereo samples @44.1kHz) */
static const u8[32] waveHeader =
[
  0x57,0x41,0x56,0x45,0x66,0x6d,0x74,0x20,0x10,0x00,0x00,0x00,0x01,0x00,0x02,0x00,
  0x44,0xac,0x00,0x00,0x10,0xb1,0x02,0x00,0x04,0x00,0x10,0x00,0x64,0x61,0x74,0x61
];

/* supported WAVE file extensions */
static const string[10] extensions =
[
  "%02d.wav",
  " %02d.wav",
  "-%02d.wav",
  "_%02d.wav",
  " - %02d.wav",
  "%d.wav",
  " %d.wav",
  "-%d.wav",
  "_%d.wav",
  " - %d.wav"
];

static blip_t[2] blip;

void cdd_init(blip_t* left, blip_t* right)
{
  /* CD-DA is running by default at 44100 Hz */
  /* Audio stream is resampled to desired rate using Blip Buffer */
  blip[0] = left;
  blip[1] = right;
  blip_set_rates(left, 44100, snd.sample_rate);
  blip_set_rates(right, 44100, snd.sample_rate);
}

void cdd_reset()
{
  /* reset cycle counter */
  cdd.cycles = 0;
  
  /* reset drive access latency */
  cdd.latency = 0;
  
  /* reset track index */
  cdd.index = 0;
  
  /* reset logical block address */
  cdd.lba = 0;

  /* reset status */
  cdd.status = cdd.loaded ? CD_STOP : NO_DISC;
  
  /* reset CD-DA fader (full volume) */
  cdd.volume = 0x400;

  /* clear CD-DA output */
  cdd.audio[0] = cdd.audio[1] = 0;
}

s32 cdd_context_save(u8 *state)
{
  s32 bufferptr = 0;

  save_param(&bufferptr, state, &cdd.cycles, sizeof(cdd.cycles));
  save_param(&bufferptr, state, &cdd.latency, sizeof(cdd.latency));
  save_param(&bufferptr, state, &cdd.index, sizeof(cdd.index));
  save_param(&bufferptr, state, &cdd.lba, sizeof(cdd.lba));
  save_param(&bufferptr, state, &cdd.scanOffset, sizeof(cdd.scanOffset));
  save_param(&bufferptr, state, &cdd.volume, sizeof(cdd.volume));
  save_param(&bufferptr, state, &cdd.status, sizeof(cdd.status));

  return bufferptr;
}

s32 cdd_context_load(u8 *state)
{
  s32 lba;
  s32 bufferptr = 0;

  load_param(&bufferptr, state, &cdd.cycles, sizeof(cdd.cycles));
  load_param(&bufferptr, state, &cdd.latency, sizeof(cdd.latency));
  load_param(&bufferptr, state, &cdd.index, sizeof(cdd.index));
  load_param(&bufferptr, state, &cdd.lba, sizeof(cdd.lba));
  load_param(&bufferptr, state, &cdd.scanOffset, sizeof(cdd.scanOffset));
  load_param(&bufferptr, state, &cdd.volume, sizeof(cdd.volume));
  load_param(&bufferptr, state, &cdd.status, sizeof(cdd.status));

  /* adjust current LBA within track limit */
  lba = cdd.lba;
  if (lba < cdd.toc.tracks[cdd.index].start)
  {
    lba = cdd.toc.tracks[cdd.index].start;
  }

  /* seek to current track position */
  if (!cdd.index)
  {
    /* DATA track */
    if (cdd.toc.tracks[0].fd)
    {
      fseek(cdd.toc.tracks[0].fd, lba * cdd.sectorSize, SEEK_SET);
    }
  }
  else if (cdd.toc.tracks[cdd.index].fd)
  {
    /* AUDIO track */
    fseek(cdd.toc.tracks[cdd.index].fd, (lba * 2352) - cdd.toc.tracks[cdd.index].offset, SEEK_SET);
  }

  return bufferptr;
}

s32 cdd_load(char *filename, char *header)
{
  char[256] fname;
  char[128] line;
  char *ptr = 0;
  char *lptr;
  FILE *fd;

  /* first unmount any loaded disc */
  cdd_unload();

  /* open file */
  fd = fopen(filename, "rb");

  /* save a copy of base filename */
  if (strlen(filename) < 256)
  {
    strncpy(fname, filename, strlen(filename));
    fname[strlen(filename)] = 0;
  }

  /* autodetect .cue file */
  if (!memcmp(".cue", &filename[strlen(filename) - 4], 4) || !memcmp(".CUE", &filename[strlen(filename) - 4], 4))
  {
    if (fd)
    {
      /* find first FILE command */
      lptr = strstr(line, "FILE");
      while (!lptr)
      {
        if (fgets(line, 128, fd) == null)
        {
          break;
        }
        lptr = strstr(line, "FILE");
      }

      /* get BINARY file name  */
      if (lptr && strstr(line, " BINARY"))
      {
        /* skip "FILE" attribute */
        lptr += 4;

        /* skip DOUBLE QUOTE or SPACE characters */
        while ((*lptr == 0x20) || (*lptr == '\"')) lptr++;

        /* set pointer at the end of filepath */
        ptr = fname + strlen(fname) - 1;
        while ((ptr - fname) && (*ptr != '/') && (*ptr != '\\')) ptr--;
        if (ptr - fname) ptr++;

        /* append filename characters after filepath */
        while ((*lptr != '\"') && memcmp(lptr, " BINARY", 7))
        {
          *ptr++ = *lptr++;
        }
        *ptr = 0;

        /* open file & initialize DATA track file descriptor */
        cdd.toc.tracks[0].fd = fopen(fname, "rb");
      }
      else
      {
        /* close .cue file */
        fclose(fd);

        /* invalid .cue file */
        return -1;
      }
    }
  }
  else
  {
    /* initialize DATA track file descriptor */
    cdd.toc.tracks[0].fd = fd;

    /* automatically try to open associated .cue file  */
    strncpy(&fname[strlen(fname) - 4], ".cue", 4);
    fd = fopen(fname, "rb");
  }

  if (!cdd.toc.tracks[0].fd)
  {
    /* close any opened .cue file */
    if (fd) fclose(fd);

    /* error opening file */
    return -1;
  }

  /* read first 16 bytes */
  fread(header, 0x10, 1, cdd.toc.tracks[0].fd);

  /* look for valid CD image ID string */
  if (memcmp("SEGADISCSYSTEM", header, 14))
  {    
    /* if not found, read next 16 bytes */
    fread(header, 0x10, 1, cdd.toc.tracks[0].fd);

    /* look again for valid CD image ID string */
    if (memcmp("SEGADISCSYSTEM", header, 14))
    {
      /* close any opened .cue file */
      if (fd) fclose(fd);

      /* close binary file */
      fclose(cdd.toc.tracks[0].fd);

      /* not a CD image file */
      return 0;
    }

    /* BIN format (2352 bytes data blocks) */
    cdd.sectorSize = 2352;
  }
  else
  {
    /* ISO format (2048 bytes data blocks) */
    cdd.sectorSize = 2048;
  }

  /* read CD image header + security code */
  fread(header + 0x10, 0x200, 1, cdd.toc.tracks[0].fd);

  /* DATA track length (default) */
  fseek(cdd.toc.tracks[0].fd, 0, SEEK_END);
  cdd.toc.tracks[0].end = ftell(cdd.toc.tracks[0].fd) / cdd.sectorSize;
  
  /* DATA track start (logical block 0) */
  fseek(cdd.toc.tracks[0].fd, 0, SEEK_SET);
  cdd.toc.tracks[0].start = 0;

  /* initialize TOC */
  cdd.toc.end = cdd.toc.tracks[0].end;
  cdd.toc.last = 1;

  /* automatically retrieve audio tracks infos from .cue file */
  if (fd)
  {
    s32 pregap = 0;
    s32 mm, ss, bb;
        
    /* skip first (DATA) track */
    while (!strstr(line, "INDEX 01") && !strstr(line, "INDEX 1"))
    {
      if (fgets(line, 128, fd) == null)
      {
        break;
      }
    }

    /* read next lines until end of file */
    while (fgets(line, 128, fd) != null)
    {
      /* skip any SPACE characters */
      lptr = line;
      while (*lptr == 0x20) lptr++;

      /* decode FILE commands */
      if (!(memcmp(lptr, "FILE", 4)))
      {
        /* check supported file types */
        if (!strstr(lptr," BINARY") && !strstr(lptr," WAV"))
        {
          /* unsupported file type */
          break;
        }

        /* skip "FILE" attribute */
        lptr += 4;

        /* skip DOUBLE QUOTE or SPACE characters */
        while ((*lptr == 0x20) || (*lptr == '\"')) lptr++;

        /* set pointer at the end of filepath */
        ptr = fname + strlen(fname) - 1;
        while ((ptr - fname) && (*ptr != '/') && (*ptr != '\\')) ptr--;
        if (ptr - fname) ptr++;

        /* append filename characters after filepath */
        while ((*lptr != '\"') && memcmp(lptr, " BINARY", 7) && memcmp(lptr, " WAV", 4))
        {
          *ptr++ = *lptr++;
        }
        *ptr = 0;

        /* open file & initialize AUDIO track file descriptor */
        cdd.toc.tracks[cdd.toc.last].fd = fopen(fname, "rb");
        if (!cdd.toc.tracks[cdd.toc.last].fd)
        {
          /* error opening file */
          break;
        }

        /* reset current file PREGAP length */
        pregap = 0;
      }

      /* decode TRACK commands */
      else if ((sscanf(lptr, "TRACK %02d AUDIO", &bb)) || (sscanf(lptr, "TRACK %d AUDIO", &bb)))
      {
        /* check track number */
        if (bb != (cdd.toc.last + 1))
        {
          /* close any opened file */
          if (cdd.toc.tracks[cdd.toc.last].fd)
          {
            fclose(cdd.toc.tracks[cdd.toc.last].fd);
          }

          /* missing tracks */
          break;
        }

        /* check if a single file is used for all tracks */
        if (!cdd.toc.tracks[cdd.toc.last].fd)
        {
          /* clear previous track end index */
          cdd.toc.tracks[cdd.toc.last - 1].end = 0;
        }
      }

      /* decode PREGAP commands */
      else if (sscanf(lptr, "PREGAP %02d:%02d:%02d", &mm, &ss, &bb) == 3)
      {
        /* increment current file PREGAP length */
        pregap += bb + ss*75 + mm*60*75;
      }

      /* decode INDEX commands */
      else if ((sscanf(lptr, "INDEX 00 %02d:%02d:%02d", &mm, &ss, &bb) == 3) ||
                (sscanf(lptr, "INDEX 0 %02d:%02d:%02d", &mm, &ss, &bb) == 3))
      {
        /* check if a single file is used for all tracks */
        if (!cdd.toc.tracks[cdd.toc.last].fd)
        {
          /* set previous track end index */
          cdd.toc.tracks[cdd.toc.last - 1].end = bb + ss*75 + mm*60*75 + pregap;
        }
      }
      else if ((sscanf(lptr, "INDEX 01 %02d:%02d:%02d", &mm, &ss, &bb) == 3) ||
                (sscanf(lptr, "INDEX 1 %02d:%02d:%02d", &mm, &ss, &bb) == 3))
      {
        char id[4];

        /* set file read offset for current track with current file PREGAP length */
        cdd.toc.tracks[cdd.toc.last].offset = pregap * 2352;

        /* check if a single file is used for all tracks */
        if (!cdd.toc.tracks[cdd.toc.last].fd)
        {
          /* previous track end index already set (through INDEX00 command) ? */
          if (cdd.toc.tracks[cdd.toc.last - 1].end == 0)
          {
            /* if not, set previous track end index */
            cdd.toc.tracks[cdd.toc.last - 1].end = bb + ss*75 + mm*60*75;
          }

          /* current track start index */
          cdd.toc.tracks[cdd.toc.last].start = bb + ss*75 + mm*60*75 + pregap;

          /* use common file descriptor */
          cdd.toc.tracks[cdd.toc.last].fd = cdd.toc.tracks[0].fd;
        }
        else
        {
          /* adjust file read offset with previous track end index */
          cdd.toc.tracks[cdd.toc.last].offset += cdd.toc.end * 2352;

          /* current track start index */
          cdd.toc.tracks[cdd.toc.last].start = (cdd.toc.tracks[cdd.toc.last].offset / 2352) + bb + ss*75 + mm*60*75;

          /* current track end index */
          fseek(cdd.toc.tracks[cdd.toc.last].fd, 0, SEEK_END);
          cdd.toc.tracks[cdd.toc.last].end = cdd.toc.tracks[cdd.toc.last].start + ((ftell(cdd.toc.tracks[cdd.toc.last].fd) + 2351) / 2352);

          /* update TOC end */
          cdd.toc.end = cdd.toc.tracks[cdd.toc.last].end;
        }

        /* autodetect WAVE header (note: sometime found in BIN files as well) */
        fseek(cdd.toc.tracks[cdd.toc.last].fd, (cdd.toc.tracks[cdd.toc.last].start * 2352) - cdd.toc.tracks[cdd.toc.last].offset, SEEK_SET);
        fread(id, 4, 1, cdd.toc.tracks[cdd.toc.last].fd);
        if (!memcmp(id,"RIFF",4))
        {
          /* adjust file read offset for current track with WAVE header length */
          cdd.toc.tracks[cdd.toc.last].offset -= (ftell(cdd.toc.tracks[cdd.toc.last].fd) + 40);
        }
        fseek(cdd.toc.tracks[cdd.toc.last].fd, 0, SEEK_SET);
     
        /* increment track number */
        cdd.toc.last++;
      }
    }

    /* check if a single file is used for all tracks */
    if (cdd.toc.tracks[cdd.toc.last - 1].fd == cdd.toc.tracks[0].fd)
    {
      /* adjust TOC end */
      cdd.toc.end += pregap;

      /* last track end index */
      cdd.toc.tracks[cdd.toc.last - 1].end = cdd.toc.end;
    }

    /* close .cue file */
    fclose(fd);
  }

  /* ISO+WAV audio tracks auto-detection */
  else if (cdd.sectorSize == 2048)
  {
    s32 i, offset;

    /* set pointer at the end of filename */
    ptr = fname + strlen(fname) - 4;

    /* auto-detect track file extensions */
    for (i=0; i<10; i++)
    {
      /* auto-detect bad rips with wrong track indexes */
      sprintf(ptr, extensions[i], 1);
      fd = fopen(fname, "rb");
      if (fd)
      {
        offset = 0;
        break;
      }

      sprintf(ptr, extensions[i], 2);
      fd = fopen(fname, "rb");
      if (fd)
      {
        offset = 1;
        break;
      }
    }

    /* repeat until no more valid track files can be found */
    while (fd)
    {
      u8[32] head;

      /* make sure this is a valid WAVE file (16-bit stereo @44.1kHz only) */
      fseek(fd, 8, SEEK_SET);
      fread(head, 32, 1, fd);
      if (!memcmp(head, waveHeader, 32))
      {
        /* initialize current track file descriptor */
        cdd.toc.tracks[cdd.toc.last].fd = fd;

        /* initialize current track start index with previous track end index */
        cdd.toc.tracks[cdd.toc.last].start = cdd.toc.end;

        /* add default 2s PAUSE */
        cdd.toc.tracks[cdd.toc.last].start += 150;

        /* current track end index */
        fseek(fd, 0, SEEK_END);
        cdd.toc.tracks[cdd.toc.last].end = cdd.toc.tracks[cdd.toc.last].start + ((ftell(fd) + 2351) / 2352);

        /* initialize file read offset for current track */
        cdd.toc.tracks[cdd.toc.last].offset = cdd.toc.tracks[cdd.toc.last].start * 2352;

        /* auto-detect PAUSE within audio files */
        fseek(fd, 100 * 2352, SEEK_SET);
        fread(head, 4, 1, fd);
        if (*cast(s32 *)head == 0)
        {
          /* assume 2s PAUSE is included at the beginning of the file */
          cdd.toc.tracks[cdd.toc.last].offset -= 150 * 2352;
          cdd.toc.tracks[cdd.toc.last].end -= 150;
        }
        fseek(fd, 0, SEEK_SET);

        /* update TOC end */
        cdd.toc.end = cdd.toc.tracks[cdd.toc.last].end;

        /* adjust file read offset for current track with WAVE header length */
        cdd.toc.tracks[cdd.toc.last].offset -= 44;

        /* increment track number */
        cdd.toc.last++;
      }
      else
      {
        /* invalid file type */
        fclose(fd);
        break;
      }

      /* try to open next audio track file */
      sprintf(ptr, extensions[i], cdd.toc.last + offset);
      fd = fopen(fname, "rb");
    }
  }

  /* Simulate audio tracks if none found */
  if (cdd.toc.last == 1)
  {
    /* Some games require exact TOC infos */
    if (strstr(header + 0x180,"T-95035") != null)
    {
      /* Snatcher */
      cdd.toc.last = cdd.toc.end = 0;
      do
      {
        cdd.toc.tracks[cdd.toc.last].start = cdd.toc.end;
        cdd.toc.tracks[cdd.toc.last].end = cdd.toc.tracks[cdd.toc.last].start + toc_snatcher[cdd.toc.last];
        cdd.toc.end = cdd.toc.tracks[cdd.toc.last].end;
        cdd.toc.last++;
      }
      while (cdd.toc.last < 21);
    }
    else if (strstr(header + 0x180,"T-127015") != null)
    {
      /* Lunar - The Silver Star */
      cdd.toc.last = cdd.toc.end = 0;
      do
      {
        cdd.toc.tracks[cdd.toc.last].start = cdd.toc.end;
        cdd.toc.tracks[cdd.toc.last].end = cdd.toc.tracks[cdd.toc.last].start + toc_lunar[cdd.toc.last];
        cdd.toc.end = cdd.toc.tracks[cdd.toc.last].end;
        cdd.toc.last++;
      }
      while (cdd.toc.last < 52);
    }
    else if (strstr(header + 0x180,"T-113045") != null)
    {
      /* Shadow of the Beast II */
      cdd.toc.last = cdd.toc.end = 0;
      do
      {
        cdd.toc.tracks[cdd.toc.last].start = cdd.toc.end;
        cdd.toc.tracks[cdd.toc.last].end = cdd.toc.tracks[cdd.toc.last].start + toc_shadow[cdd.toc.last];
        cdd.toc.end = cdd.toc.tracks[cdd.toc.last].end;
        cdd.toc.last++;
      }
      while (cdd.toc.last < 15);
    }
    else if (strstr(header + 0x180,"T-143025") != null)
    {
      /* Dungeon Explorer */
      cdd.toc.last = cdd.toc.end = 0;
      do
      {
        cdd.toc.tracks[cdd.toc.last].start = cdd.toc.end;
        cdd.toc.tracks[cdd.toc.last].end = cdd.toc.tracks[cdd.toc.last].start + toc_dungeon[cdd.toc.last];
        cdd.toc.end = cdd.toc.tracks[cdd.toc.last].end;
        cdd.toc.last++;
      }
      while (cdd.toc.last < 13);
    }
    else if (strstr(header + 0x180,"MK-4410") != null)
    {
      /* Final Fight CD (USA, Europe) */
      cdd.toc.last = cdd.toc.end = 0;
      do
      {
        cdd.toc.tracks[cdd.toc.last].start = cdd.toc.end;
        cdd.toc.tracks[cdd.toc.last].end = cdd.toc.tracks[cdd.toc.last].start + toc_ffight[cdd.toc.last];
        cdd.toc.end = cdd.toc.tracks[cdd.toc.last].end;
        cdd.toc.last++;
      }
      while (cdd.toc.last < 26);
    }
    else if (strstr(header + 0x180,"G-6013") != null)
    {
      /* Final Fight CD (Japan) */
      cdd.toc.last = cdd.toc.end = 0;
      do
      {
        cdd.toc.tracks[cdd.toc.last].start = cdd.toc.end;
        cdd.toc.tracks[cdd.toc.last].end = cdd.toc.tracks[cdd.toc.last].start + toc_ffightj[cdd.toc.last];
        cdd.toc.end = cdd.toc.tracks[cdd.toc.last].end;
        cdd.toc.last++;
      }
      while (cdd.toc.last < 29);
    }
    else
    {
      /* default TOC (99 tracks & 2s per audio tracks) */
      do
      {
        cdd.toc.tracks[cdd.toc.last].start = cdd.toc.end + 2*75;
        cdd.toc.tracks[cdd.toc.last].end = cdd.toc.tracks[cdd.toc.last].start + 2*75;
        cdd.toc.end = cdd.toc.tracks[cdd.toc.last].end;
        cdd.toc.last++;
      }
      while ((cdd.toc.last < 99) && (cdd.toc.end < 56*60*75));
    }
  }

  /* Lead-out */
  cdd.toc.tracks[cdd.toc.last].start = cdd.toc.end;

  /* CD loaded */
  cdd.loaded = 1;
  return 1;
}

void cdd_unload()
{
  if (cdd.loaded)
  {
    s32 i;

    /* close CD tracks */
    for (i=0; i<cdd.toc.last; i++)
    {
      if (cdd.toc.tracks[i].fd)
      {
        fclose(cdd.toc.tracks[i].fd);

        /* detect single file images */
        if (cdd.toc.tracks[i+1].fd == cdd.toc.tracks[i].fd)
        {
          /* exit loop */
          i = cdd.toc.last;
        }
      }
    }

    /* CD unloaded */
    cdd.loaded = 0;
  }

  /* reset TOC */
  cdd.toc = toc_t.init;
    
  /* unknown CD image file format */
  cdd.sectorSize = 0;
}

void cdd_read_data(u8 *dst)
{
  /* only read DATA track sectors */
  if ((cdd.lba >= 0) && (cdd.lba < cdd.toc.tracks[0].end))
  {
    /* BIN format ? */
    if (cdd.sectorSize == 2352)
    {
      /* skip 16-byte header */
      fseek(cdd.toc.tracks[0].fd, cdd.lba * 2352 + 16, SEEK_SET);
    }

    /* read sector data (Mode 1 = 2048 bytes) */
    fread(dst, 2048, 1, cdd.toc.tracks[0].fd);
  }
}

void cdd_read_audio(u32 samples)
{
  /* previous audio outputs */
  s16 l = cdd.audio[0];
  s16 r = cdd.audio[1];

  /* get number of internal clocks (samples) needed */
  samples = blip_clocks_needed(blip[0], samples);

  /* audio track playing ? */
  if (!scd.regs[0x36>>1].b.h && cdd.toc.tracks[cdd.index].fd)
  {
    s32 i, mul, delta;

    /* current CD-DA fader volume */
    s32 curVol = cdd.volume;

    /* CD-DA fader volume setup (0-1024) */
    s32 endVol = scd.regs[0x34>>1].w >> 4;

    /* use CDD buffer as temporary buffer */
version(LSB_FIRST) {
    s16 *ptr = cast(s16 *) (cdc.ram);
} else {
    u8 *ptr = cdc.ram;
}

    /* read samples from current block */
    fread(cdc.ram, 1, samples * 4, cdd.toc.tracks[cdd.index].fd);

    /* process 16-bit (little-endian) stereo samples */
    for (i=0; i<samples; i++)
    {
      /* CD-DA fader multiplier (cf. LC7883 datasheet) */
      /* (MIN) 0,1,2,3,4,8,12,16,20...,1020,1024 (MAX) */
      mul = (curVol & 0x7fc) ? (curVol & 0x7fc) : (curVol & 0x03);

      /* left channel */
version(LSB_FIRST) {
      delta = ((ptr[0] * mul) / 1024) - l;
      ptr++;
} else {
      delta = ((cast(s16)((ptr[0] + ptr[1]*256)) * mul) / 1024) - l;
      ptr += 2;
}
      l += delta;
      blip_add_delta_fast(blip[0], i, delta);

      /* right channel */
version(LSB_FIRST) {
      delta = ((ptr[0] * mul) / 1024) - r;
      ptr++;
} else {
      delta = ((cast(s16)((ptr[0] + ptr[1]*256)) * mul) / 1024) - r;
      ptr += 2;
}
      r += delta;
      blip_add_delta_fast(blip[1], i, delta);

      /* update CD-DA fader volume (one step/sample) */
      if (curVol < endVol)
      {
        /* fade-in */
        curVol++;
      }
      else if (curVol > endVol)
      {
        /* fade-out */
        curVol--;
      }
      else if (!curVol)
      {
        /* audio will remain muted until next setup */
        break;
      }
    }

    /* save current CD-DA fader volume */
    cdd.volume = curVol;

    /* save last audio output for next frame */
    cdd.audio[0] = l;
    cdd.audio[1] = r;
  }
  else
  {
    /* no audio output */
    if (l) blip_add_delta_fast(blip[0], 0, -l);
    if (r) blip_add_delta_fast(blip[1], 0, -r);

    /* save audio output for next frame */
    cdd.audio[0] = 0;
    cdd.audio[1] = 0;
  }

  /* end of Blip Buffer timeframe */
  blip_end_frame(blip[0], samples);
  blip_end_frame(blip[1], samples);
}


void cdd_update()
{  
version(LOG_CDD) {
  error("LBA = %d (track n0%d)(latency=%d)", cdd.lba, cdd.index, cdd.latency);
}
  
  /* seeking disc */
  if (cdd.status == CD_SEEK)
  {
    /* drive latency */
    if (cdd.latency > 0)
    {
      cdd.latency--;
      return;
    }

    /* drive is ready */
    cdd.status = CD_READY;
  }

  /* reading disc */
  else if (cdd.status == CD_PLAY)
  {
    /* drive latency */
    if (cdd.latency > 0)
    {
      cdd.latency--;
      return;
    }

    /* track type */
    if (!cdd.index)
    {
      /* DATA sector header (CD-ROM Mode 1) */
      u8 header[4];
      u32 msf = cdd.lba + 150;
      header[0] = lut_BCD_8[(msf / 75) / 60];
      header[1] = lut_BCD_8[(msf / 75) % 60];
      header[2] = lut_BCD_8[(msf % 75)];
      header[3] = 0x01;

      /* data track sector read is controlled by CDC */
      cdd.lba += cdc_decoder_update(*cast(u32 *)(header));
    }
    else if (cdd.index < cdd.toc.last)
    {
      /* check against audio track start index */
      if (cdd.lba >= cdd.toc.tracks[cdd.index].start)
      {
        /* audio track playing */
        scd.regs[0x36>>1].b.h = 0x00;
      }

      /* audio blocks are still sent to CDC as well as CD DAC/Fader */
      cdc_decoder_update(0);
 
      /* next audio block is automatically read */
      cdd.lba++;
    }
    else
    {
      cdd.status = CD_END;
      return;
    }

    /* check end of current track */
    if (cdd.lba >= cdd.toc.tracks[cdd.index].end)
    {
      /* play next track */
      cdd.index++;

      /* PAUSE between tracks */
      scd.regs[0x36>>1].b.h = 0x01;

      /* seek to current block */
      if (cdd.toc.tracks[cdd.index].fd)
      {
        if (cdd.lba < cdd.toc.tracks[cdd.index].start)
        {
          fseek(cdd.toc.tracks[cdd.index].fd, (cdd.toc.tracks[cdd.index].start * 2352) - cdd.toc.tracks[cdd.index].offset, SEEK_SET);
        }
        else
        {
          fseek(cdd.toc.tracks[cdd.index].fd, (cdd.lba * 2352) - cdd.toc.tracks[cdd.index].offset, SEEK_SET);
        }
      }
    }
  }

  /* scanning disc */
  else if (cdd.status == CD_SCAN)
  {
    /* fast-forward or fast-rewind */
    cdd.lba += cdd.scanOffset;

    /* check current track limits */
    if (cdd.lba >= cdd.toc.tracks[cdd.index].end)
    {
      /* next track */
      cdd.index++;

      /* skip directly to track start position */
      cdd.lba = cdd.toc.tracks[cdd.index].start;
    }
    else if (cdd.lba < cdd.toc.tracks[cdd.index].start)
    {
      /* previous track */
      cdd.index--;

      /* skip directly to track end position */
      cdd.lba = cdd.toc.tracks[cdd.index].end;
    }

    /* check disc limits */
    if (cdd.index < 0)
    {
      cdd.index = 0;
      cdd.lba = 0;
    }
    else if (cdd.index >= cdd.toc.last)
    {
      /* no AUDIO track playing */
      scd.regs[0x36>>1].b.h = 0x01;

      /* end of disc */
      cdd.index = cdd.toc.last;
      cdd.lba = cdd.toc.end;
    }

    /* seek to current block */
    if (!cdd.index)
    {
      /* no AUDIO track playing */
      scd.regs[0x36>>1].b.h = 0x01;

      fseek(cdd.toc.tracks[0].fd, cdd.lba * cdd.sectorSize, SEEK_SET);
    }
    else if (cdd.toc.tracks[cdd.index].fd)
    {
      /* AUDIO track playing */
      scd.regs[0x36>>1].b.h = 0x00;

      if (cdd.lba < cdd.toc.tracks[cdd.index].start)
      {
        fseek(cdd.toc.tracks[cdd.index].fd, (cdd.toc.tracks[cdd.index].start * 2352) - cdd.toc.tracks[cdd.index].offset, SEEK_SET);
      }
      else
      {
        fseek(cdd.toc.tracks[cdd.index].fd, (cdd.lba * 2352) - cdd.toc.tracks[cdd.index].offset, SEEK_SET);
      }
    }
  }
}

void cdd_process()
{
  /* Process CDD command */
  switch (scd.regs[0x42>>1].b.h & 0x0f)
  {
    case 0x00:  /* Drive Status */
    {
      /* RS1-RS8 unchanged */
      scd.regs[0x38>>1].b.h = cdd.status;
      break;
    }

    case 0x01:  /* Stop Drive */
    {
      /* update status */
      cdd.status = cdd.loaded ? CD_STOP : NO_DISC;

      /* no audio track playing */
      scd.regs[0x36>>1].b.h = 0x01;

      /* RS1-RS8 ignored, expects 0x0 ("no disc" ?) in RS0 once */
      scd.regs[0x38>>1].w = 0x0000;
      scd.regs[0x3a>>1].w = 0x0000;
      scd.regs[0x3c>>1].w = 0x0000;
      scd.regs[0x3e>>1].w = 0x0000;
      scd.regs[0x40>>1].w = 0x000f;
      return;
    }

    case 0x02:  /* Read TOC */
    {
      /* Infos automatically retrieved by CDD processor from Q-Channel */
      /* commands 0x00-0x02 (current block) and 0x03-0x05 (Lead-In) */
      switch (scd.regs[0x44>>1].b.l)
      {
        case 0x00:  /* Current Absolute Time (MM:SS:FF) */
        {
          s32 lba = cdd.lba + 150;
          scd.regs[0x38>>1].w = cdd.status << 8;
          scd.regs[0x3a>>1].w = lut_BCD_16[(lba/75)/60];
          scd.regs[0x3c>>1].w = lut_BCD_16[(lba/75)%60];
          scd.regs[0x3e>>1].w = lut_BCD_16[(lba%75)];
          scd.regs[0x40>>1].b.h = cdd.index ? 0x00 : 0x04; /* Current block flags in RS8 (bit0 = mute status, bit1: pre-emphasis status, bit2: track type) */
          break;
        }

        case 0x01:  /* Current Track Relative Time (MM:SS:FF) */
        {
          s32 lba = cdd.lba - cdd.toc.tracks[cdd.index].start;
          scd.regs[0x38>>1].w = (cdd.status << 8) | 0x01;
          scd.regs[0x3a>>1].w = lut_BCD_16[(lba/75)/60];
          scd.regs[0x3c>>1].w = lut_BCD_16[(lba/75)%60];
          scd.regs[0x3e>>1].w = lut_BCD_16[(lba%75)];
          scd.regs[0x40>>1].b.h = cdd.index ? 0x00 : 0x04; /* Current block flags in RS8 (bit0 = mute status, bit1: pre-emphasis status, bit2: track type) */
          break;
        }

        case 0x02:  /* Current Track Number */
        {
          scd.regs[0x38>>1].w = (cdd.status << 8) | 0x02;
          scd.regs[0x3a>>1].w = (cdd.index < cdd.toc.last) ? lut_BCD_16[cdd.index + 1] : 0x0A0A;
          scd.regs[0x3c>>1].w = 0x0000;
          scd.regs[0x3e>>1].w = 0x0000; /* Disk Control Code (?) in RS6 */
          scd.regs[0x40>>1].b.h = 0x00;
          break;
        }

        case 0x03:  /* Total length (MM:SS:FF) */
        {
          s32 lba = cdd.toc.end + 150;
          scd.regs[0x38>>1].w = (cdd.status << 8) | 0x03;
          scd.regs[0x3a>>1].w = lut_BCD_16[(lba/75)/60];
          scd.regs[0x3c>>1].w = lut_BCD_16[(lba/75)%60];
          scd.regs[0x3e>>1].w = lut_BCD_16[(lba%75)];
          scd.regs[0x40>>1].b.h = 0x00;
          break;
        }

        case 0x04:  /* First & Last Track Numbers */
        {
          scd.regs[0x38>>1].w = (cdd.status << 8) | 0x04;
          scd.regs[0x3a>>1].w = 0x0001;
          scd.regs[0x3c>>1].w = lut_BCD_16[cdd.toc.last];
          scd.regs[0x3e>>1].w = 0x0000; /* Drive Version (?) in RS6-RS7 */
          scd.regs[0x40>>1].b.h = 0x00;  /* Lead-In flags in RS8 (bit0 = mute status, bit1: pre-emphasis status, bit2: track type) */
          break;
        }

        case 0x05:  /* Track Start Time (MM:SS:FF) */
        {
          s32 track = scd.regs[0x46>>1].b.h * 10 + scd.regs[0x46>>1].b.l;
          s32 lba = cdd.toc.tracks[track-1].start + 150;
          scd.regs[0x38>>1].w = (cdd.status << 8) | 0x05;
          scd.regs[0x3a>>1].w = lut_BCD_16[(lba/75)/60];
          scd.regs[0x3c>>1].w = lut_BCD_16[(lba/75)%60];
          scd.regs[0x3e>>1].w = lut_BCD_16[(lba%75)];
          scd.regs[0x40>>1].b.h = track % 10;  /* Track Number (low digit) */
          if (track == 1)
          {
            /* RS6 bit 3 is set for the first (DATA) track */
            scd.regs[0x3e>>1].b.h |= 0x08;
          }
          break;
        }

        default:
        {
version(LOG_ERROR) {
          error("Unknown CDD Command %02X (%X)\n", scd.regs[0x44>>1].b.l, s68k.pc);
}
          return;
        }
      }
      break;
    }

    case 0x03:  /* Play  */
    {
      /* reset track index */
      s32 index = 0;

      /* new LBA position */
      s32 lba = ((scd.regs[0x44>>1].b.h * 10 + scd.regs[0x44>>1].b.l) * 60 + 
                 (scd.regs[0x46>>1].b.h * 10 + scd.regs[0x46>>1].b.l)) * 75 +
                 (scd.regs[0x48>>1].b.h * 10 + scd.regs[0x48>>1].b.l) - 150;

      /* CD drive latency */
      if (!cdd.latency)
      {
        /* Fixes a few games hanging during intro because they expect data to be read with some delay */
        /* Radical Rex needs at least one interrupt delay */
        /* Wolf Team games (Anet Futatabi, Cobra Command, Road Avenger & Time Gal) need at least 6 interrupts delay  */
        /* Space Adventure Cobra (2nd morgue scene) needs at least 13 interrupts delay (incl. seek time, so 6 is OK) */
        /* Jeopardy & ESPN Sunday Night NFL are picky about this as well: 10 interrupts delay (+ seek time) seems OK  */
        cdd.latency = 10;
      }

      /* CD drive seek time */
      /* max. seek time = 1.5 s = 1.5 x 75 = 112.5 CDD interrupts (rounded to 120) for 270000 sectors max on disc. */
      /* Note: This is only a rough approximation since, on real hardware, seek time is much likely not linear and */
      /* latency much larger than above value, but this model works fine for Sonic CD (track 26 playback needs to  */
      /* be enough delayed to start in sync with intro sequence, as compared with real hardware recording).        */
      if (lba > cdd.lba)
      {
        cdd.latency += (((lba - cdd.lba) * 120) / 270000);
      }
      else 
      {
        cdd.latency += (((cdd.lba - lba) * 120) / 270000);
      }

      /* update current LBA */
      cdd.lba = lba;

      /* update current track index */
      while ((cdd.toc.tracks[index].end <= lba) && (index < cdd.toc.last)) index++;
      cdd.index = index;

      /* seek to current block */
      if (!index)
      {
        /* seek DATA track */
        if (lba < 0)
        {
          fseek(cdd.toc.tracks[0].fd, 0, SEEK_SET);
        }
        else
        {
          fseek(cdd.toc.tracks[0].fd, lba * cdd.sectorSize, SEEK_SET);
        }
      }
      else if (cdd.toc.tracks[index].fd)
      {
        /* seek AUDIO track */
        if (lba < cdd.toc.tracks[index].start)
        {
          fseek(cdd.toc.tracks[index].fd, (cdd.toc.tracks[index].start * 2352) - cdd.toc.tracks[index].offset, SEEK_SET);
        }
        else
        {
          fseek(cdd.toc.tracks[index].fd, (lba * 2352) - cdd.toc.tracks[index].offset, SEEK_SET);
        }
      }

      /* no audio track playing (yet) */
      scd.regs[0x36>>1].b.h = 0x01;

      /* update status */
      cdd.status = CD_PLAY;

      /* return current track number in RS2-RS3 */
      scd.regs[0x38>>1].w = (CD_PLAY << 8) | 0x02;
      scd.regs[0x3a>>1].w = (cdd.index < cdd.toc.last) ? lut_BCD_16[index + 1] : 0x0A0A;
      scd.regs[0x3c>>1].w = 0x0000;
      scd.regs[0x3e>>1].w = 0x0000;
      scd.regs[0x40>>1].b.h = 0x00;
      break;
    }

    case 0x04:  /* Seek */
    {
      /* reset track index */
      s32 index = 0;

      /* new LBA position */
      s32 lba = ((scd.regs[0x44>>1].b.h * 10 + scd.regs[0x44>>1].b.l) * 60 + 
                 (scd.regs[0x46>>1].b.h * 10 + scd.regs[0x46>>1].b.l)) * 75 +
                 (scd.regs[0x48>>1].b.h * 10 + scd.regs[0x48>>1].b.l) - 150;

      /* CD drive seek time  */
      /* We are using similar linear model as above, although still not exactly accurate, */
      /* it works fine for Switch/Panic! intro (Switch needs at least 30 interrupts while */
      /* seeking from 00:05:63 to 24:03:19, Panic! when seeking from 00:05:60 to 24:06:07) */
      if (lba > cdd.lba)
      {
        cdd.latency = ((lba - cdd.lba) * 120) / 270000;
      }
      else
      {
        cdd.latency = ((cdd.lba - lba) * 120) / 270000;
      }

      /* update current LBA */
      cdd.lba = lba;

      /* update current track index */
      while ((cdd.toc.tracks[index].end <= lba) && (index < cdd.toc.last)) index++;
      cdd.index = index;

      /* seek to current block */
      if (!index)
      {
        /* DATA track */
        if (lba < 0) lba = 0;
        fseek(cdd.toc.tracks[0].fd, lba * cdd.sectorSize, SEEK_SET);
      }
      else if (cdd.toc.tracks[index].fd)
      {
        /* AUDIO track */
        if (lba < cdd.toc.tracks[index].start) lba = cdd.toc.tracks[index].start;
        fseek(cdd.toc.tracks[index].fd, (lba * 2352) - cdd.toc.tracks[index].offset, SEEK_SET);
      }

      /* no audio track playing */
      scd.regs[0x36>>1].b.h = 0x01;

      /* update status */
      cdd.status = CD_SEEK;

      /* unknown RS1-RS8 values (returning 0xF in RS1 invalidates track infos usually returned in RS2-RS8, which fixes Final Fight CD intro when seek time is emulated) */
      scd.regs[0x38>>1].w = (CD_SEEK << 8) | 0x0f;
      scd.regs[0x3a>>1].w = 0x0000;
      scd.regs[0x3c>>1].w = 0x0000;
      scd.regs[0x3e>>1].w = 0x0000;
      scd.regs[0x40>>1].w = ~(CD_SEEK + 0xf) & 0x0f;
      return;
    }

    case 0x06:  /* Pause */
    {
      /* no audio track playing */
      scd.regs[0x36>>1].b.h = 0x01;

      /* update status (RS1-RS8 unchanged) */
      cdd.status = scd.regs[0x38>>1].b.h = CD_READY;
      break;
    }

    case 0x07:  /* Resume */
    {
      /* update status (RS1-RS8 unchanged) */
      cdd.status = scd.regs[0x38>>1].b.h = CD_PLAY;
      break;
    }

    case 0x08:  /* Forward Scan */
    {
      /* reset scanning direction / speed */
      cdd.scanOffset = CD_SCAN_SPEED;

      /* update status (RS1-RS8 unchanged) */
      cdd.status = scd.regs[0x38>>1].b.h = CD_SCAN;
      break;
    }

    case 0x09:  /* Rewind Scan */
    {
      /* reset scanning direction / speed */
      cdd.scanOffset = -CD_SCAN_SPEED;

      /* update status (RS1-RS8 unchanged) */
      cdd.status = scd.regs[0x38>>1].b.h = CD_SCAN;
      break;
    }


    case 0x0a:  /* N-Track Jump Control ? (usually sent before CD_SEEK or CD_PLAY commands) */
    {
      /* TC3 corresponds to seek direction (00=forward, FF=reverse) */
      /* TC4-TC7 are related to seek length (4x4 bits i.e parameter values are between -65535 and +65535) */
      /* Maybe related to number of auto-sequenced track jumps/moves for CD DSP (cf. CXD2500BQ datasheet) */
      /* also see US Patent nr. 5222054 for a detailled description of seeking operation using Track Jump */

      /* no audio track playing */
      scd.regs[0x36>>1].b.h = 0x01;

      /* update status */
      cdd.status = CD_READY;

      /* unknown RS0-RS8 values (returning 0xF in RS1 invalidates track infos usually returned in RS2-RS8) */
      scd.regs[0x38>>1].w = (CD_READY << 8) | 0x0f;
      scd.regs[0x3a>>1].w = 0x0000;
      scd.regs[0x3c>>1].w = 0x0000;
      scd.regs[0x3e>>1].w = 0x0000;
      scd.regs[0x40>>1].w = ~(CD_READY + 0xf) & 0x0f;
      return;
    }

    case 0x0c:  /* Close Tray */
    {
      /* no audio track playing */
      scd.regs[0x36>>1].b.h = 0x01;

      /* update status */
      cdd.status = cdd.loaded ? CD_STOP : NO_DISC;

      /* RS1-RS8 ignored, expects 0x0 ("no disc" ?) in RS0 once */
      scd.regs[0x38>>1].w = 0x0000;
      scd.regs[0x3a>>1].w = 0x0000;
      scd.regs[0x3c>>1].w = 0x0000;
      scd.regs[0x3e>>1].w = 0x0000;
      scd.regs[0x40>>1].w = 0x000f;

version(CD_TRAY_CALLBACK) {
      CD_TRAY_CALLBACK();
}
      return;
    }

    case 0x0d:  /* Open Tray */
    {
      /* no audio track playing */
      scd.regs[0x36>>1].b.h = 0x01;

      /* update status (RS1-RS8 ignored) */
      cdd.status = CD_OPEN;
      scd.regs[0x38>>1].w = CD_OPEN << 8;
      scd.regs[0x3a>>1].w = 0x0000;
      scd.regs[0x3c>>1].w = 0x0000;
      scd.regs[0x3e>>1].w = 0x0000;
      scd.regs[0x40>>1].w = ~CD_OPEN & 0x0f;

version(CD_TRAY_CALLBACK) {
      CD_TRAY_CALLBACK();
}
      return;
    }

    default:  /* Unknown command */
version(LOG_CDD) {
      error("Unknown CDD Command !!!\n");
}
      scd.regs[0x38>>1].b.h = cdd.status;
      break;
  }

  /* only compute checksum when necessary */
  scd.regs[0x40>>1].b.l = ~(scd.regs[0x38>>1].b.h + scd.regs[0x38>>1].b.l +
                               scd.regs[0x3a>>1].b.h + scd.regs[0x3a>>1].b.l +
                               scd.regs[0x3c>>1].b.h + scd.regs[0x3c>>1].b.l +
                               scd.regs[0x3e>>1].b.h + scd.regs[0x3e>>1].b.l +
                               scd.regs[0x40>>1].b.h) & 0x0f;
}

