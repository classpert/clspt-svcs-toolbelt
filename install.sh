#!/usr/bin/env bash
set -u

abort() {
  printf "%s\n" "$@"
  exit 1
}

if [ -z "${BASH_VERSION:-}" ]; then
  abort "Bash is required to interpret this script."
fi

if ! [ -x "$(command -v git)" ]; then
  abort "Git is required to run this installer."
fi

# Check if script is run non-interactively (e.g. CI)
# If it is run non-interactively we should not prompt for passwords.
if [[ ! -t 0 || -n "${CI-}" ]]; then
  NONINTERACTIVE=1
fi

CLSPT_SVCS_TOOLBELT_GIT_REMOTE="https://raw.githubusercontent.com/classpert/clspt-svcs-toolbelt/HEAD/clspt-svcs"

# string formatters
if [[ -t 1 ]]; then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_underline="$(tty_escape "4;39")"
tty_blue="$(tty_mkbold 34)"
tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"

shell_join() {
  local arg
  printf "%s" "$1"
  shift
  for arg in "$@"; do
    printf " "
    printf "%s" "${arg// /\ }"
  done
}

chomp() {
  printf "%s" "${1/"$'\n'"/}"
}

ohai() {
  printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

warn() {
  printf "${tty_red}Warning${tty_reset}: %s\n" "$(chomp "$1")"
}

execute() {
  if ! "$@"; then
    abort "$(printf "Failed during: %s" "$(shell_join "$@")")"
  fi
}

# temporary directory to clone project into
ohai "Fetching clspt-svcs"
tmpdir=$(dirname $(mktemp -d))
curl $CLSPT_SVCS_TOOLBELT_GIT_REMOTE > $tmpdir/clspt-svcs
chown $(id -un):$(id -gn) $tmpdir/clspt-svcs
chmod +x $tmpdir/clspt-svcs

case "$SHELL" in
  */bash*)
    if [[ -r "$HOME/.bash_profile" ]]; then
      shell_profile="$HOME/.bashrc"
    else
      shell_profile="$HOME/.profile"
    fi
    ;;
  */zsh*)
    shell_profile="$HOME/.zprofile"
    ;;
  *)
    shell_profile="$HOME/.profile"
    ;;
esac

ohai "Installing clspt-svcs"
mkdir -p $HOME/.local/bin
mv $tmpdir/clspt-svcs $HOME/.local/bin
case ":$PATH:" in
  *:$HOME/.local/bin:*)
    ;;
  *)
    echo 'export PATH=$PATH:$HOME/.local/bin' >> $shell_profile ;
    export PATH=$PATH:$HOME/.local/bin ;
    ;;
esac
ohai "Done."