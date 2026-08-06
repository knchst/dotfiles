#!/usr/bin/env python3
from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import sqlite3
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable


CODEX_HOME = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")).expanduser()
STATE_DB = CODEX_HOME / "state_5.sqlite"
SKILLS_ROOT = CODEX_HOME / "skills"
SKILL_ROOTS = (CODEX_HOME / "skills", Path.home() / ".agents" / "skills")
GLOBAL_AGENTS = CODEX_HOME / "AGENTS.md"
REPO_SEARCH_ROOTS = (
    Path.home() / "Developer",
    Path.home() / "dev",
    Path.home() / "code",
    Path.home() / "personal",
)
CANONICAL_OBSIDIAN_ROOT = Path.home() / "Developer" / "knchst" / "Obsidian"

PREFERENCE_MARKERS = (
    "make sure", "default to", "prefer", "instead of", "do not", "don't",
    "never", "always", "should be", "should default", "i want you to",
    "i don't want", "preserve", "keep ", "lean on", "continue", "keep going",
    "don't stop", "come on", "can't you just",
    "必ず", "毎回", "常に", "今後", "デフォルト", "優先", "ではなく",
    "じゃなく", "しないで", "しないこと", "しなくて", "しないように",
    "禁止", "勝手に", "承認してから", "承認を得て", "確認してから",
    "先に", "まず", "維持", "保持", "そのまま", "続けて", "止めないで",
    "止まらず", "スコープ", "範囲を", "徹底", "忘れず",
)

SKIP_USER_MESSAGE_RE = re.compile(
    r"<INSTRUCTIONS>|#\s*AGENTS\.md instructions|PLEASE IMPLEMENT THIS PLAN|"
    r"<environment_context>|<recommended_plugins>|<codex_delegation>|<input>",
    re.IGNORECASE,
)
NOISY_SNIPPET_RE = re.compile(
    r"```|^#+\s|^[-+]{1,3}\s|^comment:\s|^file:\s|^lines:\s|"
    r"^(key changes|implementation|summary|test plan|assumptions)\b|"
    r"diff hunk|review findings|my request for codex",
    re.IGNORECASE,
)
TRANSIENT_ERROR_TOKENS = (
    "correct access rights and the repository exists",
    "fatal: could not read from remote repository",
    "repository not found",
)
QUESTION_PREFIXES = (
    "okay, can you", "ok, can you", "what should", "how should",
    "how do you think", "also, what", "also what", "can you propose",
    "can you look", "could you look", "first can you", "i feel like",
    "どうすれば", "どう思う", "できますか", "でしょうか",
)
QUESTION_OVERRIDE_MARKERS = (
    "make sure", "default to", "prefer", "必ず", "毎回", "しないで",
    "しないこと", "承認してから", "確認してから", "維持", "保持",
)
PROJECT_CONTEXT_TOKENS = (
    "agents.md", "readme", "this repo", "this project", "in this repo",
    "implementation", "component", "api", "docs", "slack", "vault",
    "screenshot", "このrepo", "このリポジトリ", "このプロジェクト", "実装",
    "コード", "画面", "機能", "アプリ", "ファームウェア", "バックエンド",
    "設定", "ドキュメント", "obsidian", "github", "linear", "gmail",
)
GLOBAL_CONTEXT_MARKERS = (
    "globally", "all repos", "all projects", "for any repo", "across repos",
    "グローバル", "すべてのrepo", "全repo", "すべてのリポジトリ",
    "どのrepoでも", "どのプロジェクトでも", "全プロジェクト", "常に共通",
)
PROJECT_IMPLEMENTATION_TOKENS = (
    "activation gating", "app-local state", "dom-derived", "selected widget",
    "event handlers", "typed fields", "streaming tokens", "audio output",
    "system message", "画面", "api", "firmware", "ファームウェア",
)
COMMON_WORDS = {
    "about", "after", "again", "also", "because", "could", "default",
    "doing", "first", "have", "instead", "maybe", "please", "should",
    "that", "their", "there", "these", "thing", "things", "this", "those",
    "using", "want", "would", "write", "your",
}


