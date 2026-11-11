# shellcheck extended-analysis=false
# -------------------------------------------------------------- packages
# sets: DISTRO FAMILIES FAMILIES_SAID PM
# reads: OS REPO
PM=
DISTRO=
pm_detect() {
    # SPARK_OS_RELEASE pins the family (tests), even on macOS
    if [ "$OS" = Darwin ] && [ -z "${SPARK_OS_RELEASE:-}" ]; then PM=brew; return; fi
    _f=${SPARK_OS_RELEASE:-/etc/os-release}
    for w in $(sed -n 's/^ID=//p; s/^ID_LIKE=//p' "$_f" 2>/dev/null | tr -d '"'); do
        case " $FAMILIES " in *" $w "*) DISTRO=$w; break ;; esac
    done
    [ -z "$DISTRO" ] || load_env "$REPO/distro/$DISTRO.env" env || exit 1
    : "${PM:=}" "${PKG_SHELL:=}" "${PKG_CLI:=}" "${PKG_CONSOLE:=}" "${PKG_DESKTOP:=}" "${PKG_SOUND:=}" "${PKG_LOGIN:=}" "${LOGIN_ACCOUNT:=}"
}
# the families, one distro/NAME.env each: ID first, then each ID_LIKE
# word; FAMILIES_SAID is what a todo row says of a Linux none match
FAMILIES='debian arch void fedora opensuse'
FAMILIES_SAID='Debian, Ubuntu, Arch, Void, Fedora and openSUSE'
pkg_listed() { case " $PKG_SHELL $PKG_CLI $PKG_CONSOLE $PKG_DESKTOP $PKG_SOUND $PKG_LOGIN " in *" $1 "*) return 0 ;; esac; return 1; }   # pkg_listed NAME -- the family's lists name the package (after pm_detect)
starship_listed() { [ "$PM" = brew ] || pkg_listed starship; }   # the prompt comes with the packages: brew always, a family's list may
pkg_update_said() {   # -> the family's own step when an install is refused: a rolling distro wants the whole upgrade first
    case $PM in
        xbps) echo 'sudo xbps-install -Su' ;;   # not pacman: its install is that upgrade already
        dnf) echo 'sudo dnf upgrade --refresh' ;; zypper) echo 'sudo zypper dup' ;;
    esac
}
tool_here() {   # tool_here NAME -- on PATH or in ~/.local/bin; under apt by Debian's name (fdfind, batcat), after pm_detect
    _n=$1
    if [ "$PM" = apt ]; then case $1 in fd) _n=fdfind ;; bat) _n=batcat ;; esac; fi
    command -v "$_n" >/dev/null 2>&1 || [ -x "$HOME/.local/bin/$_n" ]
}
pkg_installed() {   # pkg_installed NAME -- the manager's own database; rpm counts a provider (python3 is python313's capability on Tumbleweed)
    case $PM in
        apt) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
        pacman) pacman -Qq "$1" >/dev/null 2>&1 ;;
        xbps) xbps-query "$1" >/dev/null 2>&1 ;;
        dnf|zypper) rpm -q --whatprovides "$1" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}
pkg_install() {   # pkg_install NAME... -- as root, the manager's own way
    case $PM in
        apt) as_root apt-get update -qq && as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" ;;
        pacman) as_root pacman -S --needed --noconfirm "$@" ;;      # never -Sy alone: a rolling distro forbids the partial upgrade
        xbps) as_root xbps-install -Sy "$@" ;;                     # -S syncs the index; a stale xbps refuses (the todo names the upgrade)
        dnf) as_root dnf install -y "$@" ;;                        # dnf refreshes its own index when it is old
        zypper) as_root zypper --non-interactive install "$@" ;;   # the same: zypper refreshes first
        *) return 1 ;;
    esac
}
pkg_nobody() {   # -> true when no one here can answer: no terminal, and sudo wants its password or pacman asks before its upgrade
    [ ! -t 0 ] || return 1
    if [ "$PM" = pacman ] && [ -z "${SPARK_SHELL_TEST_TTY:-}" ]; then return 0; fi
    [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null
}
pkg_install_on() {
    # pacman refreshes with the full upgrade and asks before applying it
    if [ "$PM" = pacman ]; then as_root pacman -Syu --needed "$@"
    else pkg_install "$@"; fi
}

