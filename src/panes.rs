use crate::document::DocumentId;
use iced::widget::pane_grid;

pub struct Pane {
    pub document: DocumentId,
    pub preview: bool,
}
pub struct Panes {
    pub state: pane_grid::State<Pane>,
    pub active: pane_grid::Pane,
}
impl Panes {
    pub fn new(document: DocumentId) -> Self {
        let (state, active) = pane_grid::State::new(Pane {
            document,
            preview: false,
        });
        Self { state, active }
    }
    pub fn document(&self) -> DocumentId {
        self.state.get(self.active).unwrap().document
    }
    pub fn select(&mut self, document: DocumentId) {
        self.state.get_mut(self.active).unwrap().document = document;
    }
    pub fn split(&mut self, axis: pane_grid::Axis, document: DocumentId) {
        if self.state.len() >= 8 {
            return;
        }
        if let Some((pane, _)) = self.state.split(
            axis,
            self.active,
            Pane {
                document,
                preview: false,
            },
        ) {
            self.active = pane;
        }
    }
    pub fn close(&mut self, pane: pane_grid::Pane) {
        if let Some((_, sibling)) = self.state.close(pane) {
            self.active = sibling;
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn splits_keep_the_original_document_and_select_the_new_one() {
        let mut p = Panes::new(7);
        p.split(pane_grid::Axis::Vertical, 8);
        assert_eq!(p.state.len(), 2);
        assert_eq!(p.document(), 8);
        assert!(p.state.iter().any(|(_, v)| v.document == 7));
        p.select(8);
        assert_eq!(p.document(), 8);
    }
}
