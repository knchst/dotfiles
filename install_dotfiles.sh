#!/bin/sh

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd) || {
    printf 'ERROR could not resolve installer directory\n' >&2
    exit 1
}
REPO_ROOT=$SCRIPT_DIR
REPO_PHYSICAL=$(CDPATH= cd "$SCRIPT_DIR" && pwd -P) || {
    printf 'ERROR could not resolve installer directory\n' >&2
    exit 1
}
MANIFEST=$REPO_ROOT/dotfiles.manifest

DRY_RUN=0
AI_ONLY=0
BACKUP_SET=0
BACKUP_DIR=
PREFLIGHT_FAILED=0

usage() {
    printf '%s\n' 'usage: install_dotfiles.sh [--dry-run] [--ai-only] [--backup-dir ABSOLUTE_PATH]'
}

fail() {
    printf 'ERROR %s\n' "$*" >&2
    exit 1
}

record_error() {
    printf 'ERROR %s\n' "$*" >&2
    PREFLIGHT_FAILED=1
}

record_conflict() {
    printf 'CONFLICT %s\n' "$*" >&2
    PREFLIGHT_FAILED=1
}

path_exists() {
    [ -e "$1" ] || [ -L "$1" ]
}

is_safe_relative_path() {
    case $1 in
        ''|/*|.|..|./*|../*|*/|*//*|*/./*|*/.|*/../*|*/..)
            return 1
            ;;
    esac
    return 0
}

