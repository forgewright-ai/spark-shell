//! spark-shell's status: `spark-shell bar status` run as a child, the i3bar protocol as swaybar speaks
//! it. Its lines come in over a channel, read aside; the clicks go to its stdin. Every value the bar
//! shows is said there. The child is a shell loop with jobs of its own that hold its stream open, so
//! it leads a process group: the group is ended as one, and the child's end is told by its exit as
//! well as by its stream's end.

use crate::bar::{self, Click};
use calloop::channel::Sender;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::io::AsRawFd;
use std::os::unix::process::CommandExt;
use std::process::{ChildStdin, Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

/// What a status child said, with the count of the child that said it: an older child's words are dropped.
pub enum Said {
    Line(u64, String),
    /// Its stream ended or broke, or the child itself ended: one child may say both.
    End(u64),
}

/// A running status child.
pub struct Feed {
    /// The child's pid, and its process group's: it leads a group of its own.
    pid: libc::pid_t,
    stdin: Option<ChildStdin>,
    /// No click was written yet: the first one opens the array.
    first: bool,
    started: Instant,
    /// Dropped with the feed: the child is reaped only after, so the pid is the child's own for as
    /// long as the feed may signal its group.
    _unreaped: mpsc::Sender<()>,
}

impl Feed {
    /// Starts `PROGRAM bar status` with SPARK_BAR=1, in a process group of its own; its lines and its
    /// end are sent to `tx` under `gen`.
    pub fn start(program: &str, gen: u64, tx: Sender<Said>) -> std::io::Result<Feed> {
        let mut command = Command::new(program);
        command
            .args(["bar", "status"])
            .env("SPARK_BAR", "1")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .process_group(0);
        // the bar keeps the signals it reads blocked, and a child inherits that: a shell that leaves the mask as
        // it found it would never get its redraw (USR1) or its end (TERM). The child starts with none blocked
        unsafe {
            command.pre_exec(|| {
                let mut none = std::mem::MaybeUninit::<libc::sigset_t>::uninit();
                libc::sigemptyset(none.as_mut_ptr());
                match libc::sigprocmask(libc::SIG_SETMASK, none.as_ptr(), std::ptr::null_mut()) {
                    0 => Ok(()),
                    _ => Err(std::io::Error::last_os_error()),
                }
            });
        }
        let mut child = command.spawn()?;
        let pid = libc::pid_t::try_from(child.id()).unwrap_or(0);
        let stdin = child.stdin.take();
        if let Some(i) = &stdin {
            // a child that reads no clicks never holds the bar: a full pipe drops the click
            unsafe {
                let flags = libc::fcntl(i.as_raw_fd(), libc::F_GETFL);
                libc::fcntl(i.as_raw_fd(), libc::F_SETFL, flags | libc::O_NONBLOCK);
            }
        }
        if let Some(out) = child.stdout.take() {
            let tx = tx.clone();
            std::thread::spawn(move || {
                let mut out = BufReader::new(out);
                let mut line = Vec::new();
                loop {
                    line.clear();
                    match out.read_until(b'\n', &mut line) {
                        Ok(n) if n > 0 => {
                            if tx.send(Said::Line(gen, String::from_utf8_lossy(&line).into_owned())).is_err() {
                                return;
                            }
                        }
                        _ => break,
                    }
                }
                let _ = tx.send(Said::End(gen));
            });
        }
        let (unreaped, ended) = mpsc::channel::<()>();
        std::thread::spawn(move || {
            // the child's exit, seen and not yet reaped: a job it left may hold its stream open for ever
            let mut info = std::mem::MaybeUninit::<libc::siginfo_t>::uninit();
            loop {
                let got = unsafe { libc::waitid(libc::P_PID, pid as libc::id_t, info.as_mut_ptr(), libc::WEXITED | libc::WNOWAIT) };
                if got == 0 || std::io::Error::last_os_error().kind() != std::io::ErrorKind::Interrupted {
                    break;
                }
            }
            let _ = tx.send(Said::End(gen));
            // the feed ended and its group was told: the child is reaped, no zombie stays
            let _ = ended.recv();
            let _ = child.wait();
        });
        Ok(Feed {
            pid,
            stdin,
            first: true,
            started: Instant::now(),
            _unreaped: unreaped,
        })
    }

    /// How long the child has run.
    pub fn lived(&self) -> Duration {
        self.started.elapsed()
    }

    /// A click written to the child as swaybar writes it.
    pub fn click(&mut self, click: &Click) {
        let Some(i) = self.stdin.as_mut() else { return };
        if i.write_all(bar::click_line(click, self.first).as_bytes()).is_ok() {
            self.first = false;
            let _ = i.flush();
        }
    }

    /// The child's whole group told to end (SIGTERM): the loop and the jobs it started, whether the
    /// loop still runs or not. Nothing is waited for here: the child is reaped aside.
    pub fn end(self) {
        if self.pid > 1 {
            unsafe {
                libc::kill(-self.pid, libc::SIGTERM);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use calloop::channel::{channel, Channel};
    use std::os::unix::fs::PermissionsExt;

    /// A status program for a test: a shell script, run as spark-shell is.
    fn script(name: &str, body: &str) -> String {
        let path = std::env::temp_dir().join(format!("spark-bar-test-{}-{name}", std::process::id()));
        std::fs::write(&path, format!("#!/bin/sh\n{body}\n")).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o700)).unwrap();
        path.to_string_lossy().into_owned()
    }

    /// What a feed said, until `enough` of it: the lines and the count of ends, within twenty seconds.
    fn heard(rx: &Channel<Said>, gen: u64, mut lines: Vec<String>, mut ends: u32, enough: impl Fn(&[String], u32) -> bool) -> (Vec<String>, u32) {
        let until = Instant::now() + Duration::from_secs(20);
        while !enough(&lines, ends) {
            match rx.try_recv() {
                Ok(Said::Line(g, line)) if g == gen => lines.push(line.trim().to_string()),
                Ok(Said::End(g)) if g == gen => ends += 1,
                Ok(_) => {}
                Err(_) => {
                    assert!(Instant::now() < until, "after {lines:?} and {ends} ends, nothing more in time");
                    std::thread::sleep(Duration::from_millis(5));
                }
            }
        }
        (lines, ends)
    }

    /// Whether the child is gone and reaped: no zombie of it is left to wait for.
    fn reaped(pid: libc::pid_t) -> bool {
        let until = Instant::now() + Duration::from_secs(20);
        loop {
            let mut info = std::mem::MaybeUninit::<libc::siginfo_t>::uninit();
            let got = unsafe { libc::waitid(libc::P_PID, pid as libc::id_t, info.as_mut_ptr(), libc::WEXITED | libc::WNOHANG | libc::WNOWAIT) };
            if got != 0 {
                return true;
            }
            if Instant::now() >= until {
                return false;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
    }

    #[test]
    fn a_child_starts_with_no_signal_blocked() {
        // as the bar does: the signals it reads are blocked where the child is started
        let mut set = std::mem::MaybeUninit::<libc::sigset_t>::uninit();
        unsafe {
            libc::sigemptyset(set.as_mut_ptr());
            libc::sigaddset(set.as_mut_ptr(), libc::SIGUSR1);
            libc::sigaddset(set.as_mut_ptr(), libc::SIGTERM);
            libc::pthread_sigmask(libc::SIG_BLOCK, set.as_ptr(), std::ptr::null_mut());
        }
        // no shell between: one may clear the mask itself, another keeps what it is handed
        let path = std::env::temp_dir().join(format!("spark-bar-test-{}-mask", std::process::id()));
        let says_its_mask = "#!/usr/bin/awk -f\nBEGIN { while ((getline l < \"/proc/self/status\") > 0) if (l ~ /^SigBlk/) print l; exit }\n";
        std::fs::write(&path, says_its_mask).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o700)).unwrap();
        let (tx, rx) = channel::<Said>();
        let feed = Feed::start(&path.to_string_lossy(), 1, tx).unwrap();
        let (lines, _) = heard(&rx, 1, vec![], 0, |lines, ends| !lines.is_empty() && ends >= 1);
        feed.end();
        let _ = std::fs::remove_file(&path);
        let mask = lines[0].trim_start_matches("SigBlk:").trim();
        assert!(!mask.is_empty() && mask.bytes().all(|b| b == b'0'), "the child's blocked signals: {mask}");
    }

    #[test]
    fn a_child_ends_as_a_group_and_its_exit_tells_its_end() {
        let (tx, rx) = channel::<Said>();

        // the loop ends and a job of its lives on with the stream open: the exit tells the end, no EOF does
        let program = script("left", "sleep 60 &\necho \"$!\"\nexit 0");
        let feed = Feed::start(&program, 1, tx.clone()).unwrap();
        let pid = feed.pid;
        let (lines, ends) = heard(&rx, 1, vec![], 0, |lines, ends| !lines.is_empty() && ends == 1);
        let job: libc::pid_t = lines[0].parse().unwrap();
        assert_eq!(unsafe { libc::kill(job, 0) }, 0, "the job the loop left still runs");
        assert_eq!(unsafe { libc::getpgid(job) }, pid, "in the child's group");
        // the feed ended: the job is told too, so the stream ends at last, and the child is reaped
        feed.end();
        assert_eq!(heard(&rx, 1, lines, ends, |_, ends| ends == 2).1, 2);
        assert!(reaped(pid), "a zombie of the child stays");
        let _ = std::fs::remove_file(&program);

        // a loop that still runs, a job beside it: ending the feed ends both, and both ends are told
        let program = script("runs", "sleep 60 &\necho up\nwhile :; do sleep 60; done");
        let feed = Feed::start(&program, 2, tx).unwrap();
        let pid = feed.pid;
        let (lines, ends) = heard(&rx, 2, vec![], 0, |lines, _| !lines.is_empty());
        assert_eq!((lines.as_slice(), ends), (&["up".to_string()][..], 0));
        feed.end();
        assert_eq!(heard(&rx, 2, lines, ends, |_, ends| ends == 2).1, 2);
        assert!(reaped(pid), "a zombie of the child stays");
        let _ = std::fs::remove_file(&program);
    }
}
