use faro_core::{Field, metadata};
use gpui::{
    App, Application, Bounds, Context, Window, WindowBounds, WindowOptions, div, prelude::*, px,
    rgb, size,
};

struct FaroWelcome;

impl Render for FaroWelcome {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        let text = |field| metadata(field).to_str().expect("core metadata is UTF-8");
        div()
            .size_full()
            .flex()
            .flex_col()
            .items_center()
            .justify_center()
            .gap_4()
            .p_8()
            .bg(rgb(0x151a24))
            .text_color(rgb(0xf1f5fb))
            .child(div().text_3xl().child(text(Field::Name)))
            .child(div().text_xl().child(text(Field::Tagline)))
            .child(div().text_color(rgb(0xa6b4ca)).child(text(Field::Status)))
            .child(format!("Version {}", text(Field::Version)))
    }
}

fn main() {
    Application::new().run(|cx: &mut App| {
        cx.on_window_closed(|cx| {
            if cx.windows().is_empty() {
                cx.quit();
            }
        })
        .detach();
        let bounds = Bounds::centered(None, size(px(720.), px(480.)), cx);
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                ..Default::default()
            },
            |window, cx| {
                window.set_window_title("Faro");
                cx.new(|_| FaroWelcome)
            },
        )
        .expect("open Faro window");
        cx.activate(true);
    });
}
