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

fn add_light(dst: Rgba<u8>, light: Rgba<u8>, strength: f32) -> Rgba<u8> {
    // Additive blend for "glow" (background is already opaque inside the icon).
    let s = strength.clamp(0.0, 1.5);
    if s <= 0.0 {
        return dst;
    }
    let r = (dst[0] as f32 + (light[0] as f32) * s).clamp(0.0, 255.0);
    let g = (dst[1] as f32 + (light[1] as f32) * s).clamp(0.0, 255.0);
    let b = (dst[2] as f32 + (light[2] as f32) * s).clamp(0.0, 255.0);
    Rgba([clamp_u8(r), clamp_u8(g), clamp_u8(b), dst[3]])
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

fn gaussian(x: f32, mu: f32, sigma: f32) -> f32 {
    let z = (x - mu) / sigma.max(1e-4);
    (-0.5 * z * z).exp()
}

fn golden_ribbon_y(t: f32, mid: f32, h: f32, phase: f32, offset: f32) -> f32 {
    // Shape inspired by the provided reference:
    // - a left "scoop" and a broad rise
    // - a gentle wiggle riding on top
    let dip = -0.22 * h * gaussian(t, 0.16, 0.18);
    let bump = 0.26 * h * gaussian(t, 0.70, 0.24);
    let wiggle = 0.075 * h * (std::f32::consts::TAU * 1.05 * t + phase).sin();
    mid + dip + bump + wiggle + offset
}

fn approx_ribbon_cos_factor(t: f32, mid: f32, h: f32, phase: f32, offset: f32, w: f32) -> f32 {
    // Approximate cos(theta) where theta is the curve angle,
    // used to convert vertical distance into approximate normal distance.
    let dt = 1.0 / 2048.0;
    let y0 = golden_ribbon_y(t - dt, mid, h, phase, offset);
    let y1 = golden_ribbon_y(t + dt, mid, h, phase, offset);
    let dy_dt = (y1 - y0) / (2.0 * dt);
    let dy_dx = dy_dt / w.max(1.0);
    1.0 / (1.0 + dy_dx * dy_dx).sqrt()
}

/// Draw the Remix app icon at a given resolution.
/// Render high-res once and downsample for crisp, anti-aliased edges.
fn draw_icon(resolution: u32) -> RgbaImage {
    let mut img = RgbaImage::new(resolution, resolution);

    // Black background with subtle depth (still reads as "black")
    let bg_top = color("#101117");
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

    // Golden light-curve palette (core + warm glow)
    let gold_core = color("#FFE8B0");
    let gold_hot = color("#FFD27A");
    let gold_warm = color("#FFB54A");
    let gold_deep = color("#FF8A1C");

    for y in 0..resolution {
        let ty = y as f32 / (resolution - 1).max(1) as f32;
        let base_bg = lerp_color(bg_top, bg_bottom, ty);

        for x in 0..resolution {
            if !in_rounded_rect(x, y, resolution, radius) {
                img.put_pixel(x, y, Rgba([0, 0, 0, 0]));
                continue;
            }

            // Subtle vignette
            let cx = (resolution as f32 - 1.0) * 0.5;
            let cy = (resolution as f32 - 1.0) * 0.5;
            let dx = (x as f32 - cx) / cx.max(1.0);
            let dy = (y as f32 - cy) / cy.max(1.0);
            let r2 = dx * dx + dy * dy;
            let vig = (1.0 - 0.22 * smoothstep(0.15, 1.0, r2.sqrt())).clamp(0.0, 1.0);
            let mut px = Rgba([
                clamp_u8((base_bg[0] as f32) * vig),
                clamp_u8((base_bg[1] as f32) * vig),
                clamp_u8((base_bg[2] as f32) * vig),
                255,
            ]);

            let xi = x as i32;
            let yi = y as i32;
            // Map ribbon parameterization to a "safe" inner width, but allow t < 0 and t > 1
            // so the glow can naturally extend towards the icon edges (no hard crop).
            let w = ((x1 - x0).max(1)) as f32;
            let t = (xi - x0) as f32 / w;
            let tc = t.clamp(0.0, 1.0);
            let yf = yi as f32;

            // Ribbon placement
            let mid = y0 as f32 + content_h * 0.50;
            let h = content_h;

            // Fade out to a thin tip on the right; allow a bright bloom on the left.
            let tip_fade = smoothstep(0.0, 0.10, 1.0 - tc);
            let head_boost = 1.0 + 0.95 * gaussian(t, 0.02, 0.10);

            // Color gradient along the ribbon (warmer at the head, paler at the tip)
            let grad_t = smoothstep(0.0, 1.0, tc);
            let warm = lerp_color(gold_deep, gold_hot, grad_t);
            let core = lerp_color(gold_warm, gold_core, grad_t * 0.9);
            let deep = lerp_color(color("#6B2B00"), gold_deep, grad_t);

            // Multiple strands to suggest a light ribbon (kept tight like the reference)
            let strands = [
                (-0.055 * h, 0.55, 1.00),
                (-0.015 * h, 1.05, 0.95),
                (0.025 * h, 1.55, 0.90),
            ];

            // Global glow under the ribbon body (helps form the "sheet" on the left)
            let body_y = golden_ribbon_y(t, mid, h, 0.85, 0.0);
            let body_cos = approx_ribbon_cos_factor(t, mid, h, 0.85, 0.0, w);
            let body_d = (yf - body_y).abs() * body_cos;
            let body_sigma = (h * 0.11).max(10.0);
            let body_i = gaussian(body_d, 0.0, body_sigma) * tip_fade * head_boost;
            px = add_light(px, gold_warm, body_i * 0.20);

            for (off, phase, weight) in strands {
                let yc = golden_ribbon_y(t, mid, h, phase, off);
                let cosf = approx_ribbon_cos_factor(t, mid, h, phase, off, w);
                let d = (yf - yc).abs() * cosf;

                // Taper thickness strongly towards the right tip
                let thick = lerp(h * 0.060, h * 0.014, smoothstep(0.10, 1.0, tc)) * weight;

                // Glow layers
                let core_sigma = (thick * 0.18).max(1.2);
                let mid_sigma = (thick * 0.55).max(2.8);
                let glow_sigma = (thick * 1.25).max(6.0);

                let i_core = gaussian(d, 0.0, core_sigma);
                let i_mid = gaussian(d, 0.0, mid_sigma);
                let i_glow = gaussian(d, 0.0, glow_sigma);

                let intensity = tip_fade * head_boost * weight;

                // Outer bloom (deep/warm), then hot glow, then bright core.
                px = add_light(px, deep, i_glow * 0.16 * intensity);
                px = add_light(px, warm, i_mid * 0.36 * intensity);
                px = add_light(px, core, i_core * 0.55 * intensity);

                // A thin highlight slightly above the strand to mimic specular
                let hi_y = yc - thick * 0.16;
                let dhi = (yf - hi_y).abs() * cosf;
                let i_hi = gaussian(dhi, 0.0, (thick * 0.14).max(1.0));
                px = add_light(px, gold_core, i_hi * 0.32 * intensity);
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
