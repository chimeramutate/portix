//! Keyboard-interactive auth (OTP / 2FA / PAM prompts) without a callback
//! into Dart: a connect that meets prompts it cannot answer records them and
//! fails with [`PortixError::KeyboardInteractiveRequired`]; the UI reads them
//! with [`pending_prompts`], stores the answers with [`set_answers`] and
//! connects again. Answers are per round, in the order the server asks.

use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};

use russh::client::{self, KeyboardInteractiveAuthResponse};
use tokio::time::timeout;

use crate::domain::errors::{PortixError, Result};
use crate::domain::profile::SshProfile;

#[derive(Clone, Debug, PartialEq)]
pub struct PendingPrompts {
    /// How many rounds were answered before this one; the UI keeps that many
    /// of its answers and appends the answer to this round.
    pub round: usize,
    pub name: String,
    pub instructions: String,
    /// (prompt text, echo the typed answer)
    pub prompts: Vec<(String, bool)>,
}

type HostPort = (String, u16);

static PENDING: LazyLock<Mutex<HashMap<HostPort, PendingPrompts>>> =
    LazyLock::new(Default::default);
static ANSWERS: LazyLock<Mutex<HashMap<HostPort, Vec<Vec<String>>>>> =
    LazyLock::new(Default::default);

pub fn pending_prompts(host: &str, port: u16) -> Option<PendingPrompts> {
    PENDING
        .lock()
        .unwrap()
        .get(&(host.to_owned(), port))
        .cloned()
}

/// Answers for the next connect to `host:port`, used once.
pub fn set_answers(host: &str, port: u16, rounds: Vec<Vec<String>>) {
    ANSWERS
        .lock()
        .unwrap()
        .insert((host.to_owned(), port), rounds);
}

fn take_answers(host: &str, port: u16) -> Vec<Vec<String>> {
    let id = (host.to_owned(), port);
    PENDING.lock().unwrap().remove(&id);
    ANSWERS.lock().unwrap().remove(&id).unwrap_or_default()
}

// ponytail: a lone hidden prompt mentioning "password" gets the saved
// password (the usual PAM "Password: "); anything else goes to the user.
fn is_password_prompt(prompts: &[(String, bool)]) -> bool {
    matches!(prompts, [(text, false)] if text.to_lowercase().contains("password"))
}

/// Runs keyboard-interactive auth; Ok(false) when the server refuses it.
pub(crate) async fn authenticate<H: client::Handler>(
    session: &mut client::Handle<H>,
    profile: &SshProfile,
    step_timeout: std::time::Duration,
) -> Result<bool> {
    let mut answers = take_answers(&profile.host, profile.port).into_iter();
    let mut round = 0;
    let mut response = timeout(
        step_timeout,
        session.authenticate_keyboard_interactive_start(profile.username.clone(), None),
    )
    .await
    .map_err(|_| PortixError::AuthenticationTimeout)??;
    loop {
        let (name, instructions, prompts) = match response {
            KeyboardInteractiveAuthResponse::Success => return Ok(true),
            KeyboardInteractiveAuthResponse::Failure { .. } => return Ok(false),
            KeyboardInteractiveAuthResponse::InfoRequest {
                name,
                instructions,
                prompts,
            } => (
                name,
                instructions,
                prompts
                    .into_iter()
                    .map(|p| (p.prompt, p.echo))
                    .collect::<Vec<_>>(),
            ),
        };
        let reply = match &profile.password {
            _ if prompts.is_empty() => Vec::new(),
            Some(password) if is_password_prompt(&prompts) => vec![password.clone()],
            _ => match answers.next() {
                Some(reply) => {
                    round += 1;
                    reply
                }
                None => {
                    PENDING.lock().unwrap().insert(
                        (profile.host.clone(), profile.port),
                        PendingPrompts {
                            round,
                            name,
                            instructions,
                            prompts,
                        },
                    );
                    return Err(PortixError::KeyboardInteractiveRequired {
                        host: profile.host.clone(),
                        port: profile.port,
                    });
                }
            },
        };
        response = timeout(
            step_timeout,
            session.authenticate_keyboard_interactive_respond(reply),
        )
        .await
        .map_err(|_| PortixError::AuthenticationTimeout)??;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn password_prompt_detection() {
        assert!(is_password_prompt(&[("Password: ".into(), false)]));
        assert!(is_password_prompt(&[(
            "deploy@host's password:".into(),
            false
        )]));
        assert!(!is_password_prompt(&[(
            "Verification code: ".into(),
            false
        )]));
        assert!(!is_password_prompt(&[("Password: ".into(), true)]));
        assert!(!is_password_prompt(&[
            ("Password: ".into(), false),
            ("Code: ".into(), false)
        ]));
    }

    #[test]
    fn answers_are_used_once_and_clear_pending() {
        set_answers("kbd.test", 22, vec![vec!["123456".into()]]);
        PENDING.lock().unwrap().insert(
            ("kbd.test".into(), 22),
            PendingPrompts {
                round: 0,
                name: String::new(),
                instructions: String::new(),
                prompts: vec![("Code: ".into(), false)],
            },
        );
        assert_eq!(
            take_answers("kbd.test", 22),
            vec![vec!["123456".to_owned()]]
        );
        assert!(pending_prompts("kbd.test", 22).is_none());
        assert!(take_answers("kbd.test", 22).is_empty());
    }
}
