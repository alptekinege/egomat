# fish completion for egomat
#
# install.sh installs this into fish's vendor_completions.d directory
# (${XDG_DATA_HOME:-~/.local/share}/fish/vendor_completions.d or
# /usr/share/fish/vendor_completions.d). For a manual install, copy it to
# ~/.config/fish/completions/egomat.fish

# Positional words typed after the subcommand, one per line. Options and
# their values do not count; "--" ends option parsing.
function __egomat_positionals
    set -l tokens (commandline -opc)
    set -l seen 0
    set -l skip 0
    for t in $tokens
        if test $skip -eq 1
            set skip 0
            continue
        end
        if test $seen -eq 0
            switch $t
                case convert optimize resize info formats assistant gui menu install uninstall version help completion
                    set seen 1
            end
            continue
        end
        switch $t
            case '--'
                break
            case '--*'
                continue
            case '-f' '--format' '-q' '--quality' '-r' '--resize' '--size' '-o' '--outdir' '--output-dir' '-s' '--suffix' '-l' '--level' '--prefix'
                set skip 1
            case '-*'
                continue
            case '*'
                echo $t
        end
    end
end

# No file completion by default; it is re-enabled per command below.
complete -c egomat -f

# Global options. --quiet/--verbose also work after convert, optimize and
# resize; --no-ui/--ui belong before the command only.
complete -c egomat -n '__fish_use_subcommand; or __fish_seen_subcommand_from convert optimize resize' -l quiet -d 'print only errors'
complete -c egomat -n '__fish_use_subcommand; or __fish_seen_subcommand_from convert optimize resize' -l verbose -d 'print backend decisions and errors'
complete -c egomat -n __fish_use_subcommand -l no-ui -d 'never open dialogs'
complete -c egomat -n __fish_use_subcommand -l ui -d 'open dialogs when available'
complete -c egomat -s h -l help -d 'show help and exit'

# Commands.
complete -c egomat -n __fish_use_subcommand -a convert -d 'convert images to a different format'
complete -c egomat -n __fish_use_subcommand -a optimize -d 'shrink images in place or into new files'
complete -c egomat -n __fish_use_subcommand -a resize -d 'resize images into new files'
complete -c egomat -n __fish_use_subcommand -a info -d 'show image information'
complete -c egomat -n __fish_use_subcommand -a formats -d 'list installed image tools and target formats'
complete -c egomat -n __fish_use_subcommand -a assistant -d 'interactive wizard for file-manager use'
complete -c egomat -n __fish_use_subcommand -a menu -d 'entry point used by the desktop actions'
complete -c egomat -n __fish_use_subcommand -a install -d 'install the command and desktop actions'
complete -c egomat -n __fish_use_subcommand -a uninstall -d 'remove an install recorded by install.sh'
complete -c egomat -n __fish_use_subcommand -a completion -d 'print shell completion for Bash, Zsh, or Fish'
complete -c egomat -n __fish_use_subcommand -a version -d 'print the Egomat version'
complete -c egomat -n __fish_use_subcommand -a help -d 'show help for Egomat or for one command'

# Option values.
complete -c egomat -n '__fish_seen_subcommand_from convert' -s f -l format -x -a 'png jpg jpeg webp avif gif bmp tiff tif ico pdf' -d 'target format'
complete -c egomat -n '__fish_seen_subcommand_from optimize' -s l -l level -x -a 'light lossless fast balanced normal default mid aggressive max maximum strong heavy' -d 'optimization level'
complete -c egomat -n '__fish_seen_subcommand_from convert optimize resize' -s o -l outdir -l output-dir -r -f -a '(__fish_complete_directories)' -d 'output directory'
complete -c egomat -n '__fish_seen_subcommand_from install uninstall' -l prefix -r -f -a '(__fish_complete_directories)' -d 'install under DIR'

# Per-command options.
complete -c egomat -n '__fish_seen_subcommand_from convert' -s q -l quality -x -d 'quality 1-100 for lossy formats'
complete -c egomat -n '__fish_seen_subcommand_from convert' -s r -l resize -l size -x -d 'resize geometry, e.g. 1920x1080'
complete -c egomat -n '__fish_seen_subcommand_from convert' -s s -l suffix -x -d 'add SUFFIX to the new file name'
complete -c egomat -n '__fish_seen_subcommand_from convert' -l overwrite -d 'replace an existing output file'
complete -c egomat -n '__fish_seen_subcommand_from convert' -l keep-metadata -d 'do not strip EXIF/ICC data'
complete -c egomat -n '__fish_seen_subcommand_from convert' -l delete-source -d 'remove the source after conversion'
complete -c egomat -n '__fish_seen_subcommand_from optimize' -s s -l suffix -x -d 'write to a new name instead of in place'
complete -c egomat -n '__fish_seen_subcommand_from optimize' -l backup -d 'keep a copy of the original before writing'
complete -c egomat -n '__fish_seen_subcommand_from optimize' -l force -d 'replace even when the candidate is not smaller'
complete -c egomat -n '__fish_seen_subcommand_from resize' -s s -l suffix -x -d 'file-name suffix (default: -resized)'
complete -c egomat -n '__fish_seen_subcommand_from resize' -l overwrite -d 'replace an existing output file'
complete -c egomat -n '__fish_seen_subcommand_from install uninstall' -l user -d 'install for the current user (default)'
complete -c egomat -n '__fish_seen_subcommand_from install uninstall' -l system -d 'install into /usr/local'
complete -c egomat -n '__fish_seen_subcommand_from install' -l no-kde -d 'skip the KDE/Dolphin service menu'
complete -c egomat -n '__fish_seen_subcommand_from install' -l no-freedesktop -d 'skip the file-manager actions'
complete -c egomat -n '__fish_seen_subcommand_from install' -l no-app -d 'skip the application-menu entry'
complete -c egomat -n '__fish_seen_subcommand_from install' -l gui -d 'also build and install egomat-gui'
complete -c egomat -n '__fish_seen_subcommand_from install' -l no-gui -d 'do not build egomat-gui (default)'
complete -c egomat -n '__fish_seen_subcommand_from install uninstall' -s n -l dry-run -d 'print what would be done, change nothing'

# Positional words.
complete -c egomat -n '__fish_seen_subcommand_from help; and test (__egomat_positionals | count) -eq 0' -a 'convert optimize resize info formats assistant menu install uninstall version help completion' -d 'command'
complete -c egomat -n '__fish_seen_subcommand_from completion; and test (__egomat_positionals | count) -eq 0' -a 'bash zsh fish' -d 'shell'
complete -c egomat -n '__fish_seen_subcommand_from menu; and test (__egomat_positionals | count) -eq 0' -a 'convert optimize resize info' -d 'action'
complete -c egomat -n '__fish_seen_subcommand_from menu; and test (__egomat_positionals | count) -eq 1; and __egomat_positionals | string match -q convert' -a 'png jpg jpeg webp avif gif bmp tiff tif ico pdf custom'
complete -c egomat -n '__fish_seen_subcommand_from menu; and test (__egomat_positionals | count) -eq 1; and __egomat_positionals | string match -q optimize' -a 'light lossless fast balanced normal default mid aggressive max maximum strong heavy ask'

# File arguments. resize takes a geometry first; menu takes ACTION [PARAM].
complete -c egomat -n '__fish_seen_subcommand_from convert optimize info assistant' -F
complete -c egomat -n '__fish_seen_subcommand_from resize; and test (__egomat_positionals | count) -ge 1' -F
complete -c egomat -n '__fish_seen_subcommand_from menu; and test (__egomat_positionals | count) -ge 2' -F
