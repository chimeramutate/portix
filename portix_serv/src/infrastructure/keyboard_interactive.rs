//! Keyboard-interactive auth (OTP / 2FA / PAM prompts) without a callback
//! into Dart: a connect that meets prompts it cannot answer records them and
//! fails with [`PortixError::KeyboardInteractiveRequired`]; the UI reads them
//! with [`pending_prompts`], answers them with [`answer_pending`] and
//! connects again. Earlier rounds' answers stay here, not in Dart, and every
//! connect attempt takes them, so nothing is kept after a login ends.

use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};

use russh::client::{self, KeyboardInteractiveAuthResponse};
use tokio::time::timeout;

use crate::domain::errors::{PortixError, Result};
use crate::domain::profile::SshProfile;

#[derive(Clone, Debug, PartialEq)]
pub struct PendingPrompts {
    pub name: String,
    pub instructions: String,
    /// (prompt text, echo the typed answer)
    pub prompts: Vec<(String, bool)>,
}

type HostPort = (String, u16);

/// The unanswered round, and the answers to the rounds before it.
static PENDING: LazyLock<Mutex<HashMap<HostPort, (PendingPrompts, Vec<Vec<String>>)>>> =
    LazyLock::new(Default::default);
static ANSWERS: LazyLock<Mutex<HashMap<HostPort, Vec<Vec<String>>>>> =
    LazyLock::new(Default::default);

pub fn pending_prompts(host: &str, port: u16) -> Option<PendingPrompts> {
    PENDING
        .lock()
        .unwrap()
        .get(&(host.to_owned(), port))
        .map(|(prompts, _)| prompts.clone())
}

/// Answers the pending round; the next connect to `host:port` replays the
/// earlier rounds and this one.
pub fn answer_pending(host: &str, port: u16, answers: Vec<String>) {
    let id = (host.to_owned(), port);
    let mut rounds = PENDING
        .lock()
        .unwrap()
        .remove(&id)
        .map(|(_, answered)| answered)
        .unwrap_or_default();
    rounds.push(answers);
    ANSWERS.lock().unwrap().insert(id, rounds);
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
    let mut answered = Vec::new();
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
                    answered.push(reply.clone());
                    reply
                }
                None => {
                    let prompts = PendingPrompts {
                        name,
                        instructions,
                        prompts,
                    };
                    PENDING
                        .lock()
                        .unwrap()
                        .insert((profile.host.clone(), profile.port), (prompts, answered));
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

    fn pend(host: &str, answered: Vec<Vec<String>>) {
        let prompts = PendingPrompts {
            name: String::new(),
            instructions: String::new(),
            prompts: vec![("Code: ".into(), false)],
        };
        PENDING
            .lock()
            .unwrap()
            .insert((host.into(), 22), (prompts, answered));
    }

    #[test]
    fn answering_appends_to_earlier_rounds_and_is_used_once() {
        pend("kbd.test", vec![vec!["111".into()]]);
        answer_pending("kbd.test", 22, vec!["222".into()]);
        assert!(pending_prompts("kbd.test", 22).is_none());
        assert_eq!(
            take_answers("kbd.test", 22),
            vec![vec!["111".to_owned()], vec!["222".to_owned()]]
        );
        assert!(take_answers("kbd.test", 22).is_empty());
    }

    #[test]
    fn a_cancelled_round_is_dropped_by_the_next_connect() {
        pend("cancel.test", vec![vec!["111".into()]]);
        assert!(take_answers("cancel.test", 22).is_empty());
        assert!(pending_prompts("cancel.test", 22).is_none());
    }
}
