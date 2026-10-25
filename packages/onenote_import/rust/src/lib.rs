//! Reads OneNote files with `onenote_parser` and returns their pages
//! as JSON, with every position converted to CSS pixels (96 dpi),
//! measured from the top left of the OneNote page.
//!
//! Saber lays the pages out itself; this crate only extracts them.

use std::ffi::{CStr, CString, c_char};
use std::fs::File;
use std::io;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::{Path, PathBuf};

use onenote_parser::Parser;
use onenote_parser::contents::{
    Content, Image, Ink, InkStroke, Outline, OutlineElement, OutlineItem, Table,
};
use onenote_parser::notebook::Notebook;
use onenote_parser::page::{Page, PageContent};
use onenote_parser::section::{Section, SectionEntry};
use serde::Serialize;
use typed_path::TypedPath;

/// Ink units per pixel: one ink unit is 0.01 mm.
const INK_UNITS_PER_PX: f32 = 2540.0 / 96.0;

/// Pixels per layout unit: layout offsets and sizes are in half inches.
const PX_PER_HALF_INCH: f32 = 48.0;

/// The height given to a line of typed text when laying out an outline.
const TEXT_LINE_HEIGHT: f32 = 20.0;

#[derive(Serialize, Default)]
pub struct ImportResult {
    pub sections: Vec<SectionOut>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Serialize)]
pub struct SectionOut {
    pub name: String,
    /// The names of the section groups that contain this section.
    pub groups: Vec<String>,
    pub pages: Vec<PageOut>,
}

#[derive(Serialize, Default)]
pub struct PageOut {
    pub title: String,
    /// The page's level in the page tree: 1 for pages, 2+ for subpages.
    pub level: i32,
    /// Seconds since the Unix epoch.
    pub created: i64,
    /// Seconds since the Unix epoch.
    pub updated: i64,
    pub strokes: Vec<StrokeOut>,
    pub images: Vec<ImageOut>,
    pub texts: Vec<TextOut>,
    /// Content that has no counterpart in Saber, e.g. tables.
    pub skipped: u32,
}

#[derive(Serialize)]
pub struct StrokeOut {
    /// Red, green and blue.
    pub rgb: [u8; 3],
    /// 255 is opaque.
    pub alpha: u8,
    /// The pen width in pixels.
    pub width: f32,
    /// 0 is a round pen tip, anything else is a rectangle (e.g. a highlighter).
    pub tip: u8,
    /// Absolute points as `[x0, y0, x1, y1, ...]`.
    pub points: Vec<f32>,
}

#[derive(Serialize)]
pub struct ImageOut {
    pub x: f32,
    pub y: f32,
    /// Zero if unknown; the image's own size is then used.
    pub width: f32,
    pub height: f32,
    /// The file the image was written to.
    pub file: String,
}

#[derive(Serialize)]
pub struct TextOut {
    pub x: f32,
    pub y: f32,
    /// The width of the outline the text is in, or 0 if unknown.
    pub width: f32,
    /// One paragraph; a table row is one paragraph with its cells
    /// separated by " | ".
    pub text: String,
}

/// Parses the OneNote file at [path] and writes its images to [image_dir].
///
/// `.one` files are sections, `.onepkg` files are exported notebooks
/// and `.onetoc2` files are notebooks whose sections lie next to them.
pub fn import_file(path: &Path, image_dir: &Path) -> ImportResult {
    match catch_unwind(AssertUnwindSafe(|| try_import_file(path, image_dir))) {
        Ok(Ok(result)) => result,
        Ok(Err(error)) => ImportResult {
            error: Some(error),
            ..Default::default()
        },
        Err(panic) => ImportResult {
            error: Some(format!(
                "The OneNote parser crashed: {}",
                panic
                    .downcast_ref::<String>()
                    .map(String::as_str)
                    .or_else(|| panic.downcast_ref::<&str>().copied())
                    .unwrap_or("unknown error")
            )),
            ..Default::default()
        },
    }
}

