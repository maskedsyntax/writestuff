use crate::{
    app::{Message, shortcut},
    document::Document,
    settings::{Settings, Typeface},
};
use iced::{
    Element, Font, Length,
    widget::{container, scrollable, text, text_editor},
};

pub fn id(pane: iced::widget::pane_grid::Pane) -> String {
    format!("editor-{pane:?}")
}

pub fn view<'a>(
    doc: &'a Document,
    pane: iced::widget::pane_grid::Pane,
    settings: &'a Settings,
    preview: bool,
    dark: bool,
) -> Element<'a, Message> {
    if preview {
        if !doc.is_markdown() {
            return container(text("Save this document as .md to preview Markdown.").size(14))
                .padding(24)
                .into();
        }
        return scrollable(
            container(
                iced::widget::markdown::view(
                    &doc.preview,
                    iced::widget::markdown::Settings::with_text_size(
                        settings.size,
                        if dark {
                            &iced::Theme::Dark
                        } else {
                            &iced::Theme::Light
                        },
                    ),
                )
                .map(Message::Link),
            )
            .padding(24),
        )
        .height(Length::Fill)
        .into();
    }
    text_editor(&doc.content)
        .id(id(pane))
        .on_action(move |a| Message::Edit(pane, doc.id, a))
        .key_binding(move |key| {
            if matches!(key.status, text_editor::Status::Focused { .. })
                && let Some(message) = shortcut(&key.key, key.modifiers)
            {
                Some(text_editor::Binding::Custom(message))
            } else {
                text_editor::Binding::from_key_press(key)
            }
        })
        .font(match settings.font {
            Typeface::Monospace => Font::MONOSPACE,
            Typeface::Sans => Font::DEFAULT,
            Typeface::Serif => Font {
                family: iced::font::Family::Serif,
                ..Font::DEFAULT
            },
        })
        .size(settings.size)
        .line_height(iced::widget::text::LineHeight::Relative(
            settings.line_height,
        ))
        .wrapping(if settings.wrap {
            iced::widget::text::Wrapping::Word
        } else {
            iced::widget::text::Wrapping::None
        })
        .padding(iced::Padding {
            top: 26.0,
            right: 32.0,
            bottom: 26.0,
            left: 32.0,
        })
        .height(Length::Fill)
        .style(crate::style::editor)
        .highlight(
            if doc.is_markdown() { "md" } else { "txt" },
            if dark {
                iced::highlighter::Theme::Base16Ocean
            } else {
                iced::highlighter::Theme::InspiredGitHub
            },
        )
        .into()
}
