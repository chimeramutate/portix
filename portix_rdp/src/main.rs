/// portix_rdp — standalone viewer: window rendering + keyboard/mouse
///
/// Usage:
///   cargo run --bin portix-rdp -- <host> <port> <username> <password> [domain] [width] [height]
use std::env;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use minifb::{Key, MouseButton, MouseMode, Scale, Window, WindowOptions};
use tokio::sync::broadcast;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use portix_rdp::domain::events::{RdpErrorEvent, RdpFrameEvent, RdpStatusEvent};
use portix_rdp::domain::profile::RdpProfile;
use portix_rdp::infrastructure::rdp_client::{RdpCommand, RdpRuntime};
use tracing_subscriber::EnvFilter;

// ── Scancode map: minifb Key → PS/2 set-1 ────────────────────────────────────
fn key_to_scancode(key: Key) -> Option<u16> {
    Some(match key {
        Key::Escape => 0x01,
        Key::Key1 => 0x02,
        Key::Key2 => 0x03,
        Key::Key3 => 0x04,
        Key::Key4 => 0x05,
        Key::Key5 => 0x06,
        Key::Key6 => 0x07,
        Key::Key7 => 0x08,
        Key::Key8 => 0x09,
        Key::Key9 => 0x0A,
        Key::Key0 => 0x0B,
        Key::Minus => 0x0C,
        Key::Equal => 0x0D,
        Key::Backspace => 0x0E,
        Key::Tab => 0x0F,
        Key::Q => 0x10,
        Key::W => 0x11,
        Key::E => 0x12,
        Key::R => 0x13,
        Key::T => 0x14,
        Key::Y => 0x15,
        Key::U => 0x16,
        Key::I => 0x17,
        Key::O => 0x18,
        Key::P => 0x19,
        Key::LeftBracket => 0x1A,
        Key::RightBracket => 0x1B,
        Key::Enter => 0x1C,
        Key::LeftCtrl => 0x1D,
        Key::A => 0x1E,
        Key::S => 0x1F,
        Key::D => 0x20,
        Key::F => 0x21,
        Key::G => 0x22,
        Key::H => 0x23,
        Key::J => 0x24,
        Key::K => 0x25,
        Key::L => 0x26,
        Key::Semicolon => 0x27,
        Key::Apostrophe => 0x28,
        Key::Backquote => 0x29,
        Key::LeftShift => 0x2A,
        Key::Backslash => 0x2B,
        Key::Z => 0x2C,
        Key::X => 0x2D,
        Key::C => 0x2E,
        Key::V => 0x2F,
        Key::B => 0x30,
        Key::N => 0x31,
        Key::M => 0x32,
        Key::Comma => 0x33,
        Key::Period => 0x34,
        Key::Slash => 0x35,
        Key::RightShift => 0x36,
        Key::NumPadAsterisk => 0x37,
        Key::LeftAlt => 0x38,
        Key::Space => 0x39,
        Key::CapsLock => 0x3A,
        Key::F1 => 0x3B,
        Key::F2 => 0x3C,
        Key::F3 => 0x3D,
        Key::F4 => 0x3E,
        Key::F5 => 0x3F,
        Key::F6 => 0x40,
        Key::F7 => 0x41,
        Key::F8 => 0x42,
        Key::F9 => 0x43,
        Key::F10 => 0x44,
        Key::NumLock => 0x45,
        Key::ScrollLock => 0x46,
        Key::NumPad7 => 0x47,
        Key::NumPad8 => 0x48,
        Key::NumPad9 => 0x49,
        Key::NumPadMinus => 0x4A,
        Key::NumPad4 => 0x4B,
        Key::NumPad5 => 0x4C,
        Key::NumPad6 => 0x4D,
        Key::NumPadPlus => 0x4E,
        Key::NumPad1 => 0x4F,
        Key::NumPad2 => 0x50,
        Key::NumPad3 => 0x51,
        Key::NumPad0 => 0x52,
        Key::NumPadDot => 0x53,
        Key::F11 => 0x57,
        Key::F12 => 0x58,
        Key::RightCtrl => 0xE01D,
        Key::RightAlt => 0xE038,
        Key::NumPadEnter => 0xE01C,
        Key::NumPadSlash => 0xE035,
        Key::Insert => 0xE052,
        Key::Delete => 0xE053,
        Key::Home => 0xE047,
        Key::End => 0xE04F,
        Key::PageUp => 0xE049,
        Key::PageDown => 0xE051,
        Key::Up => 0xE048,
        Key::Down => 0xE050,
        Key::Left => 0xE04B,
        Key::Right => 0xE04D,
        _ => return None,
    })
}