is_selected() {
    if [ "$AI_ONLY" -eq 0 ]; then
        return 0
    fi

    case $1 in
        .codex/*|.claude/*|.config/opencode/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

parse_manifest_line() {
    PARSE_RAW=$1
    PARSE_LINE_NUMBER=$2
    MANIFEST_MODE=
    MANIFEST_PATH=

    set -f
    SAVED_IFS=$IFS
    IFS=' 	'
    set -- $PARSE_RAW
    IFS=$SAVED_IFS
    set +f

    if [ "$#" -ne 2 ]; then
        record_error "manifest line $PARSE_LINE_NUMBER must contain exactly two fields"
        return 1
    fi

    MANIFEST_MODE=$1
    MANIFEST_PATH=$2
    return 0
}

validate_manifest_syntax() {
    MANIFEST_LINE_NUMBER=0

    while IFS= read -r MANIFEST_RAW || [ -n "$MANIFEST_RAW" ]; do
        MANIFEST_LINE_NUMBER=$((MANIFEST_LINE_NUMBER + 1))
        parse_manifest_line "$MANIFEST_RAW" "$MANIFEST_LINE_NUMBER" || continue

        case $MANIFEST_MODE in
            link|seed)
                ;;
            *)
                record_error "manifest line $MANIFEST_LINE_NUMBER has invalid mode: $MANIFEST_MODE"
                ;;
        esac

        if ! is_safe_relative_path "$MANIFEST_PATH"; then
            record_error "manifest line $MANIFEST_LINE_NUMBER has unsafe path: $MANIFEST_PATH"
        fi
    done < "$MANIFEST"
}

validate_manifest_duplicates() {
    OUTER_LINE_NUMBER=0

    while IFS= read -r OUTER_RAW || [ -n "$OUTER_RAW" ]; do
        OUTER_LINE_NUMBER=$((OUTER_LINE_NUMBER + 1))
        parse_manifest_line "$OUTER_RAW" "$OUTER_LINE_NUMBER" || continue
        OUTER_PATH=$MANIFEST_PATH
        INNER_LINE_NUMBER=0

        while IFS= read -r INNER_RAW || [ -n "$INNER_RAW" ]; do
            INNER_LINE_NUMBER=$((INNER_LINE_NUMBER + 1))
            if [ "$INNER_LINE_NUMBER" -ge "$OUTER_LINE_NUMBER" ]; then
                break
            fi

            parse_manifest_line "$INNER_RAW" "$INNER_LINE_NUMBER" || continue
            case $OUTER_PATH in
                "$MANIFEST_PATH"|"$MANIFEST_PATH"/*)
                    record_error "manifest line $OUTER_LINE_NUMBER conflicts with line $INNER_LINE_NUMBER: $OUTER_PATH"
                    break
                    ;;
            esac
            case $MANIFEST_PATH in
                "$OUTER_PATH"/*)
                    record_error "manifest line $OUTER_LINE_NUMBER conflicts with line $INNER_LINE_NUMBER: $OUTER_PATH"
                break
                    ;;
            esac
        done < "$MANIFEST"
    done < "$MANIFEST"
}

normalize_absolute_path() {
    NORMALIZE_REST=${1#/}
    NORMALIZED_PATH=

    while [ -n "$NORMALIZE_REST" ]; do
        NORMALIZE_COMPONENT=${NORMALIZE_REST%%/*}
        case $NORMALIZE_REST in
            */*)
                NORMALIZE_REST=${NORMALIZE_REST#*/}
                ;;
            *)
                NORMALIZE_REST=
                ;;
        esac

        case $NORMALIZE_COMPONENT in
            ''|.)
                ;;
            ..)
                NORMALIZED_PATH=${NORMALIZED_PATH%/*}
                ;;
            *)
                NORMALIZED_PATH=$NORMALIZED_PATH/$NORMALIZE_COMPONENT
                ;;
        esac
    done

    if [ -z "$NORMALIZED_PATH" ]; then
        NORMALIZED_PATH=/
    fi
}

validate_backup_dir() {
    case $BACKUP_DIR in
        /*)
            ;;
        *)
            record_error 'backup directory must be an absolute path'
            return 1
            ;;
    esac

    normalize_absolute_path "$BACKUP_DIR"
    BACKUP_DIR=$NORMALIZED_PATH

    if [ "$BACKUP_DIR" = / ]; then
        record_error 'backup directory must not be the filesystem root'
        return 1
    fi

    case $BACKUP_DIR in
        "$REPO_ROOT"|"$REPO_ROOT"/*)
            record_error "backup directory must be outside the repository: $BACKUP_DIR"
            return 1
            ;;
    esac

    if [ -L "$BACKUP_DIR" ]; then
        record_error "backup directory must not be a symlink: $BACKUP_DIR"
        return 1
    fi

    if [ -e "$BACKUP_DIR" ] && [ ! -d "$BACKUP_DIR" ]; then
        record_error "backup directory is not a directory: $BACKUP_DIR"
        return 1
    fi

    BACKUP_EXISTING=$BACKUP_DIR
    BACKUP_SUFFIX=
    while ! path_exists "$BACKUP_EXISTING"; do
        BACKUP_COMPONENT=${BACKUP_EXISTING##*/}
        BACKUP_SUFFIX=/$BACKUP_COMPONENT$BACKUP_SUFFIX
        BACKUP_PARENT=${BACKUP_EXISTING%/*}
        if [ -z "$BACKUP_PARENT" ]; then
            BACKUP_PARENT=/
        fi
        if [ "$BACKUP_PARENT" = "$BACKUP_EXISTING" ]; then
            record_error "could not resolve backup directory: $BACKUP_DIR"
            return 1
        fi
        BACKUP_EXISTING=$BACKUP_PARENT
    done

    if [ -L "$BACKUP_EXISTING" ]; then
        record_error "backup directory has a symlinked ancestor: $BACKUP_EXISTING"
        return 1
    fi

    if [ ! -d "$BACKUP_EXISTING" ]; then
        record_error "backup directory has a non-directory ancestor: $BACKUP_EXISTING"
        return 1
    fi

    BACKUP_PHYSICAL=$(CDPATH= cd "$BACKUP_EXISTING" && pwd -P) || {
        record_error "could not resolve backup directory: $BACKUP_DIR"
        return 1
    }
    normalize_absolute_path "$BACKUP_PHYSICAL$BACKUP_SUFFIX"

    case $NORMALIZED_PATH in
        "$REPO_PHYSICAL"|"$REPO_PHYSICAL"/*)
            record_error "backup directory must be outside the repository: $BACKUP_DIR"
            return 1
            ;;
    esac

    return 0
}

validate_target_ancestors() {
    TARGET_PARENT=$(dirname "$1") || {
        record_error "could not inspect target parent: $1"
        return
    }

    while :; do
        if [ -L "$TARGET_PARENT" ]; then
            record_error "target ancestor is a symlink: $TARGET_PARENT"
            return
        fi

        if [ -e "$TARGET_PARENT" ] && [ ! -d "$TARGET_PARENT" ]; then
            record_error "target ancestor is not a directory: $TARGET_PARENT"
            return
        fi

        if [ "$TARGET_PARENT" = "$HOME_DIR" ]; then
            return
        fi

        NEXT_PARENT=$(dirname "$TARGET_PARENT") || {
            record_error "could not inspect target parent: $TARGET_PARENT"
            return
        }
        if [ "$NEXT_PARENT" = "$TARGET_PARENT" ]; then
            record_error "target escapes home directory: $1"
            return
        fi
        TARGET_PARENT=$NEXT_PARENT
    done
}

validate_backup_destination_ancestors() {
    BACKUP_PARENT=$(dirname "$1") || {
        record_error "could not inspect backup parent: $1"
        return 1
    }

    while [ "$BACKUP_PARENT" != "$BACKUP_DIR" ]; do
        if [ -L "$BACKUP_PARENT" ]; then
            record_error "backup ancestor is a symlink: $BACKUP_PARENT"
            return 1
        fi

        if [ -e "$BACKUP_PARENT" ] && [ ! -d "$BACKUP_PARENT" ]; then
            record_error "backup ancestor is not a directory: $BACKUP_PARENT"
            return 1
        fi

        NEXT_BACKUP_PARENT=$(dirname "$BACKUP_PARENT") || {
            record_error "could not inspect backup parent: $BACKUP_PARENT"
            return 1
        }
        if [ "$NEXT_BACKUP_PARENT" = "$BACKUP_PARENT" ]; then
            record_error "backup destination escapes backup directory: $1"
            return 1
        fi
        BACKUP_PARENT=$NEXT_BACKUP_PARENT
    done

    return 0
}

validate_backup_destination() {
    validate_backup_destination_ancestors "$1" || return 1

    if path_exists "$1"; then
        record_conflict "backup destination is occupied: $1"
        return 1
    fi

    return 0
}

seed_backup_matches() {
    [ -f "$2" ] && [ ! -L "$2" ] && cmp -s "$1" "$2"
}

validate_seed_backup_destination() {
    validate_backup_destination_ancestors "$2" || return 1

    if ! path_exists "$2"; then
        return 0
    fi

    if seed_backup_matches "$1" "$2"; then
        return 0
    fi

    record_conflict "backup destination is occupied: $2"
    return 1
}

is_exact_link() {
    [ -L "$1" ] || return 1
    LINK_VALUE=$(readlink "$1") || return 1
    [ "$LINK_VALUE" = "$2" ]
}

validate_selected_entries() {
    MANIFEST_LINE_NUMBER=0

    while IFS= read -r MANIFEST_RAW || [ -n "$MANIFEST_RAW" ]; do
        MANIFEST_LINE_NUMBER=$((MANIFEST_LINE_NUMBER + 1))
        parse_manifest_line "$MANIFEST_RAW" "$MANIFEST_LINE_NUMBER" || continue

        if ! is_selected "$MANIFEST_PATH"; then
            continue
        fi

        SOURCE=$REPO_ROOT/$MANIFEST_PATH
        TARGET=$HOME_DIR/$MANIFEST_PATH

        if [ ! -e "$SOURCE" ]; then
            record_error "manifest source does not exist: $SOURCE"
            continue
        fi

        case $MANIFEST_MODE in
            link)
                if [ ! -f "$SOURCE" ] && [ ! -d "$SOURCE" ]; then
                    record_error "link source must be a regular file or directory: $SOURCE"
                fi
                ;;
            seed)
                if [ ! -f "$SOURCE" ] || [ -L "$SOURCE" ]; then
                    record_error "seed source must be a regular file: $SOURCE"
                fi
                ;;
        esac

        validate_target_ancestors "$TARGET"

        case $MANIFEST_MODE in
            link)
                if is_exact_link "$TARGET" "$SOURCE"; then
                    continue
                fi

                if path_exists "$TARGET"; then
                    if [ "$BACKUP_SET" -eq 0 ]; then
                        record_conflict "link target already exists: $TARGET"
                    else
                        validate_backup_destination "$BACKUP_DIR/$MANIFEST_PATH"
                    fi
                fi
                ;;
            seed)
                if [ -L "$TARGET" ]; then
                    record_conflict "seed target must not be a symlink: $TARGET"
                elif [ -e "$TARGET" ]; then
                    if [ ! -f "$TARGET" ]; then
                        record_conflict "seed target must be a regular file: $TARGET"
                    elif [ "$BACKUP_SET" -eq 1 ]; then
                        validate_seed_backup_destination "$TARGET" "$BACKUP_DIR/$MANIFEST_PATH"
                    fi
                fi
                ;;
        esac
    done < "$MANIFEST"
}

make_parent_dir() {
    PARENT_DIR=$(dirname "$1") || return 1
    mkdir -p "$PARENT_DIR"
}

apply_error() {
    printf 'ERROR %s\n' "$*" >&2
    return 1
}

restore_backed_up_target() {
    if path_exists "$2"; then
        return 1
    fi

    mv "$1" "$2"
}

apply_selected_entries() {
    MANIFEST_LINE_NUMBER=0

    while IFS= read -r MANIFEST_RAW || [ -n "$MANIFEST_RAW" ]; do
        MANIFEST_LINE_NUMBER=$((MANIFEST_LINE_NUMBER + 1))
        parse_manifest_line "$MANIFEST_RAW" "$MANIFEST_LINE_NUMBER" || return 1

        if ! is_selected "$MANIFEST_PATH"; then
            printf 'SKIP %s\n' "$MANIFEST_PATH"
            continue
        fi

        SOURCE=$REPO_ROOT/$MANIFEST_PATH
        TARGET=$HOME_DIR/$MANIFEST_PATH

        case $MANIFEST_MODE in
            link)
                if is_exact_link "$TARGET" "$SOURCE"; then
                    printf 'OK %s\n' "$TARGET"
                elif path_exists "$TARGET"; then
                    if [ "$BACKUP_SET" -ne 1 ]; then
                        apply_error "link target appeared without backup mode: $TARGET"
                        return 1
                    fi
                    BACKUP_TARGET=$BACKUP_DIR/$MANIFEST_PATH
                    if ! validate_backup_dir || ! validate_backup_destination "$BACKUP_TARGET"; then
                        apply_error "backup destination is no longer safe: $BACKUP_TARGET"
                        return 1
                    fi
                    if [ "$DRY_RUN" -eq 1 ]; then
                        printf 'BACKUP %s -> %s\n' "$TARGET" "$BACKUP_TARGET"
                        printf 'LINK %s -> %s\n' "$SOURCE" "$TARGET"
                    else
                        if ! make_parent_dir "$BACKUP_TARGET"; then
                            apply_error "could not create backup parent for: $BACKUP_TARGET"
                            return 1
                        fi
                        if ! mv "$TARGET" "$BACKUP_TARGET"; then
                            apply_error "could not back up: $TARGET"
                            return 1
                        fi
                        printf 'BACKUP %s -> %s\n' "$TARGET" "$BACKUP_TARGET"
                        if ! make_parent_dir "$TARGET" || ! ln -s "$SOURCE" "$TARGET"; then
                            if restore_backed_up_target "$BACKUP_TARGET" "$TARGET"; then
                                apply_error "could not link; restored target: $TARGET"
                            else
                                apply_error "could not link or restore target: $TARGET"
                            fi
                            return 1
                        fi
                        printf 'LINK %s -> %s\n' "$SOURCE" "$TARGET"
                    fi
                elif [ "$DRY_RUN" -eq 1 ]; then
                    printf 'LINK %s -> %s\n' "$SOURCE" "$TARGET"
                else
                    if ! make_parent_dir "$TARGET" || ! ln -s "$SOURCE" "$TARGET"; then
                        apply_error "could not link: $TARGET"
                        return 1
                    fi
                    printf 'LINK %s -> %s\n' "$SOURCE" "$TARGET"
                fi
                ;;
            seed)
                if [ -L "$TARGET" ]; then
                    apply_error "seed target must not be a symlink: $TARGET"
                    return 1
                elif [ -e "$TARGET" ]; then
                    if [ ! -f "$TARGET" ]; then
                        apply_error "seed target must be a regular file: $TARGET"
                        return 1
                    fi
                    if [ "$BACKUP_SET" -eq 1 ]; then
                        BACKUP_TARGET=$BACKUP_DIR/$MANIFEST_PATH
                        if ! validate_backup_dir || ! validate_seed_backup_destination "$TARGET" "$BACKUP_TARGET"; then
                            apply_error "backup destination is no longer safe: $BACKUP_TARGET"
                            return 1
                        fi
                        if [ "$DRY_RUN" -eq 1 ]; then
                            printf 'BACKUP %s -> %s\n' "$TARGET" "$BACKUP_TARGET"
                        elif seed_backup_matches "$TARGET" "$BACKUP_TARGET"; then
                            printf 'OK %s\n' "$BACKUP_TARGET"
                        else
                            if ! make_parent_dir "$BACKUP_TARGET" || ! cp "$TARGET" "$BACKUP_TARGET"; then
                                apply_error "could not back up seed: $TARGET"
                                return 1
                            fi
                            printf 'BACKUP %s -> %s\n' "$TARGET" "$BACKUP_TARGET"
                        fi
                    fi
                    printf 'PRESERVE %s\n' "$TARGET"
                elif [ "$DRY_RUN" -eq 1 ]; then
                    printf 'SEED %s -> %s\n' "$SOURCE" "$TARGET"
                else
                    if ! make_parent_dir "$TARGET" || ! cp "$SOURCE" "$TARGET"; then
                        apply_error "could not seed: $TARGET"
                        return 1
                    fi
                    printf 'SEED %s -> %s\n' "$SOURCE" "$TARGET"
                fi
                ;;
        esac
    done < "$MANIFEST"
}

validate_skills() {
    SKILLS_SOURCE_DIR=$REPO_ROOT/skills

    if [ ! -d "$SKILLS_SOURCE_DIR" ]; then
        return
    fi

    for SKILL_SOURCE in "$SKILLS_SOURCE_DIR"/*; do
        [ -d "$SKILL_SOURCE" ] || continue

        SKILL_NAME=${SKILL_SOURCE##*/}
        SKILL_TARGET=$HOME_DIR/.agents/skills/$SKILL_NAME

        if [ ! -f "$SKILL_SOURCE/SKILL.md" ]; then
            record_error "skill is missing SKILL.md: $SKILL_SOURCE"
            continue
        fi

        validate_target_ancestors "$SKILL_TARGET"

        if ! is_exact_link "$SKILL_TARGET" "$SKILL_SOURCE" && path_exists "$SKILL_TARGET"; then
            record_conflict "skill target already exists: $SKILL_TARGET"
        fi
    done
}

