use crate::{
    document::{self, Document, DocumentId},
    panes::Panes,
    settings::{self, Appearance, Session, Settings, Typeface},
};
use iced::{
    Element,
    Length::Fill,
    Subscription, Task, Theme,
    keyboard::{self, Key, Modifiers},
    widget::{
        self, button, checkbox, column, container, mouse_area, pane_grid, pick_list, row,
        scrollable, slider, space, text, text_input,
    },
};
use std::{collections::BTreeMap, path::PathBuf};

pub struct App {
    system_dark: bool,
    documents: BTreeMap<DocumentId, Document>,
    tabs: Vec<DocumentId>,
    panes: Panes,
    next_id: u64,
    settings: Settings,
    settings_open: bool,
    find_open: bool,
    query: String,
    replacement: String,
    find_offset: usize,
    notice: Option<String>,
    confirm: Option<DocumentId>,
    quitting: bool,
    saving: Option<DocumentId>,
    dragging: Option<DocumentId>,
    generation: u64,
    persisting: bool,
    persist_again: bool,
    exit_after_persist: bool,
}
#[derive(Debug, Clone)]
pub enum Message {
    SystemTheme(iced::theme::Mode),
    New,
    FileAction(FileAction),
    CloseActivePane,
    Open,
    Opened(Result<Option<(PathBuf, String)>, String>),
    Save(bool),
    Saved(DocumentId, String, Result<Option<PathBuf>, String>),
    Close(DocumentId),
    Discard,
    Cancel,
    SaveClose,
    Edit(pane_grid::Pane, DocumentId, widget::text_editor::Action),
    Undo(bool),
    Split(pane_grid::Axis),
    Focus(pane_grid::Pane),
    ClosePane(pane_grid::Pane),
    Resize(pane_grid::ResizeEvent),
    DragPane(pane_grid::DragEvent),
    DragTab(DocumentId),
    HoverTab(DocumentId),
    Release,
    Preview,
    Settings,
    Appearance(Appearance),
    Font(Typeface),
    Size(f32),
    LineHeight(f32),
    Wrap(bool),
    Status(bool),
    Find,
    Query(String),
    Replacement(String),
    FindNext,
    Replace,
    ReplaceAll,
    Dismiss,
    Link(widget::markdown::Uri),
    Quit,
    Checkpoint(u64),
    Persisted(Result<(), String>),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileAction {
    Open,
    Save,
    SaveAs,
    Find,
}
impl std::fmt::Display for FileAction {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::Open => "Open…",
            Self::Save => "Save",
            Self::SaveAs => "Save as…",
            Self::Find => "Find and replace…",
        })
    }
}