@dataclass(frozen=True)
class ThreadRecord:
    thread_id: str
    title: str
    source: str
    cwd: str
    created_at: int
    updated_at: int
    archived: bool
    model: str
    reasoning_effort: str
    rollout_path: str
    agent_role: str
    agent_nickname: str


@dataclass(frozen=True)
class Evidence:
    thread_id: str
    title: str
    updated_at: int
    rollout_path: str
    cwd: str
    cluster_key: str


@dataclass
class Proposal:
    bucket: str
    target: str
    suggestion: str
    evidence: list[Evidence] = field(default_factory=list)

    @property
    def support(self) -> int:
        return len({item.cluster_key for item in self.evidence})

    @property
    def last_seen(self) -> int:
        return max((item.updated_at for item in self.evidence), default=0)

    @property
    def confidence(self) -> float:
        score = 0.42 + min(self.support, 6) * 0.12
        lowered = self.suggestion.lower()
        if lowered.startswith(("i ", "this ", "that ", "only ", "leave room for")):
            score -= 0.18
        if any(token in lowered for token in (" kind of ", " sort of ", " maybe ", " thing ", " stuff ")):
            score -= 0.08
        if any(token in lowered for token in ("create sub-agents", "keep improving the complexity", "let's just iterate")):
            score -= 0.24
        if "?" in self.suggestion or "？" in self.suggestion:
            score -= 0.18
        if self.bucket == "Global AGENTS.md" and any(token in lowered for token in PROJECT_IMPLEMENTATION_TOKENS):
            score -= 0.22
        if "human-authored documentation" in lowered or "over-engineering" in lowered:
            score += 0.08
        if any(token in lowered for token in ("continue", "keep going", "don't stop", "続け", "止めない")):
            score += 0.08
        return max(0.0, min(0.99, score))


@dataclass(frozen=True)
class SkillRecord:
    name: str
    path: Path
    text: str
    aliases: tuple[str, ...]


def require_db(path: Path) -> None:
    if not path.exists():
        raise SystemExit(f"Codex state DBが見つかりません: {path}")


def to_utc(timestamp: int) -> str:
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")


def shorten(value: str, width: int) -> str:
    value = " ".join((value or "").split())
    return value if len(value) <= width else f"{value[:max(width - 1, 1)]}…"


def normalize_source(source: str) -> str:
    if not (source or "").startswith("{"):
        return source or ""
    try:
        parsed = json.loads(source)
    except json.JSONDecodeError:
        return source
    subagent = parsed.get("subagent")
    if isinstance(subagent, str):
        return f"subagent:{subagent}"
    if isinstance(subagent, dict):
        spawn = subagent.get("thread_spawn") or {}
        role = spawn.get("agent_role") or "subagent"
        nickname = spawn.get("agent_nickname")
        parent = spawn.get("parent_thread_id")
        if nickname and parent:
            return f"{role}:{nickname}@{parent[:8]}"
        return f"{role}@{parent[:8]}" if parent else role
    return source


def normalize_words(value: str) -> list[str]:
    return [
        token for token in re.findall(r"[^\W_]+", value.lower(), re.UNICODE)
        if token not in COMMON_WORDS and len(token) > 1
    ]


def normalize_tokens(value: str) -> set[str]:
    return set(normalize_words(value))


def thread_cluster_key(thread: ThreadRecord, target: str) -> str:
    day = datetime.fromtimestamp(thread.updated_at, tz=timezone.utc).strftime("%Y-%m-%d")
    title_key = "-".join(normalize_words(thread.title)[:12])
    return f"{target}::{title_key or thread.cwd or thread.thread_id}::{day}"


