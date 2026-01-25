//! Generate app icon for Remix
//!
//! Creates PNG icons at various sizes and converts to .icns using iconutil.
//! Replaces the Python generate_app_icon.py script.

use image::{Rgba, RgbaImage};
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

/// Draw the Remix app icon
fn draw_icon(size: u32) -> RgbaImage {
    let mut img = RgbaImage::new(size, size);
    
    // Colors - dark gradient background
    let top = color("#2C2F38");
    let bottom = color("#12151B");
    let wave_color = color("#E8EEF6");
    
    // Rounded rect parameters
    let radius = (size as f32 * 0.2) as u32;
    
    // Background with vertical gradient
    for y in 0..size {
        let t = y as f32 / (size - 1) as f32;
        let r = (top[0] as f32 * (1.0 - t) + bottom[0] as f32 * t) as u8;
        let g = (top[1] as f32 * (1.0 - t) + bottom[1] as f32 * t) as u8;
        let b = (top[2] as f32 * (1.0 - t) + bottom[2] as f32 * t) as u8;
        let row_color = Rgba([r, g, b, 255]);
        
        for x in 0..size {
            if in_rounded_rect(x, y, size, radius) {
                img.put_pixel(x, y, row_color);
            } else {
                img.put_pixel(x, y, Rgba([0, 0, 0, 0]));
            }
        }
    }
    
    // Waveform bars
    let bar_count = 5;
    let bar_width = (size as f32 * 0.09) as i32;
    let bar_spacing = (size as f32 * 0.06) as i32;
    let bar_heights = [0.35f32, 0.6, 0.82, 0.6, 0.35];
    
    let total_width = bar_count * bar_width + (bar_count - 1) * bar_spacing;
    let start_x = (size as i32 - total_width) / 2;
    let center_y = size as i32 / 2;
    let cap_radius = bar_width / 2;
    
    for i in 0..bar_count as usize {
        let h = (size as f32 * bar_heights[i]) as i32;
        let x0 = start_x + i as i32 * (bar_width + bar_spacing);
        let x1 = x0 + bar_width - 1;
        let y0 = center_y - h / 2;
        let y1 = center_y + h / 2;
        
        // Draw bar rectangle
        for y in y0..=y1 {
            for x in x0..=x1 {
                if x >= 0 && x < size as i32 && y >= 0 && y < size as i32 {
                    img.put_pixel(x as u32, y as u32, wave_color);
                }
            }
        }
        
        // Rounded caps (top)
        let cx = x0 + bar_width / 2;
        for y in (y0 - cap_radius)..=(y0 + cap_radius) {
            for x in (cx - cap_radius)..=(cx + cap_radius) {
                let dx = x - cx;
                let dy = y - y0;
                if dx * dx + dy * dy <= cap_radius * cap_radius {
                    if x >= 0 && x < size as i32 && y >= 0 && y < size as i32 {
                        img.put_pixel(x as u32, y as u32, wave_color);
                    }
                }
            }
        }
        
        // Rounded caps (bottom)
        for y in (y1 - cap_radius)..=(y1 + cap_radius) {
            for x in (cx - cap_radius)..=(cx + cap_radius) {
                let dx = x - cx;
                let dy = y - y1;
                if dx * dx + dy * dy <= cap_radius * cap_radius {
                    if x >= 0 && x < size as i32 && y >= 0 && y < size as i32 {
                        img.put_pixel(x as u32, y as u32, wave_color);
                    }
                }
            }
        }
    }
    
    img
}

/// Generate all icon sizes for macOS iconset
fn generate_iconset(output_dir: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(output_dir)?;
    
    let sizes = [16u32, 32, 64, 128, 256, 512, 1024];
    
    for &size in &sizes {
        let img = draw_icon(size);
        let path = output_dir.join(format!("icon_{}x{}.png", size, size));
        img.save(&path).expect("Failed to save icon");
        println!("Generated: {}", path.display());
        
        // @2x versions (except for 1024)
        if size <= 512 {
            let img_2x = draw_icon(size * 2);
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