/// Patch dirty region RGBA → XRGB ke dalam framebuffer flat.
/// Patch dirty region RGBA → XRGB ke dalam framebuffer flat.
/// Patch dirty region RGBA → XRGB ke dalam framebuffer flat.
fn patch_framebuf(
    dst: &mut [u32],
    dst_w: usize,
    dst_h: usize,
    src: &[u8],
    x: usize,
    y: usize,
    w: usize,
    h: usize,
) {
    // ======================================================
    // TES MUTLAK: Jika ada kotak hijau yang lurus di layar,
    // berarti RDP benar, dan warna/byte order yang salah.
    // ======================================================
    if w > 100 && h > 100 {
        let mut is_single_color = true;
        if src.len() >= 4 {
            let r = src[0];
            let g = src[1];
            let b = src[2];
            for i in (0..src.len()).step_by(4) {
                if src[i] != r || src[i + 1] != g || src[i + 2] != b {
                    is_single_color = false;
                    break;
                }
            }
        }

        if is_single_color {
            // Gambar kotak hijau di area update RDP
            for row in 0..h {
                if y + row >= dst_h {
                    break;
                }
                for col in 0..w {
                    if x + col >= dst_w {
                        break;
                    }
                    dst[(y + row) * dst_w + (x + col)] = 0x00FF00; // Hijau Murni
                }
            }
            return; // Skip proses RDP asli
        }
    }
    // ======================================================

    if x >= dst_w || y >= dst_h {
        return;
    }

    let w = w.min(dst_w - x);
    let h = h.min(dst_h - y);

    if src.len() < w * h * 4 {
        eprintln!(
            "[patch_framebuf] invalid source: {} < {}",
            src.len(),
            w * h * 4
        );
        return;
    }

    for row in 0..h {
        let src_row = row * w * 4;
        let dst_row = (y + row) * dst_w + x;

        if dst_row + w > dst.len() {
            eprintln!(
                "[patch_framebuf] ⚠️ DST OVERFLOW! row={} offset={} width={} len={}",
                row,
                dst_row,
                w,
                dst.len()
            );
            break; // JANGAN RETURN, tetap print errornya!
        }

        for col in 0..w {
            let si = src_row + col * 4;

            let r = src[si] as u32;
            let g = src[si + 1] as u32;
            let b = src[si + 2] as u32;

            // MINIFB DI LINUX KADANG BUTUH FORMAT BGR, BUKAN RGB!
            // Coba ubah baris bawah ini:
            dst[dst_row + col] = (b << 16) | (g << 8) | r;
        }
    }
}

fn init_logging() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::from_default_env()
                .add_directive("portix_rdp=debug".parse().unwrap())
                .add_directive("ironrdp=debug".parse().unwrap())
                .add_directive("ironrdp_async=debug".parse().unwrap())
                .add_directive("ironrdp_connector=debug".parse().unwrap()),
        )
        .init();
}