def fetch_threads(
    db_path: Path,
    *,
    limit: int,
    archived: str,
    cwd_prefix: str | None = None,
    source_query: str | None = None,
    model_query: str | None = None,
    text_query: str | None = None,
    days: int | None = None,
    top_level_only: bool = False,
) -> list[ThreadRecord]:
    require_db(db_path)
    where: list[str] = []
    params: list[Any] = []
    if archived == "active":
        where.append("archived = 0")
    elif archived == "archived":
        where.append("archived = 1")
    elif archived != "all":
        raise SystemExit("--archivedはactive、archived、allのいずれかです")
    if cwd_prefix:
        where.append("cwd LIKE ?")
        params.append(f"{cwd_prefix}%")
    if source_query:
        where.append("source LIKE ?")
        params.append(f"%{source_query}%")
    if model_query:
        where.append("coalesce(model, '') LIKE ?")
        params.append(f"%{model_query}%")
    if text_query:
        lowered = f"%{text_query.lower()}%"
        where.append("(lower(title) LIKE ? OR lower(first_user_message) LIKE ?)")
        params.extend([lowered, lowered])
    if days:
        cutoff = int((datetime.now(tz=timezone.utc) - timedelta(days=days)).timestamp())
        where.append("updated_at >= ?")
        params.append(cutoff)
    if top_level_only:
        where.extend((
            "source IN ('vscode', 'cli', 'exec')",
            "(agent_role IS NULL OR agent_role = '')",
            "title NOT LIKE 'Automation:%'",
            "title NOT LIKE '<codex_delegation>%'",
       ))
    where_sql = f"WHERE {' AND '.join(where)}" if where else ""
    sql = f"""
        SELECT id, title, source, cwd, created_at, updated_at, archived,
               coalesce(model, ''), coalesce(reasoning_effort, ''), rollout_path,
               coalesce(agent_role, ''), coalesce(agent_nickname, '')
        FROM threads {where_sql}
        ORDER BY updated_at DESC, id DESC LIMIT ?
    """
    params.append(limit)
    with sqlite3.connect(db_path) as connection:
        rows = connection.execute(sql, params).fetchall()
    return [ThreadRecord(row[0], row[1] or "", row[2] or "", row[3] or "", int(row[4]),
                         int(row[5]), bool(row[6]), row[7] or "", row[8] or "",
                         row[9] or "", row[10] or "", row[11] or "") for row in rows]


def fetch_thread_by_id(thread_id: str) -> ThreadRecord | None:
    require_db(STATE_DB)
    with sqlite3.connect(STATE_DB) as connection:
        row = connection.execute(
            """SELECT id, title, source, cwd, created_at, updated_at, archived,
                      coalesce(model, ''), coalesce(reasoning_effort, ''), rollout_path,
                      coalesce(agent_role, ''), coalesce(agent_nickname, '')
               FROM threads WHERE id = ?""", (thread_id,),
        ).fetchone()
    if not row:
        return None
    return ThreadRecord(row[0], row[1] or "", row[2] or "", row[3] or "", int(row[4]),
                        int(row[5]), bool(row[6]), row[7] or "", row[8] or "",
                        row[9] or "", row[10] or "", row[11] or "")


def find_orphan_rollout(thread_id: str) -> Path | None:
    for root in (CODEX_HOME / "sessions", CODEX_HOME / "archived_sessions"):
        if root.exists():
            match = next(root.rglob(f"*{thread_id}.jsonl"), None)
            if match:
                return match
    return None


def iter_rollout_events(path: Path) -> Iterable[dict[str, Any]]:
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError as error:
                raise SystemExit(f"不正なJSONです: {path}:{line_number}: {error}") from error


def collect_user_messages(thread: ThreadRecord) -> list[str]:
    path = Path(thread.rollout_path)
    if not path.exists():
        return []
    messages = []
    for event in iter_rollout_events(path):
        payload = event.get("payload") or {}
        if event.get("type") == "event_msg" and payload.get("type") == "user_message":
            if message := (payload.get("message") or "").strip():
                messages.append(message)
    return messages


def query_matches_thread(thread: ThreadRecord, query: str | None) -> bool:
    if not query:
        return True
    needle = query.lower()
    return any(needle in value.lower() for value in (thread.title, thread.cwd, *collect_user_messages(thread)))


def cmd_list(args: argparse.Namespace) -> None:
    rows = fetch_threads(STATE_DB, limit=args.limit, archived=args.archived,
                         cwd_prefix=args.cwd, source_query=args.source,
                         model_query=args.model, text_query=args.query,
                         days=args.days, top_level_only=args.top_level_only)
    print("Updated UTC         St Source            Model           CWD                              Title                            Thread")
    print("------------------- -- ----------------- --------------- -------------------------------- -------------------------------- ------------------------------------")
    for row in rows:
        state = "AR" if row.archived else "AC"
        print(f"{to_utc(row.updated_at):<19} {state:<2} {shorten(normalize_source(row.source), 17):<17} "
              f"{shorten(row.model, 15):<15} {shorten(row.cwd, 32):<32} "
              f"{shorten(row.title, 32):<32} {row.thread_id}")


