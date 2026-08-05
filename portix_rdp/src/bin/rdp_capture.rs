/// Standalone RDP capture tool
///
/// Connects ke RDP server, menunggu beberapa frame, lalu menyimpan
/// beberapa versi PNG untuk diagnosa visual:
///
///   frame_raw_stride.png  — gambar dengan raw_stride dari image.stride()  (cara saat ini)
///   frame_tight.png       — gambar dengan tight stride = width*4 (TANPA padding)
///   frame_bgr_swap.png    — gambar dengan B↔R channel swap
///   frame_patch.png       — hanya region dirty terakhir
///
/// Usage:
///   cd portix_rdp
///   cargo run --bin rdp_capture -- <host> <port> <username> <password>
///
/// Contoh:
///   cargo run --bin rdp_capture -- 192.168.1.100 3389 Administrator P@ssw0rd
///
/// File PNG akan disimpan di direktori di mana command dijalankan.

use std::env;
use std::fs::File;
use std::io::BufWriter;
use std::path::Path;

use ironrdp_connector::{ClientConnector, Config, Credentials, DesktopSize, ServerName};
use ironrdp_graphics::image_processing::PixelFormat;
use ironrdp_pdu::geometry::InclusiveRectangle;
use ironrdp_session::image::DecodedImage;
use ironrdp_session::{ActiveStageBuilder, ActiveStageOutput};
use ironrdp_tokio::reqwest::ReqwestNetworkClient;
use ironrdp_tokio::{FramedRead, FramedWrite, TokioFramed, connect_begin, connect_finalize, mark_as_upgraded};
use tokio::net::TcpStream;
use tokio::time::{Duration, timeout};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(20);

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 5 {
        eprintln!("Usage: rdp_capture <host> <port> <username> <password>");
        eprintln!("Example: cargo run --bin rdp_capture -- 192.168.1.100 3389 admin P@ssw0rd");
        std::process::exit(1);
    }

    let host = args[1].clone();
    let port: u16 = args[2].parse().expect("Port must be a number");
    let username = args[3].clone();
    let password = args[4].clone();
    let domain: Option<String> = args.get(5).cloned();

    println!("╔══════════════════════════════════════════╗");
    println!("║        RDP Frame Capture Tool            ║");
    println!("╚══════════════════════════════════════════╝");
    println!("Host    : {}:{}", host, port);
    println!("User    : {}{}", 
        domain.as_deref().map(|d| format!("{}\\", d)).unwrap_or_default(),
        username
    );
    println!();

    run_capture(&host, port, &username, &password, domain.as_deref()).await?;
    Ok(())
}