pub fn shortcut(key: &Key, modifiers: Modifiers) -> Option<Message> {
    if !modifiers.command() || modifiers.alt() {
        return None;
    }
    let Key::Character(key) = key else {
        return None;
    };
    Some(match key.to_lowercase().as_str() {
        "n" | "t" => Message::New,
        "o" => Message::Open,
        "s" => Message::Save(modifiers.shift()),
        "w" if modifiers.shift() => Message::CloseActivePane,
        "w" => Message::Close(0),
        "d" => Message::Split(if modifiers.shift() {
            pane_grid::Axis::Horizontal
        } else {
            pane_grid::Axis::Vertical
        }),
        "f" => Message::Find,
        "," => Message::Settings,
        "z" => Message::Undo(modifiers.shift()),
        "y" if !cfg!(target_os = "macos") => Message::Undo(true),
        "=" | "+" => Message::Size(-1.0),
        "-" => Message::Size(-2.0),
        _ => return None,
    })
}
impl App {
    pub fn new() -> (Self, Task<Message>) {
        let (session, notice) = match settings::load() {
            Ok(s) => s,
            Err(e) => (Session::default(), Some(e)),
        };
        let app = Self::from_session(session, notice);
        let tasks = std::env::args_os().skip(1).map(PathBuf::from).map(|path| {
            Task::perform(
                async move {
                    tokio::task::spawn_blocking(move || document::read(&path))
                        .await
                        .map_err(|e| e.to_string())?
                        .map(Some)
                },
                Message::Opened,
            )
        });
        (
            app,
            Task::batch(tasks.chain(std::iter::once(
                iced::system::theme().map(Message::SystemTheme),
            ))),
        )
    }
    fn from_session(session: Session, notice: Option<String>) -> Self {
        let mut documents = BTreeMap::new();
        let mut tabs = vec![];
        for snapshot in session.documents {
            if documents.contains_key(&snapshot.id) {
                continue;
            }
            tabs.push(snapshot.id);
            documents.insert(snapshot.id, Document::restore(snapshot));
        }
        if tabs.is_empty() {
            tabs.push(1);
            documents.insert(1, Document::new(1));
        }
        let active = session
            .active
            .filter(|id| documents.contains_key(id))
            .unwrap_or(tabs[0]);
        let next_id = tabs.iter().max().unwrap() + 1;
        let mut settings = session.settings;
        settings.size = settings.size.clamp(10.0, 40.0);
        settings.line_height = settings.line_height.clamp(1.0, 2.4);
        Self {
            system_dark: false,
            documents,
            tabs,
            panes: Panes::new(active),
            next_id,
            settings,
            settings_open: false,
            find_open: false,
            query: String::new(),
            replacement: String::new(),
            find_offset: 0,
            notice,
            confirm: None,
            quitting: false,
            saving: None,
            dragging: None,
            generation: 0,
            persisting: false,
            persist_again: false,
            exit_after_persist: false,
        }
    }
    fn focus_editor(&self) -> Task<Message> {
        widget::operation::focus(crate::editor::id(self.panes.active))
    }
    fn active(&self) -> DocumentId {
        self.panes.document()
    }
    pub fn title(&self) -> String {
        format!(
            "{}{} — writestuff",
            self.documents[&self.active()].name(),
            if self.documents[&self.active()].dirty() {
                " •"
            } else {
                ""
            }
        )
    }
    pub fn theme(&self) -> Option<Theme> {
        Some(crate::style::theme(match self.settings.appearance {
            Appearance::System => self.system_dark,
            Appearance::Light => false,
            Appearance::Dark => true,
        }))
    }
    pub fn subscription(&self) -> Subscription<Message> {
        Subscription::batch([
            iced::system::theme_changes().map(Message::SystemTheme),
            iced::event::listen_with(|event, status, _| match event {
                iced::Event::Keyboard(keyboard::Event::KeyPressed { key, modifiers, .. })
                    if status == iced::event::Status::Ignored =>
                {
                    shortcut(&key, modifiers)
                }
                iced::Event::Mouse(iced::mouse::Event::ButtonReleased(
                    iced::mouse::Button::Left,
                )) => Some(Message::Release),
                _ => None,
            }),
            iced::window::close_requests().map(|_| Message::Quit),
        ])
    }
    fn checkpoint(&mut self) -> Task<Message> {
        self.generation += 1;
        let generation = self.generation;
        Task::perform(
            async move {
                tokio::time::sleep(std::time::Duration::from_millis(700)).await;
                generation
            },
            Message::Checkpoint,
        )
    }
    fn persist(&mut self) -> Task<Message> {
        if self.persisting {
            self.persist_again = true;
            return Task::none();
        }
        self.persisting = true;
        let session = Session {
            settings: self.settings.clone(),
            documents: self
                .tabs
                .iter()
                .map(|id| self.documents[id].snapshot())
                .collect(),
            active: Some(self.active()),
        };
        Task::perform(
            async move {
                tokio::task::spawn_blocking(move || settings::save(&session))
                    .await
                    .map_err(|e| e.to_string())?
            },
            Message::Persisted,
        )
    }
    fn new_document(&mut self) {
        let id = self.next_id;
        self.next_id += 1;
        self.documents.insert(id, Document::new(id));
        self.tabs.push(id);
        self.panes.select(id);
    }
    fn remove(&mut self, id: DocumentId) {
        let affected: Vec<_> = self
            .panes
            .state
            .iter()
            .filter(|(_, pane)| pane.document == id)
            .map(|(pane, _)| *pane)
            .collect();
        self.documents.remove(&id);
        self.tabs.retain(|tab| *tab != id);
        if self.tabs.is_empty() {
            self.new_document();
        }
        // Prefer another hidden tab. If every remaining document is already visible,
        // remove the empty view rather than unexpectedly mirroring a neighboring pane.
        let replacement = self
            .tabs
            .iter()
            .find(|tab| {
                !self
                    .panes
                    .state
                    .iter()
                    .any(|(pane, state)| !affected.contains(pane) && state.document == **tab)
            })
            .copied();
        for pane in affected {
            if let Some(replacement) = replacement {
                self.panes.state.get_mut(pane).unwrap().document = replacement;
            } else if self.panes.state.len() > 1 {
                self.panes.close(pane);
            } else {
                self.panes.state.get_mut(pane).unwrap().document = self.tabs[0];
            }
        }
        self.confirm = None;
    }
    fn quit_next(&mut self) -> Task<Message> {
        if let Some(id) = self
            .tabs
            .iter()
            .find(|id| self.documents[id].dirty())
            .copied()
        {
            self.confirm = Some(id);
            Task::none()
        } else {
            self.exit_after_persist = true;
            self.persist()
        }
    }
    pub fn update(&mut self, message: Message) -> Task<Message> {
        if self.exit_after_persist && !matches!(message, Message::Persisted(_)) {
            return Task::none();
        }
        // Confirmation blocks document mutation and shortcuts behind the prompt.
        if self.confirm.is_some()
            && !matches!(
                message,
                Message::Discard
                    | Message::Cancel
                    | Message::SaveClose
                    | Message::Saved(..)
                    | Message::Checkpoint(_)
                    | Message::Persisted(_)
                    | Message::Dismiss
            )
        {
            return Task::none();
        }
        match message {
            Message::SystemTheme(mode) => {
                self.system_dark = mode == iced::theme::Mode::Dark;
                return Task::none();
            }
            Message::New => {
                self.new_document();
                return Task::batch([self.checkpoint(), self.focus_editor()]);
            }
            Message::FileAction(action) => {
                return self.update(match action {
                    FileAction::Open => Message::Open,
                    FileAction::Save => Message::Save(false),
                    FileAction::SaveAs => Message::Save(true),
                    FileAction::Find => Message::Find,
                });
            }
            Message::CloseActivePane => {
                self.panes.close(self.panes.active);
                return Task::batch([self.checkpoint(), self.focus_editor()]);
            }
            Message::Open => {
                return Task::perform(
                    async {
                        let Some(file) = rfd::AsyncFileDialog::new()
                            .set_title("Open text file")
                            .pick_file()
                            .await
                        else {
                            return Ok(None);
                        };
                        let path = file.path().to_owned();
                        tokio::task::spawn_blocking(move || document::read(&path))
                            .await
                            .map_err(|e| e.to_string())?
                            .map(Some)
                    },
                    Message::Opened,
                );
            }
            Message::Opened(result) => match result {
                Ok(Some((path, text))) => {
                    if let Some(id) = self
                        .tabs
                        .iter()
                        .find(|id| self.documents[id].path.as_ref() == Some(&path))
                        .copied()
                    {
                        self.panes.select(id);
                    } else {
                        self.new_document();
                        let id = self.active();
                        self.documents.insert(
                            id,
                            Document::restore(document::Snapshot {
                                id,
                                path: Some(path),
                                saved: text.clone(),
                                text,
                            }),
                        );
                    }
                }
                Ok(None) => return Task::none(),
                Err(e) => self.notice = Some(e),
            },
            Message::Save(as_new) => return self.save(self.active(), as_new),
            Message::Saved(id, text, result) => {
                self.saving = None;
                match result {
                    Ok(Some(path)) => {
                        if let Some(doc) = self.documents.get_mut(&id) {
                            doc.saved(path, text);
                        }
                        if self.confirm == Some(id) && !self.documents[&id].dirty() {
                            if self.quitting {
                                self.confirm = None;
                                return self.quit_next();
                            }
                            self.remove(id);
                            return Task::batch([self.checkpoint(), self.focus_editor()]);
                        }
                    }
                    Ok(None) => {}
                    Err(e) => self.notice = Some(e),
                }
            }
            Message::Edit(pane, id, action) => {
                self.panes.active = pane;
                let edit = action.is_edit();
                self.documents.get_mut(&id).unwrap().action(action);
                if !edit {
                    return Task::none();
                }
            }
            Message::Undo(redo) => self.documents.get_mut(&self.active()).unwrap().undo(redo),
            Message::Close(id) => {
                let id = if id == 0 { self.active() } else { id };
                if self.saving == Some(id) {
                    self.notice = Some("Wait for this document to finish saving.".into());
                    return Task::none();
                }
                if self.documents[&id].dirty() {
                    self.confirm = Some(id);
                } else {
                    self.remove(id);
                    return Task::batch([self.checkpoint(), self.focus_editor()]);
                }
            }
            Message::Discard => {
                if let Some(id) = self.confirm {
                    if self.saving.is_some() {
                        return Task::none();
                    }
                    self.remove(id);
                }
                if self.quitting {
                    return self.quit_next();
                }
                return Task::batch([self.checkpoint(), self.focus_editor()]);
            }
            Message::Cancel => {
                if self.saving.is_none() {
                    self.confirm = None;
                    self.quitting = false;
                }
            }
            Message::SaveClose => return self.save(self.confirm.unwrap(), false),
            Message::Quit => {
                self.quitting = true;
                return self.quit_next();
            }
            Message::Split(axis) => {
                if self.panes.state.len() >= 8 {
                    return Task::none();
                }
                let id = self.next_id;
                self.next_id += 1;
                self.documents.insert(id, Document::new(id));
                self.tabs.push(id);
                self.panes.split(axis, id);
                return Task::batch([self.checkpoint(), self.focus_editor()]);
            }
            Message::Focus(pane) => self.panes.active = pane,
            Message::ClosePane(pane) => {
                self.panes.close(pane);
                return Task::batch([self.checkpoint(), self.focus_editor()]);
            }
            Message::Resize(e) => {
                self.panes.state.resize(e.split, e.ratio);
                return Task::none();
            }
            Message::DragPane(pane_grid::DragEvent::Dropped { pane, target }) => {
                self.panes.state.drop(pane, target)
            }
            Message::DragPane(_) => return Task::none(),
            Message::DragTab(id) => {
                self.find_offset = 0;
                self.dragging = Some(id);
                self.panes.select(id);
                return Task::batch([self.checkpoint(), self.focus_editor()]);
            }
            Message::HoverTab(id) => {
                if let Some(from) = self.dragging {
                    let a = self.tabs.iter().position(|v| *v == from).unwrap();
                    let b = self.tabs.iter().position(|v| *v == id).unwrap();
                    if a != b {
                        self.tabs.remove(a);
                        self.tabs.insert(b, from);
                    }
                }
            }
            Message::Release => {
                self.dragging = None;
                return Task::none();
            }
            Message::Preview => {
                let pane = self.panes.state.get_mut(self.panes.active).unwrap();
                pane.preview = !pane.preview;
            }
            Message::Settings => self.settings_open = !self.settings_open,
            Message::Appearance(v) => self.settings.appearance = v,
            Message::Font(v) => self.settings.font = v,
            Message::Size(v) => {
                self.settings.size = (if v == -1.0 {
                    self.settings.size + 1.0
                } else if v == -2.0 {
                    self.settings.size - 1.0
                } else {
                    v
                })
                .clamp(10.0, 40.0)
            }
            Message::LineHeight(v) => self.settings.line_height = v,
            Message::Wrap(v) => self.settings.wrap = v,
            Message::Status(v) => self.settings.status = v,
            Message::Find => {
                self.find_open = !self.find_open;
                return widget::operation::focus("find");
            }
            Message::Query(v) => {
                self.query = v;
                self.find_offset = 0;
                return Task::none();
            }
            Message::Replacement(v) => {
                self.replacement = v;
                return Task::none();
            }
            Message::FindNext => {
                self.find_next();
                return Task::none();
            }
            Message::Replace => {
                if !self.query.is_empty() {
                    let id = self.active();
                    let doc = &self.documents[&id];
                    if doc.content.selection().as_deref() == Some(self.query.as_str()) {
                        self.documents.get_mut(&id).unwrap().action(
                            widget::text_editor::Action::Edit(widget::text_editor::Edit::Paste(
                                std::sync::Arc::new(self.replacement.clone()),
                            )),
                        );
                    }
                    self.find_next();
                }
            }
            Message::ReplaceAll => {
                if !self.query.is_empty() {
                    let id = self.active();
                    let new = self.documents[&id]
                        .text
                        .replace(&self.query, &self.replacement);
                    self.documents.get_mut(&id).unwrap().replace_text(new);
                    self.find_offset = 0;
                }
            }
            Message::Dismiss => {
                self.notice = None;
                return Task::none();
            }
            Message::Link(uri) => {
                self.notice = Some(format!("Link: {uri}"));
                return Task::none();
            }
            Message::Checkpoint(generation) => {
                if generation == self.generation {
                    return self.persist();
                }
                return Task::none();
            }
            Message::Persisted(result) => {
                self.persisting = false;
                if let Err(e) = result {
                    self.notice = Some(format!("Session recovery could not be saved: {e}"));
                    self.exit_after_persist = false;
                    self.quitting = false;
                }
                if self.persist_again {
                    self.persist_again = false;
                    return self.persist();
                }
                if self.exit_after_persist {
                    return iced::exit();
                }
                return Task::none();
            }
        }
        self.checkpoint()
    }
    fn save(&mut self, id: DocumentId, as_new: bool) -> Task<Message> {
        if self.saving.is_some() {
            return Task::none();
        }
        let doc = &self.documents[&id];
        let path = if as_new { None } else { doc.path.clone() };
        let occupied: Vec<_> = self
            .documents
            .values()
            .filter(|other| other.id != id)
            .filter_map(|other| other.path.clone())
            .collect();
        let original = doc.path.clone();
        let expected = doc.saved.clone();
        let text = doc.text.clone();
        let name = doc.name();
        self.saving = Some(id);
        Task::perform(
            async move {
                let result = async {
                    let path = if let Some(path) = path {
                        path
                    } else {
                        let Some(file) = rfd::AsyncFileDialog::new()
                            .set_title("Save text file")
                            .set_file_name(&name)
                            .save_file()
                            .await
                        else {
                            return Ok(None);
                        };
                        file.path().to_owned()
                    };
                    let path = path.canonicalize().unwrap_or(path);
                    if occupied.contains(&path) {
                        return Err(
                            "This file is already open in another tab. Save to a different file."
                                .into(),
                        );
                    }
                    let content = text.clone();
                    let output = path.clone();
                    tokio::task::spawn_blocking(move || {
                        document::write(
                            &output,
                            &content,
                            if original.as_ref() == Some(&output) {
                                Some(&expected)
                            } else {
                                None
                            },
                        )
                    })
                    .await
                    .map_err(|e| e.to_string())??;
                    Ok(Some(path))
                }
                .await;
                (id, text, result)
            },
            |(id, text, result)| Message::Saved(id, text, result),
        )
    }
    fn find_next(&mut self) {
        if self.query.is_empty() {
            return;
        }
        let id = self.active();
        let doc = &self.documents[&id];
        let start = self.find_offset.min(doc.text.len());
        let start = if doc.text.is_char_boundary(start) {
            start
        } else {
            0
        };
        let found = doc.text[start..]
            .find(&self.query)
            .map(|n| n + start)
            .or_else(|| doc.text.find(&self.query));
        if let Some(start) = found {
            let end = start + self.query.len();
            self.documents
                .get_mut(&id)
                .unwrap()
                .select_bytes(start, end);
            self.find_offset = end;
        } else {
            self.notice = Some("No matches found.".into());
        }
    }
    pub fn view(&self) -> Element<'_, Message> {
        let active = self.active();
        let mut tabs = row![].spacing(1);
        for id in &self.tabs {
            let doc = &self.documents[id];
            let label = format!("{}{}", doc.name(), if doc.dirty() { " •" } else { "" });
            let tab = row![
                container(text(label).size(12)).padding([7, 12]),
                control("×", "Close tab · Cmd/Ctrl+W", Message::Close(*id))
            ]
            .spacing(0);
            tabs = tabs.push(
                mouse_area(
                    container(tab)
                        .style(move |theme: &Theme| crate::style::tab(theme, *id == active)),
                )
                .on_press(Message::DragTab(*id))
                .on_enter(Message::HoverTab(*id)),
            );
        }
        let bar = container(
            row![
                pick_list(
                    [
                        FileAction::Open,
                        FileAction::Save,
                        FileAction::SaveAs,
                        FileAction::Find
                    ],
                    None::<FileAction>,
                    Message::FileAction
                )
                .placeholder("File")
                .text_size(12)
                .padding([6, 8])
                .style(crate::style::menu),
                scrollable(tabs)
                    .direction(scrollable::Direction::Horizontal(
                        scrollable::Scrollbar::default()
                    ))
                    .width(Fill),
                control("+", "New tab · Cmd/Ctrl+T", Message::New),
                control(
                    "◫",
                    "Split right · Cmd/Ctrl+D",
                    Message::Split(pane_grid::Axis::Vertical)
                ),
                control(
                    "⊟",
                    "Split down · Cmd/Ctrl+Shift+D",
                    Message::Split(pane_grid::Axis::Horizontal)
                ),
                control("Preview", "Toggle Markdown preview", Message::Preview),
                control("⋯", "Settings · Cmd/Ctrl+,", Message::Settings)
            ]
            .spacing(4)
            .align_y(iced::Center),
        )
        .padding([5, 8])
        .style(crate::style::chrome);
        let mut body = column![bar, separator()];
        if self.settings_open {
            body = body.push(self.settings_view()).push(separator());
        }
        if self.find_open {
            body = body.push(
                row![
                    text_input("Find", &self.query)
                        .id("find")
                        .on_input(Message::Query)
                        .on_submit(Message::FindNext),
                    text_input("Replace with", &self.replacement)
                        .on_input(Message::Replacement)
                        .on_submit(Message::Replace),
                    button("Next").on_press(Message::FindNext),
                    button("Replace").on_press(Message::Replace),
                    button("All").on_press(Message::ReplaceAll),
                    button("×").on_press(Message::Find)
                ]
                .spacing(6)
                .padding(8),
            );
        }
        let grid = pane_grid::PaneGrid::new(&self.panes.state, |pane, state, _| {
            let doc = &self.documents[&state.document];
            let content = crate::editor::view(
                doc,
                pane,
                &self.settings,
                state.preview,
                self.theme()
                    .map(|t| t.palette().background.r < 0.5)
                    .unwrap_or(self.system_dark),
            );
            let mut result = pane_grid::Content::new(content);
            if self.panes.state.len() > 1 {
                result = result.title_bar(
                    pane_grid::TitleBar::new(
                        row![
                            text(if pane == self.panes.active {
                                "●"
                            } else {
                                "○"
                            })
                            .size(8),
                            text(format!(
                                "{}{}",
                                doc.name(),
                                if doc.dirty() { " •" } else { "" }
                            ))
                            .size(11)
                        ]
                        .spacing(8)
                        .align_y(iced::Center),
                    )
                    .padding([3, 12])
                    .style(move |theme| crate::style::pane_header(theme, pane == self.panes.active))
                    .controls(Element::from(control(
                        "×",
                        "Close pane · Cmd/Ctrl+Shift+W",
                        Message::ClosePane(pane),
                    ))),
                );
            }
            result
        })
        .on_click(Message::Focus)
        .on_resize(5, Message::Resize)
        .on_drag(Message::DragPane)
        .style(crate::style::panes)
        .spacing(1);
        body = body.push(
            container(grid)
                .width(Fill)
                .height(Fill)
                .style(|theme: &Theme| container::Style {
                    background: Some(crate::style::line(theme).into()),
                    ..Default::default()
                }),
        );
        if self.settings.status {
            let doc = &self.documents[&active];
            let cursor = doc.content.cursor().position;
            let column = doc
                .content
                .line(cursor.line)
                .map(|line| {
                    line.text
                        .get(..cursor.column)
                        .unwrap_or(&line.text)
                        .chars()
                        .count()
                })
                .unwrap_or(0);
            body = body.push(separator()).push(
                container(
                    row![
                        text(if doc.is_markdown() {
                            "Markdown"
                        } else {
                            "Plain text"
                        }),
                        space::horizontal(),
                        text(format!(
                            "{} words   {} characters",
                            doc.words, doc.characters
                        )),
                        text(format!("Ln {}, Col {}", cursor.line + 1, column + 1))
                    ]
                    .spacing(22)
                    .align_y(iced::Center),
                )
                .padding([6, 16])
                .style(|theme: &Theme| container::Style {
                    text_color: Some(crate::style::muted(theme)),
                    ..crate::style::chrome(theme)
                }),
            );
        }
        if let Some(notice) = &self.notice {
            body = body.push(
                row![
                    text(notice).size(13).width(Fill),
                    button("Dismiss").on_press(Message::Dismiss)
                ]
                .padding(8)
                .spacing(8),
            );
        }
        if let Some(id) = self.confirm {
            let prompt = container(
                column![
                    text(format!("Save changes to {}?", self.documents[&id].name())).size(18),
                    text("Your unsaved changes will be lost if you discard them.").size(13),
                    row![
                        button("Cancel").on_press(Message::Cancel),
                        button("Discard").on_press(Message::Discard),
                        button("Save").on_press(Message::SaveClose)
                    ]
                    .spacing(10)
                ]
                .spacing(16),
            )
            .padding(24)
            .style(container::bordered_box);
            return widget::stack![
                body,
                container(prompt).center(Fill).style(|_| container::Style {
                    background: Some(iced::Color::from_rgba(0.0, 0.0, 0.0, 0.4).into()),
                    ..Default::default()
                })
            ]
            .into();
        }
        body.into()
    }
    fn settings_view(&self) -> Element<'_, Message> {
        column![
            row![
                text("Settings").size(16),
                space::horizontal(),
                button("Done").on_press(Message::Settings)
            ]
            .align_y(iced::Center),
            row![
                text("Theme"),
                pick_list(
                    [Appearance::System, Appearance::Light, Appearance::Dark],
                    Some(self.settings.appearance),
                    Message::Appearance
                ),
                text("Font"),
                pick_list(
                    [Typeface::Monospace, Typeface::Sans, Typeface::Serif],
                    Some(self.settings.font),
                    Message::Font
                )
            ]
            .spacing(12)
            .align_y(iced::Center),
            row![
                text(format!("Size  {:.0}", self.settings.size)).width(110),
                slider(10.0..=40.0, self.settings.size, Message::Size)
                    .step(1.0_f32)
                    .width(180)
            ]
            .spacing(12)
            .align_y(iced::Center),
            row![
                text(format!("Line height  {:.1}", self.settings.line_height)),
                slider(1.0..=2.4, self.settings.line_height, Message::LineHeight)
                    .step(0.1_f32)
                    .width(180)
            ]
            .spacing(12)
            .align_y(iced::Center),
            row![
                checkbox(self.settings.wrap)
                    .label("Word wrap")
                    .on_toggle(Message::Wrap),
                checkbox(self.settings.status)
                    .label("Status bar")
                    .on_toggle(Message::Status)
            ]
            .spacing(24),
            text("writestuff. just a place to write stuff.").size(11)
        ]
        .spacing(12)
        .padding(16)
        .into()
    }
}
fn separator<'a>() -> Element<'a, Message> {
    widget::rule::horizontal(1)
        .style(|theme: &Theme| widget::rule::Style {
            color: crate::style::line(theme),
            radius: 0.0.into(),
            fill_mode: widget::rule::FillMode::Full,
            snap: true,
        })
        .into()
}