def extract_message_text(payload: dict[str, Any]) -> str:
    return "\n".join(str(item.get("text")) for item in payload.get("content") or []
                     if isinstance(item, dict) and item.get("text")).strip()


def render_transcript(thread: ThreadRecord, max_tool_chars: int, include_instructions: bool) -> None:
    path = Path(thread.rollout_path)
    if not path.exists():
        path = find_orphan_rollout(thread.thread_id) or path
    print(f"# {thread.title or thread.thread_id}\n")
    for key, value in (("thread_id", thread.thread_id), ("updated_at", to_utc(thread.updated_at)),
                       ("created_at", to_utc(thread.created_at)), ("source", normalize_source(thread.source)),
                       ("model", thread.model), ("reasoning_effort", thread.reasoning_effort),
                       ("archived", int(thread.archived)), ("cwd", thread.cwd), ("rollout_path", path)):
        print(f"- {key}: `{value}`")
    print()
    for event in iter_rollout_events(path):
        event_type, payload = event.get("type"), event.get("payload") or {}
        if event_type == "event_msg":
            payload_type = payload.get("type")
            if payload_type in {"user_message", "agent_message"}:
                message = (payload.get("message") or "").strip()
                if message:
                    heading = "User" if payload_type == "user_message" else f"Assistant ({payload.get('phase') or 'assistant'})"
                    print(f"## {heading}\n\n{message}\n")
            elif payload_type in {"task_started", "task_complete"}:
                print(f"## {'Task Started' if payload_type == 'task_started' else 'Task Complete'}\n")
            continue
        if event_type != "response_item":
            continue
        payload_type = payload.get("type")
        if payload_type == "message" and include_instructions and payload.get("role") in {"developer", "system"}:
            text = extract_message_text(payload)
            if text:
                print(f"## {payload.get('role').title()} Instructions\n\n{text}\n")
        elif payload_type == "function_call":
            print(f"## Tool Call: {payload.get('name') or 'unknown_tool'}\n\n```json\n"
                  f"{shorten(str(payload.get('arguments') or ''), max_tool_chars)}\n```\n")
        elif payload_type == "function_call_output":
            print(f"## Tool Output: {payload.get('call_id') or 'unknown'}\n\n```text\n"
                  f"{shorten(str(payload.get('output') or ''), max_tool_chars)}\n```\n")


def cmd_show(args: argparse.Namespace) -> None:
    thread = fetch_thread_by_id(args.thread_id)
    if thread:
        render_transcript(thread, args.max_tool_chars, args.include_instructions)
        return
    orphan = find_orphan_rollout(args.thread_id)
    if not orphan:
        raise SystemExit(f"タスクが見つかりません: {args.thread_id}")
    print(f"# Orphan Rollout {args.thread_id}\n\n- rollout_path: `{orphan}`\n")


def split_sentences(message: str) -> Iterable[str]:
    message = message.replace("\r\n", "\n").replace("\r", "\n")
    for chunk in re.split(r"(?<=[。！？])|(?<=[.!?])(?:\s+|$)|[;；]\s*|\s+\|\s+|\n+", message):
        chunk = re.sub(r"\s+", " ", chunk).strip(" \t\"'`・")
        chunk = re.sub(r"^(?:[-+*]|\d+[.)]|[①-⑳])\s*", "", chunk)
        if chunk:
            yield chunk


def looks_like_preference(sentence: str) -> bool:
    lowered = sentence.lower()
    if NOISY_SNIPPET_RE.search(sentence) or any(token in lowered for token in TRANSIENT_ERROR_TOKENS):
        return False
    if "don't know" in lowered or "do not know" in lowered or "わからない" in sentence:
        return False
    if lowered.startswith(QUESTION_PREFIXES):
        return False
    explicit = any(marker in lowered for marker in PREFERENCE_MARKERS)
    if sentence.endswith(("?", "？")) and not any(marker in lowered for marker in QUESTION_OVERRIDE_MARKERS):
        return False
    if lowered.startswith("can you") and not any(marker in lowered for marker in ("make sure", "default to", "prefer")):
        return False
    return explicit


