function gestionarServicio() {
    echo "MENÚ DE GESTIÓN DEL SERVICIO:"
    echo "1. Iniciar"
    echo "2. Detener"
    echo "3. Reiniciar"
    echo "4. Estado"
    read -p "Seleccione una acción para dnsmasq: " opcionGestion
    if [ $opcionGestion -eq 1 ]; then
        sudo systemctl start dnsmasq
    elif [ $opcionGestion -eq 2 ]; then
        sudo systemctl stop dnsmasq
    elif [ $opcionGestion -eq 3 ]; then
        sudo systemctl restart dnsmasq
    elif [ $opcionGestion -eq 4 ]; then
        sudo systemctl status dnsmasq
    fi
}
gestionarServicio
echo "Has elegido la opcion $opcionGestion"