use iced::{
    Border, Color, Theme, color,
    widget::{button, container, pane_grid, pick_list, text_editor},
};

pub fn theme(dark: bool) -> Theme {
    Theme::custom(
        "writestuff",
        iced::theme::Palette {
            background: if dark {
                color!(0x1b1c1e)
            } else {
                color!(0xfaf9f6)
            },
            text: if dark {
                color!(0xd9d9d6)
            } else {
                color!(0x303330)
            },
            primary: if dark {
                color!(0x9eafa4)
            } else {
                color!(0x536d60)
            },
            success: color!(0x63836a),
            warning: color!(0xad8650),
            danger: color!(0xb76c68),
        },
    )
}
fn dark(theme: &Theme) -> bool {
    theme.palette().background.r < 0.5
}
pub fn muted(theme: &Theme) -> Color {
    if dark(theme) {
        color!(0x999c99)
    } else {
        color!(0x737873)
    }
}
pub fn line(theme: &Theme) -> Color {
    if dark(theme) {
        color!(0x343638)
    } else {
        color!(0xe0e1db)
    }
}
pub fn chrome(theme: &Theme) -> container::Style {
    container::Style {
        background: Some(
            if dark(theme) {
                color!(0x202123)
            } else {
                color!(0xf0f0eb)
            }
            .into(),
        ),
        ..Default::default()
    }
}
pub fn tab(theme: &Theme, active: bool) -> container::Style {
    container::Style {
        background: active.then_some(theme.palette().background.into()),
        text_color: Some(if active {
            theme.palette().text
        } else {
            muted(theme)
        }),
        border: Border {
            color: if active {
                line(theme)
            } else {
                Color::TRANSPARENT
            },
            width: 1.0,
            radius: 3.0.into(),
        },
        ..Default::default()
    }
}
pub fn control(theme: &Theme, status: button::Status) -> button::Style {
    let mut style = button::text(theme, status);
    style.text_color = muted(theme);
    style.border.radius = 3.0.into();
    if matches!(status, button::Status::Hovered | button::Status::Pressed) {
        style.background = Some(line(theme).into());
        style.text_color = theme.palette().text;
    }
    style
}
pub fn menu(theme: &Theme, status: pick_list::Status) -> pick_list::Style {
    let mut style = pick_list::default(theme, status);
    style.background = Color::TRANSPARENT.into();
    style.text_color = muted(theme);
    style.placeholder_color = muted(theme);
    style.border = Border::default();
    style
}
pub fn pane_header(theme: &Theme, active: bool) -> container::Style {
    let mut style = chrome(theme);
    style.text_color = Some(if active {
        theme.palette().text
    } else {
        muted(theme)
    });
    style
}
pub fn panes(theme: &Theme) -> pane_grid::Style {
    let mut style = pane_grid::default(theme);
    style.hovered_split.color = theme.palette().primary;
    style.hovered_split.width = 2.0;
    style.picked_split = style.hovered_split;
    style
}
pub fn editor(theme: &Theme, status: text_editor::Status) -> text_editor::Style {
    let mut style = text_editor::default(theme, status);
    style.border = Border::default();
    style.background = theme.palette().background.into();
    style
}
