#!/bin/bash

#define uid that tor run as
readonly tor_uid="$(id -u debian-tor)"
# Tor TransPort
readonly trans_port="9040"
# Tor DNSPort
readonly dns_port="5353"
# Tor VirtualAddrNetworkIPv4
readonly virtual_address="10.192.0.0/10"
# LAN destinations that shouldn't be routed through Tor
readonly non_tor="127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"
redbookpath=$(find / -not -path '*/.*' -type d -name 'RedBook' 2>/dev/null)
readonly config_dir="$redbookpath/outils/tor/anon/AnonScript/conf"
readonly backup_dir="$redbookpath/outils/tor/anon/AnonScript/backup"

#CHECK FOR ROOT
if [[ "${UID}" -ne 0 ]]; then
       echo "Error: Must be run as root" 1>&2 ; exit 1;
    fi


check_settings() {

    # Check for tor
    if ! hash "tor" 2>/dev/null; then
        echo "'tor' isn't installed, exit" 1>&2; exit 1;
    fi

    # directories
    if [[ ! -d "${backup_dir}" ]]; then
        echo "directory '${backup_dir}' not exist" 1>&2; exit 1;
    fi

    if [[ ! -d "${config_dir}" ]]; then
        echo "directory '${config_dir}' not exist" 1>&2; exit 1;
    fi

    # replace torrc file
    if [[ ! -f /etc/tor/torrc ]]; then
        echo "/etc/tor/torrc file not exist, check Tor configuration" 1>&2; exit 1;
    fi

    printf "%s\\n" "Set /etc/tor/torrc"

    if ! cp -f /etc/tor/torrc "${backup_dir}/torrc.backup"; then
        echo "can't backup '/etc/tor/torrc'" 1>&2; exit 1;
    fi

    if ! cp -f "${config_dir}/torrc" /etc/tor/torrc; then
        echo "can't copy new '/etc/tor/torrc'" 1>&2; exit 1;
    fi

    # reload systemd daemons
    printf "%s\\n" "Reload systemd daemons"
    systemctl --system daemon-reload
}

#iptables config:
# conf_iptables tor -> rules for tor transparent proxy
# conf_iptables clear -> rules backup
conf_iptables(){
case "$1" in
        tor)
            printf "%s\\n" "Set iptables rules"

            ## Flush current iptables rules
            iptables -F
            iptables -X
            iptables -t nat -F
            iptables -t nat -X
            iptables -P INPUT ACCEPT
            iptables -P FORWARD ACCEPT
            iptables -P OUTPUT ACCEPT

            ## *nat OUTPUT (For local redirection)
            #
            # nat .onion addresses
            iptables -t nat -A OUTPUT -d $virtual_address -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j REDIRECT --to-ports $trans_port

            # nat dns requests to Tor
            iptables -t nat -A OUTPUT -d 127.0.0.1/32 -p udp -m udp --dport 53 -j REDIRECT --to-ports $dns_port

            # Don't nat the Tor process, the loopback, or the local network
            iptables -t nat -A OUTPUT -m owner --uid-owner $tor_uid -j RETURN
            iptables -t nat -A OUTPUT -o lo -j RETURN

            # Allow lan access for hosts in $non_tor
            for lan in $non_tor; do
                iptables -t nat -A OUTPUT -d $lan -j RETURN
            done

            # Redirects all other pre-routing and output to Tor's TransPort
            iptables -t nat -A OUTPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j REDIRECT --to-ports $trans_port

            ## *filter INPUT
            iptables -A INPUT -m state --state ESTABLISHED -j ACCEPT
            iptables -A INPUT -i lo -j ACCEPT

            # Drop everything else
            iptables -A INPUT -j DROP
            iptables -A FORWARD -j DROP

            # Fix for potential kernel transproxy packet leaks
            # see: https://lists.torproject.org/pipermail/tor-talk/2014-March/032507.html
            iptables -A OUTPUT -m conntrack --ctstate INVALID -j DROP

            iptables -A OUTPUT -m state --state INVALID -j DROP
            iptables -A OUTPUT -m state --state ESTABLISHED -j ACCEPT

            # Allow Tor process output
            iptables -A OUTPUT -m owner --uid-owner $tor_uid -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -m state --state NEW -j ACCEPT

            # Allow loopback output
            iptables -A OUTPUT -d 127.0.0.1/32 -o lo -j ACCEPT

            # Tor transproxy magic
            iptables -A OUTPUT -d 127.0.0.1/32 -p tcp -m tcp --dport $trans_port --tcp-flags FIN,SYN,RST,ACK SYN -j ACCEPT

            # Drop everything else
            iptables -A OUTPUT -j DROP

            ## Set default policies to DROP
            iptables -P INPUT DROP
            iptables -P FORWARD DROP
            iptables -P OUTPUT DROP
        ;;

        clear)
            printf "%s\\n" "Restore default iptables rules"

            # Flush iptables rules
            iptables -F
            iptables -X
            iptables -t nat -F
            iptables -t nat -X
            iptables -P INPUT ACCEPT
            iptables -P FORWARD ACCEPT
            iptables -P OUTPUT ACCEPT
        ;;
    esac
}

