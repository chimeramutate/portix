# Testing & Verification Checklist - Stride Fix

**Purpose:** Verify that the RDP stride mismatch fixes are working correctly.

**Estimated Time:** 15-20 minutes

---

## Phase 1: Build Verification (5 min)

### ✅ Step 1.1: Rust Compilation
```bash
cd portix_rdp
cargo check
```

**Expected Output:**
```
   Checking portix_rdp v0.1.0
    Finished check [unoptimized + debuginfo] target(s) in 2.XX s
```

**Verification:**
- [ ] No compilation errors
- [ ] No warnings about `raw_stride`
- [ ] No warnings about unused variables

---

### ✅ Step 1.2: Flutter Analysis
```bash
cd portix_app
flutter analyze
```

**Expected Output:**
```
Analyzing portix_app...
No issues found! (in XX ms)
```

**Verification:**
- [ ] No analysis errors
- [ ] No warnings about stride/blit functions
- [ ] Clean analysis report

---

### ✅ Step 1.3: Flutter Build (Debug)
```bash
cd portix_app
flutter clean
flutter pub get
flutter build app  # or flutter run for direct testing
```

**Expected Output:**
```
✓ Built build/app/outputs/flutter-app.apk (or similar)
```

**Verification:**
- [ ] Build completes successfully
- [ ] No linking errors
- [ ] Output file created

---

## Phase 2: Source Code Verification (5 min)

### ✅ Step 2.1: Verify Rust Fix
```bash
cd portix_rdp/src/infrastructure
grep -n "let raw_stride = image.stride();" rdp_client.rs
```

**Expected Output:**
```
435:                let raw_stride = image.stride();
```

**Verification:**
- [ ] Line 435 exists
- [ ] Using `image.stride()` NOT calculated stride
- [ ] No `let tight_stride = ...` nearby

---

### ✅ Step 2.2: Verify Flutter Fix - Boundary Check
```bash
cd portix_app/lib/src/features/rdp/widget
grep -n "x < 0 || y < 0 || x + w > _fbWidth" rdp_frame_viewer.dart
```

**Expected Output:**
```
390:    if (x < 0 || y < 0 || x + w > _fbWidth || y + h > _fbHeight) {
```

**Verification:**
- [ ] Boundary check exists around line 390
- [ ] Checks both negative bounds and max bounds
- [ ] Returns early if out of bounds

---

### ✅ Step 2.3: Verify Flutter Fix - Per-Row Validation
```bash
cd portix_app/lib/src/features/rdp/widget
grep -n "if (srcOffset + copyBytes >" rdp_frame_viewer.dart
```

**Expected Output:**
```
404:      if (srcOffset + copyBytes > patchData.length) {
```

**Verification:**
- [ ] Row validation exists
- [ ] Checks source offset
- [ ] Checks destination offset
- [ ] Returns early on error

---

## Phase 3: Log Output Verification (5 min)

### ✅ Step 3.1: Build Release Binary
```bash
cd portix_rdp
cargo build --release
```

**Verification:**
- [ ] Build completes
- [ ] Binary at `target/release/` exists

---

### ✅ Step 3.2: Check Log Output (when connected to RDP)

Run the app and connect to an RDP server, then check logs:

```bash
flutter logs | grep -E "\[RDP|emit_frame\]"
```

**Expected Log Pattern (Rust sender):**
```
[emit_frame] region=(0,0) to (1919,1079), size=1920x1080, raw_stride=7680 bpp=4
[emit_frame] packed 1080 rows successfully, packed_size=8294400
[emit_frame] SUCCESS: emitted RGBA patch 1920x1080=8294400 bytes
```

**Verification:**
- [ ] Logs appear for each frame
- [ ] `raw_stride` value matches expected stride
  - For 1920 width: stride = 1920 * 4 = 7680 (or aligned value)
- [ ] `packed_size` matches width * height * 4
  - For 1920x1080: 8294400 bytes ✓
- [ ] No stride mismatch errors

---

### ✅ Step 3.3: Check Flutter Receiver Logs

```bash
flutter logs | grep "\[RDP BLIT\]"
```

**Expected Log Pattern (Flutter receiver):**
```
[RDP BLIT] pos=(0,0) size=(1920,1080) patch=8294400 bytes
[RDP BLIT] done: copied=1080 rows, srcStride=7680 destStride=7680 dirty=true
```

