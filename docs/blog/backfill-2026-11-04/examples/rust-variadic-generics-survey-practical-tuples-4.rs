trait Label {
    fn label(&self) -> String;
}
impl Label for u32 {
    fn label(&self) -> String {
        self.to_string()
    }
}
impl Label for &str {
    fn label(&self) -> String {
        (*self).to_owned()
    }
}
impl Label for bool {
    fn label(&self) -> String {
        if *self { "enabled" } else { "disabled" }.to_owned()
    }
}
trait Labels {
    fn labels(&self) -> Vec<String>;
}
macro_rules! impl_labels {
    ($($T:ident : $i:tt),+) => {
        impl<$($T: Label),+> Labels for ($($T,)+) {
            fn labels(&self) -> Vec<String> {
                vec![$(self.$i.label()),+]
            }
        }
    };
}
impl_labels!(A: 0, B: 1);
impl_labels!(A: 0, B: 1, C: 2);
fn main() {
    let values = (3_u32, "network", true);
    assert_eq!(values.labels(), ["3", "network", "enabled"]);
    assert_eq!((0_u32, false).labels(), ["0", "disabled"]);
    assert_eq!(values.0, 3);
    println!("tuple labels: all checks passed");
}