fn try_import_file(path: &Path, image_dir: &Path) -> Result<ImportResult, String> {
    let path_str = path.to_str().ok_or("The file path is not valid UTF-8")?;
    let typed_path = TypedPath::derive(path_str);
    let extension = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or_default()
        .to_lowercase();

    let parser = Parser::new();
    let mut writer = ImageWriter::new(image_dir);
    let mut sections = vec![];
    match extension.as_str() {
        "one" => {
            let section = parser
                .parse_section(typed_path)
                .map_err(|e| e.to_string())?;
            sections.push(convert_section(&section, &[], &mut writer));
        }
        "onepkg" => {
            let notebook = parser
                .parse_package(typed_path)
                .map_err(|e| e.to_string())?;
            convert_notebook(&notebook, &mut writer, &mut sections);
        }
        "onetoc2" => {
            let notebook = parser
                .parse_notebook(typed_path)
                .map_err(|e| e.to_string())?;
            convert_notebook(&notebook, &mut writer, &mut sections);
        }
        _ => return Err(format!("Not a OneNote file: {path_str}")),
    }

    Ok(ImportResult {
        sections,
        error: None,
    })
}

fn convert_notebook(notebook: &Notebook, writer: &mut ImageWriter, out: &mut Vec<SectionOut>) {
    convert_entries(notebook.entries(), &[], writer, out);
}

fn convert_entries(
    entries: &[SectionEntry],
    groups: &[String],
    writer: &mut ImageWriter,
    out: &mut Vec<SectionOut>,
) {
    for entry in entries {
        match entry {
            SectionEntry::Section(section) => out.push(convert_section(section, groups, writer)),
            SectionEntry::SectionGroup(group) => {
                let mut groups = groups.to_vec();
                groups.push(group.display_name().to_string());
                convert_entries(group.entries(), &groups, writer, out);
            }
        }
    }
}

fn convert_section(section: &Section, groups: &[String], writer: &mut ImageWriter) -> SectionOut {
    SectionOut {
        name: section.display_name().to_string(),
        groups: groups.to_vec(),
        pages: section
            .page_series()
            .iter()
            .flat_map(|series| series.pages())
            .map(|page| convert_page(page, writer))
            .collect(),
    }
}

fn convert_page(page: &Page, writer: &mut ImageWriter) -> PageOut {
    let mut out = PageOut {
        title: page.title_text().unwrap_or_default().trim().to_string(),
        level: page.level(),
        created: page.created_time().unix_timestamp(),
        updated: page.updated_time().unix_timestamp(),
        ..Default::default()
    };

    for content in page.contents() {
        match content {
            PageContent::Ink(ink) => {
                let origin = (
                    ink.offset_horizontal().unwrap_or_default() * PX_PER_HALF_INCH,
                    ink.offset_vertical().unwrap_or_default() * PX_PER_HALF_INCH,
                );
                push_ink(ink, origin, false, &mut out);
            }
            PageContent::Image(image) => {
                let x = image.offset_horizontal().unwrap_or_default() * PX_PER_HALF_INCH;
                let y = image.offset_vertical().unwrap_or_default() * PX_PER_HALF_INCH;
                push_image(image, x, y, writer, &mut out);
            }
            PageContent::Outline(outline) => push_outline(outline, writer, &mut out),
            PageContent::EmbeddedFile(_) | PageContent::Unknown => out.skipped += 1,
        }
    }

    out
}

