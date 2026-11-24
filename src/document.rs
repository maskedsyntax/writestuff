use iced::widget::text_editor::{self, Action, Content};
use serde::{Deserialize, Serialize};
use std::{
    io::Write,
    path::{Path, PathBuf},
};

pub type DocumentId = u64;

#[derive(Clone, Serialize, Deserialize)]
pub struct Snapshot {
    pub id: DocumentId,
    pub path: Option<PathBuf>,
    pub text: String,
    pub saved: String,
}

pub struct Document {
    pub id: DocumentId,
    pub path: Option<PathBuf>,
    pub content: Content,
    pub saved: String,
    pub text: String,
    pub words: usize,
    pub characters: usize,
    pub preview: Vec<iced::widget::markdown::Item>,
    undo: Vec<History>,
    redo: Vec<History>,
}

struct History {
    text: String,
    cursor: text_editor::Cursor,
}

impl Document {
    pub fn restore(s: Snapshot) -> Self {
        let mut doc = Self {
            id: s.id,
            path: s.path,
            content: Content::with_text(&s.text),
            saved: s.saved,
            text: s.text,
            words: 0,
            characters: 0,
            preview: vec![],
            undo: vec![],
            redo: vec![],
        };
        doc.refresh();
        doc
    }
    pub fn new(id: DocumentId) -> Self {
        Self::restore(Snapshot {
            id,
            path: None,
            text: String::new(),
            saved: String::new(),
        })
    }
    pub fn snapshot(&self) -> Snapshot {
        Snapshot {
            id: self.id,
            path: self.path.clone(),
            text: self.text.clone(),
            saved: self.saved.clone(),
        }
    }
    pub fn dirty(&self) -> bool {
        self.text != self.saved
    }
    pub fn name(&self) -> String {
        self.path
            .as_ref()
            .and_then(|p| p.file_name())
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_else(|| format!("Untitled {}", self.id))
    }
    pub fn is_markdown(&self) -> bool {
        self.path
            .as_ref()
            .and_then(|p| p.extension())
            .is_some_and(|e| e.eq_ignore_ascii_case("md") || e.eq_ignore_ascii_case("markdown"))
    }
    fn remember(&mut self) {
        if self.undo.len() == 200 {
            self.undo.remove(0);
        }
        self.undo.push(History {
            text: self.text.clone(),
            cursor: self.content.cursor(),
        });
        self.redo.clear();
    }
    fn refresh(&mut self) {
        self.words = self.text.split_whitespace().count();
        self.characters = self.text.chars().count();
        self.preview = if self.is_markdown() {
            crate::markdown::parse(&self.text)
        } else {
            vec![]
        };
    }
    pub fn action(&mut self, action: Action) {
        let edit = action.is_edit();
        if edit {
            self.remember();
        }
        self.content.perform(action);
        if edit {
            self.text = self.content.text();
            self.refresh();
        }
    }
    pub fn replace_text(&mut self, text: String) {
        if text == self.text {
            return;
        }
        self.remember();
        self.set_text(text);
    }
    fn set_text(&mut self, text: String) {
        self.content = Content::with_text(&text);
        self.text = text;
        self.refresh();
    }
    pub fn undo(&mut self, redo: bool) {
        let text = if redo {
            self.redo.pop()
        } else {
            self.undo.pop()
        };
        if let Some(history) = text {
            let current = History {
                text: self.text.clone(),
                cursor: self.content.cursor(),
            };
            if redo {
                self.undo.push(current);
            } else {
                self.redo.push(current);
            }
            self.set_text(history.text);
            self.content.move_to(history.cursor);
        }
    }
    pub fn saved(&mut self, path: PathBuf, text: String) {
        self.path = Some(path);
        self.saved = text;
        self.refresh();
    }
    pub fn select_bytes(&mut self, start: usize, end: usize) {
        // Iced forwards columns to cosmic-text as UTF-8 byte offsets.
        let position = |offset| {
            let prefix = &self.text[..offset];
            text_editor::Position {
                line: prefix.bytes().filter(|b| *b == b'\n').count(),
                column: prefix
                    .rsplit('\n')
                    .next()
                    .unwrap_or("")
                    .trim_end_matches('\r')
                    .len(),
            }
        };
        self.content.move_to(text_editor::Cursor {
            position: position(end),
            selection: Some(position(start)),
        });
    }
}

pub fn read(path: &Path) -> Result<(PathBuf, String), String> {
    let path = path.canonicalize().map_err(|e| e.to_string())?;
    let text = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
    Ok((path, text))
}

/// Write beside the destination and atomically replace it; preserve file permissions.
/// Compare against the last known disk contents before replacing an existing file.
pub fn write(path: &Path, text: &str, expected: Option<&str>) -> Result<(), String> {
    if let Some(expected) = expected {
        let disk = std::fs::read_to_string(path)
            .map_err(|e| format!("Cannot verify original file: {e}. Use Save as."))?;
        if disk != expected {
            return Err("The file changed on disk. Use Save as to preserve both versions.".into());
        }
    }
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let mut temp = tempfile::NamedTempFile::new_in(parent).map_err(|e| e.to_string())?;
    if let Ok(meta) = path.metadata() {
        temp.as_file()
            .set_permissions(meta.permissions())
            .map_err(|e| e.to_string())?;
    }
    temp.write_all(text.as_bytes()).map_err(|e| e.to_string())?;
    temp.as_file().sync_all().map_err(|e| e.to_string())?;
    temp.persist(path).map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn atomic_save_rejects_conflict_and_preserves_exact_text() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("note.md");
        write(&path, "hello\r\n世界", None).unwrap();
        assert_eq!(read(&path).unwrap().1, "hello\r\n世界");
        assert!(write(&path, "lost", Some("old")).is_err());
        assert_eq!(read(&path).unwrap().1, "hello\r\n世界");
        write(&path, "new", Some("hello\r\n世界")).unwrap();
        assert_eq!(read(&path).unwrap().1, "new");
    }
    #[test]
    fn history_and_saved_snapshot_are_independent() {
        let mut d = Document::new(1);
        d.replace_text("one".into());
        d.saved(PathBuf::from("note.txt"), "one".into());
        d.replace_text("two".into());
        assert!(d.dirty());
        d.undo(false);
        assert_eq!(d.text, "one");
        assert!(!d.dirty());
        d.undo(true);
        assert_eq!(d.text, "two");
        let restored = Document::restore(d.snapshot());
        assert_eq!(restored.text, "two");
        assert!(restored.dirty());
    }
    #[test]
    fn editing_preserves_crlf_and_final_newline() {
        let mut doc = Document::restore(Snapshot {
            id: 1,
            path: None,
            text: "one\r\ntwo\r\n".into(),
            saved: String::new(),
        });
        doc.select_bytes(0, 3);
        doc.action(Action::Edit(text_editor::Edit::Paste(std::sync::Arc::new(
            "first".into(),
        ))));
        assert_eq!(doc.text, "first\r\ntwo\r\n");
    }
}
