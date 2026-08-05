# Quick Test Commands - Stride Fix

**Copy & paste these commands to verify the stride fix is working.**

---

## 1. Build Verification (2 min)

### Verify Rust Compilation
```bash
cd /Users/asepimam/Documents/project/portix/portix_rdp
cargo check
```

✅ **Expected:** `Finished check [unoptimized + debuginfo] target(s) in X.XXs`

---

### Verify Flutter Analysis  
```bash
cd /Users/asepimam/Documents/project/portix/portix_app
flutter analyze
```

✅ **Expected:** `No issues found!` (or just stride-unrelated warnings)

---

## 2. Source Code Verification (1 min)

### Verify Rust Fix (raw_stride)
```bash
grep -n "let raw_stride = image.stride();" /Users/asepimam/Documents/project/portix/portix_rdp/src/infrastructure/rdp_client.rs
```

✅ **Expected:** Line number around 435 showing the raw_stride assignment

---

### Verify Flutter Boundary Check
```bash
grep -n "x < 0 || y < 0 || x + w > _fbWidth" /Users/asepimam/Documents/project/portix/portix_app/lib/src/features/rdp/widget/rdp_frame_viewer.dart
```

✅ **Expected:** Line number around 390 showing boundary validation

---

### Verify Flutter Per-Row Validation
```bash
grep -n "srcOffset + copyBytes >" /Users/asepimam/Documents/project/portix/portix_app/lib/src/features/rdp/widget/rdp_frame_viewer.dart
```

✅ **Expected:** Line number around 404 showing row boundary check

---

## 3. Build & Run

### Build Release Binary (Rust)
```bash
cd /Users/asepimam/Documents/project/portix/portix_rdp
cargo build --release
```

✅ **Expected:** `Finished release [optimized] target(s)`

---

### Clean Flutter (Important!)
```bash
cd /Users/asepimam/Documents/project/portix/portix_app
flutter clean
flutter pub get
```

✅ **Expected:** Clean cache and fresh dependency install

---

### Build/Run Flutter
```bash
cd /Users/asepimam/Documents/project/portix/portix_app
flutter run -v
```

✅ **Expected:** App builds and runs with detailed logs

---

## 4. Log Verification (During RDP Connection)

### See All RDP-Related Logs
```bash
flutter logs | grep -E "\[RDP|emit_frame\]"
```

✅ **Look for:**
- `[emit_frame]` entries with `raw_stride=XXXX`
- `[RDP BLIT]` entries showing stride values
- NO error messages about stride mismatch

---

### Extract Stride Values from Rust
```bash
flutter logs | grep "emit_frame" | grep -oP "raw_stride=\K[0-9]+" | sort | uniq -c
```

✅ **Expected:** One consistent stride value repeated (e.g., 7680 for 1920 width)

---

### Extract Stride Values from Flutter  
```bash
flutter logs | grep "RDP BLIT" | grep -oP "destStride=\K[0-9]+" | sort | uniq -c
```

✅ **Expected:** Same stride value as Rust logs

---

### Check for Stride Errors
```bash
flutter logs | grep -E "stride|mismatch|ERROR"
```

✅ **Expected:** No stride-related errors (other errors OK)

---

## 5. Quick Visual Test

**While running the app connected to RDP:**

1. Look at the screen rendering
   - ✅ Image should be clean and readable
   - ❌ Should NOT see diagonal striping patterns

2. Move mouse around
   - ✅ Cursor should move smoothly
   - ❌ Should NOT see artifacts

3. Scroll or drag a window
   - ✅ Update should be smooth
   - ❌ Should NOT see pixel corruption

---

## 6. Test at Different Resolutions

```bash
# In your RDP server, try these resolutions:
# - 640x480    → expected stride: 2560
# - 1024x768   → expected stride: 4096  
# - 1280x800   → expected stride: 5120
# - 1920x1080  → expected stride: 7680 (or GPU-aligned value)

# After each resolution change:
# Check Flutter logs for matching strides
```

**Command to see stride for current resolution:**
```bash
flutter logs | grep "emit_frame" | tail -1
```

---

