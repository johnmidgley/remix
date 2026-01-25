//! Generate app icon for Remix
//!
//! Creates PNG icons at various sizes and converts to .icns using iconutil.
//! Replaces the Python generate_app_icon.py script.

use image::{imageops::FilterType, DynamicImage, Rgba, RgbaImage};
use std::path::Path;
use std::process::Command;

/// Color from hex string
fn color(hex: &str) -> Rgba<u8> {
    let hex = hex.trim_start_matches('#');
    let r = u8::from_str_radix(&hex[0..2], 16).unwrap();
    let g = u8::from_str_radix(&hex[2..4], 16).unwrap();
    let b = u8::from_str_radix(&hex[4..6], 16).unwrap();
    Rgba([r, g, b, 255])
}

fn clamp_u8(v: f32) -> u8 {
    v.round().clamp(0.0, 255.0) as u8
}

fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

fn lerp_color(a: Rgba<u8>, b: Rgba<u8>, t: f32) -> Rgba<u8> {
    let t = t.clamp(0.0, 1.0);
    Rgba([
        clamp_u8(lerp(a[0] as f32, b[0] as f32, t)),
        clamp_u8(lerp(a[1] as f32, b[1] as f32, t)),
        clamp_u8(lerp(a[2] as f32, b[2] as f32, t)),
        clamp_u8(lerp(a[3] as f32, b[3] as f32, t)),
    ])
}

fn with_alpha(c: Rgba<u8>, a: f32) -> Rgba<u8> {
    let a = a.clamp(0.0, 1.0);
    Rgba([c[0], c[1], c[2], clamp_u8(255.0 * a)])
}

fn blend_over(dst: Rgba<u8>, src: Rgba<u8>) -> Rgba<u8> {
    let sa = (src[3] as f32) / 255.0;
    if sa <= 0.0 {
        return dst;
    }
    let da = (dst[3] as f32) / 255.0;

    // Straight alpha blending
    let out_a = sa + da * (1.0 - sa);
    if out_a <= 0.0 {
        return Rgba([0, 0, 0, 0]);
    }

    let out_r = (src[0] as f32) * sa + (dst[0] as f32) * da * (1.0 - sa);
    let out_g = (src[1] as f32) * sa + (dst[1] as f32) * da * (1.0 - sa);
    let out_b = (src[2] as f32) * sa + (dst[2] as f32) * da * (1.0 - sa);

    Rgba([
        clamp_u8(out_r / out_a),
        clamp_u8(out_g / out_a),
        clamp_u8(out_b / out_a),
        clamp_u8(out_a * 255.0),
    ])
}

/// Check if point is inside rounded rectangle
fn in_rounded_rect(x: u32, y: u32, size: u32, radius: u32) -> bool {
    let x = x as i32;
    let y = y as i32;
    let size = size as i32;
    let radius = radius as i32;
    
    // Check corners
    if x < radius && y < radius {
        let dx = radius - x;
        let dy = radius - y;
        return dx * dx + dy * dy <= radius * radius;
    }
    if x >= size - radius && y < radius {
        let dx = x - (size - radius - 1);
        let dy = radius - y;
        return dx * dx + dy * dy <= radius * radius;
    }
    if x < radius && y >= size - radius {
        let dx = radius - x;
        let dy = y - (size - radius - 1);
        return dx * dx + dy * dy <= radius * radius;
    }
    if x >= size - radius && y >= size - radius {
        let dx = x - (size - radius - 1);
        let dy = y - (size - radius - 1);
        return dx * dx + dy * dy <= radius * radius;
    }
    
    true
}

fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

fn waveform_y(t: f32, base: f32, amp: f32, freq: f32, phase: f32) -> f32 {
    // Mostly-sine waveform with gentle, non-chaotic variability:
    // - slight amplitude envelope
    // - tiny 2nd harmonic for character
    let w = std::f32::consts::TAU * freq;
    let env = 0.92 + 0.08 * (std::f32::consts::TAU * 0.55 * t + phase * 0.18).sin();
    let s1 = (w * t + phase).sin();
    let s2 = (w * 2.0 * t + phase * 0.63).sin();
    base + (amp * env) * (0.88 * s1 + 0.12 * s2)
}