apply_skills() {
    SKILLS_SOURCE_DIR=$REPO_ROOT/skills

    if [ ! -d "$SKILLS_SOURCE_DIR" ]; then
        return
    fi

    for SKILL_SOURCE in "$SKILLS_SOURCE_DIR"/*; do
        [ -d "$SKILL_SOURCE" ] || continue

        SKILL_NAME=${SKILL_SOURCE##*/}
        SKILL_TARGET=$HOME_DIR/.agents/skills/$SKILL_NAME

        if is_exact_link "$SKILL_TARGET" "$SKILL_SOURCE"; then
            printf 'OK %s\n' "$SKILL_TARGET"
        elif [ "$DRY_RUN" -eq 1 ]; then
            printf 'LINK %s -> %s\n' "$SKILL_SOURCE" "$SKILL_TARGET"
        else
            if ! make_parent_dir "$SKILL_TARGET" || ! ln -s "$SKILL_SOURCE" "$SKILL_TARGET"; then
                apply_error "could not link skill: $SKILL_TARGET"
                return 1
            fi
            printf 'LINK %s -> %s\n' "$SKILL_SOURCE" "$SKILL_TARGET"
        fi
    done
}

remove_stale_skills() {
    SKILLS_TARGET_DIR=$HOME_DIR/.agents/skills

    if [ ! -d "$SKILLS_TARGET_DIR" ]; then
        return
    fi

    for SKILL_TARGET in "$SKILLS_TARGET_DIR"/*; do
        [ -L "$SKILL_TARGET" ] || continue

        SKILL_LINK=$(readlink "$SKILL_TARGET") || continue
        case $SKILL_LINK in
            "$REPO_ROOT"/skills/*)
                SKILL_RELATIVE=${SKILL_LINK#"$REPO_ROOT"/skills/}
                case $SKILL_RELATIVE in
                    */*)
                        continue
                        ;;
                esac

                if [ ! -e "$SKILL_LINK" ]; then
                    if [ "$DRY_RUN" -eq 1 ]; then
                        printf 'UNLINK %s\n' "$SKILL_TARGET"
                    elif ! rm -- "$SKILL_TARGET"; then
                        apply_error "could not unlink stale skill: $SKILL_TARGET"
                        return 1
                    else
                        printf 'UNLINK %s\n' "$SKILL_TARGET"
                    fi
                fi
                ;;
        esac
    done
}