def normalize_suggestion(sentence: str) -> str:
    suggestion = sentence.strip()
    suggestion = re.sub(r"^(okay|ok|yeah|and then)[, ]+", "", suggestion, flags=re.IGNORECASE)
    suggestion = re.sub(r"^(can you|could you)\s+(please\s+)?", "", suggestion, flags=re.IGNORECASE)
    suggestion = re.sub(r"^make sure\s+(that\s+)?", "", suggestion, flags=re.IGNORECASE)
    suggestion = re.sub(r"^i want you to\s+", "", suggestion, flags=re.IGNORECASE)
    suggestion = re.sub(r"^let'?s\s+", "Prefer to ", suggestion, flags=re.IGNORECASE)
    suggestion = re.sub(r"\b(relatively speaking|kind of|sort of|basically|actually|really)\b", "", suggestion, flags=re.IGNORECASE)
    suggestion = re.sub(r"^(はい|うん|そうですね|お願いします|あと|それと)[、,\s]+", "", suggestion)
    suggestion = re.sub(r"^(できれば|可能であれば)[、,\s]*", "", suggestion)
    lowered = suggestion.lower()
    if lowered in {"continue", "keep going", "just keep going", "sorry keep going"} or "don't stop" in lowered:
        return "ユーザーが`continue`、`keep going`、`don't stop`と伝えたら、実際のblockerや破壊的操作の承認境界がない限り、不要な確認で止まらず現在のタスクを続行する。"
    if lowered == "come on" or "can't you just" in lowered:
        return "ユーザーの苛立ちを示す表現を検知したら、広い質問を返さず、ローカル環境を直接調べて具体的な作業を進める。"
    suggestion = re.sub(r"\s+", " ", suggestion).strip(" .!?。！？")
    if not suggestion:
        return ""
    if re.search(r"[ぁ-んァ-ン一-龯]", suggestion):
        return suggestion + "。"
    suggestion = suggestion[0].upper() + suggestion[1:]
    return suggestion + "."


def known_repo_roots() -> tuple[Path, ...]:
    roots: list[Path] = []
    if CANONICAL_OBSIDIAN_ROOT.exists():
        roots.append(CANONICAL_OBSIDIAN_ROOT)
    for search_root in REPO_SEARCH_ROOTS:
        if search_root.is_dir():
            for child in search_root.iterdir():
                if not child.is_dir():
                    continue
                if (child / ".git").exists():
                    roots.append(child)
                for grandchild in child.iterdir():
                    if grandchild.is_dir() and (grandchild / ".git").exists():
                        roots.append(grandchild)
    return tuple(roots)


def resolve_repo_root_name(repo_name: str, fallback: Path) -> Path:
    candidates = known_repo_roots()
    exact = next((path for path in candidates if path.name == repo_name), None)
    if exact:
        return exact
    scored = sorted(((difflib.SequenceMatcher(None, repo_name, path.name).ratio(), path)
                     for path in candidates), reverse=True, key=lambda item: item[0])
    return scored[0][1] if scored and scored[0][0] >= 0.74 else fallback


def infer_project_agents_path(cwd: str) -> str:
    path = Path(cwd).expanduser()
    worktrees_root = CODEX_HOME / "worktrees"
    try:
        relative = path.relative_to(worktrees_root)
    except ValueError:
        relative = None
    if relative and len(relative.parts) >= 2:
        repo_name = relative.parts[1]
        repo_root = resolve_repo_root_name(repo_name, worktrees_root / relative.parts[0] / repo_name)
        return str(next((repo_root / name for name in ("AGENTS.md", "AGENTS.MD") if (repo_root / name).exists()), repo_root / "AGENTS.md"))
    for candidate in (path, *path.parents):
        if candidate in {Path.home(), CODEX_HOME}:
            break
        for name in ("AGENTS.md", "AGENTS.MD"):
            if (candidate / name).exists():
                return str(candidate / name)
        if (candidate / ".git").exists():
            return str(candidate / "AGENTS.md")
    return str(path / "AGENTS.md")


