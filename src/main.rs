mod app;
mod document;
mod editor;
mod markdown;
mod panes;
mod settings;
mod style;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let _session_lock = settings::lock()?;
    iced::application(app::App::new, app::App::update, app::App::view)
        .title(app::App::title)
        .settings(iced::Settings {
            default_text_size: 13.into(),
            ..Default::default()
        })
        .theme(app::App::theme)
        .subscription(app::App::subscription)
        .window(iced::window::Settings {
            size: iced::Size::new(1050.0, 740.0),
            min_size: Some(iced::Size::new(560.0, 360.0)),
            exit_on_close_request: false,
            ..Default::default()
        })
        .run()?;
    Ok(())
}
