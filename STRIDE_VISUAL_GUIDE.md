# RDP Frame Stride - Visual Guide

## The Problem Visualized

### ❌ WRONG: Assuming Tight Stride (Before Fix)

```
IronRDP GPU Buffer (raw_stride = 5120 for 1280px)
┌─────────────────────────────────────────────────────────┐
│ Row 0: [RGBA pixels 0-1279 + PADDING] (5120 bytes)     │
│ Row 1: [RGBA pixels 1280-2559 + PADDING] (5120 bytes)  │
│ Row 2: [RGBA pixels 2560-3839 + PADDING] (5120 bytes)  │
│ ...                                                     │
└─────────────────────────────────────────────────────────┘
        ↓ (WRONG: Used tight_stride = 5120)
        ↓ (If padding exists, reads JUNK)
        ↓
Extract Region: Width=1280, Height=800
Calculated tight_stride = 1280 * 4 = 5120

for row in 0..800:
    src_offset = row * 5120 + left * 4  ← CORRECT BY ACCIDENT
    ↓
    But if width ≠ 1280, this breaks!
    
Result: 
  ✅ Works for 1280x800
  ❌ Broken for 1024x768 (stride mismatch!)
  ❌ Broken for partial dirty rects
  ⚠️  CAUSES DIAGONAL ARTIFACTS
```

---

### ✅ CORRECT: Using Raw Stride (After Fix)

```
IronRDP GPU Buffer (raw_stride from image.stride())
┌─────────────────────────────────────────────────────────┐
│ Row 0: [RGBA pixels 0-1279 + GPU PADDING] (5120 bytes) │
│ Row 1: [RGBA pixels 1280-2559 + GPU PADDING] (5120)    │
│ Row 2: [RGBA pixels 2560-3839 + GPU PADDING] (5120)    │
│ ...                                                     │
└─────────────────────────────────────────────────────────┘
        ↓ (CORRECT: Use actual raw_stride)
        ↓
let raw_stride = image.stride();  // e.g., 5120

for row in 0..800:
    src_offset = row * raw_stride + left * 4  ← ALWAYS CORRECT
    
Result:
  ✅ Works for 1280x800
  ✅ Works for 1024x768  
  ✅ Works for any resolution
  ✅ NO ARTIFACTS
```

---

## Stride Values for Common Resolutions

```
Resolution    Width   Tight (W*4)   Aligned (64-byte)   GPU Padding?
─────────────────────────────────────────────────────────────────────
 640x480       640      2560           2560              None
 800x600       800      3200           3200              None
1024x768      1024      4096           4096              None
1280x800      1280      5120           5120              None
1280x1024     1280      5120           5120              None
1600x900      1600      6400           6400              None
1920x1080     1920      7680           7680              None
1024x720      1024      4096           4096              None
512x384        512      2048           2048              None

Key: Tight = no padding, Aligned = may have padding for GPU
```

**Note:** Most desktop resolutions align nicely to 64-byte boundary.
But IronRDP may add extra padding for GPU optimization.

---

## Data Flow Diagram

### BEFORE (Broken)

```
┌─────────────────────────────────────────────────────────────┐
│                  IronRDP Decoder                            │
│           Outputs DecodedImage (GPU-aligned)                │
│              raw_stride = 5120 (or more)                    │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ↓
┌─────────────────────────────────────────────────────────────┐
│               Rust: emit_frame()                            │
│  ❌ WRONG: tight_stride = width * 4  (ignores GPU padding)  │
│  ❌ Calculates: src_offset = y * tight_stride + x*4         │
│                                                             │
│  For width=1280: tight=5120 ← WORKS (by accident)          │
│  For width<1280: tight<5120 ← BROKEN (stride mismatch!)    │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ↓
        ╔═════════════════════════════════╗
        ║  PIXEL DATA CORRUPTED! ✗        ║
        ║  Diagonal stripes appear        ║
        ╚═════════════════════════════════╝
                       │
                       ↓
┌─────────────────────────────────────────────────────────────┐
│               Flutter: _onCompleteFrame()                   │
│        Receives corrupted patch data (wrong rows)           │
│        Tries to blit, but pixels are shifted               │
└─────────────────────────────────────────────────────────────┘
                       │
                       ↓
                    🎨 SCREEN
                 [DIAGONAL STRIPES] ❌
```

---

### AFTER (Fixed)