def installed_skill_names() -> list[str]:
    names = {path.parent.name for root in SKILL_ROOTS if root.exists() for path in root.glob("*/SKILL.md")}
    return sorted(names, key=len, reverse=True)


def infer_skill_path(sentence: str, cwd: str, skills: list[str]) -> str:
    cwd_path = Path(cwd).expanduser()
    for root in SKILL_ROOTS:
        try:
            candidate = root / cwd_path.relative_to(root).parts[0] / "SKILL.md"
            if candidate.exists():
                return str(candidate)
        except (ValueError, IndexError):
            pass
    lowered = sentence.lower()
    for name in skills:
        if name.lower() in lowered or name.lower().replace("-", " ") in lowered:
            for root in SKILL_ROOTS:
                if (root / name / "SKILL.md").exists():
                    return str(root / name / "SKILL.md")
    return str(SKILLS_ROOT / "<new-skill>" / "SKILL.md")


def classify_bucket(sentence: str, thread: ThreadRecord, skills: list[str]) -> tuple[str, str]:
    lowered, cwd = sentence.lower(), thread.cwd or ""
    if ("skill" in lowered or "スキル" in sentence or "skill.md" in lowered or
            "/skills/" in lowered or any(cwd.startswith(str(root)) for root in SKILL_ROOTS)):
        return "Skills", infer_skill_path(sentence, cwd, skills)
    if cwd in {str(Path.home()), str(CODEX_HOME)} or any(marker in lowered for marker in GLOBAL_CONTEXT_MARKERS):
        return "Global AGENTS.md", str(GLOBAL_AGENTS)
    if cwd.startswith(str(CANONICAL_OBSIDIAN_ROOT)):
        return "Project AGENTS.md", infer_project_agents_path(cwd)
    if any(token in lowered for token in PROJECT_CONTEXT_TOKENS):
        return "Project AGENTS.md", infer_project_agents_path(cwd)
    return "Global AGENTS.md", str(GLOBAL_AGENTS)


def extract_preference_signals(thread: ThreadRecord) -> list[tuple[str, str]]:
    signals = []
    for message in collect_user_messages(thread):
        if not message or len(message) > 5000 or SKIP_USER_MESSAGE_RE.search(message):
            continue
        for sentence in split_sentences(message):
            if not 8 <= len(sentence) <= 600 or not looks_like_preference(sentence):
                continue
            suggestion = normalize_suggestion(sentence)
            if len(suggestion) >= 12:
                signals.append((sentence, suggestion))
    return signals


def collect_proposals(rows: list[ThreadRecord], min_support: int) -> list[Proposal]:
    skills, grouped = installed_skill_names(), {}
    for thread in rows:
        for raw, suggestion in extract_preference_signals(thread):
            bucket, target = classify_bucket(raw, thread, skills)
            key = (bucket, target, suggestion.lower())
            proposal = grouped.setdefault(key, Proposal(bucket, target, suggestion))
            if not any(item.thread_id == thread.thread_id for item in proposal.evidence):
                proposal.evidence.append(Evidence(thread.thread_id, thread.title, thread.updated_at,
                                                  thread.rollout_path, thread.cwd,
                                                  thread_cluster_key(thread, target)))
    proposals = [proposal for proposal in grouped.values() if proposal.support >= min_support]
    return sorted(proposals, key=lambda item: (item.bucket, -item.confidence, -item.support, -item.last_seen, item.target))


def parse_skill_name(text: str, fallback: str) -> str:
    match = re.search(r"^name:\s*['\"]?([^'\"\n]+)['\"]?\s*$", text, re.MULTILINE)
    return match.group(1).strip() if match else fallback


@lru_cache(maxsize=1)
def load_skill_records() -> tuple[SkillRecord, ...]:
    records, seen = [], set()
    for root in SKILL_ROOTS:
        if not root.exists():
            continue
        for path in sorted(root.glob("*/SKILL.md")):
            real = path.resolve()
            if real in seen:
                continue
            seen.add(real)
            text = path.read_text(encoding="utf-8")
            name = parse_skill_name(text, path.parent.name)
            aliases = {name.lower(), f"${name.lower()}", name.lower().replace("-", " "),
                       path.parent.name.lower(), str(path).lower()}
            records.append(SkillRecord(name, path, text, tuple(sorted(aliases))))
    return tuple(sorted(records, key=lambda record: record.name))