/// Adds the strokes of [ink], offset by [origin].
///
/// Ink drawn on the page has absolute coordinates.
/// Ink inside an outline ([relative]) is moved so its top left is at [origin].
/// Returns the height of the ink in pixels.
fn push_ink(ink: &Ink, origin: (f32, f32), relative: bool, out: &mut PageOut) -> f32 {
    let mut strokes = vec![];
    collect_strokes(ink, &mut strokes);
    if strokes.is_empty() {
        return 0.0;
    }

    let paths: Vec<_> = strokes.iter().map(|s| s.absolute_path()).collect();
    let (mut min_x, mut min_y) = (f32::INFINITY, f32::INFINITY);
    let mut max_y = f32::NEG_INFINITY;
    for point in paths.iter().flatten() {
        min_x = min_x.min(point.x());
        min_y = min_y.min(point.y());
        max_y = max_y.max(point.y());
    }
    let shift = if relative { (min_x, min_y) } else { (0.0, 0.0) };

    for (stroke, path) in strokes.iter().zip(&paths) {
        if path.is_empty() {
            continue;
        }
        let points = path
            .iter()
            .flat_map(|p| {
                [
                    origin.0 + (p.x() - shift.0) / INK_UNITS_PER_PX,
                    origin.1 + (p.y() - shift.1) / INK_UNITS_PER_PX,
                ]
            })
            .collect();
        out.strokes.push(StrokeOut {
            rgb: colorref_to_rgb(stroke.color()),
            alpha: 255 - stroke.transparency().unwrap_or_default(),
            width: stroke.width() / INK_UNITS_PER_PX,
            tip: stroke.pen_tip().unwrap_or_default(),
            points,
        });
    }

    (max_y - min_y) / INK_UNITS_PER_PX
}

fn collect_strokes<'a>(ink: &'a Ink, out: &mut Vec<&'a InkStroke>) {
    out.extend(ink.ink_strokes());
    for child in ink.child_groups() {
        collect_strokes(child, out);
    }
}

/// A COLORREF stores red in the lowest byte.
fn colorref_to_rgb(color: Option<u32>) -> [u8; 3] {
    match color {
        Some(c) => [c as u8, (c >> 8) as u8, (c >> 16) as u8],
        None => [0, 0, 0],
    }
}

/// Returns the height of the image in pixels, or 0 if unknown.
fn push_image(image: &Image, x: f32, y: f32, writer: &mut ImageWriter, out: &mut PageOut) -> f32 {
    let Some(file) = writer.write(image) else {
        out.skipped += 1;
        return 0.0;
    };
    let width = image.layout_max_width().unwrap_or_default() * PX_PER_HALF_INCH;
    let height = image.layout_max_height().unwrap_or_default() * PX_PER_HALF_INCH;
    out.images.push(ImageOut {
        x,
        y,
        width,
        height,
        file,
    });
    height
}

/// Lays out the outline's contents top to bottom, one element per line.
///
/// OneNote does not store where an element inside an outline is drawn,
/// so this is an approximation.
fn push_outline(outline: &Outline, writer: &mut ImageWriter, out: &mut PageOut) {
    let x = outline.offset_horizontal().unwrap_or_default() * PX_PER_HALF_INCH;
    let mut y = outline.offset_vertical().unwrap_or_default() * PX_PER_HALF_INCH;
    let width = outline.layout_max_width().unwrap_or_default() * PX_PER_HALF_INCH;
    push_outline_items(outline.items(), x, &mut y, width, writer, out);
}

fn push_outline_items(
    items: &[OutlineItem],
    x: f32,
    y: &mut f32,
    width: f32,
    writer: &mut ImageWriter,
    out: &mut PageOut,
) {
    for item in items {
        match item {
            OutlineItem::Group(group) => {
                push_outline_items(group.outlines(), x, y, width, writer, out)
            }
            OutlineItem::Element(element) => {
                // A list item starts with a bullet; numbering is not kept.
                let bullet = if element.list_contents().is_empty() {
                    ""
                } else {
                    "• "
                };
                for content in element.contents() {
                    let height = match content {
                        Content::RichText(text) => {
                            let text = text.text().trim_end();
                            if text.is_empty() {
                                0.0
                            } else {
                                push_text(format!("{bullet}{text}"), x, *y, width, out)
                            }
                        }
                        Content::Image(image) => push_image(image, x, *y, writer, out),
                        Content::Ink(ink) => push_ink(ink, (x, *y), true, out),
                        Content::Table(table) => push_table(table, x, *y, width, out),
                        Content::EmbeddedFile(_) | Content::Unknown => {
                            out.skipped += 1;
                            TEXT_LINE_HEIGHT
                        }
                    };
                    *y += height;
                }
                // Children are indented like a nested list.
                let indent = PX_PER_HALF_INCH / 2.0;
                push_outline_items(
                    element.children(),
                    x + indent,
                    y,
                    (width - indent).max(0.0),
                    writer,
                    out,
                );
            }
        }
    }
}

