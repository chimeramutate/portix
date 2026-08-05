# Debugging Stride Issues - Troubleshooting Guide

## Symptom Checklist

### Visual Artifacts

| Symptom | Likely Cause | Check |
|---------|-------------|-------|
| **Diagonal stripes** | Stride mismatch | Compare `raw_stride` vs `_rowBytes` in logs |
| **Horizontal shift** | Wrong X offset | Check `x` coordinate in `_blitRect` |
| **Vertical shift** | Wrong Y offset or stride calc | Check `y` coordinate and row math |
| **Garbled pixels** | Byte order or format mismatch | Verify pixel format in logs |
| **Out-of-bounds corruption** | No clipping check | Look for boundary error logs |
| **Checkerboard pattern** | Missing rows | Check `rows_filled` in Rust logs |

---

## Log Analysis Flowchart

```
START
  ↓
[Check Rust emit_frame logs]
  ├─ "raw_stride=X" printed? 
  │  ├─ NO → Need rebuild
  │  └─ YES → Continue
  ├─ "rows_ok=H rows_filled=0"?
  │  ├─ NO → Source buffer out of bounds
  │  └─ YES → Continue
  ├─ "total_bytes=W*H*4"?
  │  ├─ NO → Size calculation error
  │  └─ YES → Continue
  ↓
[Check Flutter blit logs]
  ├─ "[RDP BLIT] pos=(X,Y) size=(W,H)"?
  │  ├─ NO → Frame not reaching blit
  │  └─ YES → Continue
  ├─ "srcStride=W*4 destStride=X"?
  │  ├─ NO → Stride mismatch (main issue)
  │  └─ YES → Continue
  ├─ "copied=H rows" (all rows)?
  │  ├─ NO → Boundary check failed
  │  └─ YES → Data transfer OK
  ├─ "dirty=true" set?
  │  ├─ NO → Not triggering decode
  │  └─ YES → Continue
  ↓
[Check Flutter decode logs]
  ├─ "[RDP DECODE] image decoded"?
  │  ├─ NO → decode failed
  │  └─ YES → Check render
  ↓
[Check screen render]
  ├─ Clean image? → ✅ FIX COMPLETE
  └─ Artifacts? → 🔍 CONTINUE DEBUGGING
```

---

## Step-by-Step Debugging

### Step 1: Extract Rust Logs

```bash
flutter run 2>&1 | grep "\[emit_frame\]"
```

**Expected output:**
```
[emit_frame] region=(0,0) size=1280x800, raw_stride=5120 bpp=4
[emit_frame] packed region=(0,0) size=1280x800 rows_ok=800 rows_filled=0 total_bytes=4096000
[emit_frame] sending 2 chunks, frame_id=1, chunk_size=262144
[emit_frame] chunk 0/2: data_len=262144 bytes
```

**Red flags:**
- `rows_filled > 0` → Source buffer boundary issue
- `total_bytes != W*H*4` → Size calculation wrong
- `raw_stride` missing → Code not updated

---

### Step 2: Extract Flutter Blit Logs

```bash
flutter logs | grep "\[RDP BLIT\]"
```

**Expected output:**
```
[RDP BLIT] pos=(0,0) size=(1280,800) patch=4096000 bytes
[RDP BLIT] done: copied=800 rows, srcStride=5120 destStride=5120 dirty=true
```

**Red flags:**
- `copied < H` → Boundary check triggered
- `srcStride != destStride` → Stride calculation diverged
- Boundary errors printed before this line

---

### Step 3: Check Frame Assembly

```bash
flutter logs | grep "\[RDP ASSEMBLY\]"
```

**Expected output (multi-chunk frames):**
```
[RDP ASSEMBLY] creating new assembly frame=1 size=1280x800 chunks=2
[RDP ASSEMBLY] chunk received frame=1 chunk=0/2 progress=1/2
[RDP ASSEMBLY] chunk received frame=1 chunk=1/2 progress=2/2
[RDP ASSEMBLY] complete, building bytes...
[RDP ASSEMBLY] assembled complete frame=1 bytes=4096000
```

**Red flags:**
- Chunks arriving out of order (OK if reordered)
- Timeout → Too many chunks, buffer too small
- Size mismatch → Width/height metadata inconsistent

---

### Step 4: Manual Stride Calculation

Given a desktop 1280x800:

**Rust side:**
```
raw_stride = image.stride()  // from IronRDP
if raw_stride != 5120:
    ISSUE: GPU alignment unexpected
```

**Flutter side:**
```dart
_rowBytes = (1280 * 4 + 63) & ~63
         = (5120 + 63) & ~63
         = 5120  ✅

// For comparison
if width = 1024:
_rowBytes = (4096 + 63) & ~63 = 4096  ✅

if width = 640:
_rowBytes = (2560 + 63) & ~63 = 2560  ✅
```