def suggestion_already_documented(skill: SkillRecord, suggestion: str) -> bool:
    suggestion_text = " ".join(suggestion.lower().split())
    skill_text = " ".join(skill.text.lower().split())
    if suggestion_text in skill_text:
        return True
    tokens = normalize_tokens(suggestion)
    if len(tokens) < 3:
        return False
    overlap = len(tokens & normalize_tokens(skill.text)) / len(tokens)
    return overlap >= 0.85 or difflib.SequenceMatcher(None, suggestion_text, skill_text).ratio() >= 0.9


def collect_skill_audit_proposals(rows: list[ThreadRecord], skill_name: str | None,
                                  min_support: int) -> tuple[list[Proposal], list[SkillRecord]]:
    skills = list(load_skill_records())
    if skill_name:
        needle = skill_name.lower()
        skills = [skill for skill in skills if needle in {skill.name.lower(), skill.path.parent.name.lower(), *skill.aliases}]
        if not skills:
            raise SystemExit(f"インストール済みスキルが見つかりません: {skill_name}")
    grouped = {}
    for thread in rows:
        messages = collect_user_messages(thread)
        suggestions = [suggestion for _, suggestion in extract_preference_signals(thread)]
        haystack = " ".join((thread.title, thread.cwd, *messages)).lower()
        for skill in skills:
            if not any(alias in haystack for alias in skill.aliases):
                continue
            for suggestion in suggestions:
                if suggestion_already_documented(skill, suggestion):
                    continue
                key = (str(skill.path), suggestion.lower())
                proposal = grouped.setdefault(key, Proposal("Skills", str(skill.path), suggestion))
                if not any(item.thread_id == thread.thread_id for item in proposal.evidence):
                    proposal.evidence.append(Evidence(thread.thread_id, thread.title, thread.updated_at,
                                                      thread.rollout_path, thread.cwd,
                                                      thread_cluster_key(thread, str(skill.path))))
    proposals = [proposal for proposal in grouped.values() if proposal.support >= min_support]
    return sorted(proposals, key=lambda item: (-item.confidence, -item.support, -item.last_seen, item.target)), skills


def emit_evidence(proposal: Proposal) -> None:
    print(f"- 提案: {proposal.suggestion}")
    print(f"  Support: {proposal.support} thread cluster(s)")
    print(f"  Confidence: {proposal.confidence:.2f}")
    evidence = [f"{item.thread_id} | {shorten(item.title, 60)} | {to_utc(item.updated_at)} | {item.rollout_path}"
                for item in proposal.evidence[:3]]
    print(f"  Evidence: {' || '.join(evidence)}")


def emit_patch_preview(proposals: list[Proposal], maximum: int) -> None:
    grouped: dict[str, dict[str, list[Proposal]]] = defaultdict(lambda: defaultdict(list))
    for proposal in proposals:
        grouped[proposal.bucket][proposal.target].append(proposal)
    print("## Patch Preview\n")
    for bucket in ("Skills", "Project AGENTS.md", "Global AGENTS.md"):
        for target, items in grouped.get(bucket, {}).items():
            print(f"### {bucket}\n\n```diff\n--- {target}\n+++ {target}\n@@")
            for proposal in items[:maximum]:
                print(f"+- {proposal.suggestion}")
            print("```\n")


