//! The login screen's state: the fields, the keys, the confirm before a
//! restart or a shut down, what the screen says after a try. No terminal
//! and no greetd here: main.rs runs what an action asks for and hands
//! the outcome back, so all of it is tested without either.

use crate::greetd::{Outcome, Secret};
use crate::scrub::{cut, scrub};

/// The longest user name the field takes, in characters.
pub const USER_MOST: usize = 64;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Field {
    User,
    Password,
    Session,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Session {
    Desktop,
    Shell,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Power {
    Restart,
    Shutdown,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum View {
    Form,
    Confirm(Power),
}

/// A key, as the login screen reads it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Key {
    Tab,
    BackTab,
    Up,
    Down,
    Left,
    Right,
    Enter,
    Esc,
    Backspace,
    /// Ctrl+U: the field emptied.
    Kill,
    F(u8),
    Char(char),
}

/// What main.rs is asked to do.
#[derive(Debug, PartialEq)]
pub enum Action {
    /// Log in: the password is handed over with take_password.
    LogIn,
    Power(Power),
}

/// One line under the form: a refusal in the alarm color with its cross, or a plain one muted.
#[derive(Clone, Debug, PartialEq)]
pub enum Note {
    Wrong(String),
    Plain(String),
}

pub struct Login {
    pub host: String,
    pub distro: String,
    pub field: Field,
    pub user: String,
    pub password: Secret,
    pub session: Session,
    pub view: View,
    pub confirm: String,
    pub note: Option<Note>,
    /// A login on its way: the dots it had, while the keys wait.
    pub busy: Option<usize>,
    /// spark's state: None when no port was given, else ready or not.
    pub spark: Option<bool>,
    /// The session row: off when this machine has no desktop.
    pub desktop: bool,
    pub can_restart: bool,
    pub can_shutdown: bool,
}

pub const WRONG: &str = "Wrong user name or password.";
pub const MORE: &str = "This account asks for more than a password.";

impl Login {
    pub fn new(host: &str, distro: &str) -> Login {
        Login {
            host: host.into(),
            distro: distro.into(),
            field: Field::User,
            user: String::new(),
            password: Secret::new(),
            session: Session::Desktop,
            view: View::Form,
            confirm: String::new(),
            note: None,
            busy: None,
            spark: None,
            desktop: true,
            can_restart: false,
            can_shutdown: false,
        }
    }

    fn fields(&self) -> &'static [Field] {
        if self.desktop {
            &[Field::User, Field::Password, Field::Session]
        } else {
            &[Field::User, Field::Password]
        }
    }

    fn step(&mut self, by: isize) {
        let f = self.fields();
        let i = f.iter().position(|x| *x == self.field).unwrap_or(0) as isize;
        let n = f.len() as isize;
        self.field = f[((i + by) % n + n) as usize % n as usize];
    }

    /// The session greetd starts: always the shell when there is no desktop.
    pub fn session(&self) -> Session {
        if self.desktop {
            self.session
        } else {
            Session::Shell
        }
    }

    fn power_ok(&self, p: Power) -> bool {
        match p {
            Power::Restart => self.can_restart,
            Power::Shutdown => self.can_shutdown,
        }
    }

    pub fn key(&mut self, k: Key) -> Option<Action> {
        if self.busy.is_some() {
            return None;
        }
        let power = match k {
            Key::F(11) => Some(Power::Restart),
            Key::F(12) => Some(Power::Shutdown),
            _ => None,
        };
        if let Some(p) = power {
            if self.power_ok(p) {
                self.view = View::Confirm(p);
                self.confirm.clear();
                self.note = None;
            }
            return None;
        }
        match self.view {
            View::Confirm(p) => self.confirm_key(p, k),
            View::Form => self.form_key(k),
        }
    }

    fn confirm_key(&mut self, p: Power, k: Key) -> Option<Action> {
        match k {
            Key::Esc => {
                self.view = View::Form;
                self.confirm.clear();
                self.note = None;
            }
            Key::Enter => {
                if self.confirm == "yes" {
                    self.note = Some(Note::Plain(
                        match p {
                            Power::Restart => "Restarting.",
                            Power::Shutdown => "Shutting down.",
                        }
                        .into(),
                    ));
                    return Some(Action::Power(p));
                }
                self.note = Some(Note::Plain("Type yes, or Esc to go back.".into()));
            }
            Key::Backspace => {
                self.confirm.pop();
            }
            Key::Kill => self.confirm.clear(),
            Key::Char(c) if !c.is_control() && self.confirm.chars().count() < 8 => self.confirm.push(c),
            _ => {}
        }
        None
    }

    fn form_key(&mut self, k: Key) -> Option<Action> {
        match k {
            Key::Tab | Key::Down => self.step(1),
            Key::BackTab | Key::Up => self.step(-1),
            Key::Esc => self.note = None,
            Key::Left | Key::Right | Key::Char(' ') if self.field == Field::Session => {
                self.session = match self.session {
                    Session::Desktop => Session::Shell,
                    Session::Shell => Session::Desktop,
                }
            }
            Key::Enter => {
                if self.field == Field::User {
                    self.field = Field::Password;
                } else if self.user.is_empty() {
                    self.field = Field::User;
                } else {
                    self.busy = Some(self.password.len());
                    self.note = Some(Note::Plain("Checking.".into()));
                    return Some(Action::LogIn);
                }
            }
            Key::Backspace => match self.field {
                Field::User => {
                    self.user.pop();
                }
                Field::Password => self.password.pop(),
                Field::Session => {}
            },
            Key::Kill => match self.field {
                Field::User => self.user.clear(),
                Field::Password => self.password.clear(),
                Field::Session => {}
            },
            Key::Char(c) if !c.is_control() => match self.field {
                Field::User if !c.is_whitespace() && self.user.chars().count() < USER_MOST => self.user.push(c),
                Field::Password => {
                    self.password.push(c);
                }
                _ => {}
            },
            _ => {}
        }
        None
    }

    /// The password, moved out for the login (the field keeps its dots while it runs).
    pub fn take_password(&mut self) -> Secret {
        std::mem::take(&mut self.password)
    }

    /// The login's outcome: Started ends the screen (true), anything else is said under the form.
    pub fn outcome(&mut self, o: Outcome) -> bool {
        self.busy = None;
        self.password.clear();
        self.field = Field::Password;
        self.note = match o {
            Outcome::Started => return true,
            Outcome::Wrong => Some(Note::Wrong(WRONG.into())),
            Outcome::More => Some(Note::Wrong(MORE.into())),
            Outcome::Failed(why) => Some(Note::Wrong(one_line(&why))),
        };
        false
    }

    /// A restart or a shut down that did not run.
    pub fn power_failed(&mut self, p: Power, why: &str) {
        let what = match p {
            Power::Restart => "The restart",
            Power::Shutdown => "The shut down",
        };
        self.note = Some(Note::Wrong(one_line(&format!("{} did not run: {}", what, why))));
    }
}

/// The text as one line the strip can hold.
pub fn one_line(s: &str) -> String {
    let t: String = scrub(s).split_whitespace().collect::<Vec<_>>().join(" ");
    cut(&t, 50)
}

/// The distro line: os-release's PRETTY_NAME (NAME, then Linux), and for
/// a distro with no version of its own (VERSION_ID absent: a rolling
/// one), the kernel's release cut at its first _ or -.
pub fn distro(os_release: &str, kernel: &str) -> String {
    let get = |k: &str| {
        os_release.lines().find_map(|l| {
            let v = l.strip_prefix(k)?.strip_prefix('=')?;
            let v = v.trim().trim_matches('"').trim_matches('\'').trim();
            (!v.is_empty()).then(|| scrub(v))
        })
    };
    let name = get("PRETTY_NAME").or_else(|| get("NAME")).unwrap_or_else(|| "Linux".into());
    if get("VERSION_ID").is_some() {
        return name;
    }
    let k = kernel.split(['_', '-']).next().unwrap_or("").trim();
    if k.is_empty() {
        name
    } else {
        format!("{} \u{b7} kernel {}", name, scrub(k))
    }
}

/// The machine's short name: up to its first dot.
pub fn short_host(h: &str) -> String {
    let s = scrub(h.split('.').next().unwrap_or("").trim());
    if s.is_empty() {
        "this machine".into()
    } else {
        cut(&s, 40)
    }
}

/// The argv a --restart or --shutdown names: words split on spaces, an absolute path first.
pub fn power_argv(words: &str) -> Result<Vec<String>, String> {
    let argv: Vec<String> = words.split_whitespace().map(String::from).collect();
    match argv.first() {
        None => Err("a power command needs a program".into()),
        Some(p) if !p.starts_with('/') => Err(format!("{}: a power command is an absolute path", p)),
        Some(p) if p.chars().any(|c| c.is_control()) => Err("a power command holds a control character".into()),
        _ => Ok(argv),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn typed(l: &mut Login, s: &str) {
        for c in s.chars() {
            l.key(Key::Char(c));
        }
    }

    #[test]
    fn tab_walks_the_fields_and_wraps() {
        let mut l = Login::new("void", "Void Linux");
        assert_eq!(l.field, Field::User);
        l.key(Key::Tab);
        assert_eq!(l.field, Field::Password);
        l.key(Key::Down);
        assert_eq!(l.field, Field::Session);
        l.key(Key::Tab);
        assert_eq!(l.field, Field::User);
        l.key(Key::BackTab);
        assert_eq!(l.field, Field::Session);
    }

    #[test]
    fn with_no_desktop_tab_skips_the_session_and_it_is_the_shell() {
        let mut l = Login::new("void", "Void Linux");
        l.desktop = false;
        l.key(Key::Tab);
        l.key(Key::Tab);
        assert_eq!(l.field, Field::User);
        assert_eq!(l.session(), Session::Shell);
    }

    #[test]
    fn the_session_toggles_on_its_row_only() {
        let mut l = Login::new("void", "Void Linux");
        l.key(Key::Right);
        assert_eq!(l.session, Session::Desktop);
        l.field = Field::Session;
        l.key(Key::Right);
        assert_eq!(l.session, Session::Shell);
        l.key(Key::Char(' '));
        assert_eq!(l.session, Session::Desktop);
    }

    #[test]
    fn enter_on_the_user_goes_to_the_password_then_logs_in() {
        let mut l = Login::new("void", "Void Linux");
        typed(&mut l, "w ");
        assert_eq!(l.user, "w", "a user name takes no space");
        assert_eq!(l.key(Key::Enter), None);
        assert_eq!(l.field, Field::Password);
        typed(&mut l, "pa ss");
        assert_eq!(l.password.len(), 5);
        assert_eq!(l.key(Key::Enter), Some(Action::LogIn));
        assert_eq!(l.busy, Some(5));
        assert_eq!(l.key(Key::Char('x')), None, "the keys wait while the login runs");
        let p = l.take_password();
        assert_eq!(p.expose(), b"pa ss");
        assert!(l.password.is_empty());
    }

    #[test]
    fn enter_with_no_user_goes_back_to_it() {
        let mut l = Login::new("void", "Void Linux");
        l.field = Field::Password;
        assert_eq!(l.key(Key::Enter), None);
        assert_eq!(l.field, Field::User);
    }

    #[test]
    fn a_wrong_password_is_said_and_cleared() {
        let mut l = Login::new("void", "Void Linux");
        typed(&mut l, "w");
        l.key(Key::Enter);
        typed(&mut l, "nope");
        l.key(Key::Enter);
        let _p = l.take_password();
        l.field = Field::Session;
        assert!(!l.outcome(Outcome::Wrong));
        assert_eq!(l.note, Some(Note::Wrong(WRONG.into())));
        assert!(l.password.is_empty());
        assert_eq!(l.field, Field::Password);
        assert_eq!(l.busy, None);
        assert!(l.outcome(Outcome::Started));
    }

    #[test]
    fn a_power_key_asks_for_yes_and_esc_goes_back() {
        let mut l = Login::new("void", "Void Linux");
        l.key(Key::F(12));
        assert_eq!(l.view, View::Form, "no shut down command: the key does nothing");
        l.can_shutdown = true;
        l.can_restart = true;
        l.key(Key::F(12));
        assert_eq!(l.view, View::Confirm(Power::Shutdown));
        typed(&mut l, "ye");
        assert_eq!(l.key(Key::Enter), None);
        assert!(matches!(l.note, Some(Note::Plain(_))));
        typed(&mut l, "s");
        assert_eq!(l.key(Key::Enter), Some(Action::Power(Power::Shutdown)));
        l.key(Key::F(11));
        assert_eq!(l.view, View::Confirm(Power::Restart));
        assert_eq!(l.confirm, "");
        l.key(Key::Esc);
        assert_eq!(l.view, View::Form);
    }

    #[test]
    fn the_distro_line() {
        let void = "NAME=\"Void\"\nID=\"void\"\nPRETTY_NAME=\"Void Linux\"\n";
        assert_eq!(distro(void, "6.18.54_1"), "Void Linux \u{b7} kernel 6.18.54");
        let arch = "NAME=\"Arch Linux\"\nPRETTY_NAME=\"Arch Linux\"\nBUILD_ID=rolling\n";
        assert_eq!(distro(arch, "6.17.1-arch1-1"), "Arch Linux \u{b7} kernel 6.17.1");
        let debian = "PRETTY_NAME=\"Debian GNU/Linux 13 (trixie)\"\nNAME=\"Debian GNU/Linux\"\nVERSION_ID=\"13\"\n";
        assert_eq!(distro(debian, "6.12.43+deb13-amd64"), "Debian GNU/Linux 13 (trixie)");
        assert_eq!(distro("NAME=Plain\n", ""), "Plain");
        assert_eq!(distro("", "6.1"), "Linux \u{b7} kernel 6.1");
        assert_eq!(distro("PRETTY_NAME=\"Evil\u{1b}[2J\"\nVERSION_ID=1\n", ""), "Evil[2J");
    }

    #[test]
    fn the_short_host_and_the_power_argv() {
        assert_eq!(short_host("void.lan"), "void");
        assert_eq!(short_host(""), "this machine");
        assert_eq!(power_argv("/usr/bin/sudo -n /usr/bin/reboot").unwrap().len(), 3);
        assert!(power_argv("reboot").is_err());
        assert!(power_argv("  ").is_err());
    }
}
