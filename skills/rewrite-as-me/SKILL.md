---
name: rewrite-as-me
description: Rewrite drafts so they sound like Kenichi Saito while preserving facts, intent, commitments, and requested actions. Use when the user asks to rewrite, polish, draft, reply, translate, or make text sound like them, especially for external Gmail/email communication or internal Slack messages in Japanese, English, or Chinese. Also use when the user asks to refresh or relearn their writing style from Gmail and Slack.
---

# Rewrite as Me

Rewrite the supplied content in Kenichi's voice. Treat Gmail as the external voice and Slack as the internal voice.

## Workflow

1. Read [references/voice-profile.md](references/voice-profile.md).
2. Determine the channel from the request or surrounding context:
   - Use `external-email` for Gmail, email, customers, vendors, factories, or other external recipients.
   - Use `internal-slack` for Slack and coworkers.
   - Ask one short question only when the channel materially changes the wording and cannot be inferred.
3. Preserve the source message's language unless the user requests a translation. Preserve names, dates, numbers, links, technical terms, decisions, uncertainty, and calls to action.
4. Rewrite for the selected voice. Improve clarity and structure, but do not add facts, confidence, promises, deadlines, recipients, greetings, signatures, or emotional intensity that the source does not support.
5. Return only the ready-to-use rewritten text by default. Add alternatives or an explanation only when requested.

## Editing Rules

- Keep the original meaning and scope. Do not turn a suggestion into a decision or an intention into a commitment.
- Prefer the shortest natural version that retains the necessary context.
- Match the draft's level of detail. Use bullets or numbered items only when they make multiple facts or requests easier to scan.
- Preserve intentional product names and common English technical terms.
- Do not copy sentences from source messages stored in Gmail or Slack. Apply patterns, not memorized passages.
- Do not expose or reproduce credentials, tokens, private addresses, phone numbers, quoted-thread contents, or unrelated personal information found during style analysis.
- Never send, post, draft, or edit Gmail/Slack content unless the user separately asks for that action.

## Relearn the Voice

Only refresh the profile when the user explicitly asks to relearn, recalibrate, or update the voice.

1. Read the installed Gmail and `agent-slack` skill instructions before accessing either source.
2. Use read-only operations and sample only messages authored by Kenichi from `2026-01-01` onward unless the user gives a different range.
3. For Gmail, sample Sent messages and analyze only Kenichi's newly authored body. Exclude signatures, quoted threads, forwarding headers, automated mail, and messages to internal `@franky.tokyo` recipients from the external profile.
4. For Slack, sample messages authored by the authenticated Kenichi account. Exclude forwarded content, automated reports, bot commands, pasted third-party text, generated PR bodies, and secrets.
5. Derive aggregate tendencies across varied recipients and message lengths. Do not overfit to one project, language, or unusually formal exchange.
6. Update only [references/voice-profile.md](references/voice-profile.md). Store aggregate observations and synthetic patterns; never store raw messages, message IDs, URLs, contact details, or credentials.
7. Report the date range, sample counts, and exclusions used.

## Quality Check

Before returning text, verify:

- It sounds natural for the selected channel without becoming a caricature.
- Every factual claim and commitment is traceable to the input.
- External email is courteous and direct; internal Slack is warm, quick, and conversational.
- The output can be pasted as-is.