**Verification:**
- [ ] Blit logs appear
- [ ] `srcStride` matches `destStride` (both 7680 for 1920)
- [ ] `copied` rows equals frame height (1080)
- [ ] No boundary errors in logs

---

### ✅ Step 3.4: Check for Stride Mismatch Errors

```bash
flutter logs | grep -E "\[RDP.*ERROR|stride|mismatch|out of bounds\]"
```

**Expected Output:**
```
(no errors or warnings)
```

**Verification:**
- [ ] No stride mismatch errors
- [ ] No boundary violations
- [ ] No corrupt frame warnings

---

## Phase 4: Visual Verification (3 min)

### ✅ Step 4.1: Visual Inspection
While running the app connected to RDP:

**Look for:**
- [ ] Clean, diagonal-stripe-free rendering
- [ ] Smooth mouse movement
- [ ] Correct colors (no channel shifts)
- [ ] Text is readable (no corruption)
- [ ] No flickering or tearing
- [ ] No "ghost" images or artifacts

**Before Fix (❌ Bad):**
```
Visual artifacts:
- Diagonal striping across screen
- Pixel shifts row-by-row
- Color channel misalignment
- Text corruption
```

**After Fix (✅ Good):**
```
Clean rendering:
- No diagonal patterns
- Smooth, clean image
- Correct colors
- Readable text
- Smooth animations
```

---

### ✅ Step 4.2: Test at Different Resolutions

Test the following resolutions and check for artifacts:

| Resolution | Expected Stride | Test | Result |
|------------|-----------------|------|--------|
| 640x480 | 2560 | Connect & check | ✅ Clean? |
| 1024x768 | 4096 | Connect & check | ✅ Clean? |
| 1280x800 | 5120 | Connect & check | ✅ Clean? |
| 1920x1080 | 7680 | Connect & check | ✅ Clean? |

**Instructions per resolution:**
1. RDP server: Set resolution to target
2. Flutter app: Reconnect
3. Check logs: Look for matching strides
4. Check visual: Look for diagonal artifacts
5. Record result: ✅ or ❌

---

### ✅ Step 4.3: Stress Test (Optional)

Perform actions that send many frames:

- [ ] Drag window around screen → many small updates
- [ ] Scroll webpage → rapid full-screen updates
- [ ] Move mouse cursor → continuous frame data
- [ ] Play video → high-frequency frame updates
- [ ] Open/close applications → various update patterns

**During stress test, check:**
- [ ] No crashes or freezes
- [ ] Consistent log output (strides match)
- [ ] No progressive corruption (each frame independent)
- [ ] Performance remains stable

---

## Phase 5: Diagnostic Output (2 min)

### ✅ Step 5.1: Capture Full Log for Stride Info

```bash
flutter logs > rdp_logs.txt 2>&1 &
# Wait for 30 seconds of activity
sleep 30
# Kill the logging
pkill -f "flutter logs"
```

**Then analyze:**
```bash
grep "\[emit_frame\]" rdp_logs.txt | head -5
grep "\[RDP BLIT\]" rdp_logs.txt | head -5
```

**Expected:**
- All emit_frame logs show same raw_stride
- All RDP BLIT logs show matching srcStride/destStride
- Pattern repeats consistently

---

### ✅ Step 5.2: Compare Stride Values

Create a simple check:

```bash
# Extract raw strides from Rust
grep "raw_stride=" rdp_logs.txt | sed 's/.*raw_stride=\([0-9]*\).*/\1/' | sort | uniq -c

# Extract dest strides from Flutter  
grep "destStride=" rdp_logs.txt | sed 's/.*destStride=\([0-9]*\).*/\1/' | sort | uniq -c
```

**Expected Output:**
```
# Should see ONE dominant stride value repeated, e.g.:
    145 7680  # If 1920 width
    142 7680
```

**Verification:**
- [ ] All values are consistent
- [ ] No scattered stride values
- [ ] No 0 or negative strides

---

## Phase 6: Edge Case Testing (Optional, 5 min)

### ✅ Step 6.1: Partial Frames

Set up RDP to send partial screen updates (windows moving, tooltips, etc.)

**Check:**
- [ ] Logs show smaller dimensions (e.g., 400x300 patches)
- [ ] Boundary checks don't reject valid patches
- [ ] Only invalid patches are rejected