/// Draw the Remix app icon at a given resolution.
/// Render high-res once and downsample for crisp, anti-aliased edges.
fn draw_icon(resolution: u32) -> RgbaImage {
    let mut img = RgbaImage::new(resolution, resolution);

    // Black background with subtle depth (still reads as "black")
    let bg_top = color("#111216");
    let bg_bottom = color("#05060A");

    // Rounded rect parameters
    let radius = (resolution as f32 * 0.21) as u32;

    // Content inset (gives breathing room like SF/App icons)
    let inset = (resolution as f32 * 0.11) as i32;
    let x0 = inset;
    let x1 = resolution as i32 - inset - 1;
    let y0 = inset;
    let y1 = resolution as i32 - inset - 1;
    let content_h = (y1 - y0).max(1) as f32;

    // 5 waveform strokes (Apple system colors)
    // User requested: add Red back in too.
    let stroke_colors = [
        color("#FF3B30"), // red
        color("#34C759"), // green
        color("#007AFF"), // blue
        color("#FF9500"), // orange
        color("#FFCC00"), // yellow
    ];
    let stroke_count = stroke_colors.len() as i32;

    // Waveform geometry
    let freq = 1.28;
    let amp_base = content_h * 0.12;
    let stroke_half = (content_h * 0.028).clamp(6.0, content_h * 0.05);
    let shadow = with_alpha(color("#000000"), 0.35);
    let shadow_offset = (resolution as f32 * 0.005).clamp(2.0, 14.0);

    for y in 0..resolution {
        let ty = y as f32 / (resolution - 1).max(1) as f32;
        let bg = lerp_color(bg_top, bg_bottom, ty);

        for x in 0..resolution {
            if !in_rounded_rect(x, y, resolution, radius) {
                img.put_pixel(x, y, Rgba([0, 0, 0, 0]));
                continue;
            }

            let mut px = bg;

            let xi = x as i32;
            let yi = y as i32;
            if xi >= x0 && xi <= x1 && yi >= y0 && yi <= y1 {
                let t = (xi - x0) as f32 / ((x1 - x0).max(1)) as f32;
                let yf = yi as f32;

                // Center the 5 waveforms vertically within the content area.
                // Use tighter spacing so they can overlap a bit.
                let top_pad = content_h * 0.22;
                let bottom_pad = content_h * 0.22;
                let usable_h = (content_h - top_pad - bottom_pad).max(1.0);
                let spacing = (usable_h / (stroke_count as f32 - 1.0).max(1.0)) * 0.82;

                // Fade in/out near left/right edges for rounded stroke ends.
                let edge_w = 0.065;
                let edge_fade = smoothstep(0.0, edge_w, t) * smoothstep(0.0, edge_w, 1.0 - t);

                // Draw each waveform as a stroked curve with soft edges.
                for i in 0..stroke_count {
                    let base_y = y0 as f32 + top_pad + spacing * (i as f32);
                    let amp = amp_base * (0.92 + 0.04 * (i as f32));
                    let phase = 0.35 + 0.92 * (i as f32);
                    let f = freq * (1.0 + 0.035 * (i as f32));
                    let yc = waveform_y(t, base_y, amp, f, phase);

                    // Distance from current pixel row to the curve.
                    let d = (yf - yc).abs();

                    // Anti-aliased stroke coverage (soft edge).
                    let a = (1.0 - smoothstep(stroke_half - 1.25, stroke_half + 1.25, d)) * edge_fade;
                    if a <= 0.0 {
                        continue;
                    }

                    // Subtle shadow below the stroke for separation.
                    let ds = (yf - (yc + shadow_offset)).abs();
                    let as_ =
                        (1.0 - smoothstep(stroke_half - 1.0, stroke_half + 2.0, ds)) * edge_fade;
                    if as_ > 0.0 {
                        px = blend_over(px, with_alpha(shadow, as_ * 0.55));
                    }

                    let c = stroke_colors[i as usize];
                    px = blend_over(px, with_alpha(c, a));
                }
            }

            img.put_pixel(x, y, px);
        }
    }

    img
}

fn render_icon(size: u32) -> RgbaImage {
    // Render high-res once and downsample for clean edges at small sizes.
    let render_size = (size * 4).max(1024).min(4096);
    let hi = draw_icon(render_size);
    if render_size == size {
        return hi;
    }
    let dyn_img = DynamicImage::ImageRgba8(hi);
    dyn_img
        .resize_exact(size, size, FilterType::Lanczos3)
        .to_rgba8()
}

/// Generate all icon sizes for macOS iconset
fn generate_iconset(output_dir: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(output_dir)?;
    
    let sizes = [16u32, 32, 64, 128, 256, 512, 1024];
    
    for &size in &sizes {
        let img = render_icon(size);
        let path = output_dir.join(format!("icon_{}x{}.png", size, size));
        img.save(&path).expect("Failed to save icon");
        println!("Generated: {}", path.display());
        
        // @2x versions (except for 1024)
        if size <= 512 {
            let img_2x = render_icon(size * 2);
            let path_2x = output_dir.join(format!("icon_{}x{}@2x.png", size, size));
            img_2x.save(&path_2x).expect("Failed to save @2x icon");
            println!("Generated: {}", path_2x.display());
        }
    }
    
    Ok(())
}

fn main() {
    // Determine output directory
    let exe_path = std::env::current_exe().expect("Failed to get exe path");
    let project_root = exe_path
        .parent() // target/release or target/debug
        .and_then(|p| p.parent()) // target
        .and_then(|p| p.parent()) // project root
        .expect("Failed to find project root");
    
    let iconset_dir = project_root.join("scripts").join("Remix.iconset");
    let icns_path = project_root.join("scripts").join("Remix.icns");
    
    // Clear existing iconset
    if iconset_dir.exists() {
        for entry in std::fs::read_dir(&iconset_dir).unwrap() {
            let entry = entry.unwrap();
            std::fs::remove_file(entry.path()).ok();
        }
    }
    
    // Generate iconset
    println!("Generating iconset at: {}", iconset_dir.display());
    generate_iconset(&iconset_dir).expect("Failed to generate iconset");
    
    // Convert to .icns using iconutil (macOS only)
    println!("Converting to .icns...");
    let status = Command::new("iconutil")
        .args(["-c", "icns"])
        .arg(&iconset_dir)
        .arg("-o")
        .arg(&icns_path)
        .status()
        .expect("Failed to run iconutil");
    
    if status.success() {
        println!("Created: {}", icns_path.display());
    } else {
        eprintln!("iconutil failed with status: {}", status);
        std::process::exit(1);
    }
}