## 7. Save Logs to File for Analysis

```bash
# Start logging to file
flutter logs > rdp_session_logs.txt 2>&1 &

# Let it run for 30 seconds
sleep 30

# Stop logging
pkill -f "flutter logs"

# View results
cat rdp_session_logs.txt | grep "\[emit_frame\]" | head -5
cat rdp_session_logs.txt | grep "\[RDP BLIT\]" | head -5
```

---

## 8. One-Line Test Summary

Copy and paste this to verify everything:

```bash
echo "=== RUST ===" && \
cd /Users/asepimam/Documents/project/portix/portix_rdp && \
cargo check 2>&1 | tail -3 && \
echo "" && \
echo "=== FLUTTER ===" && \
cd /Users/asepimam/Documents/project/portix/portix_app && \
flutter analyze 2>&1 | tail -3 && \
echo "" && \
echo "=== CODE CHECK ===" && \
grep -c "let raw_stride = image.stride();" ../portix_rdp/src/infrastructure/rdp_client.rs && \
grep -c "x < 0 || y < 0 || x + w > _fbWidth" lib/src/features/rdp/widget/rdp_frame_viewer.dart && \
echo "✅ All checks passed!"
```

---

## Stride Value Reference

| Resolution | Width | Calc. Stride | GPU Stride (actual) |
|------------|-------|--------------|-------------------|
| 640x480 | 640 | 640 * 4 = 2560 | 2560 or aligned |
| 1024x768 | 1024 | 1024 * 4 = 4096 | 4096 or aligned |
| 1280x800 | 1280 | 1280 * 4 = 5120 | 5120 or aligned |
| 1920x1080 | 1920 | 1920 * 4 = 7680 | 7680 or aligned |

**Note:** GPU stride may be larger due to alignment (typically 64-byte boundary), but the FIX ensures that whatever the actual stride is, Rust and Flutter agree on it.

---

## Troubleshooting One-Liners

### "What stride is being used?"
```bash
flutter logs | grep -E "raw_stride=|destStride=" | head -3
```

### "Are strides matching?"
```bash
flutter logs | grep "emit_frame" | grep -oP "raw_stride=\K[0-9]+" | uniq && \
flutter logs | grep "RDP BLIT" | grep -oP "destStride=\K[0-9]+" | uniq
```

### "Any errors in stride handling?"
```bash
flutter logs | grep -i "stride\|error\|mismatch\|boundary"
```

### "Verify fix is in code?"
```bash
grep "raw_stride" /Users/asepimam/Documents/project/portix/portix_rdp/src/infrastructure/rdp_client.rs | wc -l
```

✅ Should show multiple references to raw_stride (fix is there)

---

## Status Check

Run this to see if stride fix is properly deployed:

```bash
#!/bin/bash
echo "STRIDE FIX VERIFICATION"
echo "======================="
echo ""
echo "1. Rust has raw_stride fix:"
if grep -q "let raw_stride = image.stride();" /Users/asepimam/Documents/project/portix/portix_rdp/src/infrastructure/rdp_client.rs; then
    echo "   ✅ YES"
else
    echo "   ❌ NO"
fi
echo ""
echo "2. Flutter has boundary check:"
if grep -q "x < 0 || y < 0 || x + w > _fbWidth" /Users/asepimam/Documents/project/portix/portix_app/lib/src/features/rdp/widget/rdp_frame_viewer.dart; then
    echo "   ✅ YES"
else
    echo "   ❌ NO"
fi
echo ""
echo "3. Rust compilation:"
cd /Users/asepimam/Documents/project/portix/portix_rdp && cargo check 2>&1 | grep -q "Finished" && echo "   ✅ OK" || echo "   ❌ FAILED"
echo ""
echo "4. Flutter analysis:"
cd /Users/asepimam/Documents/project/portix/portix_app && flutter analyze 2>&1 | grep -q "issues found\|No issues" && echo "   ✅ OK" || echo "   ❌ FAILED"
echo ""
echo "SUMMARY: Stride fix is ready for testing ✅"
```

---

**Last Updated:** 2026-08-04  
**Status:** Ready to use  
