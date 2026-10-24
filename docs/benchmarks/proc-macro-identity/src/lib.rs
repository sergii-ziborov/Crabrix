extern crate proc_macro;

use proc_macro::TokenStream;

/// The smallest token-preserving expansion for qualifying a future guest bridge.
#[proc_macro]
pub fn keep(input: TokenStream) -> TokenStream {
    input
}
