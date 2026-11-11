//! The search from Home (#169): how well the words typed name a thing. Every word must be in the
//! name: at its start, at a word's start, inside a word, or, for a word of four letters or more, one
//! letter off (a letter missing, one too many, a wrong one, or two swapped). The files provider ranks
//! its names the same way (files_match), so a file it found and a row the dialog holds read alike.

/// What a word scores where it is found: the name's start, a word's start, inside, one letter off.
pub const AT_START: u32 = 4;
pub const AT_WORD: u32 = 3;
pub const INSIDE: u32 = 2;
pub const NEAR: u32 = 1;

/// The words typed, lowercase, one a word.
pub fn words(typed: &str) -> Vec<String> {
    typed.split_whitespace().map(str::to_lowercase).collect()
}

/// How well every word names `name`: the sum of their scores, None when a word is not in it.
pub fn score(words: &[String], name: &str) -> Option<u32> {
    if words.is_empty() {
        return None;
    }
    let name = name.to_lowercase();
    let parts: Vec<&str> = name.split(|c: char| !c.is_alphanumeric()).filter(|p| !p.is_empty()).collect();
    words.iter().map(|w| one(w, &name, &parts)).sum::<Option<u32>>()
}

fn one(w: &str, name: &str, parts: &[&str]) -> Option<u32> {
    if name.starts_with(w) {
        return Some(AT_START);
    }
    if parts.iter().any(|p| p.starts_with(w)) {
        return Some(AT_WORD);
    }
    if name.contains(w) {
        return Some(INSIDE);
    }
    let w: Vec<char> = w.chars().collect();
    if w.len() < 4 {
        return None;
    }
    for p in parts {
        let c: Vec<char> = p.chars().collect();
        // a typo is rarely in the first letter, unless the first two are swapped
        let first = c[0] == w[0] || (c.len() > 1 && c[0] == w[1] && c[1] == w[0]);
        let cut = |n: usize| &c[..n.min(c.len())];
        if first && (near(&w, cut(w.len())) || near(&w, cut(w.len() + 1)) || near(&w, cut(w.len() - 1)) || near(&w, &c)) {
            return Some(NEAR);
        }
    }
    None
}

/// One edit apart at most: a letter missing, one too many, a wrong one, or two side by side swapped.
fn near(a: &[char], b: &[char]) -> bool {
    if a.len() == b.len() {
        let off: Vec<usize> = (0..a.len()).filter(|&i| a[i] != b[i]).collect();
        return match off.as_slice() {
            [] | [_] => true,
            [i, j] => *j == i + 1 && a[*i] == b[*j] && a[*j] == b[*i],
            _ => false,
        };
    }
    let (long, short) = if a.len() > b.len() { (a, b) } else { (b, a) };
    if long.len() != short.len() + 1 {
        return false;
    }
    let i = (0..short.len()).find(|&i| long[i] != short[i]).unwrap_or(short.len());
    long[i + 1..] == short[i..]
}

/// Words as a uri's last part, the way the files provider writes a path in one: base64 with - and _ for + and /, no padding.
pub fn b64(text: &str) -> String {
    const ABC: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut out = String::new();
    for chunk in text.as_bytes().chunks(3) {
        let n = chunk.iter().enumerate().fold(0u32, |n, (i, b)| n | (*b as u32) << (16 - 8 * i));
        for k in 0..=chunk.len() {
            out.push(ABC[(n >> (18 - 6 * k) & 63) as usize] as char);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn words_go_in_a_uri_as_the_provider_reads_them() {
        assert_eq!(b64("fi"), "Zmk");
        assert_eq!(b64("vet friday"), "dmV0IGZyaWRheQ");
        assert_eq!(b64("\u{fb}?>"), "w7s_Pg");
    }

    fn s(typed: &str, name: &str) -> Option<u32> {
        score(&words(typed), name)
    }

    #[test]
    fn the_start_beats_a_word_beats_inside_beats_a_typo() {
        assert_eq!(s("fire", "Firefox"), Some(AT_START));
        assert_eq!(s("notes", "field-notes.md"), Some(AT_WORD));
        assert_eq!(s("fox", "Firefox"), Some(INSIDE));
        assert_eq!(s("firfox", "Firefox"), Some(NEAR));
        assert_eq!(s("xyz", "Firefox"), None);
    }

    #[test]
    fn a_letter_missing_extra_wrong_or_swapped_still_holds() {
        for typo in ["firfox", "fireefox", "firwfox", "fierfox", "ifrefox"] {
            assert_eq!(s(typo, "firefox"), Some(NEAR), "{}", typo);
        }
        // a word typed short of the name, one letter off
        assert_eq!(s("firmwre", "firmware.bin"), Some(NEAR));
        // two letters off is no match, nor a short word one letter off
        assert_eq!(s("frifux", "firefox"), None);
        assert_eq!(s("fxr", "firefox"), None);
    }

    #[test]
    fn every_word_must_be_in_the_name_and_the_scores_add() {
        assert_eq!(s("feild notes", "field-notes.md"), Some(NEAR + AT_WORD));
        assert_eq!(s("field music", "field-notes.md"), None);
        assert_eq!(s("", "anything"), None);
    }

    #[test]
    fn letters_past_ascii_are_letters() {
        assert_eq!(s("cafe", "Caf\u{e9} du coin"), Some(NEAR));
        assert_eq!(s("coin", "Caf\u{e9} du coin"), Some(AT_WORD));
    }
}