**To verify:**
```bash
# Add debug print in Flutter
print('_rowBytes=$_rowBytes for width=$_fbWidth');
```

---

## Common Issues & Fixes

### Issue 1: "rows_filled > 0" in Rust logs

```
[emit_frame] packed ... rows_ok=799 rows_filled=1 ...
```

**Cause:** Accessing beyond image buffer while reading dirty rect

**Fix in Rust:**
```rust
// Check raw_stride aligns with source.len()
if src_row_end > source.len() {
    // This means raw_stride was calculated wrong
    eprintln!("Stride calculation error!");
}
```

**Action:** Verify `raw_stride` from `image.stride()` is correct:
```bash
flutter logs | grep "raw_stride"
# If unexpected, investigate IronRDP decoder
```

---

### Issue 2: Boundary errors in Flutter

```
[RDP BLIT ERROR] row X src out of bounds: Y > Z
```

**Cause:** Patch data size doesn't match declared width × height

**Fix in Flutter:**
```dart
final expectedPatchBytes = w * h * 4;
if (patchData.length != expectedPatchBytes) {
    print('Expected $expectedPatchBytes, got ${patchData.length}');
    // Shows if Rust packing is wrong
}
```

**Action:** Check Rust logs for mismatch:
- `total_bytes` in Rust
- `patch=X` in Flutter
- Should match exactly

---

### Issue 3: Stride mismatch (main issue)

```
[RDP BLIT] srcStride=5120 destStride=5184  // ❌ MISMATCH
```

**This should NOT happen with the fix.** If it does:

**Check in Flutter:**
```dart
int get _rowBytes => (_fbWidth * 4 + 63) & ~63;
// Print this:
print('_fbWidth=$_fbWidth → _rowBytes=$_rowBytes');
```

**Check in Rust:**
```rust
println!("[emit_frame] raw_stride={}", raw_stride);
// If != expected, investigate image creation
```

**Resolution:**
- If Rust raw_stride is wrong → Fix IronRDP decoder
- If Flutter _rowBytes is wrong → Fix alignment formula

---

### Issue 4: Frames not reaching Flutter

```
[RDP _onFrame] ENTRY frame=1 ...
[RDP ASSEMBLY] creating new assembly ...
// NO [RDP _onCompleteFrame] following
```

**Cause:** Assembly incomplete or timeout

**Check:**
```bash
flutter logs | grep "ASSEMBLY TIMEOUT"
# If present, increase timeout or check for missing chunks
```

---

## Performance Checklist

After fixing stride issues:

- [ ] No "out of bounds" errors in logs
- [ ] `rows_ok = height` (all rows copied)
- [ ] `rows_filled = 0` (no fallback black)
- [ ] `copied = height` in Flutter blit
- [ ] Frame rate stable (check "tick skipped" count)
- [ ] No memory leaks (logs growing endlessly?)

---

## Testing with Different Resolutions

If stride fix works for 1280x800, verify other resolutions:

```bash
# On RDP server, change resolution to test
# Then check logs

# 1024x768
# Expected: _rowBytes = 4096

# 1920x1080
# Expected: _rowBytes = 7680

# 640x480
# Expected: _rowBytes = 2560
```

---

## Creating a Minimal Test Case

If issues persist, create minimal repro:

```rust
#[test]
fn test_stride_calculation() {
    let widths = vec![640, 1024, 1280, 1920, 2560];
    for w in widths {
        let tight = w * 4;
        let aligned = (w * 4 + 63) & !63;
        println!("Width {}: tight={} aligned={}", w, tight, aligned);
    }
}
```

```dart
void testRowBytesCalculation() {
    const widths = [640, 1024, 1280, 1920, 2560];
    for (int w in widths) {
        final rowBytes = (w * 4 + 63) & ~63;
        print('Width $w: rowBytes=$rowBytes');
    }
}
```

Both should produce identical aligned values.

---

## Advanced: GPU Texture Inspection

If visual artifacts persist, inspect the GPU texture:

```dart
// Add to build() after image is decoded
if (_image != null) {
    print('Image info:');
    print('  Width: ${_image!.width}');
    print('  Height: ${_image!.height}');
    print('  ByteLength: ${_image!.toByteData()?.lengthInBytes}');
}
```

If `ByteLength != width * height * 4`, GPU allocated extra padding.

---

## Summary: The Right Fix

✅ **Correct approach:**
1. Rust reads from GPU-aligned buffer using `image.stride()`
2. Rust packs tight (no padding) for transmission
3. Flutter unpacks tight data into aligned framebuffer
4. Flutter validates boundaries before each blit
5. Logs show matching strides end-to-end

❌ **Wrong approach:**
- Calculate stride from width (ignores padding)
- Assume tight packing everywhere
- Skip boundary checks
- Silent data corruption

---

**Last Updated:** August 4, 2026
**For Support:** Check logs with grep patterns provided above