async fn run_capture(
    host: &str,
    port: u16,
    username: &str,
    password: &str,
    domain: Option<&str>,
) -> anyhow::Result<()> {
    let addr = format!("{}:{}", host, port);
    println!("[1/5] TCP connecting to {}...", addr);

    let tcp = timeout(CONNECT_TIMEOUT, TcpStream::connect(&addr))
        .await
        .map_err(|_| anyhow::anyhow!("TCP connect timeout"))?
        .map_err(|e| anyhow::anyhow!("TCP connect error: {}", e))?;

    tcp.set_nodelay(true)?;
    let client_addr = tcp.peer_addr()?;
    println!("[1/5] TCP connected from {}", client_addr);

    // Build config — identik dengan rdp_client.rs
    let config = Config {
        desktop_size: DesktopSize {
            width: 1280,
            height: 800,
        },
        desktop_scale_factor: 0,
        enable_tls: true,
        enable_credssp: true,
        credentials: Credentials::UsernamePassword {
            username: username.to_string(),
            password: password.to_string(),
        },
        domain: domain.map(str::to_owned),
        client_build: 7601,
        client_name: "Portix-Capture".to_owned(),
        keyboard_type: ironrdp_pdu::gcc::KeyboardType::IbmEnhanced,
        keyboard_subtype: 0,
        keyboard_functional_keys_count: 12,
        keyboard_layout: 0x0409,
        ime_file_name: String::new(),
        bitmap: None,
        dig_product_id: String::new(),
        client_dir: String::new(),
        alternate_shell: String::new(),
        work_dir: String::new(),
        platform: ironrdp_pdu::rdp::capability_sets::MajorPlatformType::UNSPECIFIED,
        hardware_id: None,
        request_data: None,
        autologon: false,
        enable_audio_playback: false,
        performance_flags: ironrdp_pdu::rdp::client_info::PerformanceFlags::empty(),
        license_cache: None,
        timezone_info: ironrdp_pdu::rdp::client_info::TimezoneInfo::default(),
        compression_type: None,
        enable_server_pointer: true,
        pointer_software_rendering: true,
        multitransport_flags: None,
    };

    let server_name = ServerName::new(host.to_string());

    println!("[2/5] Starting RDP negotiation...");
    let mut connector = ClientConnector::new(config, client_addr);
    let mut framed = TokioFramed::new(tcp);

    let should_upgrade = timeout(CONNECT_TIMEOUT, connect_begin(&mut framed, &mut connector))
        .await
        .map_err(|_| anyhow::anyhow!("connect_begin timeout"))?
        .map_err(|e| anyhow::anyhow!("connect_begin failed: {}", e))?;

    let (raw_stream, leftover) = framed.into_inner();

    println!("[3/5] TLS upgrade...");
    let (upgraded_stream, server_cert_der) = timeout(
        CONNECT_TIMEOUT,
        ironrdp_tls::upgrade(raw_stream, host),
    )
    .await
    .map_err(|_| anyhow::anyhow!("TLS upgrade timeout"))?
    .map_err(|e| anyhow::anyhow!("TLS upgrade failed: {}", e))?;

    let server_public_key =
        ironrdp_tls::extract_tls_server_public_key(&server_cert_der).unwrap_or_default();

    let mut tls_framed = TokioFramed::new_with_leftover(upgraded_stream, leftover);
    let upgraded = mark_as_upgraded(should_upgrade, &mut connector);

    println!("[4/5] Finalizing connection (CredSSP/NLA)...");
    let mut network_client = ReqwestNetworkClient::new();
    let connection_result = timeout(
        CONNECT_TIMEOUT,
        connect_finalize(
            upgraded,
            connector,
            &mut tls_framed,
            &mut network_client,
            server_name,
            server_public_key.to_vec(),
            None,
        ),
    )
    .await
    .map_err(|_| anyhow::anyhow!("connect_finalize timeout"))?
    .map_err(|e| anyhow::anyhow!("connect_finalize failed: {}", e))?;

    let desktop_w = connection_result.desktop_size.width;
    let desktop_h = connection_result.desktop_size.height;
    println!("[4/5] Connected! Negotiated: {}x{}", desktop_w, desktop_h);

    // =====================================================================
    // USE SAME FORMAT AS rdp_client.rs — RgbA32
    // =====================================================================
    let mut image = DecodedImage::new(PixelFormat::RgbA32, desktop_w, desktop_h);

    let mut active_stage = ActiveStageBuilder {
        static_channels: connection_result.static_channels,
        user_channel_id: connection_result.user_channel_id,
        io_channel_id: connection_result.io_channel_id,
        message_channel_id: connection_result.message_channel_id,
        share_id: connection_result.share_id,
        compression_type: connection_result.compression_type,
        enable_server_pointer: false,
        pointer_software_rendering: false,
    }
    .build();

    println!("[5/5] Waiting for frames (will capture after 5 graphics updates)...");

    let mut update_count = 0u32;
    let mut last_region: Option<InclusiveRectangle> = None;

    loop {
        let (action, pdu_bytes) = tls_framed
            .read_pdu()
            .await
            .map_err(|e| anyhow::anyhow!("read_pdu: {}", e))?;

        let outputs = active_stage
            .process(&mut image, action, &pdu_bytes)
            .map_err(|e| anyhow::anyhow!("process: {}", e))?;

        for output in outputs {
            match output {
                ActiveStageOutput::ResponseFrame(frame) => {
                    tls_framed.write_all(&frame).await?;
                }
                ActiveStageOutput::GraphicsUpdate(region) => {
                    update_count += 1;
                    last_region = Some(region.clone());

                    let img_w = usize::from(image.width());
                    let img_h = usize::from(image.height());
                    let stride = image.stride();
                    let bpp = image.bytes_per_pixel();
                    let data_len = image.data().len();

                    // ── Stride diagnosis ──────────────────────────────
                    let tight = img_w * bpp;
                    let aligned_64 = (img_w * bpp + 63) & !63;
                    let aligned_4 = (img_w * bpp + 3) & !3;

                    println!(
                        "  Update #{:3}: region=({:4},{:4})→({:4},{:4}) | stride={} bpp={} [tight={} 4-align={} 64-align={}] {}",
                        update_count,
                        region.left, region.top, region.right, region.bottom,
                        stride, bpp,
                        tight, aligned_4, aligned_64,
                        if stride == tight { "✓ TIGHT" }
                        else if stride == aligned_4 { "⚠ 4-BYTE ALIGNED" }
                        else if stride == aligned_64 { "⚠ 64-BYTE ALIGNED" }
                        else { "? OTHER" },
                    );

                    // Capture setelah beberapa update agar layar sudah terisi
                    if update_count >= 43 {
                        println!("\n══════════════════════════════════════════");
                        println!("Capturing frame after {} updates...", update_count);
                        println!("Image: {}x{}  stride={}  bpp={}  data.len()={}", img_w, img_h, stride, bpp, data_len);
                        
                        save_diagnostic_pngs(&image);
                        
                        println!("\n══════════════════════════════════════════");
                        println!("DONE. Check these PNG files:");
                        println!("  frame_raw_stride.png  ← uses image.stride() [WHAT WE SEND TO FLUTTER]");
                        println!("  frame_tight.png       ← uses width*4 (no padding)");
                        println!("  frame_bgr_swap.png    ← B↔R channel swapped");
                        println!("  frame_full_raw.png    ← raw dump, stride bytes per row");
                        println!();
                        println!("If frame_raw_stride.png looks CORRECT → problem is in Flutter");
                        println!("If frame_raw_stride.png looks CORRUPT → problem is in Rust packing");
                        println!("If frame_bgr_swap.png looks correct  → format is BGR not RGB");
                        return Ok(());
                    }
                }
                ActiveStageOutput::Terminate(_) => {
                    anyhow::bail!("Server terminated connection before capture");
                }
                _ => {}
            }
        }

        if update_count > 200 {
            println!("200 updates processed, quitting");
            return Ok(());
        }
    }
}