/// Adds a paragraph of text and returns its height in pixels.
fn push_text(text: String, x: f32, y: f32, width: f32, out: &mut PageOut) -> f32 {
    let height = text.lines().count() as f32 * TEXT_LINE_HEIGHT;
    out.texts.push(TextOut { x, y, width, text });
    height
}

/// Adds each row of [table] as a paragraph and returns their height in pixels.
///
/// Only the text of the cells is kept, not the table's layout.
fn push_table(table: &Table, x: f32, y: f32, width: f32, out: &mut PageOut) -> f32 {
    let mut height = 0.0;
    for row in table.contents() {
        let cells: Vec<String> = row
            .contents()
            .iter()
            .map(|cell| {
                let mut text = String::new();
                for element in cell.contents() {
                    collect_text(element, &mut text);
                }
                text
            })
            .collect();
        if cells.iter().all(|cell| cell.is_empty()) {
            continue;
        }
        height += push_text(cells.join(" | "), x, y + height, width, out);
    }
    height
}

/// Appends the text of [element] and its children to [text] on one line.
fn collect_text(element: &OutlineElement, text: &mut String) {
    for content in element.contents() {
        if let Content::RichText(rich_text) = content {
            for line in rich_text.text().lines() {
                let line = line.trim();
                if !line.is_empty() {
                    if !text.is_empty() {
                        text.push(' ');
                    }
                    text.push_str(line);
                }
            }
        }
    }
    for child in element.children() {
        if let OutlineItem::Element(child) = child {
            collect_text(child, text);
        }
    }
}

/// Writes images to numbered files in a directory.
struct ImageWriter {
    dir: PathBuf,
    count: usize,
}

impl ImageWriter {
    fn new(dir: &Path) -> Self {
        Self {
            dir: dir.to_path_buf(),
            count: 0,
        }
    }

    /// Returns the file name, or `None` if the image data is missing.
    fn write(&mut self, image: &Image) -> Option<String> {
        let mut reader = image.read()?;
        let extension = image
            .extension()
            .map(|e| e.trim_start_matches('.').to_lowercase())
            .filter(|e| !e.is_empty())
            .unwrap_or_else(|| "png".to_string());
        let name = format!("{}.{}", self.count, extension);
        let mut file = File::create(self.dir.join(&name)).ok()?;
        io::copy(&mut reader, &mut file).ok()?;
        self.count += 1;
        Some(name)
    }
}

/// Parses the OneNote file at [path], writing its images to [image_dir].
///
/// Returns JSON that must be freed with [onenote_import_free].
///
/// # Safety
/// Both arguments must be valid, null-terminated UTF-8 strings.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn onenote_import_file(
    path: *const c_char,
    image_dir: *const c_char,
) -> *mut c_char {
    let result = match unsafe {
        (
            CStr::from_ptr(path).to_str(),
            CStr::from_ptr(image_dir).to_str(),
        )
    } {
        (Ok(path), Ok(image_dir)) => import_file(Path::new(path), Path::new(image_dir)),
        _ => ImportResult {
            error: Some("The file path is not valid UTF-8".to_string()),
            ..Default::default()
        },
    };
    let json = serde_json::to_string(&result)
        .unwrap_or_else(|e| format!("{{\"sections\":[],\"error\":\"{e}\"}}"));
    CString::new(json)
        .expect("JSON never contains a null byte")
        .into_raw()
}

/// Frees a string returned by [onenote_import_file].
///
/// # Safety
/// [json] must come from [onenote_import_file] and not be freed already.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn onenote_import_free(json: *mut c_char) {
    if !json.is_null() {
        drop(unsafe { CString::from_raw(json) });
    }
}