fn main() {
    init_logging();
    let args: Vec<String> = env::args().collect();
    if args.len() < 5 {
        eprintln!(
            "Usage: portix-rdp <host> <port> <username> <password> [domain] [width] [height]"
        );
        std::process::exit(1);
    }

    let host = args[1].clone();
    let port: u16 = args[2].parse().expect("port must be a number");
    let username = args[3].clone();
    let password = args[4].clone();
    let domain: Option<String> = args.get(5).filter(|s| !s.is_empty()).cloned();
    let width: u16 = args.get(6).and_then(|s| s.parse().ok()).unwrap_or(1280);
    let height: u16 = args.get(7).and_then(|s| s.parse().ok()).unwrap_or(800);

    let win_w = width as usize;
    let win_h = height as usize;

    println!("╔══════════════════════════════════════════╗");
    println!("║       portix_rdp  —  standalone viewer   ║");
    println!("╚══════════════════════════════════════════╝");
    println!("  host    : {}:{}", host, port);
    println!(
        "  user    : {}{}",
        domain
            .as_deref()
            .map(|d| format!("{}\\", d))
            .unwrap_or_default(),
        username
    );
    println!("  desktop : {}×{}", width, height);
    println!();

    let domain: Option<String> = args
        .get(5)
        .filter(|s| !s.is_empty())
        .cloned()
        .or_else(|| Some(String::new()));

    let profile = RdpProfile {
        id: Uuid::new_v4().to_string(),
        name: format!("portix-rdp {}:{}", host, port),
        host,
        port,
        username,
        password: Some(password),
        domain,
        desktop_width: width,
        desktop_height: height,
        full_screen: false,
        enable_cred_ssp: true,
        alternate_shell: None,
        source_rdp_content: None,
    };

    // ── Shared framebuffer: DOUBLE BUFFER ─────────────────────────────────────
    // back  = ditulis oleh frame consumer thread
    // front = dibaca oleh window thread saat render
    // Swap via pointer swap — window thread tidak pernah blocking lama
    let back_buf: Arc<Mutex<Vec<u32>>> = Arc::new(Mutex::new(vec![0x18_1A_2E_u32; win_w * win_h]));
    let front_buf: Arc<Mutex<Vec<u32>>> = Arc::new(Mutex::new(vec![0x18_1A_2E_u32; win_w * win_h]));
    let dirty_flag: Arc<AtomicBool> = Arc::new(AtomicBool::new(false));

    // ── Input channel: window thread → tokio ─────────────────────────────────
    let (cmd_tx, cmd_rx) = std::sync::mpsc::sync_channel::<RdpCommand>(256);
    let cmd_tx_win = cmd_tx.clone();

    // ── Cancel token ─────────────────────────────────────────────────────────
    let cancel = CancellationToken::new();
    let cancel_tokio = cancel.clone();
    let cancel_win = cancel.clone();

    // ── Frame consumer thread (pure std, no tokio) ────────────────────────────
    // Menerima frame dari std::sync::mpsc, update back buffer, set dirty flag
    let (frame_tx_std, frame_rx_std) = std::sync::mpsc::sync_channel::<RdpFrameEvent>(512);

    let back_consumer = Arc::clone(&back_buf);
    let dirty_consumer = Arc::clone(&dirty_flag);
    let front_swap = Arc::clone(&front_buf);
    let cancel_consumer = cancel.clone();

    std::thread::Builder::new()
        .name("frame-consumer".into())
        .spawn(move || {
            loop {
                if cancel_consumer.is_cancelled() {
                    break;
                }

                let ev = match frame_rx_std.recv_timeout(Duration::from_millis(100)) {
                    Ok(ev) => ev,
                    Err(std::sync::mpsc::RecvTimeoutError::Timeout) => continue,
                    Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => break,
                };

                // Patch ke back buffer
                {
                    let mut back = back_consumer.lock().unwrap();
                    patch_framebuf(
                        &mut back,
                        win_w,
                        win_h,
                        &ev.data,
                        ev.x as usize,
                        ev.y as usize,
                        ev.width as usize,
                        ev.height as usize,
                    );
                }

                // Drain sisa frame yang pending supaya burst tidak menumpuk
                loop {
                    match frame_rx_std.try_recv() {
                        Ok(ev) => {
                            let mut back = back_consumer.lock().unwrap();
                            patch_framebuf(
                                &mut back,
                                win_w,
                                win_h,
                                &ev.data,
                                ev.x as usize,
                                ev.y as usize,
                                ev.width as usize,
                                ev.height as usize,
                            );
                        }
                        Err(_) => break,
                    }
                }

                // Swap back → front (copy ke front, window thread baca front)
                {
                    let back = back_consumer.lock().unwrap();
                    let mut front = front_swap.lock().unwrap();
                    front.copy_from_slice(&back);
                }
                dirty_consumer.store(true, Ordering::Release);
            }
        })
        .expect("spawn frame-consumer");

    // ── Tokio runtime thread ──────────────────────────────────────────────────
    std::thread::Builder::new()
        .name("rdp-runtime".into())
        .spawn(move || {
            let rt = tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .expect("tokio runtime");

            rt.block_on(async move {
                let (bcast_frame_tx, mut bcast_frame_rx) =
                    broadcast::channel::<RdpFrameEvent>(2048);
                let (bcast_status_tx, mut bcast_status_rx) =
                    broadcast::channel::<RdpStatusEvent>(64);
                let (bcast_error_tx, mut bcast_error_rx) = broadcast::channel::<RdpErrorEvent>(64);

                let next_frame_id = Arc::new(AtomicU64::new(0));

                let runtime = RdpRuntime::new(
                    profile,
                    "standalone-session".to_string(),
                    bcast_frame_tx,
                    bcast_status_tx,
                    bcast_error_tx,
                    next_frame_id,
                );

                // Ctrl-C
                let cc = cancel_tokio.clone();
                tokio::spawn(async move {
                    tokio::signal::ctrl_c().await.ok();
                    println!("\n[main] Ctrl-C");
                    cc.cancel();
                });

                // Input bridge: std::sync::mpsc → tokio mpsc
                let (cmd_async_tx, cmd_async_rx) = tokio::sync::mpsc::channel::<RdpCommand>(256);
                let cc_cmd = cancel_tokio.clone();
                tokio::task::spawn_blocking(move || loop {
                    match cmd_rx.recv_timeout(Duration::from_millis(50)) {
                        Ok(cmd) => {
                            if cmd_async_tx.blocking_send(cmd).is_err() {
                                break;
                            }
                        }
                        Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                            if cc_cmd.is_cancelled() {
                                break;
                            }
                        }
                        Err(_) => break,
                    }
                });

                // Runtime task
                let (done_tx, mut done_rx) = tokio::sync::oneshot::channel::<()>();
                let cc_run = cancel_tokio.clone();
                tokio::spawn(async move {
                    match runtime.run(cmd_async_rx, cc_run).await {
                        Ok(()) => println!("[runtime] finished normally"),
                        Err(e) => eprintln!("[runtime] error: {}", e),
                    }
                    let _ = done_tx.send(());
                });

                // Status logger
                let cc_s = cancel_tokio.clone();
                tokio::spawn(async move {
                    loop {
                        tokio::select! {
                            _ = cc_s.cancelled() => break,
                            r = bcast_status_rx.recv() => match r {
                                Ok(ev) => println!("[STATUS] {:?} — {}",
                                    ev.status, ev.message.as_deref().unwrap_or("-")),
                                Err(broadcast::error::RecvError::Lagged(n)) =>
                                    eprintln!("[STATUS] lagged {n}"),
                                Err(_) => break,
                            }
                        }
                    }
                });

                // Error logger
                let cc_e = cancel_tokio.clone();
                tokio::spawn(async move {
                    loop {
                        tokio::select! {
                            _ = cc_e.cancelled() => break,
                            r = bcast_error_rx.recv() => match r {
                                Ok(ev) => eprintln!("[ERROR] [{}] {}", ev.code, ev.message),
                                Err(broadcast::error::RecvError::Lagged(n)) =>
                                    eprintln!("[ERROR] lagged {n}"),
                                Err(_) => break,
                            }
                        }
                    }
                });

                // Frame forwarder: broadcast → std::sync channel
                let cc_f = cancel_tokio.clone();
                loop {
                    tokio::select! {
                        biased;
                        _ = cc_f.cancelled() => break,
                        _ = &mut done_rx => break,
                        r = bcast_frame_rx.recv() => match r {
                            Ok(ev) => { let _ = frame_tx_std.try_send(ev); }
                            Err(broadcast::error::RecvError::Lagged(n)) =>
                                eprintln!("[FRAME] broadcast lagged {n}"),
                            Err(_) => break,
                        }
                    }
                }

                cancel_tokio.cancel();
            });
        })
        .expect("spawn rdp-runtime thread");

    // ── Window loop — main thread, TIDAK BOLEH BLOCKING ───────────────────────
    let title = format!("portix-rdp  {}×{}", win_w, win_h);
    let mut window = Window::new(
        &title,
        win_w,
        win_h,
        WindowOptions {
            resize: false,
            scale: Scale::X1,
            borderless: false,
            ..WindowOptions::default()
        },
    )
    .expect("failed to create window");

    window.set_target_fps(60);

    // Working buffer milik window thread — tidak perlu lock saat render
    let mut render_buf: Vec<u32> = vec![0x18_1A_2E_u32; win_w * win_h];

    let mut prev_keys: Vec<Key> = Vec::new();
    let mut prev_mx = 0.0f32;
    let mut prev_my = 0.0f32;
    let mut prev_lmb = false;
    let mut prev_rmb = false;
    let mut prev_mmb = false;

    println!("[window] ready — close window or Ctrl-C to quit");
    // ==========================================
    // DIAGNOSTIC 1: Test apakah minifb merender lurus
    // ==========================================
    // Gambar garis diagonal merah
    for i in 0..200 {
        let x = 100 + i;
        let y = 100 + i;
        if x < win_w && y < win_h {
            render_buf[y * win_w + x] = 0x00FF0000; // Merah
        }
    }
    // Gambar garis horizontal hijau
    for x in 100..300 {
        if x < win_w {
            render_buf[150 * win_w + x] = 0x0000FF00; // Hijau
        }
    }
    // ==========================================
    while window.is_open() && !cancel_win.is_cancelled() {
        // ── 1. Cek dirty flag, copy front → render_buf jika ada update ────
        if dirty_flag.load(Ordering::Acquire) {
            dirty_flag.store(false, Ordering::Release);
            if let Ok(front) = front_buf.try_lock() {
                render_buf.copy_from_slice(&front);
            }
        }

        // ── 2. Render — WAJIB dipanggil setiap iterasi untuk Wayland ─────
        if let Err(e) = window.update_with_buffer(&render_buf, win_w, win_h) {
            eprintln!("[window] update error: {e}");
            break;
        }

        // ── 3. Mouse move ─────────────────────────────────────────────────
        if let Some((mx, my)) = window.get_mouse_pos(MouseMode::Clamp) {
            let ix = (mx as u16).min(width - 1);
            let iy = (my as u16).min(height - 1);

            if (mx - prev_mx).abs() > 0.4 || (my - prev_my).abs() > 0.4 {
                prev_mx = mx;
                prev_my = my;
                let _ = cmd_tx_win.try_send(RdpCommand::MouseMove { x: ix, y: iy });
            }

            // ── 4. Mouse buttons ──────────────────────────────────────────
            let lmb = window.get_mouse_down(MouseButton::Left);
            let rmb = window.get_mouse_down(MouseButton::Right);
            let mmb = window.get_mouse_down(MouseButton::Middle);

            if lmb != prev_lmb {
                prev_lmb = lmb;
                let _ = cmd_tx_win.try_send(RdpCommand::MouseButton {
                    x: ix,
                    y: iy,
                    button: 0,
                    down: lmb,
                });
            }
            if rmb != prev_rmb {
                prev_rmb = rmb;
                let _ = cmd_tx_win.try_send(RdpCommand::MouseButton {
                    x: ix,
                    y: iy,
                    button: 2,
                    down: rmb,
                });
            }
            if mmb != prev_mmb {
                prev_mmb = mmb;
                let _ = cmd_tx_win.try_send(RdpCommand::MouseButton {
                    x: ix,
                    y: iy,
                    button: 1,
                    down: mmb,
                });
            }
        }

        // ── 5. Scroll ─────────────────────────────────────────────────────
        if let Some((_, sy)) = window.get_scroll_wheel() {
            if sy.abs() > 0.01 {
                let delta = (sy * 120.0).clamp(-32768.0, 32767.0) as i16;
                let _ = cmd_tx_win.try_send(RdpCommand::MouseWheel {
                    x: prev_mx as u16,
                    y: prev_my as u16,
                    delta,
                    is_vertical: true,
                });
            }
        }

        // ── 6. Keyboard ───────────────────────────────────────────────────
        let curr_keys = window.get_keys();
        for &key in &curr_keys {
            if !prev_keys.contains(&key) {
                if let Some(sc) = key_to_scancode(key) {
                    let _ = cmd_tx_win.try_send(RdpCommand::KeyboardInput {
                        scancode: sc,
                        down: true,
                    });
                }
            }
        }
        for &key in &prev_keys {
            if !curr_keys.contains(&key) {
                if let Some(sc) = key_to_scancode(key) {
                    let _ = cmd_tx_win.try_send(RdpCommand::KeyboardInput {
                        scancode: sc,
                        down: false,
                    });
                }
            }
        }
        prev_keys = curr_keys;
    }

    println!("[window] closed");
    cancel_win.cancel();
    std::thread::sleep(Duration::from_millis(400));
    println!("[main] done");
}
