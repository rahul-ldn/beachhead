# ~/.config/fish/conf.d/landingham-prompt.fish — installed by beachhead's prompt installer. Nothing here prints.
# Homebrew on a Mac, ~/.local/bin on every machine, the shared variables, then the prompt with its per-folder palette.
if test -x /opt/homebrew/bin/brew
    /opt/homebrew/bin/brew shellenv | source
end
fish_add_path --global --move ~/.local/bin
if test -r ~/.config/landingham-prompt/env
    for line in (string match -r '^[A-Za-z_][A-Za-z0-9_]*=.*' < ~/.config/landingham-prompt/env)
        set -l kv (string split -m1 = -- $line)
        set -gx $kv[1] (string trim -c '"' -- $kv[2])
    end
end
if status is-interactive; and command -q starship
    function __landingham_prompt_palette --on-variable PWD
        set -gx STARSHIP_CONFIG (landingham-prompt-palette)
    end
    __landingham_prompt_palette
    starship init fish | source
end

# `account a` or `account b`: the Claude account a `claude` typed in THIS shell uses (the prompt's pill follows at the
# next prompt). With --save the choice is kept in ~/.config/landingham-prompt/env, so every new shell after a re-login
# starts that way until the next --save. `account` alone says which. B's folder is CLAUDE_CONFIG_DIR_B, else ~/.claude-b.
function account --description 'the Claude account a `claude` typed here uses: account a|b [--save]'
    set -l env ~/.config/landingham-prompt/env
    set -l which $argv[1]; set -l save (contains -- --save $argv; and echo yes)
    switch "$which"
        case a A
            set -e CLAUDE_CONFIG_DIR; set -eg CLAUDE_CONFIG_DIR
            echo 'claude: A (the default folder)'
        case b B
            set -l dir (set -q CLAUDE_CONFIG_DIR_B; and echo $CLAUDE_CONFIG_DIR_B; or echo ~/.claude-b)
            test -d $dir; or begin; echo "account b: no folder at $dir on this machine" >&2; return 66; end
            set -gx CLAUDE_CONFIG_DIR $dir
            echo "claude: B ($dir)"
        case ''
            if set -q CLAUDE_CONFIG_DIR; echo "claude: B ($CLAUDE_CONFIG_DIR)"; else; echo 'claude: A (the default folder)'; end
            return 0
        case '*'
            echo 'usage: account a|b [--save]' >&2; return 64
    end
    if test -n "$save"; and test -w $env
        grep -v '^CLAUDE_CONFIG_DIR=' $env > $env.new
        if set -q CLAUDE_CONFIG_DIR; echo "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR" >> $env.new; end
        mv $env.new $env; and echo "  saved: new shells start on $which"
    end
end
complete -c account -f -a 'a b'
complete -c account -l save -d 'keep the choice for every new shell'
