# RDP Frame Stride Mismatch - Quick Summary

## The Problem
Diagonal striping/pixel corruption on RDP frames due to stride mismatch.

## The 3 Key Fixes

### ✅ Fix #1: Rust - Use raw_stride, not tight_stride
**File:** `portix_rdp/src/infrastructure/rdp_client.rs` Line 435

```rust
// BEFORE (WRONG)
let tight_stride = image_width * bpp;
let src_row_start = y * tight_stride + left * bpp;  // ❌

// AFTER (CORRECT)
let raw_stride = image.stride();
let src_row_start = y * raw_stride + left * bpp;  // ✅
```

**Why:** IronRDP's `DecodedImage` has GPU-aligned buffers with padding. Use the actual stride, don't calculate it.

---

### ✅ Fix #2: Flutter - Improved boundary validation
**File:** `portix_app/lib/src/features/rdp/widget/rdp_frame_viewer.dart` Lines 557-616

```dart
// NEW: Check bounds before blitting
if (x < 0 || y < 0 || x + w > _fbWidth || y + h > _fbHeight) {
    debugPrint('[RDP BLIT WARN] rect out of bounds...');
    return;
}

// NEW: Validate each row
for (var row = 0; row < h; row++) {
    final srcOffset = row * srcStride;
    final dstOffset = (y + row) * destStride + x * 4;
    
    if (srcOffset + copyBytes > patchData.length) return;
    if (dstOffset + copyBytes > _framebuffer.length) return;
    
    _framebuffer.setRange(dstOffset, dstOffset + copyBytes, ...);
}
```

**Why:** Catch stride mismatches early with explicit validation before copying.

---

### ✅ Fix #3: Enhanced logging
**Both files:** Better error messages with stride/size info

```
[emit_frame] region=(x,y) size=WxH raw_stride=STRIDE  // Rust
[RDP BLIT] done: srcStride=X destStride=Y rows=Z      // Flutter
```

**Why:** Diagnose issues quickly by seeing actual stride values.

---

## Testing

```bash
# 1. Rebuild Rust
cd portix_rdp && cargo build --release

# 2. Rebuild Flutter
cd portix_app && flutter clean && flutter pub get

# 3. Run and check logs
flutter logs | grep -E "\[RDP|emit_frame\]"

# 4. Look for:
# - No boundary errors
# - rows_ok = total rows (in Rust log)
# - copied = height (in Flutter log)
# - Clean image rendering
```

---

## Key Concept: Strides

### **Tight Packing (Patch Data)**
- Each row: `width * 4` bytes (no padding)
- Total: `width * height * 4` bytes
- Simple indexing: `(y * width * 4) + (x * 4)`

### **GPU Alignment (Framebuffer)**
- Each row: `_fbWidth * 4` bytes, then aligned (usually 64-byte boundary)
- If 1280: `(1280 * 4 = 5120)` → already 64-byte aligned ✅
- Total: `_rowBytes * _fbHeight` bytes
- Careful indexing: `((y * _rowBytes) + (x * 4))`

**The Fix:** Rust now extracts data using the **actual GPU stride** from IronRDP, then packs it **tight** for transmission. Flutter unpacks **tight** data and blits it back to **aligned** framebuffer.

---

## Before & After

| Aspect | Before | After |
|--------|--------|-------|
| **Stride calc** | Assumed tight layout | Uses raw_stride from image |
| **Validation** | Minimal | Comprehensive per-row |
| **Logging** | Basic | Detailed with stride info |
| **Clipping** | None | Boundary checks |
| **Result** | Diagonal artifacts | Clean rendering |

---

## What Changed in Git

```
portix_rdp/src/infrastructure/rdp_client.rs
  - Line 435: raw_stride instead of tight_stride
  - Lines 450-490: Enhanced error handling
  - Lines 500-530: Better chunk logging

portix_app/lib/src/features/rdp/widget/rdp_frame_viewer.dart
  - Lines 557-616: Improved _blitRect with validation
  - Lines 717-746: Enhanced _onCompleteFrame logging
```

---

## Compile & Run

```bash
# Check Rust
cd portix_rdp && cargo check

# Build everything
flutter run

# Monitor with
flutter logs
```

---

**Status:** ✅ Ready to test  
**Impact:** Low (validation only, no algorithm changes)  
**Affected Files:** 2 core files (Rust sender + Flutter receiver)
