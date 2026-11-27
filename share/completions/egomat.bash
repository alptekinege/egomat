# bash completion for egomat
#
# install.sh installs this into bash-completion's completions directory
# (${XDG_DATA_HOME:-~/.local/share}/bash-completion/completions/egomat or
# /usr/share/bash-completion/completions/egomat). For a manual install,
# source it from ~/.bashrc:
#
#   source /path/to/egomat/share/completions/egomat.bash

_egomat_complete() {
  local cur prev cmd cmd_i word i want f
  local commands="convert optimize resize info formats assistant menu install uninstall version help completion"
  local formats="png jpg jpeg webp avif gif bmp tiff tif ico pdf"
  local levels="light lossless fast balanced normal default mid aggressive max maximum strong heavy"
  local conflicts="rename skip overwrite ask"
  local opts
  local -a pos=()
  COMPREPLY=()
  cur=${COMP_WORDS[COMP_CWORD]}
  prev=${COMP_WORDS[COMP_CWORD-1]}

  # The command is the first word that is not a global option. The help
  # flag before the command means "help" ("egomat --help convert").
  cmd=""
  cmd_i=0
  for ((i = 1; i < COMP_CWORD; i++)); do
    word=${COMP_WORDS[i]}
    case $word in
      --quiet|--verbose|--no-ui|--ui|--ui=*) ;;
      -h|--help) cmd=help; cmd_i=$i; break ;;
      *)         cmd=$word; cmd_i=$i; break ;;
    esac
  done

  # The previous word is an option that expects a value: complete that.
  case $prev in
    -f|--format)
      COMPREPLY=( $(compgen -W "$formats" -- "$cur") )
      return 0 ;;
    -l|--level)
      COMPREPLY=( $(compgen -W "$levels" -- "$cur") )
      return 0 ;;
    --on-conflict)
      COMPREPLY=( $(compgen -W "$conflicts" -- "$cur") )
      return 0 ;;
    -o|--outdir|--output-dir|--prefix)
      COMPREPLY=( $(compgen -d -- "$cur") )
      return 0 ;;
    -q|--quality|-r|--resize|--size|-s|--suffix)
      return 0 ;;
  esac

  # Positional words already typed after the command. Options and their
  # values do not count; "--" ends option parsing.
  want=0
  for ((i = cmd_i + 1; i < COMP_CWORD; i++)); do
    word=${COMP_WORDS[i]}
    if [ "$want" -eq 1 ]; then want=0; continue; fi
    case $word in
      --) break ;;
      --*=*) ;;
      -f|--format|-q|--quality|-r|--resize|--size|-o|--outdir|--output-dir|-s|--suffix|-l|--level|--on-conflict|--prefix)
        want=1 ;;
      -*) ;;
      *) pos+=("$word") ;;
    esac
  done

  if [[ $cur == -* ]]; then
    case $cmd in
      "")
        opts="-h --help --quiet --verbose --no-ui --ui" ;;
      convert)
        opts="-f --format -q --quality -r --resize --size -o --outdir --output-dir -s --suffix --on-conflict --overwrite --keep-metadata --delete-source --dry-run --quiet --verbose -h --help" ;;
      optimize)
        opts="-l --level -o --outdir --output-dir -s --suffix --on-conflict --backup --force --dry-run --quiet --verbose -h --help" ;;
      resize)
        opts="-o --outdir --output-dir -s --suffix --on-conflict --overwrite --dry-run --quiet --verbose -h --help" ;;
      install)
        opts="--user --system --prefix --no-kde --no-freedesktop --no-app --gui --no-gui -n --dry-run -h --help" ;;
      uninstall)
        opts="--user --system --prefix -n --dry-run -h --help" ;;
      *)
        opts="-h --help" ;;
    esac
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    return 0
  fi

  # Non-option words: commands, option values, then files.
  case $cmd in
    "")
      COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
      return 0 ;;
    help)
      [ ${#pos[@]} -eq 0 ] && COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
      return 0 ;;
    completion)
      [ ${#pos[@]} -eq 0 ] && COMPREPLY=( $(compgen -W "bash zsh fish" -- "$cur") )
      return 0 ;;
    menu)
      if [ ${#pos[@]} -eq 0 ]; then
        COMPREPLY=( $(compgen -W "convert optimize resize info" -- "$cur") )
      elif [ ${#pos[@]} -eq 1 ]; then
        case ${pos[0]} in
          convert)  COMPREPLY=( $(compgen -W "$formats custom" -- "$cur") ) ;;
          optimize) COMPREPLY=( $(compgen -W "$levels ask" -- "$cur") ) ;;
          resize)   COMPREPLY=( $(compgen -W "ask" -- "$cur") ) ;;
        esac
      fi
      [ ${#pos[@]} -lt 2 ] && return 0 ;;
    resize)
      # The first positional word is the geometry; files follow it.
      [ ${#pos[@]} -lt 1 ] && return 0 ;;
    formats|version|install|uninstall)
      return 0 ;;
  esac

  while IFS= read -r f; do
    [ -d "$f" ] && f="$f/"
    COMPREPLY+=("$f")
  done < <(compgen -f -- "$cur")
  return 0
}

complete -F _egomat_complete egomat
