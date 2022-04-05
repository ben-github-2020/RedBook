#!/bin/bash








scan(){

echo "(1)Nmap classique"
echo "(2)Nmap avec OS"
echo "(3)Retour Menu"

read -p $"Choisisssez une option:" option

if [[ $option == 1 ]]
        then
		read -p $"quelle adresse IP ? :" IP
		nmap $IP
		sleep 5
		menu
elif [[ $option == 2 ]]
        then
		read -p $"quelle adresse IP ? :" IP
		nmap -v -O -T4 -Pn -oG OSDetect  $IP
		sleep 5
		menu
elif [[ $option == 3 ]]
        then
                menu


else
        echo "vous n'avez pas choisi une option valable"
        scan
fi
}





menu(){

echo "(1) Nmap"
echo "(2) Quitter"

read -p $"Bonjour, choisisssez une option:" option


if [[ $option == 1 || $option == 02 ]]
	then
		scan
		menu
elif [[ $option == 2 || $option == 02 ]]
	then
		exit 1

else
	echo "vous n'avez pas choisi une option valable"
	menu
fi
}

menu
