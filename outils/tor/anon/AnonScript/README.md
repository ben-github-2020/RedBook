# AnonScript

Bash script that allow you to redirect all the traffics through Tor network for anonymization

# Features

1. Start a transparent proxy through tor
2. Reset iptables and return to clearnet navigation
3. Change mac address on all interfaces
5. Remove some logs and bash history / And change hostname

## Install

As sudo go to /usr/share and clone the git repo:
```
cd /usr/share
git clone https://github.com/v4resk/AnonScript
```

## Usage

1. Start tor transparent proxy :
```
sudo ./AnonScript.sh --tor
```

2. Reset iptables and return to clearnet navigation
```
sudo ./AnonScript.sh --clearnet
```

3. Change mac address on all interfaces
```
sudo ./AnonScript.sh --mac
```

4. Remove some logs and bash history + change hostname
```
sudo ./AnonScript.sh --logs
```

5. Do all (--tor --mac --logs)
```
sudo ./AnonScript.sh --all
```