```
┌─────────────────────────────────────────────────────────────┐
│                  IronRDP Decoder                            │
│           Outputs DecodedImage (GPU-aligned)                │
│              raw_stride = 5120 (or variable)                │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ↓
┌─────────────────────────────────────────────────────────────┐
│               Rust: emit_frame()                            │
│  ✅ CORRECT: raw_stride = image.stride()  (from GPU)        │
│  ✅ Calculates: src_offset = y * raw_stride + x*4           │
│                                                             │
│  For any width: Uses actual GPU stride ← ALWAYS WORKS      │
│  Extracts clean region data                                │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ↓
        ╔═════════════════════════════════╗
        ║  PIXEL DATA CORRECT! ✓          ║
        ║  Tight-packed RGBA sent         ║
        ╚═════════════════════════════════╝
                       │
                       ↓
┌─────────────────────────────────────────────────────────────┐
│               Flutter: _onCompleteFrame()                   │
│        Receives correct patch data                          │
│  ✅ Validates boundaries                                    │
│  ✅ Blits to aligned framebuffer (destStride = _rowBytes)  │
│  ✅ Triggers decode                                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ↓
                    🎨 SCREEN
                [CLEAN IMAGE] ✅
```

---

## Stride Calculation Examples

### Example 1: 1280x800 Desktop

```
GPU Buffer Layout:
┌─────────────────────────────────┐
│ Row 0: [1280 pixels × 4 bytes]  │ → 5120 bytes
│        [GPU padding (if any)]   │
├─────────────────────────────────┤
│ Row 1: [1280 pixels × 4 bytes]  │ → 5120 bytes
│        [GPU padding]            │
├─────────────────────────────────┤
│ ...                             │
├─────────────────────────────────┤
│ Row 799: [1280 pixels]          │ → 5120 bytes
└─────────────────────────────────┘
Total: 800 rows × 5120 = 4,096,000 bytes

Extracting full screen:
  raw_stride = 5120 (from image.stride())
  for row in 0..800:
      src_offset = row * 5120
      Rows: 0, 5120, 10240, 15360, ...
      
PACKED OUTPUT (tight, no padding):
  Width: 1280 pixels × 4 = 5120 bytes per row
  Height: 800 rows
  Total: 800 × 5120 = 4,096,000 bytes (MATCHES!)
```

### Example 2: 1024x768 Desktop

```
GPU Buffer Layout:
┌──────────────────────────────┐
│ Row 0: [1024 × 4] = 4096     │ (already aligned to 64)
│        [no padding needed]   │
├──────────────────────────────┤
│ Row 1: [1024 × 4] = 4096     │
│        [no padding]          │
├──────────────────────────────┤
│ ...                          │
└──────────────────────────────┘
Total: 768 rows × 4096 = 3,145,728 bytes

RUST (if using WRONG tight_stride):
  tight_stride = 1024 * 4 = 4096  ← Happens to work
  for row in 0..768:
      src_offset = row * 4096
      Rows: 0, 4096, 8192, ...
  WORKS, but only by coincidence!

RUST (using CORRECT raw_stride):
  raw_stride = image.stride() = 4096
  for row in 0..768:
      src_offset = row * 4096
      Rows: 0, 4096, 8192, ...
  WORKS CORRECTLY!
  
PACKED OUTPUT (tight):
  Width: 1024 × 4 = 4096 bytes/row
  Height: 768 rows
  Total: 768 × 4096 = 3,145,728 bytes ✓
```

### Example 3: Partial Dirty Rect (1280x800 desktop)

```
Suppose dirty rect: x=100, y=50, w=200, h=100

IronRDP GPU Buffer with raw_stride=5120:
  Row 50: [1280 pixels]        ← Our region START
  Row 51: [100-299 pixels needed]
  ...
  Row 149: [100-299 pixels needed]  ← Our region END

WRONG Calculation (using tight=5120):
  for y in 50..150:
      src_offset = y * 5120 + 100 * 4
      Row 50: 50*5120 + 400 = 256,400
      Row 51: 51*5120 + 400 = 261,520
      ...
      HAPPENS TO WORK (stride correct for this res!)
  But fails if GPU adds padding!

CORRECT Calculation (using raw_stride):
  for y in 50..150:
      src_offset = y * raw_stride + 100 * 4
      If raw_stride = 5120:
          Row 50: 50*5120 + 400 = 256,400 ✓
          Row 51: 51*5120 + 400 = 261,520 ✓
      If raw_stride = 5184 (with GPU padding):
          Row 50: 50*5184 + 400 = 259,600 ✓
          Row 51: 51*5184 + 400 = 264,784 ✓
          
RESULT: Works for ANY stride!
```

---

## Memory Layout Comparison

### Scenario: Extract 200×100 rect from 1280×800 buffer

