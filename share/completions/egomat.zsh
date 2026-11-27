#compdef egomat
# zsh completion for egomat
#
# install.sh installs this as _egomat in zsh's site-functions directory
# (${XDG_DATA_HOME:-~/.local/share}/zsh/site-functions or
# /usr/local/share/zsh/site-functions). For a manual install, put the
# directory on your $fpath before running compinit, e.g. in ~/.zshrc:
#
#   fpath=(/path/to/egomat/share/completions $fpath)
#   autoload -Uz compinit && compinit

_egomat() {
  local cmd cmd_i word want i
  local -a commands formats levels pos opts

  commands=(
    'convert:convert images to a different format'
    'optimize:shrink images in place or into new files'
    'resize:resize images into new files'
    'info:show image information'
    'formats:list installed image tools and target formats'
    'assistant:interactive wizard for file-manager use'
    'menu:entry point used by the desktop actions'
    'install:install the command and desktop actions'
    'uninstall:remove an install recorded by install.sh'
    'completion:print shell completion for Bash, Zsh, or Fish'
    'version:print the Egomat version'
    'help:show help for Egomat or for one command'
  )
  formats=(png jpg jpeg webp avif gif bmp tiff tif ico pdf)
  levels=(light lossless fast balanced normal default mid aggressive max maximum strong heavy)

  # The command is the first word that is not a global option. The help
  # flag before the command means "help" ("egomat --help convert").
  for (( i = 2; i < CURRENT; i++ )); do
    word=${words[i]}
    case $word in
      --quiet|--verbose|--no-ui|--ui|--ui=*) ;;
      -h|--help) cmd=help; cmd_i=$i; break ;;
      *)         cmd=$word; cmd_i=$i; break ;;
    esac
  done

  # The previous word is an option that expects a value: complete that.
  case ${words[CURRENT-1]} in
    -f|--format) _values 'format' $formats; return ;;
    -l|--level)  _values 'level' $levels; return ;;
    -o|--outdir|--output-dir|--prefix) _files -/; return ;;
    -q|--quality|-r|--resize|--size|-s|--suffix) return ;;
  esac

  # Positional words already typed after the command. Options and their
  # values do not count; "--" ends option parsing.
  want=0
  for (( i = cmd_i + 1; i < CURRENT; i++ )); do
    word=${words[i]}
    if (( want )); then want=0; continue; fi
    case $word in
      --) break ;;
      --*=*) ;;
      -f|--format|-q|--quality|-r|--resize|--size|-o|--outdir|--output-dir|-s|--suffix|-l|--level|--prefix)
        want=1 ;;
      -*) ;;
      *) pos+=("$word") ;;
    esac
  done

  if [[ ${words[CURRENT]} == -* ]]; then
    case $cmd in
      "")      opts=(-h --help --quiet --verbose --no-ui --ui) ;;
      convert)
        opts=(-f --format -q --quality -r --resize --size -o --outdir
              --output-dir -s --suffix --overwrite --keep-metadata
              --delete-source --dry-run --quiet --verbose -h --help) ;;
      optimize)
        opts=(-l --level -o --outdir --output-dir -s --suffix --backup
              --force --dry-run --quiet --verbose -h --help) ;;
      resize)
        opts=(-o --outdir --output-dir -s --suffix --overwrite --dry-run
              --quiet --verbose -h --help) ;;
      install)
        opts=(--user --system --prefix --no-kde --no-freedesktop --no-app
              --gui --no-gui -n --dry-run -h --help) ;;
      uninstall)
        opts=(--user --system --prefix -n --dry-run -h --help) ;;
      *)       opts=(-h --help) ;;
    esac
    _describe 'option' opts
    return
  fi

  case $cmd in
    "")
      _describe -t commands 'egomat command' commands
      ;;
    help)
      (( ${#pos} )) || _describe -t commands 'egomat command' commands
      ;;
    completion)
      (( ${#pos} )) || _values 'shell' bash zsh fish
      ;;
    menu)
      if (( ! ${#pos} )); then
        _values 'action' convert optimize resize info
      elif (( ${#pos} == 1 )); then
        case ${pos[1]} in
          convert)  _values 'format' $formats custom ;;
          optimize) _values 'level' $levels ask ;;
          resize)   _values 'geometry' ask ;;
        esac
      else
        _files
      fi
      ;;
    resize)
      # The first positional word is the geometry; files follow it.
      (( ${#pos} )) && _files
      ;;
    formats|version|install|uninstall) ;;
    *)
      _files
      ;;
  esac
}

_egomat "$@"