fn save_diagnostic_pngs(image: &DecodedImage) {
    let img_w = usize::from(image.width());
    let img_h = usize::from(image.height());
    let stride = image.stride();
    let bpp = image.bytes_per_pixel();
    let data = image.data();

    println!("\nSaving diagnostic PNGs...");

    // ──────────────────────────────────────────────────────────────────────
    // PNG 1: frame_raw_stride.png
    // Uses image.stride() — exactly what emit_frame() reads with raw_stride
    // This is what we're currently sending to Flutter
    // ──────────────────────────────────────────────────────────────────────
    {
        let mut pixels = vec![0u8; img_w * img_h * 4];
        for row in 0..img_h {
            for col in 0..img_w {
                let src = row * stride + col * bpp;
                let dst = (row * img_w + col) * 4;
                if src + bpp <= data.len() && dst + 4 <= pixels.len() {
                    pixels[dst]     = data[src];
                    pixels[dst + 1] = data[src + 1];
                    pixels[dst + 2] = data[src + 2];
                    pixels[dst + 3] = 255;
                }
            }
        }
        write_png("frame_raw_stride.png", img_w, img_h, &pixels);
    }

    // ──────────────────────────────────────────────────────────────────────
    // PNG 2: frame_tight.png
    // Uses width*4 as stride — ignores any padding
    // If stride==tight, identical to PNG 1
    // If stride>tight, this will have diagonal stripes
    // ──────────────────────────────────────────────────────────────────────
    {
        let tight_stride = img_w * bpp;
        let mut pixels = vec![0u8; img_w * img_h * 4];
        for row in 0..img_h {
            for col in 0..img_w {
                let src = row * tight_stride + col * bpp; // uses tight, ignores padding
                let dst = (row * img_w + col) * 4;
                if src + bpp <= data.len() && dst + 4 <= pixels.len() {
                    pixels[dst]     = data[src];
                    pixels[dst + 1] = data[src + 1];
                    pixels[dst + 2] = data[src + 2];
                    pixels[dst + 3] = 255;
                }
            }
        }
        write_png("frame_tight.png", img_w, img_h, &pixels);
    }

    // ──────────────────────────────────────────────────────────────────────
    // PNG 3: frame_bgr_swap.png  
    // Same as PNG 1 but with B↔R swap
    // If this looks correct, IronRDP data is BGR not RGB
    // ──────────────────────────────────────────────────────────────────────
    {
        let mut pixels = vec![0u8; img_w * img_h * 4];
        for row in 0..img_h {
            for col in 0..img_w {
                let src = row * stride + col * bpp;
                let dst = (row * img_w + col) * 4;
                if src + bpp <= data.len() && dst + 4 <= pixels.len() {
                    pixels[dst]     = data[src + 2]; // R ← byte[2]
                    pixels[dst + 1] = data[src + 1]; // G ← byte[1]
                    pixels[dst + 2] = data[src];     // B ← byte[0]
                    pixels[dst + 3] = 255;
                }
            }
        }
        write_png("frame_bgr_swap.png", img_w, img_h, &pixels);
    }

    // ──────────────────────────────────────────────────────────────────────
    // PNG 4: frame_full_raw.png
    // Dumps the raw buffer treating each row as `stride` bytes wide
    // Shows the actual padded buffer including any alignment bytes
    // ──────────────────────────────────────────────────────────────────────
    {
        // Render each stride-row as a wider image so you can see the padding
        let raw_w = stride / bpp; // width including padding pixels
        if raw_w > 0 && raw_w * bpp * img_h <= data.len() {
            let mut pixels = vec![0u8; raw_w * img_h * 4];
            for row in 0..img_h {
                for col in 0..raw_w {
                    let src = row * stride + col * bpp;
                    let dst = (row * raw_w + col) * 4;
                    if src + bpp <= data.len() && dst + 4 <= pixels.len() {
                        pixels[dst]     = data[src];
                        pixels[dst + 1] = data[src + 1];
                        pixels[dst + 2] = data[src + 2];
                        pixels[dst + 3] = 255;
                    }
                }
            }
            write_png("frame_full_raw.png", raw_w, img_h, &pixels);
            if raw_w != img_w {
                println!("  frame_full_raw.png  → {}x{} (includes {} padding pixels per row)",
                    raw_w, img_h, raw_w - img_w);
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // PNG 5: Jika stride != tight, buat juga versi dengan packed emit_frame
    // Ini mensimulasikan persis apa yang dikirim ke Flutter
    // ──────────────────────────────────────────────────────────────────────
    {
        let tight_stride = img_w * bpp;
        let mut packed = vec![0u8; img_w * img_h * 4];

        for row in 0..img_h {
            let src_start = row * stride;
            let src_end = src_start + tight_stride;
            let dst_start = row * tight_stride;
            let dst_end = dst_start + tight_stride;

            if src_end <= data.len() && dst_end <= packed.len() {
                packed[dst_start..dst_end].copy_from_slice(&data[src_start..src_end]);
            }
        }

        // Force alpha
        for p in packed.chunks_exact_mut(4) { p[3] = 0xFF; }

        write_png("frame_packed_emit.png", img_w, img_h, &packed);
    }

    // ── Print pixel samples ────────────────────────────────────────────
    // Sample at the center of screen (where updates actually happened)
    let sample_y = img_h / 2;
    let sample_x_start = img_w / 4;
    println!("\n  Pixel samples (center area, row {}):", sample_y);
    println!("  col  | byte[0]  byte[1]  byte[2]  byte[3] | interpretation");
    println!("  -----|--------------------------------------|--------------");
    for col in sample_x_start..( sample_x_start + 8).min(img_w) {
        let src = sample_y * stride + col * bpp;
        if src + 4 <= data.len() {
            println!("  {:4} |  {:3}      {:3}      {:3}      {:3}    | R={} G={} B={} A={} (if RGBA)",
                col,
                data[src], data[src+1], data[src+2], data[src+3],
                data[src], data[src+1], data[src+2], data[src+3],
            );
        }
    }
    // Also sample row 0
    println!("\n  Pixel samples (top-left corner, row 0):");
    for col in 0..8.min(img_w) {
        let src = col * bpp;
        if src + 4 <= data.len() {
            println!("  {:4} |  {:3}      {:3}      {:3}      {:3}    | R={} G={} B={} A={} (if RGBA)",
                col,
                data[src], data[src+1], data[src+2], data[src+3],
                data[src], data[src+1], data[src+2], data[src+3],
            );
        }
    }

    println!("\n  Stride info:");
    println!("  image.stride()    = {}", stride);
    println!("  width * bpp       = {} (tight)", img_w * bpp);
    println!("  difference        = {} bytes per row (padding)", stride.saturating_sub(img_w * bpp));

    println!("\nFiles saved:");
    println!("  frame_raw_stride.png  — gambar pakai image.stride()");
    println!("  frame_tight.png       — gambar pakai width*4 (no padding)");
    println!("  frame_bgr_swap.png    — gambar dengan B↔R swap");
    println!("  frame_full_raw.png    — buffer mentah termasuk padding");
    println!("  frame_packed_emit.png — simulasi emit_frame() output → ini yang diterima Flutter");
}

fn write_png(filename: &str, width: usize, height: usize, rgba: &[u8]) {
    assert_eq!(rgba.len(), width * height * 4, "PNG {}: size mismatch", filename);
    let path = Path::new(filename);
    let file = match File::create(path) {
        Ok(f) => f,
        Err(e) => { eprintln!("  ERROR creating {}: {}", filename, e); return; }
    };
    let mut w = BufWriter::new(file);
    let mut encoder = png::Encoder::new(&mut w, width as u32, height as u32);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = match encoder.write_header() {
        Ok(wr) => wr,
        Err(e) => { eprintln!("  ERROR writing PNG header {}: {}", filename, e); return; }
    };
    if let Err(e) = writer.write_image_data(rgba) {
        eprintln!("  ERROR writing PNG data {}: {}", filename, e);
    } else {
        println!("  ✓ {}", filename);
    }
}