**Look for:**
```
[RDP BLIT] pos=(100,200) size=(400,300) patch=480000 bytes
[RDP BLIT] done: copied=300 rows, srcStride=1600 destStride=7680 dirty=true
```

---

### ✅ Step 6.2: Reconnect Test

Disconnect and reconnect to RDP:

```bash
# In Flutter app: Disconnect
# In Flutter app: Reconnect
# Check logs
```

**Expected:**
- [ ] New connection works
- [ ] Strides recalculate correctly
- [ ] No stride confusion between sessions
- [ ] Rendering clean after reconnect

---

## Summary Checklist

### Build Phase
- [ ] Rust compiles cleanly
- [ ] Flutter analyzes cleanly
- [ ] Release build succeeds

### Code Phase
- [ ] `raw_stride` fix in place (line 435)
- [ ] Boundary checks in place (line 390)
- [ ] Per-row validation in place (line 404)

### Log Phase
- [ ] Rust logs show raw_stride values
- [ ] Flutter logs show stride matches
- [ ] No stride mismatch errors
- [ ] Logs consistent across frames

### Visual Phase
- [ ] No diagonal striping artifacts
- [ ] Clean image rendering
- [ ] Correct colors
- [ ] Smooth interaction
- [ ] All tested resolutions work

### Result
- [ ] **PASS** - All checks pass, stride fix is working ✅
- [ ] **FAIL** - Some checks fail (see Phase 7)

---

## Phase 7: Troubleshooting (If Issues Found)

### Problem: Logs show mismatched strides

```
[emit_frame] raw_stride=7680
[RDP BLIT] srcStride=7680 destStride=7680
```

**But still see artifacts?**

→ Check if this is from BEFORE the fix was applied. Rebuild everything:
```bash
cd portix_rdp && cargo clean && cargo build --release
cd portix_app && flutter clean && flutter pub get && flutter build app
```

---

### Problem: Boundary checks rejecting valid frames

```
[RDP BLIT WARN] rect out of bounds: pos=(1900,1000) size=(100,100) vs framebuffer=(1920,1080)
```

**This is WRONG because 1900+100=2000 > 1920**

→ Expected: Framebuffer should be initialized to actual screen size
→ Check: `_fbWidth` and `_fbHeight` in `rdp_frame_viewer.dart`

---

### Problem: Strides don't match expected values

Expected stride for 1920: `7680` (1920 * 4)  
Got: `8192` or other value?

→ GPU padding! This is NORMAL if GPU alignment is active
→ As long as strides MATCH between Rust and Flutter, it's correct
→ Verify: `[emit_frame]` and `[RDP BLIT]` show same stride

---

### Problem: Still seeing diagonal artifacts

**Checklist:**
- [ ] Did you rebuild Rust binary? (`cargo build --release`)
- [ ] Did you rebuild Flutter? (`flutter clean && pub get`)
- [ ] Did you wait for new binary to deploy?
- [ ] Are you looking at fresh data (not cached)?
- [ ] Check logs: Are strides matching?

---

## Success Criteria

✅ **Fix is working correctly when:**

1. ✅ Rust compiles with no errors
2. ✅ Flutter analyzes with no errors  
3. ✅ Logs show consistent stride values
4. ✅ srcStride matches destStride (per-frame)
5. ✅ No boundary violation errors
6. ✅ Visual rendering is clean
7. ✅ No diagonal artifacts
8. ✅ Works at multiple resolutions
9. ✅ Stress test passes
10. ✅ Reconnect works correctly

---

## Next Steps if All Checks Pass

✅ **Stride fix is verified working!**

Consider:
- [ ] Deploy to production
- [ ] Document in release notes: "Fixed RDP stride mismatch causing diagonal artifacts"
- [ ] Monitor production logs for any new stride-related errors
- [ ] Keep logging enabled for next 48 hours to catch edge cases

---

## Next Steps if Issues Remain

❌ **Some checks failed**

1. Compare your logs with examples in this document
2. Check which phase failed
3. Review the troubleshooting section
4. If still stuck: Check `DEBUG_STRIDE_ISSUES.md` for detailed flowcharts
5. Collect logs and share `flutter logs` output for analysis

---

**Document Version:** 1.0  
**Last Updated:** 2026-08-04  
**Status:** Ready for Testing  