```
┌─ FULL BUFFER (GPU-aligned, raw_stride=5120) ─────────────────┐
│                                                                │
│ Row 0:   [1280 pixels × 4 bytes] = 5120                      │
│ ...                                                            │
│ Row 50:  [....].[100-299 pixels needed].[...]                 │
│ Row 51:  [....].[100-299 pixels needed].[...]                 │
│ ...                                                            │
│ Row 149: [....].[100-299 pixels needed].[...]                 │
│ ...                                                            │
│ Row 799: [1280 pixels × 4 bytes] = 5120                      │
│                                                                │
└────────────────────────────────────────────────────────────────┘

SOURCE OFFSET CALCULATION:

WRONG (tight_stride = 5120):
  For row in [50..150]:
    offset = row * 5120 + 100*4
    Reads: 5120 bytes/row
    
  Row 50: offset = 50*5120 + 400   = 256,400
  Row 51: offset = 51*5120 + 400   = 261,520
  Row 52: offset = 52*5120 + 400   = 266,640
  ...
  ❌ FAILS if GPU stride ≠ 5120

CORRECT (raw_stride = ???):
  For row in [50..150]:
    offset = row * raw_stride + 100*4
    
  If raw_stride = 5120:
    Row 50: offset = 50*5120 + 400 = 256,400 ✓
  
  If raw_stride = 5184 (GPU padding):
    Row 50: offset = 50*5184 + 400 = 259,600 ✓
  
  ✅ WORKS regardless of padding!

PACKED OUTPUT (tight):
  Dimensions: 200 × 100
  Stride: 200 * 4 = 800 bytes/row
  Size: 100 * 800 = 80,000 bytes
  
  Layout:
  [Row 50, pixels 100-299] → bytes 0-799 (tight)
  [Row 51, pixels 100-299] → bytes 800-1599 (tight)
  ...
  [Row 149, pixels 100-299] → bytes 79,200-79,999 (tight)
```

---

## The Fix in One Picture

```
BEFORE:                          AFTER:
╔════════════════════╗          ╔════════════════════╗
║ GPU Buffer         ║          ║ GPU Buffer         ║
║ raw_stride=5120    ║          ║ raw_stride=5120    ║
║ (may have padding) ║          ║ (may have padding) ║
╚─────────┬──────────╝          ╚─────────┬──────────╝
          │                              │
          ↓                              ↓
╔════════════════════╗          ╔════════════════════╗
║ Calculate:         ║          ║ Use:               ║
║ tight_stride =     ║          ║ raw_stride =       ║
║   width * 4        ║          ║   image.stride()   ║
║ ❌ IGNORES PADDING ║          ║ ✅ RESPECTS PADDING║
╚─────────┬──────────╝          ╚─────────┬──────────╝
          │                              │
          ↓                              ↓
╔════════════════════╗          ╔════════════════════╗
║ Extract region     ║          ║ Extract region     ║
║ ❌ WRONG offsets   ║          ║ ✅ CORRECT offsets ║
║ ❌ SKIPS data      ║          ║ ✅ READS all data  ║
║ ❌ READS JUNK      ║          ║ ✅ NO JUNK         ║
╚─────────┬──────────╝          ╚─────────┬──────────╝
          │                              │
          ↓                              ↓
╔════════════════════╗          ╔════════════════════╗
║ Pack tight         ║          ║ Pack tight         ║
║ ❌ GARBAGE DATA    ║          ║ ✅ CLEAN DATA      ║
╚─────────┬──────────╝          ╚─────────┬──────────╝
          │                              │
          ↓                              ↓
        FLUTTER                       FLUTTER
        BLIT                          BLIT
          │                              │
          ↓                              ↓
    [CORRUPTED] ❌                  [CLEAN] ✅
    Diagonal stripes                Perfect render
```

---

## Debugging: Log Values to Compare

### What to look for:

```
Rust Logs:
  [emit_frame] region=(...) size=WxH, raw_stride=X bpp=4
  └─ X should be width*4 or more (if GPU adds padding)

Flutter Logs:
  [RDP BLIT] pos=(...) size=(W,H) patch=BYTES bytes
  └─ BYTES should be W*H*4

  [RDP BLIT] done: copied=H rows, srcStride=X destStride=Y
  └─ X = W*4 (tight pack)
  └─ Y = (_fbWidth*4 + 63) & ~63 (aligned)
  └─ If X ≠ Y, may indicate framebuffer misalignment (not stride bug)
```

---

## Summary Checklist

- ✅ Rust uses `raw_stride` from `image.stride()`
- ✅ Rust extracts region with correct offsets
- ✅ Flutter receives tight-packed (no padding) data
- ✅ Flutter validates boundaries before blit
- ✅ Flutter unpacks tight data into aligned framebuffer
- ✅ No pixel shifting between rows
- ✅ No diagonal artifacts

---

**Last Updated:** August 4, 2026  
**Clarity Level:** Visual + Technical