start() {
    echo "------------------------------------------"
    # Exit if tor.service is already active
    if systemctl is-active tor.service >/dev/null 2>&1; then
        echo "Tor service is already active, stop it first" 2>&1; exit 1;
    fi

    check_settings

    # DNS settings: /etc/resolv.conf:
    #
    # write nameserver 127.0.0.1 to `/etc/resolv.conf` file
    # i.e. use Tor DNSPort (see: /etc/tor/torrc)
    printf "%s\\n" "Configure resolv.conf file to use Tor DNSPort"

    # backup current resolv.conf
    if ! cp /etc/resolv.conf "${backup_dir}/resolv.conf.backup"; then
        echo "can't backup '/etc/resolv.conf'" 2>&1; exit 1;
    fi

    # write new nameserver
    printf "%s\\n" "nameserver 127.0.0.1" > /etc/resolv.conf

    # disable IPv6 with sysctl
    printf "%s\\n" "Disable IPv6 with sysctl"
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1

    # start tor.service
    printf "%s\\n" "Start Tor service"

    if ! systemctl start tor.service >/dev/null 2>&1; then
        echo "can't start tor service, exit!" 2>&1; exit 1;
    fi

    # set new iptables rules
    conf_iptables tor

    # check program status
    printf "\nYou are running under Tor !\n"
    echo "------------------------------------------"
}

stop() {

    # don't run function if tor.service is NOT running!
    if systemctl is-active tor.service >/dev/null 2>&1; then


        # resets default iptables rules
        conf_iptables clear

        printf "%s\\n" "Stop tor service"
        systemctl stop tor.service

        # restore /etc/resolv.conf:
        #
        # restore file with resolvconf program if exists
        # otherwise copy the original file from backup directory
        printf "%s\\n" "Restore default DNS"

        if hash resolvconf 2>/dev/null; then
            resolvconf -u
        else
            cp "${backup_dir}/resolv.conf.backup" /etc/resolv.conf
        fi

        # enable IPv6
        printf "%s\\n" "Enable IPv6"
        sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
        sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1

        # restore default `/etc/tor/torrc`
        printf "%s\\n" "Restore default /etc/tor/torrc"
        cp "${backup_dir}/torrc.backup" /etc/tor/torrc

        exit 0
    else
        echo "Tor service is not running! exit" 2>&1; exit 1;
    fi
}

secure_os_logs(){
    echo "------------------------------------------"
    echo "Removing bash logs"
    #Unset bash/zsh history
    unset HISTFILE; unset SAVEFILE
    rm ~/.bash_history
    ln -s /dev/null ~/.bash_history

    export HISTFILE=/dev/null
    export SAVEFILE=/dev/null

    #KaliLinux
    rm ~/.zsh_history
    ln -s /dev/null ~/.zsh_history

    hostname PC-Win
    echo "------------------------------------------"
}

update_mac_addr(){
    echo "------------------------------------------"
    printf "Macchanger on all interfaces\n"
    ifconfig -a | sed 's/[ \t].*//;/^$/d' | sed 's/:$//' > ${config_dir}/interfaces.txt
    readarray -t interfaces < ${config_dir}/interfaces.txt

    for i in ${!interfaces[*]}; do
        echo 'Change' ${interfaces[$i]} 'MAC addr:'
        ifconfig ${interfaces[$i]} down
        macchanger -r ${interfaces[$i]}
        ifconfig ${interfaces[$i]} up
    done
    echo "------------------------------------------"
}

usage() {
    printf "%s\\n\\n" "Options:"
    printf "%s\\n" "-h, --help      show this help message and exit"
    printf "%s\\n" "-t, --tor       start transparent proxy through tor"
    printf "%s\\n" "-c, --clearnet  reset iptables and return to clearnet navigation"
    printf "%s\\n" "-m, --mac  change mac address on all interfaces"
    printf "%s\\n" "-l, --logs  remove some logs and bash history"
    exit 0
}

main() {
    if [[ "$#" -eq 0 ]]; then
        printf "%s\\n" "${prog_name}: Argument required"
        printf "%s\\n" "Try '${prog_name} --help' for more information."
        exit 1
    fi

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -t | --tor)
                start
                ;;
            -c | --clearnet)
                stop
                ;;
            -m | --mac)
                update_mac_addr
                ;;
            -a | --all)
                update_mac_addr
                start
                secure_os_logs
                ;;
            -l | --logs)
                secure_os_logs
                    ;;
            -h | --help)
                usage
                exit 0
                ;;
            -- | -* | *)
                printf "%s\\n" "${prog_name}: Invalid option '$1'"
                printf "%s\\n" "Try '${prog_name} --help' for more information."
                exit 1
                ;;
        esac
        exit 0
    done
}

# Call main
main "${@}"