while [ "$#" -gt 0 ]; do
    case $1 in
        --dry-run)
            DRY_RUN=1
            ;;
        --ai-only)
            AI_ONLY=1
            ;;
        --backup-dir)
            if [ "$#" -lt 2 ]; then
                fail '--backup-dir requires an absolute path'
            fi
            if [ "$BACKUP_SET" -eq 1 ]; then
                fail '--backup-dir may only be provided once'
            fi
            BACKUP_DIR=$2
            BACKUP_SET=1
            shift 2
            continue
            ;;
        --backup-dir=*)
            if [ "$BACKUP_SET" -eq 1 ]; then
                fail '--backup-dir may only be provided once'
            fi
            BACKUP_DIR=${1#--backup-dir=}
            BACKUP_SET=1
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "unknown option: $1"
            ;;
    esac
    shift
done

if [ ! -f "$MANIFEST" ] || [ ! -r "$MANIFEST" ]; then
    fail "manifest is not readable: $MANIFEST"
fi

if [ -z "${HOME:-}" ]; then
    fail 'HOME must be set'
fi

case $HOME in
    /*)
        ;;
    *)
        fail 'HOME must be an absolute path'
        ;;
esac

HOME_DIR=${HOME%/}
if [ -z "$HOME_DIR" ]; then
    HOME_DIR=/
fi

if [ "$HOME_DIR" = / ]; then
    fail 'HOME must not be the filesystem root'
fi

if [ ! -d "$HOME_DIR" ] || [ -L "$HOME_DIR" ]; then
    fail "HOME must be an existing real directory: $HOME_DIR"
fi

HOME_PHYSICAL=$(CDPATH= cd "$HOME_DIR" && pwd -P) || fail "could not resolve HOME: $HOME_DIR"

case $HOME_PHYSICAL in
    "$REPO_PHYSICAL"|"$REPO_PHYSICAL"/*)
        fail "HOME must not be inside the repository: $HOME_DIR"
        ;;
esac

validate_manifest_syntax
if [ "$PREFLIGHT_FAILED" -eq 0 ]; then
    validate_manifest_duplicates
fi
if [ "$PREFLIGHT_FAILED" -eq 0 ] && [ "$BACKUP_SET" -eq 1 ]; then
    validate_backup_dir
fi
if [ "$PREFLIGHT_FAILED" -eq 0 ]; then
    validate_selected_entries
fi
if [ "$PREFLIGHT_FAILED" -eq 0 ]; then
    validate_skills
fi
if [ "$PREFLIGHT_FAILED" -ne 0 ]; then
    exit 1
fi

apply_selected_entries || exit 1
apply_skills || exit 1
remove_stale_skills
