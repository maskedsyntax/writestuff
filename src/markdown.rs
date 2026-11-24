use iced::widget::markdown;

pub fn parse(text: &str) -> Vec<markdown::Item> {
    markdown::parse(text).collect()
}