def cmd_dream(args: argparse.Namespace) -> None:
    rows = fetch_threads(STATE_DB, limit=args.limit, archived=args.archived,
                         cwd_prefix=args.cwd, days=args.days, top_level_only=True)
    rows = [row for row in rows if query_matches_thread(row, args.query)]
    proposals = [proposal for proposal in collect_proposals(rows, args.min_support)
                 if proposal.confidence >= args.min_confidence]
    oldest = min((row.updated_at for row in rows), default=0)
    newest = max((row.updated_at for row in rows), default=0)
    print("# /self-improve dream\n")
    print(f"{len(rows)}件のトップレベルタスクを分析しました: "
          f"{to_utc(oldest) if oldest else 'n/a'} 〜 {to_utc(newest) if newest else 'n/a'}")
    print("既定の書き込み方針: propose-first。明示承認前にファイルを変更しません。\n")
    for bucket in ("Skills", "Project AGENTS.md", "Global AGENTS.md"):
        print(f"## {bucket}\n")
        items = [proposal for proposal in proposals if proposal.bucket == bucket][:args.max_per_bucket]
        if not items:
            print("- このサンプルでは強い提案が見つかりませんでした。\n")
        for proposal in items:
            print(f"- Target: `{proposal.target}`")
            emit_evidence(proposal)
            print()
    if args.emit_patch and proposals:
        emit_patch_preview(proposals, args.max_per_bucket)


def cmd_skill_audit(args: argparse.Namespace) -> None:
    rows = fetch_threads(STATE_DB, limit=args.limit, archived=args.archived,
                         days=args.days, top_level_only=True)
    rows = [row for row in rows if query_matches_thread(row, args.query)]
    proposals, skills = collect_skill_audit_proposals(rows, args.skill, args.min_support)
    proposals = [proposal for proposal in proposals if proposal.confidence >= args.min_confidence]
    print("# /self-improve skill-audit\n")
    print(f"{len(rows)}件のトップレベルタスクと{len(skills)}個のスキルを分析しました。")
    print("既定の書き込み方針: propose-first。明示承認前にSKILL.mdを変更しません。\n")
    if not proposals:
        print("- このサンプルでは未記載のスキル改善案が見つかりませんでした。")
        return
    grouped: dict[str, list[Proposal]] = defaultdict(list)
    for proposal in proposals:
        grouped[proposal.target].append(proposal)
    for target, items in sorted(grouped.items()):
        print(f"## {target}\n")
        for proposal in items[:args.max_per_skill]:
            emit_evidence(proposal)
        print()
    if args.emit_patch:
        emit_patch_preview(proposals, args.max_per_skill)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Codexタスクを調べ、自己改善の提案を作成します。")
    commands = parser.add_subparsers(dest="command", required=True)
    listing = commands.add_parser("list", help="state_5.sqliteからタスクを一覧します。")
    listing.add_argument("--limit", type=int, default=25)
    listing.add_argument("--archived", choices=("active", "archived", "all"), default="active")
    listing.add_argument("--cwd"); listing.add_argument("--source"); listing.add_argument("--model")
    listing.add_argument("--query"); listing.add_argument("--days", type=int)
    listing.add_argument("--top-level-only", action="store_true"); listing.set_defaults(func=cmd_list)
    show = commands.add_parser("show", help="1件のタスクをtranscriptとして表示します。")
    show.add_argument("thread_id"); show.add_argument("--max-tool-chars", type=int, default=1600)
    show.add_argument("--include-instructions", action="store_true"); show.set_defaults(func=cmd_show)
    dream = commands.add_parser("dream", help="繰り返された修正指示と好みを抽出します。")
    dream.add_argument("--limit", type=int, default=250); dream.add_argument("--days", type=int, default=365)
    dream.add_argument("--archived", choices=("active", "archived", "all"), default="all")
    dream.add_argument("--cwd"); dream.add_argument("--query"); dream.add_argument("--min-support", type=int, default=1)
    dream.add_argument("--min-confidence", type=float, default=0.5); dream.add_argument("--max-per-bucket", type=int, default=25)
    dream.add_argument("--emit-patch", action="store_true"); dream.set_defaults(func=cmd_dream)
    audit = commands.add_parser("skill-audit", help="既存スキルに不足するルールを抽出します。")
    audit.add_argument("--skill"); audit.add_argument("--limit", type=int, default=500)
    audit.add_argument("--days", type=int, default=365)
    audit.add_argument("--archived", choices=("active", "archived", "all"), default="all")
    audit.add_argument("--query"); audit.add_argument("--min-support", type=int, default=1)
    audit.add_argument("--min-confidence", type=float, default=0.6); audit.add_argument("--max-per-skill", type=int, default=8)
    audit.add_argument("--emit-patch", action="store_true"); audit.set_defaults(func=cmd_skill_audit)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
