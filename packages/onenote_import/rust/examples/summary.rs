//! Prints what would be imported from OneNote files:
//! `cargo run --example summary -- <file.one>...`

use std::path::Path;

fn main() {
    let image_dir = std::env::temp_dir().join("onenote_import_summary");
    std::fs::create_dir_all(&image_dir).unwrap();
    for arg in std::env::args().skip(1) {
        let result = onenote_import::import_file(Path::new(&arg), &image_dir);
        println!("{arg}");
        if let Some(error) = result.error {
            println!("  error: {error}");
        }
        for section in result.sections {
            println!("  section {:?} in {:?}", section.name, section.groups);
            for page in section.pages {
                let points: usize = page.strokes.iter().map(|s| s.points.len() / 2).sum();
                println!(
                    "    page {:?} (level {}): {} strokes, {} points, {} images, {} texts, {} skipped",
                    page.title,
                    page.level,
                    page.strokes.len(),
                    points,
                    page.images.len(),
                    page.texts.len(),
                    page.skipped,
                );
            }
        }
    }
}
