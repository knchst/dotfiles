---
name: self-improve
description: Codexの過去タスクを調べ、繰り返された日本語・英語の修正指示や作業上の好みを証拠付きで抽出し、既存スキル、project-local AGENTS.md、global AGENTS.mdの改善案を提示する。ユーザーが過去セッションの確認、dream pass、自己改善、繰り返しの指摘の分析、スキル監査、AGENTS.mdやSKILL.mdの改善を依頼したときに使う。
---

# Self Improve

Codexのローカルタスク履歴から、再利用可能な改善ルールを日本語で提案する。原版 `jxnl/dots/agents/skills/self-improve` の4コマンドとpropose-first設計を維持する。

## Workflow

1. 候補タスクを一覧する。

   ```bash
   python3 scripts/self_improve.py list --limit 25 --archived all
   ```

2. 提案の根拠を直接確認するときは、対象タスクをtranscriptとして表示する。

   ```bash
   python3 scripts/self_improve.py show <thread-id>
   ```

3. 繰り返された修正指示と作業上の好みを調べる。

   ```bash
   python3 scripts/self_improve.py dream --limit 250 --days 365 --min-support 2 --min-confidence 0.6 --emit-patch
   ```

4. 既存スキルごとの不足ルールを調べる。

   ```bash
   python3 scripts/self_improve.py skill-audit --limit 500 --days 365 --min-support 1 --min-confidence 0.6 --emit-patch
   ```

5. 提案を次のいずれか一つへ配置する。
   - `Skills`: 既存`SKILL.md`の改善、script/referenceの追加、新規スキル。
   - `Project AGENTS.md`: 特定repoやvaultだけに適用する指示。
   - `Global AGENTS.md`: repoをまたいで常に適用する指示。

6. 提案を採用する前に、必ず`show`で引用元の文脈を確認する。

## Source of Truth

- `~/.codex/state_5.sqlite`をタスク一覧の正本として扱う。
- `threads.rollout_path`が示す`~/.codex/sessions`または`~/.codex/archived_sessions`のJSONLを発言の正本として扱う。
- `~/.codex/memories/MEMORY.md`と`memory_summary.md`は候補探索の補助に限り、提案の証拠には元タスクを使う。
- canonical Obsidian rootは`/Users/knchst/Developer/knchst/Obsidian`だけを使う。旧`Obsidian/Primary`は読まない。

## Proposal Rules

- 常にpropose-firstで進める。明示承認前に`SKILL.md`や`AGENTS.md`を変更しない。
- 各提案にthread ID、UTC日時、rollout pathを付け、事実と推論を分ける。
- 一度きりの実装依頼を永続ルールへ昇格させない。原則として`--min-support 2`を使う。
- Supportはthread数ではなく、対象・タスクタイトル・日付で重複排除したcluster数として読む。
- project固有のルールをglobalへ重複掲載しない。
- project提案はcwdから最も近い既存`AGENTS.md`を優先し、次にrepo rootを使う。
- skill提案は`~/.codex/skills`または`~/.agents/skills`の既存スキルへ対応付ける。不明な場合だけ新規スキルとして提案する。
- `--emit-patch`は表示用のdiff previewであり、実ファイルを変更しない。
- transcriptには機密情報が含まれ得る。出力を外部共有せず、必要最小限のタスクだけ表示する。

## Japanese Optimization

- `。！？`、改行、箇条書きを文境界として扱う。
- `必ず`、`毎回`、`今後`、`ではなく`、`しないで`、`承認してから`、`まず`、`維持`などを継続的な指示の候補として扱う。
- 日本語の提案は英訳せず、元の意味と強さを保った自然な日本語へ正規化する。
- `このrepo`、`このプロジェクト`、`実装`、`画面`、`Slack`、`Obsidian`などをproject文脈として扱う。
- `すべてのrepo`、`どのプロジェクトでも`、`グローバル`などが明示された場合だけglobal性を強く推定する。

## Script

`scripts/self_improve.py`は`list`、`show`、`dream`、`skill-audit`を提供する。標準ライブラリだけを使い、読み取りと標準出力以外の状態変更を行わない。

## Upstream

Behavior and command structure are based on `https://github.com/jxnl/dots/tree/master/agents/skills/self-improve` (retrieved 2026-08-06). This implementation is rewritten for Japanese Codex sessions and Kenichi's local project layout.