fn control<'a>(label: &'a str, hint: &'a str, message: Message) -> Element<'a, Message> {
    widget::tooltip(
        button(text(label).size(13))
            .padding([5, 8])
            .style(crate::style::control)
            .on_press(message),
        text(hint).size(12),
        widget::tooltip::Position::Bottom,
    )
    .into()
}

#[cfg(test)]
mod tests {
    use super::*;
    fn app() -> App {
        App::from_session(Session::default(), None)
    }
    #[test]
    fn same_document_edits_are_shared_between_panes() {
        let mut app = app();
        let id = app.active();
        app.panes.split(pane_grid::Axis::Vertical, id);
        let _ = app.update(Message::Edit(
            app.panes.active,
            id,
            widget::text_editor::Action::Edit(widget::text_editor::Edit::Insert('é')),
        ));
        assert_eq!(app.documents.len(), 1);
        assert!(
            app.panes
                .state
                .iter()
                .all(|(_, pane)| app.documents[&pane.document].text == "é")
        );
        let _ = app.update(Message::Undo(false));
        assert_eq!(app.documents[&id].text, "");
    }
    #[test]
    fn close_requires_explicit_discard_and_redirects_all_panes() {
        let mut app = app();
        let id = app.active();
        app.documents
            .get_mut(&id)
            .unwrap()
            .replace_text("keep me".into());
        app.panes.split(pane_grid::Axis::Vertical, id);
        let _ = app.update(Message::Close(id));
        assert!(app.documents.contains_key(&id));
        assert_eq!(app.confirm, Some(id));
        let _ = app.update(Message::New);
        assert_eq!(app.documents.len(), 1);
        let _ = app.update(Message::Cancel);
        assert!(app.documents.contains_key(&id));
        let _ = app.update(Message::Close(id));
        let _ = app.update(Message::Discard);
        assert!(!app.documents.contains_key(&id));
        assert!(
            app.panes
                .state
                .iter()
                .all(|(_, p)| app.documents.contains_key(&p.document))
        );
    }
    #[test]
    fn session_roundtrip_preserves_unsaved_content_baseline_order_and_selection() {
        let mut app = app();
        let first = app.active();
        app.documents
            .get_mut(&first)
            .unwrap()
            .replace_text("unsaved 世界\n".into());
        app.new_document();
        let second = app.active();
        app.documents
            .get_mut(&second)
            .unwrap()
            .replace_text("second".into());
        let session = Session {
            settings: app.settings.clone(),
            documents: app
                .tabs
                .iter()
                .map(|id| app.documents[id].snapshot())
                .collect(),
            active: Some(first),
        };
        let bytes = serde_json::to_vec(&session).unwrap();
        let restored = App::from_session(serde_json::from_slice(&bytes).unwrap(), None);
        assert_eq!(restored.active(), first);
        assert_eq!(restored.tabs, vec![first, second]);
        assert_eq!(restored.documents[&first].text, "unsaved 世界\n");
        assert!(restored.documents[&first].dirty());
        assert_eq!(restored.documents[&second].text, "second");
    }
    #[test]
    fn background_save_does_not_clear_newer_changes() {
        let mut app = app();
        let id = app.active();
        app.documents
            .get_mut(&id)
            .unwrap()
            .replace_text("newer".into());
        let _ = app.update(Message::Saved(
            id,
            "older".into(),
            Ok(Some(PathBuf::from("test.txt"))),
        ));
        assert!(app.documents[&id].dirty());
        assert_eq!(app.documents[&id].text, "newer");
    }
    #[test]
    fn unicode_find_and_replace_selects_the_right_text() {
        let mut app = app();
        let id = app.active();
        app.documents
            .get_mut(&id)
            .unwrap()
            .replace_text("é猫\nhello 猫".into());
        app.query = "猫".into();
        app.find_next();
        assert_eq!(
            app.documents[&id].content.selection().as_deref(),
            Some("猫")
        );
        app.replacement = "world".into();
        let _ = app.update(Message::Replace);
        assert_eq!(app.documents[&id].text, "éworld\nhello 猫");
    }
    #[test]
    fn saving_during_quit_retains_the_document_for_recovery() {
        let mut app = app();
        let id = app.active();
        app.documents
            .get_mut(&id)
            .unwrap()
            .replace_text("keep tab".into());
        let _ = app.update(Message::Quit);
        assert_eq!(app.confirm, Some(id));
        let _ = app.update(Message::Saved(
            id,
            "keep tab".into(),
            Ok(Some(PathBuf::from("saved.md"))),
        ));
        assert!(app.documents.contains_key(&id));
        assert!(app.tabs.contains(&id));
        assert!(!app.documents[&id].dirty());
        assert!(app.exit_after_persist);
        let _ = app.update(Message::New);
        assert_eq!(app.documents.len(), 1);
    }
    #[test]
    fn splitting_creates_an_independent_document_without_changing_the_original() {
        let mut app = app();
        let original = app.active();
        let original_pane = app.panes.active;
        app.documents
            .get_mut(&original)
            .unwrap()
            .replace_text("original".into());
        let _ = app.update(Message::Split(pane_grid::Axis::Vertical));
        let new = app.active();
        assert_ne!(new, original);
        assert_eq!(
            app.panes.state.get(original_pane).unwrap().document,
            original
        );
        assert_eq!(app.documents[&new].text, "");
        let _ = app.update(Message::Edit(
            app.panes.active,
            new,
            widget::text_editor::Action::Edit(widget::text_editor::Edit::Insert('x')),
        ));
        assert_eq!(app.documents[&original].text, "original");
        assert_eq!(app.documents[&new].text, "x");
        let _ = app.update(Message::CloseActivePane);
        assert_eq!(app.panes.state.len(), 1);
        assert!(app.documents.contains_key(&new));
        assert_eq!(app.active(), original);
    }
    #[test]
    fn split_and_close_shortcuts_use_platform_command_modifier() {
        let key = |s: &str| Key::Character(s.into());
        assert!(matches!(
            shortcut(&key("d"), Modifiers::COMMAND),
            Some(Message::Split(pane_grid::Axis::Vertical))
        ));
        assert!(matches!(
            shortcut(&key("D"), Modifiers::COMMAND | Modifiers::SHIFT),
            Some(Message::Split(pane_grid::Axis::Horizontal))
        ));
        assert!(matches!(
            shortcut(&key("w"), Modifiers::COMMAND),
            Some(Message::Close(0))
        ));
        assert!(matches!(
            shortcut(&key("w"), Modifiers::COMMAND | Modifiers::SHIFT),
            Some(Message::CloseActivePane)
        ));
        assert!(shortcut(&key("d"), Modifiers::empty()).is_none());
        let mut app = app();
        let original = app.active();
        app.documents
            .get_mut(&original)
            .unwrap()
            .replace_text("unsaved".into());
        let _ = app.update(shortcut(&key("w"), Modifiers::COMMAND).unwrap());
        assert_eq!(app.confirm, Some(original));
        assert_eq!(app.documents[&original].text, "unsaved");
    }
    #[test]
    fn closing_a_split_tab_does_not_mirror_the_neighbor() {
        let mut app = app();
        let original = app.active();
        let _ = app.update(Message::Split(pane_grid::Axis::Vertical));
        let second = app.active();
        let _ = app.update(Message::Close(second));
        assert_eq!(app.panes.state.len(), 1);
        assert_eq!(app.active(), original);
        assert!(!app.documents.contains_key(&second));
    }
}
